import 'package:flutter/material.dart';

import 'app_colors.dart';

// =============================================================================
// 로컬 퀘스트 디자인 시스템 v1.0 — 형태 · 깊이 · 리듬 토큰
//
// [입체감 5원칙]
//  1. 빛은 항상 위에서 온다 — 표면 상단에 밝은 하이라이트, 그림자는 아래로.
//  2. 그림자는 회색이 아니라 따뜻한 잉크색(#2A1512)의 알파 변형이다.
//  3. 한 화면에 e3 이상은 최대 1개. 초점은 하나뿐이어야 깊이가 읽힌다.
//  4. 1.5px 검정 테두리를 없애고 그 역할을 "표면 밝기 차 + 그림자"로 옮긴다.
//     테두리는 강조가 필요할 때만 남긴다.
//  5. 누름은 색이 아니라 깊이로 표현한다 — 그림자 한 단계 하강 + scale 0.97.
// =============================================================================

/// 4pt 그리드 간격
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// 화면 좌우 기본 여백
  static const double gutter = 16;
}

/// 모서리 반경 — 요소가 클수록 반경도 커진다(광학적 일관성)
class AppRadius {
  const AppRadius._();

  static const double xs = 6; // 칩 안쪽 · 작은 배지
  static const double sm = 10; // 인풋 · 작은 박스
  static const double md = 14; // 카드
  static const double lg = 18; // 큰 카드 · 강조 패널
  static const double xl = 24; // 바텀시트 · 모달
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius panel = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheet = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
  );
}

/// 그림자 단계 — 화면의 z축 위계
///
/// e0 종이에 붙어 있음 · e1 살짝 뜸 · e2 카드 · e3 떠 있는 카드
/// e4 시트/모달 · e5 최상위(레벨업 · 마커 팝오버)
class AppElevation {
  const AppElevation._();

  static Color _ink(double opacity) =>
      AppColors.shadowBase.withValues(alpha: opacity);

  /// 종이에 인쇄된 상태. 그림자 없음.
  static const List<BoxShadow> e0 = <BoxShadow>[];

  /// 칩 · 인라인 요소. 존재만 알리는 최소 깊이.
  static List<BoxShadow> get e1 => [
        BoxShadow(color: _ink(0.05), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(color: _ink(0.04), blurRadius: 4, offset: const Offset(0, 2)),
      ];

  /// 기본 카드. 목록에서 반복되는 표면.
  static List<BoxShadow> get e2 => [
        BoxShadow(color: _ink(0.06), blurRadius: 3, offset: const Offset(0, 1)),
        BoxShadow(color: _ink(0.05), blurRadius: 10, offset: const Offset(0, 4)),
      ];

  /// 떠 있는 카드 — 진행 중 퀘스트, 선택된 항목. 화면당 1~2개.
  static List<BoxShadow> get e3 => [
        BoxShadow(color: _ink(0.07), blurRadius: 6, offset: const Offset(0, 2)),
        BoxShadow(color: _ink(0.07), blurRadius: 22, offset: const Offset(0, 10)),
      ];

  /// 바텀시트 · 모달. 아래 레이어를 확실히 눌러야 한다.
  static List<BoxShadow> get e4 => [
        BoxShadow(color: _ink(0.09), blurRadius: 14, offset: const Offset(0, -2)),
        BoxShadow(color: _ink(0.10), blurRadius: 40, offset: const Offset(0, 16)),
      ];

  /// 최상위 — 레벨업 연출, 지도 마커 팝오버.
  static List<BoxShadow> get e5 => [
        BoxShadow(color: _ink(0.14), blurRadius: 24, offset: const Offset(0, 8)),
        BoxShadow(color: _ink(0.12), blurRadius: 64, offset: const Offset(0, 28)),
      ];

  /// 붉은 표면(주 버튼 · 활성 마커) 아래에는 붉은 기가 도는 그림자를 쓴다.
  /// 중립 회색 그림자는 브랜드 색을 탁하게 만든다.
  static List<BoxShadow> get brand => [
        BoxShadow(
          color: AppColors.shadowWarm.withValues(alpha: 0.28),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];

  /// 지도 마커용 — 배경(타일)이 복잡하므로 더 또렷하게 띄운다.
  static List<BoxShadow> get marker => [
        BoxShadow(color: _ink(0.22), blurRadius: 8, offset: const Offset(0, 4)),
        BoxShadow(color: _ink(0.10), blurRadius: 18, offset: const Offset(0, 10)),
      ];

  /// 포커스 링 — 선택된 요소를 색이 아닌 "빛 번짐"으로 표시.
  static List<BoxShadow> focusRing(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.16),
          blurRadius: 0,
          spreadRadius: 3,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.26),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
}

/// 표면 처리 — 평평한 단색 대신 "위에서 빛을 받은 면"을 만든다.
class AppSurface {
  const AppSurface._();

