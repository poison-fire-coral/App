import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';

/// 1a — 스플래시.
///
/// 예전에는 1.5초를 무조건 기다렸다. 지금은 `main.dart`가 그 사이에
/// 토큰을 읽고 `GET /users/me`로 세션을 복원한다. 이 화면은 그동안 보이는 얼굴이다.
class SplashScreen extends StatelessWidget {
  /// 세션 복원 진행률(0~1). 실제 단계 수에 맞춰 올라간다.
  final double progress;

  const SplashScreen({super.key, this.progress = 0.35});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            SvgPicture.asset(AppAssets.logo, width: 132),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '로컬 퀘스트',
              style: AppType.display.copyWith(
                color: AppColors.quest500,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('아는 길 전체가 하나의 퀘스트 맵', style: AppType.bodyMuted),
            const SizedBox(height: AppSpacing.xxxl),
            SizedBox(
              width: 132,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: AppMotion.slow,
                curve: AppMotion.emphasized,
                builder: (_, value, _) => _Track(value: value),
              ),
            ),
            const Spacer(flex: 4),
            Text(
              'team 붉은사슴뿔버섯',
              style: AppType.micro.copyWith(color: AppColors.textDisabled),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _Track extends StatelessWidget {
  final double value;
  const _Track({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        gradient: AppSurface.sunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppSurface.brandFill,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
    );
  }
}
