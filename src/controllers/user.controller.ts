import { Request, Response, NextFunction } from "express";
import { AuthenticatedRequest } from "../middlewares/auth.middleware";
import { UserService } from "../services/user.service";
import { AppError } from "../utils/CustomError";

export class UserController {
  // 1. 내 프로필 조회
  static async getProfile(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const profile = await UserService.getMyProfile(userId);
      return res.status(200).json({ data: profile, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 2. 프로필 수정 (온보딩 정보 및 키워드 수정 포함)
  static async updateProfile(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const { nickname, avatarId, homeRegion, activityLevel, keywords } = req.body;

      const updatedUser = await UserService.updateProfile({
        userId,
        nickname,
        avatarId,
        homeRegion,
        activityLevel,
        keywords,
      });

      return res.status(200).json({ data: updatedUser, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 3. 닉네임 중복 확인 (User 엔드포인트용)
  static async checkNickname(req: Request, res: Response, next: NextFunction) {
    try {
      const nickname = req.query.nickname as string;
      const result = await UserService.checkNickname(nickname);
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 3. 프로필 화면(5c) — 통계 + 최근 발자국
  static async getProfileSummary(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const summary = await UserService.getProfileSummary(userId);
      return res.status(200).json({ data: summary, error: null });
    } catch (error) {
      next(error);
    }
  }
}