import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:firebase_core/firebase_core.dart'; // 1. Firebase Core 임포트 추가

import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

// 하단 내비게이션 탭 (배지 탭은 아직 화면 미구현)
enum _AppTab { home, map }

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

  runApp(LocalQuestApp(initialIsLoggedIn: isLoggedIn, initialUser: savedUser));
}

class LocalQuestApp extends StatefulWidget {
  final bool initialIsLoggedIn;
  final UserModel? initialUser;

  const LocalQuestApp({
    super.key,
    required this.initialIsLoggedIn,
    this.initialUser,
  });

  @override
  State<LocalQuestApp> createState() => _LocalQuestAppState();
}

class _LocalQuestAppState extends State<LocalQuestApp> {
  late bool _isLoggedIn;
  late UserModel? _currentUser;
  bool _isEditingSurvey = false;
  bool _showSplash = true;
  _AppTab _currentTab = _AppTab.home;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.initialIsLoggedIn;
    _currentUser = widget.initialUser;

    // 1a 스플래시 화면을 앱 실행 시 항상 노출 (추후 버전 체크·토큰 유효성 검사로 대체 예정)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', user.toRawJson());
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
      _currentTab = _AppTab.home;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '로컬 퀘스트지상주의',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Pretendard', // 프로젝트에 설정된 폰트
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9E2B1E)),
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

    // 3. 로그인 및 온보딩 완료 -> 탭 전환 (홈 · 지도)
    if (_currentTab == _AppTab.map) {
      return MapScreen(
        user: _currentUser!,
        onOpenHome: () => setState(() => _currentTab = _AppTab.home),
        onOpenSettings: (mapContext) => _showDevMenu(mapContext),
      );
    }

    return HomeScreen(
      user: _currentUser!,
      onOpenSettings: (homeContext) => _showDevMenu(homeContext),
      onOpenMap: () => setState(() => _currentTab = _AppTab.map),
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
              leading: const Icon(Icons.tune_rounded, color: Color(0xFF9E2B1E)),
              title: const Text('취향 재설정하기'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _isEditingSurvey = true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFF2A1512)),
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
