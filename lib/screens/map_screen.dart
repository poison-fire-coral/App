import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../data/quest_repository.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../services/compass_service.dart';
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

  // ---------------------------------------------------------------------------
  // 현위치 방향 (나침반)
  // ---------------------------------------------------------------------------

  /// WebView 안의 부채꼴 div id. 방위각이 바뀔 때마다 오버레이를 지웠다 다시
  /// 그리면 깜빡이므로, 한 번 만든 뒤 이 id로 찾아 CSS transform만 돌린다.
  static const String _headingConeId = 'lq_heading_cone';
  static const String _headingOverlayId = 'lq_heading_overlay';

  final CompassService _compass = CompassService();
  StreamSubscription<double>? _headingSub;
  double? _heading;

  /// 오버레이를 이미 지도에 올렸는지. 현위치가 바뀌면 다시 올려야 한다.
  bool _headingOverlayPlaced = false;

  /// CSS `rotate()`에 실제로 넣는 각도. 0~360으로 래핑하지 **않고** 누적한다.
  ///
  /// 래핑한 방위각을 그대로 넘기면 357° → 3°가 브라우저에는 +6°가 아니라
  /// -354°로 보이고, `transition`이 그 길을 다 보간한다 — 북쪽을 지날 때마다
  /// 부채꼴이 한 바퀴 거꾸로 휘도는 이유다. 최단 차이만 더해서 쌓는다.
  double _coneAngle = 0;

  /// `_coneAngle`을 마지막으로 갱신할 때 쓴 방위각. 다음 차이의 기준이 된다.
  double? _coneAngleSource;

  @override
  void initState() {
    super.initState();
    // 시드 데이터 중심지(수원/서울) 초기 위치 설정
    _initialCenter = QuestRepository.mockUserLatLng;

    // 나침반이 없는 기기·에뮬레이터면 값이 영영 안 온다. 그때는 방향 표시만
    // 빠지고 현위치 점은 그대로 찍힌다.
    _headingSub = _compass.headingStream.listen(_onHeading);
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusQuestId != oldWidget.focusQuestId) {
      _applyFocusRequest();
    }

    // 퀘스트를 수락하거나 포기하고 돌아오면 그 핀의 색이 달라져야 한다.
    // 마커는 지도(WebView) 쪽 상태라 build()가 다시 돌아도 저절로 갱신되지 않는다.
    if (!setEquals(widget.activeQuestIds, oldWidget.activeQuestIds)) {
      _updateMarkers();
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
    _headingSub?.cancel();
    _compass.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 현위치 방향 부채꼴 (나침반 로직)
  // ---------------------------------------------------------------------------

  void _onHeading(double degrees) {
    _heading = degrees;

    // 방위각은 화면 어디에도 글자로 안 나온다. setState를 부르면 지도까지
    // 초당 열 번씩 다시 빌드된다 — WebView 안에서 CSS만 돌린다.
    if (!_isMapReady || _userLocation == null) return;

    if (!_headingOverlayPlaced) {
      _placeHeadingOverlay();
      return;
    }
    _rotateHeadingCone(degrees);
  }

  /// 현위치 점 위에 방향 부채꼴을 얹는다.
  ///
  /// 같은 id가 이미 있으면 플러그인의 `addCustomOverlay`가 조용히 무시하고,
  /// `clearCustomOverlay(ids)`는 **넘긴 id만 남기고 나머지를 지운다**.
  /// 그래서 갈아 끼우려면 인자 없이 한 번 비우고 다시 올려야 한다.
  void _placeHeadingOverlay() {
    final controller = _mapController;
    final location = _userLocation;
    final heading = _heading;
    if (controller == null || location == null || !_isMapReady) return;

    // 아직 방위각을 못 받았으면(센서 없음·첫 표본 대기) 부채꼴을 올리지 않는다.
    // 0으로 채우면 북쪽을 보고 있다고 거짓말하게 된다.
    if (heading == null) return;

    _headingOverlayPlaced = true;
    controller.clearCustomOverlay();
    controller.addCustomOverlay(customOverlays: [
      CustomOverlay(
        customOverlayId: _headingOverlayId,
        latLng: location,
        // 새로 만든 div에는 이전 각도가 없어 보간이 안 일어나지만, 이후
        // _rotateHeadingCone이 이어 붙일 수 있도록 누적값으로 시작한다.
        content: _headingConeHtml(_advanceConeAngle(heading)),
        // 부채꼴의 회전 중심이 곧 현위치 좌표다.
        xAnchor: 0.5,
        yAnchor: 0.5,
        // 현위치 마커(zIndex 10)보다 아래. 부채꼴은 점 바깥쪽에만 그려서
        // 두 레이어가 겹치지 않는다.
        zIndex: 9,
      ),
    ]);
  }

  /// 64×64 상자 한가운데가 현위치다. 부채꼴은 반지름 14px(현위치 점) 밖에서
  /// 시작하므로 점을 가리지 않는다. 상자를 통째로 돌려서 방향을 만든다.
  ///
  /// 플러그인이 이 문자열을 작은따옴표로 감싼 JS에 그대로 넣는다 —
  /// 작은따옴표·줄바꿈을 쓰면 안 된다.
  static String _headingConeHtml(double rotation) {
    final deg = rotation.toStringAsFixed(1);
    return '<div id="$_headingConeId" style="width:64px;height:64px;'
        'position:relative;pointer-events:none;'
        'transform:rotate(${deg}deg);transform-origin:32px 32px;'
        'transition:transform 150ms linear;will-change:transform;">'
        '<div style="position:absolute;left:21px;top:0px;width:0;height:0;'
        'border-left:11px solid transparent;border-right:11px solid transparent;'
        'border-bottom:18px solid rgba(158,43,30,0.55);"></div>'
        '</div>';
  }

  /// 방위각을 누적 회전각으로 바꾼다. 두 각의 최단 차이(-180~180)만 더하므로
  /// 359° 다음에 1°가 오면 +2°가 되고, 값은 360을 넘어 계속 자란다.
  double _advanceConeAngle(double degrees) {
    final previous = _coneAngleSource;
    _coneAngle +=
        previous == null ? degrees : ((degrees - previous + 540) % 360) - 180;
    _coneAngleSource = degrees;
    return _coneAngle;
  }

  void _rotateHeadingCone(double degrees) {
    final controller = _mapController;
    if (controller == null) return;

    final deg = _advanceConeAngle(degrees).toStringAsFixed(1);
    controller.webViewController.runJavaScript(
      'var e=document.getElementById("$_headingConeId");'
      'if(e){e.style.transform="rotate(${deg}deg)";}',
    );
  }

  bool _isKoreaLatLng(double lat, double lng) {
    return lat >= 33.0 && lat <= 39.0 && lng >= 124.0 && lng <= 132.0;
  }

  // ---------------------------------------------------------------------------
  // 백엔드 통신 및 데이터 로드
  // ---------------------------------------------------------------------------
  Future<void> _fetchQuestsFromBackend(double lat, double lng) async {
    if (_isLoadingQuests) return;
    setState(() => _isLoadingQuests = true);

    try {
      final fetchedQuests = await QuestRepository.fetchNearbyQuests(
        lat: lat,
        lng: lng,
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

      if (!_isKoreaLatLng(lat, lng)) {
        lat = QuestRepository.mockUserLocation.latitude;
        lng = QuestRepository.mockUserLocation.longitude;
      }

      final userLatLng = LatLng(lat, lng);
      _userLocation = userLatLng;

      // 현위치가 움직였으니 방향 부채꼴도 새 좌표에 다시 올린다.
      _headingOverlayPlaced = false;
      _placeHeadingOverlay();

      // 위치 확보 후 백엔드 API 호출!
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

  final Map<String, MarkerIcon> _iconCache = {};

  Future<MarkerIcon?> _icon(String assetPath) async {
    final cached = _iconCache[assetPath];
    if (cached != null) return cached;
    try {
      final icon = await MarkerIcon.fromAsset(assetPath);
      _iconCache[assetPath] = icon;
      return icon;
    } catch (e) {
      debugPrint('마커 아이콘 로드 실패($assetPath): $e');
      return null;
    }
  }

  Future<List<Marker>> _buildKakaoMarkers() async {
    final List<Marker> markers = [];
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

    for (final q in _visibleQuests) {
      // 진행 중인 퀘스트는 난이도 색 대신 브랜드 강조색으로 통일한다.
      // 5성 핀도 같은 색이므로, 크기와 zIndex로 한 번 더 갈라 놓는다.
      final isActive = widget.activeQuestIds.contains(q.id);

      final icon = await _icon(isActive
          ? AppAssets.activeQuestMarker(
              questType: q.questType,
              devicePixelRatio: dpr,
            )
          : AppAssets.questMarker(
              questType: q.questType,
              stars: q.difficulty.stars,
              devicePixelRatio: dpr,
            ));

      // 논리 크기 36×46. 끝점(아래 중앙)이 좌표에 꽂히도록 오프셋을 준다.
      final width = isActive ? 43 : 36;
      final height = isActive ? 55 : 46;

      markers.add(
        Marker(
          markerId: q.id,
          latLng: LatLng(q.latitude, q.longitude),
          icon: icon,
          width: width,
          height: height,
          offsetX: (width / 2).round(),
          // 원본 36×46에서 끝점은 y=40 — 높이의 40/46 지점이다.
          offsetY: (height * 40 / 46).round(),
          zIndex: isActive ? 5 : 0,
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
          width: 28,
          height: 28,
          offsetX: 14,
          offsetY: 14,
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

  // ---------------------------------------------------------------------------
  // 대표 이미지 로딩 & 이미지 없음 처리 헬퍼 위젯
  // ---------------------------------------------------------------------------
  Widget _buildQuestImage(String? imageUrl, {double width = 78, double height = 62, double borderRadius = 7}) {
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppSurface.sunken,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: hasImage
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildNoImagePlaceholder(),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.quest500),
                  ),
                );
              },
            )
          : _buildNoImagePlaceholder(),
    );
  }

  Widget _buildNoImagePlaceholder() {
    return const Center(
      child: Text(
        '대표이미지\n없음',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: AppColors.textSecondary, height: 1.2),
      ),
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
      child: AppSheetSurface(
        child: isDetail
            ? SingleChildScrollView(child: _buildDetailContent(quest))
            : _buildPreviewContent(quest),
      ),
    );
  }

  Widget _acceptButton(QuestModel quest) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildQuestImage(quest.imageUrl, width: 72, height: 72, borderRadius: 10),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          quest.title,
                          style: AppType.h1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TierBadge(
                        stars: quest.difficulty.stars,
                        hasHalfStar: quest.hasHalfStar,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
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
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
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
            _buildQuestImage(quest.imageUrl, width: 88, height: 68, borderRadius: 8),
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