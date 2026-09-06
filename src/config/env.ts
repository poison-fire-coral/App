import "dotenv/config";

/**
 * 환경 변수를 **기동 시점에 한 번** 확인한다.
 *
 * **왜 파일 하나로 모으는가.** 예전에는 각 모듈이 필요할 때마다 `process.env`를
 * 직접 읽었고, 그중 `jwt.ts`는 값이 없으면 `"default_jwt_secret_key"`로 조용히
 * 넘어갔다. 저장소에 그대로 적혀 있는 문자열이라, 배포에서 `JWT_SECRET`을
 * 빠뜨리면 **아무나 남의 토큰을 만들 수 있는 서버가 정상 기동한다.**
 * 없으면 뜨지 않는 편이 낫다 — 배포 직후에 알게 되는 것과 몇 달 뒤에 알게 되는
 * 것의 차이다.
 *
 * 또 하나: 읽는 시점도 문제였다. `index.ts`가 `dotenv.config()`를 부르기 전에
 * `import app`이 먼저 돌아서, 모듈 최상단에서 `process.env`를 읽는 파일은
 * 순서에 기대고 있었다. 여기서 `dotenv/config`를 맨 위에 두고 다른 모듈은
 * 이 파일만 보게 하면 순서를 신경 쓸 필요가 없다.
 */

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === "") {
    throw new Error(
      `[환경변수] ${name} 이(가) 없습니다. .env.example 을 참고해 채운 뒤 다시 시작하세요.`
    );
  }
  return value;
}

function optional(name: string, fallback = ""): string {
  return process.env[name]?.trim() || fallback;
}

export const env = {
  /** 'production' 이면 GUEST 로그인이 막히고 오류 메시지가 가려진다. */
  nodeEnv: optional("NODE_ENV", "development"),

  get isProduction() {
    return this.nodeEnv === "production";
  },

  port: Number(optional("PORT", "5001")),

  databaseUrl: required("DATABASE_URL"),

  /** 액세스·리프레시 토큰 서명 키. 폴백은 두지 않는다. */
  jwtSecret: required("JWT_SECRET"),

  /**
   * 브라우저에서 이 API를 부를 수 있는 오리진 목록(쉼표 구분).
   *
   * 앱(Flutter)은 Origin 헤더를 보내지 않으므로 이 목록과 무관하게 동작한다.
   * 여기서 막는 것은 **다른 웹사이트가 사용자의 브라우저 세션으로 우리 API를
   * 부르는 것**이다. 비워 두면 브라우저 요청을 전부 막는다.
   */
  corsOrigins: optional("CORS_ORIGINS")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean),

  /**
   * 이 인스턴스가 배치 작업을 돌릴지.
   *
   * 크론이 프로세스 안에서 돌아서, 인스턴스를 둘로 늘리면 혼잡도 계산과 푸시가
   * 두 번씩 나간다. 기본은 켬(단일 인스턴스 가정)이고, 늘릴 때 한 대만 남긴다.
   */
  runJobs: optional("RUN_JOBS", "true") !== "false",

  /** 어뷰징 로그를 볼 수 있는 사용자 id 목록(쉼표 구분). 비면 아무도 못 본다. */
  adminUserIds: optional("ADMIN_USER_IDS")
    .split(",")
    .map((id) => Number(id.trim()))
    .filter((id) => Number.isInteger(id) && id > 0),
};

/**
 * 기동 직후 한 번 부른다. 없는 값이 있으면 여기서 죽는다.
 *
 * 선택 값은 막지 않고 경고만 한다 — TourAPI 키가 없어도 서버는 돌아야 하고,
 * 그 사실을 로그에서 볼 수 있으면 된다.
 */
export function assertEnv(): void {
  // getter 들을 한 번 읽어 required 검사를 실행시킨다.
  void env.databaseUrl;
  void env.jwtSecret;

  const warnings: string[] = [];
  if (!process.env.KAKAO_REST_API_KEY) warnings.push("KAKAO_REST_API_KEY (카카오 로그인 검증)");
  if (!process.env.TOUR_API_SERVICE_KEY) warnings.push("TOUR_API_SERVICE_KEY (실시간 퀘스트 생성)");
  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    warnings.push("FIREBASE_* (푸시 발송)");
  }
  if (env.isProduction && env.corsOrigins.length === 0) {
    warnings.push("CORS_ORIGINS (브라우저 요청을 전부 막습니다)");
  }
  if (env.isProduction && env.adminUserIds.length === 0) {
    warnings.push("ADMIN_USER_IDS (어뷰징 로그를 아무도 볼 수 없습니다)");
  }

  for (const w of warnings) {
    console.warn(`[환경변수] 선택 값이 비어 있습니다: ${w}`);
  }
}
