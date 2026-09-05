import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../config/app_config.dart';
import '../models/quest_model.dart';
import '../services/geo.dart';
import '../theme/app_assets.dart';
import 'heading_cone.dart';

/// 퀘스트 진행 중(4a)에 깔리는 지도.
///
/// **지도 화면(3a)과 다른 점은 "무엇을 그리지 않는가"다.** 여기서는 뷰포트·주변
/// 퀘스트 API를 한 번도 부르지 않는다. 넘겨받은 목적지 하나와 현위치만 그리므로
/// 다른 퀘스트 마커는 "지우는" 것이 아니라 **애초에 존재하지 않는다.** 이동 중에
/// 옆 퀘스트가 눈에 들어오면 지금 하는 것을 놓친다.
///
/// 그리는 것은 넷뿐이다 — 목적지 핀, 인증 반경 원, 현위치 점, 방향 부채꼴.
class QuestRouteMap extends StatefulWidget {
  /// 목적지 핀의 아이콘을 고르는 데만 쓴다(유형).
  final QuestModel quest;

  /// 이번에 가야 할 지점.
  final GeoPoint target;

  /// 인증 반경(m). 원의 반지름이 된다.
  final double radiusMeters;

  /// 현위치. 첫 표본이 오기 전에는 null — 그동안은 목적지만 보여준다.
  final GeoPoint? user;

  /// 지도 아래를 덮고 있는 시트의 높이(논리 픽셀).
  ///
  /// 지도는 화면 전체를 채우지만 아래쪽은 시트에 가려 실제로 보이는 띠는
  /// 그보다 짧다. 이 값을 모르면 카메라가 위젯 정중앙을 기준으로 맞춰서
  /// 현위치 점이 시트 뒤로 숨는다 — 실기기에서 실제로 그랬다.
  final double bottomInset;

  /// 나침반 방위각(도). 값이 null인 동안에는 부채꼴을 그리지 않는다.
  ///
  /// **왜 값이 아니라 [ValueListenable]인가.** 방위각은 초당 열 번 넘게 바뀌는데,
  /// 이걸 프로퍼티로 받으면 그때마다 부모가 setState를 해야 하고 지도까지 다시
  /// 빌드된다. 여기서 직접 구독하면 리빌드 없이 WebView 안 CSS만 돌릴 수 있다.
  final ValueListenable<double?> heading;

  const QuestRouteMap({
    super.key,
    required this.quest,
    required this.target,
    required this.radiusMeters,
    this.user,
    required this.heading,
    this.bottomInset = 0,
  });

  @override
  State<QuestRouteMap> createState() => _QuestRouteMapState();
}

class _QuestRouteMapState extends State<QuestRouteMap> {
  static const String _coneElementId = 'lq_route_cone';
  static const String _coneOverlayId = 'lq_route_cone_overlay';
  static const String _targetMarkerId = 'lq_route_target';
  static const String _userMarkerId = 'lq_route_user';
  static const String _radiusCircleId = 'lq_route_radius';

  /// 인장 붉은색. HTML 부채꼴이 쓰는 rgba(158,43,30)과 같은 값이다.
  static const Color _seal = Color(0xFF9E2B1E);

  /// 카카오맵 레벨 1에서 CSS 픽셀 하나가 덮는 거리(m). 레벨이 1 오를 때마다 두 배다.
  ///
  /// 실기기에서 재서 확인했다 — 레벨 5, 704m가 509 device px(DPR 3)이었으니
  /// 4.15 m/CSS px이고, 0.25 × 2^4 = 4.00과 맞는다.
  static const double _metersPerCssPixelAtLevel1 = 0.25;

  /// 위도 1도의 거리(m). 경도는 위도에 따라 줄지만 여기서는 남북으로만 민다.
  static const double _metersPerLatitudeDegree = 111320;

  /// 화면을 옮길 때 목표 지점을 보이는 띠의 어디에 둘지.
  /// 0.5는 한가운데. 시트 위 여백이 답답하지 않도록 살짝 위로 올린다.
  static const double _paddingFactor = 1.35;

  KakaoMapController? _controller;
  bool _isMapReady = false;

  /// 부채꼴을 이미 한 번 올렸는지. 올린 뒤에는 CSS 회전만 돌린다 —
  /// 오버레이를 다시 만들면 회전이 처음부터 시작해 튄다.
  bool _conePlaced = false;
  final ConeAngle _cone = ConeAngle();

