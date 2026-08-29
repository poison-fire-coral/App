/// 약관 동의 항목과 문서 링크를 한곳에 모아 둔다.
///
/// 가입 화면(1c)과 설정 화면(5d)이 **같은 목록**을 본다. 두 군데에 따로
/// 적어 두면 한쪽만 고쳐지고, "동의는 받았는데 설정에서는 안 보이는" 항목이 생긴다.
///
/// **아직 문서가 없다** — 체크리스트 04번(약관 3종 작성)은 코드가 아니라 문서
/// 작업이라 여기서 끝낼 수 없다. 그래서 [TermsDocument.url]을 null로 두고
/// 화면은 "준비 중"으로 그린다. 문서가 서면 이 파일에서 url만 채우면 되고,
/// 화면 코드는 건드리지 않는다.
library;

/// 동의 항목 하나.
class TermsDocument {
  /// 저장·조회에 쓰는 안정된 키. 화면 문구가 바뀌어도 이 값은 그대로 둔다.
  final String key;

  /// 체크박스 옆에 보이는 이름.
  final String title;

  /// 동의하지 않으면 가입을 진행할 수 없는지.
  final bool isRequired;

  /// 공개된 문서 주소. null이면 아직 문서가 없다는 뜻이다.
  ///
  /// 체크리스트 34번(개인정보처리방침 공개 URL 게시)이 끝나면 그 주소를 넣는다.
  /// 구글 플레이 심사가 개인정보처리방침만큼은 **URL**을 요구한다.
  final String? url;

  /// 문서가 없는 동안 최소한 무엇에 동의하는지는 알려준다.
  /// 문서 요약이지 문서 대체가 아니다.
  final String summary;

  const TermsDocument({
    required this.key,
    required this.title,
    required this.isRequired,
    required this.summary,
    this.url,
  });

  bool get hasDocument => url != null && url!.isNotEmpty;
}

/// 가입 시 동의받는 항목 — 필수 2 + 선택 1.
///
/// 개인정보 처리방침은 "동의" 대상이 아니라 **고지** 대상이라 이 목록이 아니라
/// [kNoticeDocuments]에 둔다. 동의 항목을 늘리면 늘릴수록 가입 이탈이 늘고,
/// 법적으로 필요한 것은 이용약관·위치기반서비스 두 가지다.
const List<TermsDocument> kConsentDocuments = <TermsDocument>[
  TermsDocument(
    key: 'service',
    title: '서비스 이용약관',
    isRequired: true,
    summary: '로컬 퀘스트 계정을 만들고 퀘스트를 수행하는 데 적용되는 기본 약속입니다.',
  ),
  TermsDocument(
    key: 'location',
    title: '위치기반서비스 이용약관',
    isRequired: true,
    summary: '퀘스트를 찾고 도착을 인증하기 위해 내 위치를 사용합니다. '
        '이동 경로를 따로 저장하거나 다른 사람에게 공유하지 않습니다.',
  ),
  TermsDocument(
    key: 'marketing',
    title: '마케팅 정보 수신',
    isRequired: false,
    summary: '새 퀘스트와 이벤트 소식을 받아봅니다. 동의하지 않아도 모든 기능을 쓸 수 있습니다.',
  ),
];

/// 동의는 받지 않고 보여주기만 하는 문서.
const List<TermsDocument> kNoticeDocuments = <TermsDocument>[
  TermsDocument(
    key: 'privacy',
    title: '개인정보 처리방침',
    isRequired: false,
    summary: '수집하는 항목, 보관 기간, 파기 방법을 적어 둔 문서입니다.',
  ),
];

/// 화면 어디서든 문서를 찾아 쓰기 위한 합본.
const List<TermsDocument> kAllDocuments = <TermsDocument>[
  ...kConsentDocuments,
  ...kNoticeDocuments,
];

TermsDocument? termsDocumentFor(String key) {
  for (final doc in kAllDocuments) {
    if (doc.key == key) return doc;
  }
  return null;
}

/// 서버 `users.terms_version`에 남기는 값.
///
/// 이 문자열이 가리키는 것은 **사용자가 읽고 동의한 문서의 판본**이다.
/// 지금은 문서 자체가 없으므로 `draft`라고 솔직하게 적는다.
///
/// 04번(약관 3종 작성)이 끝나면
///   1. 이 상수를 문서 개정일자(예: `2026-09-v1`)로 바꾸고,
///   2. [kConsentDocuments]의 `url`을 채우고,
///   3. 그 이전 버전으로 가입한 사용자에게 재동의를 받는다.
///      (`user.termsVersion != kTermsVersion` 이면 재동의 화면을 띄우는 식)
///
/// 이전 값 `2026-08-implicit-v1`은 **동의 화면 없이** 가입한 사용자들이다.
/// 그 사용자들은 재동의 대상이라는 사실을 문자열만으로 구분할 수 있어야 한다.
const String kTermsVersion = '2026-08-draft-v1';
