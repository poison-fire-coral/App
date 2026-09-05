import { prisma } from "../utils/prisma";
import { calculateHaversineDistance } from "../utils/geo.util";
import { listBadges } from "./badge.service";
import { QuestService } from "./quest.service";

export interface HomeQueryOptions {
  /** 내 위치. 있으면 추천을 가까운 순으로 정렬한다. */
  lat?: number;
  lng?: number;
}

/** 홈 상단에 세우는 배지 칸 수. 5c 스펙의 3칸. */
const HOME_BADGE_SLOTS = 3;

/** 추천으로 내려보낼 최대 개수. 화면은 3개만 쓰지만 여유를 준다. */
const RECOMMEND_LIMIT = 10;

export class HomeService {
  /**
   * GET /api/v1/home 통합 응답 — 체크리스트 20번.
   *
   * 홈이 진행중·추천·배지를 **각각** 부르던 것을 한 번으로 묶는다.
   * 홈은 앱에서 가장 자주 열리는 화면이라 왕복 수가 체감 속도를 좌우한다.
   *
   * 응답의 각 조각은 앱이 이미 파싱할 줄 아는 모양 그대로다 —
   * 퀘스트는 `place`를 포함한 행(`QuestModel.fromJson`), 배지는 목록 API와
   * 같은 항목(`BadgeSummary.fromJson`). 앱에 새 파서를 만들지 않으려는 것이다.
   */
  static async getHomeSummary(userId: number, options: HomeQueryOptions = {}) {
    const { lat, lng } = options;

    const [user, activeQuests, completedCompletions, badgeList] = await Promise.all([
      prisma.user.findUnique({
        where: { id: userId },
        include: { keywords: true },
      }),
      prisma.userQuest.findMany({
        where: { userId, status: "IN_PROGRESS" },
        include: { quest: { include: { place: true } } },
        orderBy: { startedAt: "desc" },
      }),
      prisma.questCompletion.findMany({
        where: { userId },
        select: { questId: true },
      }),
      // 목록 API를 그대로 쓴다. 홈만 다른 규칙으로 배지를 고르면 프로필에서
      // 대표로 지정한 것과 홈에 뜨는 것이 또 어긋난다 — 21번이 그 사고였다.
      listBadges(userId),
    ]);

    const userKeywordIds = user?.keywords.map((k) => k.keywordId) ?? [];

    // 추천에서 뺄 것: 이미 완료한 것(22번) + 지금 진행중인 것.
    // 진행중인 퀘스트는 바로 위 캐러셀에 이미 떠 있어서, 추천에 또 나오면
    // 같은 화면에 같은 퀘스트가 두 번 보인다.
    const excludedQuestIds = Array.from(
      new Set([
        ...completedCompletions.map((c) => c.questId),
        ...activeQuests.map((a) => a.questId),
      ])
    );

    const hasOrigin = lat !== undefined && lng !== undefined;

    const notExcluded = {
      active: true,
      ...(excludedQuestIds.length > 0 && { id: { notIn: excludedQuestIds } }),
    };

    let recommendedQuests: any[];

    if (hasOrigin) {
      // 화면 제목이 "내 주변 추천 퀘스트"다 — 좌표를 아는 순간 기준은 거리 하나뿐이다.
      //
      // **키워드로 먼저 거르지 않는다.** 온보딩 키워드(`골목산책`)와 퀘스트 키워드
      // (`골목`)는 어휘가 달라서 그대로 맞대면 0건이 나온다. 예전 `/quests/nearby`도
      // 키워드를 요구하지 않고 거리로만 찾았고, 홈은 그 동작을 그대로 이어받는다.
      const candidates = await prisma.quest.findMany({
        where: notExcluded,
        include: { place: true },
      });

      recommendedQuests = candidates
        .map((q) => ({
          quest: q,
          distanceM: Math.round(
            calculateHaversineDistance(lat!, lng!, q.place.lat, q.place.lng)
          ),
        }))
        .sort((a, b) => a.distanceM - b.distanceM)
        .slice(0, RECOMMEND_LIMIT)
        .map(({ quest, distanceM }) => ({
          ...QuestService.toClientQuest(quest),
          distanceM,
          isCompleted: false,
        }));
    } else {
      // 위치를 모를 때만 취향으로 고른다. 이때도 조건에 걸리는 게 없으면
      // 빈 화면을 주는 대신 그냥 아무거나 채운다 — 홈이 비어 있는 편이 더 나쁘다.
      const preferenceFilters = [
        ...(userKeywordIds.length > 0 ? [{ keywords: { hasSome: userKeywordIds } }] : []),
        ...(user?.homeRegion ? [{ place: { regionCode: user.homeRegion } }] : []),
      ];

      const preferred =
        preferenceFilters.length > 0
          ? await prisma.quest.findMany({
              where: { ...notExcluded, OR: preferenceFilters },
              include: { place: true },
              take: RECOMMEND_LIMIT,
            })
          : [];

      let picked = preferred;

      if (picked.length < RECOMMEND_LIMIT) {
        const pickedIds = picked.map((q) => q.id);
        const filler = await prisma.quest.findMany({
          where: {
            ...notExcluded,
            ...(pickedIds.length > 0 && {
              id: { notIn: [...excludedQuestIds, ...pickedIds] },
            }),
          },
          include: { place: true },
          take: RECOMMEND_LIMIT - picked.length,
        });
        picked = [...picked, ...filler];
      }

      recommendedQuests = picked.map((q) => ({
        ...QuestService.toClientQuest(q),
        isCompleted: false,
      }));
    }

    // 홈 3칸 — 대표 배지 먼저, 남는 칸은 최근 획득으로 채운다.
    // 앱이 목록을 받아 스스로 고르던 규칙을 서버로 옮긴 것이다.
    const featured = badgeList.items
      .filter((b) => b.isFeatured)
      .sort((a, b) => (a.featuredOrder ?? 0) - (b.featuredOrder ?? 0));

    const achieved = badgeList.items
      .filter((b) => b.state === "achieved" && !b.isFeatured)
      .sort((a, b) => {
        const at = a.achievedAt?.getTime() ?? 0;
        const bt = b.achievedAt?.getTime() ?? 0;
        return bt - at;
      });

    const badges = [...featured, ...achieved].slice(0, HOME_BADGE_SLOTS);

    return {
      // 진행중 퀘스트도 정답을 품고 있으므로 같이 지운다.
      activeQuests: activeQuests.map((a) => ({
        ...a,
        quest: QuestService.toClientQuest(a.quest),
      })),
      recommendedQuests,
      badges,
      /** 5a 헤드라인("배지 3 / 12")에 쓰는 값. 배지 탭을 열지 않아도 보인다. */
      badgeSummary: { total: badgeList.total, achieved: badgeList.achieved },
      /** 대표 배지 한 장만 필요한 자리를 위한 지름길. 없으면 null. */
      mainBadge: badges[0] ?? null,
    };
  }
}
