/// 퀘스트 난이도 및 기본 EXP (기획서 6a 기준)
enum QuestDifficulty {
  star1(1.0, 50),
  star2(2.0, 110),
  star3(3.0, 220),
  star4(4.0, 400),
  star5(5.0, 700);

  final double stars;
  final int baseExp;

  const QuestDifficulty(this.stars, this.baseExp);

  static int getExpWithHalfStar({required QuestDifficulty base, bool hasHalfStar = false}) {
    if (!hasHalfStar) return base.baseExp;
    return (base.baseExp * 1.15).floor();
  }
}

/// 퀘스트 데이터 모델 (기획서 3b, 3c, 4a 기준)
class QuestModel {
  final String id;
  final String title;
  final String summary;
  final String description;
  final QuestDifficulty difficulty;
  final bool hasHalfStar;
  final double latitude;
  final double longitude;
  final double validRadiusMeters;
  final String spotName;
  final String regionLabel;
  final List<String> keywords;
  final double crowdMultiplier; // 피로도(혼잡도) 배율 · 기획서 6b 기준 (한산 ×1.4 ~ 혼잡 ×0.7)

  QuestModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.description,
    required this.difficulty,
    this.hasHalfStar = false,
    required this.latitude,
    required this.longitude,
    this.validRadiusMeters = 50.0,
    required this.spotName,
    this.regionLabel = '',
    required this.keywords,
    this.crowdMultiplier = 1.0,
  });

  /// 최종 보상 EXP = 반스타 보정 EXP × 피로도 배율 (기획서 6a·6b 기준)
  int get rewardExp => (QuestDifficulty.getExpWithHalfStar(base: difficulty, hasHalfStar: hasHalfStar) * crowdMultiplier).floor();
}