/// 디자인 시스템 v1.0 (Parchment & Seal) — 에셋 경로 카탈로그
///
/// 화면에서 'assets/...' 문자열을 직접 쓰지 말고 항상 이 클래스를 거친다.
/// 파일 구조가 바뀌어도 여기 한 곳만 고치면 된다.
class AppAssets {
  const AppAssets._();

  // ---------------------------------------------------------------------------
  // 아바타 프리셋 6종
  //   DB(User.avatarId)에는 'avatar_03' 같은 **id만** 저장한다.
  //   경로를 저장하면 에셋 구조를 못 바꾸게 된다.
  // ---------------------------------------------------------------------------
  static const List<String> avatarIds = <String>[
    'avatar_01', // 첫 모험가 · 밀짚모자
    'avatar_02', // 사진스팟 · 카메라
    'avatar_03', // 산·트레킹 · 비니
    'avatar_04', // 골목산책 · 헤드폰
    'avatar_05', // 역사·박물관 · 안경과 책
    'avatar_06', // 시장·먹기 · 두건
  ];

  static const String defaultAvatarId = 'avatar_01';

  /// 알 수 없는 id는 조용히 기본값으로 떨어뜨린다.
  /// (구버전 캐시에 'assets/avatars/avatar_1.png' 같은 값이 남아 있을 수 있다)
  static String normalizeAvatarId(String? raw) {
    if (raw == null) return defaultAvatarId;
    return avatarIds.contains(raw) ? raw : defaultAvatarId;
  }

  static String avatarPath(String? avatarId) =>
      'assets/avatars/${normalizeAvatarId(avatarId)}.svg';

  // ---------------------------------------------------------------------------
  // 일러스트 · 브랜드
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // 배지 아트
  //   서버는 `Badge.artUrl`에 'first_step' 같은 **키만** 저장한다.
  //   경로를 DB에 넣으면 에셋 구조를 못 바꾸게 된다.
  // ---------------------------------------------------------------------------
  static const List<String> badgeArtKeys = <String>[
    'first_step', 'twenty_steps',
    'region_gyeonggi', 'region_seoul', 'region_jeju', 'region_all',
    'type_photo', 'type_collect', 'type_quiz',
    'type_explore', 'type_time', 'type_record',
    'hidden_dawn',
  ];

  /// 모르는 키가 오면 null. 위젯이 자물쇠 아이콘으로 대신 그린다.
  static String? badgeArtPath(String? artKey) {
    if (artKey == null || !badgeArtKeys.contains(artKey)) return null;
    return 'assets/badges/$artKey.svg';
  }

  // ---------------------------------------------------------------------------
  // 지도 마커 (4단계)
  //   `test/generate_marker_icons_test.dart`가 구워낸 PNG다. SVG는 못 쓴다 —
  //   kakao_map_plugin이 에셋 바이트를 `new Blob([...], {type:'image/png'})`로
  //   되살리기 때문에 MIME이 PNG로 고정이다.
  //
  //   **모양은 퀘스트 유형, 색은 난이도.** 색만 다르면 색약 사용자가 구별하지 못한다.
  // ---------------------------------------------------------------------------
  static const List<String> markerQuestTypes = <String>[
    'VISIT', 'TIME_WINDOW', 'PHOTO_SINGLE', 'PHOTO_COLLECT',
    'QUIZ', 'EXPLORATION', 'RECORD',
  ];

  /// Flutter의 `2.0x/` 변형 규약을 쓰지 않는다 — 플러그인이 `rootBundle.load`로
  /// 경로를 직접 읽어서 변형 해석이 일어나지 않는다. 그래서 배율을 손으로 고른다.
  static String _suffix(double devicePixelRatio) {
    if (devicePixelRatio >= 2.5) return '@3x';
    if (devicePixelRatio >= 1.5) return '@2x';
    return '';
  }

  static String questMarker({
    required String questType,
    required int stars,
    required double devicePixelRatio,
  }) {
    final type = markerQuestTypes.contains(questType) ? questType : 'VISIT';
    final tier = stars.clamp(1, 5);
    return 'assets/markers/${type.toLowerCase()}_t$tier'
        '${_suffix(devicePixelRatio)}.png';
  }

  /// 진행 중인 퀘스트 핀.
  ///
  /// 원칙은 **색 = 난이도**지만 진행 중인 퀘스트만은 예외로 브랜드 강조색
  /// (quest500)으로 통일한다. 지도에서 "지금 내가 하고 있는 것"을 먼저 찾아야 하고,
  /// 그 핀의 난이도는 이미 홈 캐러셀에서 보고 수락한 뒤다.
  ///
  /// 새 PNG를 굽지 않고 5성 아트를 빌려 쓴다 — 5성 색이 이미 quest500이고,
  /// 에셋 생성기는 `test/`에 있어 앱 코드에서 손댈 수 없다. 5성 퀘스트와 겹치는
  /// 만큼은 [MapScreen]이 핀을 키우고 위로 올려 구분한다.
  static String activeQuestMarker({
    required String questType,
    required double devicePixelRatio,
  }) {
    return questMarker(
      questType: questType,
      stars: 5,
      devicePixelRatio: devicePixelRatio,
    );
  }

  static String myLocationMarker(double devicePixelRatio) =>
      'assets/markers/my_location${_suffix(devicePixelRatio)}.png';

  static const String locationPermission =
      'assets/illustrations/location_permission.svg';
  static const String logo = 'assets/brand/logo.svg';
}
