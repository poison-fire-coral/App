import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
// 이 패키지도 `AuthRepository`라는 이름을 쓴다. 우리 것과 충돌하므로 접두사를 붙인다.
import 'package:kakao_map_plugin/kakao_map_plugin.dart' as kakao_map;
import 'package:firebase_core/firebase_core.dart';

import 'data/auth_repository.dart';
import 'data/badge_repository.dart';
import 'data/quest_repository.dart';
import 'dev/dev_tools.dart'; // DEV-ONLY
import 'models/api_exception.dart';
import 'models/auth_models.dart';
import 'models/active_quest.dart';
import 'models/quest_completion.dart';
import 'models/quest_model.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/quest_active_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/exp_service.dart';
import 'services/geolocator_location_service.dart';
import 'services/token_store.dart';
import 'theme/app_colors.dart';
import 'theme/design_tokens.dart';
import 'theme/app_theme.dart';
import 'widgets/app_widgets.dart';

const String _activeQuestsPrefsKey = 'active_quests';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase 초기화
  try {
    await Firebase.initializeApp();
    debugPrint("✅ Firebase 초기화 성공!");
  } catch (e) {
    debugPrint("❌ Firebase 초기화 실패 에러: $e");
  }

  // 2. 카카오 로그인 SDK 초기화 (네이티브 앱 키)
  kakao.KakaoSdk.init(nativeAppKey: 'bddd99905a1b4d3731ed3b0f370aa8da');

  // 3. 카카오 지도 SDK 초기화 (JavaScript 키 + baseUrl 지정)
  kakao_map.AuthRepository.initialize(
    appKey: '5956eb5b7490c0ec1be4c2419c0ffdae',
    baseUrl: 'http://localhost',
  );

  // 4. 토큰과 개발자 모드 설정을 메모리로 올린다.
  await TokenStore.load();
  await DevTools.load(); // DEV-ONLY

  final prefs = await SharedPreferences.getInstance();
  final String? userJson = prefs.getString('user_profile');

  UserModel? savedUser;
  if (userJson != null) {
    try {
      savedUser = UserModel.fromRawJson(userJson);
    } catch (e) {
      debugPrint('프로필 불러오기 실패: $e');
    }
  }

  runApp(
    LocalQuestApp(
      initialUser: savedUser,
      initialActiveQuests: _loadActiveQuests(prefs),
    ),
  );
}

/// 진행 중 퀘스트 복원.
///
/// 저장본에 퀘스트 스냅샷이 통째로 들어 있으므로 서버에서 온 퀘스트도 살아남는다.
/// 스냅샷이 없는 구버전 데이터는 목업 저장소에서 찾아보고, 없으면 버린다.
List<ActiveQuest> _loadActiveQuests(SharedPreferences prefs) {
  final raw = prefs.getString(_activeQuestsPrefsKey);
  if (raw == null) return [];

  try {
    final decoded = json.decode(raw) as List<dynamic>;
    final restored = <ActiveQuest>[];
    for (final entry in decoded) {
      final map = Map<String, dynamic>.from(entry as Map);
      final legacyId = map['questId'] as String?;
      final active = ActiveQuest.fromJson(
        map,
        fallbackQuest:
            legacyId == null ? null : QuestRepository.findById(legacyId),
      );
      if (active != null) restored.add(active);
    }
    return restored;
  } catch (e) {
    debugPrint('진행 중 퀘스트 불러오기 실패: $e');
    return [];
  }
}

class LocalQuestApp extends StatefulWidget {
  /// 지난 실행에서 캐시해 둔 프로필. 서버 응답이 오기 전까지 화면을 채우는 용도다.
  final UserModel? initialUser;
  final List<ActiveQuest> initialActiveQuests;

  const LocalQuestApp({
    super.key,
    this.initialUser,
    this.initialActiveQuests = const [],
  });

  @override
  State<LocalQuestApp> createState() => _LocalQuestAppState();
}

/// 로그인 전 어느 화면에 있는지. signup을 Navigator.push로 띄우면
/// 루트 밖 화면과 스택 화면이 섞여 뒤로가기가 비결정적이 되므로 상태로 내렸다.
enum _AuthPhase { login, chooseProvider }

class _LocalQuestAppState extends State<LocalQuestApp> {
  /// 퀘스트 흐름(4a~4d)이 Navigator.push로 쌓이므로 루트 밖에서도 화면을 띄울 수 있게 키를 둔다.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _isLoggedIn = false;
  UserModel? _currentUser;
  late List<ActiveQuest> _activeQuests;

