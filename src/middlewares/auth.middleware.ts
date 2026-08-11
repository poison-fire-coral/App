import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt";
import { CustomError } from "../utils/CustomError";

export interface AuthenticatedRequest extends Request {
  user?: {
    id: number;
  };
}

export const authenticateToken = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return next(new CustomError(401, "UNAUTHORIZED", "인증 토큰이 필요합니다."));
  }

  try {
    // jwt.ts의 verifyAccessToken을 사용하여 검증 키 일치화
    const decoded = verifyAccessToken(token);

    req.user = { id: decoded.userId };
    next();
  } catch (err) {
    console.error("====== 실제 JWT 에러 내용 ======", err);
    return next(new CustomError(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다."));
  }
};