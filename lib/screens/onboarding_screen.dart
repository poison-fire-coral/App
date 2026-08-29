import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/auth_repository.dart';
import '../data/region_options.dart';
import '../data/terms.dart';
import '../models/api_exception.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';
import '../services/permission_service.dart';
import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../utils/nickname_validator.dart';
import '../widgets/app_widgets.dart';
import '../widgets/avatar_widgets.dart';
import '../widgets/terms_widgets.dart';

/// 온보딩이 어떤 목적으로 열렸는지.
enum OnboardingMode {
  /// 신규 가입 — 마지막에 `POST /auth/signup`으로 계정을 만든다.
  signup,

  /// 이미 가입한 사용자의 취향 재설정 — `PATCH /users/me`.
  editProfile,
}

/// 닉네임 중복확인 상태. `idle`이면 **아무 메시지도 띄우지 않는다**.
enum _NicknameCheck { idle, checking, available, taken, failed }

/// 1d 프로필 → 1e 키워드 → 1f 위치 권한
class OnboardingScreen extends StatefulWidget {
  final OnboardingMode mode;

  /// 신규 가입일 때 `/auth/login`이 돌려준 provider·providerUid.
  final PendingSignup? pending;

  /// 취향 재설정일 때 채워 넣을 기존 값.
  final UserModel? initialData;

  /// 가입/수정이 끝났을 때. 서버가 확정한 프로필이 올라온다.
  final ValueChanged<UserModel> onComplete;

  /// 1단계에서 뒤로 갔을 때. 가입 방법 재선택 화면으로 돌아간다.
  final VoidCallback? onBack;

