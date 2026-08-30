import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

/// 1c — 가입 방법 선택 및 법적 필수 약관 동의
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
  bool _serviceTermsAgreed = false;
  bool _locationTermsAgreed = false;
  bool _privacyPolicyAgreed = false;

  bool get _isAllAgreed =>
      _serviceTermsAgreed && _locationTermsAgreed && _privacyPolicyAgreed;

  void _toggleAll(bool? value) {
    final newValue = value ?? false;
    setState(() {
      _serviceTermsAgreed = newValue;
      _locationTermsAgreed = newValue;
      _privacyPolicyAgreed = newValue;
    });
  }

  void _showTermsModal(String title, String content) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: AppType.h2),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canProceed = _isAllAgreed && !widget.isBusy;

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
                          '약관 동의 후 가입 방법을 선택해주세요.',
                          style: AppType.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // 📋 필수 약관 동의 체크박스 영역
                        _buildTermsSection(),

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

  Widget _buildTermsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: _isAllAgreed,
                onChanged: widget.isBusy ? null : _toggleAll,
                //activeColor: AppColors.primary,
              ),
              GestureDetector(
                onTap: () => _toggleAll(!_isAllAgreed),
                child: Text(
                  '약관 전체 동의',
                  style: AppType.bodyMuted.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          _buildTermsRow(
            title: '[필수] 서비스 이용약관',
            value: _serviceTermsAgreed,
            onChanged: (val) =>
                setState(() => _serviceTermsAgreed = val ?? false),
            onTapDetail: () => _showTermsModal(
              '서비스 이용약관',
              _serviceTermsText,
            ),
          ),
          _buildTermsRow(
            title: '[필수] 위치정보 이용약관',
            value: _locationTermsAgreed,
            onChanged: (val) =>
                setState(() => _locationTermsAgreed = val ?? false),
            onTapDetail: () => _showTermsModal(
              '위치정보 이용약관',
              _locationTermsText,
            ),
          ),
          _buildTermsRow(
            title: '[필수] 개인정보 처리방침',
            value: _privacyPolicyAgreed,
            onChanged: (val) =>
                setState(() => _privacyPolicyAgreed = val ?? false),
            onTapDetail: () => _showTermsModal(
              '개인정보 처리방침',
              _privacyPolicyText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsRow({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required VoidCallback onTapDetail,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: widget.isBusy ? null : onChanged,
          //activeColor: AppColors.primary,
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Text(
              title,
              style: AppType.caption.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
        TextButton(
          onPressed: onTapDetail,
          child: Text(
            '보기',
            style: AppType.micro.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  // 📄 약관 텍스트 전문
  static const String _serviceTermsText = '''
제1조 (목적)
본 약관은 회사가 제공하는 '로컬퀘스트(Local Quest)' 서비스의 이용조건 및 절차, 이용자와 회사의 권리·의무 및 책임사항을 규정함을 목적으로 합니다.

제2조 (부정 이용 및 어뷰징 금지)
회원은 다음 각 호의 행위를 하여서는 안 되며, 위반 시 회사는 사전 통보 없이 계정 정지, 획득한 경험치(EXP) 및 보상 회수 등의 제재를 가할 수 있습니다.
1. GPS 모의 위치(Spoofing) 프로그램 또는 기기를 조작하여 허위 위치로 퀘스트를 완료하는 행위
2. 타인의 사진을 도용하거나 퀘스트 장소와 무관한 사진을 제출하는 행위
''';

  static const String _locationTermsText = '''
제1조 (목적)
본 약관은 회사가 제공하는 위치기반서비스와 관련하여 회사와 개인위치정보주체의 권리·의무 및 책임사항을 규정함을 목적으로 합니다.

제2조 (위치정보의 이용 및 보유)
1. 회사는 위치정보를 활용하여 이용자 주변의 퀘스트 스팟 제공, 위치 도착 인증, 이동 거리 계산 서비스를 제공합니다.
2. 회사는 퀘스트 방문 인증 시점에 한하여 위치 좌표를 일회성으로 이용하며, 법령에 따른 기록 외에 위치 좌표 자체를 영구 저장하지 않습니다.
''';

  static const String _privacyPolicyText = '''
1. 수집하는 개인정보 항목
- 필수 항목: 소셜 Provider(카카오/구글), Provider UID, 이메일, 닉네임, 서비스 이용 기록, 접속 로그, 기기 정보
- 선택 항목: 프로필 아바타 ID, 선호 키워드, 활동 지역, 퀘스트 인증 사진

2. 개인정보의 수집 및 이용목적
- 회원 관리: 소셜 로그인을 통한 본인 식별, 불량 회원의 부정 이용 방지
- 서비스 제공: 위치 기반 퀘스트 추천, 방문 인증, 레벨 및 경험치(EXP) 산정
''';
}