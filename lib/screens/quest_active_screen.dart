import 'dart:async';

import 'package:flutter/material.dart';

import '../data/quest_repository.dart';
import '../models/active_quest.dart';
import '../models/quest_completion.dart';
import '../models/quest_model.dart';
import '../services/geo.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';
import 'level_up_screen.dart';
import 'quest_reward_screen.dart';
import 'quest_verify_screen.dart';

/// 4a · 이동 · 도달
///
/// 목표 지점까지 남은 거리를 보여주고, 인증 반경(기본 50m) 안에 들어와야
/// "도착 인증하기" 버튼이 활성화된다. 여러 지점짜리 퀘스트는 한 지점을 인증할 때마다
/// 다음 지점으로 목표를 옮기고, 마지막 지점까지 끝나면 4c 보상 화면으로 넘어간다.
class QuestActiveScreen extends StatefulWidget {
  final ActiveQuest activeQuest;

  /// 지점 하나를 인증했을 때. 진행도를 상위(main)에 저장한다.
  final ValueChanged<ActiveQuest> onSpotVerified;

  /// 마지막 지점까지 인증했을 때. EXP·레벨·배지 정산은 상위에서 수행하고 결과를 돌려받는다.
  final Future<QuestCompletionResult> Function(ActiveQuest completed) onQuestCompleted;

  /// 퀘스트 포기
  final ValueChanged<ActiveQuest> onAbandon;

  /// 위치 공급자. 지정하지 않으면 시뮬레이터를 쓴다.
  final LocationService? locationService;

  const QuestActiveScreen({
    super.key,
    required this.activeQuest,
    required this.onSpotVerified,
    required this.onQuestCompleted,
    required this.onAbandon,
    this.locationService,
  });

  @override
  State<QuestActiveScreen> createState() => _QuestActiveScreenState();
}

class _QuestActiveScreenState extends State<QuestActiveScreen> {
  late ActiveQuest _activeQuest;
  late LocationService _location;

  StreamSubscription<LocationSample>? _subscription;
  LocationSample? _sample;

  /// 목표 지점을 잡은 시점의 거리. 진행바 비율(1 - 남은거리/최초거리) 계산에 쓴다.
  double _initialDistance = 0;

