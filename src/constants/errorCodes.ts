export const ERROR_CODES = {
  // 인증/계정 관련 (S1)
  AUTH_NOT_REGISTERED: {
    status: 401,
    code: "AUTH_NOT_REGISTERED",
    message: "회원가입이 되지 않은 계정입니다.",
  },
  UNAUTHORIZED: {
    status: 401,
    code: "UNAUTHORIZED",
    message: "인증 토큰이 유효하지 않습니다.",
  },
  DUPLICATE_NICKNAME: {
    status: 409,
    code: "DUPLICATE_NICKNAME",
    message: "이미 사용 중인 닉네임입니다.",
  },

  // 퀘스트/위치 관련 (S2~S3)
  LOC_OUT_OF_RANGE: {
    status: 400,
    code: "LOC_OUT_OF_RANGE",
    message: "인증 가능 거리(50m)를 벗어났습니다.",
  },
  QUEST_ALREADY_DONE: {
    status: 400,
    code: "QUEST_ALREADY_DONE",
    message: "이미 완료한 퀘스트입니다.",
  },
  ABUSE_SPEED: {
    status: 400,
    code: "ABUSE_SPEED",
    message: "비정상적인 이동 속도가 감지되었습니다.",
  },

  // 공통
  BAD_REQUEST: {
    status: 400,
    code: "BAD_REQUEST",
    message: "잘못된 요청 파라미터입니다.",
  },
  NOT_FOUND: {
    status: 404,
    code: "NOT_FOUND",
    message: "요청한 리소스를 찾을 수 없습니다.",
  },
  INTERNAL_SERVER_ERROR: {
    status: 500,
    code: "INTERNAL_SERVER_ERROR",
    message: "서버 내부 오류가 발생했습니다.",
  },
};