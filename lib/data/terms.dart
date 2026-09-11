library;

/// 약관 문서가 올라가 있는 서버 주소.
/// 개발 중에는 ngrok 주소를 기본값으로 지정하여 환경 변수가 없어도 정상 동작합니다.
const String kLegalBaseUrl = String.fromEnvironment(
  'LEGAL_BASE_URL',
  defaultValue: 'https://chewing-asleep-vest.ngrok-free.dev',
);

String? _legalUrl(String path) =>
    kLegalBaseUrl.isEmpty ? null : '$kLegalBaseUrl$path';

/// 동의 항목 하나.
class TermsDocument {
  final String key;
  final String title;
  final bool isRequired;
  final String? url;
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
  TermsDocument(
    key: 'marketing',
    title: '마케팅 정보 수신',
    isRequired: false,
    url: _legalUrl('/terms/marketing'),
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

const String kTermsVersion = '2026-09-v1';