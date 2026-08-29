import 'dart:async';

import 'geo.dart';

/// 위치 한 번 측정한 결과.
class LocationSample {
  final GeoPoint point;
  final double accuracyMeters;

  /// 실제 GPS가 아니라 시뮬레이터가 만든 값인지. 안티 어뷰징 판정을 건너뛰는 근거가 된다.
  ///
  /// **[isMocked]와 다르다.** 이쪽은 *우리가* 만든 값(개발 도구·시뮬레이터)이라
  /// 서버에 보내지 않는다. 저쪽은 *사용자가* 위치 위조 앱을 켰다는 뜻이다.
  final bool isSimulated;

  /// 운영체제가 "이 좌표는 모의 위치 앱이 만든 것"이라고 표시한 표본인지.
  ///
  /// 안드로이드의 개발자 옵션 > 모의 위치 앱, iOS의 시뮬레이터·일부 탈옥 도구가
  /// 여기에 걸린다. 체크리스트 18번 — 인증 요청에 그대로 실어 서버가 판단하게 한다.
  ///
  /// 클라이언트 값이라 마음먹으면 속일 수 있다. 그래도 **없는 것보다 낫다** —
  /// 대충 위조 앱만 깐 사람은 걸리고, 걸린 기록이 남는다.
  final bool isMocked;

  const LocationSample({
    required this.point,
    required this.accuracyMeters,
    this.isSimulated = false,
    this.isMocked = false,
  });

  /// GPS 정확도 100m 초과 시 재측정 요구 (기획서 6d)
  bool get needsRemeasure => accuracyMeters > Geo.maxAccuracyMeters;
}

/// 4a 이동·도달 화면에 현재 위치를 공급한다.
///
/// 프로젝트에 아직 GPS 플러그인(geolocator 등)이 없어 지금은 시뮬레이터 구현만 있다.
/// 실제 GPS를 붙일 때는 이 인터페이스를 구현한 클래스를 하나 더 만들어
/// [QuestActiveScreen]에 넘기면 화면 코드는 그대로 둔 채 교체할 수 있다.
abstract class LocationService {
  /// [target]을 향해 이동하는 동안의 위치 표본 스트림.
  Stream<LocationSample> track(GeoPoint target);

  void dispose();
}

/// 목적지를 향해 일정 속도로 접근하는 이동 시뮬레이터.
///
/// 데모용이므로 실제 도보 속도(약 1.4m/s)가 아니라 화면당 15초 남짓에 도착하도록
/// 남은 거리를 [stepCount]등분해 전진한다. 이 값은 GPS 측정이 아니므로
/// 40km/h 어뷰징 판정 대상에서 제외한다([LocationSample.isSimulated]).
class SimulatedLocationService implements LocationService {
  final GeoPoint origin;
  final Duration tick;
  final int stepCount;
  final double accuracyMeters;

  /// 마지막으로 내보낸 위치. 여러 지점짜리 퀘스트에서 다음 구간을
  /// 앞 구간이 끝난 자리에서 이어가기 위해 track() 호출 사이에도 유지한다.
  late GeoPoint _current;

  StreamController<LocationSample>? _controller;
  Timer? _timer;

  SimulatedLocationService({
    required this.origin,
    this.tick = const Duration(milliseconds: 400),
    this.stepCount = 36,
    this.accuracyMeters = 12,
  }) {
    _current = origin;
  }

  @override
  Stream<LocationSample> track(GeoPoint target) {
    dispose();

    final step = Geo.distanceMeters(_current, target) / stepCount;
    final controller = StreamController<LocationSample>();
    _controller = controller;

    void emit() {
      if (controller.isClosed) return;
      controller.add(
        LocationSample(point: _current, accuracyMeters: accuracyMeters, isSimulated: true),
      );
    }

    controller.onListen = () {
      emit();
      _timer = Timer.periodic(tick, (timer) {
        if (controller.isClosed) {
          timer.cancel();
          return;
        }
        if (_current == target) {
          timer.cancel();
          return;
        }
        _current = Geo.moveToward(_current, target, step);
        emit();
      });
    };
    controller.onCancel = () {
      _timer?.cancel();
      _timer = null;
    };

    return controller.stream;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }
}
