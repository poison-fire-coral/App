import 'dart:math';
import 'package:flutter/material.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';

// -----------------------------------------------------------------------------
// 2a/2b 공용 셸 · 홈 화면
// 진행 중 퀘스트가 없으면 2b(빈 상태 CTA), 있으면 2a(캐러셀)로 갈릴 예정.
// 진행 중 퀘스트 연동 전까지는 항상 2b(빈 상태)로 표시.
// -----------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  final UserModel user;
  final void Function(BuildContext context)? onOpenSettings;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenBadges;

  const HomeScreen({
    super.key,
    required this.user,
    this.onOpenSettings,
    this.onOpenMap,
    this.onOpenBadges,
  });

  static const Color primaryRed = Color(0xFF9E2B1E);
  static const Color darkBorder = Color(0xFF2A1512);
  static const Color bgCream = Color(0xFFFFFDFB);
  static const Color subTextColor = Color(0x8C2A1512);
  static const Color noteBorder = Color(0xFFA2908A);
  static const Color noteText = Color(0xFF6D5A55);
  static const Color highlightBg = Color(0xFFF7DFD9);
  static const Color progressBg = Color(0xFFE8DCD6);
  static const Color navBg = Color(0xFFFAF5F2);

  // 임시 추천 퀘스트 목록 (기획서 2a 기준 · 추후 위치 기반 API 연동 예정)
  static const List<({String title, String distance, QuestDifficulty difficulty})> _nearbyQuests = [
    (title: '남부시장 야시장', distance: '120m', difficulty: QuestDifficulty.star2),
    (title: '폐역 벽화 찾기', distance: '450m', difficulty: QuestDifficulty.star3),
  ];

  String _stars(QuestDifficulty d) => '★' * d.stars.toInt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEmptyQuestCard(context),
                    const SizedBox(height: 18),
                    const Text('내 주변 추천 퀘스트', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkBorder)),
                    const SizedBox(height: 8),
                    for (final q in _nearbyQuests) _buildQuestRow(q),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('내 대표 배지', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkBorder)),
                        ),
                        _buildChip(context, '전체보기 ›', onTap: _fallback(context, onOpenBadges, '배지')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildEmptyBadgeBox(),
                  ],
                ),
              ),
            ),
            _buildBottomNav(context),
          ],
        ),
      ),
    );
  }

  VoidCallback _fallback(BuildContext context, VoidCallback? callback, String label) {
    return callback ??
        () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label 화면은 준비 중입니다.')),
          );
        };
  }

  // ---------------------------------------------------------------------------
  // 상단 바 : 프로필 링(레벨 진행률) · 닉네임 · 레벨 · 설정
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          _buildProfileRing(user.levelProgress),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.nickname, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkBorder)),
                Text(
                  'Lv.${user.level} · ${(user.levelProgress * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: subTextColor),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onOpenSettings != null
                ? onOpenSettings!(context)
                : _fallback(context, null, '설정')(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: noteBorder, width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.settings_outlined, size: 16, color: noteText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRing(double progress) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
          colors: [primaryRed, primaryRed, progressBg, progressBg],
          stops: [0, progress, progress, 1],
        ),
      ),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.fromBorderSide(BorderSide(color: darkBorder, width: 1)),
          ),
          child: const Center(
            child: Text('프로필', style: TextStyle(fontSize: 7, color: subTextColor)),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2b. 진행 중 퀘스트 빈 상태 카드
  // ---------------------------------------------------------------------------
  Widget _buildEmptyQuestCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlightBg,
        border: Border.all(color: darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: bgCream,
            ),
            child: const Icon(Icons.explore_outlined, color: primaryRed, size: 26),
          ),
          const SizedBox(height: 10),
          const Text('진행 중인 퀘스트가 없어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkBorder)),
          const SizedBox(height: 6),
          const Text(
            '아래 추천 목록이나 지도에서 퀘스트를 수락하면\n여기에 캐러셀 카드로 표시돼요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: subTextColor, height: 1.4),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _fallback(context, onOpenMap, '지도'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: primaryRed,
                border: Border.all(color: darkBorder, width: 1.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text('지도에서 찾아보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestRow(({String title, String distance, QuestDifficulty difficulty}) quest) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '🎯 ${quest.title} · ${quest.distance} · ${_stars(quest.difficulty)}',
        style: const TextStyle(fontSize: 13, color: darkBorder),
      ),
    );
  }

  Widget _buildEmptyBadgeBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: noteBorder, width: 1.5),
        borderRadius: BorderRadius.circular(7),
        color: bgCream,
      ),
      child: const Text(
        '아직 획득한 배지가 없어요. 첫 퀘스트를 완료하면 배지가 생겨요',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: noteText, height: 1.3),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: darkBorder, width: 1.2),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: darkBorder)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 하단 탭 : 배지 · 홈(활성) · 지도
  // ---------------------------------------------------------------------------
  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: navBg,
        border: Border(top: BorderSide(color: darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          _buildNavItem('배지', isActive: false, onTap: _fallback(context, onOpenBadges, '배지'), showDivider: true),
          _buildNavItem('홈', isActive: true, onTap: () {}, showDivider: true),
          _buildNavItem('지도', isActive: false, onTap: _fallback(context, onOpenMap, '지도'), showDivider: false),
        ],
      ),
    );
  }

  Widget _buildNavItem(String label, {required bool isActive, required VoidCallback onTap, required bool showDivider}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? primaryRed : Colors.transparent,
            border: Border(
              right: showDivider ? const BorderSide(color: Color(0xFFD8CCC6), width: 1) : BorderSide.none,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : darkBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
