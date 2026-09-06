import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 1c — 가입 방법 선택 및 법적 필수 약관 동의
/// 1b · 가입 방법 선택.
///
/// **약관 동의는 여기서 받지 않는다.** 예전에는 이 화면이 자체 체크박스와
/// 자체 약관 문구(조항 2개짜리 축약본)를 들고 있었는데, 그 동의는 어디에도
/// 기록되지 않았고 바로 다음 온보딩 1c 가 같은 것을 또 물었다. 게다가 로그인
/// 화면에서 바로 카카오를 누른 사람은 이 화면을 지나지도 않는다.
///
/// 동의는 실제로 서버에 기록되는 온보딩 1c 한 곳에서만 받는다.
class SignupScreen extends StatefulWidget {
  /// 소셜 SDK 로그인을 실제로 수행하고 결과를 위로 올린다.
  final ValueChanged<String> onPickProvider;

  /// 개발용 GUEST 계정으로 바로 진행. 개발자 모드가 켜져 있을 때만 채워진다.
  final VoidCallback? onGuest;

  final VoidCallback onBack;
  final bool isBusy;

  const SignupScreen({
    super.key,
    required this.onPickProvider,
    required this.onBack,
    this.onGuest,
    this.isBusy = false,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {

  @override
  Widget build(BuildContext context) {
    final bool canProceed = !widget.isBusy;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    top: AppSpacing.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: widget.isBusy ? null : widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.textSecondary,
                      tooltip: '로그인으로',
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.gutter,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        Center(
                          child: SvgPicture.asset(AppAssets.logo, width: 84),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text('모험을 시작할까요?',
                            style: AppType.h1, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '가입 방법을 선택해주세요.',
                          style: AppType.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        PrimaryButton(
                          label: '카카오로 가입',
                          enabled: canProceed,
                          onTap: () => widget.onPickProvider('KAKAO'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SecondaryButton(
                          label: 'Google로 가입',
                          onTap: canProceed
                              ? () => widget.onPickProvider('GOOGLE')
                              : null,
                        ),

                        if (widget.onGuest != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          SecondaryButton(
                            label: '개발용 계정으로 진행',
                            icon: Icons.bug_report_outlined,
                            onTap: canProceed ? widget.onGuest : null,
                          ),
                        ],

                        const SizedBox(height: AppSpacing.xxxl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (widget.isBusy)
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
