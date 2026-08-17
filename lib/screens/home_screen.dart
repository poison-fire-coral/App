import 'package:flutter/material.dart';

import '../data/badge_repository.dart';
import '../data/quest_repository.dart';
import '../models/active_quest.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/geo.dart';
import '../theme/app_colors.dart';
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
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _carouselController;
  int _carouselIndex = 0;

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
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

    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              nickname: widget.user.nickname,
              level: widget.user.level,
              levelProgress: widget.user.levelProgress,
              onTapProfile: () => _notReady('프로필'),
              onTapSettings: () => widget.onOpenSettings?.call(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.activeQuests.isEmpty)
                      _buildEmptyQuestCard()
                    else
                      _buildActiveQuestCarousel(),
                    const SizedBox(height: 18),
                    const Text(
                      '내 주변 추천 퀘스트',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                    ),
                    const SizedBox(height: 8),
                    if (widget.recommendedQuests.isEmpty)
                      NoteBox.text('주변에 추천할 퀘스트가 없어요. 지도를 움직여 다른 지역을 살펴보세요.', fontSize: 12)
                    else
                      for (final quest in widget.recommendedQuests) _buildRecommendedRow(quest),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '내 대표 배지',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                          ),
                        ),
                        TagChip(
                          label: '전체보기 ›',
                          fontSize: 11,
                          onTap: widget.onOpenBadges ?? () => _notReady('배지'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.highlightBg,
        border: Border.all(color: AppColors.darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '진행 중 퀘스트',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                ),
              ),
              Text(
                '${_carouselIndex + 1} / ${quests.length}',
                style: const TextStyle(fontSize: 12, color: AppColors.subText),
              ),
            ],
          ),
          const SizedBox(height: 9),
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
                        color: i == _carouselIndex ? AppColors.primaryRed : AppColors.dotInactive,
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
            color: enabled ? AppColors.darkBorder : AppColors.dotInactive,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveQuestCard(ActiveQuest active) {
    final quest = active.quest;
    final distance = Geo.distanceMeters(QuestRepository.mockUserLocation, active.currentSpot.point);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.bgCream,
            border: Border.all(color: AppColors.noteBorder, width: 1.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Text(
            '퀘스트\n대표사진',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.noteText, height: 1.3),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                quest.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.darkBorder, height: 1.25),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  TagChip(label: quest.starLabel, fontSize: 11),
                  const SizedBox(width: 5),
                  Text(
                    Geo.formatDistance(distance),
                    style: const TextStyle(fontSize: 11, color: AppColors.subText),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ProgressBar(value: active.progress),
              const SizedBox(height: 4),
              Text(
                active.progressLabel,
                style: const TextStyle(fontSize: 11, color: AppColors.subText),
              ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.highlightBg,
        border: Border.all(color: AppColors.darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bgCream),
            child: const Icon(Icons.explore_outlined, color: AppColors.primaryRed, size: 26),
          ),
          const SizedBox(height: 10),
          const Text(
            '진행 중인 퀘스트가 없어요',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
          ),
          const SizedBox(height: 6),
          const Text(
            '아래 추천 목록이나 지도에서 퀘스트를 수락하면\n여기에 캐러셀 카드로 표시돼요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.subText, height: 1.4),
          ),
          const SizedBox(height: 12),
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
    final distance = QuestRepository.distanceFromUser(quest);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => widget.onSelectQuest(quest),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkBorder, width: 1.5),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            '🎯 ${quest.title} · ${Geo.formatDistance(distance)} · ${quest.starLabel}',
            style: const TextStyle(fontSize: 13, color: AppColors.darkBorder),
          ),
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

  Widget _buildBadgeSlot(BadgeProgress badge) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.highlightBg,
        border: Border.all(color: AppColors.darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        badge.rule.name,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: AppColors.darkBorder, height: 1.25),
      ),
    );
  }

  Widget _buildEmptyBadgeSlot() {
    return GestureDetector(
      onTap: widget.onOpenBadges ?? () => _notReady('배지'),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.noteBorder, width: 1.5),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Text('+', style: TextStyle(fontSize: 16, color: AppColors.noteText)),
      ),
    );
  }
}
