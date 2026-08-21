import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../dev/dev_tools.dart'; // DEV-ONLY
import 'geo.dart';
import 'location_service.dart';

/// 진짜 GPS로 [LocationService]를 채운다.
///
/// 4a 화면은 그동안 `SimulatedLocationService`만 받고 있었다
/// (`main.dart`가 `locationService`를 넘기지 않아서). 이제 이걸 주입한다.
class GeolocatorLocationService implements LocationService {
  StreamSubscription<Position>? _subscription;
  StreamController<LocationSample>? _controller;

  /// DEV-ONLY — 순간이동. null이 아니면 이 좌표를 방출한다.
  GeoPoint? _teleport;

  /// DEV-ONLY — 정확도 위조. `ACCURACY_TOO_LOW` 경로를 재현할 때 쓴다.
  double? _forcedAccuracy;

  @override
  Stream<LocationSample> track(GeoPoint target) {
    _controller?.close();
    final controller = StreamController<LocationSample>.broadcast();
    _controller = controller;

    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3, // 3m 이상 움직였을 때만
      ),
    ).listen(
      (position) => controller.add(_toSample(position)),
      onError: controller.addError,
    );

    // 스트림 구독 직후엔 아무 값도 안 와서 화면이 비어 보인다. 마지막 위치로 먼저 채운다.
    unawaited(_emitSeed(controller));

    return controller.stream;
  }

  Future<void> _emitSeed(StreamController<LocationSample> controller) async {
    // DEV-ONLY: 순간이동/위치고정이 걸려 있으면 그 값을 먼저 흘린다.
    final overridden = _teleport ?? DevTools.locationOverride;
    if (overridden != null) {
      if (!controller.isClosed) {
        controller.add(LocationSample(
          point: overridden,
          accuracyMeters: _forcedAccuracy ?? 8,
          isSimulated: true,
        ));
      }
      return;
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && !controller.isClosed) {
        controller.add(_toSample(last));
      }
    } catch (_) {
      // 마지막 위치가 없으면 그냥 스트림을 기다린다.
    }
  }

  LocationSample _toSample(Position position) {
    // DEV-ONLY — 위조가 걸려 있으면 실제 측정값 대신 그것을 쓴다.
    final overridden = _teleport ?? DevTools.locationOverride;
    if (overridden != null) {
      return LocationSample(
        point: overridden,
        accuracyMeters: _forcedAccuracy ?? 8,
        isSimulated: true,
      );
    }

    return LocationSample(
      point: GeoPoint(position.latitude, position.longitude),
      accuracyMeters: _forcedAccuracy ?? position.accuracy,
      isSimulated: _forcedAccuracy != null,
    );
  }

  // ---------------------------------------------------------------------------
  // DEV-ONLY — 개발 패널이 부르는 조작기들
  // ---------------------------------------------------------------------------

  /// 목표 지점으로 순간이동한다.
  ///
  /// 서버는 클라이언트가 보낸 좌표로 거리를 재검증하므로(`quest.service.ts:449`),
  /// 위조한 좌표를 그대로 verify에 실어 보내면 거리 검사를 정상 통과한다.
  /// 백엔드를 손대지 않고도 EXP·레벨업 로직이 진짜로 돈다.
  void teleportTo(GeoPoint point) {
    _teleport = point;
    _pushCurrent();
  }

  /// 목표에서 [meters]만큼 떨어진 지점으로. `OUT_OF_RANGE`를 재현할 때 쓴다.
  void teleportNear(GeoPoint target, double meters) {
    // 위도 1도 ≈ 111,320m. 북쪽으로 밀어낸다.
    final offsetLat = target.latitude + (meters / 111320.0);
    teleportTo(GeoPoint(offsetLat, target.longitude));
  }

  /// 정확도를 강제한다. 100m를 넘기면 `needsRemeasure`와 서버 `ACCURACY_TOO_LOW`가 뜬다.
  void forceAccuracy(double? meters) {
    _forcedAccuracy = meters;
    _pushCurrent();
  }

  void clearOverrides() {
    _teleport = null;
    _forcedAccuracy = null;
  }

  void _pushCurrent() {
    final controller = _controller;
    final point = _teleport ?? DevTools.locationOverride;
    if (controller == null || controller.isClosed || point == null) return;
    controller.add(LocationSample(
      point: point,
      accuracyMeters: _forcedAccuracy ?? 8,
      isSimulated: true,
    ));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller?.close();
    _controller = null;
  }
}
