import { Router } from "express";
import { QuestController } from "../controllers/quest.controller";
import { authenticateToken } from "../middlewares/auth.middleware";

const router = Router();

// GET /api/v1/quests
router.get("/", QuestController.getQuests);

// GET /api/v1/quests/:id
router.get("/:id", QuestController.getQuestById);

// POST /api/v1/quests/:id/accept (인증 필요)
router.post("/:id/accept", authenticateToken, QuestController.acceptQuest);

export default router;
