import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 1. 카카오 SDK 임포트 추가
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import 'models/user_model.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 카카오 SDK 초기화 추가
  // Kakao Developers 콘솔에서 발급받은 '네이티브 앱 키'를 입력해 주세요.
  kakao.KakaoSdk.init(nativeAppKey: 'bddd99905a1b4d3731ed3b0f370aa8da');
  //debugPrint("🔑 내 앱의 카카오 키 해시: ${await kakao.KakaoSdk.origin}");

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

  runApp(LocalQuestApp(
    initialIsLoggedIn: isLoggedIn,
    initialUser: savedUser,
  ));
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

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.initialIsLoggedIn;
    _currentUser = widget.initialUser;
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
    // 1. 로그인 전 -> 로그인 화면
    if (!_isLoggedIn) {
      return LoginScreen(
        onLoginSuccess: _handleLoginSuccess,
      );
    }

    // 2. 로그인 완료 + 온보딩 미완료(또는 재설정 모드) -> 온보딩 화면
    if (_currentUser == null || _isEditingSurvey) {
      return OnboardingScreen(
        initialData: _currentUser,
        onComplete: (user) => _saveUser(user),
      );
    }

    // 3. 로그인 및 온보딩 완료 -> 메인 홈 화면
    return MainHomeScreen(
      user: _currentUser!,
      onReSurvey: () {
        setState(() {
          _isEditingSurvey = true;
        });
      },
      onLogout: _logout,
    );
  }
}

// -----------------------------------------------------------------------------
// 메인 홈 화면 (임시)
// -----------------------------------------------------------------------------
class MainHomeScreen extends StatelessWidget {
  final UserModel user;
  final VoidCallback onReSurvey;
  final VoidCallback onLogout;

  const MainHomeScreen({
    super.key,
    required this.user,
    required this.onReSurvey,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFDFB),
      appBar: AppBar(
        title: const Text('로컬 퀘스트지상주의', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF9E2B1E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2A1512), width: 1.5),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xFF9E2B1E).withAlpha(30),
                      child: Text(
                        'Lv.${user.level}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9E2B1E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${user.nickname} 모험가님',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1512)),
                    ),
                    const SizedBox(height: 4),
                    Text('경험치: ${user.exp} / 100 EXP', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const Divider(height: 24, thickness: 1),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🎯 취향: ${user.travelStyles.join(', ')}', style: const TextStyle(fontSize: 12, color: Color(0xFF2A1512))),
                          const SizedBox(height: 6),
                          Text('🚗 활동 강도: ${user.transport}', style: const TextStyle(fontSize: 12, color: Color(0xFF2A1512))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 버튼 모음
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onReSurvey,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('취향 재설정하기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9E2B1E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, size: 18, color: Color(0xFF2A1512)),
                  label: const Text('로그아웃 및 데이터 초기화', style: TextStyle(color: Color(0xFF2A1512))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2A1512), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}