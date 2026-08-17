import '../models/quest_model.dart';

/// 배지 획득 규칙. 배지는 별도 보상이 아니라 퀘스트 키워드 카운트로 자동 적립된다 (기획서 3b·5a).
class BadgeRule {
  final String id;
  final String name;

  /// 이 키워드가 붙은 퀘스트를 셈한다. 빈 문자열이면 모든 퀘스트를 센다.
  final String keyword;

  final int requiredCount;
  final String condition;

  const BadgeRule({
    required this.id,
    required this.name,
    required this.keyword,
    required this.requiredCount,
    required this.condition,
  });

  bool matches(QuestModel quest) => keyword.isEmpty || quest.keywords.contains(keyword);
}

/// 한 배지의 현재 진행 상황 (4c 보상 화면 · 5a 배지 컬렉션에서 사용)
class BadgeProgress {
  final BadgeRule rule;
  final int count;

  const BadgeProgress({required this.rule, required this.count});

  bool get isEarned => count >= rule.requiredCount;

  double get progress => (count / rule.requiredCount).clamp(0.0, 1.0);

  /// "2 / 3 진행 중" 또는 "3 / 3 · 완료"
  String get progressLabel =>
      isEarned ? '${rule.requiredCount} / ${rule.requiredCount} · 완료' : '$count / ${rule.requiredCount} 진행 중';
}

/// 배지 규칙 목록과 진행도 계산. 분기 E(배지 컬렉션)는 아직 미구현이라
/// 4c 보상 화면이 필요한 최소 규칙만 정의해 둔다.
class BadgeRepository {
  const BadgeRepository._();

  static const List<BadgeRule> rules = [
    BadgeRule(
      id: 'first_step',
      name: '첫 발자국',
      keyword: '',
      requiredCount: 1,
      condition: '첫 퀘스트 완료 시 획득',
    ),
    BadgeRule(
      id: 'alley_explorer',
      name: '골목 탐험가',
      keyword: '#골목산책',
      requiredCount: 3,
      condition: '#골목산책 퀘스트 3개 완료 시 획득',
    ),
    BadgeRule(
      id: 'night_market_gourmet',
      name: '야시장 미식가',
      keyword: '#야시장',
      requiredCount: 3,
      condition: '#야시장 퀘스트 3개 완료 시 획득',
    ),
    BadgeRule(
      id: 'mural_collector',
      name: '벽화 수집가',
      keyword: '#벽화·거리예술',
      requiredCount: 3,
      condition: '#벽화·거리예술 퀘스트 3개 완료 시 획득',
    ),
    BadgeRule(
      id: 'photo_hunter',
      name: '사진 사냥꾼',
      keyword: '#사진스팟',
      requiredCount: 3,
      condition: '#사진스팟 퀘스트 3개 완료 시 획득',
    ),
    BadgeRule(
      id: 'market_walker',
      name: '시장 산책자',
      keyword: '#전통시장',
      requiredCount: 3,
      condition: '#전통시장 퀘스트 3개 완료 시 획득',
    ),
  ];

  /// 완료한 퀘스트 목록에서 전체 배지 진행도를 계산한다.
  static List<BadgeProgress> progressFor(List<QuestModel> completedQuests) {
    return [
      for (final rule in rules)
        BadgeProgress(
          rule: rule,
          count: completedQuests.where(rule.matches).length,
        ),
    ];
  }

  /// 방금 완료한 퀘스트로 한 칸 나아간 배지 중 대표 하나를 고른다.
  /// 이번에 완성된 배지가 있으면 그것을, 없으면 완성에 가장 가까운 배지를 반환한다.
  static BadgeProgress? highlightFor({
    required List<QuestModel> completedQuests,
    required QuestModel justCompleted,
  }) {
    final advanced = progressFor(completedQuests)
        .where((p) => p.rule.matches(justCompleted))
        .toList();
    if (advanced.isEmpty) return null;

    final justEarned = advanced.where((p) => p.count == p.rule.requiredCount).toList();
    if (justEarned.isNotEmpty) return justEarned.first;

    final inProgress = advanced.where((p) => !p.isEarned).toList();
    if (inProgress.isEmpty) return advanced.first;

    inProgress.sort((a, b) => b.progress.compareTo(a.progress));
    return inProgress.first;
  }
}
