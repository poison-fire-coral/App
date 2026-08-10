import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// 1c. 회원가입 화면 (가입 방법 선택 + 약관 동의)
// -----------------------------------------------------------------------------
class SignupScreen extends StatefulWidget {
  final VoidCallback onSignupSuccess;

  const SignupScreen({
    super.key,
    required this.onSignupSuccess,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static const Color primaryRed = Color(0xFF9E2B1E);
  static const Color darkBorder = Color(0xFF2A1512);
  static const Color bgCream = Color(0xFFFFFDFB);
  static const Color subTextColor = Color(0x8C2A1512);
  static const Color noteBorder = Color(0xFFA2908A);
  static const Color noteText = Color(0xFF6D5A55);

  String? _selectedMethod;
  bool _agreeService = true;
  bool _agreeLocation = true;
  bool _agreeMarketing = false;

  bool get _canContinue =>
      _selectedMethod != null && _agreeService && _agreeLocation;

  void _handleContinue() {
    if (!_canContinue) return;
    widget.onSignupSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '가입 방법 선택',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkBorder),
                    ),
                    const SizedBox(height: 16),

                    _buildMethodButton('Google로 가입'),
                    const SizedBox(height: 10),
                    _buildMethodButton('카카오로 가입'),
                    const SizedBox(height: 10),
                    _buildMethodButton('이메일로 가입'),
                    const SizedBox(height: 20),

                    // 약관 동의 박스
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: darkBorder, width: 1.5),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Column(
                        children: [
                          _buildCheckRow(
                            '서비스 이용약관 (필수)',
                            value: _agreeService,
                            onChanged: (v) => setState(() => _agreeService = v),
                          ),
                          _buildCheckRow(
                            '위치정보 이용약관 (필수)',
                            value: _agreeLocation,
                            onChanged: (v) => setState(() => _agreeLocation = v),
                          ),
                          _buildCheckRow(
                            '마케팅 수신 (선택)',
                            value: _agreeMarketing,
                            onChanged: (v) => setState(() => _agreeMarketing = v),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    _buildPrimaryButton('동의하고 계속', onTap: _handleContinue, enabled: _canContinue),
                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: _buildDashedNote(
                        '이미 가입된 계정 → "이미 가입됨, 로그인해 주세요" 후 로그인 화면으로 이동',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Text(
              '← 회원가입',
              style: TextStyle(fontSize: 14, color: darkBorder, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodButton(String label) {
    final bool isSelected = _selectedMethod == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = label),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? primaryRed.withAlpha(20) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? primaryRed : darkBorder, width: isSelected ? 2 : 1.5),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? primaryRed : darkBorder),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckRow(String label, {required bool value, required ValueChanged<bool> onChanged}) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? primaryRed : Colors.white,
                border: Border.all(color: darkBorder, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: value ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12, color: darkBorder)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(String label, {required VoidCallback onTap, required bool enabled}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? primaryRed : subTextColor,
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
        style: const TextStyle(fontSize: 11, color: noteText, height: 1.3, decoration: TextDecoration.underline),
      ),
    );
  }
}
