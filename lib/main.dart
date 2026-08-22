import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
// 이 패키지도 `AuthRepository`라는 이름을 쓴다. 우리 것과 충돌하므로 접두사를 붙인다.
import 'package:kakao_map_plugin/kakao_map_plugin.dart' as kakao_map;
import 'package:firebase_core/firebase_core.dart';

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
  /// 예전에는 1.5초를 무조건 기다리기만 했다.
  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();

    if (TokenStore.hasSession) {
      if (mounted) setState(() => _splashProgress = 0.55);
      try {
        final user = await _withCompletedQuests(await AuthRepository.me());
        await _persistUser(user);

        // 다른 기기에서 끝낸 퀘스트가 "진행 중"으로 남아 있을 수 있다.
        // 그대로 두면 홈에서 "이어서 하기"로 들어갔다가 인증 단계에서야 거절당한다.
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
  // 완료 이력
  // ---------------------------------------------------------------------------

  /// 서버가 아는 완료 목록을 프로필에 채워 넣는다.
  ///
  /// 완료 판정의 진실은 서버 `quest_completions`인데, [UserModel.fromServer]는
  /// 그 필드를 싣고 오지 않는다. 채우지 않으면 앱을 다시 켤 때마다 완료 이력이
  /// 빈 채로 시작해, 이미 끝낸 퀘스트가 다시 수락 가능한 것처럼 보인다.
  /// (서버가 인증을 거절하므로 EXP가 새지는 않지만, 현장에 가서야 알게 된다)
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
      // 목록을 못 받아도 로그인 자체는 성공시킨다. 재클리어는 서버가 막는다.
      debugPrint('완료 퀘스트 목록 불러오기 실패: ${e.code}');
      return user;
    }
  }

  /// 이미 완료한 퀘스트를 진행 중 목록에서 걷어낸다.
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
  ///
  /// 한 번 완료한 퀘스트는 여기서 끝이다. 서버도 수락과 인증을 모두 거절하지만,
  /// 목업 퀘스트는 서버를 거치지 않으므로 이 검사가 유일한 관문이다.
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

    // 서버가 완료 기록을 다시 세어 내려준 배지 진행도. 멱등 재요청이면
    // payload 안쪽에 들어 있다.
    final serverBadge = serverResult == null
        ? null
        : VerifyBadgeProgress.pick(
            serverResult['badgeProgress'] ??
                (serverResult['completion'] is Map
                    ? (serverResult['completion'] as Map)['badgeProgress']
                    : null),
          );

    // 서버가 없을 때만 쓰는 폴백. 완료한 퀘스트의 키워드 카운트로 로컬 적립한다.
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
    final completedIds = user.completedQuestIds.toSet();

    // 5. 설정 (5d) — 탭 위에 겹친다
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
      );
    }

    // 6. 프로필 (5c)
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

    // 7. 배지 탭 (5a)
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

    // 3. 지도 탭
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

    // 4. 홈 탭
    return HomeScreen(
      user: user,
      activeQuests: _activeQuests,
      // 완료한 퀘스트는 추천하지 않는다. 눌러도 수락되지 않으니 자리만 차지한다.
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
