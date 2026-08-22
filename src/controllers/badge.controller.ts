import { Request, Response, NextFunction } from "express";
import {
  listBadges,
  getBadgeDetail,
  setFeaturedBadges,
  listFeatured,
} from "../services/badge.service";

export class BadgeController {
  /** GET /badges — 획득·진행중·미공개 3상태 + 지역/유형 필터 */
  static async list(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = (req as any).user.id;
      const region = req.query.region as string | undefined;
      const questType = req.query.questType as string | undefined;

      const result = await listBadges(userId, { region, questType });
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  /** GET /badges/:id — 상세 + 어떤 퀘스트로 채웠는지 이력 */
  static async detail(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = (req as any).user.id;
      const badgeId = Number(req.params.id);
      if (isNaN(badgeId)) {
        return res.status(400).json({
          data: null,
          error: { code: "BAD_REQUEST", message: "잘못된 배지 ID입니다." },
        });
      }

      const result = await getBadgeDetail(userId, badgeId);
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  /** GET /users/me/featured-badges */
  static async featured(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = (req as any).user.id;
      const result = await listFeatured(userId);
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  /** PUT /users/me/featured-badges — body: { badgeIds: number[] } */
  static async updateFeatured(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = (req as any).user.id;
      const raw = req.body?.badgeIds;

      if (!Array.isArray(raw) || raw.some((v) => typeof v !== "number")) {
        return res.status(400).json({
          data: null,
          error: {
            code: "BAD_REQUEST",
            message: "badgeIds는 숫자 배열이어야 합니다.",
          },
        });
      }

      const result = await setFeaturedBadges(userId, raw);
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }
}
