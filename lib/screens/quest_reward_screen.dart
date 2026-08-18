import 'package:flutter/material.dart';

import '../data/badge_repository.dart';
import '../models/quest_completion.dart';
import '../services/exp_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

/// 4c · 보상 획득
///
/// 보상은 EXP와 배지 진행도(또는 획득)뿐이다 (제휴 쿠폰 없음).
/// 레벨이 올랐으면 [onConfirm]에서 4d 레벨업 화면으로 이어진다.
class QuestRewardScreen extends StatelessWidget {
  final QuestCompletionResult result;

  /// "확인"을 눌렀을 때. 전달된 context로 다음 화면을 push하거나 홈으로 돌아간다.
  final void Function(BuildContext context) onConfirm;

  const QuestRewardScreen({super.key, required this.result, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final breakdown = result.breakdown;
    final level = result.levelResult;

    return PopScope(
      // 정산이 끝난 화면이라 뒤로가기로 4a·4b로 되돌아가지 못하게 막는다.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.navBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                const Spacer(),
                Text(
                  breakdown.isSpeedAbuse ? '퀘스트 기록됨' : '퀘스트 완료!',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryRed,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  result.quest.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.subText),
                ),
                const SizedBox(height: 16),
                _buildExpCard(breakdown),
                const SizedBox(height: 14),
                ProgressBar(value: level.progress),
                const SizedBox(height: 8),
                Text(
                  'Lv.${level.level} · 다음 레벨까지 ${level.expToNextLevel} EXP',
                  style: const TextStyle(fontSize: 13, color: AppColors.subText),
                ),
                const SizedBox(height: 16),
                if (result.badge != null) _buildBadgeCard(result.badge!),
                if (breakdown.isSingleCapped || breakdown.isDailyCapped) ...[
                  const SizedBox(height: 10),
                  _buildCapNotice(breakdown),
                ],
                const Spacer(),
                PrimaryButton(
                  label: result.leveledUp ? '레벨업 확인' : '확인',
                  onTap: () => onConfirm(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpCard(ExpBreakdown breakdown) {
    return SolidBox(
      color: AppColors.bgCream,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        children: [
          Text(
            'EXP +${breakdown.finalExp}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
          ),
          const SizedBox(height: 6),
          Text(
            breakdown.summaryLine,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.subText, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(BadgeProgress badge) {
    return SolidBox(
      color: AppColors.highlightBg,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgCream,
              border: Border.all(color: AppColors.noteBorder, width: 1.5),
            ),
            child: const Text('배지', style: TextStyle(fontSize: 10, color: AppColors.noteText)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.badgeJustEarned ? '배지 획득! ${badge.rule.name}' : badge.rule.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                ),
                const SizedBox(height: 6),
                ProgressBar(value: badge.progress),
                const SizedBox(height: 5),
                Text(
                  badge.progressLabel,
                  style: const TextStyle(fontSize: 12, color: AppColors.subText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapNotice(ExpBreakdown breakdown) {
    final reason = breakdown.isDailyCapped
        ? '1일 획득 상한 ${ExpService.dailyCap} EXP에 걸려 ${breakdown.singleCapped} EXP 중 ${breakdown.finalExp} EXP만 지급됐어요. (이월 없음)'
        : '단일 퀘스트 상한 ${ExpService.singleQuestCap} EXP가 적용됐어요.';
    return NoteBox.text(reason, fontSize: 12);
  }
}
