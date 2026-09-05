import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";

import { env } from "./config/env";
import authRoutes from "./routes/auth.routes";
import userRoutes from "./routes/user.routes";
import questRoutes from "./routes/quest.routes";
import badgeRoutes from "./routes/badge.routes";
import homeRoutes from "./routes/home.routes";
import legalRouter from "./routes/legal.router";
import { errorHandler, notFoundHandler } from "./middlewares/errorHandler";
import { prisma } from "./utils/prisma";

const app = express();

// 프록시(Northflank·Render 등) 뒤에서 돌 때 클라이언트 IP를 제대로 읽는다.
// 이게 없으면 레이트리밋이 프록시 IP 하나만 보고 전체 사용자를 한 덩어리로 센다.
app.set("trust proxy", 1);

app.use(helmet());

/**
 * **앱은 이 설정과 무관하다.** Flutter의 http 클라이언트는 Origin 헤더를 보내지
 * 않으므로 CORS 검사 자체를 거치지 않는다. 여기서 막는 것은 다른 웹사이트가
 * 방문자의 브라우저로 우리 API를 부르는 경우다.
 *
 * 예전에는 `cors()` 기본값이라 `Access-Control-Allow-Origin: *` 이었다.
 */
app.use(
  cors({
    origin(origin, callback) {
      // Origin 없음 = 앱·서버 간 호출·curl. 브라우저가 아니므로 통과시킨다.
      if (!origin) return callback(null, true);
      if (env.corsOrigins.includes(origin)) return callback(null, true);
      return callback(null, false);
    },
  })
);

// 100kb 기본값을 그대로 쓰면 인증 요청이 통과한다 — 사진은 S3로 직접 올라가고
// 우리 서버에는 URL만 오기 때문이다. 명시해서 의도를 남긴다.
app.use(express.json({ limit: "100kb" }));

/**
 * 로그인·인증처럼 **한 사람이 반복할 이유가 없는** 경로만 조인다.
 *
 * 지도 조회에는 걸지 않는다. 지도를 훑으면 정상 사용에서도 요청이 몰리고,
 * 거기에 상한을 걸면 제일 열심히 쓰는 사람이 먼저 막힌다.
 */
const authLimiter = rateLimit({
  windowMs: 60_000,
  limit: 20,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  message: {
    data: null,
    error: { code: "TOO_MANY_REQUESTS", message: "잠시 후 다시 시도해 주세요." },
  },
});

const verifyLimiter = rateLimit({
  windowMs: 60_000,
  // 여러 지점짜리 퀘스트와 대기 큐 재전송이 겹칠 수 있어 조금 넉넉히 준다.
  limit: 30,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  message: {
    data: null,
    error: { code: "TOO_MANY_REQUESTS", message: "잠시 후 다시 시도해 주세요." },
  },
});

/**
 * 살아 있는지, 그리고 **DB까지 닿는지**.
 *
 * `GET /`는 프로세스가 떠 있다는 것만 말한다. Postgres가 죽어도 계속 200을
 * 주므로 배포 플랫폼의 헬스체크로 쓰면 고장을 못 잡는다.
 */
app.get("/health", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: "ok", db: "ok" });
  } catch (e) {
    res.status(503).json({ status: "degraded", db: "unreachable" });
  }
});

app.get("/", (_req, res) => {
  res.json({ status: "OK", message: "Local Quest API Server is running!" });
});

// 공개 약관 라우터 (스토어 제출용 /privacy · /terms/*)
app.use(legalRouter);

// API 라우터 연결
app.use("/api/v1/auth", authLimiter, authRoutes);
app.use("/api/v1/users", userRoutes);

// 인증(verify)만 따로 조인다. **퀘스트 라우터보다 먼저 걸어야 한다** —
// 뒤에 두면 questRoutes 가 요청을 이미 처리해 버려 상한이 한 번도 안 걸린다.
app.use("/api/v1/quests/:questId/verify", verifyLimiter);
app.use("/api/v1/quests", questRoutes);

app.use("/api/v1/badges", badgeRoutes);
app.use("/api/v1/home", homeRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
