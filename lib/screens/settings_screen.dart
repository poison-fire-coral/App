import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/terms.dart';
import '../dev/dev_tools.dart'; // DEV-ONLY
import '../services/permission_service.dart';
import '../services/token_store.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';
import '../widgets/terms_widgets.dart';

/// 5d · 설정
///
/// 예전에는 우상단 톱니가 개발자 메뉴 바텀시트를 띄웠다. 그걸 진짜 설정 화면으로
/// 바꾸고 개발자 모드는 이 화면 맨 아래 항목으로 내렸다.
class SettingsScreen extends StatefulWidget {
  final String appVersion;
  final VoidCallback onBack;
  final VoidCallback onEditProfile;
  final VoidCallback onEditKeywords;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.onBack,
    required this.onEditProfile,
    required this.onEditKeywords,
    required this.onLogout,
    this.appVersion = '0.1.0',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _dataSaver = false;
  bool _photoPublic = true;
  LocationAccess? _locationState;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    final granted = await PermissionService.hasPermission();
    if (!mounted) return;
    setState(() {
      _locationState =
          granted ? LocationAccess.granted : LocationAccess.denied;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
        title: const Text('로그아웃할까요?', style: AppType.h2),
        content: Text(
          '진행 중인 퀘스트는 서버에 남아 있어요. 다시 로그인하면 이어서 할 수 있어요.',
          style: AppType.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('로그아웃',
                style: TextStyle(color: AppColors.quest500)),
          ),
        ],
      ),
    );
    if (ok == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    top: AppSpacing.sm,
                  ),
                  child: IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textSecondary,
                    tooltip: '뒤로',
                  ),
                ),
                const Text('설정', style: AppType.h2),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  AppSpacing.xxl,
                ),
                children: [
                  const SectionHeader(title: '계정'),
                  const SizedBox(height: AppSpacing.sm),
                  _Row(
                    icon: Icons.person_outline_rounded,
                    title: '닉네임 · 아바타 변경',
                    onTap: widget.onEditProfile,
                  ),
                  _Row(
                    icon: Icons.tune_rounded,
                    title: '관심 키워드 다시 고르기',
                    onTap: widget.onEditKeywords,
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: '알림과 권한'),
                  const SizedBox(height: AppSpacing.sm),
                  _SwitchRow(
                    icon: Icons.notifications_none_rounded,
                    title: '주변 퀘스트 알림',
                    value: _notifications,
                    // 푸시는 아직 서버에 없다. 값만 기억해 두고 실제 발송은 S5에서.
                    subtitle: '푸시 발송은 아직 준비 중이에요',
                    onChanged: (v) => setState(() => _notifications = v),
                  ),
                  _Row(
                    icon: Icons.my_location_rounded,
                    title: '위치 권한',
                    trailing: _locationState == LocationAccess.granted
                        ? '허용됨'
                        : '필요함',
                    trailingColor: _locationState == LocationAccess.granted
                        ? AppColors.jade500
                        : AppColors.quest500,
                    onTap: () async {
                      final result =
                          await PermissionService.ensureLocationAccess();
                      if (!mounted) return;
                      if (result == LocationAccess.deniedForever) {
                        await PermissionService.openAppSettings();
                      }
                      _checkLocation();
                    },
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: '지도와 사진'),
                  const SizedBox(height: AppSpacing.sm),
                  _SwitchRow(
                    icon: Icons.data_saver_off_rounded,
                    title: '데이터 절약 모드',
                    subtitle: '지도 갱신 주기를 늘려 데이터를 아껴요',
                    value: _dataSaver,
                    onChanged: (v) => setState(() => _dataSaver = v),
                  ),
                  _SwitchRow(
                    icon: Icons.photo_camera_outlined,
                    title: '사진 기본 공개',
                    subtitle: _photoPublic
                        ? '인증 사진이 다른 모험가에게 보여요'
                        : '인증 사진은 나만 봐요',
                    value: _photoPublic,
                    onChanged: (v) => setState(() => _photoPublic = v),
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: '정보'),
                  const SizedBox(height: AppSpacing.sm),
                  // 가입 화면(1c)이 동의받는 목록과 **같은 곳**을 본다.
                  // 항목이 늘거나 문서가 서면 `data/terms.dart`만 고치면 된다.
                  for (final doc in kAllDocuments)
                    _Row(
                      icon: doc.key == 'privacy'
                          ? Icons.privacy_tip_outlined
                          : Icons.description_outlined,
                      title: doc.title,
                      trailing: doc.hasDocument ? null : '준비 중',
                      onTap: () => showTermsDocument(context, doc),
                    ),
                  _Row(
                    icon: Icons.code_rounded,
                    title: '오픈소스 라이선스',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: '로컬 퀘스트',
                      applicationVersion: widget.appVersion,
                    ),
                  ),
                  _Row(
                    icon: Icons.info_outline_rounded,
                    title: '버전',
                    trailing: widget.appVersion,
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(label: '로그아웃', onTap: _confirmLogout),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: TextButton(
                      onPressed: () => _toast('회원 탈퇴는 아직 준비 중이에요.'),
                      child: Text(
                        '회원 탈퇴',
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  ),

                  // ─── DEV-ONLY ─────────────────────────────────────────
                  // `AppConfig.devToolsEnabled`는 컴파일 상수다. 릴리스 빌드
                  // (`--dart-define=DEV_TOOLS=false`)에서는 이 블록 전체가
                  // 코드에서 사라지고, 여기서만 부르던 `DevTools`도 함께 지워진다.
                  if (AppConfig.devToolsEnabled) ...[
                    const SizedBox(height: AppSpacing.xxl),
                    const SectionHeader(title: '개발자'),
                    const SizedBox(height: AppSpacing.sm),
                    _SwitchRow(
                      icon: Icons.build_rounded,
                      title: '개발자 모드',
                      subtitle: '테스트용 위치 조작 도구를 켭니다',
                      value: DevTools.enabled.value,
                      onChanged: (v) async {
                        await DevTools.setEnabled(v);
                        if (mounted) setState(() {});
                      },
                    ),
                    if (DevTools.enabled.value) ...[
                      _Row(
                        icon: Icons.place_outlined,
                        title: DevTools.isLocationOverridden
                            ? '내 위치 고정 해제'
                            : '내 위치를 수원화성으로 고정',
                        subtitle: '시드 퀘스트가 보이게 합니다',
                        onTap: () {
                          DevTools.toggleLocationOverride();
                          setState(() {});
                        },
                      ),
                      _Row(
                        icon: Icons.key_off_rounded,
                        title: '토큰 강제 만료',
                        subtitle: '자동 갱신이 도는지 확인합니다',
                        onTap: () {
                          TokenStore.debugCorruptAccessToken();
                          _toast('access token을 망가뜨렸어요. 다음 요청에서 갱신이 돕니다.');
                        },
                      ),
                    ],
                  ],
                  // ─── /DEV-ONLY ────────────────────────────────────────
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.body),
                  if (subtitle != null)
                    Text(subtitle!, style: AppType.micro),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: AppType.caption.copyWith(
                  color: trailingColor ?? AppColors.textTertiary,
                ),
              )
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.body),
                  if (subtitle != null)
                    Text(subtitle!, style: AppType.micro),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.quest500,
            ),
          ],
        ),
      ),
    );
  }
}
