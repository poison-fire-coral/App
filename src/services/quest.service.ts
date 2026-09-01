import axios from "axios";
import { QuestType } from "@prisma/client";
import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";
import { calculateHaversineDistance, checkSpeedAbuse } from "../utils/geo.util";
import { getKSTDateString, isOffPeakKST } from "../utils/date.util";
import { calculateRewardExp, processLevelUp } from "./exp-engine.service";
import { recalculateBadges } from "./badge.service";

/**
 * Place.congestionScore(0~100 백분위)를 EXP 엔진이 기대하는 1/2/3 등급으로 옮긴다.
 */
export function toCongestionTier(score: number | null | undefined): number {
  if (score === null || score === undefined) return 2;
  if (score <= 30) return 1; // 한산 x1.4
  if (score >= 90) return 3; // 혼잡 x0.7
  return 2; // 보통 x1.0
}

export interface VerifyQuestDto {
  userId: number;
  questId: number;
  requestId: string;
  lat: number;
  lng: number;
  accuracyM: number;
  photoUrl?: string;
  photoVisibility?: string;
  userText?: string;
  emotionTag?: string;
}

export interface ViewportQueryDto {
  swLat?: number;
  swLng?: number;
  neLat?: number;
  neLng?: number;
  zoom?: number;
  keywords?: string[];
  search?: string;

  /**
   * 보고 있는 사람. 비로그인이면 undefined다 (`optionalAuth`).
   *
   * 있으면 각 퀘스트에 `isCompleted`가 붙는다 - 체크리스트 22번.
   * 지도에서 완료한 퀘스트를 **지우지 않고 흐리게** 그리기 위한 값이다.
   */
  userId?: number;
}

export interface NearbyQueryDto {
  /** 보고 있는 사람. 있으면 완료한 퀘스트를 목록에서 뺀다 (22번). */
  userId?: number;
  lat: number;
  lng: number;
  radiusM?: number; // 기본값 3000m (3km)
  keywords?: string[];
}

interface TourApiPlace {
  contentid: string;
  contenttypeid: string;
  title: string;
  addr1?: string;
  addr2?: string;
  mapx: string; // lng
  mapy: string; // lat
  firstimage?: string;
  firstimage2?: string;
  areacode?: string;
}

export class QuestService {
  private static isCompletedStatus(status?: string | null) {
    return status === "COMPLETED" || status === "done";
  }

  /**
   * 이 사용자가 이미 끝낸 퀘스트 id 집합 - 체크리스트 22번.
   *
   * **어뷰징으로 걸린 완료는 세지 않는다.** `isAbused: true`인 줄은 EXP도
   * 못 받은 기록이라 "완료했다"고 보면 다시 시도할 길이 막힌다.
   *
   * questIds를 주면 그 범위만 본다 - 뷰포트에 100개가 떠 있는데 전국의
   * 완료 이력을 다 긁어올 이유가 없다.
   */
  private static async completedQuestIds(
    userId: number,
    questIds?: number[]
  ): Promise<Set<number>> {
    const rows = await prisma.questCompletion.findMany({
      where: {
        userId,
        isAbused: false,
        ...(questIds && questIds.length > 0 && { questId: { in: questIds } }),
      },
      select: { questId: true },
      distinct: ["questId"],
    });
    return new Set(rows.map((r) => r.questId));
  }

  private static async searchTourApiPlaces(
    lat: number,
    lng: number,
    radiusM: number
  ): Promise<TourApiPlace[]> {
    const serviceKey = process.env.TOUR_API_SERVICE_KEY;
    if (!serviceKey) {
      console.warn("⚠️ TOUR_API_SERVICE_KEY가 설정되지 않았습니다. 실시간 검색을 스킵합니다.");
      return [];
    }

    try {
      const encodedKey = serviceKey.includes("%") ? serviceKey : encodeURIComponent(serviceKey);
      const baseUrl = "https://apis.data.go.kr/B551011/KorService2/locationBasedList2";

      const response = await axios.get(`${baseUrl}?serviceKey=${encodedKey}`, {
        params: {
          numOfRows: 50,
          pageNo: 1,
          MobileOS: "ETC",
          MobileApp: "LocalQuest",
          _type: "json",
          mapX: lng.toString(),
          mapY: lat.toString(),
          radius: Math.min(radiusM, 20000),
        },
      });

      const items = response.data?.response?.body?.items?.item;
      if (!items) return [];
      return Array.isArray(items) ? items : [items];
    } catch (error: any) {
      if (error.response?.data) {
        console.error("TourAPI 에러 응답 상세:", JSON.stringify(error.response.data, null, 2));
      } else {
        console.error("TourAPI 호출 실패:", error.message);
      }
      return [];
    }
  }

