import 'package:flutter/material.dart';

import '../data/badge_api.dart';
import '../models/api_exception.dart';
import '../models/user_model.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';
import '../widgets/badge_widgets.dart';

/// 5c · 프로필 · 대표 배지
///
/// 통계와 발자국은 **서버가 센 값**을 쓴다. 예전에는 앱이 완료 목록을
/// SharedPreferences에만 들고 있어서 기기를 바꾸면 사라졌다.
class ProfileScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onOpenBadges;
  final VoidCallback onBack;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onBack,
    this.onOpenBadges,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileSummary? _summary;
  List<FeaturedBadge> _featured = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        BadgeApi.profileSummary(),
        BadgeApi.featured(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ProfileSummary;
        _featured = results[1] as List<FeaturedBadge>;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.displayMessage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  top: AppSpacing.sm,
                ),
                child: IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.textSecondary,
                  tooltip: '홈으로',
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final user = widget.user;
    final summary = _summary;

    return RefreshIndicator(
      color: AppColors.quest500,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          // 프로필 머리
          Row(
            children: [
              ProfileRing(
                progress: user.levelProgress,
                avatarId: user.avatarId,
                size: 76,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.nickname, style: AppType.h1),
                    const SizedBox(height: 2),
                    Text(
                      'Lv.${user.level} · 다음 레벨까지 ${user.expToNextLevel} EXP',
                      style: AppType.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // 통계 3칸
          if (_isLoading)
            const SizedBox(
              height: 74,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.quest500,
                ),
              ),
            )
          else if (_error != null)
            NoteBox.text(_error!)
          else
            Row(
              children: [
                _StatTile(label: '완료', value: summary!.completed),
                const SizedBox(width: AppSpacing.md),
                _StatTile(
                  label: '지역',
                  value: summary.regions,
                  accent: AppColors.lapis500,
                ),
                const SizedBox(width: AppSpacing.md),
                _StatTile(
                  label: '배지',
                  value: summary.badges,
                  accent: AppColors.jade500,
                ),
              ],
            ),

          const SizedBox(height: AppSpacing.xxl),
          SectionHeader(
            title: '대표 배지',
            trailingText: '전체보기 ›',
            accent: AppColors.jade500,
            onTapTrailing: widget.onOpenBadges,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildFeaturedRow(),

          if (summary != null && summary.footprints.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(title: '최근 발자국'),
            const SizedBox(height: AppSpacing.md),
            for (final f in summary.footprints.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.questTitle, style: AppType.h3),
                            const SizedBox(height: 2),
                            Text(
                              [
                                _formatDate(f.date),
                                if (f.regionCode != null) f.regionCode!,
                                if (f.placeName != null) f.placeName!,
                              ].join(' · '),
                              style: AppType.caption,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      RewardPill(exp: f.expAwarded),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 3칸 고정. 비어 있으면 안내 문구를 띄운다 (의뢰서 S4 FE 7).
  Widget _buildFeaturedRow() {
    if (_featured.isEmpty) {
      return NoteBox.text('아직 대표 배지가 없어요. 배지를 모아보세요.');
    }

    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: i < _featured.length
                  ? Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        gradient: AppSurface.paper,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppElevation.e1,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          BadgeArt(artKey: _featured[i].artKey, size: 44),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _featured[i].name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.micro,
                          ),
                        ],
                      ),
                    )
                  : PressableScale(
                      onTap: widget.onOpenBadges,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppSurface.sunken,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(Icons.add_rounded,
                            size: 20, color: AppColors.textDisabled),
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color? accent;

  const _StatTile({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: [
            Text(label, style: AppType.micro),
            const SizedBox(height: 2),
            Text(
              '$value',
              style: AppType.h1.copyWith(
                color: accent ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
