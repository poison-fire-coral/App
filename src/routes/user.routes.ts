import { Router } from "express";
import { UserController } from "../controllers/user.controller";
import { authenticateToken } from "../middlewares/auth.middleware"; // authenticateJwt -> authenticateToken으로 변경

const router = Router();

// 내 프로필 조회
router.get("/me", authenticateToken, UserController.getProfile);

// 내 프로필/온보딩 정보 수정
router.patch("/me", authenticateToken, UserController.updateProfile);

export default router;