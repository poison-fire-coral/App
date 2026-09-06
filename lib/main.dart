import 'dart:async' show runZonedGuarded, unawaited;
import 'dart:ui' show PlatformDispatcher;
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
// 이 패키지도 `AuthRepository`라는 이름을 쓴다. 우리 것과 충돌하므로 접두사를 붙인다.
import 'package:kakao_map_plugin/kakao_map_plugin.dart' as kakao_map;
import 'package:firebase_core/firebase_core.dart';

import 'config/app_config.dart';
import 'data/auth_repository.dart';
import 'data/badge_api.dart';
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
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/exp_service.dart';
import 'services/geolocator_location_service.dart';
import 'services/token_store.dart';
import 'services/push_service.dart';
import 'services/verify_queue.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/app_widgets.dart';

const String _activeQuestsPrefsKey = 'active_quests';

void main() {
  // **모든 것을 한 존 안에서 돌린다.**
  //
  // 지금까지 잡히지 않는 예외를 받는 곳이 한 군데도 없었다. 릴리스에서 빌드
  // 도중 예외가 나면 회색 오류 상자가 그대로 보였고, 비동기 콜백에서 터진
  // 것은 어디에도 남지 않고 사라졌다. 사용자는 "눌렀는데 아무 일도 안 남"만 겪는다.
  //
  // `runZonedGuarded`는 async 경로를, `FlutterError.onError`는 위젯 트리를,
  // `PlatformDispatcher.onError`는 그 둘이 놓친 것을 받는다. 셋 다 필요하다.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _reportCrash(details.exception, details.stack, context: 'flutter');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _reportCrash(error, stack, context: 'platform');
      return true;
    };

    // 릴리스에서 회색·붉은 오류 상자를 사용자에게 보여 주지 않는다.
    // 디버그에서는 그대로 둔다 — 개발 중에는 그 상자가 가장 빠른 신호다.
    if (!kDebugMode) {
      ErrorWidget.builder = (details) => const _FriendlyErrorBox();
    }

    await _startApp();
  }, (error, stack) {
    _reportCrash(error, stack, context: 'zone');
  });
}

/// 잡히지 않은 예외가 도착하는 한 곳.
///
/// 지금은 로그로 남기는 것이 전부다. 크래시 리포팅 SDK를 붙이면 여기 한 줄만
/// 늘리면 된다 — 호출부가 세 군데로 흩어져 있지 않도록 모아 둔 이유다.
void _reportCrash(Object error, StackTrace? stack, {required String context}) {
  debugPrint('[$context] 처리되지 않은 오류: $error');
  if (stack != null) debugPrint(stack.toString());
}

