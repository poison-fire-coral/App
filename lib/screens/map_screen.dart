import 'package:flutter/material.dart';

import '../data/quest_repository.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/geo.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

class MapScreen extends StatefulWidget {
  final UserModel user;

  /// 이미 수락해 진행 중인 퀘스트 id. 해당 마커의 시트는 "이어서 하기"로 바뀐다.
  final Set<String> activeQuestIds;

  /// 퀘스트 수락 (또는 진행 중이면 이어서 하기)
  final ValueChanged<QuestModel> onAcceptQuest;

  /// 외부에서 특정 퀘스트 시트를 열어 달라고 요청한 경우 (홈 추천 목록 → 지도)
  final String? focusQuestId;

  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenBadges;
  final void Function(BuildContext context)? onOpenSettings;

  const MapScreen({
    super.key,
    required this.user,
    required this.onAcceptQuest,
    this.activeQuestIds = const {},
    this.focusQuestId,
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
  List<QuestModel> get _quests => QuestRepository.all;

  late final double _minLat, _maxLat, _minLng, _maxLng;

  KakaoMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedKeywordFilter = '전체';
  QuestModel? _selectedQuest;
  _SheetState _sheetState = _SheetState.closed;

  LatLng? _userLocation;
  bool _isFetchingLocation = false;
  bool _isMapReady = false;

  late final LatLng _initialCenter;

  @override
  void initState() {
    super.initState();
    final lats = _quests.map((q) => q.latitude).toList();
    final lngs = _quests.map((q) => q.longitude).toList();
    _minLat = lats.reduce((a, b) => a < b ? a : b);
    _maxLat = lats.reduce((a, b) => a > b ? a : b);
    _minLng = lngs.reduce((a, b) => a < b ? a : b);
    _maxLng = lngs.reduce((a, b) => a > b ? a : b);

    _applyFocusRequest();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusQuestId != oldWidget.focusQuestId) {
      _applyFocusRequest();
    }
  }

  /// 홈 추천 목록에서 넘어온 퀘스트가 있으면 해당 시트를 바로 펼친다 (와이어프레임 2a → 3b).
  void _applyFocusRequest() {
    final id = widget.focusQuestId;
    if (id == null) return;
    final quest = QuestRepository.findById(id);
    if (quest == null) return;
    _selectedQuest = quest;
    _sheetState = _SheetState.preview;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isKoreaLatLng(double lat, double lng) {
    return lat >= 33.0 && lat <= 39.0 && lng >= 124.0 && lng <= 132.0;
  }

  // ---------------------------------------------------------------------------
  // 투영 · 클러스터링 계산
  // ---------------------------------------------------------------------------
  Offset _project(QuestModel q, Size canvas) {
    const pad = 0.16;
    final latSpan = (_maxLat - _minLat).abs() < 1e-6 ? 1e-6 : (_maxLat - _minLat);
    final lngSpan = (_maxLng - _minLng).abs() < 1e-6 ? 1e-6 : (_maxLng - _minLng);
    final fx = pad + (1 - 2 * pad) * ((q.longitude - _minLng) / lngSpan);
    final fy = pad + (1 - 2 * pad) * (1 - (q.latitude - _minLat) / latSpan);
    return Offset(fx * canvas.width, fy * canvas.height);
  }

  // ---------------------------------------------------------------------------
  // 필터링 및 마커 생성
  // ---------------------------------------------------------------------------
  List<QuestModel> get _visibleQuests {
    final query = _searchQuery.trim();
    return _quests.where((q) {
      final matchesKeyword =
          _selectedKeywordFilter == '전체' || q.keywords.contains(_selectedKeywordFilter);
      final matchesQuery = query.isEmpty ||
          q.title.contains(query) ||
          q.spotName.contains(query) ||
          q.regionLabel.contains(query) ||
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

  List<Marker> _buildKakaoMarkers() {
    final List<Marker> markers = [];

    for (final q in _visibleQuests) {
      markers.add(
        Marker(
          markerId: q.id,
          latLng: LatLng(q.latitude, q.longitude),
        ),
      );
    }

    if (_userLocation != null) {
      markers.add(
        Marker(
          markerId: 'user_my_location_pin',
          latLng: _userLocation!,
        ),
      );
    }

    return markers;
  }

  void _selectQuest(QuestModel q) {
    setState(() {
      _selectedQuest = q;
      _sheetState = _SheetState.preview;
    });
    _mapController?.panTo(LatLng(q.latitude, q.longitude));
  }

  void _closeSheet() => setState(() {
        _selectedQuest = null;
        _sheetState = _SheetState.closed;
      });

  void _expandSheet() => setState(() => _sheetState = _SheetState.detail);

  void _collapseSheet() => setState(() => _sheetState = _SheetState.preview);

  void _unclusterMap() => setState(() => _clusterMode = false);

  /// 3b·3c 시트의 수락 버튼 → 분기 D(4a 이동 화면)로 넘긴다.
  void _acceptQuest(QuestModel q) {
    _closeSheet();
    widget.onAcceptQuest(q);
  }

  void _notReady(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 화면은 준비 중입니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                              const Positioned.fill(child: MapBackdrop()),
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
                  if (_isLoadingQuests)
                    const Positioned(
                      top: 80,
                      left: 0,
                      right: 0,
                      child: Center(child: LinearProgressIndicator(color: AppColors.primaryRed)),
                    ),
                  if (!_isLoadingQuests && _visibleQuests.isEmpty) _buildEmptyResultNote(),

                  _buildMyLocationButton(),

                  if (_selectedQuest != null) _buildSheet(),
                ],
              ),
            ),
            AppBottomNav(
              current: AppTab.map,
              onSelect: (tab) {
                if (tab == AppTab.home) {
                  (widget.onOpenHome ?? () => _notReady('홈'))();
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
  // 3a · 마커 · 사용자 위치 점
  // ---------------------------------------------------------------------------
  Widget _buildUserDot() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.bgCream,
        border: Border.all(color: AppColors.primaryRed, width: 2),
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
              color: isBig ? AppColors.primaryRed : AppColors.bgCream,
              border: Border.all(color: AppColors.darkBorder, width: 1.5),
            ),
            child: Center(
              child: Text(
                '+${cluster.quests.length}',
                style: TextStyle(
                  fontSize: isBig ? 14 : 13,
                  fontWeight: FontWeight.bold,
                  color: isBig ? Colors.white : AppColors.darkBorder,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final quest = cluster.quests.first;
    final isHighlighted =
        _selectedQuest?.id == quest.id || widget.activeQuestIds.contains(quest.id);
    return Positioned(
      left: cluster.position.dx - 10,
      top: cluster.position.dy - 20,
      child: GestureDetector(
        onTap: () => _selectQuest(quest),
        child: QuestMarker(isActive: isHighlighted),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        decoration: const BoxDecoration(
          color: AppColors.bgCream,
          border: Border(bottom: BorderSide(color: AppColors.darkBorder, width: 1.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.darkBorder, width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 15, color: AppColors.noteText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(fontSize: 13, color: AppColors.darkBorder),
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
    return Center(
      child: TagChip(
        label: label,
        isSelected: _selectedKeywordFilter == label,
        fontSize: 12.5,
        onTap: () => setState(() => _selectedKeywordFilter = label),
      ),
    );
  }

  Widget _buildEmptyResultNote() {
    return Positioned(
      left: 24,
      right: 24,
      top: 84,
      child: NoteBox(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: const Text(
          '조건에 맞는 퀘스트가 없어요',
          style: TextStyle(fontSize: 12, color: AppColors.noteText),
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
            color: AppColors.bgCream,
            border: Border.all(color: AppColors.darkBorder, width: 1.5),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            _clusterMode ? Icons.add : Icons.remove,
            size: 16,
            color: AppColors.darkBorder,
          ),
        ),
      ),
    );
  }

  Widget _buildSheet() {
    final quest = _selectedQuest!;
    final isDetail = _sheetState == _SheetState.detail;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: isDetail ? 80 : null,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCream,
          border: Border.fromBorderSide(BorderSide(color: AppColors.darkBorder, width: 1.5)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: isDetail
            ? SingleChildScrollView(child: _buildDetailContent(quest))
            : _buildPreviewContent(quest),
      ),
    );
  }

  /// 이미 수락한 퀘스트는 다시 수락하지 않고 4a 이동 화면으로 바로 들어간다.
  Widget _acceptButton(QuestModel quest) {
    final isActive = widget.activeQuestIds.contains(quest.id);
    return PrimaryButton(
      label: isActive ? '이어서 하기' : '퀘스트 수락',
      onTap: () => _acceptQuest(quest),
    );
  }

  Widget _buildPreviewContent(QuestModel quest) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: GrabHandle(onTap: _expandSheet)),
        Row(
          children: [
            Expanded(
              child: Text(
                quest.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
              ),
            ),
            TagChip(label: quest.starLabel, fontSize: 11),
          ],
        ),
        const SizedBox(height: 8),
        SolidBox.text('보상 : EXP ${quest.displayExp}'),
        const SizedBox(height: 8),
        NoteBox.text(quest.summary),
        const SizedBox(height: 10),
        _acceptButton(quest),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _expandSheet,
          child: const Center(
            child: Text(
              '▲ 위로 드래그하면 관광지 정보',
              style: TextStyle(fontSize: 12, color: AppColors.subText),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailContent(QuestModel quest) {
    final distance = Geo.formatDistance(QuestRepository.distanceFromUser(quest));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: GrabHandle(onTap: _collapseSheet)),
        Row(
          children: [
            Expanded(
              child: Text(
                quest.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
              ),
            ),
            TagChip(label: quest.starLabel, fontSize: 11),
          ],
        ),
        const SizedBox(height: 8),
        SolidBox.text('보상 : EXP ${quest.displayExp}'),
        const SizedBox(height: 8),
        NoteBox.text(quest.description),
        const SizedBox(height: 8),
        SolidBox.text('달성 기준\n${quest.completionCriteria}'),
        const SizedBox(height: 10),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 10),
        const Center(
          child: Text('― 관광지 정보 ―', style: TextStyle(fontSize: 11, color: AppColors.subText)),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 78,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.noteBorder, width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                '사진 1장',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.noteText),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.spotName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.darkBorder),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [for (final k in quest.keywords) TagChip(label: k, fontSize: 11)],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${quest.regionLabel} · $distance',
                    style: const TextStyle(fontSize: 12, color: AppColors.subText),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        NoteBox.text(
          '혼잡도 : ${quest.crowdLabel} · EXP ×${quest.crowdMultiplier.toStringAsFixed(1)}',
        ),
        const SizedBox(height: 12),
        _acceptButton(quest),
      ],
    );
  }
}
