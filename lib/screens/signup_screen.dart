import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 1c — 가입 방법 선택.
///
/// 약관 체크박스는 제거했다. 실제 약관 문서가 아직 없는데 동의 UI만 두면
/// 형식만 갖춘 가짜 절차가 된다. 대신 소셜 버튼 아래에 고지 한 줄을 남기고,
/// 서버에는 `AuthRepository.termsVersion`(= `...-implicit-v1`)을 보내
/// "묵시적 동의 구간"임을 DB에 기록해 둔다.
class SignupScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                      onPressed: isBusy ? null : onBack,
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
                          '가입 방법을 고르면 이름과 취향을 물어볼게요.',
                          style: AppType.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xxxl),

                        PrimaryButton(
                          label: '카카오로 가입',
                          enabled: !isBusy,
                          onTap: () => onPickProvider('KAKAO'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SecondaryButton(
                          label: 'Google로 가입',
                          onTap: isBusy ? null : () => onPickProvider('GOOGLE'),
                        ),

                        if (onGuest != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          SecondaryButton(
                            label: '개발용 계정으로 진행',
                            icon: Icons.bug_report_outlined,
                            onTap: isBusy ? null : onGuest,
                          ),
                        ],

                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          '계속하면 서비스 이용약관 및 위치정보 이용약관에\n동의한 것으로 봅니다.',
                          style: AppType.micro
                              .copyWith(color: AppColors.textTertiary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                      ],
                    ),
                  ),
                ),
              ],
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
