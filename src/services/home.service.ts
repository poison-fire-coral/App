import { prisma } from "../utils/prisma";

export class HomeService {
  /**
   * GET /api/home 통합 응답 데이터 생성
   */
  static async getHomeSummary(userId: number) {
    // 1. 진행 중인 퀘스트
    const activeQuests = await prisma.userQuest.findMany({
      where: {
        userId,
        status: "IN_PROGRESS",
      },
      include: {
        quest: { include: { place: true } },
      },
      orderBy: { startedAt: "desc" },
    });

    // 2. 유저 정보 및 완료한 퀘스트 ID 목록 추출
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { keywords: true },
    });

    const userKeywordIds = user?.keywords.map((k) => k.keywordId) ?? [];

    const completedCompletions = await prisma.questCompletion.findMany({
      where: { userId },
      select: { questId: true },
    });
    const completedQuestIds = completedCompletions.map((c) => c.questId);

    // 3. 추천 퀘스트 (완료 퀘스트 제외)
    const recommendedQuests = await prisma.quest.findMany({
      where: {
        active: true,
        ...(completedQuestIds.length > 0 && {
          id: { notIn: completedQuestIds },
        }),
        OR: [
          ...(userKeywordIds.length > 0 ? [{ keywords: { hasSome: userKeywordIds } }] : []),
          ...(user?.homeRegion ? [{ place: { regionCode: user.homeRegion } }] : []),
        ],
      },
      include: { place: true },
      take: 10,
    });

    // 4. 대표 배지 조회 (isFeatured: true 배지 우선, 없으면 최근 획득 배지 Fallback)
    const featuredUserBadges = await prisma.userBadge.findMany({
      where: { userId, isFeatured: true },
      include: { badge: true },
      orderBy: { featuredOrder: "asc" },
    });

    let mainBadge = null;

    if (featuredUserBadges.length > 0) {
      // 대표 배지가 설정되어 있다면 1번째 순서 배지 바인딩
      mainBadge = {
        ...featuredUserBadges[0].badge,
        achievedAt: featuredUserBadges[0].achievedAt,
      };
    } else {
      // 대표 배지 설정이 없을 경우 최근 획득한 1개 바인딩
      const latestBadge = await prisma.userBadge.findFirst({
        where: { userId, achievedAt: { not: null } },
        include: { badge: true },
        orderBy: { achievedAt: "desc" },
      });

      if (latestBadge) {
        mainBadge = {
          ...latestBadge.badge,
          achievedAt: latestBadge.achievedAt,
        };
      }
    }

    return {
      activeQuests,
      recommendedQuests: recommendedQuests.map((q) => ({
        ...q,
        isCompleted: false,
      })),
      mainBadge,
      featuredBadges: featuredUserBadges.map((fb) => ({
        ...fb.badge,
        achievedAt: fb.achievedAt,
        featuredOrder: fb.featuredOrder,
      })),
    };
  }
}