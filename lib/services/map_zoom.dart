/// 카카오 지도 레벨과 서버 zoom 사이의 환산.
///
/// **두 숫자는 방향이 반대다.**
///  - 카카오 `level`: 1이 가장 확대, 14가 가장 축소.
///  - 웹 지도 `zoom`(구글·네이버·OSM 계열, 우리 서버가 쓰는 것):
///    클수록 확대. `quest.service.ts:314`가 `zoom < 14`면 클러스터로 묶는다.
///
/// 카카오 레벨을 그대로 `zoom`으로 넘기면 **판정이 정확히 뒤집힌다** —
/// 골목까지 당겨 본 화면(level 3 → zoom 3)에서 클러스터가 나오고,
/// 전국을 펼친 화면(level 14 → zoom 14)에서 마커 수천 개가 쏟아진다.
class MapZoom {
  const MapZoom._();

  /// 카카오 레벨 ↔ 웹 zoom 환산 상수.
  ///
  /// 업계에서 통용되는 근사식 `webZoom = 21 - kakaoLevel`을 쓴다.
  /// 카카오 level 3(축척 50m)이 웹 zoom 18에, level 6(250m)이 15에 대응한다.
  static const int _pivot = 21;

  /// 카카오가 실제로 내주는 레벨 범위.
  static const int minKakaoLevel = 1;
  static const int maxKakaoLevel = 14;

  /// 서버가 클러스터를 돌려주기 시작하는 웹 zoom.
  static const int clusterZoomThreshold = 14;

  /// 이 카카오 레벨보다 축소하면 서버가 클러스터를 준다.
  ///
  /// `21 - 7 = 14`이므로 레벨 8부터(축척 1km쯤) 클러스터다. 사람이 보기에도
  /// 그쯤부터는 핀이 서로 겹쳐서 개별 마커가 의미를 잃는다.
  static const int clusterKakaoLevel = _pivot - clusterZoomThreshold; // 7

  /// 카카오 레벨 → 서버 zoom.
  static int fromKakaoLevel(int kakaoLevel) {
    final clamped = kakaoLevel.clamp(minKakaoLevel, maxKakaoLevel);
    return _pivot - clamped;
  }

  /// 서버 zoom → 카카오 레벨. 클러스터를 눌러 확대할 때 쓴다.
  static int toKakaoLevel(int webZoom) =>
      (_pivot - webZoom).clamp(minKakaoLevel, maxKakaoLevel);

  /// 이 레벨에서 서버가 클러스터를 돌려주는지.
  static bool isClusteredAt(int kakaoLevel) =>
      fromKakaoLevel(kakaoLevel) < clusterZoomThreshold;
}
