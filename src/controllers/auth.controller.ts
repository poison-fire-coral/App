import { Request, Response, NextFunction } from "express";
import { AuthService } from "../services/auth.service";

export class AuthController {
  static async login(req: Request, res: Response, next: NextFunction) {
    try {
      const { provider, token, providerUid } = req.body;
      const result = await AuthService.login({ provider, token, providerUid });
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  static async signup(req: Request, res: Response, next: NextFunction) {
    try {
      const result = await AuthService.signup(req.body);
      return res.status(201).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  static async refresh(req: Request, res: Response, next: NextFunction) {
    try {
      const { refreshToken } = req.body;
      const tokens = await AuthService.refreshTokens(refreshToken);
      return res.status(200).json({ data: tokens, error: null });
    } catch (error) {
      next(error);
    }
  }
}
