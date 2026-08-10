import { Router } from "express";
import { UserController } from "../controllers/user.controller";
import { authenticateToken } from "../middlewares/auth.middleware";

const router = Router();

// GET /api/v1/users/me (내 프로필 조회)
router.get("/me", authenticateToken, UserController.getProfile);

// POST /api/v1/users/me (내 프로필 수정)
router.post("/me", authenticateToken, UserController.updateProfile);

export default router;
