import { Router } from "express";
import { UserController } from "../controllers/user.controller";
import { BadgeController } from "../controllers/badge.controller";
import { authenticateToken } from "../middlewares/auth.middleware";

const router = Router();

// 내 프로필 조회
router.get("/me", authenticateToken, UserController.getProfile);

// 내 프로필/온보딩 정보 수정
router.patch("/me", authenticateToken, UserController.updateProfile);

// 프로필 화면(5c) — 통계 + 최근 발자국
router.get("/me/profile", authenticateToken, UserController.getProfileSummary);

// 대표 배지 (홈 3칸)
router.get("/me/featured-badges", authenticateToken, BadgeController.featured);
router.put("/me/featured-badges", authenticateToken, BadgeController.updateFeatured);

// 💡 회원 탈퇴 (본인 계정 삭제)
router.delete("/me", authenticateToken, UserController.deleteMe);

// 푸시 알림 기기 (체크리스트 24번)
// 등록/해제에 토큰이 필요해서 해제도 POST 로 받는다 — DELETE 에 body 를 싣는 건
// 프록시마다 다르게 다뤄서 조용히 빈 body 가 오는 경우가 있다.
router.post("/me/devices", authenticateToken, UserController.registerDevice);
router.post("/me/devices/unregister", authenticateToken, UserController.unregisterDevice);
router.put("/me/push-enabled", authenticateToken, UserController.setPushEnabled);

export default router;