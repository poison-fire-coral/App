import 'package:flutter/material.dart';

import '../services/exp_service.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 4d · 레벨업
///
/// 레벨은 랭킹이 아니라 콘텐츠 해금 게이트다 (기획서 6d).
/// 보상 화면과 함께 e5를 쓰는 두 화면 중 하나 (디자인 시스템 11).
class LevelUpScreen extends StatelessWidget {
  final LevelUpResult result;

  const LevelUpScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
                  'LEVEL UP',
                  style: AppType.display.copyWith(
                    color: AppColors.quest500,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _LevelTransition(
                  from: result.previousLevel,
                  to: result.level,
                ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: 230,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: result.progress),
                    duration: AppMotion.slow,
                    curve: AppMotion.emphasized,
                    builder: (_, value, _) => ProgressBar(value: value),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '다음 레벨까지 ${result.expToNextLevel} EXP',
                  style: AppType.numeric.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (result.unlocks.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  _UnlockCard(unlocks: result.unlocks),
                ],
                const Spacer(),
                PrimaryButton(
                  label: '계속하기',
                  onTap: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 지난 레벨은 눌러 새긴 면, 새 레벨은 인장처럼 떠오른다.
/// 볼록과 오목을 짝으로 써야 층이 읽힌다 (디자인 시스템 04).
class _LevelTransition extends StatelessWidget {
  final int from;
  final int to;
  const _LevelTransition({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppSurface.sunken,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            'Lv.$from',
            style: AppType.numeric.copyWith(color: AppColors.textTertiary),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Icon(Icons.arrow_forward_rounded,
              size: 20, color: AppColors.textDisabled),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.8, end: 1),
          duration: AppMotion.slow,
          curve: AppMotion.spring,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 76,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppSurface.brandFill,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppElevation.brand,
            ),
            child: Text(
              'Lv.$to',
              style: AppType.h2.copyWith(color: AppColors.textOnDark),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnlockCard extends StatelessWidget {
  final List<String> unlocks;
  const _UnlockCard({required this.unlocks});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: AppCard(
        color: AppColors.amber50,
        shadow: AppElevation.e2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open_rounded,
                    size: 18, color: AppColors.amber700),
                const SizedBox(width: AppSpacing.sm),
                Text('해금됨',
                    style: AppType.h3.copyWith(color: AppColors.amber700)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final unlock in unlocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '· $unlock',
                  style: AppType.body.copyWith(color: AppColors.amber700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
