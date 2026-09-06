import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt";
import { CustomError } from "../utils/CustomError";
import { env } from "../config/env";

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

/**
 * 운영자만 지나갈 수 있는 문.
 *
 * 어뷰징 로그(`GET /quests/abuse-logs`)는 로그인만 하면 누구나 볼 수 있었다.
 * 그 응답에는 **다른 사용자의 닉네임과 소셜 제공자 회원번호**가 들어 있다.
 * 32번이 만든 조회 경로는 운영을 위한 것이지 사용자용이 아니다.
 *
 * 역할 컬럼을 두지 않고 환경 변수 목록으로 정하는 이유: 지금 운영자는 몇 명이고,
 * DB에 역할을 넣으면 그 값을 바꾸는 화면과 그 화면을 지키는 권한이 또 필요하다.
 * 배포 설정으로 두면 서버에 접근할 수 있는 사람만 바꿀 수 있다.
 */
export const requireAdmin = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  const userId = req.user?.id;

  if (!userId || !env.adminUserIds.includes(userId)) {
    // 있는지 없는지도 알려 주지 않는다.
    return res.status(404).json({
      data: null,
      error: { code: "NOT_FOUND", message: "경로를 찾을 수 없습니다." },
    });
  }

  next();
};
