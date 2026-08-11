import { Request, Response, NextFunction } from "express";
import { AuthService } from "../services/auth.service";

export class AuthController {
  // 소셜 로그인
  static async login(req: Request, res: Response, next: NextFunction) {
    try {
      const { provider, token, providerUid } = req.body;
      const result = await AuthService.login({ provider, token, providerUid });
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 닉네임 중복 확인 (추가)
  static async checkNickname(req: Request, res: Response, next: NextFunction) {
    try {
      const nickname = req.query.nickname as string;
      const result = await AuthService.checkNickname(nickname);
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 회원가입 (약관 + 온보딩 동시 처리)
  static async signup(req: Request, res: Response, next: NextFunction) {
    try {
      const result = await AuthService.signup(req.body);
      return res.status(201).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 토큰 갱신
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