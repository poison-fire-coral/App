import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 1b — 로그인.
///
/// 가입과 로그인은 분리돼 있다. 미가입 계정으로 로그인하면 서버가
/// `AUTH_NOT_REGISTERED`를 주고, 앱은 자동 가입 대신 온보딩으로 안내한다.
class LoginScreen extends StatelessWidget {
  /// 'KAKAO' | 'GOOGLE'
  final ValueChanged<String> onPickProvider;
  final VoidCallback onGoSignup;

  /// 개발자 모드가 켜져 있을 때만 채워진다.
  final VoidCallback? onGuest;

  final bool isBusy;

  const LoginScreen({
    super.key,
    required this.onPickProvider,
    required this.onGoSignup,
    this.onGuest,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // 화면을 채우되 내용이 넘치면 스크롤되게 한다.
            //
            // 주의: `SingleChildScrollView` 안의 Column은 최대 높이가 무한이라
            // `Spacer`(= Expanded)를 그냥 쓰면 배치에 실패해 **화면이 통째로
            // 비어 버린다.** 뷰포트 높이를 최소 높이로 주고 IntrinsicHeight로
            // 감싸야 flex 자식이 딛고 설 바닥이 생긴다.
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(flex: 2),
                        Center(
                          child: SvgPicture.asset(AppAssets.logo, width: 112),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          '로컬 퀘스트',
                          style: AppType.display.copyWith(
                            color: AppColors.quest500,
                            fontSize: 26,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '아는 길 전체가 하나의 퀘스트 맵',
                          style: AppType.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(flex: 3),
                        PrimaryButton(
                          label: '카카오로 계속하기',
                          enabled: !isBusy,
                          onTap: () => onPickProvider('KAKAO'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SecondaryButton(
                          label: 'Google로 계속하기',
                          onTap:
                              isBusy ? null : () => onPickProvider('GOOGLE'),
                        ),
                        if (onGuest != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          SecondaryButton(
                            label: '개발용 계정으로 로그인',
                            icon: Icons.bug_report_outlined,
                            onTap: isBusy ? null : onGuest,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        Center(
                          child: TextButton(
                            onPressed: isBusy ? null : onGoSignup,
                            child: Text(
                              '아직 계정이 없어요 · 회원가입',
                              style: AppType.body.copyWith(
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.ink300,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (isBusy)
              const ColoredBox(
                color: Color(0x66FFFDFB),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
