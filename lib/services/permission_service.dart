import 'package:geolocator/geolocator.dart';

/// 위치 접근을 시도한 결과.
enum LocationAccess {
  granted,

  /// 이번엔 거절. 다시 물어볼 수 있다.
  denied,

  /// 영구 거절 — 앱 설정에서 직접 켜야 한다.
  deniedForever,

  /// 권한과 별개로 기기의 위치 기능 자체가 꺼져 있다.
  serviceDisabled,
}

/// 위치 권한 · 현재 위치를 다루는 한 곳.
///
/// 원래 이 흐름이 `map_screen.dart` 안에만 있어서, 온보딩의 권한 단계는
/// 버튼만 있고 실제로는 아무것도 요청하지 않았다. 여기로 끌어내 공유한다.
class PermissionService {
  const PermissionService._();

  /// 위치를 쓸 수 있는 상태로 만든다. 필요하면 시스템 권한 팝업을 띄운다.
  static Future<LocationAccess> ensureLocationAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  /// 이미 허용돼 있는지만 확인한다(팝업을 띄우지 않는다).
  static Future<bool> hasPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// 현재 위치. 권한이 없거나 측정에 실패하면 null.
  static Future<Position?> currentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!await hasPermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> openAppSettings() => Geolocator.openAppSettings();
  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();
}
