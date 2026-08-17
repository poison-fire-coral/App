import 'dart:math';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 하단 내비게이션 탭 (와이어프레임 공통 셸 : 배지 · 홈 · 지도)
enum AppTab { badges, home, map }

/// 상단 바 좌측의 프로필 링. 링 채움 비율 = 다음 레벨까지의 진행률.
class ProfileRing extends StatelessWidget {
  final double progress;
  final double size;
  final VoidCallback? onTap;

  const ProfileRing({super.key, required this.progress, this.size = 38, this.onTap});

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final inner = size - 8;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            startAngle: -pi / 2,
            endAngle: 3 * pi / 2,
            colors: const [
              AppColors.primaryRed,
              AppColors.primaryRed,
              AppColors.progressBg,
              AppColors.progressBg,
            ],
            stops: [0, clamped, clamped, 1],
          ),
        ),
        child: Center(
          child: Container(
            width: inner,
            height: inner,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.fromBorderSide(BorderSide(color: AppColors.darkBorder, width: 1)),
            ),
            child: Center(
              child: Text(
                '프로필',
                style: TextStyle(fontSize: size * 0.19, color: AppColors.subText),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 홈 · 지도 · 배지 탭이 공유하는 상단 바 (프로필 링 · 닉네임 · 레벨 · 설정)
class AppTopBar extends StatelessWidget {
  final String nickname;
  final int level;
  final double levelProgress;
  final VoidCallback? onTapProfile;
  final VoidCallback? onTapSettings;

  const AppTopBar({
    super.key,
    required this.nickname,
    required this.level,
    required this.levelProgress,
    this.onTapProfile,
    this.onTapSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          ProfileRing(progress: levelProgress, onTap: onTapProfile),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                ),
                Text(
                  'Lv.$level · ${(levelProgress * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: AppColors.subText),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTapSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.noteBorder, width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.settings_outlined, size: 16, color: AppColors.noteText),
            ),
          ),
        ],
      ),
    );
  }
}

/// 하단 3탭 내비게이션
class AppBottomNav extends StatelessWidget {
  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  const AppBottomNav({super.key, required this.current, required this.onSelect});

  static const List<({AppTab tab, String label})> _items = [
    (tab: AppTab.badges, label: '배지'),
    (tab: AppTab.home, label: '홈'),
    (tab: AppTab.map, label: '지도'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBg,
        border: Border(top: BorderSide(color: AppColors.darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          for (final item in _items)
            _NavItem(
              label: item.label,
              isActive: item.tab == current,
              showDivider: item.tab != AppTab.map,
              onTap: () => onSelect(item.tab),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool showDivider;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.isActive,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryRed : Colors.transparent,
            border: Border(
              right: showDivider
                  ? const BorderSide(color: AppColors.navDivider, width: 1)
                  : BorderSide.none,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : AppColors.darkBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 실선 테두리 박스 (.bx)
class SolidBox extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const SolidBox({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(11)});

  factory SolidBox.text(String text, {Color? color, double fontSize = 13}) {
    return SolidBox(
      color: color,
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, color: AppColors.darkBorder, height: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppColors.darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }
}

/// 점선 느낌의 보조 박스 (.bxd — Flutter 기본 Border에 dashed가 없어 연한 실선으로 대체)
class NoteBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Alignment? alignment;
  final double? height;

  const NoteBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(11),
    this.alignment,
    this.height,
  });

  factory NoteBox.text(String text, {double fontSize = 13, TextAlign textAlign = TextAlign.left}) {
    return NoteBox(
      child: Text(
        text,
        textAlign: textAlign,
        style: TextStyle(fontSize: fontSize, color: AppColors.noteText, height: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.bgCream,
        border: Border.all(color: AppColors.noteBorder, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }
}

/// 채워진 주 버튼 (.btnp) — enabled=false면 와이어프레임의 비활성(회색) 상태
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(vertical: 11),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primaryRed : AppColors.disabledBg,
          border: Border.all(
            color: enabled ? AppColors.darkBorder : AppColors.disabledBorder,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: enabled ? Colors.white : AppColors.bgCream,
            ),
          ),
        ),
      ),
    );
  }
}

/// 외곽선 보조 버튼 (.btn)
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const SecondaryButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.softButton,
          border: Border.all(color: AppColors.darkBorder, width: 1.5),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, color: AppColors.darkBorder),
          ),
        ),
      ),
    );
  }
}

/// 칩 (.chip / .chipa)
class TagChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final double fontSize;

  const TagChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryRed : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.primaryRed : AppColors.darkBorder,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppColors.darkBorder,
          ),
        ),
      ),
    );
  }
}

/// 진행바 (.ln / .lnf)
class ProgressBar extends StatelessWidget {
  final double value;
  final double height;

  const ProgressBar({super.key, required this.value, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.progressBg,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primaryRed,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}

/// 바텀시트 상단 손잡이 (.grab)
class GrabHandle extends StatelessWidget {
  final VoidCallback? onTap;

  const GrabHandle({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.grabHandle,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 실제 타일맵 SDK를 붙이기 전까지 쓰는 45도 스트라이프 배경 (.map)
class MapBackdrop extends StatelessWidget {
  const MapBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MapBackdropPainter(), child: const SizedBox.expand());
  }
}

class _MapBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFFF7F3F0);
    canvas.drawRect(Offset.zero & size, base);

    final stripe = Paint()
      ..color = const Color(0xFFECE4DF)
      ..strokeWidth = 9;
    const gap = 18.0;
    final diagonalCount = ((size.width + size.height) / gap).ceil() + 2;
    for (int i = -diagonalCount; i < diagonalCount; i++) {
      final offset = i * gap;
      canvas.drawLine(Offset(offset, 0), Offset(offset + size.height, size.height), stripe);
    }
  }

  @override
  bool shouldRepaint(covariant _MapBackdropPainter oldDelegate) => false;
}

/// 퀘스트 위치를 나타내는 물방울 마커 (.mk / .mka)
class QuestMarker extends StatelessWidget {
  final bool isActive;
  final double size;

  const QuestMarker({super.key, this.isActive = false, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryRed : AppColors.bgCream,
          border: Border.all(color: AppColors.darkBorder, width: 1.5),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(size / 2),
            topRight: Radius.circular(size / 2),
            bottomLeft: Radius.circular(size / 2),
          ),
        ),
      ),
    );
  }
}
