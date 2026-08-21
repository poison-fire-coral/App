/// 홈 지역 선택지 — 남한 8권역.
///
/// 화면에 보이는 라벨과 서버에 저장하는 코드를 분리한다.
///
/// **저장값을 왜 '경기도'가 아니라 '경기'로 두는가**
/// `quest.service.ts:319`가 `place.regionCode == user.homeRegion` 완전일치로
/// 추천 퀘스트를 고른다. 그런데 카카오 로컬 API로 자동 생성되는 Place의
/// regionCode는 `address_name.split(" ")[0]`, 즉 '경기' · '서울' 같은 짧은 형태다.
/// 저장값을 그 형태에 맞춰야 매칭이 된다.
///
/// 광역시를 권역에 묶었으므로 매칭은 부분적이다(인천·대전 등은 자기 이름을 쓴다).
/// `/quests/recommended`는 지금 임계경로가 아니라 이 정도로 둔다.
class RegionOption {
  /// 드롭다운에 보이는 이름
  final String label;

  /// 서버 `users.home_region`에 저장하는 값
  final String code;

  const RegionOption(this.label, this.code);
}

const List<RegionOption> kRegionOptions = <RegionOption>[
  RegionOption('서울', '서울'),
  RegionOption('경기·인천', '경기'),
  RegionOption('강원', '강원'),
  RegionOption('충청·대전·세종', '충북'),
  RegionOption('전라·광주', '전남'),
  RegionOption('경북·대구', '경북'),
  RegionOption('경남·부산·울산', '경남'),
  RegionOption('제주', '제주'),
];

/// 서버에서 받은 코드로 선택지를 되찾는다. 모르는 값이면 null(미선택).
RegionOption? regionOptionForCode(String? code) {
  if (code == null || code.isEmpty) return null;
  for (final option in kRegionOptions) {
    if (option.code == code) return option;
  }
  return null;
}
