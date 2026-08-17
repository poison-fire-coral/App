import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:firebase_core/firebase_core.dart'; // 1. Firebase Core 임포트 추가

import 'data/badge_repository.dart';
import 'data/quest_repository.dart';
import 'models/active_quest.dart';
import 'models/quest_completion.dart';
import 'models/quest_model.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/quest_active_screen.dart';
import 'screens/splash_screen.dart';
import 'services/exp_service.dart';
import 'theme/app_colors.dart';
import 'widgets/app_widgets.dart';

const String _activeQuestsPrefsKey = 'active_quests';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 예외 처리
  try {
    await Firebase.initializeApp();
    debugPrint("✅ Firebase 초기화 성공!");
  } catch (e) {
    debugPrint("❌ Firebase 초기화 실패 에러: $e");
  }

  // 카카오 SDK 초기화
  kakao.KakaoSdk.init(nativeAppKey: 'bddd99905a1b4d3731ed3b0f370aa8da');

  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
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
      initialIsLoggedIn: isLoggedIn,
      initialUser: savedUser,
      initialActiveQuests: _loadActiveQuests(prefs),
    ),
  );
}

/// 진행 중 퀘스트는 id와 진행도만 저장하고, 본문은 목업 저장소에서 다시 찾아온다.
List<ActiveQuest> _loadActiveQuests(SharedPreferences prefs) {
  final raw = prefs.getString(_activeQuestsPrefsKey);
  if (raw == null) return [];

  try {
    final decoded = json.decode(raw) as List<dynamic>;
    final restored = <ActiveQuest>[];
    for (final entry in decoded) {
      final map = entry as Map<String, dynamic>;
      final quest = QuestRepository.findById(map['questId'] as String);
      if (quest == null) continue; // 목록에서 사라진 퀘스트는 버린다
      restored.add(
        ActiveQuest(
          quest: quest,
          verifiedSpotCount: map['verifiedSpotCount'] as int? ?? 0,
          startedAt: DateTime.tryParse(map['startedAt'] as String? ?? '') ?? DateTime.now(),
        ),
      );
    }
    return restored;
  } catch (e) {
    debugPrint('진행 중 퀘스트 불러오기 실패: $e');
    return [];
  }
}

class LocalQuestApp extends StatefulWidget {
  final bool initialIsLoggedIn;
  final UserModel? initialUser;
  final List<ActiveQuest> initialActiveQuests;

  const LocalQuestApp({
    super.key,
    required this.initialIsLoggedIn,
    this.initialUser,
    this.initialActiveQuests = const [],
  });

  @override
  State<LocalQuestApp> createState() => _LocalQuestAppState();
}

class _LocalQuestAppState extends State<LocalQuestApp> {
  /// 퀘스트 흐름(4a~4d)이 Navigator.push로 쌓이므로 루트 밖에서도 화면을 띄울 수 있게 키를 둔다.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late bool _isLoggedIn;
  late UserModel? _currentUser;
  late List<ActiveQuest> _activeQuests;

  bool _isEditingSurvey = false;
  bool _showSplash = true;
  AppTab _currentTab = AppTab.home;

  /// 홈 추천 목록에서 퀘스트를 골라 지도로 넘어왔을 때 펼칠 시트
  String? _focusQuestId;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.initialIsLoggedIn;
    _currentUser = widget.initialUser;
    _activeQuests = List.of(widget.initialActiveQuests);

    // 1a 스플래시 화면을 앱 실행 시 항상 노출 (추후 버전 체크·토큰 유효성 검사로 대체 예정)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

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

