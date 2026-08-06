import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  static const Color primaryRed = Color(0xFF9E2B1E);
  static const Color darkBorder = Color(0xFF2A1512);
  static const Color bgCream = Color(0xFFFFFDFB);
  static const Color subTextColor = Color(0x8C2A1512);
  static const Color kakaoYellow = Color(0xFFFEE500);

  // 로그인 핸들러
  Future<void> _handleSocialLogin(Future<bool> Function() loginMethod) async {
    setState(() => _isLoading = true);

    final bool success = await loginMethod();

    setState(() => _isLoading = false);

    if (success) {
      widget.onLoginSuccess();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인에 실패했거나 취소되었습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // 로고 영역
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: primaryRed,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: darkBorder, width: 1.5),
                    ),
                    child: const Center(child: Text('🚩', style: TextStyle(fontSize: 44))),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '로컬 퀘스트지상주의',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: darkBorder),
                  ),
                  const SizedBox(height: 8),
                  const Text('일상 속 골목길이 특별한 모험이 되는 순간', style: TextStyle(fontSize: 12, color: subTextColor)),
                  const Spacer(),

                  // 소셜 로그인 버튼들
                  _buildSocialButton(
                    label: '카카오로 시작하기',
                    icon: '💬',
                    bgColor: kakaoYellow,
                    textColor: darkBorder,
                    onTap: () => _handleSocialLogin(AuthService.signInWithKakao),
                  ),
                  const SizedBox(height: 10),
                  _buildSocialButton(
                    label: 'Google로 시작하기',
                    icon: '🌐',
                    bgColor: Colors.white,
                    textColor: darkBorder,
                    onTap: () => _handleSocialLogin(AuthService.signInWithGoogle),
                  ),
                  const SizedBox(height: 10),
                  _buildSocialButton(
                    label: 'Apple로 시작하기',
                    icon: '🍎',
                    bgColor: darkBorder,
                    textColor: Colors.white,
                    onTap: () => _handleSocialLogin(AuthService.signInWithApple),
                  ),
                  const SizedBox(height: 20),

                  // 둘러보기 (게스트 모드)
                  GestureDetector(
                    onTap: widget.onLoginSuccess,
                    child: const Text(
                      '로그인 없이 둘러보기',
                      style: TextStyle(fontSize: 12, color: subTextColor, decoration: TextDecoration.underline),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // 로딩 오버레이
            if (_isLoading)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(color: primaryRed),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required String label,
    required String icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: darkBorder, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }
}