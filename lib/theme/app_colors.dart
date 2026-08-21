import 'package:flutter/material.dart';

/// 로컬 퀘스트 디자인 시스템 v1.0 — 컬러 토큰
///
/// 콘셉트: **Parchment & Seal** (양피지와 인장)
/// 모험가 수첩의 따뜻한 종이 위에, 붉은 낙관(인장)이 찍힌 화면.
/// 기존 와이어프레임의 크림/딥레드 정체성은 유지하되
/// - 회색 그림자 대신 **따뜻한 잉크색 그림자**
/// - 단조로운 단색 대신 **역할별 보조 색상(EXP·완료·기록)**
/// 을 도입해 입체감과 리듬을 만든다.
///
/// 규칙: 화면에서 색을 직접 하드코딩하지 말고 항상 이 클래스를 참조한다.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------------
  // 1. Ink — 따뜻한 뉴트럴 (배경 · 텍스트 · 구분선)
  //    차가운 회색이 아니라 갈색이 섞인 잉크 계열. 종이 위 인쇄물의 느낌.
  // ---------------------------------------------------------------------------
  static const Color ink0 = Color(0xFFFFFDFB); // 카드 · 시트 표면 (종이)
  static const Color ink50 = Color(0xFFFBF6F3); // 앱 바탕
  static const Color ink100 = Color(0xFFF4EBE6); // 눌린 면 · 트랙 배경
  static const Color ink200 = Color(0xFFE8DCD6); // 구분선 · 진행바 트랙
  static const Color ink300 = Color(0xFFD6C8C2); // 헤어라인 테두리 · 손잡이
  static const Color ink400 = Color(0xFFB6A49E); // 비활성 텍스트 · 아이콘
  static const Color ink500 = Color(0xFF8E7A74); // 3차 텍스트
  static const Color ink600 = Color(0xFF6D5A55); // 2차 텍스트 (보조 설명)
  static const Color ink700 = Color(0xFF4A342F); // 강한 보조 텍스트
  static const Color ink800 = Color(0xFF37211C);
  static const Color ink900 = Color(0xFF2A1512); // 본문 텍스트 · 그림자 원색

  // ---------------------------------------------------------------------------
  // 2. Quest Red — 브랜드 주색 (인장)
  //    주 CTA · 활성 마커 · 선택 상태에만. 남발하면 위계가 무너진다.
  // ---------------------------------------------------------------------------
  static const Color quest50 = Color(0xFFFDF4F1);
  static const Color quest100 = Color(0xFFF9E0D9);
  static const Color quest200 = Color(0xFFF0BCAF);
  static const Color quest300 = Color(0xFFE1917F);
  static const Color quest400 = Color(0xFFC55B45);
  static const Color quest500 = Color(0xFF9E2B1E); // 브랜드 원색
  static const Color quest600 = Color(0xFF8A2419); // hover · 그라데이션 하단
  static const Color quest700 = Color(0xFF6F1C13); // 버튼 물리적 하단 모서리
  static const Color quest800 = Color(0xFF53150E);
  static const Color quest900 = Color(0xFF380E09);

  // ---------------------------------------------------------------------------
  // 3. 역할 색상 — 단조로움을 깨는 축
  //    "모든 게 빨강"이던 문제를 의미 단위로 분리한다.
  // ---------------------------------------------------------------------------
  // Amber · 보상 / EXP / 획득
  static const Color amber50 = Color(0xFFFDF6E7);
  static const Color amber100 = Color(0xFFF8E7BE);
  static const Color amber300 = Color(0xFFE2B45F);
  static const Color amber500 = Color(0xFFC08428);
  static const Color amber700 = Color(0xFF8A5C15);

  // Jade · 완료 / 인증 성공 / 도달
  static const Color jade50 = Color(0xFFECF5F0);
  static const Color jade100 = Color(0xFFCFE7DB);
  static const Color jade500 = Color(0xFF2E7D5B);
  static const Color jade700 = Color(0xFF1E5A40);

  // Lapis · 정보 / 기록 / 관광지 데이터
  static const Color lapis50 = Color(0xFFEDF2F8);
  static const Color lapis100 = Color(0xFFD3E0EF);
  static const Color lapis500 = Color(0xFF2F5D8C);
  static const Color lapis700 = Color(0xFF1E3F62);

  // ---------------------------------------------------------------------------
  // 4. 그림자 원색
  //    모든 그림자는 이 색의 알파 변형이다. 검정(#000) 그림자는 금지 —
  //    크림 배경 위에서 회색 그림자는 즉시 "싸구려 머티리얼"처럼 보인다.
  // ---------------------------------------------------------------------------
  static const Color shadowBase = Color(0xFF2A1512);
  static const Color shadowWarm = Color(0xFF5A2A1A); // 붉은 표면 아래 그림자

  /// 위에서 빛을 받은 표면의 상단 하이라이트 (1px)
  static const Color surfaceHighlight = Color(0xCCFFFFFF);

  // ---------------------------------------------------------------------------
  // 5. 시맨틱 별칭 — 화면 코드는 되도록 이쪽을 쓴다
  // ---------------------------------------------------------------------------
  static const Color background = ink50;
  static const Color surface = ink0;
  static const Color surfaceSunken = ink100; // 눌린 면 · 입력창 안쪽
  static const Color textPrimary = ink900;
  static const Color textSecondary = ink600;
  static const Color textTertiary = ink500;
  static const Color textDisabled = ink400;
  static const Color textOnDark = Color(0xFFFFF6F3);
  static const Color hairline = Color(0x142A1512); // 8% — 기본 표면 경계
  static const Color hairlineStrong = Color(0x242A1512); // 14% — 강조 경계

  // ---------------------------------------------------------------------------
  // 6. 레거시 별칭 (기존 화면 호환용)
  //    v1.0 이전 코드가 쓰던 이름. 신규 코드에서는 사용하지 않는다.
  // ---------------------------------------------------------------------------
  static const Color primaryRed = quest500;
  static const Color darkBorder = ink900;
  static const Color bgCream = ink0;
  static const Color subText = Color(0x8C2A1512);
  static const Color noteBorder = ink300;
  static const Color noteText = ink600;
  static const Color highlightBg = quest50;
  static const Color progressBg = ink200;
  static const Color navBg = ink0;
  static const Color divider = ink200;
  static const Color navDivider = ink200;
  static const Color grabHandle = ink300;
  static const Color softButton = ink100;
  static const Color disabledBg = ink200;
  static const Color disabledBorder = ink300;
  static const Color disabledText = ink400;
  static const Color dotInactive = ink300;
}
