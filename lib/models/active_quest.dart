import 'quest_model.dart';

/// 수락했지만 아직 완료하지 않은 퀘스트 (홈 2a 캐러셀 · 4a 이동 화면의 상태)
class ActiveQuest {
  final QuestModel quest;

  /// 지금까지 도달 인증을 마친 지점 수
  final int verifiedSpotCount;

  final DateTime startedAt;

  const ActiveQuest({
    required this.quest,
    required this.startedAt,
    this.verifiedSpotCount = 0,
  });

  /// 다음에 향해야 할 지점. 모두 인증했으면 마지막 지점을 반환한다.
  QuestSpot get currentSpot =>
      quest.visitSpots[verifiedSpotCount.clamp(0, quest.spotCount - 1)];

  bool get isFinished => verifiedSpotCount >= quest.spotCount;

  /// 0.0 ~ 1.0. 홈 캐러셀과 4a 시트의 진행바에 쓴다.
  double get progress =>
      quest.spotCount == 0 ? 0 : (verifiedSpotCount / quest.spotCount).clamp(0.0, 1.0);

  /// 와이어프레임 2a의 "2 / 3 지점 완료" 문구
  String get progressLabel => '$verifiedSpotCount / ${quest.spotCount} 지점 완료';

  /// 여러 지점짜리 퀘스트에서 현재 향하는 지점을 알려주는 문구
  String get currentSpotLabel =>
      quest.spotCount > 1 ? '지점 ${verifiedSpotCount + 1} / ${quest.spotCount} · ${currentSpot.name}' : currentSpot.name;

  ActiveQuest advanced() => copyWith(verifiedSpotCount: verifiedSpotCount + 1);

  ActiveQuest copyWith({int? verifiedSpotCount}) => ActiveQuest(
        quest: quest,
        startedAt: startedAt,
        verifiedSpotCount: verifiedSpotCount ?? this.verifiedSpotCount,
      );

  /// 퀘스트 본문은 목업 저장소에서 다시 찾아오므로 id와 진행도만 저장한다.
  Map<String, dynamic> toJson() => {
        'questId': quest.id,
        'verifiedSpotCount': verifiedSpotCount,
        'startedAt': startedAt.toIso8601String(),
      };
}
