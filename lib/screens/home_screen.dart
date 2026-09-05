import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/badge_api.dart';
import '../data/home_repository.dart';
import '../data/quest_repository.dart';
import '../dev/dev_tools.dart'; // DEV-ONLY
import '../models/active_quest.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/geo.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';
import '../widgets/badge_widgets.dart';

// -----------------------------------------------------------------------------
// 분기 B · 홈 화면
// -----------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final UserModel user;
  final List<ActiveQuest> activeQuests;
  final ValueChanged<ActiveQuest> onContinueQuest;
  final ValueChanged<QuestModel> onSelectQuest;
  final void Function(BuildContext context)? onOpenSettings;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenBadges;
  final VoidCallback? onOpenProfile;

  const HomeScreen({
    super.key,
    required this.user,
    required this.onContinueQuest,
    required this.onSelectQuest,
    this.activeQuests = const [],
    this.onOpenSettings,
    this.onOpenMap,
    this.onOpenBadges,
    this.onOpenProfile,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _carouselController;
  int _carouselIndex = 0;

  // 내 위치 기준 추천 3개.
  List<QuestModel> _nearbyQuests = [];
  bool _isLoadingNearby = true;
  double? _userLat;
  double? _userLng;

  /// 홈 3칸에 세울 배지 — **서버가 진실이다** (체크리스트 21번).
  List<BadgeSummary> _badges = const [];
  bool _isLoadingBadges = true;

  /// 서버를 못 불렀을 때. null이면 정상이다.
  ///
  /// 예전에는 실패하면 하드코딩된 목업 퀘스트로 갈아 끼웠다. 화면은 멀쩡해 보이지만
  /// 존재하지 않는 퀘스트가 뜨고, 누르면 그 id로 수락을 시도한다. 실패는 실패라고 말한다.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
    _loadHome();
  }

  /// 홈에 필요한 것을 **한 번에** 받는다 — 체크리스트 20번.
  ///
  /// 예전에는 `BadgeApi.list()`와 `fetchNearbyQuests()`를 따로 불렀다. 홈은 앱에서
  /// 가장 자주 열리는 화면이라 그 왕복 수가 그대로 체감 속도가 된다.
  ///
  /// 위치는 서버로 넘겨 **가까운 순**으로 받는다. 권한을 아직 안 줬으면 좌표 없이
  /// 보내고, 그때는 키워드·홈지역 기준 추천이 온다 — 홈이 비어 보이지 않게 하려는 것이다.
  Future<void> _loadHome() async {
    double? lat;
    double? lng;

    try {
      final pos = await PermissionService.currentPosition();
      final override = DevTools.locationOverride;
      lat = override?.latitude ?? pos?.latitude;
      lng = override?.longitude ?? pos?.longitude;
    } catch (_) {
      // 위치를 못 잡아도 홈은 뜬다. 거리 표기만 흐려질 뿐이다.
    }

    if (lat != null && lng != null) {
      // 거리 표기와 검색 정렬이 같은 기준을 보도록 알려 둔다.
      QuestRepository.updateUserLocation(lat, lng);
    }

    try {
      final summary = await HomeRepository.fetchSummary(lat: lat, lng: lng);

      if (!mounted) return;
      setState(() {
        _userLat = lat;
        _userLng = lng;
        _nearbyQuests = summary.recommendedQuests
            .where((q) => !widget.user.hasCompleted(q.id))
            .take(3)
            .toList();
        _badges = summary.badges;
        _loadFailed = false;
        _isLoadingNearby = false;
        _isLoadingBadges = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _userLat = lat;
        _userLng = lng;
        _nearbyQuests = const [];
        _loadFailed = true;
        _isLoadingNearby = false;
        _isLoadingBadges = false;
      });
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = widget.activeQuests.length - 1;
    if (_carouselIndex > maxIndex) {
      _carouselIndex = maxIndex < 0 ? 0 : maxIndex;
      if (_carouselController.hasClients && maxIndex >= 0) {
        _carouselController.jumpToPage(_carouselIndex);
      }
    }
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  void _moveCarousel(int delta) {
    final count = widget.activeQuests.length;
    if (count <= 1) return;
    final next = (_carouselIndex + delta + count) % count;
    _carouselController.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _notReady(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 화면은 준비 중입니다.')),
    );
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
            Expanded(
              child: RefreshIndicator(
                color: AppColors.quest500,
                onRefresh: _loadHome,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.lg,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.activeQuests.isEmpty)
                        _buildEmptyQuestCard()
                      else
                        _buildActiveQuestCarousel(),
                      const SizedBox(height: AppSpacing.xxl),
                      SectionHeader(
                        title: '내 주변 추천 퀘스트',
                        trailingText: '새로고침',
                        onTapTrailing: () {
                          setState(() {
                            _isLoadingNearby = true;
                            _isLoadingBadges = true;
                          });
                          _loadHome();
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_isLoadingNearby)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.quest500,
                              ),
                            ),
                          ),
                        )
                      else if (_loadFailed)
                        _buildLoadError()
                      else if (_nearbyQuests.isEmpty)
                        NoteBox.text('주변에 추천할 퀘스트가 없어요. 지도를 움직여 다른 지역을 살펴보세요.',
                            fontSize: 12)
                      else
                        for (final quest in _nearbyQuests)
                          _buildRecommendedRow(quest),
                      const SizedBox(height: AppSpacing.xxl),
                      SectionHeader(
                        title: '내 대표 배지',
                        trailingText: '전체보기 ›',
                        accent: AppColors.jade500,
                        onTapTrailing:
                            widget.onOpenBadges ?? () => _notReady('배지'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_isLoadingBadges)
                        _buildBadgeRow(const [])
                      else if (_badges.isEmpty)
                        NoteBox.text(
                          '아직 획득한 배지가 없어요. 첫 퀘스트를 완료하면 배지가 생겨요',
                          fontSize: 12,
                          textAlign: TextAlign.center,
                        )
                      else
                        _buildBadgeRow(_badges),
                    ],
                  ),
                ),
              ),
            ),
            AppBottomNav(
              current: AppTab.home,
              onSelect: (tab) {
                if (tab == AppTab.map) {
                  (widget.onOpenMap ?? () => _notReady('지도'))();
                } else if (tab == AppTab.badges) {
                  (widget.onOpenBadges ?? () => _notReady('배지'))();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveQuestCarousel() {
    final quests = widget.activeQuests;

    return AppCard(
      gradient: AppSurface.highlight,
      shadow: AppElevation.e3,
      accentEdge: AppColors.quest500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('진행 중 퀘스트', style: AppType.h3)),
              Text(
                '${_carouselIndex + 1} / ${quests.length}',
                style: AppType.numeric.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _buildCarouselArrow(
                  '‹', () => _moveCarousel(-1), quests.length > 1),
              Expanded(
                child: SizedBox(
                  // PageView는 높이를 스스로 못 정해서 여기서 잡아 줘야 한다.
                  //
                  // 고정 104는 좁은 화면에서 제목이 두 줄로 접히는 순간 모자랐다
                  // (320×568에서 30px 넘침). 글자 크기를 키운 기기에서도 같은 일이
                  // 난다 — 카드 안이 전부 글자라 배율을 그대로 따라간다.
                  height: 104 *
                      MediaQuery.textScalerOf(context)
                          .scale(1.0)
                          .clamp(1.0, 1.4),
                  child: PageView.builder(
                    controller: _carouselController,
                    itemCount: quests.length,
                    onPageChanged: (index) =>
                        setState(() => _carouselIndex = index),
                    itemBuilder: (context, index) =>
                        _buildActiveQuestCard(quests[index]),
                  ),
                ),
              ),
              _buildCarouselArrow(
                  '›', () => _moveCarousel(1), quests.length > 1),
            ],
          ),
          const SizedBox(height: 9),
          if (quests.length > 1)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < quests.length; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _carouselIndex
                            ? AppColors.quest500
                            : AppColors.ink300,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: '이어서 하기',
            fontSize: 13,
            padding: const EdgeInsets.symmetric(vertical: 9),
            onTap: () => widget.onContinueQuest(quests[_carouselIndex]),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselArrow(String glyph, VoidCallback onTap, bool enabled) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 20,
            color: enabled ? AppColors.textPrimary : AppColors.ink300,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveQuestCard(ActiveQuest active) {
    final quest = active.quest;
    final double distanceMeters;
    if (_userLat != null && _userLng != null) {
      distanceMeters = Geolocator.distanceBetween(
        _userLat!,
        _userLng!,
        active.currentSpot.point.latitude,
        active.currentSpot.point.longitude,
      );
    } else {
      distanceMeters = Geo.distanceMeters(
          QuestRepository.defaultMapCenter, active.currentSpot.point);
    }

    final isNear = active.progress >= 0.85;

    // 320px 폭 기기에서는 이 카드 안쪽이 250px 남짓이다. 등급 상자와 제목 두 줄을
    // 그대로 두면 가로로 20px, 세로로 30px 넘쳤다. 좁으면 둘 다 한 단계 줄인다.
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 260;

      return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: isNarrow ? 56 : 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppSurface.sunken,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: TierBadge(
            stars: quest.difficulty.stars,
            hasHalfStar: quest.hasHalfStar,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                quest.title,
                maxLines: isNarrow ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.h3,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  RewardPill(exp: quest.displayExp),
                  const SizedBox(width: AppSpacing.sm),
                  // 좁은 화면에서는 EXP 배지가 먼저고 거리는 줄어들어도 된다.
                  Flexible(
                    child: Text(
                      Geo.formatDistance(distanceMeters),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.numeric.copyWith(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ProgressBar(
                value: active.progress,
                accent: isNear ? AppColors.jade500 : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                active.progressLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro,
              ),
            ],
          ),
        ),
      ],
      );
    });
  }

  Widget _buildEmptyQuestCard() {
    return AppCard(
      gradient: AppSurface.highlight,
      shadow: AppElevation.e3,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppSurface.paper,
              boxShadow: AppElevation.e1,
            ),
            child: const Icon(Icons.explore_outlined,
                color: AppColors.quest500, size: 26),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('진행 중인 퀘스트가 없어요', style: AppType.h3),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '아래 추천이나 지도에서 마음에 드는 걸 골라보세요.',
            textAlign: TextAlign.center,
            style: AppType.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: '지도에서 찾아보기',
            fontSize: 13,
            padding: const EdgeInsets.symmetric(vertical: 10),
            onTap: widget.onOpenMap ?? () => _notReady('지도'),
          ),
        ],
      ),
    );
  }

  /// 추천을 못 받아 왔을 때. 조용히 넘어가지 않고 다시 시도할 길을 준다.
  Widget _buildLoadError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoteBox.text(
          '주변 퀘스트를 불러오지 못했어요. 네트워크를 확인해 주세요.',
          fontSize: 12,
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: () {
            setState(() {
              _isLoadingNearby = true;
              _isLoadingBadges = true;
            });
            _loadHome();
          },
          child: const Text(
            '다시 시도',
            style: TextStyle(color: AppColors.quest500, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedRow(QuestModel quest) {
    String distanceStr;
    if (_userLat != null && _userLng != null && quest.spots.isNotEmpty) {
      final meters = Geolocator.distanceBetween(
        _userLat!,
        _userLng!,
        quest.spots.first.point.latitude,
        quest.spots.first.point.longitude,
      );
      distanceStr = Geo.formatDistance(meters);
    } else {
      distanceStr = QuestRepository.distanceFromUser(quest);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: () => widget.onSelectQuest(quest),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            TierBadge(
              stars: quest.difficulty.stars,
              hasHalfStar: quest.hasHalfStar,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.h3,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${quest.spotName} · $distanceStr',
                    style: AppType.caption,
                  ),
                  const SizedBox(height: 5),
                  // 난이도(별)만 보이던 줄에 "무엇을 하는 퀘스트인지"를 더한다.
                  QuestTypeBadge(questType: quest.questType),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            RewardPill(exp: quest.displayExp),
          ],
        ),
      ),
    );
  }

  /// 대표 배지는 3칸 고정. 아직 못 채운 칸은 배지 화면으로 가는 빈 슬롯으로 둔다.
  Widget _buildBadgeRow(List<BadgeSummary> badges) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: i < badges.length
                  ? _buildBadgeSlot(badges[i])
                  : _buildEmptyBadgeSlot(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBadgeSlot(BadgeSummary badge) {
    return PressableScale(
      onTap: widget.onOpenBadges ?? () => _notReady('배지'),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.jade50,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppElevation.e1,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BadgeArt(artKey: badge.artKey, size: 26),
            const SizedBox(height: AppSpacing.xs),
            Text(
              badge.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro.copyWith(color: AppColors.jade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBadgeSlot() {
    return PressableScale(
      onTap: widget.onOpenBadges ?? () => _notReady('배지'),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppSurface.sunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.add_rounded,
            size: 20, color: AppColors.textDisabled),
      ),
    );
  }
}