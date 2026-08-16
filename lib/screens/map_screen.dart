import 'dart:math';
import 'package:flutter/material.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';

// -----------------------------------------------------------------------------
// 분기 C · 지도 화면
// 3a 0단계(마커+검색) · 3b 1단계(마커 클릭 요약 시트) · 3c 2단계(퀘스트 상세 시트)
// 3d 마커 클러스터링. 실제 지도 SDK 없이(placeholder 맵) 좌표를 화면 좌표로
// 투영해 마커를 배치하고, 화면상 거리 기반으로 클러스터를 묶는다.
// -----------------------------------------------------------------------------
class MapScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenBadges;
  final void Function(BuildContext context)? onOpenSettings;

  const MapScreen({
    super.key,
    required this.user,
    this.onOpenHome,
    this.onOpenBadges,
    this.onOpenSettings,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum _SheetState { closed, preview, detail }

class _MarkerCluster {
  final Offset position;
  final List<QuestModel> quests;
  _MarkerCluster(this.position, this.quests);
  bool get isCluster => quests.length > 1;
}

class _MapScreenState extends State<MapScreen> {
  static const Color primaryRed = Color(0xFF9E2B1E);
  static const Color darkBorder = Color(0xFF2A1512);
  static const Color bgCream = Color(0xFFFFFDFB);
  static const Color subTextColor = Color(0x8C2A1512);
  static const Color noteBorder = Color(0xFFA2908A);
  static const Color noteText = Color(0xFF6D5A55);
  static const Color progressBg = Color(0xFFE8DCD6);
  static const Color navBg = Color(0xFFFAF5F2);
  static const Color dividerColor = Color(0xFFE6DCD6);

  // 임시 목업 퀘스트 데이터 (전주 한옥마을 일대 · 실좌표 기반 거리/투영 계산용)
  static final List<QuestModel> _quests = [
    QuestModel(
      id: 'q1',
      title: '남부시장 야시장 방문',
      summary: '남부시장 야시장 서쪽 끝까지 걸어 들어가 가장 오래된 점포를 찾아보세요.',
      description: '남부시장 야시장 서쪽 끝까지 걸어 들어가 가장 오래된 점포를 찾아보세요.',
      difficulty: QuestDifficulty.star2,
      hasHalfStar: true,
      latitude: 35.8115,
      longitude: 127.1470,
      spotName: '남부시장',
      regionLabel: '전주시 완산구',
      keywords: const ['#전통시장', '#야시장'],
      crowdMultiplier: 1.4,
    ),
    QuestModel(
      id: 'q2',
      title: '청년몰 골목 한바퀴',
      summary: '남부시장 청년몰 골목을 한 바퀴 돌며 로컬 브랜드 소품샵 2곳을 방문해 보세요.',
      description: '남부시장 청년몰 골목을 한 바퀴 돌며 로컬 브랜드 소품샵 2곳을 방문해 보세요.',
      difficulty: QuestDifficulty.star1,
      latitude: 35.8110,
      longitude: 127.1465,
      spotName: '남부시장 청년몰',
      regionLabel: '전주시 완산구',
      keywords: const ['#로컬브랜드', '#소품샵'],
      crowdMultiplier: 1.0,
    ),
    QuestModel(
      id: 'q3',
      title: '경기전 돌담길 걷기',
      summary: '경기전 돌담을 따라 걸으며 가장 마음에 드는 풍경을 사진으로 남겨보세요.',
      description: '경기전 돌담을 따라 걸으며 가장 마음에 드는 풍경을 사진으로 남겨보세요.',
      difficulty: QuestDifficulty.star1,
      latitude: 35.8156,
      longitude: 127.1523,
      spotName: '경기전',
      regionLabel: '전주시 완산구',
      keywords: const ['#한옥·고택', '#역사유적'],
      crowdMultiplier: 0.7,
    ),
    QuestModel(
      id: 'q4',
      title: '전동성당 사진 남기기',
      summary: '전동성당 정면이 가장 잘 보이는 자리에서 인증 사진을 남겨보세요.',
      description: '전동성당 정면이 가장 잘 보이는 자리에서 인증 사진을 남겨보세요.',
      difficulty: QuestDifficulty.star2,
      latitude: 35.8135,
      longitude: 127.1538,
      spotName: '전동성당',
      regionLabel: '전주시 완산구',
      keywords: const ['#종교건축', '#사진스팟'],
      crowdMultiplier: 1.0,
    ),
    QuestModel(
      id: 'q5',
      title: '산지천 야경 담기',
      summary: '해질 무렵 산지천을 따라 걸으며 야경 사진 한 장을 남겨보세요.',
      description: '해질 무렵 산지천을 따라 걸으며 야경 사진 한 장을 남겨보세요.',
      difficulty: QuestDifficulty.star2,
      latitude: 35.8175,
      longitude: 127.1575,
      spotName: '산지천',
      regionLabel: '전주시 완산구',
      keywords: const ['#야경·일출일몰', '#사진스팟'],
      crowdMultiplier: 1.2,
    ),
    QuestModel(
      id: 'q6',
      title: '오목대 전망 오르기',
      summary: '오목대에 올라 한옥마을 전경이 한눈에 들어오는 자리를 찾아보세요.',
      description: '오목대에 올라 한옥마을 전경이 한눈에 들어오는 자리를 찾아보세요.',
      difficulty: QuestDifficulty.star3,
      latitude: 35.8163,
      longitude: 127.1607,
      spotName: '오목대',
      regionLabel: '전주시 완산구',
      keywords: const ['#근대건축', '#야경·일출일몰'],
      crowdMultiplier: 1.0,
    ),
    QuestModel(
      id: 'q7',
      title: '자만벽화마을 벽화 찾기',
      summary: '자만벽화마을 골목에서 가장 오래된 벽화를 찾아 사진으로 남겨보세요.',
      description: '자만벽화마을 골목에서 가장 오래된 벽화를 찾아 사진으로 남겨보세요.',
      difficulty: QuestDifficulty.star3,
      latitude: 35.8206,
      longitude: 127.1653,
      spotName: '자만벽화마을',
      regionLabel: '전주시 덕진구',
      keywords: const ['#벽화·거리예술', '#사진스팟'],
      crowdMultiplier: 1.5,
    ),
  ];

  // 임시 사용자 현재 위치 (한옥마을 초입 부근 고정 좌표)
  static const double _userLat = 35.8150;
  static const double _userLng = 127.1540;

  late final double _minLat, _maxLat, _minLng, _maxLng;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedKeywordFilter = '전체';
  bool _clusterMode = false;
  QuestModel? _selectedQuest;
  _SheetState _sheetState = _SheetState.closed;

  @override
  void initState() {
    super.initState();
    final lats = _quests.map((q) => q.latitude);
    final lngs = _quests.map((q) => q.longitude);
    _minLat = lats.reduce(min);
    _maxLat = lats.reduce(max);
    _minLng = lngs.reduce(min);
    _maxLng = lngs.reduce(max);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 위치 · 투영 · 클러스터링 계산
  // ---------------------------------------------------------------------------
  double _deg2rad(double deg) => deg * pi / 180;

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  Offset _project(QuestModel q, Size canvas) {
    const pad = 0.16;
    final latSpan = (_maxLat - _minLat).abs() < 1e-6 ? 1e-6 : (_maxLat - _minLat);
    final lngSpan = (_maxLng - _minLng).abs() < 1e-6 ? 1e-6 : (_maxLng - _minLng);
    final fx = pad + (1 - 2 * pad) * ((q.longitude - _minLng) / lngSpan);
    final fy = pad + (1 - 2 * pad) * (1 - (q.latitude - _minLat) / latSpan);
    return Offset(fx * canvas.width, fy * canvas.height);
  }

  List<QuestModel> get _visibleQuests {
    final query = _searchQuery.trim();
    return _quests.where((q) {
      final matchesKeyword = _selectedKeywordFilter == '전체' || q.keywords.contains(_selectedKeywordFilter);
      final matchesQuery = query.isEmpty ||
          q.title.contains(query) ||
          q.spotName.contains(query) ||
          q.keywords.any((k) => k.contains(query));
      return matchesKeyword && matchesQuery;
    }).toList();
  }

  List<String> get _availableKeywords {
    final set = <String>{};
    for (final q in _quests) {
      set.addAll(q.keywords);
    }
    return set.toList();
  }

  List<_MarkerCluster> _buildClusters(Size canvas) {
    final quests = _visibleQuests;
    final positions = {for (final q in quests) q.id: _project(q, canvas)};

    if (!_clusterMode) {
      return [for (final q in quests) _MarkerCluster(positions[q.id]!, [q])];
    }

    const threshold = 56.0;
    final used = <String>{};
    final clusters = <_MarkerCluster>[];
    for (final q in quests) {
      if (used.contains(q.id)) continue;
      final base = positions[q.id]!;
      final group = <QuestModel>[q];
      used.add(q.id);
      for (final other in quests) {
        if (used.contains(other.id)) continue;
        if ((positions[other.id]! - base).distance <= threshold) {
          group.add(other);
          used.add(other.id);
        }
      }
      var centroid = Offset.zero;
      for (final g in group) {
        centroid += positions[g.id]!;
      }
      clusters.add(_MarkerCluster(centroid / group.length.toDouble(), group));
    }
    return clusters;
  }

  // ---------------------------------------------------------------------------
  // 상태 전환
  // ---------------------------------------------------------------------------
  void _selectQuest(QuestModel q) => setState(() {
        _selectedQuest = q;
        _sheetState = _SheetState.preview;
      });

  void _closeSheet() => setState(() {
        _selectedQuest = null;
        _sheetState = _SheetState.closed;
      });

  void _expandSheet() => setState(() => _sheetState = _SheetState.detail);

  void _collapseSheet() => setState(() => _sheetState = _SheetState.preview);

  void _unclusterMap() => setState(() => _clusterMode = false);

  void _acceptQuest(QuestModel q) {
    _closeSheet();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${q.title}" 퀘스트를 수락했어요! (진행 화면은 준비 중입니다)')),
    );
  }

  VoidCallback _fallback(String label) {
    return () {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label 화면은 준비 중입니다.')),
      );
    };
  }

  // ---------------------------------------------------------------------------
  // 빌드
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, constraints.maxHeight);
                        final clusters = _buildClusters(size);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _selectedQuest != null ? _closeSheet : null,
                          child: Stack(
                            children: [
                              CustomPaint(size: size, painter: _MapBackgroundPainter()),
                              Positioned(
                                left: size.width * 0.5 - 9,
                                top: size.height * 0.55 - 9,
                                child: _buildUserDot(),
                              ),
                              for (final cluster in clusters) _buildMarker(cluster),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (_sheetState != _SheetState.detail) _buildSearchBar(),
                  if (_visibleQuests.isEmpty) _buildEmptyResultNote(),
                  _buildZoomButton(),
                  if (_selectedQuest != null) _buildSheet(),
                ],
              ),
            ),
            _buildBottomNav(context),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 상단 바 · 하단 내비게이션 (홈 화면과 동일한 셸)
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(BuildContext context) {
    final user = widget.user;
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
            onTap: () => widget.onOpenSettings != null ? widget.onOpenSettings!(context) : _fallback('설정')(),
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

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: navBg,
        border: Border(top: BorderSide(color: darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          _buildNavItem('배지', isActive: false, onTap: widget.onOpenBadges ?? _fallback('배지'), showDivider: true),
          _buildNavItem('홈', isActive: false, onTap: widget.onOpenHome ?? _fallback('홈'), showDivider: true),
          _buildNavItem('지도', isActive: true, onTap: () {}, showDivider: false),
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

  // ---------------------------------------------------------------------------
  // 3a · 마커 · 사용자 위치 점
  // ---------------------------------------------------------------------------
  Widget _buildUserDot() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgCream,
        border: Border.all(color: primaryRed, width: 2),
      ),
    );
  }

  // 3d · 클러스터 또는 단일 마커
  Widget _buildMarker(_MarkerCluster cluster) {
    if (cluster.isCluster) {
      final isBig = cluster.quests.length > 4;
      final size = isBig ? 52.0 : 40.0;
      return Positioned(
        left: cluster.position.dx - size / 2,
        top: cluster.position.dy - size / 2,
        child: GestureDetector(
          onTap: _unclusterMap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isBig ? primaryRed : bgCream,
              border: Border.all(color: darkBorder, width: 1.5),
            ),
            child: Center(
              child: Text(
                '+${cluster.quests.length}',
                style: TextStyle(
                  fontSize: isBig ? 14 : 13,
                  fontWeight: FontWeight.bold,
                  color: isBig ? Colors.white : darkBorder,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final quest = cluster.quests.first;
    final isSelected = _selectedQuest?.id == quest.id;
    return Positioned(
      left: cluster.position.dx - 10,
      top: cluster.position.dy - 20,
      child: GestureDetector(
        onTap: () => _selectQuest(quest),
        child: Transform.rotate(
          angle: -pi / 4,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isSelected ? primaryRed : bgCream,
              border: Border.all(color: darkBorder, width: 1.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3a · 검색 · 키워드 필터 바
  // ---------------------------------------------------------------------------
  Widget _buildSearchBar() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        decoration: const BoxDecoration(
          color: bgCream,
          border: Border(bottom: BorderSide(color: darkBorder, width: 1.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: darkBorder, width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 15, color: noteText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(fontSize: 13, color: darkBorder),
                      decoration: const InputDecoration(
                        hintText: '지역 · 퀘스트 검색',
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _filterChip('전체'),
                  for (final k in _availableKeywords) ...[
                    const SizedBox(width: 6),
                    _filterChip(k),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final isSelected = _selectedKeywordFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedKeywordFilter = label),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: isSelected ? primaryRed : bgCream,
          border: Border.all(color: isSelected ? primaryRed : darkBorder, width: 1.2),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : darkBorder,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyResultNote() {
    return Positioned(
      left: 24,
      right: 24,
      top: 84,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgCream,
          border: Border.all(color: noteBorder, width: 1.5, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Center(
          child: Text('조건에 맞는 퀘스트가 없어요', style: TextStyle(fontSize: 12, color: noteText)),
        ),
      ),
    );
  }

  Widget _buildZoomButton() {
    return Positioned(
      right: 14,
      bottom: 20,
      child: GestureDetector(
        onTap: () => setState(() => _clusterMode = !_clusterMode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: bgCream,
            border: Border.all(color: darkBorder, width: 1.5),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(_clusterMode ? Icons.add : Icons.remove, size: 16, color: darkBorder),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3b · 3c · 퀘스트 미리보기 / 상세 시트
  // ---------------------------------------------------------------------------
  Widget _buildSheet() {
    final quest = _selectedQuest!;
    final isDetail = _sheetState == _SheetState.detail;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: isDetail ? 80 : null,
      child: Container(
        decoration: BoxDecoration(
          color: bgCream,
          border: Border.all(color: darkBorder, width: 1.5),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: isDetail
            ? SingleChildScrollView(child: _buildDetailContent(quest))
            : _buildPreviewContent(quest),
      ),
    );
  }

  Widget _grabHandle({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: const Color(0xFFD6C8C2), borderRadius: BorderRadius.circular(2)),
      ),
    );
  }

  Widget _starsChip(QuestModel q) {
    final stars = '★' * q.difficulty.stars.toInt();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: darkBorder, width: 1.2), borderRadius: BorderRadius.circular(11)),
      child: Text(q.hasHalfStar ? '$stars½' : stars, style: const TextStyle(fontSize: 11, color: darkBorder)),
    );
  }

  Widget _solidBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(border: Border.all(color: darkBorder, width: 1.5), borderRadius: BorderRadius.circular(7)),
      child: Text(text, style: const TextStyle(fontSize: 13, color: darkBorder, height: 1.25)),
    );
  }

  Widget _dashedBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(border: Border.all(color: noteBorder, width: 1.5), borderRadius: BorderRadius.circular(7)),
      child: Text(text, style: const TextStyle(fontSize: 13, color: noteText, height: 1.25)),
    );
  }

  Widget _primaryButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: primaryRed,
          border: Border.all(color: darkBorder, width: 1.5),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Center(
          child: Text('퀘스트 수락', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildPreviewContent(QuestModel quest) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _grabHandle(onTap: _expandSheet)),
        Row(
          children: [
            Expanded(child: Text(quest.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkBorder))),
            _starsChip(quest),
          ],
        ),
        const SizedBox(height: 8),
        _solidBox('보상 : EXP ${quest.rewardExp}'),
        const SizedBox(height: 8),
        _dashedBox(quest.summary),
        const SizedBox(height: 10),
        _primaryButton('퀘스트 수락', onTap: () => _acceptQuest(quest)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _expandSheet,
          child: const Center(
            child: Text('▲ 위로 드래그하면 관광지 정보', style: TextStyle(fontSize: 12, color: subTextColor)),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailContent(QuestModel quest) {
    final distance = _formatDistance(_distanceMeters(_userLat, _userLng, quest.latitude, quest.longitude));
    final crowdLabel = quest.crowdMultiplier >= 1.3
        ? '한산'
        : quest.crowdMultiplier <= 0.8
            ? '혼잡'
            : '보통';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _grabHandle(onTap: _collapseSheet)),
        Row(
          children: [
            Expanded(child: Text(quest.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: darkBorder))),
            _starsChip(quest),
          ],
        ),
        const SizedBox(height: 8),
        _solidBox('보상 : EXP ${quest.rewardExp}'),
        const SizedBox(height: 8),
        _dashedBox(quest.description),
        const SizedBox(height: 8),
        _solidBox('달성 기준\n목표 좌표 반경 ${quest.validRadiusMeters.toInt()}m 도달 · 사진 1장'),
        const SizedBox(height: 10),
        const Divider(color: dividerColor, height: 1),
        const SizedBox(height: 10),
        const Center(child: Text('― 관광지 정보 ―', style: TextStyle(fontSize: 11, color: subTextColor))),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 78,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: noteBorder, width: 1.5), borderRadius: BorderRadius.circular(7)),
              child: const Text('사진 1장', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: noteText)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quest.spotName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: darkBorder)),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [for (final k in quest.keywords) _filterTag(k)],
                  ),
                  const SizedBox(height: 5),
                  Text('${quest.regionLabel} · $distance', style: const TextStyle(fontSize: 12, color: subTextColor)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _dashedBox('피로도 : $crowdLabel EXP ×${quest.crowdMultiplier.toStringAsFixed(1)}'),
        const SizedBox(height: 12),
        _primaryButton('퀘스트 수락', onTap: () => _acceptQuest(quest)),
      ],
    );
  }

  Widget _filterTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: darkBorder, width: 1.2), borderRadius: BorderRadius.circular(11)),
      child: Text(label, style: const TextStyle(fontSize: 11, color: darkBorder)),
    );
  }
}

// -----------------------------------------------------------------------------
// placeholder 지도 배경 (45도 반복 대각선 패턴, 실제 타일맵 대체용)
// -----------------------------------------------------------------------------
class _MapBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFFF7F3F0);
    canvas.drawRect(Offset.zero & size, base);

    final stripe = Paint()
      ..color = const Color(0xFFECE4DF)
      ..strokeWidth = 9;
    const gap = 18.0;
    final diagonalCount = ((size.width + size.height) / gap).ceil() + 2;
    for (int i = -diagonalCount; i < diagonalCount; i++) {
      final offset = i * gap;
      canvas.drawLine(Offset(offset, 0), Offset(offset + size.height, size.height), stripe);
    }
  }

  @override
  bool shouldRepaint(covariant _MapBackgroundPainter oldDelegate) => false;
}
