import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';

// -----------------------------------------------------------------------------
// 1b. 로그인 화면 (계속하기 3종 + 회원가입 진입)
// -----------------------------------------------------------------------------
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
  static const Color noteBorder = Color(0xFFA2908A);
  static const Color noteText = Color(0xFF6D5A55);

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

  void _handleEmailLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이메일 로그인은 준비 중입니다.')),
    );
  }

  void _goToSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignupScreen(onSignupSuccess: widget.onLoginSuccess),
      ),
    );
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
                children: [
                  const Spacer(flex: 3),
                  const Text(
                    '모험을 시작할까요?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkBorder),
                  ),
                  const Spacer(flex: 3),

                  // 계속하기 3종
                  _buildOutlineButton(
                    label: 'Google로 계속하기',
                    onTap: () => _handleSocialLogin(AuthService.signInWithGoogle),
                  ),
                  const SizedBox(height: 10),
                  _buildOutlineButton(
                    label: '카카오로 계속하기',
                    onTap: () => _handleSocialLogin(AuthService.signInWithKakao),
                  ),
                  const SizedBox(height: 10),
                  _buildOutlineButton(
                    label: '이메일로 계속하기',
                    onTap: _handleEmailLogin,
                  ),
                  const SizedBox(height: 20),

                  // 회원가입 진입 (1c)
                  _buildPrimaryButton(
                    label: '회원가입',
                    onTap: _goToSignup,
                  ),
                  const SizedBox(height: 14),

                  _buildDashedNote(
                    '미가입 계정으로 시도 → "가입된 계정이 없습니다" 토스트 후 이 화면 유지',
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

  Widget _buildOutlineButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: darkBorder, width: 1.5),
        ),
        child: Center(
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkBorder)),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: primaryRed,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: darkBorder, width: 1.5),
        ),
        child: Center(
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildDashedNote(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: noteBorder, width: 1.5),
        borderRadius: BorderRadius.circular(7),
        color: bgCream,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: noteText, height: 1.3),
      ),
    );
  }
}
