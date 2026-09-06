import { Response, NextFunction } from "express";
import { HomeService } from "../services/home.service";
import { AuthenticatedRequest } from "../middlewares/auth.middleware";
import { CustomError } from "../utils/CustomError";

/**
 * GET /api/v1/home — 체크리스트 20번.
 *
 * **`?userId=`로 남의 홈을 볼 수 없다.** 예전에는 토큰이 없으면 쿼리 파라미터로
 * 떨어지게 돼 있었는데, 그건 아무 숫자나 넣으면 남의 진행중 퀘스트와 배지를
 * 읽는 구멍이다. 라우터가 `authenticateToken`을 거치므로 여기서는 토큰만 믿는다.
 */
export const getHomeData = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      throw new CustomError(401, "UNAUTHORIZED", "인증 정보가 없습니다.");
    }

    const { lat, lng } = req.query;

    const summary = await HomeService.getHomeSummary(userId, {
      lat: lat ? parseFloat(lat as string) : undefined,
      lng: lng ? parseFloat(lng as string) : undefined,
    });

    return res.status(200).json({ data: summary, error: null });
  } catch (error) {
    next(error);
  }
};
