import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../data/quest_repository.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/geo.dart';
import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_widgets.dart';

class MapScreen extends StatefulWidget {
  final UserModel user;
  final Set<String> activeQuestIds;

  /// 이미 완료해 다시 수락할 수 없는 퀘스트들.
  final Set<String> completedQuestIds;

  final ValueChanged<QuestModel> onAcceptQuest;
  final String? focusQuestId;

  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenBadges;

  /// 좌상단 프로필 링을 눌렀을 때 (5c)
  final VoidCallback? onOpenProfile;
  final void Function(BuildContext context)? onOpenSettings;

  const MapScreen({
    super.key,
    required this.user,
    required this.onAcceptQuest,
    this.activeQuestIds = const {},
    this.completedQuestIds = const {},
    this.focusQuestId,
    this.onOpenHome,
    this.onOpenBadges,
    this.onOpenProfile,
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
        // 이 API는 호출할 때마다 카카오 로컬 API를 4번 때리고 DB에 쓴다
        // (quest.service.ts:278). 반경이 넓을수록 느려지고 DB가 계속 부푼다.
        radiusM: 5000,
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
      final markers = await _buildKakaoMarkers();
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

  /// 아이콘은 에셋을 읽어 base64로 감싸는 비용이 있다. 지도를 움직일 때마다
  /// 마커를 다시 그리므로 경로별로 한 번만 만들고 재사용한다.
  final Map<String, MarkerIcon> _iconCache = {};

  Future<MarkerIcon?> _icon(String assetPath) async {
    final cached = _iconCache[assetPath];
    if (cached != null) return cached;
    try {
      final icon = await MarkerIcon.fromAsset(assetPath);
      _iconCache[assetPath] = icon;
      return icon;
    } catch (e) {
      // 에셋이 빠졌다고 지도가 통째로 비면 안 된다. 기본 핀으로 떨어진다.
      debugPrint('마커 아이콘 로드 실패($assetPath): $e');
      return null;
    }
  }

  Future<List<Marker>> _buildKakaoMarkers() async {
    final List<Marker> markers = [];
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

    for (final q in _visibleQuests) {
      final icon = await _icon(AppAssets.questMarker(
        questType: q.questType,
        stars: q.difficulty.stars,
        devicePixelRatio: dpr,
      ));
      markers.add(
        Marker(
          markerId: q.id,
          latLng: LatLng(q.latitude, q.longitude),
          icon: icon,
          // 논리 크기 36×46. 끝점(아래 중앙)이 좌표에 꽂히도록 오프셋을 준다.
          width: 36,
          height: 46,
          offsetX: 18,
          offsetY: 40,
        ),
      );
    }

    if (_userLocation != null) {
      final icon = await _icon(AppAssets.myLocationMarker(dpr));
      markers.add(
        Marker(
          markerId: 'user_my_location_pin',
          latLng: _userLocation!,
          icon: icon,
          // 현위치는 원이라 중심이 곧 좌표다.
          width: 28,
          height: 28,
          offsetX: 14,
          offsetY: 14,
          // 퀘스트 핀에 가리지 않게 위로 올린다.
          zIndex: 10,
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
      backgroundColor: AppColors.surface,
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
                      child: Center(
                          child: LinearProgressIndicator(
                              color: AppColors.quest500)),
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

  /// 디자인 시스템 11: 현위치는 FloatingSurfaceButton(emphasized: false).
  /// 주 행동이 아니므로 붉은 인장을 쓰지 않는다.
  Widget _buildMyLocationButton() {
    final double bottomPadding = _selectedQuest != null ? 220.0 : AppSpacing.xl;

    return Positioned(
      right: AppSpacing.gutter,
      bottom: bottomPadding,
      child: FloatingSurfaceButton(
        icon: Icons.my_location_rounded,
        onTap: () => _initUserLocation(panToUser: true),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      // 지도 배경이 복잡해서 납작한 바는 묻힌다. 종이 카드로 띄운다 (11).
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              radius: BorderRadius.circular(AppRadius.pill),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) {
                        setState(() => _searchQuery = v);
                        _updateMarkers();
                      },
                      style: AppType.body,
                      decoration: InputDecoration(
                        hintText: '지역 · 퀘스트 검색',
                        hintStyle: AppType.body
                            .copyWith(color: AppColors.textDisabled),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 2),
                children: [
                  _filterChip('전체'),
                  for (final k in _availableKeywords) ...[
                    const SizedBox(width: AppSpacing.sm),
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
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
      // 바텀시트는 e4 — 상단 반경 24 + 위로 던지는 그림자 (디자인 시스템 10).
      child: AppSheetSurface(
        child: isDetail
            ? SingleChildScrollView(child: _buildDetailContent(quest))
            : _buildPreviewContent(quest),
      ),
    );
  }

  Widget _acceptButton(QuestModel quest) {
    // 완료한 퀘스트는 재수락도 재클리어도 안 된다. 서버가 거절하기 전에
    // 버튼에서 먼저 알려준다 — 눌러보고 스낵바로 거절당하는 것보다 낫다.
    if (widget.completedQuestIds.contains(quest.id)) {
      return const PrimaryButton(label: '완료한 퀘스트', enabled: false);
    }

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
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: Text(quest.title, style: AppType.h1)),
            TierBadge(
              stars: quest.difficulty.stars,
              hasHalfStar: quest.hasHalfStar,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            // 보상은 앰버로 떠오르고(볼록),
            RewardPill(
              exp: quest.displayExp,
              multiplierNote: quest.crowdMultiplier != 1.0
                  ? quest.crowdLabel
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              QuestRepository.distanceFromUser(quest),
              style: AppType.numeric.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // 설명은 종이에 눌러 새긴 면으로 내려간다(오목). 04 표면.
        NoteBox.text(quest.summary),
        const SizedBox(height: AppSpacing.lg),
        _acceptButton(quest),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          onTap: _expandSheet,
          child: Center(
            child: Text('관광지 정보 보기', style: AppType.caption),
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
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
          child: Text('― 관광지 정보 ―', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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
                gradient: AppSurface.sunken,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                '사진 1장',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.spotName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
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