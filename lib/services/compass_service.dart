import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 자기 나침반 방위각(0~360°, 0 = 북) 스트림.
///
/// **왜 geolocator를 안 쓰는가:** `Position.heading`은 GPS 진행 방향
/// (course over ground)이라 **서 있으면 값이 없다.** 지도의 "내가 보는 방향"은
/// 폰을 제자리에서 돌리기만 해도 따라와야 하므로 자기계가 필요하다.
///
/// **왜 flutter_compass를 안 쓰는가:** `flutter_compass`·`flutter_compass_v2`·
/// `compassx` 모두 라이브러리 매니페스트에 `package=` 속성이 남아 있고
/// `lintOptions`를 쓴다 — AGP 8부터 에러라 이 프로젝트(AGP 9)에서 빌드가 깨진다.
/// 그래서 `sensors_plus`로 원시 센서를 받아 직접 계산한다.
///
/// 계산은 안드로이드 `SensorManager.getRotationMatrix` + `getOrientation`과
/// 같은 식이다. `sensors_plus`가 iOS 축을 안드로이드 규약으로 맞춰 주므로
/// 두 플랫폼에서 같은 코드를 쓴다.
class CompassService {
  CompassService({
    this.smoothing = 0.18,
    this.minDeltaDegrees = 2.0,
    this.minInterval = const Duration(milliseconds: 100),
    this.declinationDegrees = -8.0,
  });

  /// 저역 통과 계수. 낮을수록 부드럽지만 늦게 따라온다.
  /// 자기계 원값은 손떨림만으로도 수 도씩 튄다.
  final double smoothing;

  /// 이만큼 돌아가기 전에는 새 값을 흘리지 않는다. WebView에 JS를 쏘는
  /// 비용이 있어서 1도 단위로 갱신할 이유가 없다.
  final double minDeltaDegrees;

  /// 방출 간격 하한. 센서는 초당 수십 번 들어온다.
  final Duration minInterval;

  /// 자편각 — 자북과 진북의 차이. 한국은 서편 약 8°.
  /// 카카오 지도는 항상 북쪽이 위이므로 진북으로 보정해야 화살표가 맞는다.
  final double declinationDegrees;

  StreamController<double>? _controller;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  /// 저역 통과를 거친 중력·지자기 벡터.
  List<double>? _gravity;
  List<double>? _geomagnetic;

  double? _lastEmitted;
  DateTime? _lastEmittedAt;

  /// 마지막으로 계산된 방위각. 구독 전에도 화면이 초기값을 물어볼 수 있다.
  double? get lastHeading => _lastEmitted;

  /// 구독하는 동안에만 센서가 돈다. 지도 화면을 벗어나면 자동으로 멈춘다.
  Stream<double> get headingStream {
    final existing = _controller;
    if (existing != null && !existing.isClosed) return existing.stream;

    final controller = StreamController<double>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    _controller = controller;
    return controller.stream;
  }

  void _start() {
    _accelSub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (event) {
        _gravity = _lowPass(_gravity, [event.x, event.y, event.z]);
        _emit();
      },
      // 센서가 없는 기기·에뮬레이터면 조용히 방향 표시만 빠진다.
      onError: (_) {},
      cancelOnError: false,
    );

    _magSub ??= magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (event) {
        _geomagnetic = _lowPass(_geomagnetic, [event.x, event.y, event.z]);
        _emit();
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _magSub?.cancel();
    _magSub = null;
    _gravity = null;
    _geomagnetic = null;
  }

  List<double> _lowPass(List<double>? previous, List<double> next) {
    if (previous == null) return next;
    return [
      for (var i = 0; i < 3; i++)
        previous[i] + smoothing * (next[i] - previous[i]),
    ];
  }

  void _emit() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;

    final heading = _computeHeading();
    if (heading == null) return;

    final now = DateTime.now();
    final lastAt = _lastEmittedAt;
    if (lastAt != null && now.difference(lastAt) < minInterval) return;

    final last = _lastEmitted;
    if (last != null && _angleDelta(last, heading).abs() < minDeltaDegrees) {
      return;
    }

    _lastEmitted = heading;
    _lastEmittedAt = now;
    controller.add(heading);
  }

  /// 두 각의 최단 차이(-180 ~ 180). 359°와 1°는 2° 차이지 358°가 아니다.
  static double _angleDelta(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  /// 중력·지자기 벡터에서 방위각을 만든다. 두 벡터가 거의 평행하면
  /// (자석 근처·자유낙하) 회전행렬을 만들 수 없어 null이다.
  double? _computeHeading() {
    final a = _gravity;
    final e = _geomagnetic;
    if (a == null || e == null) return null;

    // H = E × A — 동쪽을 가리키는 축
    final hx = e[1] * a[2] - e[2] * a[1];
    final hy = e[2] * a[0] - e[0] * a[2];
    final hz = e[0] * a[1] - e[1] * a[0];

    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return null;

    final normA = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    if (normA < 0.1) return null;

    // getOrientation의 azimuth = atan2(R[1], R[4]).
    // R[1] = Hy/|H|, R[4] = My = (Az*Hx - Ax*Hz)/(|A||H|)
    final r1 = hy / normH;
    final r4 = (a[2] / normA) * (hx / normH) - (a[0] / normA) * (hz / normH);

    final degrees =
        math.atan2(r1, r4) * 180 / math.pi + declinationDegrees;
    return (degrees % 360 + 360) % 360;
  }

  void dispose() {
    _stop();
    _controller?.close();
    _controller = null;
  }
}