import '../services/geo.dart';
import 'quest_model.dart';

/// 수락했지만 아직 완료하지 않은 퀘스트 (홈 2a 캐러셀 · 4a 이동 화면의 상태)
class ActiveQuest {
  final QuestModel quest;

  /// 지금까지 도달 인증을 마친 지점 수
  final int verifiedSpotCount;

  final DateTime startedAt;

  /// 현재 향하는 지점까지의 접근률 0.0~1.0.
  ///
  /// 서버에는 다중 지점 개념이 없고(`verifyQuest`가 퀘스트를 한 번에 COMPLETED로
  /// 만든다), 백엔드에서 온 퀘스트는 지점이 하나뿐이라 지점 수만으로는 진행바가
  /// 0%에서 100%로 점프해 버린다. 4a가 이미 정확히 계산하고 있는 접근률을
  /// 여기로 올려 홈 캐러셀도 같이 쓰게 한다.
  final double? approachProgress;

  /// 마지막으로 잰 남은 거리(m). 진행 문구에 쓴다.
  final double? lastRemainingMeters;

  final DateTime? lastLocationAt;

  /// 도달 인증 요청에 쓸 UUID.
  ///
  /// 타임아웃 후 재시도할 때 **같은 값**을 보내야 서버가 멱등 처리해
  /// EXP를 두 번 주지 않는다. 그래서 퀘스트별로 보관한다.
  final String? pendingRequestId;

  const ActiveQuest({
    required this.quest,
    required this.startedAt,
    this.verifiedSpotCount = 0,
    this.approachProgress,
    this.lastRemainingMeters,
    this.lastLocationAt,
    this.pendingRequestId,
  });

  /// 다음에 향해야 할 지점. 모두 인증했으면 마지막 지점을 반환한다.
  QuestSpot get currentSpot =>
      quest.visitSpots[verifiedSpotCount.clamp(0, quest.spotCount - 1)];

  bool get isFinished => verifiedSpotCount >= quest.spotCount;

  /// 0.0 ~ 1.0. 홈 캐러셀과 4a 시트의 진행바에 쓴다.
  ///
  /// 지점이 하나면 접근률이 곧 진행률이고, 여러 개면 "완료한 지점 + 현재 구간 진행"을
  /// 전체 지점 수로 나눈다. 예: 2지점 중 1개 완료 + 다음 지점 30% 접근 = 65%.
  double get progress {
    final total = quest.spotCount;
    if (total <= 0) return 0;
    final approach = (approachProgress ?? 0).clamp(0.0, 1.0);
    if (isFinished) return 1;
    if (total == 1) return approach;
    return ((verifiedSpotCount + approach) / total).clamp(0.0, 1.0);
  }

  /// 캐러셀 카드 아래 한 줄.
  String get progressLabel {
    if (quest.spotCount > 1) {
      return '$verifiedSpotCount / ${quest.spotCount} 지점 완료';
    }
    final remaining = lastRemainingMeters;
    if (remaining == null) return '수락함 · 아직 출발 전';
    if (remaining <= currentSpot.radiusMeters) return '도착 · 인증할 수 있어요';
    return '목적지까지 ${Geo.formatDistance(remaining)}';
  }

  /// 여러 지점짜리 퀘스트에서 현재 향하는 지점을 알려주는 문구
  String get currentSpotLabel => quest.spotCount > 1
      ? '지점 ${verifiedSpotCount + 1} / ${quest.spotCount} · ${currentSpot.name}'
      : currentSpot.name;

  ActiveQuest advanced() => copyWith(
        verifiedSpotCount: verifiedSpotCount + 1,
        approachProgress: 0, // 다음 지점을 향해 다시 0부터
        clearRequestId: true, // 인증이 끝났으니 멱등 키도 새로 발급한다
      );

  ActiveQuest copyWith({
    int? verifiedSpotCount,
    double? approachProgress,
    double? lastRemainingMeters,
    DateTime? lastLocationAt,
    String? pendingRequestId,
    bool clearRequestId = false,
  }) =>
      ActiveQuest(
        quest: quest,
        startedAt: startedAt,
        verifiedSpotCount: verifiedSpotCount ?? this.verifiedSpotCount,
        approachProgress: approachProgress ?? this.approachProgress,
        lastRemainingMeters: lastRemainingMeters ?? this.lastRemainingMeters,
        lastLocationAt: lastLocationAt ?? this.lastLocationAt,
        pendingRequestId:
            clearRequestId ? null : (pendingRequestId ?? this.pendingRequestId),
      );

  /// 위치 표본이 들어올 때마다 접근률을 갱신한다.
  ActiveQuest withApproach({
    required double remainingMeters,
    required double initialMeters,
  }) {
    final ratio = initialMeters <= 0
        ? 1.0
        : (1 - remainingMeters / initialMeters).clamp(0.0, 1.0);
    return copyWith(
      approachProgress: ratio,
      lastRemainingMeters: remainingMeters,
      lastLocationAt: DateTime.now(),
    );
  }

  /// 퀘스트 본문을 통째로 저장한다.
  ///
  /// 예전에는 id만 저장하고 복원할 때 목업 저장소에서 찾아왔다. 그래서 **서버에서 온
  /// 퀘스트는 앱을 다시 켜면 진행 목록에서 사라졌다.** 스냅샷을 함께 담아 해결한다.
  Map<String, dynamic> toJson() => {
        'quest': quest.toJson(),
        'questId': quest.id, // 구버전 복원 경로와의 호환
        'verifiedSpotCount': verifiedSpotCount,
        'approachProgress': approachProgress,
        'lastRemainingMeters': lastRemainingMeters,
        'lastLocationAt': lastLocationAt?.toIso8601String(),
        'pendingRequestId': pendingRequestId,
        'startedAt': startedAt.toIso8601String(),
      };

  /// [fallbackQuest]는 스냅샷이 없는 구버전 데이터를 복원할 때 쓴다.
  static ActiveQuest? fromJson(
    Map<String, dynamic> json, {
    QuestModel? fallbackQuest,
  }) {
    QuestModel? quest;
    final snapshot = json['quest'];
    if (snapshot is Map) {
      quest = QuestModel.fromJson(Map<String, dynamic>.from(snapshot));
    }
    quest ??= fallbackQuest;
    if (quest == null) return null;

    return ActiveQuest(
      quest: quest,
      verifiedSpotCount: json['verifiedSpotCount'] as int? ?? 0,
      approachProgress: (json['approachProgress'] as num?)?.toDouble(),
      lastRemainingMeters: (json['lastRemainingMeters'] as num?)?.toDouble(),
      lastLocationAt: json['lastLocationAt'] != null
          ? DateTime.tryParse('${json['lastLocationAt']}')
          : null,
      pendingRequestId: json['pendingRequestId'] as String?,
      startedAt:
          DateTime.tryParse('${json['startedAt']}') ?? DateTime.now(),
    );
  }
}
