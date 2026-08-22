import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/quest_repository.dart';
import '../dev/dev_quest_panel.dart'; // DEV-ONLY
import '../models/active_quest.dart';
import '../models/api_exception.dart';
import '../models/quest_completion.dart';
import '../models/quest_model.dart';
import '../services/geo.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
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
  /// [serverResult]는 서버 `verify` 응답. 목업 퀘스트이거나 오프라인이면 null이고,
  /// 그때만 로컬 EXP 계산으로 폴백한다.
  final Future<QuestCompletionResult> Function(
    ActiveQuest completed,
    Map<String, dynamic>? serverResult,
  ) onQuestCompleted;

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

  /// **첫 실측 표본**의 거리. 진행바 비율(1 - 남은거리/최초거리)의 분모다.
  ///
  /// 예전에는 목업 좌표(`QuestRepository.mockUserLocation`)로 잡았다. 실기기가
  /// 목업에서 수십 km 떨어져 있으면 분모가 그만큼 커져서 83m를 남기고도
  /// 진행바가 가득 찼다 — 실기기 테스트에서 잡았다.
  /// 첫 표본이 오기 전에는 거리를 **모르는 것이지 0이 아니다.**
  double? _initialDistance;

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
    final sample = _sample;
    _initialDistance =
        sample == null ? null : Geo.distanceMeters(sample.point, target);
    _previousSample = null;
    _previousSampleAt = null;

    _subscription = _location.track(target).listen((sample) {
      if (!mounted) return;
      _checkSpeedAbuse(sample);
      setState(() {
        _sample = sample;
        // 분모는 첫 표본에서 한 번만 정한다. 매번 갱신하면 다가갈수록
        // 분모도 같이 줄어 진행바가 영영 안 찬다.
        _initialDistance ??= Geo.distanceMeters(
          sample.point,
          _activeQuest.currentSpot.point,
        );
      });
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

  /// 첫 표본이 오기 전에는 null — "0m 남음"이 아니다.
  double? get _remainingDistance {
    final sample = _sample;
    if (sample == null) return null;
    return Geo.distanceMeters(sample.point, _activeQuest.currentSpot.point);
  }

  double get _approachProgress {
    final remaining = _remainingDistance;
    final initial = _initialDistance;
    if (remaining == null || initial == null || initial <= 0) return 0;
    // 반경 안이면 가득. 첫 표본부터 이미 안에 있어도 빈 막대는 이상하다.
    if (remaining <= _activeQuest.currentSpot.radiusMeters) return 1;
    return (1 - remaining / initial).clamp(0.0, 1.0);
  }

  bool get _isInRange {
    final remaining = _remainingDistance;
    return remaining != null &&
        remaining <= _activeQuest.currentSpot.radiusMeters;
  }

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

    // 중간 지점은 서버에 다중 지점 개념이 없으므로 로컬 진행도만 올린다.
    if (!advanced.isFinished) {
      widget.onSpotVerified(advanced);
      setState(() => _activeQuest = advanced);
      _startTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '지점 ${advanced.verifiedSpotCount}곳 인증 완료! 다음 지점으로 이동해 주세요.'),
        ),
      );
      return;
    }

    await _verifyOnServerAndSettle(advanced, sample, result);
  }

  /// 마지막 지점을 인증했다. 서버가 거리·정확도·어뷰징을 다시 재고 EXP까지 확정한다.
  ///
  /// 의뢰서 절대원칙 ②: "위치 인증은 서버가 재검증. 클라이언트가 보낸
  /// '도착했다'를 그대로 믿지 않음."
  Future<void> _verifyOnServerAndSettle(
    ActiveQuest completed,
    LocationSample sample,
    QuestVerifyResult verifyResult,
  ) async {
    setState(() => _isSettling = true);

    Map<String, dynamic>? serverResult;
    final questId = _activeQuest.quest.id;

    // 목업 퀘스트는 서버에 존재하지 않는다(백엔드 Quest.id는 Int).
    final isRemote = int.tryParse(questId) != null;

    if (isRemote) {
      // 재시도할 때 같은 값을 보내야 서버가 멱등 처리해 EXP를 두 번 주지 않는다.
      final requestId = _activeQuest.pendingRequestId ?? const Uuid().v4();
      if (_activeQuest.pendingRequestId == null) {
        final withId = _activeQuest.copyWith(pendingRequestId: requestId);
        widget.onSpotVerified(withId);
        _activeQuest = withId;
      }

      try {
        serverResult = await QuestRepository.verifyQuest(
          questId: questId,
          requestId: requestId,
          lat: sample.point.latitude,
          lng: sample.point.longitude,
          accuracyM: sample.accuracyMeters,
          photoUrl: verifyResult.photoUrl,
          photoVisibility: verifyResult.isPhotoPublic ? 'PUBLIC' : 'PRIVATE',
        );
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _isSettling = false);
        _showVerifyFailure(e);
        return;
      }
    }

    await _settleQuest(completed, serverResult);
  }

  /// 서버가 거절한 이유를 그대로 사용자 말로 옮긴다.
  void _showVerifyFailure(ApiException e) {
    final String message;
    if (e.isOutOfRange) {
      message = '아직 인증 반경 밖이에요. 조금 더 가까이 가주세요.';
    } else if (e.isAccuracyTooLow) {
      message = 'GPS 오차가 너무 커요. 하늘이 트인 곳에서 다시 시도해 주세요.';
    } else if (e.isAlreadyAccepted) {
      message = '이미 완료한 퀘스트예요.';
    } else if (e.isNetwork) {
      message = '서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.';
    } else {
      message = e.displayMessage;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _settleQuest(
    ActiveQuest completed,
    Map<String, dynamic>? serverResult,
  ) async {
    if (!_isSettling) setState(() => _isSettling = true);

    final result = await widget.onQuestCompleted(completed, serverResult);
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
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
        title: const Text('퀘스트를 포기할까요?', style: TextStyle(fontSize: 16, color: AppColors.textPrimary)),
        content: const Text(
          '지금까지 인증한 지점 기록이 사라집니다.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속하기', style: TextStyle(color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('포기', style: TextStyle(color: AppColors.quest500)),
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
      backgroundColor: AppColors.surface,
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
          gradient: AppSurface.paper,
          boxShadow: AppElevation.e1,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text('← 홈', style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
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
                  color: AppColors.quest500.withValues(alpha: 0.08),
                  border: Border.all(color: AppColors.quest500, width: 1.5),
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
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.quest500, width: 2),
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

    // 디자인 시스템 11: 목표에 닿으면 진행바가 quest → jade 로 넘어간다.
    // "곧 도착"과 "도착"을 색으로 구분해야 인증 버튼이 왜 켜졌는지 읽힌다.
    final reached = _isInRange;

    // 바텀시트는 e4 — 위로 던지는 그림자로 지도 위에 확실히 얹는다 (03 깊이).
    return AppSheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: GrabHandle()),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  reached
                      ? '도착했어요'
                      : _remainingDistance == null
                          ? '위치를 확인하는 중'
                          : '목적지까지 '
                              '${Geo.formatDistance(_remainingDistance!)}',
                  style: AppType.h1.copyWith(
                    color: reached ? AppColors.jade700 : AppColors.textPrimary,
                  ),
                ),
              ),
              TierBadge(
                stars: quest.difficulty.stars,
                hasHalfStar: quest.hasHalfStar,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${quest.title} · ${_activeQuest.currentSpotLabel}',
            style: AppType.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          ProgressBar(
            value: _approachProgress,
            accent: reached ? AppColors.jade500 : null,
          ),
          const SizedBox(height: AppSpacing.md),
          NoteBox.text(_statusMessage(spot), fontSize: 12),
          if (_speedAbuseDetected) ...[
            const SizedBox(height: AppSpacing.sm),
            NoteBox.text(
              '이동 속도가 ${Geo.abuseSpeedKmh.round()}km/h를 넘은 구간이 있어 이번 도달은 EXP가 지급되지 않습니다.',
              fontSize: 12,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: _isSettling ? '보상 정산 중…' : '도착 인증하기',
            enabled: _canVerify,
            onTap: _openVerification,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: GestureDetector(
              onTap: _confirmAbandon,
              child: Text('퀘스트 포기', style: AppType.caption),
            ),
          ),
          // DEV-ONLY
          DevQuestPanel(
            locationService: _location,
            target: spot.point,
            targetRadiusMeters: spot.radiusMeters,
            onRunFullCycle: _canVerify ? _openVerification : null,
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
    final distance = _remainingDistance;
    if (distance == null) {
      return '위치를 확인하고 있어요. 잠시만 기다려 주세요.';
    }
    return '${Geo.formatDistance(distance)} 남았어요. '
        '${spot.name}까지 이동해 주세요.';
  }
}
