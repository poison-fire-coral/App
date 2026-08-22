import 'package:flutter/material.dart';

import '../data/badge_api.dart';
import '../models/api_exception.dart';
import '../models/user_model.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';
import '../widgets/badge_widgets.dart';
import 'badge_detail_screen.dart';

/// 5a · 배지 컬렉션
///
/// 획득 / 진행 중 / 미공개 세 상태를 한 그리드에 놓는다.
/// 필터는 지역별·유형별 — 배지 규칙의 두 축과 같다.
class BadgeScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenMap;
  final void Function(BuildContext context)? onOpenSettings;
  final VoidCallback? onOpenProfile;

  const BadgeScreen({
    super.key,
    required this.user,
    this.onOpenHome,
    this.onOpenMap,
    this.onOpenSettings,
    this.onOpenProfile,
  });

  @override
  State<BadgeScreen> createState() => _BadgeScreenState();
}

/// 필터 한 칸. 라벨과 질의 조건을 함께 들고 다닌다.
class _Filter {
  final String label;
  final String? region;
  final String? questType;
  const _Filter(this.label, {this.region, this.questType});
}

class _BadgeScreenState extends State<BadgeScreen> {
  static const List<_Filter> _filters = [
    _Filter('전체'),
    _Filter('경기', region: '경기'),
    _Filter('서울', region: '서울'),
    _Filter('제주', region: '제주'),
    _Filter('사진', questType: 'PHOTO_SINGLE'),
    _Filter('수집', questType: 'PHOTO_COLLECT'),
    _Filter('퀴즈', questType: 'QUIZ'),
    _Filter('탐색', questType: 'EXPLORATION'),
    _Filter('시간대', questType: 'TIME_WINDOW'),
    _Filter('기록', questType: 'RECORD'),
  ];

  int _filterIndex = 0;
  BadgeListResult? _result;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final filter = _filters[_filterIndex];
    try {
      final result = await BadgeApi.list(
        region: filter.region,
        questType: filter.questType,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
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

  Future<void> _openDetail(BadgeSummary badge) async {
    // 미공개 배지는 서버가 상세를 막는다. 눌러도 조용히 안내만 한다.
    if (badge.state == BadgeState.locked && badge.hidden) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('아직 공개되지 않은 배지예요.')),
        );
      return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BadgeDetailScreen(badgeId: badge.badgeId),
      ),
    );
    // 대표 배지를 바꿨으면 목록의 테두리 표시가 달라진다.
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              nickname: widget.user.nickname,
              level: widget.user.level,
              levelProgress: widget.user.levelProgress,
              avatarId: widget.user.avatarId,
              onTapProfile: widget.onOpenProfile,
              onTapSettings: () => widget.onOpenSettings?.call(context),
            ),
            Expanded(child: _buildBody()),
            AppBottomNav(
              current: AppTab.badges,
              onSelect: (tab) {
                if (tab == AppTab.home) widget.onOpenHome?.call();
                if (tab == AppTab.map) widget.onOpenMap?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final result = _result;

    return RefreshIndicator(
      color: AppColors.quest500,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          // 상단 요약 — 몇 개를 모았는지
          Row(
            children: [
              Expanded(
                child: Text(
                  result?.headline ?? '배지',
                  style: AppType.h1,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ProgressBar(
            value: result?.ratio ?? 0,
            accent: AppColors.jade500,
          ),
          const SizedBox(height: AppSpacing.lg),

          // 필터 칩 — 규칙의 두 축(지역·유형)과 같은 기준
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) => Center(
                child: TagChip(
                  label: _filters[index].label,
                  isSelected: index == _filterIndex,
                  accent: _filters[index].questType != null
                      ? AppColors.amber500
                      : _filters[index].region != null
                          ? AppColors.lapis500
                          : null,
                  onTap: () {
                    setState(() => _filterIndex = index);
                    _load();
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.quest500,
                ),
              ),
            )
          else if (_error != null)
            NoteBox.text(_error!)
          else if (result == null || result.items.isEmpty)
            NoteBox.text('이 조건에 맞는 배지가 없어요.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.82,
              ),
              itemCount: result.items.length,
              itemBuilder: (context, index) {
                final badge = result.items[index];
                return BadgeGridTile(
                  badge: badge,
                  onTap: () => _openDetail(badge),
                );
              },
            ),

          const SizedBox(height: AppSpacing.lg),
          Text(
            '배지를 눌러 어떤 퀘스트로 채웠는지 볼 수 있어요.',
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
