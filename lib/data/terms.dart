/// 약관 동의 항목과 문서 링크를 한곳에 모아 둔다.
///
/// 가입 화면(1c)과 설정 화면(5d)이 **같은 목록**을 본다. 두 군데에 따로
/// 적어 두면 한쪽만 고쳐지고, "동의는 받았는데 설정에서는 안 보이는" 항목이 생긴다.
///
/// 문서 본문은 **서버가 들고 있다**(`src/routes/legal.router.ts`). 앱에 문자열로
/// 심으면 고칠 때마다 앱을 새로 배포해야 하고, 그 사이 스토어에 걸린 문서와
/// 앱 안 문서가 갈라진다. 여기에는 주소만 둔다.
library;

/// 약관 문서가 올라가 있는 서버 주소.
///
/// API 서버와 같은 곳이지만 `/api/v1` 아래가 아니라 루트에 있다 — 스토어와
/// 브라우저가 바로 열 수 있어야 하기 때문이다. 그래서 [AppConfig] 의
/// `API_BASE_URL` 을 그대로 쓰지 않고 따로 받는다.
///
/// 값이 없으면 화면은 예전처럼 "준비 중"으로 그린다.
const String kLegalBaseUrl = String.fromEnvironment('LEGAL_BASE_URL');

String? _legalUrl(String path) =>
    kLegalBaseUrl.isEmpty ? null : '$kLegalBaseUrl$path';

/// 동의 항목 하나.
class TermsDocument {
  /// 저장·조회에 쓰는 안정된 키. 화면 문구가 바뀌어도 이 값은 그대로 둔다.
  final String key;

  /// 체크박스 옆에 보이는 이름.
  final String title;

  /// 동의하지 않으면 가입을 진행할 수 없는지.
  final bool isRequired;

  /// 공개된 문서 주소. null이면 아직 주소를 모른다는 뜻이다.
  ///
  /// 스토어(원스토어 상품 등록)도 이 주소를 요구하므로, 앱과 스토어가 같은
  /// 문서를 가리키게 된다.
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
final List<TermsDocument> kConsentDocuments = <TermsDocument>[
  TermsDocument(
    key: 'service',
    title: '서비스 이용약관',
    isRequired: true,
    url: _legalUrl('/terms/service'),
    summary: '로컬 퀘스트 계정을 만들고 퀘스트를 수행하는 데 적용되는 기본 약속입니다.',
  ),
  TermsDocument(
    key: 'location',
    title: '위치기반서비스 이용약관',
    isRequired: true,
    url: _legalUrl('/terms/location'),
    summary: '퀘스트를 찾고 도착을 인증하기 위해 내 위치를 사용합니다. '
        '이동 경로를 따로 저장하거나 다른 사람에게 공유하지 않습니다.',
  ),
  // 마케팅 동의는 문서가 아니라 한 줄짜리 약속이라 별도 페이지가 없다.
  TermsDocument(
    key: 'marketing',
    title: '마케팅 정보 수신',
    isRequired: false,
    summary: '새 퀘스트와 이벤트 소식을 받아봅니다. 동의하지 않아도 모든 기능을 쓸 수 있습니다.',
  ),
];

/// 동의는 받지 않고 보여주기만 하는 문서.
final List<TermsDocument> kNoticeDocuments = <TermsDocument>[
  TermsDocument(
    key: 'privacy',
    title: '개인정보 처리방침',
    isRequired: false,
    url: _legalUrl('/privacy'),
    summary: '수집하는 항목, 보관 기간, 파기 방법을 적어 둔 문서입니다.',
  ),
];

/// 화면 어디서든 문서를 찾아 쓰기 위한 합본.
final List<TermsDocument> kAllDocuments = <TermsDocument>[
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
/// 문서를 고칠 때마다 이 값을 함께 올려야, 누가 어느 판본에 동의했는지 남는다.
///
/// 값을 올리고 나면 이전 판본으로 가입한 사용자는 재동의 대상이 된다
/// (`AuthRepository.needsReconsent`). 재동의 화면은 아직 없다 — 첫 출시라
/// 대상자가 개발용 계정뿐이고, 실사용자가 생긴 뒤 문서를 고칠 때 필요해진다.
///
/// 이전 값 `2026-08-implicit-v1`은 **동의 화면 없이** 가입한 사용자들이고,
/// `2026-08-draft-v1`은 요약만 보고 동의한 사용자들이다.
const String kTermsVersion = '2026-09-v1';
