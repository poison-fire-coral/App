/// 온보딩 키워드와 서버 퀘스트 키워드를 잇는 표.
///
/// **왜 필요한가**
/// 두 어휘가 완전히 다르다.
///  - 온보딩(1e)이 저장하는 값: `골목산책` · `로컬맛집` 처럼 합성어 26종.
///  - 서버 `Quest.keywords`에 실제로 들어 있는 값: `골목` · `산책` · `맛집` 처럼
///    한 단어짜리. 시드 21건과 TourAPI 자동 생성분 모두 이 형태다.
///
/// 그래서 온보딩 값을 `GET /quests?keywords=`에 그대로 넘기면 **결과가 항상 0건**이다.
/// `QuestRepository.fetchNearbyQuests`의 주석이 "매핑 테이블이 생기기 전까지
/// keywords는 지도 필터에서만 쓴다"고 미뤄 둔 게 바로 이 표다.
///
/// **어디에 쓰는가**
///  - 지도 필터 칩(3a)의 순서: 내가 고른 취향이 앞에 온다.
///  - 서버 필터: 칩을 누르면 그 서버 키워드가 `?keywords=`로 나간다.
///
/// **늘릴 때**
/// 서버 쪽 어휘가 바뀌면 [_styleToQuestKeywords]의 값과 [commonQuestKeywords]를
/// 함께 고친다. 이 파일 밖에서 서버 키워드 문자열을 직접 적지 않는다.
library;

class KeywordTaxonomy {
  const KeywordTaxonomy._();

  /// 온보딩 키워드(해시 없는 저장형) → 서버 퀘스트 키워드들.
  static const Map<String, List<String>> _styleToQuestKeywords = {
    // 먹기
    '로컬맛집': ['맛집', '음식', '로컬'],
    '전통시장': ['시장', '쇼핑', '로컬'],
    '카페투어': ['음식', '힐링'],
    '노포·백년가게': ['맛집', '음식', '로컬', '역사'],
    '야시장': ['시장', '음식', '새벽'],
    '술한잔': ['음식', '로컬'],

    // 걷기
    '골목산책': ['골목', '산책', '탐방'],
    '바다·해안': ['바다', '자연', '산책'],
    '산·트레킹': ['자연', '체력', '액티비티', '스포츠'],
    '강·호수': ['자연', '산책', '힐링'],
    '들판·논밭': ['자연', '산책'],
    '숲길·섬': ['자연', '산책', '힐링'],

    // 배우기
    '역사유적': ['역사', '문화', '관광', '명소'],
    '한옥·고택': ['역사', '문화', '근대건축'],
    '박물관': ['문화', '전시', '역사'],
    '미술관': ['문화', '전시'],
    '근대건축': ['근대건축', '역사', '문화'],
    '폐공간': ['탐색', '근대건축', '탐험'],
    '종교건축': ['역사', '문화', '명소'],

    // 즐기기
    '사진스팟': ['사진', '명소', '풍경'],
    '야경·일출일몰': ['노을', '야경', '사진', '풍경'],
    '공방·체험': ['체험', '문화', '액티비티'],
    '축제·행사': ['축제', '이벤트', '체험'],
    '벽화·거리예술': ['골목', '사진', '탐색'],
    '독립서점': ['로컬', '문화'],
    '소품샵': ['쇼핑', '로컬'],

    // 사람
    '주민이야기': ['로컬', '기록'],
    '로컬브랜드': ['로컬', '쇼핑'],
    '드라마촬영지': ['명소', '사진', '관광'],
    '전설·설화': ['역사', '문화', '탐험'],
  };

  /// 지도 필터 칩에 항상 띄우는 서버 키워드.
  ///
  /// 화면에 보이는 목록을 **결과에서 뽑지 않는 이유**: 서버 필터를 걸면 결과가
  /// 줄고, 결과에서 칩을 만들면 방금 누른 칩 말고 전부 사라진다. 되돌릴 방법이
  /// 없어진다. 그래서 목록은 고정해 두고 결과와 무관하게 유지한다.
  static const List<String> commonQuestKeywords = [
    '골목', '산책', '자연', '바다', '역사', '문화', '전시',
    '맛집', '음식', '시장', '로컬', '사진', '명소', '풍경',
    '축제', '체험', '힐링', '탐험', '탐색', '기록', '쇼핑',
    '근대건축', '새벽', '노을', '체력', '액티비티',
  ];

  /// 해시(`#`)를 떼어 저장형으로 만든다.
  static String normalize(String raw) =>
      raw.startsWith('#') ? raw.substring(1) : raw;

  /// 온보딩 키워드 하나가 가리키는 서버 키워드들.
  static List<String> questKeywordsForStyle(String style) =>
      _styleToQuestKeywords[normalize(style)] ?? const [];

  /// 사용자의 취향 전체를 서버 키워드로 편다.
  ///
  /// 순서를 지킨다 — 앞쪽 취향에서 나온 키워드가 필터 칩에서도 앞에 온다.
  /// 중복은 처음 나온 자리에 남긴다.
  static List<String> questKeywordsForStyles(Iterable<String> styles) {
    final ordered = <String>{};
    for (final style in styles) {
      ordered.addAll(questKeywordsForStyle(style));
    }
    return ordered.toList();
  }

  /// 지도 필터 칩에 그릴 순서.
  ///
  /// 내 취향에서 나온 키워드가 먼저, 그다음이 나머지 공통 키워드다.
  /// 취향을 고르지 않은 사용자는 [commonQuestKeywords] 순서를 그대로 본다.
  static List<String> filterChipOrder(Iterable<String> travelStyles) {
    final preferred = questKeywordsForStyles(travelStyles);
    return [
      ...preferred,
      ...commonQuestKeywords.where((k) => !preferred.contains(k)),
    ];
  }
}