  private static generateQuestMetadata(place: TourApiPlace) {
    const typeId = place.contenttypeid;
    const name = place.title;

    switch (typeId) {
      case "12":
        return {
          title: `${name} 역사·문화 탐방`,
          story: `${name}에 도달하여 지역 고유의 특별한 매력을 발견해보세요!`,
          difficulty: 5,
          baseExp: 220,
          keywords: ["명소", "탐험", "관광"],
          questType: "VISIT" as QuestType,
          quizQuestion: `${name} 방문 인증: 이곳은 어떤 유형의 명소일까요?`,
          quizOptions: ["역사/문화 관광지", "대형 백화점", "첨단 연구소"],
          quizAnswer: "역사/문화 관광지",
          quizExplanation: "이곳은 주요 역사 및 문화 관광지입니다.",
        };
      case "14":
        return {
          title: `${name} 로컬 전시 인증`,
          story: `${name}에서 펼쳐지는 문화와 예술 공간을 조용히 관람해보세요.`,
          difficulty: 4,
          baseExp: 150,
          keywords: ["문화", "전시", "힐링"],
          questType: "VISIT" as QuestType,
          photoPrompt: `${name}의 건물 입구 또는 대표 안내판을 촬영하세요.`,
        };
      case "15":
        return {
          title: `${name} 현장 스냅 사진`,
          story: `${name} 축제 현장의 생생한 분위기를 담아보세요!`,
          difficulty: 2,
          baseExp: 180,
          keywords: ["축제", "이벤트", "체험"],
          questType: "VISIT" as QuestType,
          requiredCount: 2,
        };
      case "28":
        return {
          title: `${name} 액티비티 도전`,
          story: `${name} 주변을 둘러보며 숨겨진 활동 장소를 탐색해 보세요.`,
          difficulty: 3,
          baseExp: 200,
          keywords: ["액티비티", "모험", "스포츠"],
          questType: "VISIT" as QuestType,
        };
      case "32":
        return {
          title: `${name} 로컬 쉼터 한줄평`,
          story: `${name} 주변 공간을 거닐며 정겨운 소도시 휴식의 소감을 기록해보세요.`,
          difficulty: 1,
          baseExp: 50,
          keywords: ["휴식", "숙소", "힐링"],
          questType: "VISIT" as QuestType,
        };
      case "38":
        return {
          title: `${name} 전통시장 간판 찾기`,
          story: `${name}의 풍성한 로컬 정취와 가게 간판을 담아보세요.`,
          difficulty: 2,
          baseExp: 110,
          keywords: ["시장", "탐방", "쇼핑"],
          questType: "VISIT" as QuestType,
          photoPrompt: `${name}의 정겨운 가게 간판 사진`,
        };
      case "39":
        return {
          title: `${name} NPC 맛집 방명록`,
          story: `${name}에서 느낀 분위기와 맛에 대한 생각을 한 줄로 남겨보세요.`,
          difficulty: 1,
          baseExp: 60,
          keywords: ["맛집", "음식", "로컬"],
          questType: "VISIT" as QuestType,
        };
      default:
        return {
          title: `${name} 스팟 도달`,
          story: `${name} 목표 지점에 도달하여 로컬 인증을 완료해보세요.`,
          difficulty: 1,
          baseExp: 50,
          keywords: ["방문", "탐험"],
          questType: "VISIT" as QuestType,
        };
    }
  }

