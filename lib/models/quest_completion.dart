import '../data/badge_api.dart';
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

  /// 서버가 세어 내려준 배지 진행도. 배지는 완료 이력 전체를 봐야 셀 수 있어
  /// 서버만 알 수 있다 — 오프라인이면 null이고, 그때는 배지 칸을 비운다.
  final VerifyBadgeProgress? serverBadge;

  const QuestCompletionResult({
    required this.quest,
    required this.breakdown,
    required this.levelResult,
    this.serverBadge,
  });

  int get expAwarded => breakdown.finalExp;

  bool get leveledUp => levelResult.leveledUp;
}
