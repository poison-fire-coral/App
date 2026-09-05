import { Router } from "express";
import { getHomeData } from "../controllers/home.controller";
import { authenticateToken } from "../middlewares/auth.middleware";

const router = Router();

/**
 * 홈 통합 조회 — 체크리스트 20번.
 *
 * 서비스와 컨트롤러는 진작 쓰여 있었는데 **라우터가 없어 아무도 부를 수 없었다.**
 * 홈은 앱에서 가장 자주 열리는 화면이라 왕복 수가 체감 속도를 좌우한다.
 */
router.get("/", authenticateToken, getHomeData);

export default router;
