import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'avatar_widgets.dart';

// =============================================================================
// 로컬 퀘스트 디자인 시스템 v1.0 — 공용 컴포넌트
//
// v0(와이어프레임 이식본)와 API는 100% 호환된다. 화면 코드를 고치지 않아도
// 아래 규칙에 따라 겉모습만 입체적으로 바뀐다.
//
//  · 1.5px 검정 실선 테두리  → 헤어라인(8% 잉크) + 그림자
//  · 단색 채움              → 위에서 빛을 받는 미세 그라데이션
//  · 즉각 반응 없음          → 누르면 내려앉고(scale 0.97) 그림자가 줄어듦
// =============================================================================

/// 하단 내비게이션 탭 (공통 셸 : 배지 · 홈 · 지도)
enum AppTab { badges, home, map }

// -----------------------------------------------------------------------------
// 0. 상호작용 기반 — "누르면 물리적으로 내려앉는다"
// -----------------------------------------------------------------------------

/// 탭 가능한 모든 표면을 감싸는 래퍼.
/// 누르는 동안 축소 + (선택적으로) 아래로 내려앉아 깊이 변화를 만든다.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final double sinkY;
  final HitTestBehavior behavior;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = AppMotion.pressScale,
    this.sinkY = 0,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: AnimatedSlide(
          offset: Offset(0, _pressed ? widget.sinkY : 0),
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 1. 표면 — 모든 카드의 기본형
// -----------------------------------------------------------------------------

/// 종이 표면 카드. 그림자 단계와 강조 여부만 정하면 나머지는 토큰이 결정한다.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadow;
  final Gradient? gradient;
  final Color? color;
  final BorderRadius radius;
  final Border? border;
  final VoidCallback? onTap;

  /// 좌측에 붙는 등급/상태 색 띠. null이면 표시하지 않는다.
  final Color? accentEdge;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.shadow,
    this.gradient,
    this.color,
    this.radius = AppRadius.card,
    this.border,
    this.onTap,
    this.accentEdge,
  });

  @override
  Widget build(BuildContext context) {
    Widget surface = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.surface) : null,
        gradient: gradient,
        borderRadius: radius,
        border: border ?? AppSurface.hairline,
        boxShadow: shadow ?? AppElevation.e2,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (accentEdge != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: accentEdge),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    if (onTap == null) return surface;
    return PressableScale(onTap: onTap, scale: 0.985, child: surface);
  }
}

/// 바텀시트 · 모달의 최상단 표면. 위쪽 모서리만 크게 둥글고 위로 그림자를 던진다.
class AppSheetSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppSheetSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppSurface.paper,
        borderRadius: AppRadius.sheet,
        boxShadow: AppElevation.e4,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. 상단 바 · 프로필 링
// -----------------------------------------------------------------------------

/// 상단 바 좌측의 프로필 링. 링 채움 비율 = 다음 레벨까지의 진행률.
/// 링은 단색이 아니라 그라데이션이며, 안쪽 원판은 살짝 떠 있다.
class ProfileRing extends StatelessWidget {
  final double progress;
  final double size;
  final VoidCallback? onTap;

  /// 링 안쪽에 그릴 아바타 프리셋 id. null이면 기본 프리셋.
  final String? avatarId;

  /// 아바타 대신 짧은 글자를 넣고 싶을 때만 쓴다(로딩 중 등). 지정하면 아바타보다 우선한다.
  final String? label;

  const ProfileRing({
    super.key,
    required this.progress,
    this.size = 42,
    this.onTap,
    this.avatarId,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final inner = size - 7;

    return PressableScale(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 트랙은 오목하게, 채워진 구간은 밝은 붉은색 → 어두운 붉은색으로.
          gradient: SweepGradient(
            startAngle: -pi / 2,
            endAngle: 3 * pi / 2,
            colors: const [
              AppColors.quest400,
              AppColors.quest600,
              AppColors.ink200,
              AppColors.ink200,
            ],
            stops: [0, clamped, clamped, 1],
          ),
          boxShadow: clamped > 0 ? AppElevation.e1 : null,
        ),
        child: Center(
          child: Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppSurface.paper,
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowBase.withValues(alpha: 0.10),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipOval(
              child: label != null
                  ? Center(
                      child: Text(
                        label!,
                        style: TextStyle(
                          fontSize: size * 0.24,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    )
                  : AppAvatar(avatarId: avatarId, size: inner),
            ),
          ),
        ),
      ),
    );
  }
}

