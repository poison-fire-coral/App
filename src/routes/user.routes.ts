import { Router } from "express";
import { UserController } from "../controllers/user.controller";
import { BadgeController } from "../controllers/badge.controller";
import { authenticateToken } from "../middlewares/auth.middleware"; // authenticateJwt -> authenticateToken으로 변경

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

export default router;