  /// 카메라를 사용자 뜻과 무관하게 움직이는 것은 **처음 한 번뿐**이다.
  /// 이후에는 손으로 지도를 옮겨 둘 수 있어야 한다.
  bool _didFitCamera = false;

  final Map<String, MarkerIcon> _iconCache = {};

  /// 지도 위젯의 논리 크기. 레벨을 고르려면 "이 화면이 몇 픽셀인가"를 알아야 한다.
  Size _mapSize = Size.zero;

  LatLng get _targetLatLng =>
      LatLng(widget.target.latitude, widget.target.longitude);

  @override
  void initState() {
    super.initState();
    widget.heading.addListener(_applyHeading);
  }

  @override
  void dispose() {
    widget.heading.removeListener(_applyHeading);
    super.dispose();
  }

  @override
  void didUpdateWidget(QuestRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.heading, widget.heading)) {
      oldWidget.heading.removeListener(_applyHeading);
      widget.heading.addListener(_applyHeading);
    }

    // 지점이 바뀌면(여러 지점짜리 퀘스트의 다음 지점) 카메라를 다시 맞춘다.
    if (oldWidget.target != widget.target) {
      _didFitCamera = false;
      _conePlaced = false;
      unawaited(_redraw());
      return;
    }

    if (oldWidget.user != widget.user) {
      unawaited(_redraw());
    }
  }

  Future<MarkerIcon?> _icon(String assetPath) async {
    final cached = _iconCache[assetPath];
    if (cached != null) return cached;
    try {
      final icon = await MarkerIcon.fromAsset(assetPath);
      _iconCache[assetPath] = icon;
      return icon;
    } catch (e) {
      debugPrint('진행 지도 아이콘 로드 실패($assetPath): $e');
      return null;
    }
  }

  /// 마커·원·부채꼴을 현재 상태에 맞춰 다시 올린다.
  Future<void> _redraw() async {
    final controller = _controller;
    if (controller == null || !_isMapReady || !mounted) return;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final markers = <Marker>[];

    final targetIcon = await _icon(
      AppAssets.activeQuestMarker(
        questType: widget.quest.questType,
        devicePixelRatio: dpr,
      ),
    );
    // 논리 크기 43×55. 핀 끝점(아래 중앙)이 좌표에 꽂히도록 오프셋을 준다 —
    // 원본 36×46에서 끝점이 y=40이므로 높이의 40/46 지점이다.
    markers.add(
      Marker(
        markerId: _targetMarkerId,
        latLng: _targetLatLng,
        icon: targetIcon,
        width: 43,
        height: 55,
        offsetX: 21,
        offsetY: (55 * 40 / 46).round(),
        zIndex: 5,
      ),
    );

    final user = widget.user;
    if (user != null) {
      final userIcon = await _icon(AppAssets.myLocationMarker(dpr));
      markers.add(
        Marker(
          markerId: _userMarkerId,
          latLng: LatLng(user.latitude, user.longitude),
          icon: userIcon,
          width: 28,
          height: 28,
          offsetX: 14,
          offsetY: 14,
          zIndex: 10,
        ),
      );
    }

    try {
      await controller.clearMarker();
      await controller.addMarker(markers: markers);

      // 인증 반경 — 여기 들어와야 인증 버튼이 열린다는 것을 지도에서 바로 읽게 한다.
      await controller.addCircle(
        circles: [
          Circle(
            circleId: _radiusCircleId,
            center: _targetLatLng,
            radius: widget.radiusMeters,
            strokeWidth: 2,
            strokeColor: _seal,
            strokeOpacity: 0.9,
            strokeStyle: StrokeStyle.solid,
            fillColor: _seal,
            fillOpacity: 0.10,
          ),
        ],
      );

      await _placeCone();
      await _fitCameraOnce();
    } catch (e) {
      debugPrint('진행 지도 갱신 실패: $e');
    }
  }

  /// 부채꼴 오버레이를 현위치 위에 올린다.
  ///
  /// 같은 id로 다시 넘기면 플러그인이 "이미 있음"으로 조용히 무시하므로,
  /// 좌표를 옮기려면 한 번 비우고 다시 올리는 수밖에 없다.
  Future<void> _placeCone() async {
    final controller = _controller;
    final user = widget.user;
    final heading = widget.heading.value;
    if (controller == null || user == null || heading == null) return;

    try {
      await controller.clearCustomOverlay();
      await controller.addCustomOverlay(
        customOverlays: [
          CustomOverlay(
            customOverlayId: _coneOverlayId,
            latLng: LatLng(user.latitude, user.longitude),
            content: headingConeHtml(_coneElementId, _cone.advance(heading)),
            // 부채꼴의 회전 중심이 곧 현위치 좌표다.
            xAnchor: 0.5,
            yAnchor: 0.5,
            // 현위치 마커(10)보다 아래. 부채꼴은 점 바깥쪽에만 그려 겹치지 않는다.
            zIndex: 9,
          ),
        ],
      );
      _conePlaced = true;
    } catch (e) {
      debugPrint('방향 부채꼴 올리기 실패: $e');
    }
  }

  /// 방위각만 바뀐 경우 — 오버레이를 다시 만들지 않고 CSS 회전만 돌린다.
  void _applyHeading() {
    final controller = _controller;
    final heading = widget.heading.value;
    if (controller == null || heading == null) return;

    if (!_conePlaced) {
      unawaited(_placeCone());
      return;
    }

    final deg = _cone.advance(heading).toStringAsFixed(1);
    controller.webViewController.runJavaScript(
      'var e=document.getElementById("$_coneElementId");'
      'if(e){e.style.transform="rotate(${deg}deg)";}',
    );
  }

  /// 목적지와 현위치가 **둘 다 시트에 가리지 않고** 보이도록 처음 한 번만 맞춘다.
  ///
  /// 이후에는 손으로 지도를 옮겨 둘 수 있어야 하므로 다시 건드리지 않는다.
  Future<void> _fitCameraOnce() async {
    final controller = _controller;
    if (controller == null || _didFitCamera) return;

    final user = widget.user;
    if (user == null) {
      // 아직 현위치를 모르면 목적지만 적당한 배율로 보여준다.
      // _didFitCamera를 세우지 않아, 첫 표본이 오면 제대로 다시 맞춘다.
      controller.setCenter(_targetLatLng);
      controller.setLevel(4);
      return;
    }

    _didFitCamera = true;

    // 실제로 보이는 띠 — 시트에 덮이지 않은 부분만 센다.
    final visibleHeight = math.max(120.0, _mapSize.height - widget.bottomInset);
    final width = math.max(120.0, _mapSize.width);

    final distance = Geo.distanceMeters(user, widget.target);
    final level = _levelToFit(distance * _paddingFactor, math.min(width, visibleHeight));

    // 두 점의 중점을 보이는 띠 한가운데에 둔다. 지도 위젯의 중심은 시트에
    // 가려진 자리라, 중점을 그대로 놓으면 아래쪽 점이 시트 뒤로 들어간다.
    // 카메라 중심을 시트 높이의 절반만큼 **남쪽**으로 밀면 중점이 그만큼 위로 올라온다.
    final shiftMeters =
        _metersPerCssPixel(level) * (widget.bottomInset / 2);
    final shiftLat = shiftMeters / _metersPerLatitudeDegree;

    controller.setCenter(
      LatLng(
        (user.latitude + widget.target.latitude) / 2 - shiftLat,
        (user.longitude + widget.target.longitude) / 2,
      ),
    );
    controller.setLevel(level);
  }

  static double _metersPerCssPixel(int level) =>
      _metersPerCssPixelAtLevel1 * math.pow(2, level - 1);

  /// [spanMeters]가 [cssPixels] 안에 들어오는 가장 가까운(= 가장 작은) 레벨.
  /// 카카오맵은 레벨이 클수록 멀어지고 1이 하한, 14가 상한이다.
  static int _levelToFit(double spanMeters, double cssPixels) {
    for (var level = 1; level <= 14; level++) {
      if (_metersPerCssPixel(level) * cssPixels >= spanMeters) return level;
    }
    return 14;
  }

  @override
  Widget build(BuildContext context) {
    // 키가 없으면 지도가 뜰 수 없다. 빈 상자를 돌려 부모가 폴백을 그리게 한다.
    if (AppConfig.kakaoJavaScriptKey.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _mapSize = constraints.biggest;
        return _buildMap();
      },
    );
  }

  Widget _buildMap() {
    return KakaoMap(
      key: const ValueKey('quest_route_map_webview'),
      center: _targetLatLng,
      markers: const [],
      onMapCreated: (controller) async {
        _controller = controller;
        // 지도 화면(3a)과 같은 이유로 기다린다 — WebView 안의 kakao.maps가
        // onMapCreated 시점에 아직 준비되지 않아 바로 그리면 조용히 실패한다.
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        _isMapReady = true;
        await _redraw();
      },
    );
  }
}
