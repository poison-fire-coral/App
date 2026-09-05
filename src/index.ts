// 환경 변수를 **가장 먼저** 읽고 검사한다.
//
// 예전에는 `import app` 이 첫 줄이고 `dotenv.config()` 가 그 아래였다. 임포트는
// 위에서 아래로 평가되므로, 모듈 최상단에서 `process.env` 를 읽는 파일은
// .env 가 실리기 전에 값을 가져갔다. 우연히 `prisma.ts` 가 먼저 임포트되며
// dotenv 를 끌어와 동작했을 뿐, 임포트 순서를 바꾸면 조용히 깨지는 구조였다.
import { assertEnv, env } from "./config/env";

assertEnv();

import app from "./app";
import { prisma } from "./utils/prisma";
import { startCongestionBatchJob } from "./jobs/congestionScore.job";
import { startNearbyQuestPushJob } from "./jobs/nearbyQuestPush.job";

// 배치는 프로세스 안에서 돈다. 인스턴스를 둘로 늘리면 혼잡도 계산이 두 번 돌고
// 주변 퀘스트 알림이 두 번 나간다. 여러 대로 늘릴 때는 한 대만 RUN_JOBS 를 켠다.
if (env.runJobs) {
  startCongestionBatchJob();
  startNearbyQuestPushJob();
} else {
  console.log("배치 작업은 이 인스턴스에서 실행하지 않습니다 (RUN_JOBS=false).");
}

// '0.0.0.0' — 컨테이너 밖(그리고 개발 중에는 실기기)에서 들어올 수 있게 한다.
const server = app.listen(env.port, "0.0.0.0", () => {
  console.log(`서버가 http://0.0.0.0:${env.port} 에서 실행 중입니다. (${env.nodeEnv})`);
});

/**
 * 배포 플랫폼은 새 버전을 띄우기 전에 SIGTERM 을 보내고 잠시 기다린다.
 *
 * 그 사이에 처리 중인 요청을 끊으면, 하필 그 요청이 인증이었을 때 사용자는
 * 현장까지 가서 실패를 본다. 받고 있던 것은 마치고 새 연결만 거절한다.
 */
function shutdown(signal: string) {
  console.log(`${signal} 수신 — 처리 중인 요청을 마치고 종료합니다.`);

  server.close(async () => {
    try {
      await prisma.$disconnect();
    } catch (e) {
      console.error("DB 연결 종료 실패:", e);
    }
    process.exit(0);
  });

  // 붙잡힌 연결 때문에 영영 안 끝나는 것은 막는다.
  setTimeout(() => {
    console.error("정상 종료가 시간을 넘겨 강제로 끝냅니다.");
    process.exit(1);
  }, 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
