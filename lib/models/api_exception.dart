/// 백엔드가 `{ data, error: { code, message, details } }` 형태로 돌려준 실패를 감싼다.
///
/// **중요:** 이 백엔드는 HTTP 상태 코드를 신뢰할 수 없다.
/// `src/utils/CustomError.ts`의 `(string, string, any)` 분기가 statusCode를
/// 건드리지 않아, `AUTH_NOT_REGISTERED` · `UNAUTHORIZED` · `DUPLICATE_NICKNAME`이
/// 전부 **400**으로 나간다. 그러니 분기는 항상 [code] 문자열로 한다.
class ApiException implements Exception {
  /// 서버가 준 에러 코드 문자열. 통신 자체가 실패하면 [network].
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.details,
    this.statusCode = 0,
  });

  // ---------------------------------------------------------------------------
  // 클라이언트가 만들어내는 코드 (서버에서 오지 않는다)
  // ---------------------------------------------------------------------------
  static const String network = 'NETWORK_ERROR';
  static const String malformed = 'MALFORMED_RESPONSE';

  factory ApiException.fromNetworkFailure(Object cause) => ApiException(
        code: network,
        message: '서버에 연결하지 못했어요. 네트워크를 확인해 주세요.\n($cause)',
      );

  // ---------------------------------------------------------------------------
  // 서버 코드 판별자
  //   errorCodes.ts는 어디서도 import되지 않는 dead code라, 실제로 나가는 문자열은
  //   각 서비스가 `new CustomError(...)`에 직접 적은 값이다. 아래가 그 실제 목록.
  // ---------------------------------------------------------------------------
  bool get isNotRegistered => code == 'AUTH_NOT_REGISTERED';
  bool get isUnauthorized => code == 'UNAUTHORIZED' || statusCode == 401;
  bool get isDuplicateNickname => code == 'DUPLICATE_NICKNAME';
  /// 이미 수락해 진행 중이다. 오류가 아니라 "이어서 하기"다.
  bool get isAlreadyAccepted => code == 'QUEST_ALREADY_ACCEPTED';

  /// 이미 완료했다. 재수락·재인증 모두 서버가 막는다.
  bool get isAlreadyCompleted => code == 'QUEST_ALREADY_DONE';

  /// 인증 반경 밖. 서버는 `LOC_OUT_OF_RANGE`가 아니라 `OUT_OF_RANGE`를 쓴다.
  bool get isOutOfRange => code == 'OUT_OF_RANGE' || code == 'LOC_OUT_OF_RANGE';
  bool get isAccuracyTooLow => code == 'ACCURACY_TOO_LOW';
  bool get isNetwork => code == network;

  /// 사용자에게 그대로 보여줘도 되는 문구.
  String get displayMessage => message.isEmpty ? '알 수 없는 오류가 발생했어요.' : message;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
