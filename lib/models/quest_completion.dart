import '../data/badge_repository.dart';
import '../services/exp_service.dart';
import 'quest_model.dart';

/// 퀘스트 하나를 완료하고 정산까지 끝낸 결과.
/// 4c 보상 화면과 4d 레벨업 화면이 이 객체 하나만 보고 그려진다.
class QuestCompletionResult {
  final QuestModel quest;

  /// EXP 배율·상한 계산 내역 (기획서 6b)
  final ExpBreakdown breakdown;

  /// 레벨·잔여 경험치 정산 결과 (기획서 6c)
  final LevelUpResult levelResult;

  /// 이번 완료로 진행된 대표 배지. 해당 배지가 없으면 null.
  final BadgeProgress? badge;

  /// 이번 완료로 배지가 막 완성되었는지 (4c에서 "배지 획득!" 연출로 대체)
  final bool badgeJustEarned;

  const QuestCompletionResult({
    required this.quest,
    required this.breakdown,
    required this.levelResult,
    this.badge,
    this.badgeJustEarned = false,
  });

  int get expAwarded => breakdown.finalExp;

  bool get leveledUp => levelResult.leveledUp;
}
