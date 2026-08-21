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
  static const String locationPermission =
      'assets/illustrations/location_permission.svg';
  static const String logo = 'assets/brand/logo.svg';
}
