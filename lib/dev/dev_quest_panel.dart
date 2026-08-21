import 'package:flutter/material.dart';

import '../services/geo.dart';
import '../services/geolocator_location_service.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';
import 'dev_tools.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// DEV-ONLY — 4a 이동 화면에 붙는 테스트 패널
///
/// 개발 중에는 실제로 수원까지 걸어갈 수 없다. 이 패널이 내 좌표를 목표 지점으로
/// 옮겨주면, **그 좌표가 그대로 서버 verify로 전송되어 거리 검증을 정상 통과한다.**
/// 서버를 우회하는 게 아니라 서버가 믿을 수 있는 유일한 값(클라이언트가 보낸 좌표)을
/// 바꾸는 것이라, EXP·레벨업 로직이 진짜로 돈다. 백엔드 수정이 필요 없다.
///
/// 제거는 `lib/dev/` 삭제 + `grep -rn "DEV-ONLY" lib/`.
/// ─────────────────────────────────────────────────────────────────────────────
class DevQuestPanel extends StatelessWidget {
  final LocationService locationService;
  final GeoPoint target;
  final double targetRadiusMeters;

  /// 순간이동 → 인증까지 한 번에. 회귀 테스트용.
  final VoidCallback? onRunFullCycle;

  const DevQuestPanel({
    super.key,
    required this.locationService,
    required this.target,
    required this.targetRadiusMeters,
    this.onRunFullCycle,
  });

  GeolocatorLocationService? get _gps {
    final service = locationService;
    return service is GeolocatorLocationService ? service : null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DevTools.enabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: SecondaryButton(
            label: '개발 도구',
            icon: Icons.bug_report_outlined,
            onTap: () => _openSheet(context),
          ),
        );
      },
    );
  }

  void _openSheet(BuildContext context) {
    final gps = _gps;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const GrabHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                '위치를 위조해 서버 인증 경로를 그대로 시험합니다.',
                style: AppType.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
            if (gps == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('실제 GPS 서비스가 아니라 조작할 수 없어요.'),
              )
            else ...[
              _tile(
                icon: Icons.bolt_rounded,
                color: AppColors.quest500,
                title: '목표 지점으로 순간이동',
                subtitle: '인증 버튼이 활성화되고 서버 거리 검증을 통과합니다',
                onTap: () {
                  gps.clearOverrides();
                  gps.teleportTo(target);
                  Navigator.pop(sheetContext);
                },
              ),
              _tile(
                icon: Icons.near_me_outlined,
                color: AppColors.lapis500,
                title: '반경 바로 밖으로 (${(targetRadiusMeters + 50).round()}m)',
                subtitle: '서버 OUT_OF_RANGE 응답을 재현합니다',
                onTap: () {
                  gps.clearOverrides();
                  gps.teleportNear(target, targetRadiusMeters + 50);
                  Navigator.pop(sheetContext);
                },
              ),
              _tile(
                icon: Icons.gps_off_rounded,
                color: AppColors.amber700,
                title: 'GPS 정확도 150m로 강제',
                subtitle: '재측정 안내와 서버 ACCURACY_TOO_LOW를 재현합니다',
                onTap: () {
                  gps.teleportTo(target);
                  gps.forceAccuracy(150);
                  Navigator.pop(sheetContext);
                },
              ),
              _tile(
                icon: Icons.restart_alt_rounded,
                color: AppColors.textTertiary,
                title: '위조 해제',
                subtitle: '실제 GPS로 되돌립니다',
                onTap: () {
                  gps.clearOverrides();
                  Navigator.pop(sheetContext);
                },
              ),
              if (onRunFullCycle != null) ...[
                const Divider(height: 1, color: AppColors.divider),
                _tile(
                  icon: Icons.fast_forward_rounded,
                  color: AppColors.jade500,
                  title: '원터치 완주',
                  subtitle: '순간이동 → 인증 → 보상 화면까지 한 번에',
                  onTap: () {
                    gps.clearOverrides();
                    gps.teleportTo(target);
                    Navigator.pop(sheetContext);
                    onRunFullCycle!();
                  },
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: AppType.h3),
        subtitle: Text(subtitle, style: AppType.caption),
        onTap: onTap,
      );
}