  private static async syncNearbyTourQuests(lat: number, lng: number, radiusM: number) {
    const tourPlaces = await this.searchTourApiPlaces(lat, lng, radiusM);

    for (const tPlace of tourPlaces) {
      const placeLat = parseFloat(tPlace.mapy);
      const placeLng = parseFloat(tPlace.mapx);

      if (isNaN(placeLat) || isNaN(placeLng)) continue;

      const meta = this.generateQuestMetadata(tPlace);
      const regionCode = tPlace.areacode ? String(tPlace.areacode) : "전국";
      const imageUrl = tPlace.firstimage || tPlace.firstimage2 || null;

      try {
        let place = await prisma.place.findFirst({
          where: {
            name: tPlace.title,
            lat: { gte: placeLat - 0.0005, lte: placeLat + 0.0005 },
            lng: { gte: placeLng - 0.0005, lte: placeLng + 0.0005 },
          },
        });

        if (!place) {
          place = await prisma.place.create({
            data: {
              name: tPlace.title,
              lat: placeLat,
              lng: placeLng,
              address: tPlace.addr1 || "",
              imageUrl: imageUrl,
              regionCode: regionCode,
              congestionScore: 1,
            },
          });
        } else if (!place.imageUrl && imageUrl) {
          place = await prisma.place.update({
            where: { id: place.id },
            data: { imageUrl: imageUrl },
          });
        }

        const existingQuest = await prisma.quest.findFirst({
          where: { placeId: place.id },
        });

        if (!existingQuest) {
          await prisma.quest.create({
            data: {
              title: meta.title,
              story: meta.story,
              difficulty: meta.difficulty,
              baseExp: meta.baseExp,
              keywords: meta.keywords,
              place: { connect: { id: place.id } },
              active: true,
              radiusM: 50,
              halfStep: false,
              questType: meta.questType,
              photoPrompt: (meta as any).photoPrompt || null,
              requiredCount: (meta as any).requiredCount ?? 1,
              quizQuestion: (meta as any).quizQuestion || null,
              quizOptions: (meta as any).quizOptions || undefined,
              quizAnswer: (meta as any).quizAnswer || null,
              quizExplanation: (meta as any).quizExplanation || null,
            },
          });
        }
      } catch (err) {
        console.error(`TourAPI 퀘스트 생성 실패 (${tPlace.title}):`, err);
      }
    }
  }

  // -------------------------------------------------------------
  // [메인 서비스 메서드]
  // -------------------------------------------------------------

  static async getQuestsByViewport(dto: ViewportQueryDto) {
    const { swLat, swLng, neLat, neLng, zoom = 15, keywords, search, userId } = dto;
    const whereClause: any = { active: true };

    if (swLat !== undefined && swLng !== undefined && neLat !== undefined && neLng !== undefined) {
      whereClause.place = {
        lat: { gte: swLat, lte: neLat },
        lng: { gte: swLng, lte: neLng },
      };
    }

    if (search && search.trim().length > 0) {
      const searchTrimmed = search.trim();
      whereClause.OR = [
        { title: { contains: searchTrimmed, mode: "insensitive" } },
        { place: { name: { contains: searchTrimmed, mode: "insensitive" } } },
        { place: { regionCode: { contains: searchTrimmed, mode: "insensitive" } } },
      ];
    }

    if (keywords && keywords.length > 0) {
      whereClause.keywords = { hasSome: keywords };
    }

    const quests = await prisma.quest.findMany({
      where: whereClause,
      include: { place: true },
    });

    if (zoom < 14 && swLat !== undefined) {
      const step = 0.02 * Math.pow(2, 14 - zoom);
      const clustersMap = new Map<string, { latSum: number; lngSum: number; count: number }>();

      for (const quest of quests) {
        const gridLat = Math.floor(quest.place.lat / step) * step;
        const gridLng = Math.floor(quest.place.lng / step) * step;
        const key = `${gridLat.toFixed(4)}_${gridLng.toFixed(4)}`;

        if (!clustersMap.has(key)) {
          clustersMap.set(key, { latSum: 0, lngSum: 0, count: 0 });
        }
        const cluster = clustersMap.get(key)!;
        cluster.latSum += quest.place.lat;
        cluster.lngSum += quest.place.lng;
        cluster.count += 1;
      }

      const clusters = Array.from(clustersMap.values()).map((c) => ({
        lat: Number((c.latSum / c.count).toFixed(6)),
        lng: Number((c.lngSum / c.count).toFixed(6)),
        count: c.count,
      }));

      // 클러스터는 원 안의 개수만 보여 준다. 완료 여부는 개별 마커의 성질이라
      // 여기서는 붙일 자리가 없다 - 확대해서 마커가 갈라지면 그때 붙는다.
      return { isClustered: true, zoom, totalQuests: quests.length, clusters };
    }

    // 체크리스트 22번 - 완료한 퀘스트를 **지우지 않고** 표시만 다르게 한다.
    // 지도에서 사라지면 "여기 뭐 있었는데" 하고 다시 찾게 되고, 16번에서
    // 재방문(x0.3)을 열어 둔 것과도 어긋난다.
    const completed = userId
      ? await this.completedQuestIds(userId, quests.map((q) => q.id))
      : null;

    return {
      isClustered: false,
      zoom,
      totalQuests: quests.length,
      quests: completed
        ? quests.map((q) => ({ ...q, isCompleted: completed.has(q.id) }))
        : quests,
    };
  }

