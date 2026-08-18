import 'dart:math';

/// 위경도 한 쌍. 지도 SDK 도입 전까지 앱 내부에서 쓰는 최소 좌표 타입.
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// 거리 · 속도 계산 유틸. 백엔드 geo.util.ts와 동일한 하버사인 공식을 사용합니다.
class Geo {
  const Geo._();

  static const double earthRadiusMeters = 6371000.0;

  /// 40km/h 초과 이동 구간은 도달로 인정하지 않음 (기획서 6d 안티 어뷰징)
  static const double abuseSpeedKmh = 40.0;

  /// GPS 정확도가 이 값을 넘으면 재측정을 요구함 (기획서 6d)
  static const double maxAccuracyMeters = 100.0;

  static double _rad(double degrees) => degrees * pi / 180;

  /// GeoPoint 좌표 객체 기반 거리 계산 (미터 단위)
  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) * cos(_rad(b.latitude)) * sin(dLng / 2) * sin(dLng / 2);
    return earthRadiusMeters * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  /// double 위경도 4개로 직접 거리를 계산하는 오버로드 메서드
  static double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return distanceMeters(
      GeoPoint(startLatitude, startLongitude),
      GeoPoint(endLatitude, endLongitude),
    );
  }

  /// 미터 단위 거리를 '350m' 또는 '1.2km' 형태로 포맷팅
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  /// from에서 to 방향으로 meters만큼 나아간 지점. 남은 거리가 더 짧으면 to를 그대로 반환.
  static GeoPoint moveToward(GeoPoint from, GeoPoint to, double meters) {
    final total = distanceMeters(from, to);
    if (total <= meters || total == 0) return to;
    final ratio = meters / total;
    return GeoPoint(
      from.latitude + (to.latitude - from.latitude) * ratio,
      from.longitude + (to.longitude - from.longitude) * ratio,
    );
  }

  static double speedKmh(GeoPoint from, GeoPoint to, Duration elapsed) {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds <= 0) return double.infinity;
    return (distanceMeters(from, to) / 1000) / (seconds / 3600);
  }

  /// 이전 인증 지점 대비 비정상적으로 빠른 이동인지 판정
  static bool isSpeedAbuse(GeoPoint from, GeoPoint to, Duration elapsed) {
    return speedKmh(from, to, elapsed) > abuseSpeedKmh;
  }
}
