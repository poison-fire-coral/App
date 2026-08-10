import { Response, NextFunction } from "express";
import { QuestService } from "../services/quest.service";
import { AuthenticatedRequest } from "../middlewares/auth.middleware";

export class QuestController {
  static async getQuests(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      // 뷰포트 조회 컨트롤러 로직
      res.json({ data: [] });
    } catch (error) {
      next(error);
    }
  }

  static async getQuestById(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      res.json({ data: null });
    } catch (error) {
      next(error);
    }
  }

  static async acceptQuest(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const questId = Number(req.params.id);

      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      if (isNaN(questId)) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "올바른 퀘스트 ID가 아닙니다." } });
      }

      const result = await QuestService.acceptQuest(userId, questId);
      res.status(201).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }
}