  bool _isEditingSurvey = false;
  bool _showSplash = true;
  double _splashProgress = 0.2;
  bool _isAuthBusy = false;
  AppTab _currentTab = AppTab.home;

  _AuthPhase _authPhase = _AuthPhase.login;

  /// null이 아니면 온보딩을 "신규 가입 모드"로 띄운다.
  PendingSignup? _pendingSignup;

  /// 온보딩 1단계에서 뒤로 갔을 때 돌아갈 곳.
  _AuthPhase _signupOrigin = _AuthPhase.login;

  /// 홈 추천 목록에서 퀘스트를 골라 지도로 넘어왔을 때 펼칠 시트
  String? _focusQuestId;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.initialUser;
    _activeQuests = List.of(widget.initialActiveQuests);

    // 세션이 완전히 끊기면(refresh까지 실패) 로그인 화면으로 되돌린다.
    ApiClient.onAuthExpired = _handleSessionExpired;

    _bootstrap();
  }

  @override
  void dispose() {
    ApiClient.onAuthExpired = null;
    super.dispose();
  }

  /// 스플래시가 보이는 동안 진짜 세션 복원을 한다.
  /// 예전에는 1.5초를 무조건 기다리기만 했다.
  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();

    if (TokenStore.hasSession) {
      if (mounted) setState(() => _splashProgress = 0.55);
      try {
        final user = await AuthRepository.me();
        await _persistUser(user);
        if (mounted) {
          setState(() {
            _currentUser = user;
            _isLoggedIn = true;
            _splashProgress = 0.9;
          });
        }
      } on ApiException {
        // refresh까지 실패했거나 계정이 사라졌다. 로그인부터 다시.
        await TokenStore.clear();
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _currentUser = null;
          });
        }
      }
    }

    // 복원이 너무 빨리 끝나면 로고가 깜빡이고 만다. 최소 노출 시간을 준다.
    const minimumVisible = Duration(milliseconds: 900);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minimumVisible) {
      await Future<void>.delayed(minimumVisible - elapsed);
    }

    if (mounted) {
      setState(() {
        _splashProgress = 1;
        _showSplash = false;
      });
    }
  }

  void _handleSessionExpired() {
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _currentUser = null;
      _pendingSignup = null;
      _authPhase = _AuthPhase.login;
    });
    _toast('로그인이 만료됐어요. 다시 로그인해 주세요.');
  }

  void _toast(String message) {
    final messengerContext = _navigatorKey.currentContext;
    if (messengerContext == null) return;
    ScaffoldMessenger.of(messengerContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // 로그인 · 가입
  // ---------------------------------------------------------------------------

  /// 소셜 SDK → 우리 서버 로그인 → 성공이면 홈, 미가입이면 온보딩.
  Future<void> _runLogin(SocialCredential credential) async {
    if (_isAuthBusy) return;
    setState(() => _isAuthBusy = true);

    try {
      final outcome = await AuthRepository.login(credential);
      if (!mounted) return;

      switch (outcome) {
        case LoginSuccess(:final session):
          await _persistUser(session.user);
          if (!mounted) return;
          setState(() {
            _currentUser = session.user;
            _isLoggedIn = true;
            _pendingSignup = null;
          });
        case LoginNeedsSignup(:final pending):
          setState(() {
            _signupOrigin = _authPhase;
            _pendingSignup = pending;
          });
      }
    } on ApiException catch (e) {
      if (mounted) _toast(e.displayMessage);
    } on SocialAuthException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  /// 로그인·가입 화면의 provider 버튼이 부른다.
  Future<void> _pickProvider(String provider) async {
    if (_isAuthBusy) return;
    setState(() => _isAuthBusy = true);

    SocialCredential? credential;
    try {
      credential = switch (provider) {
        'KAKAO' => await AuthService.signInWithKakao(),
        'GOOGLE' => await AuthService.signInWithGoogle(),
        _ => null,
      };
    } on SocialAuthException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }

    if (credential == null) return; // 사용자가 취소
    await _runLogin(credential);
  }

  // DEV-ONLY: 고정 uid로 로그인해 소셜 SDK를 건너뛴다.
  Future<void> _loginAsGuest() =>
      _runLogin(const SocialCredential.guest(DevTools.guestUid));

  // ---------------------------------------------------------------------------
  // 저장
  // ---------------------------------------------------------------------------
  Future<void> _persistUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', user.toRawJson());
  }

  Future<void> _persistActiveQuests(List<ActiveQuest> quests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _activeQuestsPrefsKey,
      json.encode([for (final q in quests) q.toJson()]),
    );
  }

  /// 온보딩(가입 또는 취향 재설정)이 끝났을 때. 서버가 확정한 프로필이 올라온다.
  Future<void> _saveUser(UserModel user) async {
    await _persistUser(user);
    if (!mounted) return;
    setState(() {
      _currentUser = user;
      _isLoggedIn = true;
      _isEditingSurvey = false;
      _pendingSignup = null;
    });
  }

  /// 로그아웃 — 서버 토큰 · 소셜 세션 · 로컬 캐시를 모두 비운다.
  Future<void> _logout() async {
    await AuthRepository.logout();
    await AuthService.signOutSocial();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_profile');
    await prefs.remove(_activeQuestsPrefsKey);
    await prefs.remove('is_logged_in'); // 구버전 키 정리

    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _currentUser = null;
      _isEditingSurvey = false;
      _pendingSignup = null;
      _authPhase = _AuthPhase.login;
      _activeQuests = [];
      _currentTab = AppTab.home;
    });
  }

  // ---------------------------------------------------------------------------
  // 분기 D · 퀘스트 수행 흐름 (수락 → 이동/도달 → 인증 → 보상 → 레벨업)
  // ---------------------------------------------------------------------------

  /// 지도·홈에서 퀘스트를 수락하거나, 이미 진행 중이면 이어서 하기.
  Future<void> _acceptQuest(QuestModel quest) async {
    final existingIndex =
        _activeQuests.indexWhere((a) => a.quest.id == quest.id);

    final ActiveQuest active;
    if (existingIndex >= 0) {
      active = _activeQuests[existingIndex];
    } else {
      // 서버에도 수락을 남긴다. 목업 퀘스트(id가 정수가 아님)는 서버에 없으므로 건너뛴다.
      if (int.tryParse(quest.id) != null) {
        try {
          await QuestRepository.acceptQuest(quest.id);
        } on ApiException catch (e) {
          _toast(e.displayMessage);
          return;
        }
      }
      active = ActiveQuest(quest: quest, startedAt: DateTime.now());
      final updated = [..._activeQuests, active];
      if (!mounted) return;
      setState(() => _activeQuests = updated);
      await _persistActiveQuests(updated);
    }

    _openQuestFlow(active);
  }

  void _openQuestFlow(ActiveQuest active) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => QuestActiveScreen(
          activeQuest: active,
          locationService: GeolocatorLocationService(),
          onSpotVerified: _updateActiveQuest,
          onQuestCompleted: _completeQuest,
          onAbandon: _abandonQuest,
        ),
      ),
    );
  }

  /// 여러 지점짜리 퀘스트에서 한 지점을 인증했을 때 진행도만 갱신한다.
  void _updateActiveQuest(ActiveQuest updated) {
    final next = [
      for (final a in _activeQuests) a.quest.id == updated.quest.id ? updated : a,
    ];
    setState(() => _activeQuests = next);
    _persistActiveQuests(next);
  }

  Future<void> _abandonQuest(ActiveQuest abandoned) async {
    // 서버 기록도 지운다. 실패해도 로컬에서는 빼준다 — 사용자가 포기를 눌렀으니까.
    if (int.tryParse(abandoned.quest.id) != null) {
      try {
        await QuestRepository.abandonQuest(abandoned.quest.id);
      } on ApiException catch (e) {
        debugPrint('퀘스트 포기 서버 반영 실패: ${e.code}');
      }
    }
    final next =
        _activeQuests.where((a) => a.quest.id != abandoned.quest.id).toList();
    if (!mounted) return;
    setState(() => _activeQuests = next);
    await _persistActiveQuests(next);
  }

  /// 마지막 지점까지 인증했을 때의 정산.
  ///
  /// **EXP는 서버가 진실이다.** 의뢰서 절대원칙 ①이 "EXP·난이도·배지 판정은
  /// 100% 서버 계산, 클라이언트는 결과만 표시(조작 방지)"라고 못박고 있다.
  /// [serverResult]가 있으면 그 값을 그대로 쓰고, 없을 때(목업 퀘스트·오프라인)만
  /// 로컬 [ExpService]로 계산한다.
  Future<QuestCompletionResult> _completeQuest(
    ActiveQuest completed,
    Map<String, dynamic>? serverResult,
  ) async {
    final user = _currentUser!;
    final quest = completed.quest;
    final now = DateTime.now();

    final ExpBreakdown breakdown;
    final LevelUpResult levelResult;

    if (serverResult != null) {
      // 멱등 재요청이면 모양이 다르다: {isAlreadyProcessed: true, completion: {...}}
      final payload = serverResult['isAlreadyProcessed'] == true
          ? Map<String, dynamic>.from(serverResult['completion'] as Map? ?? {})
          : serverResult;

      final isAbused = payload['isAbused'] == true;
      final rawBreakdown = payload['breakdown'] ?? payload['multipliersJson'];

      breakdown = ExpBreakdown.fromServer(
        rawBreakdown is Map
            ? Map<String, dynamic>.from(rawBreakdown)
            : {'finalExp': payload['expAwarded'] ?? 0},
        isAbused: isAbused,
      );

      final levelInfo = serverResult['levelInfo'];
      levelResult = levelInfo is Map
          ? LevelUpResult.fromServer(
              Map<String, dynamic>.from(levelInfo),
              previousLevel: user.level,
              gainedExp: breakdown.finalExp,
            )
          : LevelUpResult(
              previousLevel: user.level,
              level: user.level,
              exp: user.exp + breakdown.finalExp,
              gainedExp: breakdown.finalExp,
            );
    } else {
      // 폴백. 4a가 감지한 속도 어뷰징을 여기서 처음으로 실제 반영한다.
      breakdown = ExpService.calculate(
        ExpService.factorsFor(quest: quest, user: user, now: now),
        dailyExpEarned: user.dailyExpEarnedOn(now),
      );
      levelResult = ExpService.applyExp(
        currentLevel: user.level,
        currentExp: user.exp,
        gainedExp: breakdown.finalExp,
      );
    }

    final completedIds = [...user.completedQuestIds, quest.id];
    final visitedRegions =
        user.hasVisited(quest.regionLabel) || quest.regionLabel.isEmpty
            ? user.visitedRegions
            : [...user.visitedRegions, quest.regionLabel];

    final updatedUser = user.copyWith(
      level: levelResult.level,
      exp: levelResult.exp,
      completedQuestIds: completedIds,
      visitedRegions: visitedRegions,
      streakDays: user.streakDaysOn(now),
      dailyExpEarned: user.dailyExpEarnedOn(now) + breakdown.finalExp,
      lastExpEarnedAt: now,
    );

    // 배지는 아직 서버에 없다(S4). 완료한 퀘스트의 키워드 카운트로 로컬 적립한다.
    final completedQuests = [
      for (final id in completedIds)
        if (QuestRepository.findById(id) != null) QuestRepository.findById(id)!,
    ];
    final badge = BadgeRepository.highlightFor(
      completedQuests: completedQuests,
      justCompleted: quest,
    );

    final remaining =
        _activeQuests.where((a) => a.quest.id != quest.id).toList();

    setState(() {
      _currentUser = updatedUser;
      _activeQuests = remaining;
    });
    await _persistUser(updatedUser);
    await _persistActiveQuests(remaining);

    return QuestCompletionResult(
      quest: quest,
      breakdown: breakdown,
      levelResult: levelResult,
      badge: badge,
      badgeJustEarned: badge != null && badge.count == badge.rule.requiredCount,
    );
  }

  /// 홈 추천 목록에서 퀘스트를 고르면 지도의 해당 시트를 펼친다 (2a → 3b).
  void _focusQuestOnMap(QuestModel quest) {
    setState(() {
      _currentTab = AppTab.map;
      _focusQuestId = quest.id;
    });
  }

  // ---------------------------------------------------------------------------
  // 빌드
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '로컬 퀘스트지상주의',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    // 0. 스플래시 — 이 뒤에서 세션 복원이 돌고 있다.
    if (_showSplash) {
      return SplashScreen(progress: _splashProgress);
    }

    // 1. 미가입 계정으로 로그인했다 → 온보딩(가입 모드)
    if (_pendingSignup != null) {
      return OnboardingScreen(
        mode: OnboardingMode.signup,
        pending: _pendingSignup,
        onComplete: _saveUser,
        onBack: () => setState(() {
          _pendingSignup = null;
          _authPhase = _signupOrigin;
        }),
      );
    }

    // 2. 가입 방법 고르기
    if (!_isLoggedIn && _authPhase == _AuthPhase.chooseProvider) {
      return SignupScreen(
        isBusy: _isAuthBusy,
        onPickProvider: _pickProvider,
        onGuest: DevTools.enabled.value ? _loginAsGuest : null, // DEV-ONLY
        onBack: () => setState(() => _authPhase = _AuthPhase.login),
      );
    }

    // 3. 로그인
    if (!_isLoggedIn) {
      return LoginScreen(
        isBusy: _isAuthBusy,
        onPickProvider: _pickProvider,
        onGuest: DevTools.enabled.value ? _loginAsGuest : null, // DEV-ONLY
        onGoSignup: () =>
            setState(() => _authPhase = _AuthPhase.chooseProvider),
      );
    }

    // 4. 취향 재설정
    if (_currentUser == null || _isEditingSurvey) {
      return OnboardingScreen(
        mode: OnboardingMode.editProfile,
        initialData: _currentUser,
        onComplete: _saveUser,
        onBack: () => setState(() => _isEditingSurvey = false),
      );
    }

    final user = _currentUser!;
    final activeIds = {for (final a in _activeQuests) a.quest.id};

    // 3. 지도 탭
    if (_currentTab == AppTab.map) {
      return MapScreen(
        user: user,
        activeQuestIds: activeIds,
        focusQuestId: _focusQuestId,
        onAcceptQuest: _acceptQuest,
        onOpenHome: () => setState(() {
          _currentTab = AppTab.home;
          _focusQuestId = null;
        }),
        onOpenSettings: (mapContext) => _showDevMenu(mapContext),
      );
    }

    final completedQuests = [
      for (final id in user.completedQuestIds)
        if (QuestRepository.findById(id) != null) QuestRepository.findById(id)!,
    ];

    // 4. 홈 탭
    return HomeScreen(
      user: user,
      activeQuests: _activeQuests,
      recommendedQuests: QuestRepository.nearby(excludeIds: activeIds),
      badges: BadgeRepository.progressFor(completedQuests),
      onContinueQuest: _openQuestFlow,
      onSelectQuest: _focusQuestOnMap,
      onOpenSettings: (homeContext) => _showDevMenu(homeContext),
      onOpenMap: () => setState(() {
        _currentTab = AppTab.map;
        _focusQuestId = null;
      }),
    );
  }

  void _showDevMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.sm),
              const GrabHandle(),
              ListTile(
                leading: const Icon(Icons.tune_rounded,
                    color: AppColors.quest500),
                title: const Text('취향 재설정하기'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _isEditingSurvey = true);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.logout, color: AppColors.textSecondary),
                title: const Text('로그아웃'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _logout();
                },
              ),

              // ─── DEV-ONLY ───────────────────────────────────────────────
              const Divider(height: 1, color: AppColors.divider),
              SwitchListTile(
                secondary: const Icon(Icons.build_rounded,
                    color: AppColors.textTertiary),
                title: const Text('개발자 모드'),
                subtitle: const Text('테스트용 위치 조작 도구를 켭니다'),
                value: DevTools.enabled.value,
                activeThumbColor: AppColors.quest500,
                onChanged: (value) async {
                  await DevTools.setEnabled(value);
                  setSheetState(() {});
                  if (mounted) setState(() {});
                },
              ),
              if (DevTools.enabled.value) ...[
                ListTile(
                  leading: const Icon(Icons.my_location_rounded,
                      color: AppColors.lapis500),
                  title: Text(DevTools.isLocationOverridden
                      ? '내 위치 고정 해제'
                      : '내 위치를 수원화성으로 고정'),
                  subtitle: const Text('시드 퀘스트가 보이게 합니다'),
                  onTap: () {
                    DevTools.toggleLocationOverride();
                    setSheetState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.key_off_rounded,
                      color: AppColors.amber700),
                  title: const Text('토큰 강제 만료'),
                  subtitle: const Text('자동 갱신이 도는지 확인합니다'),
                  onTap: () {
                    TokenStore.debugCorruptAccessToken();
                    Navigator.pop(sheetContext);
                    _toast('access token을 망가뜨렸어요. 다음 요청에서 갱신이 돕니다.');
                  },
                ),
              ],
              // ─── /DEV-ONLY ──────────────────────────────────────────────
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
