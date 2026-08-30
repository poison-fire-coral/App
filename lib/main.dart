import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
// 이 패키지도 `AuthRepository`라는 이름을 쓴다. 우리 것과 충돌하므로 접두사를 붙인다.
import 'package:kakao_map_plugin/kakao_map_plugin.dart' as kakao_map;
import 'package:firebase_core/firebase_core.dart';

import 'config/app_config.dart';
import 'data/auth_repository.dart';
import 'data/badge_api.dart';
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
import 'screens/badge_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quest_active_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/exp_service.dart';
import 'services/geolocator_location_service.dart';
import 'services/token_store.dart';
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

  // 2~3. 카카오 SDK 초기화
  AppConfig.warnIfIncomplete();

  // 💡 디버그 로그 추가로 키 로드 여부 직접 확인
  debugPrint("🔑 Kakao Native Key: '${AppConfig.kakaoNativeAppKey}'");
  debugPrint("🔑 Kakao JS Key: '${AppConfig.kakaoJavaScriptKey}'");

  if (AppConfig.kakaoNativeAppKey.isNotEmpty) {
    kakao.KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
    debugPrint("✅ KakaoSdk 초기화 완료");
  } else {
    debugPrint("❌ [경고] KakaoNativeAppKey가 비어있어 KakaoSdk.init()을 스킵했습니다.");
  }

  if (AppConfig.kakaoJavaScriptKey.isNotEmpty) {
    kakao_map.AuthRepository.initialize(
      appKey: AppConfig.kakaoJavaScriptKey,
      baseUrl: 'http://localhost',
    );
    debugPrint("✅ KakaoMap AuthRepository 초기화 완료");
  } else {
    debugPrint("❌ [경고] KakaoJavaScriptKey가 비어있어 지도 초기화를 스킵했습니다.");
  }

  // 4. 토큰과 개발자 모드 설정을 메모리로 올린다.
  await TokenStore.load();
  // DEV-ONLY — 릴리스에서는 상수가 false라 이 호출째로 트리쉐이킹된다.
  if (AppConfig.devToolsEnabled) {
    await DevTools.load();
  }

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

  /// 프로필(5c)·설정(5d)은 하단 탭이 아니라 그 위에 겹쳐 뜬다.
  /// 뒤로 가면 원래 탭으로 돌아온다.
  bool _showProfile = false;
  bool _showSettings = false;

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
  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();

    if (TokenStore.hasSession) {
      if (mounted) setState(() => _splashProgress = 0.55);
      try {
        final user = await _withCompletedQuests(await AuthRepository.me());
        await _persistUser(user);

        final remaining = _withoutCompleted(_activeQuests, user);
        if (remaining.length != _activeQuests.length) {
          await _persistActiveQuests(remaining);
        }

        if (mounted) {
          setState(() {
            _currentUser = user;
            _isLoggedIn = true;
            _activeQuests = remaining;
            _splashProgress = 0.9;
          });
        }
      } on ApiException {
        await TokenStore.clear();
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _currentUser = null;
          });
        }
      }
    }

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

  Future<void> _runLogin(SocialCredential credential) async {
    if (_isAuthBusy) return;
    setState(() => _isAuthBusy = true);

    try {
      final outcome = await AuthRepository.login(credential);
      if (!mounted) return;

      switch (outcome) {
        case LoginSuccess(:final session):
          final user = await _withCompletedQuests(session.user);
          await _persistUser(user);
          if (!mounted) return;
          setState(() {
            _currentUser = user;
            _isLoggedIn = true;
            _activeQuests = _withoutCompleted(_activeQuests, user);
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

    if (credential == null) return;
    await _runLogin(credential);
  }

  Future<void> _loginAsGuest() =>
      _runLogin(const SocialCredential.guest(DevTools.guestUid));

  VoidCallback? get _devGuestLogin =>
      AppConfig.devToolsEnabled && DevTools.enabled.value
          ? _loginAsGuest
          : null;

  // ---------------------------------------------------------------------------
  // 완료 이력
  // ---------------------------------------------------------------------------

  Future<UserModel> _withCompletedQuests(UserModel user) async {
    try {
      final rows = await QuestRepository.fetchMyQuests(status: 'completed');
      return user.copyWith(
        completedQuestIds: [
          for (final row in rows)
            if (row['questId'] != null) '${row['questId']}',
        ],
      );
    } on ApiException catch (e) {
      debugPrint('완료 퀘스트 목록 불러오기 실패: ${e.code}');
      return user;
    }
  }

  List<ActiveQuest> _withoutCompleted(
    List<ActiveQuest> quests,
    UserModel user,
  ) =>
      [
        for (final a in quests)
          if (!user.hasCompleted(a.quest.id)) a,
      ];

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
    await prefs.remove('is_logged_in');

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

  /// 회원 탈퇴 — 백엔드 계정 삭제 API 호출 및 소셜 세션/캐시 완전 정리
  Future<void> _deleteAccount() async {
    try {
      await AuthRepository.deleteAccount();
      await AuthService.signOutSocial();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_profile');
      await prefs.remove(_activeQuestsPrefsKey);
      await prefs.remove('is_logged_in');

      if (!mounted) return;
      setState(() {
        _isLoggedIn = false;
        _currentUser = null;
        _isEditingSurvey = false;
        _pendingSignup = null;
        _showSettings = false;
        _showProfile = false;
        _authPhase = _AuthPhase.login;
        _activeQuests = [];
        _currentTab = AppTab.home;
      });

      _toast('회원 탈퇴가 완료되었습니다.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast(e.displayMessage);
    } catch (e) {
      if (!mounted) return;
      _toast('회원 탈퇴 처리 중 오류가 발생했습니다.');
    }
  }

  // ---------------------------------------------------------------------------
  // 퀘스트 수행 흐름
  // ---------------------------------------------------------------------------

  Future<void> _acceptQuest(QuestModel quest) async {
    if (_currentUser?.hasCompleted(quest.id) ?? false) {
      _toast('이미 완료한 퀘스트예요. 다시 진행할 수 없어요.');
      return;
    }

    final existingIndex =
        _activeQuests.indexWhere((a) => a.quest.id == quest.id);

    final ActiveQuest active;
    if (existingIndex >= 0) {
      active = _activeQuests[existingIndex];
    } else {
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

  void _updateActiveQuest(ActiveQuest updated) {
    final next = [
      for (final a in _activeQuests) a.quest.id == updated.quest.id ? updated : a,
    ];
    setState(() => _activeQuests = next);
    _persistActiveQuests(next);
  }

  Future<void> _abandonQuest(ActiveQuest abandoned) async {
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

    final serverBadge = serverResult == null
        ? null
        : VerifyBadgeProgress.pick(
            serverResult['badgeProgress'] ??
                (serverResult['completion'] is Map
                    ? (serverResult['completion'] as Map)['badgeProgress']
                    : null),
          );

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
      serverBadge: serverBadge,
    );
  }

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
    if (_showSplash) {
      return SplashScreen(progress: _splashProgress);
    }

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

    if (!_isLoggedIn && _authPhase == _AuthPhase.chooseProvider) {
      return SignupScreen(
        isBusy: _isAuthBusy,
        onPickProvider: _pickProvider,
        onGuest: _devGuestLogin,
        onBack: () => setState(() => _authPhase = _AuthPhase.login),
      );
    }

    if (!_isLoggedIn) {
      return LoginScreen(
        isBusy: _isAuthBusy,
        onPickProvider: _pickProvider,
        onGuest: _devGuestLogin,
        onGoSignup: () =>
            setState(() => _authPhase = _AuthPhase.chooseProvider),
      );
    }

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
    final completedIds = user.completedQuestIds.toSet();

    if (_showSettings) {
      return SettingsScreen(
        onBack: () => setState(() => _showSettings = false),
        onEditProfile: () => setState(() {
          _showSettings = false;
          _isEditingSurvey = true;
        }),
        onEditKeywords: () => setState(() {
          _showSettings = false;
          _isEditingSurvey = true;
        }),
        onLogout: () {
          setState(() => _showSettings = false);
          _logout();
        },
        onDeleteAccount: () async{
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('회원 탈퇴'),
              content: const Text('정말 탈퇴하시겠습니까?\n모든 진행 기록과 데이터가 삭제됩니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _deleteAccount();
                  },
                  child: const Text(
                    '탈퇴하기',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_showProfile) {
      return ProfileScreen(
        user: user,
        onBack: () => setState(() => _showProfile = false),
        onOpenBadges: () => setState(() {
          _showProfile = false;
          _currentTab = AppTab.badges;
        }),
      );
    }

    if (_currentTab == AppTab.badges) {
      return BadgeScreen(
        user: user,
        onOpenHome: () => setState(() => _currentTab = AppTab.home),
        onOpenMap: () => setState(() {
          _currentTab = AppTab.map;
          _focusQuestId = null;
        }),
        onOpenProfile: () => setState(() => _showProfile = true),
        onOpenSettings: (_) => setState(() => _showSettings = true),
      );
    }

    if (_currentTab == AppTab.map) {
      return MapScreen(
        user: user,
        activeQuestIds: activeIds,
        completedQuestIds: completedIds,
        focusQuestId: _focusQuestId,
        onAcceptQuest: _acceptQuest,
        onOpenHome: () => setState(() {
          _currentTab = AppTab.home;
          _focusQuestId = null;
        }),
        onOpenBadges: () => setState(() => _currentTab = AppTab.badges),
        onOpenProfile: () => setState(() => _showProfile = true),
        onOpenSettings: (_) => setState(() => _showSettings = true),
      );
    }

    final completedQuests = [
      for (final id in user.completedQuestIds)
        if (QuestRepository.findById(id) != null) QuestRepository.findById(id)!,
    ];

    return HomeScreen(
      user: user,
      activeQuests: _activeQuests,
      recommendedQuests:
          QuestRepository.nearby(excludeIds: {...activeIds, ...completedIds}),
      badges: BadgeRepository.progressFor(completedQuests),
      onContinueQuest: _openQuestFlow,
      onSelectQuest: _focusQuestOnMap,
      onOpenSettings: (_) => setState(() => _showSettings = true),
      onOpenProfile: () => setState(() => _showProfile = true),
      onOpenBadges: () => setState(() => _currentTab = AppTab.badges),
      onOpenMap: () => setState(() {
        _currentTab = AppTab.map;
        _focusQuestId = null;
      }),
    );
  }
}