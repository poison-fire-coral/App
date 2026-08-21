import 'package:flutter/material.dart';

import '../data/badge_repository.dart';
import '../models/quest_completion.dart';
import '../services/exp_service.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 4c · 보상 획득
///
/// 보상은 EXP와 배지 진행도(또는 획득)뿐이다 (제휴 쿠폰 없음).
/// 레벨이 올랐으면 [onConfirm]에서 4d 레벨업 화면으로 이어진다.
///
/// 디자인 시스템 11: **보상·레벨업은 앱에서 유일하게 e5를 쓰는 화면.**
/// EXP 수치는 display 스케일 + amber, 진행바는 slow/emphasized로 채워 올린다.
class QuestRewardScreen extends StatelessWidget {
  final QuestCompletionResult result;

  /// "확인"을 눌렀을 때. 전달된 context로 다음 화면을 push하거나 홈으로 돌아간다.
  final void Function(BuildContext context) onConfirm;

  const QuestRewardScreen({
    super.key,
    required this.result,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = result.breakdown;
    final level = result.levelResult;

    return PopScope(
      // 정산이 끝난 화면이라 뒤로가기로 4a·4b로 되돌아가지 못하게 막는다.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const Spacer(),
                Text(
                  breakdown.isSpeedAbuse ? '퀘스트 기록됨' : '퀘스트 완료!',
                  style: AppType.display.copyWith(color: AppColors.quest500),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  result.quest.title,
                  textAlign: TextAlign.center,
                  style: AppType.bodyMuted,
                ),
                const SizedBox(height: AppSpacing.xl),

                _ExpCard(breakdown: breakdown),

                const SizedBox(height: AppSpacing.xl),
                _LevelStrip(level: level),

                if (result.badge != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _BadgeCard(
                    badge: result.badge!,
                    justEarned: result.badgeJustEarned,
                  ),
                ],

                if (breakdown.isSingleCapped || breakdown.isDailyCapped) ...[
                  const SizedBox(height: AppSpacing.md),
                  NoteBox.text(_capNotice(breakdown), fontSize: 12),
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

  static String _capNotice(ExpBreakdown breakdown) => breakdown.isDailyCapped
      ? '1일 획득 상한 ${ExpService.dailyCap} EXP에 걸려 '
          '${breakdown.singleCapped} EXP 중 ${breakdown.finalExp} EXP만 지급됐어요. (이월 없음)'
      : '단일 퀘스트 상한 ${ExpService.singleQuestCap} EXP가 적용됐어요.';
}

/// 화면의 초점. 앱에서 e5를 쓰는 유일한 자리다.
class _ExpCard extends StatelessWidget {
  final ExpBreakdown breakdown;
  const _ExpCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      gradient: AppSurface.rewardFill,
      shadow: AppElevation.e5,
      radius: AppRadius.panel,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          // 획득한 값은 amber. "얻는 것"이라는 신호가 즉시 읽힌다 (02 역할 색).
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: breakdown.finalExp),
            duration: AppMotion.slow,
            curve: AppMotion.emphasized,
            builder: (_, value, _) => Text(
              '+$value EXP',
              style: AppType.display.copyWith(color: AppColors.amber700),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            breakdown.summaryLine,
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(color: AppColors.amber700),
          ),
        ],
      ),
    );
  }
}

class _LevelStrip extends StatelessWidget {
  final LevelUpResult level;
  const _LevelStrip({required this.level});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 0에서 실제 진행률까지 slow/emphasized로 채워 올린다 (07 모션).
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: level.progress),
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
          builder: (_, value, _) => ProgressBar(value: value),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Lv.${level.level} · 다음 레벨까지 ${level.expToNextLevel} EXP',
          style: AppType.numeric.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final BadgeProgress badge;
  final bool justEarned;
  const _BadgeCard({required this.badge, required this.justEarned});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.jade50,
      shadow: AppElevation.e2,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppSurface.paper,
              boxShadow: AppElevation.e1,
            ),
            child: Icon(
              justEarned
                  ? Icons.workspace_premium_rounded
                  : Icons.workspace_premium_outlined,
              color: AppColors.jade500,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  justEarned ? '배지 획득! ${badge.rule.name}' : badge.rule.name,
                  style: AppType.h3.copyWith(color: AppColors.jade700),
                ),
                const SizedBox(height: AppSpacing.sm),
                ProgressBar(value: badge.progress, accent: AppColors.jade500),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  badge.progressLabel,
                  style: AppType.caption.copyWith(color: AppColors.jade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
