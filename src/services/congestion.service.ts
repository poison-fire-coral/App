import { prisma } from "../utils/prisma";

export class CongestionService {
  // 최근 완료 로그 및 시각 데이터 기반 혼잡도 백분위 계산
  static async calculateCongestion(placeId: number): Promise<number> {
    const place = await prisma.place.findUnique({
      where: { id: placeId },
    });

    if (!place) return 50;

    const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);

    const recentCompletionsCount = await prisma.userQuest.count({
      where: {
        quest: { placeId },
        completedAt: { gte: twoHoursAgo },
      },
    });

    // 최근 2시간 완료 건수 기반 혼잡도 점수 산출 (최대 100)
    const dynamicScore = Math.min(100, Math.round(recentCompletionsCount * 15 + place.congestionScore * 0.5));
    return dynamicScore;
  }
}