/// 오류 위젯 자리에 들어가는 조용한 대체 화면.
///
/// 무엇이 잘못됐는지 사용자가 할 수 있는 일이 없으므로 원인을 적지 않는다.
/// 화면 하나가 못 그려진 것이지 앱이 죽은 것은 아니라는 것만 알린다.
class _FriendlyErrorBox extends StatelessWidget {
  const _FriendlyErrorBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: const Text(
        '이 화면을 그리지 못했어요. 뒤로 갔다 다시 열어 주세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}

/// 앱을 실제로 띄운다. 이름이 State의 `_bootstrap`(세션 복원)과 겹치지 않게
/// 따로 둔다 — 둘 다 '시작'이지만 하나는 프로세스, 하나는 세션이다.
Future<void> _startApp() async {
  // 1. Firebase 초기화
  try {
    await Firebase.initializeApp();
    debugPrint("✅ Firebase 초기화 성공!");
    // 메시지가 도착할 자리를 만들어 둔다. 권한·토큰은 사용자가 스위치를
    // 켤 때 처리한다.
    await PushService.initialize();
  } catch (e) {
    debugPrint("❌ Firebase 초기화 실패 에러: $e");
  }

  // 2~3. 카카오 SDK 초기화
  AppConfig.warnIfIncomplete();

  // 키가 실렸는지만 본다. **값 자체를 찍지 않는다** — debugPrint는 릴리스에서도
  // 살아 있어서 logcat에 그대로 남고, 그건 03번에서 키를 소스 밖으로 뺀 이유를
  // 통째로 무효로 만든다. 값이 필요하면 `kDebugMode`로 감싼 자리에서 본다.
  if (kDebugMode) {
    debugPrint("🔑 Kakao Native Key: '${AppConfig.kakaoNativeAppKey}'");
    debugPrint("🔑 Kakao JS Key: '${AppConfig.kakaoJavaScriptKey}'");
  }

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

  // 4. 토큰과 설정을 메모리로 올린다. 지도 카메라가 멈출 때마다 디스크를
  //    읽을 수는 없어서, 설정은 여기서 한 번 읽어 둔다.
  await TokenStore.load();
  await AppSettings.load();
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
      final active = ActiveQuest.fromJson(map);
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

  /// 시작할 때 서버에 닿지 못해 저장된 프로필로 들어왔는지.
  ///
  /// 화면 위에 한 줄로 알린다 — 지도가 비어 있고 추천이 없는 이유를 모르면
  /// 앱이 고장 난 줄 안다.
  bool _sessionOffline = false;
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
        // 체크리스트 29번 — 오프라인에서 쌓인 도달 인증을 먼저 털어 낸다.
        //
        // **me() 앞에 둔다.** 순서가 반대면 방금 보낸 인증이 반영되기 전의
        // EXP·레벨을 받아 놓고, 서버에는 반영된 상태가 되어 다음 실행까지
        // 어긋난 채로 보인다. 큐가 비어 있으면 아무 일도 하지 않고 즉시 끝난다.
        //
        // 실패해도 무시한다 — 큐가 알아서 다음 기회에 다시 본다.
        try {
          await VerifyQueue.flush();
        } catch (e) {
          debugPrint('대기 인증 전송 실패(무시하고 계속): $e');
        }

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

        // 체크리스트 24번 — FCM 토큰은 앱을 지웠다 깔거나 데이터를 지우면
        // 바뀐다. 켜 둔 사람만, 세션이 살아 있을 때마다 다시 등록한다.
        // await 하지 않는다 — 알림 등록 때문에 스플래시가 길어질 이유가 없다.
        unawaited(PushService.registerIfEnabled());
      } on ApiException catch (e) {
        // **네트워크 실패와 세션 만료를 구분한다.**
        //
        // 예전에는 둘 다 토큰을 지우고 로그인 화면으로 보냈다. 그래서 지하철에서
        // 앱을 켜기만 해도 로그아웃됐다 — 다시 소셜 로그인을 해야 하고,
        // 저장해 둔 대기 인증까지 남의 계정 것이 될까 봐 지워진다.
        //
        // 연결이 안 된 것은 세션에 대해 아무것도 말해 주지 않는다. 토큰을
        // 그대로 두고, 저장돼 있던 프로필로 계속 쓰게 한다. 서버가 실제로
        // 거절했을 때(만료·탈퇴)만 지운다.
        if (e.isNetwork) {
          debugPrint('세션 확인을 건너뛴다(연결 없음): $e');
          final cached = widget.initialUser;
          if (mounted && cached != null) {
            setState(() {
              _currentUser = cached;
              _isLoggedIn = true;
              _sessionOffline = true;
            });
          }
        } else {
          await TokenStore.clear();
          if (mounted) {
            setState(() {
              _isLoggedIn = false;
              _currentUser = null;
            });
          }
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

    // 방금 로그인한 계정으로 이 기기를 붙인다(24번). 같은 폰을 다른 사람이
    // 쓰던 경우 서버의 upsert 가 소유자를 여기로 옮긴다.
    unawaited(PushService.registerIfEnabled());
  }

  /// 로그아웃 — 서버 토큰 · 소셜 세션 · 로컬 캐시를 모두 비운다.
  Future<void> _logout() async {
    // 토큰이 아직 살아 있을 때 먼저 뺀다 — 로그아웃 뒤에는 이 호출이
    // 401로 튕겨서 이 기기가 계정에 붙은 채로 남는다(24번).
    await PushService.unregisterOnLogout();

    await AuthRepository.logout();
    await AuthService.signOutSocial();
    // 남은 대기 인증은 이 계정의 것이다. 다음 사람이 로그인했을 때
    // 앞사람의 인증이 그 계정으로 나가면 안 된다(29번).
    await VerifyQueue.clear();
    // 다음 사람이 앞사람의 설정을 물려받으면 안 된다.
    await AppSettings.clear();
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

  /// 회원 탈퇴 — 백엔드 계정 삭제 API 호출 및 소셜 세션/캐시 완전 정리.
  ///
  /// **실패를 삼키지 않는다.** 확인 다이얼로그와 진행 표시는 설정 화면이 들고
  /// 있으므로, 여기서 잡아 토스트만 띄우면 그쪽은 성공한 줄 알고 스피너를 내린다.
  /// 던져 올려서 부른 쪽이 판단하게 한다.
  Future<void> _deleteAccount() async {
    // 계정이 사라지면 UserDevice 도 Cascade 로 함께 지워지지만, 이 기기가
    // 들고 있는 등록 상태까지 지우려면 여기서 한 번 정리해야 한다.
    await PushService.unregisterOnLogout();

    await AuthRepository.deleteAccount();
    await AuthService.signOutSocial();
    await VerifyQueue.clear();
    await AppSettings.clear();

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
      home: _buildOfflineAware(_buildCurrentScreen()),
    );
  }

  /// 서버에 닿지 못한 채 저장된 프로필로 들어왔을 때 그 사실을 한 줄로 알린다.
  ///
  /// 지도가 비어 있고 추천이 없는 이유를 모르면 앱이 고장 난 줄 안다.
  /// 스플래시 위에는 띄우지 않는다 — 아직 판단이 끝나지 않은 상태다.
  Widget _buildOfflineAware(Widget child) {
    if (!_sessionOffline || _showSplash) return child;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Material(
            color: AppColors.amber100,
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: _retrySession,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 15, color: AppColors.amber700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '서버에 연결하지 못했어요. 저장된 정보로 보고 있어요.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.amber700),
                        ),
                      ),
                      Text(
                        '다시 시도',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.amber700,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.amber700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// 배너의 '다시 시도'. 세션 확인을 처음부터 다시 돌린다.
  Future<void> _retrySession() async {
    if (!mounted) return;
    setState(() => _sessionOffline = false);
    await _bootstrap();
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

    // 홈의 추천과 배지는 HomeScreen이 서버에서 직접 받아 온다(체크리스트 20·21번).
    // 여기서 로컬 목록을 넘겨 주던 자리다 — 그게 서버 실패 시의 가짜 퀘스트 출처였다.
    return HomeScreen(
      user: user,
      activeQuests: _activeQuests,
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