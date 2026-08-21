import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import 'app_widgets.dart';

/// 아바타 프리셋 한 개를 원형으로 그린다.
///
/// SVG 자체가 이미 원형 배경과 헤어라인을 품고 있으므로 여기서 테두리를 덧대지 않는다.
/// (디자인 시스템 01 — "1.5px 검정 테두리를 없앤다")
class AppAvatar extends StatelessWidget {
  final String? avatarId;
  final double size;

  const AppAvatar({super.key, required this.avatarId, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        AppAssets.avatarPath(avatarId),
        width: size,
        height: size,
        // 자산이 없거나 파싱에 실패해도 화면이 깨지지 않게 종이색 원으로 떨어뜨린다.
        placeholderBuilder: (_) => DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppSurface.paper,
          ),
        ),
      ),
    );
  }
}

/// 온보딩 1d — 프리셋 6종 중 하나를 고르는 줄.
///
/// 선택은 테두리가 아니라 **떠오름**으로 표시한다(05 표면 · 03 깊이).
/// 선택된 항목만 e2 그림자와 붉은 링을 갖고 살짝 커진다.
class AvatarPickerRow extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onSelected;

  const AvatarPickerRow({
    super.key,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        itemCount: AppAssets.avatarIds.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final id = AppAssets.avatarIds[index];
          final isSelected = id == selectedId;

          return PressableScale(
            onTap: () => onSelected(id),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              width: isSelected ? 68 : 60,
              height: isSelected ? 68 : 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: isSelected ? AppElevation.e2 : AppElevation.e1,
                border: isSelected
                    ? Border.all(color: AppColors.quest500, width: 2.5)
                    : null,
              ),
              child: AppAvatar(avatarId: id, size: isSelected ? 60 : 56),
            ),
          );
        },
      ),
    );
  }
}
