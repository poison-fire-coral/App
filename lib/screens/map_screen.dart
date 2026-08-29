import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../data/keyword_taxonomy.dart';
import '../data/quest_repository.dart';
import '../models/api_exception.dart';
import '../models/quest_model.dart';
import '../models/user_model.dart';
import '../models/viewport_quests.dart';
import '../services/compass_service.dart';
import '../services/geo.dart';
import '../services/map_zoom.dart';
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
  /// 지금 보이는 범위에서 서버가 준 퀘스트. 확대 상태에서만 채워진다.
  List<QuestModel> _quests = [];

  /// 축소 상태에서 서버가 격자로 묶어 준 덩어리들.
  List<QuestCluster> _clusters = [];

  /// 서버가 이 범위에서 찾은 전체 개수. 잘렸는지 알려줄 때 쓴다.
  int _totalInViewport = 0;
  bool _isTruncated = false;

  bool _isLoadingQuests = false;

  KakaoMapController? _mapController;
  QuestModel? _selectedQuest;
  _SheetState _sheetState = _SheetState.closed;

  LatLng? _userLocation;
  bool _isFetchingLocation = false;
  bool _isMapReady = false;

  late final LatLng _initialCenter;

  // ---------------------------------------------------------------------------
  // 뷰포트 조회 (3b) — 체크리스트 08 · 09
  // ---------------------------------------------------------------------------

  /// 마지막으로 카카오가 알려준 지도 레벨. 1이 최대 확대다.
  int _kakaoLevel = 3;

  /// 카메라가 멈춘 뒤 이만큼 기다렸다 조회한다.
  ///
  /// 카카오는 드래그하는 내내 `idle`을 여러 번 던진다. 그대로 조회하면
  /// 한 번 훑는 동안 요청이 수십 개 나가고, 그게 서버 최다 호출 경로가 된다.
  static const Duration _cameraIdleDebounce = Duration(milliseconds: 300);
  Timer? _cameraIdleTimer;

  /// 조회 순번. 응답이 순서를 바꿔 도착해도 **더 오래된 것이 새 것을 덮지
  /// 않게** 한다. 빠르게 두 번 움직이면 첫 요청이 나중에 올 수 있다.
  int _viewportRequest = 0;

  // ---------------------------------------------------------------------------
  // 검색 · 필터 (3a) — 체크리스트 11 · 12
  // ---------------------------------------------------------------------------

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 350);

  /// 전국 검색 결과. 비어 있지 않으면 지도 위에 목록으로 펼친다.
  List<QuestModel> _searchResults = [];
  bool _isSearching = false;
  int _searchRequest = 0;

  /// null이면 '전체'. 값이 있으면 **서버 어휘**의 키워드 하나다.
  String? _selectedKeyword;

  /// 필터 칩 순서 — 내가 온보딩에서 고른 취향이 앞으로 온다.
  ///
  /// 결과에서 뽑지 않는다. 서버 필터를 걸면 결과가 줄어드는데 그걸로 칩을
  /// 만들면 방금 누른 칩만 남고 되돌릴 수가 없다.
  late final List<String> _keywordChips =
      KeywordTaxonomy.filterChipOrder(widget.user.travelStyles);

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

  /// 홈에서 고른 퀘스트(2a → 3b)의 시트를 펼친다.
  ///
  /// 지도가 뷰포트 조회로 바뀌면서 **그 퀘스트가 현재 범위 밖일 수 있다.**
  /// 목록에 없으면 서버에 단건으로 물어 좌표를 알아내고 그리로 옮긴다.
  /// 그러지 않으면 홈에서 눌러도 아무 일도 일어나지 않는다.
  Future<void> _applyFocusRequest() async {
    final id = widget.focusQuestId;
    if (id == null) return;
    if (_selectedQuest?.id == id) return; // 이미 펼쳐 놨다

    QuestModel? quest;
    for (final q in _quests) {
      if (q.id == id) {
        quest = q;
        break;
      }
    }

    // 목업 퀘스트(id가 정수가 아님)는 서버에 없으므로 로컬에서 찾는다.
    quest ??= int.tryParse(id) == null
        ? QuestRepository.findById(id)
        : await QuestRepository.fetchQuestById(id);

    if (quest == null || !mounted) return;

    setState(() {
      _selectedQuest = quest;
      _sheetState = _SheetState.preview;
    });

    _mapController?.setCenter(LatLng(quest.latitude, quest.longitude));
  }

  @override
  void dispose() {
    // 살아 있는 타이머가 화면이 사라진 뒤 setState를 부르면 예외가 난다.
    _cameraIdleTimer?.cancel();
    _searchDebounce?.cancel();
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
  void _placeHeadingOverlay() {
    final heading = _heading;
    if (_userLocation == null || heading == null || !_isMapReady) return;

    _headingOverlayPlaced = true;
    // 부채꼴이 새 좌표로 옮겨 가야 하므로 기존 것을 확실히 지우고 다시 그린다.
    _syncCustomOverlays(rebuildCone: true);
  }

  /// 커스텀 오버레이(방향 부채꼴 + 클러스터 원)를 **한 번에** 올린다.
  ///
  /// **왜 따로 못 올리는가**
  /// 플러그인의 `addCustomOverlay`는 넘긴 목록으로 먼저
  /// `clearCustomOverlay(그 id들)`을 부르는데, 그 함수는 **목록에 없는 것을
  /// 전부 지운다**. 부채꼴만 올리면 클러스터가 사라지고, 클러스터만 올리면
  /// 부채꼴이 사라진다. 그래서 항상 전부를 함께 넘긴다.
  ///
  /// 같은 id가 이미 있으면 조용히 무시되므로, 부채꼴은 자연히 살아남고
  /// (그래서 `_rotateHeadingCone`의 CSS 회전이 계속 먹는다)
  /// 클러스터는 좌표·개수가 섞인 id 덕분에 값이 바뀌면 새로 그려진다.
  Future<void> _syncCustomOverlays({bool rebuildCone = false}) async {
    final controller = _mapController;
    if (controller == null || !_isMapReady) return;

    final overlays = <CustomOverlay>[];

    final location = _userLocation;
    final heading = _heading;
    if (location != null && heading != null && _headingOverlayPlaced) {
      overlays.add(CustomOverlay(
        customOverlayId: _headingOverlayId,
        latLng: location,
        // 새로 만든 div에는 이전 각도가 없어 보간이 안 일어나지만, 이후
        // _rotateHeadingCone이 이어 붙일 수 있도록 누적값으로 시작한다.
        content: _headingConeHtml(
          rebuildCone ? _advanceConeAngle(heading) : _coneAngle,
        ),
        // 부채꼴의 회전 중심이 곧 현위치 좌표다.
        xAnchor: 0.5,
        yAnchor: 0.5,
        // 현위치 마커(zIndex 10)보다 아래. 부채꼴은 점 바깥쪽에만 그려서
        // 두 레이어가 겹치지 않는다.
        zIndex: 9,
      ));
    }

    for (final cluster in _clusters) {
      overlays.add(CustomOverlay(
        customOverlayId: cluster.overlayId,
        latLng: LatLng(cluster.latitude, cluster.longitude),
        content: _clusterHtml(cluster.count),
        xAnchor: 0.5,
        yAnchor: 0.5,
        zIndex: 8,
      ));
    }

    try {
      if (rebuildCone) {
        // 부채꼴을 옮길 때는 id가 그대로라 "이미 있음"으로 무시된다.
        // 좌표를 바꾸려면 통째로 한 번 비우는 수밖에 없다.
        controller.clearCustomOverlay();
      }
      if (overlays.isEmpty) {
        controller.clearCustomOverlay();
        return;
      }
      await controller.addCustomOverlay(customOverlays: overlays);
    } catch (e) {
      debugPrint('오버레이 갱신 실패: $e');
    }
  }

  /// 클러스터 원 하나의 HTML.
  ///
  /// `MarkerCluster`(app_widgets.dart)와 **같은 모양**을 CSS로 옮긴 것이다.
  /// 플러터 위젯을 지도 위에 그대로 얹을 수 없어서 — 지도는 WebView고
  /// 마커는 PNG만 받는다 — 커스텀 오버레이의 HTML로 만든다.
  ///
  /// 플러그인이 이 문자열을 작은따옴표로 감싼 JS에 그대로 끼워 넣는다.
  /// **작은따옴표와 줄바꿈을 쓰면 안 된다.**
  static String _clusterHtml(int count) {
    // MarkerCluster의 `34 + min(count,40) * 0.45`를 그대로 옮겼다.
    final diameter = (34.0 + (count > 40 ? 40 : count) * 0.45).toStringAsFixed(0);
    final label = count > 999 ? '999+' : '$count';

    return '<div style="width:${diameter}px;height:${diameter}px;'
        'display:flex;align-items:center;justify-content:center;'
        'border-radius:50%;box-sizing:border-box;'
        'background:linear-gradient(160deg,#B8402F,#8A2318);'
        'border:2px solid rgba(255,255,255,0.65);'
        'box-shadow:0 3px 10px rgba(74,58,42,0.35);'
        'color:#FFF6F3;font-size:13px;font-weight:600;'
        'font-family:-apple-system,Roboto,sans-serif;'
        'cursor:pointer;">$label</div>';
  }

  /// 클러스터를 눌렀다 — 그 자리로 두 단계 확대한다.
  ///
  /// 한 단계만 당기면 여전히 클러스터라 두 번 눌러야 뭔가 보인다.
  /// 확대가 끝나면 `onCameraIdle`이 알아서 다시 조회한다.
  void _onCustomOverlayTap(String overlayId, LatLng latLng) {
    if (overlayId == _headingOverlayId) return;

    final next = (_kakaoLevel - 2).clamp(
      MapZoom.minKakaoLevel,
      MapZoom.maxKakaoLevel,
    );
    _mapController?.setCenter(latLng);
    _mapController?.setLevel(next);
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

  /// 첫 진입과 "내 위치" 버튼에서만 부르는 무거운 조회.
  ///
  /// `/quests/nearby`는 매번 TourAPI를 때려 새 퀘스트를 만들어 넣는다
  /// (`quest.service.ts:348`). 그 동기화가 있어야 처음 가는 동네에 퀘스트가
  /// 생기므로 버리지 않고, 대신 **지도를 옮길 때는 부르지 않는다.**
  Future<void> _syncNearbyQuests(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _isLoadingQuests = true);

    try {
      await QuestRepository.fetchNearbyQuests(
        lat: lat,
        lng: lng,
        radiusM: 5000,
      );
    } on ApiException catch (e) {
      debugPrint('주변 퀘스트 동기화 실패: ${e.code}');
    } catch (e) {
      debugPrint('주변 퀘스트 동기화 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoadingQuests = false);
    }

    // 동기화로 새로 생긴 퀘스트까지 포함해 화면 범위를 다시 그린다.
    await _refreshViewport();
  }

  /// 카메라가 멈췄다. 디바운스를 걸고 [_refreshViewport]로 넘긴다.
  void _onCameraIdle(LatLng center, int zoomLevel) {
    _kakaoLevel = zoomLevel;
    _cameraIdleTimer?.cancel();
    _cameraIdleTimer = Timer(_cameraIdleDebounce, () {
      if (!mounted) return;
      _refreshViewport();
    });
  }

  /// 지금 보이는 사각형으로 서버에 다시 물어본다.
  ///
  /// 여기가 **지도의 유일한 데이터 경로**다. 검색·키워드 필터도 앱에서
  /// 거르지 않고 이 호출의 파라미터로 들어간다 — 그래야 화면 밖에 있는
  /// 퀘스트도 조건에 맞으면 잡힌다.
  Future<void> _refreshViewport() async {
    final controller = _mapController;
    if (controller == null || !_isMapReady || !mounted) return;

    final request = ++_viewportRequest;
    setState(() => _isLoadingQuests = true);

    try {
      final bounds = await controller.getBounds();
      final result = await QuestRepository.fetchQuestsInBounds(
        swLat: bounds.sw.latitude,
        swLng: bounds.sw.longitude,
        neLat: bounds.ne.latitude,
        neLng: bounds.ne.longitude,
        zoom: MapZoom.fromKakaoLevel(_kakaoLevel),
        keywords: _selectedKeyword == null ? null : [_selectedKeyword!],
        search: _searchQuery,
      );

      // 늦게 도착한 옛 응답이 새 화면을 덮어쓰지 않게 한다.
      if (!mounted || request != _viewportRequest) return;

      setState(() {
        _quests = result.quests;
        _clusters = result.clusters;
        _totalInViewport = result.totalQuests;
        _isTruncated = result.isTruncated;
      });

      // 화면에서 사라진 퀘스트를 고른 채로 두면 시트만 떠 있고 핀이 없다.
      if (_selectedQuest != null &&
          !_quests.any((q) => q.id == _selectedQuest!.id)) {
        _closeSheet();
      }

      await _updateMarkers();
      await _syncCustomOverlays();
      _applyFocusRequest();
    } on ApiException catch (e) {
      debugPrint('뷰포트 조회 실패: ${e.code}');
    } catch (e) {
      // getBounds()는 WebView가 아직 준비되지 않았으면 파싱에서 터진다.
      debugPrint('뷰포트 조회 실패: $e');
    } finally {
      if (mounted && request == _viewportRequest) {
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

      // 지도를 먼저 옮긴다. 그래야 뒤이은 뷰포트 조회가 **내 주변**을 본다.
      // 순서를 뒤집으면 초기 중심(수원)의 범위를 조회하고 버리게 된다.
      if (panToUser && _mapController != null && _isMapReady) {
        await Future.delayed(const Duration(milliseconds: 100));
        await _mapController?.panTo(userLatLng);
      }

      // TourAPI 동기화 + 새 범위 조회. 여기서만 무거운 쪽을 부른다.
      await _syncNearbyQuests(lat, lng);
    } catch (e) {
      debugPrint('내 위치 가져오기 실패: $e');
    } finally {
      _isFetchingLocation = false;
    }
  }

  // ---------------------------------------------------------------------------
  // 검색 · 키워드 필터 — 체크리스트 11 · 12
  // ---------------------------------------------------------------------------

  /// 지도에 그릴 퀘스트.
  ///
  /// **앱에서 더 거르지 않는다.** 검색어·키워드는 이미 서버 쿼리로 나갔고,
  /// 여기서 한 번 더 걸러 봐야 서버가 이미 걸러 준 것을 다시 거를 뿐이다.
  /// 예전에는 이 게터가 로컬 필터였고, 그래서 화면 밖 퀘스트는 아무리
  /// 검색해도 나오지 않았다.
  List<QuestModel> get _visibleQuests => _quests;

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);

    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (!mounted) return;
      _runSearch();
    });
  }

  /// 전국 검색. 지도 범위를 **넘어서** 찾는다.
  ///
  /// 검색은 "지금 보이는 곳"이 아니라 "어디에 있는지"를 묻는 기능이라
  /// 뷰포트 조회와 별개로 좌표 없이 나간다(`quest.service.ts:289`가 좌표가
  /// 없으면 범위 조건을 빼고 전체에서 찾는다).
  Future<void> _runSearch() async {
    final query = _searchQuery.trim();

    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
      });
      // 검색어를 지웠으면 지금 화면 범위로 되돌린다.
      await _refreshViewport();
      return;
    }

    final request = ++_searchRequest;
    setState(() => _isSearching = true);

    try {
      final results = await QuestRepository.searchQuests(query);
      if (!mounted || request != _searchRequest) return;
      setState(() => _searchResults = results);
    } on ApiException catch (e) {
      if (!mounted || request != _searchRequest) return;
      setState(() => _searchResults = const []);
      debugPrint('검색 실패: ${e.code}');
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _isSearching = false);
      }
    }
  }

  /// 검색 결과를 골랐다 — 지도를 그 좌표로 옮기고 시트를 편다.
  Future<void> _openSearchResult(QuestModel quest) async {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchResults = const [];
      _selectedQuest = quest;
      _sheetState = _SheetState.preview;
    });
    FocusScope.of(context).unfocus();

    _mapController?.setCenter(LatLng(quest.latitude, quest.longitude));
    // 결과가 전국 어디든 될 수 있으니 확실히 보이는 축척까지 당긴다.
    _mapController?.setLevel(4);

    // setLevel/setCenter가 idle을 던지긴 하지만, 놓쳐도 목록이 비지 않도록
    // 한 번 직접 새로 고친다. 순번 덕분에 중복 응답은 무해하다.
    await _refreshViewport();
  }

  void _onKeywordChipTap(String? keyword) {
    setState(() => _selectedKeyword = keyword);
    _refreshViewport();
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

                        // 위치 권한을 거부했거나 GPS가 꺼져 있으면
                        // `_initUserLocation`이 아무것도 싣지 않고 끝난다.
                        // 그래도 지도는 초기 중심을 보여주고 있으므로,
                        // 최소한 그 범위의 퀘스트는 채워 준다.
                        if (mounted && _quests.isEmpty && _clusters.isEmpty) {
                          await _refreshViewport();
                        }
                      },
                      onMarkerTap: (markerId, latLng, zoomLevel) {
                        if (markerId == 'user_my_location_pin') return;

                        final matched = _quests.where((q) => q.id == markerId);
                        if (matched.isNotEmpty) {
                          _selectQuest(matched.first);
                        }
                      },
                      // 클러스터 원을 눌렀을 때. 커스텀 오버레이는 이 콜백을
                      // 넘겨야만 플러그인이 onclick 래퍼를 붙인다.
                      onCustomOverlayTap: _onCustomOverlayTap,
                      // 3b — 카메라가 멈추면 보이는 범위로 다시 조회한다.
                      onCameraIdle: _onCameraIdle,
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
                  if (_shouldShowEmptyNote) _buildEmptyResultNote(),
                  if (_isTruncated) _buildTruncatedNote(),

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
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
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
                  if (_isSearching)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.quest500,
                      ),
                    )
                  else if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textTertiary),
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
                  _filterChip(null),
                  for (final k in _keywordChips) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _filterChip(k),
                  ],
                ],
              ),
            ),
            if (_searchResults.isNotEmpty) _buildSearchResults(),
          ],
        ),
      ),
    );
  }

  /// [keyword]가 null이면 '전체' 칩이다.
  Widget _filterChip(String? keyword) {
    return Center(
      child: TagChip(
        label: keyword ?? '전체',
        isSelected: _selectedKeyword == keyword,
        fontSize: 12.5,
        onTap: () => _onKeywordChipTap(keyword),
      ),
    );
  }

  /// 전국 검색 결과 목록.
  ///
  /// 지도 밖 결과가 대부분이라 마커로는 보여줄 수 없다. 목록에서 고르면
  /// 그때 지도가 그 좌표로 옮겨 간다.
  Widget _buildSearchResults() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            itemCount: _searchResults.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (context, index) {
              final quest = _searchResults[index];
              return InkWell(
                onTap: () => _openSearchResult(quest),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quest.title,
                              style: AppType.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${quest.spotName} · ${quest.regionLabel}',
                              style: AppType.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        QuestRepository.distanceFromUser(quest),
                        style: AppType.numeric.copyWith(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 안내 문구를 띄울 상황인지.
  ///
  /// 클러스터가 떠 있으면 퀘스트가 **없는 게 아니라 묶여 있는 것**이다.
  /// 검색 결과 목록이 펼쳐져 있을 때도 지도 위 안내는 방해만 된다.
  bool get _shouldShowEmptyNote =>
      !_isLoadingQuests &&
      _quests.isEmpty &&
      _clusters.isEmpty &&
      _searchResults.isEmpty;

  Widget _buildEmptyResultNote() {
    final hasFilter = _selectedKeyword != null || _searchQuery.trim().isNotEmpty;

    return Positioned(
      left: 24,
      right: 24,
      top: 84,
      child: NoteBox(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          hasFilter ? '조건에 맞는 퀘스트가 없어요' : '이 범위에는 퀘스트가 없어요 · 지도를 옮겨 보세요',
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  /// 서버가 준 개수가 그릴 수 있는 양을 넘었을 때.
  ///
  /// 서버 `findMany`에 `take` 상한이 아직 없다(체크리스트 08번 BE 몫).
  /// 상한이 생기면 이 안내는 저절로 뜨지 않게 된다.
  Widget _buildTruncatedNote() {
    return Positioned(
      left: 24,
      right: 24,
      top: 84,
      child: NoteBox(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          '$_totalInViewport개 중 ${ViewportQuests.renderLimit}개만 표시했어요 · 지도를 확대해 보세요',
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
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