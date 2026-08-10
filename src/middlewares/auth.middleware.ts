import { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";
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
    const secret = process.env.JWT_SECRET || "secret";
    const decoded = jwt.verify(token, secret) as { userId: number };
    
    // req.user.id 로 통일
    req.user = { id: decoded.userId };
    next();
  } catch (err) {
    return next(new CustomError(401, "UNAUTHORIZED", "유효하지 않은 토큰입니다."));
  }
};
