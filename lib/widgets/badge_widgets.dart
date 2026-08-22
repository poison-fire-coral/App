import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/badge_api.dart';
import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'app_widgets.dart';

/// 배지 아트 한 장.
///
/// 아트 키를 모르면(미공개 배지라 서버가 가렸거나, 앱이 모르는 키면)
/// 자물쇠로 대신 그린다. 화면이 비지 않게 하는 게 우선이다.
class BadgeArt extends StatelessWidget {
  final String? artKey;
  final double size;

  /// 미획득 배지는 채도를 빼서 "아직 내 것이 아님"을 색으로 말한다.
  final bool dimmed;

  const BadgeArt({
    super.key,
    required this.artKey,
    this.size = 64,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final path = AppAssets.badgeArtPath(artKey);

    if (path == null) {
      return _LockedArt(size: size);
    }

    final art = SvgPicture.asset(
      path,
      width: size,
      height: size,
      placeholderBuilder: (_) => _LockedArt(size: size),
    );

    if (!dimmed) return art;

    // 흑백으로 눕히고 살짝 투명하게. 형태는 남아서 무엇인지는 알아볼 수 있다.
    return Opacity(
      opacity: 0.45,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: art,
      ),
    );
  }
}

class _LockedArt extends StatelessWidget {
  final double size;
  const _LockedArt({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppSurface.sunken,
      ),
      child: Text(
        '?',
        style: AppType.h1.copyWith(
          fontSize: size * 0.4,
          color: AppColors.textDisabled,
        ),
      ),
    );
  }
}

/// 5a 그리드의 한 칸. 세 상태를 형태로 구분한다 — 색만 다르면 색약 사용자가 못 읽는다.
///
///   획득    볼록한 카드(e1) + 또렷한 아트 + 이름
///   진행 중 볼록한 카드 + 흐린 아트 + `2 / 5` 카운터 + 진행바
///   미공개  오목한 면(sunken) + 자물쇠
class BadgeGridTile extends StatelessWidget {
  final BadgeSummary badge;
  final VoidCallback? onTap;

  const BadgeGridTile({super.key, required this.badge, this.onTap});

  @override
  Widget build(BuildContext context) {
    final locked = badge.state == BadgeState.locked;
    final achieved = badge.state == BadgeState.achieved;

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          gradient: locked ? AppSurface.sunken : AppSurface.paper,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: locked ? null : AppElevation.e1,
          border: badge.isFeatured
              ? Border.all(color: AppColors.quest500, width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BadgeArt(
              artKey: badge.artKey,
              size: 46,
              dimmed: !achieved,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              badge.displayName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro.copyWith(
                color: achieved
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
            if (badge.state == BadgeState.inProgress) ...[
              const SizedBox(height: 3),
              Text(
                badge.progressLabel,
                style: AppType.numeric.copyWith(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 40,
                child: ProgressBar(
                  value: badge.ratio,
                  height: 4,
                  accent: AppColors.jade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