  const OnboardingScreen({
    super.key,
    required this.mode,
    required this.onComplete,
    this.pending,
    this.initialData,
    this.onBack,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _minKeywords = 3;

  final PageController _pageController = PageController();
  int _currentStep = 0;

  // --- 1c 약관 동의 -------------------------------------------------------------
  /// 가입 경로에서만 받는다. 취향 재설정은 이미 동의한 사람이라 이 단계를 건너뛴다.
  bool get _needsConsent => widget.mode == OnboardingMode.signup;

  int get _stepCount => _needsConsent ? 4 : 3;

  /// `TermsDocument.key` → 동의 여부.
  final Map<String, bool> _consent = {
    for (final doc in kConsentDocuments) doc.key: false,
  };

  bool get _hasAllRequiredConsent => kConsentDocuments
      .where((doc) => doc.isRequired)
      .every((doc) => _consent[doc.key] == true);

  bool get _hasEveryConsent =>
      kConsentDocuments.every((doc) => _consent[doc.key] == true);

  // --- 1d 프로필 ---------------------------------------------------------------
  late final TextEditingController _nicknameController;
  String _selectedAvatarId = AppAssets.defaultAvatarId;
  RegionOption? _selectedRegion;
  String? _nicknameError;
  _NicknameCheck _nicknameCheck = _NicknameCheck.idle;

  /// 중복확인을 통과한 바로 그 문자열. 이후 한 글자라도 바뀌면 확인이 무효가 된다.
  String _checkedNickname = '';

  // --- 1e 키워드 ---------------------------------------------------------------
  /// 신규 가입은 **아무것도 선택되지 않은 상태**로 시작한다.
  final Set<String> _selectedKeywords = <String>{};
  String _selectedIntensity = '보통';

  // --- 1f 권한 / 제출 ----------------------------------------------------------
  bool _isSubmitting = false;

  /// 퀘스트 태그 · 지도 필터 칩 · 배지 분류축으로 그대로 재사용되는 어휘.
  static const Map<String, List<String>> _keywordCategories = {
    '먹기': ['#로컬맛집', '#전통시장', '#카페투어', '#노포·백년가게', '#야시장', '#술한잔'],
    '걷기': ['#골목산책', '#바다·해안', '#산·트레킹', '#강·호수', '#들판·논밭', '#숲길·섬'],
    '배우기': ['#역사유적', '#한옥·고택', '#박물관', '#미술관', '#근대건축', '#폐공간', '#종교건축'],
    '즐기기': ['#사진스팟', '#야경·일출일몰', '#공방·체험', '#축제·행사', '#벽화·거리예술', '#독립서점', '#소품샵'],
    '사람': ['#주민이야기', '#로컬브랜드', '#드라마촬영지', '#전설·설화'],
  };

  static const List<String> _intensities = ['가볍게', '보통', '많이 걷기'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;
    _nicknameController = TextEditingController(text: initial?.nickname ?? '');

    // 취향 재설정 경로에서만 기존 값을 되살린다. 신규 가입은 빈 상태로 시작해야 한다.
    if (widget.mode == OnboardingMode.editProfile && initial != null) {
      _selectedAvatarId = initial.avatarId;
      _selectedRegion = regionOptionForCode(initial.homeRegion);
      _selectedKeywords.addAll(initial.travelStyles.map(_withHash));
      if (initial.activityLevel.isNotEmpty) {
        _selectedIntensity = initial.activityLevel;
      }
      // 자기 닉네임은 이미 자기 것이므로 확인된 것으로 본다.
      if (initial.nickname.isNotEmpty) {
        _nicknameCheck = _NicknameCheck.available;
        _checkedNickname = initial.nickname;
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 키워드 표기 변환
  //   화면에는 '#골목산책', 서버에는 '골목산책'으로 저장한다.
  // ---------------------------------------------------------------------------
  static String _withHash(String v) => v.startsWith('#') ? v : '#$v';
  static String _withoutHash(String v) =>
      v.startsWith('#') ? v.substring(1) : v;

  // ---------------------------------------------------------------------------
  // 단계 이동
  // ---------------------------------------------------------------------------
  bool get _canLeaveProfileStep =>
      _nicknameError == null &&
      _nicknameCheck == _NicknameCheck.available &&
      _checkedNickname == _nicknameController.text.trim();

  bool get _canLeaveKeywordStep => _selectedKeywords.length >= _minKeywords;

  void _goNext() {
    if (_currentStep >= _stepCount - 1) return;
    _pageController.nextPage(
      duration: AppMotion.base,
      curve: AppMotion.emphasized,
    );
  }

  void _goBack() {
    if (_currentStep == 0) {
      // 1단계에서 뒤로 = 가입 방법 재선택
      widget.onBack?.call();
      return;
    }
    _pageController.previousPage(
      duration: AppMotion.base,
      curve: AppMotion.emphasized,
    );
  }

  // ---------------------------------------------------------------------------
  // 닉네임
  // ---------------------------------------------------------------------------
  void _onNicknameChanged(String value) {
    setState(() {
      _nicknameError = NicknameValidator.validate(value, whileTyping: true);
      // 한 글자라도 달라지면 직전 중복확인은 무효다.
      if (value.trim() != _checkedNickname) {
        _nicknameCheck = _NicknameCheck.idle;
      }
    });
  }

  Future<void> _checkNickname() async {
    final nickname = _nicknameController.text.trim();
    final formatError = NicknameValidator.validate(nickname);
    if (formatError != null) {
      setState(() {
        _nicknameError = formatError;
        _nicknameCheck = _NicknameCheck.idle;
      });
      return;
    }

    setState(() {
      _nicknameError = null;
      _nicknameCheck = _NicknameCheck.checking;
    });

    try {
      final available = await AuthRepository.isNicknameAvailable(nickname);
      if (!mounted) return;
      setState(() {
        _nicknameCheck =
            available ? _NicknameCheck.available : _NicknameCheck.taken;
        _checkedNickname = available ? nickname : '';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _nicknameCheck = _NicknameCheck.failed);
      _toast(e.displayMessage);
    }
  }

  // ---------------------------------------------------------------------------
  // 1f — 권한을 실제로 받고 계정을 만든다
  // ---------------------------------------------------------------------------
  Future<void> _requestPermissionAndFinish() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final result = await PermissionService.ensureLocationAccess();
      if (!mounted) return;

      switch (result) {
        case LocationAccess.granted:
          await _submitProfile();
          return;
        case LocationAccess.serviceDisabled:
          _showBlockingDialog(
            title: '위치 서비스가 꺼져 있어요',
            body: '기기의 위치 기능을 켜야 퀘스트를 찾을 수 있어요.',
            actionLabel: '위치 설정 열기',
            onAction: PermissionService.openLocationSettings,
          );
        case LocationAccess.deniedForever:
          _showBlockingDialog(
            title: '위치 권한이 차단돼 있어요',
            body: '앱 설정에서 위치 권한을 허용해 주세요. '
                '퀘스트 탐색과 도달 인증이 GPS로만 가능합니다.',
            actionLabel: '앱 설정 열기',
            onAction: PermissionService.openAppSettings,
          );
        case LocationAccess.denied:
          _toast('위치 권한을 허용해야 모험을 시작할 수 있어요.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitProfile() async {
    final nickname = _nicknameController.text.trim();
    final keywords = _selectedKeywords.map(_withoutHash).toList();

    try {
      final UserModel user;
      if (widget.mode == OnboardingMode.signup) {
        final pending = widget.pending;
        if (pending == null) {
          _toast('가입 정보를 잃어버렸어요. 처음부터 다시 시도해 주세요.');
          widget.onBack?.call();
          return;
        }
        // 1c에서 실제로 받은 동의를 그대로 싣는다.
        // 필수 항목이 하나라도 빠져 있으면 여기까지 올 수 없다(버튼이 잠긴다).
        final session = await AuthRepository.signup(SignupRequest(
          pending: pending,
          nickname: nickname,
          avatarId: _selectedAvatarId,
          homeRegion: _selectedRegion?.code,
          activityLevel: _selectedIntensity,
          keywords: keywords,
          termsAgreed: _hasAllRequiredConsent,
          termsVersion: kTermsVersion,
          marketingAgreed: _consent['marketing'] == true,
        ));
        user = session.user;
      } else {
        user = await AuthRepository.updateProfile(
          nickname: nickname,
          avatarId: _selectedAvatarId,
          homeRegion: _selectedRegion?.code,
          activityLevel: _selectedIntensity,
          keywords: keywords,
        );
      }

      if (!mounted) return;
      widget.onComplete(user);
    } on ApiException catch (e) {
      if (!mounted) return;

      // 중복확인과 가입 사이에 다른 사람이 채갔을 수 있다. 1단계로 되돌린다.
      if (e.isDuplicateNickname) {
        setState(() {
          _nicknameCheck = _NicknameCheck.taken;
          _checkedNickname = '';
        });
        _pageController.animateToPage(
          0,
          duration: AppMotion.base,
          curve: AppMotion.emphasized,
        );
        _toast('그 사이 다른 분이 쓰기 시작했어요. 다른 이름을 골라 주세요.');
        return;
      }
      _toast(e.displayMessage);
    }
  }

  // ---------------------------------------------------------------------------
  // 보조 UI
  // ---------------------------------------------------------------------------
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showBlockingDialog({
    required String title,
    required String body,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.panel),
        title: Text(title, style: AppType.h2),
        content: Text(body, style: AppType.bodyMuted),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onAction();
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentStep = index),
                children: [
                  if (_needsConsent) _buildConsentStep(),
                  _buildProfileStep(),
                  _buildKeywordStep(),
                  _buildPermissionStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 진행바 + 뒤로가기. **모든 단계에서** 보인다 —
  /// 1단계에서 뒤로 누르면 가입 방법을 다시 고를 수 있어야 하기 때문이다.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _isSubmitting ? null : _goBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textSecondary,
            tooltip: _currentStep == 0 ? '가입 방법 다시 고르기' : '이전 단계',
          ),
          Expanded(
            child: ProgressBar(value: (_currentStep + 1) / _stepCount),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '${_currentStep + 1} / $_stepCount',
            style: AppType.numeric.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ---- 1c 약관 동의 -------------------------------------------------------------
  //
  // 이 단계가 생기기 전까지는 화면 없이 `2026-08-implicit-v1`을 보내고 있었다.
  // 위치정보를 수집하는 서비스라 명시적 동의는 선택지가 아니다.
  Widget _buildConsentStep() {
    return _StepScaffold(
      title: '시작하기 전에',
      subtitle: '필수 항목에 동의해야 계정을 만들 수 있어요.',
      footer: PrimaryButton(
        label: '동의하고 계속하기',
        enabled: _hasAllRequiredConsent,
        onTap: _goNext,
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: TermsAgreeAllRow(
            value: _hasEveryConsent,
            onChanged: (v) => setState(() {
              for (final doc in kConsentDocuments) {
                _consent[doc.key] = v;
              }
            }),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final doc in kConsentDocuments)
          TermsConsentRow(
            doc: doc,
            value: _consent[doc.key] ?? false,
            onChanged: (v) => setState(() => _consent[doc.key] = v),
          ),
        const SizedBox(height: AppSpacing.lg),
        NoteBox(
          child: Text(
            '내 위치는 퀘스트를 찾고 도착을 확인하는 데에만 씁니다.\n'
            '이동 경로를 따로 저장하거나 공유하지 않아요.',
            style: AppType.bodyMuted,
          ),
        ),
      ],
    );
  }

  // ---- 1d 프로필 --------------------------------------------------------------
  Widget _buildProfileStep() {
    return _StepScaffold(
      title: '모험가 이름을 정해주세요',
      subtitle: '아바타와 이름은 나중에 설정에서 바꿀 수 있어요.',
      footer: PrimaryButton(
        label: '다음',
        enabled: _canLeaveProfileStep,
        onTap: _goNext,
      ),
      children: [
        // 아바타 6종
        Center(child: AppAvatar(avatarId: _selectedAvatarId, size: 96)),
        const SizedBox(height: AppSpacing.md),
        AvatarPickerRow(
          selectedId: _selectedAvatarId,
          onSelected: (id) => setState(() => _selectedAvatarId = id),
        ),
        const SizedBox(height: AppSpacing.xl),

        // 닉네임
        const SectionHeader(title: '닉네임'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildNicknameField()),
            const SizedBox(width: AppSpacing.sm),
            _buildCheckButton(),
          ],
        ),
        SizedBox(height: AppSpacing.sm, child: null),
        _buildNicknameFeedback(),
        const SizedBox(height: AppSpacing.xl),

        // 홈 지역
        const SectionHeader(title: '홈 지역', trailingText: '선택'),
        const SizedBox(height: AppSpacing.sm),
        _buildRegionDropdown(),
      ],
    );
  }

  Widget _buildNicknameField() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppSurface.sunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: _nicknameError != null
              ? AppColors.quest300
              : AppColors.hairlineStrong,
        ),
      ),
      child: TextField(
        controller: _nicknameController,
        onChanged: _onNicknameChanged,
        style: AppType.body.copyWith(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          hintText: '2~10자 · 한글, 영문, 숫자',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckButton() {
    final canCheck = NicknameValidator.canCheckDuplicate(
          _nicknameController.text,
        ) &&
        _nicknameCheck != _NicknameCheck.checking;

    return SizedBox(
      width: 92,
      child: PrimaryButton(
        label: _nicknameCheck == _NicknameCheck.checking ? '확인 중' : '중복확인',
        fontSize: 13,
        padding: const EdgeInsets.symmetric(vertical: 15),
        enabled: canCheck,
        onTap: _checkNickname,
      ),
    );
  }

  /// 중복확인을 누르기 전에는 아무 문구도 띄우지 않는다.
  Widget _buildNicknameFeedback() {
    final (String text, Color color)? feedback = switch (true) {
      _ when _nicknameError != null => (_nicknameError!, AppColors.quest500),
      _ when _nicknameCheck == _NicknameCheck.available => (
          '사용할 수 있는 이름이에요',
          AppColors.jade500
        ),
      _ when _nicknameCheck == _NicknameCheck.taken => (
          '이미 누군가 쓰고 있어요',
          AppColors.quest500
        ),
      _ when _nicknameCheck == _NicknameCheck.failed => (
          '확인하지 못했어요. 다시 눌러 주세요',
          AppColors.textTertiary
        ),
      _ => null,
    };

    return AnimatedSwitcher(
      duration: AppMotion.fast,
      child: feedback == null
          ? const SizedBox(height: 18, width: double.infinity)
          : SizedBox(
              height: 18,
              width: double.infinity,
              child: Text(
                feedback.$1,
                style: AppType.caption.copyWith(color: feedback.$2),
              ),
            ),
    );
  }

  Widget _buildRegionDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: AppSurface.sunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RegionOption>(
          value: _selectedRegion,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          dropdownColor: AppColors.surface,
          hint: Text(
            '주로 활동하는 지역',
            style: AppType.body.copyWith(color: AppColors.textDisabled),
          ),
          icon: const Icon(Icons.expand_more_rounded,
              color: AppColors.textTertiary),
          items: [
            for (final region in kRegionOptions)
              DropdownMenuItem(
                value: region,
                child: Text(region.label, style: AppType.body),
              ),
          ],
          onChanged: (region) => setState(() => _selectedRegion = region),
        ),
      ),
    );
  }

  // ---- 1e 키워드 --------------------------------------------------------------
  Widget _buildKeywordStep() {
    final count = _selectedKeywords.length;
    final remaining = _minKeywords - count;

    return _StepScaffold(
      title: '관심 키워드를 골라주세요',
      subtitle: remaining > 0
          ? '$_minKeywords개 이상 골라 주세요 · $remaining개 남음'
          : '$count개 선택됨 · 더 고르셔도 좋아요',
      footer: PrimaryButton(
        label: '다음',
        enabled: _canLeaveKeywordStep,
        onTap: _goNext,
      ),
      children: [
        for (final entry in _keywordCategories.entries) ...[
          SectionHeader(title: entry.key),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final keyword in entry.value)
                TagChip(
                  label: keyword,
                  isSelected: _selectedKeywords.contains(keyword),
                  onTap: () => setState(() {
                    if (!_selectedKeywords.remove(keyword)) {
                      _selectedKeywords.add(keyword);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        const SectionHeader(title: '활동 강도'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final level in _intensities) ...[
              TagChip(
                label: level,
                isSelected: _selectedIntensity == level,
                onTap: () => setState(() => _selectedIntensity = level),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }

  // ---- 1f 위치 권한 -----------------------------------------------------------
  Widget _buildPermissionStep() {
    return _StepScaffold(
      title: '위치 권한이 필요해요',
      subtitle: '퀘스트 탐색과 도달 인증이 GPS로만 가능합니다.',
      footer: PrimaryButton(
        label: _isSubmitting ? '준비 중…' : '권한 허용하고 시작하기',
        enabled: !_isSubmitting,
        onTap: _requestPermissionAndFinish,
      ),
      children: [
        Center(
          child: SvgPicture.asset(
            AppAssets.locationPermission,
            width: 240,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        NoteBox(
          child: Text(
            '내 위치는 퀘스트를 찾고 도착을 확인하는 데에만 씁니다.\n'
            '이동 경로를 따로 저장하거나 공유하지 않아요.',
            style: AppType.bodyMuted,
          ),
        ),
      ],
    );
  }
}

/// 세 단계가 공유하는 뼈대 — 제목 · 부제 · 스크롤 본문 · 바닥 버튼.
///
/// 버튼을 스크롤 밖에 고정해 두면 키보드가 올라와도 "다음"이 사라지지 않는다.
class _StepScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;

  const _StepScaffold({
    required this.title,
    required this.children,
    required this.footer,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: AppType.h1),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppType.bodyMuted),
                ],
                const SizedBox(height: AppSpacing.xl),
                ...children,
                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.lg,
          ),
          child: footer,
        ),
      ],
    );
  }
}