  /// 직전 표본과 그 시각. 40km/h 초과 이동 판정에 쓴다 (기획서 6d).
  LocationSample? _previousSample;
  DateTime? _previousSampleAt;
  bool _speedAbuseDetected = false;

  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _activeQuest = widget.activeQuest;
    _location = widget.locationService ??
        SimulatedLocationService(origin: _startingPoint());
    _startTracking();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _location.dispose();
    super.dispose();
  }

  /// 시뮬레이터 출발점. 이미 지점을 인증한 퀘스트는 직전 지점에서 출발한다.
  GeoPoint _startingPoint() {
    final quest = widget.activeQuest.quest;
    final verified = widget.activeQuest.verifiedSpotCount;
    if (verified > 0 && verified <= quest.spotCount - 1) {
      return quest.visitSpots[verified - 1].point;
    }
    return QuestRepository.mockUserLocation;
  }

  void _startTracking() {
    _subscription?.cancel();

    final target = _activeQuest.currentSpot.point;
    final origin = _sample?.point ?? _startingPoint();
    _initialDistance = Geo.distanceMeters(origin, target);
    _previousSample = null;
    _previousSampleAt = null;

    _subscription = _location.track(target).listen((sample) {
      if (!mounted) return;
      _checkSpeedAbuse(sample);
      setState(() => _sample = sample);
    });
  }

  /// 40km/h를 넘는 구간으로 접근하면 어뷰징으로 표시한다.
  /// 시뮬레이터가 만든 값은 실제 GPS 측정이 아니므로 판정에서 제외한다.
  void _checkSpeedAbuse(LocationSample sample) {
    final previous = _previousSample;
    final previousAt = _previousSampleAt;
    final now = DateTime.now();

    if (previous != null &&
        previousAt != null &&
        !sample.isSimulated &&
        !previous.isSimulated &&
        Geo.isSpeedAbuse(previous.point, sample.point, now.difference(previousAt))) {
      _speedAbuseDetected = true;
    }

    _previousSample = sample;
    _previousSampleAt = now;
  }

  double get _remainingDistance {
    final sample = _sample;
    if (sample == null) return _initialDistance;
    return Geo.distanceMeters(sample.point, _activeQuest.currentSpot.point);
  }

  double get _approachProgress {
    if (_initialDistance <= 0) return 1;
    return (1 - _remainingDistance / _initialDistance).clamp(0.0, 1.0);
  }

  bool get _isInRange => _remainingDistance <= _activeQuest.currentSpot.radiusMeters;

  bool get _needsRemeasure => _sample?.needsRemeasure ?? false;

  bool get _canVerify => _isInRange && !_needsRemeasure && !_isSettling;

  // ---------------------------------------------------------------------------
  // 4b 인증 → 지점 전진 → 4c 보상
  // ---------------------------------------------------------------------------
  Future<void> _openVerification() async {
    final sample = _sample;
    if (sample == null) return;

    final result = await Navigator.of(context).push<QuestVerifyResult>(
      MaterialPageRoute(
        builder: (_) => QuestVerifyScreen(
          quest: _activeQuest.quest,
          spot: _activeQuest.currentSpot,
          accuracyMeters: sample.accuracyMeters,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final advanced = _activeQuest.advanced();

    if (!advanced.isFinished) {
      widget.onSpotVerified(advanced);
      setState(() => _activeQuest = advanced);
      _startTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지점 ${advanced.verifiedSpotCount}곳 인증 완료! 다음 지점으로 이동해 주세요.')),
      );
      return;
    }

    await _settleQuest(advanced);
  }

  Future<void> _settleQuest(ActiveQuest completed) async {
    setState(() => _isSettling = true);

    final result = await widget.onQuestCompleted(completed);
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuestRewardScreen(
          result: result,
          onConfirm: (rewardContext) {
            if (result.leveledUp) {
              Navigator.of(rewardContext).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => LevelUpScreen(result: result.levelResult),
                ),
              );
            } else {
              Navigator.of(rewardContext).popUntil((route) => route.isFirst);
            }
          },
        ),
      ),
    );
  }

  Future<void> _confirmAbandon() async {
    final shouldAbandon = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgCream,
        title: const Text('퀘스트를 포기할까요?', style: TextStyle(fontSize: 16, color: AppColors.darkBorder)),
        content: const Text(
          '지금까지 인증한 지점 기록이 사라집니다.',
          style: TextStyle(fontSize: 13, color: AppColors.noteText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속하기', style: TextStyle(color: AppColors.darkBorder)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('포기', style: TextStyle(color: AppColors.primaryRed)),
          ),
        ],
      ),
    );

    if (shouldAbandon != true || !mounted) return;
    widget.onAbandon(_activeQuest);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ---------------------------------------------------------------------------
  // 빌드
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: MapBackdrop()),
            Positioned.fill(child: _buildApproachOverlay()),
            Positioned(left: 12, top: 12, child: _buildBackButton()),
            Positioned(left: 0, right: 0, bottom: 0, child: _buildSheet()),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgCream,
          border: Border.all(color: AppColors.darkBorder, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text('← 홈', style: TextStyle(fontSize: 12, color: AppColors.darkBorder)),
      ),
    );
  }

  /// 목표 지점의 인증 반경 원과 현재 위치 점을 겹쳐 그린다.
  /// 실제 타일맵이 아니므로 남은 거리에 비례해 사용자 점이 원 쪽으로 다가오게만 표현한다.
  Widget _buildApproachOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(constraints.maxWidth * 0.5, constraints.maxHeight * 0.36);
        const circleSize = 150.0;

        // 진행률 0이면 화면 아래쪽에서 출발해 목표 원 중심으로 수렴한다.
        final start = Offset(center.dx, center.dy + 190);
        final position = Offset.lerp(start, center, _approachProgress)!;

        return Stack(
          children: [
            Positioned(
              left: center.dx - circleSize / 2,
              top: center.dy - circleSize / 2,
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryRed.withValues(alpha: 0.08),
                  border: Border.all(color: AppColors.primaryRed, width: 1.5),
                ),
              ),
            ),
            Positioned(
              left: center.dx - 10,
              top: center.dy - 20,
              child: const QuestMarker(isActive: true),
            ),
            Positioned(
              left: position.dx - 9,
              top: position.dy - 9,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCream,
                  border: Border.all(color: AppColors.primaryRed, width: 2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSheet() {
    final quest = _activeQuest.quest;
    final spot = _activeQuest.currentSpot;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCream,
        border: Border.fromBorderSide(BorderSide(color: AppColors.darkBorder, width: 1.5)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: GrabHandle()),
          Row(
            children: [
              Expanded(
                child: Text(
                  '목적지까지 ${Geo.formatDistance(_remainingDistance)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                ),
              ),
              TagChip(label: quest.starLabel, fontSize: 11),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${quest.title} · ${_activeQuest.currentSpotLabel}',
            style: const TextStyle(fontSize: 12, color: AppColors.subText),
          ),
          const SizedBox(height: 10),
          ProgressBar(value: _approachProgress),
          const SizedBox(height: 10),
          NoteBox.text(_statusMessage(spot), fontSize: 12),
          if (_speedAbuseDetected) ...[
            const SizedBox(height: 8),
            NoteBox.text(
              '이동 속도가 ${Geo.abuseSpeedKmh.round()}km/h를 넘은 구간이 있어 이번 도달은 EXP가 지급되지 않습니다.',
              fontSize: 12,
            ),
          ],
          const SizedBox(height: 10),
          PrimaryButton(
            label: _isSettling ? '보상 정산 중…' : '도착 인증하기',
            enabled: _canVerify,
            onTap: _openVerification,
          ),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _confirmAbandon,
              child: const Text(
                '퀘스트 포기',
                style: TextStyle(fontSize: 12, color: AppColors.subText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusMessage(QuestSpot spot) {
    if (_needsRemeasure) {
      return 'GPS 정확도가 ${_sample!.accuracyMeters.round()}m로 낮아요. '
          '${Geo.maxAccuracyMeters.round()}m 이내로 잡힐 때까지 잠시 기다려 주세요.';
    }
    if (_isInRange) {
      return '인증 반경 안에 있어요. 도착 인증을 진행해 주세요.';
    }
    return '반경 ${spot.radiusMeters.round()}m 진입 시 인증 버튼 활성화 (GPS)';
  }
}
