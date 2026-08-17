import 'package:flutter/material.dart';

/// 와이어프레임(로컬퀘스트 와이어프레임.dc.html)의 CSS 팔레트를 그대로 옮긴 공용 색상.
/// 화면마다 같은 상수를 다시 선언하지 않도록 이 클래스를 참조한다.
class AppColors {
  const AppColors._();

  static const Color primaryRed = Color(0xFF9E2B1E); // 주 강조색 (.btnp, .chipa)
  static const Color darkBorder = Color(0xFF2A1512); // 실선 테두리 · 본문 텍스트
  static const Color bgCream = Color(0xFFFFFDFB); // 카드 · 시트 배경
  static const Color subText = Color(0x8C2A1512); // .nt 보조 텍스트
  static const Color noteBorder = Color(0xFFA2908A); // .bxd 점선 테두리
  static const Color noteText = Color(0xFF6D5A55); // .bxd 텍스트
  static const Color highlightBg = Color(0xFFF7DFD9); // .hl 강조 카드 배경
  static const Color progressBg = Color(0xFFE8DCD6); // .ln 진행바 트랙
  static const Color navBg = Color(0xFFFAF5F2); // 하단 탭 배경
  static const Color divider = Color(0xFFE6DCD6);
  static const Color navDivider = Color(0xFFD8CCC6);
  static const Color grabHandle = Color(0xFFD6C8C2);
  static const Color softButton = Color(0xFFF6EFEC); // .btn 배경
  static const Color disabledBg = Color(0xFFD8C8C3);
  static const Color disabledBorder = Color(0xFFB6A49E);
  static const Color disabledText = Color(0xFFA2908A);
  static const Color dotInactive = Color(0xFFC9B8B2);
}
