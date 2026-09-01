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

/**
 * 토큰이 있으면 읽고, 없으면 그냥 통과시킨다 — 체크리스트 22번.
 *
 * **왜 authenticateToken을 그냥 붙이지 않는가**
 * 지도(`GET /quests`)는 로그인 없이도 보여야 한다. 그런데 "이미 완료한
 * 퀘스트"를 흐리게 그리려면 누가 보고 있는지 알아야 한다. 둘 다 만족하려면
 * 인증을 **선택**으로 두는 수밖에 없다.
 *
 * **깨진 토큰을 401로 만들지 않는다.** 만료된 토큰을 들고 지도를 열었을 때
 * 지도가 통째로 안 뜨는 것보다, 완료 표시만 빠진 지도가 뜨는 편이 낫다.
 * 앱은 다음 인증 필요 요청에서 어차피 refresh를 탄다.
 */
export const optionalAuth = (
  req: AuthenticatedRequest,
  _res: Response,
  next: NextFunction
) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(" ")[1];

  if (token) {
    try {
      req.user = { id: verifyAccessToken(token).userId };
    } catch {
      // 무시한다 — 비로그인과 같게 다룬다.
    }
  }

  next();
};