  /// 종이 표면. 위쪽이 아주 살짝 밝다.
  static const LinearGradient paper = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), AppColors.ink0],
  );

  /// 강조 패널 (진행 중 퀘스트 등)
  static const LinearGradient highlight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFF8F5), AppColors.quest50],
  );

  /// 주 버튼 — 위가 밝고 아래가 어두운 에나멜 면
  static const LinearGradient brandFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFB03526), AppColors.quest600],
  );

  /// 보상(EXP) 표면
  static const LinearGradient rewardFill = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.amber50, AppColors.amber100],
  );

  /// 눌린 면 — 입력창 · 트랙 안쪽. 톤 하강으로 오목함을 만든다.
  static const LinearGradient sunken = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.ink200, AppColors.ink100],
  );

  /// 기본 표면 경계 — 검정 실선이 아닌 헤어라인
  static Border get hairline =>
      Border.all(color: AppColors.hairline, width: 1);

  static Border get hairlineStrong =>
      Border.all(color: AppColors.hairlineStrong, width: 1);
}

/// 모션 — 깊이는 시간축에도 있다. 누르면 내려가고, 떼면 스프링으로 돌아온다.
class AppMotion {
  const AppMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 140); // 누름 반응
  static const Duration base = Duration(milliseconds: 220); // 상태 전환
  static const Duration slow = Duration(milliseconds: 340); // 카드 등장
  static const Duration sheet = Duration(milliseconds: 400); // 바텀시트

  /// 대부분의 상태 전환
  static const Curve standard = Cubic(0.2, 0, 0, 1);

  /// 등장 · 확장 — 빠르게 나와서 부드럽게 멎는다
  static const Curve emphasized = Cubic(0.2, 0.8, 0.2, 1);

  /// 누름 해제 · 보상 연출
  static const Curve spring = Curves.easeOutBack;

  /// 누름 시 축소 비율
  static const double pressScale = 0.97;
}

/// 타이포 — 한 벌의 목소리. 수치는 tabular figure로 흔들리지 않게.
class AppType {
  const AppType._();

  static const String family = 'Pretendard';

  /// EXP · 레벨 등 큰 수치
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.6,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  /// 배지 · 표 헤더 · 라벨
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0.2,
    color: AppColors.textTertiary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.1,
  );

  /// 수치 전용 (거리 · EXP · 개수)
  static const TextStyle numeric = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.textPrimary,
  );
}

/// 난이도 등급(★1~★5)별 시각 처리 — 목록이 단조로워지지 않게 하는 축.
/// 색만 바뀌는 게 아니라 **깊이와 광택도 함께 올라간다**.
enum QuestTierStyle {
  /// ★ 산책 — 종이에 붙어 있는 평범한 의뢰
  common(
    label: '산책',
    accent: AppColors.ink500,
    tint: AppColors.ink100,
    onTint: AppColors.ink700,
  ),

  /// ★★ 기본
  uncommon(
    label: '기본',
    accent: AppColors.jade500,
    tint: AppColors.jade50,
    onTint: AppColors.jade700,
  ),

  /// ★★★ 탐험
  rare(
    label: '탐험',
    accent: AppColors.lapis500,
    tint: AppColors.lapis50,
    onTint: AppColors.lapis700,
  ),

  /// ★★★★ 원정
  epic(
    label: '원정',
    accent: AppColors.amber500,
    tint: AppColors.amber50,
    onTint: AppColors.amber700,
  ),

  /// ★★★★★ 전설 — 인장이 찍힌 의뢰. 유일하게 발광한다.
  legendary(
    label: '전설',
    accent: AppColors.quest500,
    tint: AppColors.quest50,
    onTint: AppColors.quest700,
  );

  final String label;
  final Color accent;
  final Color tint;
  final Color onTint;

  const QuestTierStyle({
    required this.label,
    required this.accent,
    required this.tint,
    required this.onTint,
  });

  static QuestTierStyle fromStars(int stars) {
    switch (stars) {
      case 1:
        return QuestTierStyle.common;
      case 2:
        return QuestTierStyle.uncommon;
      case 3:
        return QuestTierStyle.rare;
      case 4:
        return QuestTierStyle.epic;
      default:
        return QuestTierStyle.legendary;
    }
  }

  /// 등급이 오를수록 카드가 더 떠오른다.
  List<BoxShadow> get elevation {
    switch (this) {
      case QuestTierStyle.common:
      case QuestTierStyle.uncommon:
        return AppElevation.e2;
      case QuestTierStyle.rare:
      case QuestTierStyle.epic:
        return AppElevation.e3;
      case QuestTierStyle.legendary:
        return [
          ...AppElevation.e3,
          BoxShadow(
            color: AppColors.quest500.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ];
    }
  }
}
