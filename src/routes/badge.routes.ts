import { Router } from "express";
import { BadgeController } from "../controllers/badge.controller";
import { authenticateToken } from "../middlewares/auth.middleware";

const router = Router();

// 내 배지 전체 — 획득 / 진행중 / 미공개 3상태
router.get("/", authenticateToken, BadgeController.list);

// 배지 상세 + 어떤 퀘스트로 채웠는지 이력
router.get("/:id", authenticateToken, BadgeController.detail);

export default router;