/// 홈 · 지도 · 배지 탭이 공유하는 상단 바.
/// 검정 하단 실선 대신 "표면이 아래 콘텐츠 위에 떠 있는" 그림자로 층을 만든다.
class AppTopBar extends StatelessWidget {
  final String nickname;
  final int level;
  final double levelProgress;
  final String? avatarId;
  final VoidCallback? onTapProfile;
  final VoidCallback? onTapSettings;

  const AppTopBar({
    super.key,
    required this.nickname,
    required this.level,
    required this.levelProgress,
    this.avatarId,
    this.onTapProfile,
    this.onTapSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: AppSurface.paper,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowBase.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ProfileRing(
            progress: levelProgress,
            avatarId: avatarId,
            onTap: onTapProfile,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nickname, style: AppType.h2),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _LevelPill(level: level),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ProgressBar(value: levelProgress, height: 5),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${(levelProgress * 100).round()}%',
                      style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _IconSurfaceButton(
            icon: Icons.tune_rounded,
            onTap: onTapSettings,
          ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  final int level;

  const _LevelPill({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppSurface.brandFill,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowWarm.withValues(alpha: 0.22),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        'Lv.$level',
        style: AppType.micro.copyWith(
          color: AppColors.textOnDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 떠 있는 원형/사각 아이콘 버튼 (설정 · 현위치 등)
class _IconSurfaceButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  /// 상단 바 아이콘 규격 고정. 다른 크기가 필요하면 FloatingSurfaceButton을 쓴다.
  static const double size = 38;

  const _IconSurfaceButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppSurface.paper,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: AppSurface.hairline,
          boxShadow: AppElevation.e1,
        ),
        child: Icon(icon, size: size * 0.46, color: AppColors.textSecondary),
      ),
    );
  }
}

/// 지도 우하단 등에서 쓰는 떠 있는 원형 액션 버튼
class FloatingSurfaceButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool emphasized;

  const FloatingSurfaceButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 46,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: emphasized ? AppSurface.brandFill : AppSurface.paper,
          boxShadow: emphasized ? AppElevation.brand : AppElevation.e3,
        ),
        child: Icon(
          icon,
          size: size * 0.46,
          color: emphasized ? AppColors.textOnDark : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. 하단 내비게이션 — 떠 있는 바 + 활성 알약
// -----------------------------------------------------------------------------

class AppBottomNav extends StatelessWidget {
  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  const AppBottomNav({super.key, required this.current, required this.onSelect});

  static const List<({AppTab tab, String label, IconData icon})> _items = [
    (tab: AppTab.badges, label: '배지', icon: Icons.workspace_premium_rounded),
    (tab: AppTab.home, label: '홈', icon: Icons.explore_rounded),
    (tab: AppTab.map, label: '지도', icon: Icons.map_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppSurface.paper,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowBase.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              for (final item in _items)
                Expanded(
                  child: _NavItem(
                    label: item.label,
                    icon: item.icon,
                    isActive: item.tab == current,
                    onTap: () => onSelect(item.tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          gradient: isActive ? AppSurface.brandFill : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: isActive ? AppElevation.brand : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? AppColors.textOnDark : AppColors.ink400,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppType.micro.copyWith(
                color: isActive ? AppColors.textOnDark : AppColors.ink500,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. 박스 — 정보 표시용 두 종류
// -----------------------------------------------------------------------------

/// 강조 정보 박스 (구 `.bx`). 이제는 떠 있는 종이 표면이다.
class SolidBox extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadow;
  final Color? accentEdge;

  const SolidBox({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.shadow,
    this.accentEdge,
  });

  factory SolidBox.text(String text, {Color? color, double fontSize = 13.5}) {
    return SolidBox(
      color: color,
      child: Text(
        text,
        style: AppType.body.copyWith(fontSize: fontSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: color,
      gradient: color == null ? AppSurface.paper : null,
      padding: padding,
      shadow: shadow ?? AppElevation.e2,
      accentEdge: accentEdge,
      child: child,
    );
  }
}

/// 보조 설명 박스 (구 `.bxd` 점선). 이제는 종이에 눌러 새긴 오목한 면이다.
/// 떠 있는 카드(SolidBox)와 오목한 면(NoteBox)의 대비가 층을 만든다.
class NoteBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Alignment? alignment;
  final double? height;

  const NoteBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.alignment,
    this.height,
  });

  factory NoteBox.text(
    String text, {
    double fontSize = 13.5,
    TextAlign textAlign = TextAlign.left,
  }) {
    return NoteBox(
      child: Text(
        text,
        textAlign: textAlign,
        style: AppType.bodyMuted.copyWith(fontSize: fontSize),
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
      // 오목한 면(04 표면). 빛이 위에서 오므로 윗변에 그늘, 아랫변에 반사가 진다.
      //
      // 주의: 이 그늘을 `Border`의 면별 색으로 주면 안 된다. Flutter는
      // `borderRadius`가 있는 테두리의 네 면 색이 다르면 **paint 단계에서 예외를
      // 던지고 자식을 통째로 그리지 않는다.** 실제로 그 탓에 NoteBox 안의 글자가
      // 앱 전체에서 보이지 않았다. 그래서 그늘은 inset 그림자로 표현한다.
      decoration: BoxDecoration(
        gradient: AppSurface.sunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairline, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowBase.withValues(alpha: 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// 5. 버튼 — 물리적인 키
// -----------------------------------------------------------------------------

/// 주 버튼. 아래쪽에 어두운 모서리(quest700)를 깔아 두께를 만들고,
/// 누르면 그 두께만큼 내려앉아 실제로 눌리는 것처럼 보이게 한다.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
    this.icon,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  static const double _edge = 3; // 버튼의 물리적 두께
  bool _pressed = false;

  void _set(bool v) {
    if (!widget.enabled || widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onTap != null;
    final sunk = _pressed ? _edge : 0.0;

    return GestureDetector(
      onTap: on ? widget.onTap : null,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: SizedBox(
        height: null,
        child: Stack(
          children: [
            // 아래층 = 버튼의 옆면(두께)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: on ? AppColors.quest700 : AppColors.ink300,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            // 윗면
            AnimatedPadding(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              padding: EdgeInsets.only(top: sunk, bottom: _edge - sunk),
              child: Container(
                width: double.infinity,
                padding: widget.padding,
                decoration: BoxDecoration(
                  gradient: on ? AppSurface.brandFill : null,
                  color: on ? null : AppColors.ink200,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: on && !_pressed ? AppElevation.brand : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: widget.fontSize + 2,
                        color: on
                            ? AppColors.textOnDark
                            : AppColors.textDisabled,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(
                      widget.label,
                      style: AppType.button.copyWith(
                        fontSize: widget.fontSize,
                        color:
                            on ? AppColors.textOnDark : AppColors.textDisabled,
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
}

/// 보조 버튼. 밝은 종이 표면이 살짝 떠 있는 형태.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      sinkY: 0.03,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: AppSurface.paper,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: AppSurface.hairlineStrong,
          boxShadow: AppElevation.e1,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: AppType.button.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. 칩 · 배지
// -----------------------------------------------------------------------------

/// 키워드 칩 / 필터 칩. 선택 시 색만 바뀌는 게 아니라 떠오른다.
class TagChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final double fontSize;
  final Color? accent;

  const TagChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.fontSize = 12,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? AppColors.quest500;

    return PressableScale(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          gradient: isSelected ? AppSurface.brandFill : AppSurface.paper,
          color: null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.hairlineStrong,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: tone.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : AppElevation.e1,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            height: 1.3,
            color: isSelected ? AppColors.textOnDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 난이도(★1~★5) 배지 — 등급마다 색과 광택이 다르다. 목록의 단조로움을 깬다.
class TierBadge extends StatelessWidget {
  final int stars;
  final bool hasHalfStar;
  final bool showLabel;

  const TierBadge({
    super.key,
    required this.stars,
    this.hasHalfStar = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final tier = QuestTierStyle.fromStars(stars);
    final text = '★' * stars + (hasHalfStar ? '⯪' : '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tier.tint,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: tier.accent.withValues(alpha: 0.24), width: 1),
        boxShadow: stars >= 4
            ? [
                BoxShadow(
                  color: tier.accent.withValues(alpha: 0.20),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              letterSpacing: -0.5,
              color: tier.accent,
            ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 5),
            Text(
              tier.label,
              style: AppType.micro.copyWith(
                color: tier.onTint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 보상(EXP) 표시 — 앰버 계열. 빨강 일변도를 깨는 두 번째 축.
class RewardPill extends StatelessWidget {
  final int exp;
  final String? multiplierNote;

  const RewardPill({super.key, required this.exp, this.multiplierNote});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: AppSurface.rewardFill,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.amber300.withValues(alpha: 0.45),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.amber700.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, size: 16, color: AppColors.amber500),
          const SizedBox(width: 5),
          Text(
            '$exp',
            style: AppType.numeric.copyWith(
              fontSize: 15,
              color: AppColors.amber700,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'EXP',
            style: AppType.micro.copyWith(color: AppColors.amber700),
          ),
          if (multiplierNote != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              multiplierNote!,
              style: AppType.micro.copyWith(
                color: AppColors.amber700.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 섹션 제목 — 좌측에 짧은 색 막대를 붙여 스캔하기 쉽게.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailingText;
  final VoidCallback? onTapTrailing;
  final Color accent;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailingText,
    this.onTapTrailing,
    this.accent = AppColors.quest500,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: AppType.h3),
          const Spacer(),
          if (trailingText != null)
            PressableScale(
              onTap: onTapTrailing,
              scale: 0.95,
              child: Row(
                children: [
                  Text(
                    trailingText!,
                    style: AppType.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.textDisabled,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 7. 진행바 — 오목한 트랙 위에 광택 있는 막대
// -----------------------------------------------------------------------------

class ProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? accent;

  const ProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? AppColors.quest500;
    final v = value.clamp(0.0, 1.0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: AppSurface.sunken,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: v,
        child: AnimatedContainer(
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(tone, Colors.white, 0.28)!,
                tone,
              ],
            ),
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: v > 0.02
                ? [
                    BoxShadow(
                      color: tone.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// 바텀시트 상단 손잡이
class GrabHandle extends StatelessWidget {
  final VoidCallback? onTap;

  const GrabHandle({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.ink300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 8. 지도 — 마커와 배경
// -----------------------------------------------------------------------------

/// 실제 타일맵을 붙이기 전 쓰는 목업 배경.
/// 평평한 스트라이프 대신 블록 + 도로 + 비네트로 "지도 같은 깊이"를 만든다.
class MapBackdrop extends StatelessWidget {
  const MapBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapBackdropPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _MapBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 바탕 — 위가 밝고 아래로 갈수록 살짝 어두워진다.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F2EE), Color(0xFFEDE5DF)],
        ).createShader(rect),
    );

    // 블록(건물 덩어리) — 규칙적인 격자에 살짝 어긋난 사각형
    final block = Paint()..color = const Color(0xFFE6DCD5);
    final rnd = Random(7);
    const cell = 58.0;
    for (double y = -cell; y < size.height + cell; y += cell) {
      for (double x = -cell; x < size.width + cell; x += cell) {
        if (rnd.nextDouble() < 0.28) continue;
        final w = cell * (0.42 + rnd.nextDouble() * 0.34);
        final h = cell * (0.42 + rnd.nextDouble() * 0.34);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 8, y + 8, w, h),
            const Radius.circular(3),
          ),
          block,
        );
      }
    }

    // 도로 — 밝은 선으로 블록 사이를 지난다.
    final road = Paint()
      ..color = const Color(0xFFFBF7F4)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (double y = 0; y < size.height + cell; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    for (double x = 0; x < size.width + cell; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }

    // 비네트 — 가장자리를 눌러 시트/카드가 더 떠 보이게 한다.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            Colors.transparent,
            AppColors.shadowBase.withValues(alpha: 0.10),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _MapBackdropPainter oldDelegate) => false;
}

/// 퀘스트 위치 마커 — 그림자와 접지 그림자(ground shadow)로 지도 위에 뜬다.
///
/// [size]는 마커의 **폭**이며, 실제 높이는 size * 1.32 이다.
class QuestMarker extends StatelessWidget {
  final bool isActive;
  final double size;

  /// 난이도 등급 색을 쓰고 싶을 때. null이면 기본(브랜드/종이) 배색.
  final QuestTierStyle? tier;

  const QuestMarker({
    super.key,
    this.isActive = false,
    this.size = 26,
    this.tier,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.25,
      height: size * 1.32 + size * 0.16,
      child: CustomPaint(
        painter: _MarkerPainter(
          isActive: isActive,
          fill: isActive
              ? (tier?.accent ?? AppColors.quest500)
              : AppColors.surface,
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  final bool isActive;
  final Color fill;

  _MarkerPainter({required this.isActive, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.8;
    final left = (size.width - w) / 2;
    final r = w / 2;
    final pinHeight = w * 1.32;
    final tipY = pinHeight;

    // 1. 접지 그림자 — 마커가 지면에서 떠 있음을 알린다.
    final groundRect = Rect.fromCenter(
      center: Offset(size.width / 2, tipY + w * 0.10),
      width: w * 0.62,
      height: w * 0.20,
    );
    canvas.drawOval(
      groundRect,
      Paint()
        ..color = AppColors.shadowBase.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 2. 핀 실루엣
    final path = Path()
      ..moveTo(left + r, tipY)
      ..cubicTo(left + r * 0.35, tipY - r * 0.75, left, r * 1.45, left, r)
      ..arcToPoint(Offset(left + w, r), radius: Radius.circular(r))
      ..cubicTo(
        left + w,
        r * 1.45,
        left + r * 1.65,
        tipY - r * 0.75,
        left + r,
        tipY,
      )
      ..close();

    // 3. 드롭 섀도우
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = AppColors.shadowBase.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // 4. 채움 — 위가 밝은 그라데이션
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(fill, Colors.white, isActive ? 0.22 : 0.0)!,
            isActive ? Color.lerp(fill, Colors.black, 0.12)! : fill,
          ],
        ).createShader(bounds),
    );

    // 5. 테두리 — 비활성 마커는 지도 위에서 사라지지 않도록 얇은 경계를 준다.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = isActive
            ? Colors.white.withValues(alpha: 0.55)
            : AppColors.ink300,
    );

    // 6. 안쪽 원 — 활성은 흰 점, 비활성은 브랜드색 점
    canvas.drawCircle(
      Offset(left + r, r),
      r * 0.34,
      Paint()
        ..color = isActive
            ? Colors.white.withValues(alpha: 0.95)
            : AppColors.quest500,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter old) =>
      old.isActive != isActive || old.fill != fill;
}

/// 줌아웃 시 겹친 마커를 묶는 클러스터 뱃지 (+n)
class MarkerCluster extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const MarkerCluster({super.key, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    final diameter = 34.0 + min(count, 40) * 0.45;

    return PressableScale(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppSurface.brandFill,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.65),
            width: 2,
          ),
          boxShadow: AppElevation.marker,
        ),
        child: Text(
          '+$count',
          style: AppType.numeric.copyWith(
            fontSize: 13,
            color: AppColors.textOnDark,
          ),
        ),
      ),
    );
  }
}
