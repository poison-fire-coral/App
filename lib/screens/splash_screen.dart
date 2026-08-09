import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// 1a. 스플래시 화면
// 버전 체크·토큰 유효성 검사 후 분기하는 로직은 추후 연결 예정 (현재는 정적 UI만 구현)
// -----------------------------------------------------------------------------
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const Color primaryRed = Color(0xFF9E2B1E);
  static const Color darkBorder = Color(0xFF2A1512);
  static const Color bgCream = Color(0xFFFFFDFB);
  static const Color subTextColor = Color(0x8C2A1512);
  static const Color progressBg = Color(0xFFE8DCD6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // 로고 placeholder
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: darkBorder, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    '로고\nplaceholder',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: subTextColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                '로컬 퀘스트지상주의',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkBorder),
              ),
              const SizedBox(height: 8),
              const Text('소도시 전체가 하나의 퀘스트 맵', style: TextStyle(fontSize: 12, color: subTextColor)),

              const Spacer(flex: 4),

              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  width: double.infinity,
                  child: LinearProgressIndicator(
                    value: 0.35,
                    backgroundColor: progressBg,
                    valueColor: const AlwaysStoppedAnimation<Color>(primaryRed),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text('team 붉은사슴불버섯', style: TextStyle(fontSize: 11, color: subTextColor)),
            ],
          ),
        ),
      ),
    );
  }
}
