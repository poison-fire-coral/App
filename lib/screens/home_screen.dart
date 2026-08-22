import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../dev/dev_tools.dart'; // DEV-ONLY
import '../services/permission_service.dart';

import '../data/badge_repository.dart';
import '../data/quest_repository.dart';
import '../models/active_quest.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/geo.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

// -----------------------------------------------------------------------------
// 분기 B · 홈 화면
// 진행 중 퀘스트가 있으면 2a(캐러셀), 없으면 2b(빈 상태 CTA)로 갈린다.
// -----------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final UserModel user;
  final List<ActiveQuest> activeQuests;
  final List<QuestModel> recommendedQuests;
  final List<BadgeProgress> badges;
  final ValueChanged<ActiveQuest> onContinueQuest;
  final ValueChanged<QuestModel> onSelectQuest;
  final void Function(BuildContext context)? onOpenSettings;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenBadges;

  /// 좌상단 프로필 링을 눌렀을 때 (5c)
  final VoidCallback? onOpenProfile;

  const HomeScreen({
    super.key,
    required this.user,
    required this.onContinueQuest,
    required this.onSelectQuest,
    this.activeQuests = const [],
    this.recommendedQuests = const [],
    this.badges = const [],
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

  // Real-time nearest 3 quests state
  List<QuestModel> _nearbyQuests = [];
  bool _isLoadingNearby = true;
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
    _loadNearbyQuests();
  }

/// 백엔드 API를 호출하여 내 위치 기준 가장 가까운 퀘스트 3개를 로드합니다.
  Future<void> _loadNearbyQuests() async {
    try {
      // 1. 권한을 확인하고 현재 위치를 얻는다(팝업은 온보딩에서 이미 거쳤다).
      final pos = await PermissionService.currentPosition();

      // DEV-ONLY: 위치 고정이 켜져 있으면 그 좌표를 쓴다.
      final override = DevTools.locationOverride;

      final lat = override?.latitude ??
          pos?.latitude ??
          QuestRepository.mockUserLocation.latitude;
      final lng = override?.longitude ??
          pos?.longitude ??
          QuestRepository.mockUserLocation.longitude;

      // 2. 백엔드에서 거리순 정렬된 내 주변 퀘스트 수집
      final quests = await QuestRepository.fetchNearbyQuests(lat: lat, lng: lng);

      if (mounted) {
        setState(() {
          _userLat = lat;
          _userLng = lng;
          // 가장 가까운 퀘스트 최대 3개만 추출
          _nearbyQuests = quests.take(3).toList();
          _isLoadingNearby = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // API 실패 시 기본 전달받은 추천 목록 중 3개 사용
          _nearbyQuests = widget.recommendedQuests.take(3).toList();
          _isLoadingNearby = false;
        });
      }
    }
  }
  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 퀘스트를 완료·포기해 목록이 줄면 캐러셀 인덱스를 범위 안으로 되돌린다.
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
    final earnedBadges = widget.badges.where((b) => b.isEarned).take(3).toList();
    final displayQuests = _nearbyQuests.isNotEmpty ? _nearbyQuests : widget.recommendedQuests.take(3).toList();

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
              child: SingleChildScrollView(
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
                        setState(() => _isLoadingNearby = true);
                        _loadNearbyQuests();
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
                                strokeWidth: 2, color: AppColors.quest500),
                          ),
                        ),
                      )
                    else if (displayQuests.isEmpty)
                      NoteBox.text('주변에 추천할 퀘스트가 없어요. 지도를 움직여 다른 지역을 살펴보세요.', fontSize: 12)
                    else
                      for (final quest in displayQuests) _buildRecommendedRow(quest),
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: '내 대표 배지',
                      trailingText: '전체보기 ›',
                      // 배지는 '완료'의 축이라 jade를 쓴다 (디자인 시스템 02 역할 색)
                      accent: AppColors.jade500,
                      onTapTrailing: widget.onOpenBadges ?? () => _notReady('배지'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (earnedBadges.isEmpty)
                      NoteBox.text(
                        '아직 획득한 배지가 없어요. 첫 퀘스트를 완료하면 배지가 생겨요',
                        fontSize: 12,
                        textAlign: TextAlign.center,
                      )
                    else
                      _buildBadgeRow(earnedBadges),
                  ],
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

  // ---------------------------------------------------------------------------
  // 2a · 진행 중 퀘스트 캐러셀
  // ---------------------------------------------------------------------------
  Widget _buildActiveQuestCarousel() {
    final quests = widget.activeQuests;

    // 디자인 시스템 11: 홈에서 e3를 쓰는 곳은 여기 하나뿐이다.
    // 전부 떠 있으면 아무것도 떠 있지 않다 (01 원칙 3).
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
              _buildCarouselArrow('‹', () => _moveCarousel(-1), quests.length > 1),
              Expanded(
                child: SizedBox(
                  height: 104,
                  child: PageView.builder(
                    controller: _carouselController,
                    itemCount: quests.length,
                    onPageChanged: (index) => setState(() => _carouselIndex = index),
                    itemBuilder: (context, index) => _buildActiveQuestCard(quests[index]),
                  ),
                ),
              ),
              _buildCarouselArrow('›', () => _moveCarousel(1), quests.length > 1),
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
                        color: i == _carouselIndex ? AppColors.quest500 : AppColors.ink300,
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
      distanceMeters = Geo.distanceMeters(QuestRepository.mockUserLocation, active.currentSpot.point);
    }

    // 목표에 가까워질수록 진행바가 quest → jade 로 넘어간다 (디자인 시스템 11).
    final isNear = active.progress >= 0.85;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 대표사진 자리. 아직 이미지 소스가 없으므로 난이도 등급을 대신 세운다.
        Container(
          width: 76,
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.h3,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  RewardPill(exp: quest.displayExp),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    Geo.formatDistance(distanceMeters),
                    style: AppType.numeric.copyWith(
                      fontSize: 11,
                      color: AppColors.textTertiary,
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
              Text(active.progressLabel, style: AppType.micro),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2b · 진행 중 퀘스트 빈 상태 카드
  // ---------------------------------------------------------------------------
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

    // 목록에서 반복되는 표면은 e2 (디자인 시스템 03 · 11).
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
              showLabel: false,
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
  Widget _buildBadgeRow(List<BadgeProgress> badges) {
    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: i < badges.length ? _buildBadgeSlot(badges[i]) : _buildEmptyBadgeSlot(),
            ),
          ),
        ],
      ],
    );
  }

  /// 획득한 배지는 '완료'의 축이라 jade로 칠한다 (디자인 시스템 02).
  Widget _buildBadgeSlot(BadgeProgress badge) {
    return Container(
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
          const Icon(Icons.workspace_premium_outlined,
              size: 22, color: AppColors.jade500),
          const SizedBox(height: AppSpacing.xs),
          Text(
            badge.rule.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro.copyWith(color: AppColors.jade700),
          ),
        ],
      ),
    );
  }

  /// 빈 칸은 눌러 새긴 면으로 내려간다. 볼록(획득)과 오목(미획득)이 짝을 이룬다.
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