  static async getNearbyQuests(dto: NearbyQueryDto) {
    const { lat, lng, radiusM = 3000, keywords, userId } = dto;

    await this.syncNearbyTourQuests(lat, lng, radiusM);

    const quests = await prisma.quest.findMany({
      where: {
        active: true,
        ...(keywords && keywords.length > 0 && { keywords: { hasSome: keywords } }),
      },
      include: { place: true },
    });

    const nearbyQuests = quests
      .map((quest) => {
        const distanceM = calculateHaversineDistance(lat, lng, quest.place.lat, quest.place.lng);
        return { ...quest, distanceM: Math.round(distanceM) };
      })
      .filter((quest) => quest.distanceM <= radiusM)
      .sort((a, b) => a.distanceM - b.distanceM);

    // 체크리스트 22번. 홈의 "가까운 퀘스트 3개"는 지도와 달리 **권유**라서,
    // 이미 끝낸 걸 다시 권하면 목록 3칸을 낭비한다. 여기서는 뺀다.
    if (!userId) return nearbyQuests;

    const completed = await this.completedQuestIds(
      userId,
      nearbyQuests.map((q) => q.id)
    );
    return nearbyQuests.filter((q) => !completed.has(q.id));
  }

  static async getRecommendedQuests(userId: number) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { keywords: true },
    });

    if (!user) {
      throw new CustomError(404, "USER_NOT_FOUND", "존재하지 않는 유저입니다.");
    }

    const userKeywordIds = user.keywords.map((k) => k.keywordId);

    const quests = await prisma.quest.findMany({
      where: {
        active: true,
        OR: [
          ...(userKeywordIds.length > 0 ? [{ keywords: { hasSome: userKeywordIds } }] : []),
          ...(user.homeRegion ? [{ place: { regionCode: user.homeRegion } }] : []),
        ],

        // 체크리스트 22번 - 이미 완료한 퀘스트는 추천하지 않는다.
        //
        // Prisma의 `none`이 SQL `NOT EXISTS`로 내려간다. 앱에서 받아 놓고
        // 거르면 `take: 10`이 완료한 것들로 채워져 실제로는 3개만 남는 일이
        // 생긴다 - 자르기 전에 DB에서 빼야 10개가 10개다.
        //
        // 어뷰징으로 걸린 완료(`isAbused`)는 완료로 보지 않는다.
        completions: { none: { userId, isAbused: false } },
      },
      include: { place: true },
      take: 10,
    });

    return quests;
  }

  static async getMyQuests(userId: number, status?: string) {
    const userQuests = await prisma.userQuest.findMany({
      where: {
        userId,
        ...(status && { status: status.toUpperCase() }),
      },
      include: {
        quest: { include: { place: true } },
      },
      orderBy: { startedAt: "desc" },
    });

    return userQuests;
  }

  /**
   * 💡 32번: 어뷰징 탐지 로그 목록 조회
   */
  static async getAbuseLogs({ page = 1, limit = 20 }: { page: number; limit: number }) {
    const skip = (page - 1) * limit;

    const [items, totalCount] = await Promise.all([
      prisma.questCompletion.findMany({
        where: { isAbused: true },
        include: {
          user: {
            select: { id: true, nickname: true, providerUid: true },
          },
          quest: {
            select: { id: true, title: true },
          },
        },
        orderBy: { createdAt: "desc" },
        skip,
        take: limit,
      }),
      prisma.questCompletion.count({
        where: { isAbused: true },
      }),
    ]);

    return {
      items,
      pagination: {
        page,
        limit,
        totalCount,
        totalPages: Math.ceil(totalCount / limit),
      },
    };
  }

  static async getQuestById(questId: number) {
    const quest = await prisma.quest.findUnique({
      where: { id: questId },
      include: { place: true },
    });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    return quest;
  }

  /**
   * 💡 16. 퀘스트 수락 (재수행 조건 반영)
   */
  static async acceptQuest(userId: number, questId: number) {
    const quest = await prisma.quest.findUnique({ where: { id: questId } });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    const existingUserQuest = await prisma.userQuest.findFirst({
      where: { userId, questId },
    });

    if (existingUserQuest) {
      if (this.isCompletedStatus(existingUserQuest.status)) {
        const lastCompletedAt =
          existingUserQuest.completedAt ||
          existingUserQuest.lastVerifiedAt ||
          existingUserQuest.startedAt;
        const now = new Date();
        const hoursDiff = (now.getTime() - lastCompletedAt.getTime()) / (1000 * 3600);

        if (hoursDiff < 24) {
          throw new CustomError(
            409,
            "QUEST_ALREADY_DONE",
            "이미 완료한 퀘스트입니다. 완료 후 24시간이 지나야 재수행 가능합니다."
          );
        }

        return await prisma.userQuest.update({
          where: { userId_questId: { userId, questId } },
          data: { status: "IN_PROGRESS", startedAt: now },
        });
      }
      throw new CustomError(409, "QUEST_ALREADY_ACCEPTED", "이미 수락한 퀘스트입니다.");
    }

    const userQuest = await prisma.userQuest.create({
      data: { userId, questId, status: "IN_PROGRESS" },
    });

    return userQuest;
  }

  static async abandonQuest(userId: number, questId: number) {
    const userQuest = await prisma.userQuest.findUnique({
      where: { userId_questId: { userId, questId } },
    });

    if (!userQuest) {
      throw new CustomError(404, "NOT_FOUND", "수락한 이력이 없는 퀘스트입니다.");
    }

    if (this.isCompletedStatus(userQuest.status)) {
      throw new CustomError(400, "BAD_REQUEST", "이미 완료된 퀘스트는 취소할 수 없습니다.");
    }

    await prisma.userQuest.delete({
      where: { userId_questId: { userId, questId } },
    });

    return { success: true, message: "퀘스트 수락을 취소했습니다." };
  }

  /**
   * 💡 14, 15, 16 반영: 퀘스트 검증 및 보상 지급
   */
  static async verifyQuest(dto: VerifyQuestDto) {
    const now = new Date();

    const existingCompletion = await prisma.questCompletion.findUnique({
      where: { requestId: dto.requestId },
    });

    if (existingCompletion) {
      return { isAlreadyProcessed: true, completion: existingCompletion };
    }

    const quest = await prisma.quest.findUnique({
      where: { id: dto.questId },
      include: { place: true },
    });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    const latestCompletion = await prisma.questCompletion.findFirst({
      where: { userId: dto.userId, questId: dto.questId },
      orderBy: { createdAt: "desc" },
    });

    let isRepeat = false;
    if (latestCompletion) {
      const hoursDiff = (now.getTime() - latestCompletion.createdAt.getTime()) / (1000 * 3600);
      const isSameDayKST = getKSTDateString(latestCompletion.createdAt) === getKSTDateString(now);

      if (hoursDiff < 24 || isSameDayKST) {
        throw new CustomError(
          409,
          "QUEST_ALREADY_DONE",
          "이전에 완료한 퀘스트입니다. 24시간 경과 및 하루 1회 재수행 조건이 충족되지 않았습니다."
        );
      }
      isRepeat = true;
    }

    if (dto.accuracyM > 100) {
      throw new CustomError(
        400,
        "ACCURACY_TOO_LOW",
        "위치 정확도가 낮습니다 (100m 이내 필요). 다시 시도해 주세요."
      );
    }

    const user = await prisma.user.findUnique({ where: { id: dto.userId } });
    if (!user) {
      throw new CustomError(404, "USER_NOT_FOUND", "존재하지 않는 유저입니다.");
    }

    const distance = calculateHaversineDistance(dto.lat, dto.lng, quest.place.lat, quest.place.lng);

    if (distance > quest.radiusM) {
      throw new CustomError(
        400,
        "OUT_OF_RANGE",
        `인증 반경(${quest.radiusM}m) 밖에 있습니다. (현재 거리: ${Math.round(distance)}m)`
      );
    }

    const userQuest = await prisma.userQuest.findUnique({
      where: { userId_questId: { userId: dto.userId, questId: dto.questId } },
    });

    let isAbused = false;
    if (userQuest?.lastVerifiedAt && userQuest?.lastLat && userQuest?.lastLng) {
      isAbused = checkSpeedAbuse(
        userQuest.lastLat,
        userQuest.lastLng,
        userQuest.lastVerifiedAt,
        dto.lat,
        dto.lng,
        now
      );
    }

    let isNewArea = false;
    const regionCode = quest.place?.regionCode;

    if (regionCode) {
      const pastCompletionInRegion = await prisma.questCompletion.findFirst({
        where: {
          userId: dto.userId,
          quest: {
            place: { regionCode },
          },
        },
      });
      isNewArea = !pastCompletionInRegion;
    }

    const isOffPeak = isOffPeakKST(now);

    let dailyExpEarned = user.dailyExpEarned;
    const isSameDayReset = getKSTDateString(user.lastExpResetAt) === getKSTDateString(now);
    if (!isSameDayReset) {
      dailyExpEarned = 0;
    }

    const expResult = calculateRewardExp(
      {
        baseExp: quest.baseExp,
        halfStep: isRepeat ? true : quest.halfStep,
        congestionScore: toCongestionTier(quest.place.congestionScore),
        isNewArea,
        isOffPeak,
        streakDays: user.streakDays,
        isAbused,
      },
      dailyExpEarned
    );

    const levelTable = await prisma.levelTable.findMany();
    const levelResult = processLevelUp(user.level, user.expCurrent, expResult.finalExp, levelTable);

    return await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: dto.userId },
        data: {
          level: levelResult.level,
          expCurrent: levelResult.expCurrent,
          expTotal: { increment: expResult.finalExp },
          dailyExpEarned: isSameDayReset ? { increment: expResult.finalExp } : expResult.finalExp,
          lastExpResetAt: now,
          lastActiveAt: now,
        },
      });

      await tx.userQuest.upsert({
        where: { userId_questId: { userId: dto.userId, questId: dto.questId } },
        create: {
          userId: dto.userId,
          questId: dto.questId,
          status: "COMPLETED",
          lastLat: dto.lat,
          lastLng: dto.lng,
          lastVerifiedAt: now,
          completedAt: now,
        },
        update: {
          status: "COMPLETED",
          lastLat: dto.lat,
          lastLng: dto.lng,
          lastVerifiedAt: now,
          completedAt: now,
        },
      });

      const completion = await tx.questCompletion.create({
        data: {
          userId: dto.userId,
          questId: dto.questId,
          requestId: dto.requestId,
          expAwarded: expResult.finalExp,
          multipliersJson: expResult.breakdown,
          photoUrl: dto.photoUrl,
          photoVisibility: dto.photoVisibility || "PUBLIC",
          userText: dto.userText,
          emotionTag: dto.emotionTag,
          lat: dto.lat,
          lng: dto.lng,
          accuracyM: dto.accuracyM,
          isAbused,
        },
      });

      const badgeProgress = await recalculateBadges(tx, dto.userId);

      return {
        completionId: completion.id,
        expAwarded: expResult.finalExp,
        breakdown: expResult.breakdown,
        badgeProgress,
        levelInfo: {
          ...levelResult,
          nextRequiredExp:
            levelTable.find((l) => l.level === levelResult.level + 1)?.requiredExp ?? null,
        },
        isAbused,
      };
    });
  }
}