  // 로그인 성공 시
  Future<void> _handleLoginSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    setState(() {
      _isLoggedIn = true;
    });
  }

  // 온보딩 프로필 저장 시
  Future<void> _saveUser(UserModel user) async {
    await _persistUser(user);
    setState(() {
      _currentUser = user;
      _isEditingSurvey = false;
    });
  }

  // 로그아웃 / 전체 초기화 (테스트용)
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // 로그인 및 프로필 정보 전체 삭제
    setState(() {
      _isLoggedIn = false;
      _currentUser = null;
      _isEditingSurvey = false;
      _activeQuests = [];
      _currentTab = AppTab.home;
    });
  }

  // ---------------------------------------------------------------------------
  // 분기 D · 퀘스트 수행 흐름 (수락 → 이동/도달 → 인증 → 보상 → 레벨업)
  // ---------------------------------------------------------------------------

  /// 지도·홈에서 퀘스트를 수락하거나, 이미 진행 중이면 이어서 하기.
  void _acceptQuest(QuestModel quest) {
    final existingIndex = _activeQuests.indexWhere((a) => a.quest.id == quest.id);

    final ActiveQuest active;
    if (existingIndex >= 0) {
      active = _activeQuests[existingIndex];
    } else {
      active = ActiveQuest(quest: quest, startedAt: DateTime.now());
      final updated = [..._activeQuests, active];
      setState(() => _activeQuests = updated);
      _persistActiveQuests(updated);
    }

    _openQuestFlow(active);
  }

  void _openQuestFlow(ActiveQuest active) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => QuestActiveScreen(
          activeQuest: active,
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

  void _abandonQuest(ActiveQuest abandoned) {
    final next = _activeQuests.where((a) => a.quest.id != abandoned.quest.id).toList();
    setState(() => _activeQuests = next);
    _persistActiveQuests(next);
  }

  /// 마지막 지점까지 인증했을 때의 정산. 기획서 6b(배율·상한)와 6c(레벨업)를 적용한다.
  Future<QuestCompletionResult> _completeQuest(ActiveQuest completed) async {
    final user = _currentUser!;
    final quest = completed.quest;
    final now = DateTime.now();

    final breakdown = ExpService.calculate(
      ExpService.factorsFor(quest: quest, user: user, now: now),
      dailyExpEarned: user.dailyExpEarnedOn(now),
    );

    final levelResult = ExpService.applyExp(
      currentLevel: user.level,
      currentExp: user.exp,
      gainedExp: breakdown.finalExp,
    );

    final completedIds = [...user.completedQuestIds, quest.id];
    final visitedRegions = user.hasVisited(quest.regionLabel) || quest.regionLabel.isEmpty
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

    // 배지는 별도 보상이 아니라 완료한 퀘스트의 키워드 카운트로 적립된다.
    final completedQuests = [
      for (final id in completedIds)
        if (QuestRepository.findById(id) != null) QuestRepository.findById(id)!,
    ];
    final badge = BadgeRepository.highlightFor(
      completedQuests: completedQuests,
      justCompleted: quest,
    );

    final remaining = _activeQuests.where((a) => a.quest.id != quest.id).toList();

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
      theme: ThemeData(
        fontFamily: 'Pretendard', // 프로젝트에 설정된 폰트
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryRed),
        useMaterial3: true,
      ),
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    // 0. 스플래시 화면 (앱 실행 시 항상 우선 표시)
    if (_showSplash) {
      return const SplashScreen();
    }

    // 1. 로그인 전 -> 로그인 화면
    if (!_isLoggedIn) {
      return LoginScreen(onLoginSuccess: _handleLoginSuccess);
    }

    // 2. 로그인 완료 + 온보딩 미완료(또는 재설정 모드) -> 온보딩 화면
    if (_currentUser == null || _isEditingSurvey) {
      return OnboardingScreen(
        initialData: _currentUser,
        onComplete: (user) => _saveUser(user),
      );
    }

    final user = _currentUser!;
    final activeIds = {for (final a in _activeQuests) a.quest.id};

    // 3. 로그인 및 온보딩 완료 -> 탭 전환 (홈 · 지도)
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

  // 5d 설정 화면이 아직 없어 재설정·로그아웃 테스트용으로 임시 제공하는 메뉴
  void _showDevMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded, color: AppColors.primaryRed),
              title: const Text('취향 재설정하기'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _isEditingSurvey = true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.darkBorder),
              title: const Text('로그아웃 및 데이터 초기화'),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
