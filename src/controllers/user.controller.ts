import { Response, NextFunction } from "express";
import { AuthenticatedRequest } from "../middlewares/auth.middleware";

export class UserController {
  static async getProfile(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      res.json({ status: "OK", message: "프로필 조회 성공" });
    } catch (error) {
      next(error);
    }
  }

  static async updateProfile(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      res.json({ status: "OK", message: "프로필 수정 성공" });
    } catch (error) {
      next(error);
    }
  }
}
