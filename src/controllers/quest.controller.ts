import { Response, NextFunction } from "express";
import { QuestService } from "../services/quest.service";
import { getPresignedUploadUrl } from "../services/upload.service";
import { AuthenticatedRequest } from "../middlewares/auth.middleware";

export class QuestController {
  // 1. 퀘스트 목록 / 뷰포트 / 클러스터링 조회
  static async getQuests(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const { swLat, swLng, neLat, neLng, zoom, keywords, search } = req.query;

      const parsedSwLat = swLat ? parseFloat(swLat as string) : undefined;
      const parsedSwLng = swLng ? parseFloat(swLng as string) : undefined;
      const parsedNeLat = neLat ? parseFloat(neLat as string) : undefined;
      const parsedNeLng = neLng ? parseFloat(neLng as string) : undefined;
      const parsedZoom = zoom ? parseInt(zoom as string, 10) : 15;
      const parsedKeywords = typeof keywords === "string" ? keywords.split(",") : undefined;

      const result = await QuestService.getQuestsByViewport({
        swLat: parsedSwLat,
        swLng: parsedSwLng,
        neLat: parsedNeLat,
        neLng: parsedNeLng,
        zoom: parsedZoom,
        keywords: parsedKeywords,
        search: search as string,
      });

      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 2. 근처 퀘스트 거리순 조회 (GET /api/v1/quests/nearby)
  static async getNearbyQuests(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const { lat, lng, radiusM, keywords } = req.query;

      if (!lat || !lng) {
        return res.status(400).json({
          error: { code: "BAD_REQUEST", message: "현재 위경도(lat, lng) 정보가 필요합니다." },
        });
      }

      const parsedKeywords = typeof keywords === "string" ? keywords.split(",") : undefined;

      const result = await QuestService.getNearbyQuests({
        lat: parseFloat(lat as string),
        lng: parseFloat(lng as string),
        radiusM: radiusM ? parseInt(radiusM as string, 10) : 3000,
        keywords: parsedKeywords,
      });

      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 3. 사용자 맞춤 추천 퀘스트 조회 (GET /api/v1/quests/recommended)
  static async getRecommendedQuests(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      const result = await QuestService.getRecommendedQuests(userId);
      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 4. 내 퀘스트 목록 조회 (GET /api/v1/quests/my)
  static async getMyQuests(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      const status = req.query.status as string | undefined;
      const result = await QuestService.getMyQuests(userId, status);
      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 4-1. 어뷰징 탐지 로그 조회 (GET /api/v1/quests/abuse-logs)
  static async getAbuseLogs(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      const page = req.query.page ? parseInt(req.query.page as string, 10) : 1;
      const limit = req.query.limit ? parseInt(req.query.limit as string, 10) : 20;

      const result = await QuestService.getAbuseLogs({ page, limit });
      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 5. 퀘스트 단건 상세 조회 (GET /api/v1/quests/:id)
  static async getQuestById(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const questId = Number(req.params.id);

      if (isNaN(questId)) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "올바른 퀘스트 ID가 아닙니다." } });
      }

      const quest = await QuestService.getQuestById(questId);
      res.status(200).json({ data: quest, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 6. 퀘스트 수락 (POST /api/v1/quests/:id/accept)
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

  // 7. 퀘스트 수락 취소/포기 (DELETE /api/v1/quests/:id/accept)
  static async abandonQuest(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const questId = Number(req.params.id);

      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      if (isNaN(questId)) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "올바른 퀘스트 ID가 아닙니다." } });
      }

      const result = await QuestService.abandonQuest(userId, questId);
      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 8. 도달 인증 및 보상 지급 (POST /api/v1/quests/:id/verify)
  static async verifyQuest(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const questId = Number(req.params.id);

      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      if (isNaN(questId)) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "올바른 퀘스트 ID가 아닙니다." } });
      }

      const {
        requestId,
        lat,
        lng,
        accuracyM,
        photoUrl,
        photoVisibility,
        userText,
        emotionTag,
      } = req.body;

      if (!requestId) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "요청 UUID(requestId)가 필요합니다." } });
      }

      if (lat === undefined || lng === undefined || accuracyM === undefined) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "위치 및 정확도 정보(lat, lng, accuracyM)가 필요합니다." } });
      }

      const result = await QuestService.verifyQuest({
        userId,
        questId,
        requestId,
        lat: Number(lat),
        lng: Number(lng),
        accuracyM: Number(accuracyM),
        photoUrl,
        photoVisibility,
        userText,
        emotionTag,
      });

      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 9. 사진 업로드 Presigned URL 발급
  static async getUploadUrl(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const questId = Number(req.params.id);
      const ext = (req.body.ext || req.query.ext || "jpg") as string;

      if (!userId) {
        return res.status(401).json({ error: { code: "UNAUTHORIZED", message: "인증 정보가 없습니다." } });
      }

      if (isNaN(questId)) {
        return res.status(400).json({ error: { code: "BAD_REQUEST", message: "올바른 퀘스트 ID가 아닙니다." } });
      }

      const result = await getPresignedUploadUrl(userId, questId, ext);
      res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }
}