import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../data/quest_repository.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/geo.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

class MapScreen extends StatefulWidget {
  final UserModel user;
  final Set<String> activeQuestIds;
  final ValueChanged<QuestModel> onAcceptQuest;
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

class _MapScreenState extends State<MapScreen> {
  // 백엔드에서 받아올 동적 퀘스트 목록
  List<QuestModel> _quests = [];
  bool _isLoadingQuests = false;

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
    // 시드 데이터 중심지(수원/서울) 초기 위치 설정
    _initialCenter = QuestRepository.mockUserLatLng;
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusQuestId != oldWidget.focusQuestId) {
      _applyFocusRequest();
    }
  }

  void _applyFocusRequest() {
    final id = widget.focusQuestId;
    if (id == null) return;

    final questList = _quests.where((q) => q.id == id).toList();
    if (questList.isEmpty) return;
    
    final quest = questList.first;
    _selectedQuest = quest;
    _sheetState = _SheetState.preview;

    _mapController?.setCenter(LatLng(quest.latitude, quest.longitude));
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
  // 백엔드 통신 및 데이터 로드 (포트 5001 API 호출)
  // ---------------------------------------------------------------------------
  Future<void> _fetchQuestsFromBackend(double lat, double lng) async {
    if (_isLoadingQuests) return;
    setState(() => _isLoadingQuests = true);

    try {
      final fetchedQuests = await QuestRepository.fetchNearbyQuests(
        lat: lat,
        lng: lng,
        radiusM: 50000, // 50km 반경 검색
      );

      if (mounted) {
        setState(() {
          _quests = fetchedQuests;
        });
        await _updateMarkers();
        _applyFocusRequest();
      }
    } catch (e) {
      debugPrint('퀘스트 데이터를 불러오는 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingQuests = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 마커 안전 업데이트
  // ---------------------------------------------------------------------------
  Future<void> _updateMarkers() async {
    if (_mapController == null || !_isMapReady) return;

    try {
      final markers = _buildKakaoMarkers();
      await _mapController!.clearMarker();

      if (markers.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
        await _mapController!.addMarker(markers: markers);
      }
    } catch (e) {
      debugPrint('마커 업데이트 예외 발생: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // GPS 위치 조회 및 백엔드 데이터 요청
  // ---------------------------------------------------------------------------
  Future<void> _initUserLocation({bool panToUser = true}) async {
    if (_isFetchingLocation) return;
    _isFetchingLocation = true;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      double lat = position.latitude;
      double lng = position.longitude;

      // 시뮬레이터/해외 좌표 처리 -> 시드 데이터가 존재하는 좌표로 대체
      if (!_isKoreaLatLng(lat, lng)) {
        lat = QuestRepository.mockUserLocation.latitude;
        lng = QuestRepository.mockUserLocation.longitude;
      }

      final userLatLng = LatLng(lat, lng);
      _userLocation = userLatLng;

      // 🚀 위치 확보 후 백엔드 API 호출!
      await _fetchQuestsFromBackend(lat, lng);

      if (panToUser && _mapController != null && _isMapReady) {
        await Future.delayed(const Duration(milliseconds: 100));
        await _mapController?.panTo(userLatLng);
      }
    } catch (e) {
      debugPrint('내 위치 가져오기 실패: $e');
    } finally {
      _isFetchingLocation = false;
    }
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
                    child: KakaoMap(
                      key: const ValueKey('stable_kakao_map_webview'),
                      center: _initialCenter,
                      markers: const [],
                      onMapCreated: (controller) async {
                        _mapController = controller;

                        await Future.delayed(const Duration(milliseconds: 800));
                        if (!mounted) return;

                        _isMapReady = true;
                        await _initUserLocation(panToUser: true);
                      },
                      onMarkerTap: (markerId, latLng, zoomLevel) {
                        if (markerId == 'user_my_location_pin') return;

                        final matched = _quests.where((q) => q.id == markerId);
                        if (matched.isNotEmpty) {
                          _selectQuest(matched.first);
                        }
                      },
                      onMapTap: (latLng) {
                        if (_selectedQuest != null) {
                          _closeSheet();
                        }
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

  Widget _buildMyLocationButton() {
    final double bottomPadding = _selectedQuest != null ? 220.0 : 20.0;

    return Positioned(
      right: 14,
      bottom: bottomPadding,
      child: FloatingActionButton.small(
        heroTag: 'my_location_btn',
        backgroundColor: AppColors.bgCream,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.darkBorder, width: 1.5),
        ),
        onPressed: () => _initUserLocation(panToUser: true),
        child: const Icon(
          Icons.my_location_rounded,
          color: AppColors.primaryRed,
          size: 20,
        ),
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
                      onChanged: (v) {
                        setState(() => _searchQuery = v);
                        _updateMarkers();
                      },
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
        onTap: () {
          setState(() => _selectedKeywordFilter = label);
          _updateMarkers();
        },
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
    final distance = Geo.formatDistance(
      _userLocation != null
          ? Geo.distanceBetween(
              _userLocation!.latitude,
              _userLocation!.longitude,
              quest.latitude,
              quest.longitude,
            )
          : 0.0,
    );

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