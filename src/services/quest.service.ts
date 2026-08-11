import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";
import { calculateHaversineDistance, checkSpeedAbuse } from "../utils/geo.util";
import { calculateRewardExp, processLevelUp } from "./exp-engine.service";

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
}

export interface NearbyQueryDto {
  lat: number;
  lng: number;
  radiusM?: number; // 기본값 3000m (3km)
  keywords?: string[];
}

export class QuestService {
  // 1. 지도 뷰포트 조회 & 클러스터링 & 검색
  static async getQuestsByViewport(dto: ViewportQueryDto) {
    const { swLat, swLng, neLat, neLng, zoom = 15, keywords, search } = dto;

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

      return {
        isClustered: true,
        zoom,
        totalQuests: quests.length,
        clusters,
      };
    }

    return {
      isClustered: false,
      zoom,
      totalQuests: quests.length,
      quests,
    };
  }

  // 2. 내 위치 기반 근처 퀘스트 조회 (거리순 정렬)
  static async getNearbyQuests(dto: NearbyQueryDto) {
    const { lat, lng, radiusM = 3000, keywords } = dto;

    const quests = await prisma.quest.findMany({
      where: {
        active: true,
        ...(keywords && keywords.length > 0 && { keywords: { hasSome: keywords } }),
      },
      include: { place: true },
    });

    // Haversine 거리 계산 후 반경 내 필터링 및 거리순 정렬
    const nearbyQuests = quests
      .map((quest) => {
        const distanceM = calculateHaversineDistance(lat, lng, quest.place.lat, quest.place.lng);
        return { ...quest, distanceM: Math.round(distanceM) };
      })
      .filter((quest) => quest.distanceM <= radiusM)
      .sort((a, b) => a.distanceM - b.distanceM);

    return nearbyQuests;
  }

  // 3. 사용자 맞춤 추천 퀘스트 조회 (유저 온보딩 키워드 / 지역 기반)
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
      },
      include: { place: true },
      take: 10,
    });

    return quests;
  }

  // 4. 내 수락/진행/완료 퀘스트 목록 조회
  static async getMyQuests(userId: number, status?: string) {
    const userQuests = await prisma.userQuest.findMany({
      where: {
        userId,
        ...(status && { status: status.toUpperCase() }),
      },
      include: {
        quest: {
          include: { place: true },
        },
      },
      orderBy: { startedAt: "desc" },
    });

    return userQuests;
  }

  // 5. 퀘스트 단건 상세 조회
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

  // 6. 퀘스트 수락
  static async acceptQuest(userId: number, questId: number) {
    const quest = await prisma.quest.findUnique({
      where: { id: questId },
    });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    const existingUserQuest = await prisma.userQuest.findFirst({
      where: { userId, questId },
    });

    if (existingUserQuest) {
      throw new CustomError(409, "QUEST_ALREADY_DONE", "이미 수락했거나 완료한 퀘스트입니다.");
    }

    const userQuest = await prisma.userQuest.create({
      data: {
        userId,
        questId,
        status: "IN_PROGRESS",
      },
    });

    return userQuest;
  }

  // 7. 진행 중인 퀘스트 취소/포기
  static async abandonQuest(userId: number, questId: number) {
    const userQuest = await prisma.userQuest.findUnique({
      where: { userId_questId: { userId, questId } },
    });

    if (!userQuest) {
      throw new CustomError(404, "NOT_FOUND", "수락한 이력이 없는 퀘스트입니다.");
    }

    if (userQuest.status === "COMPLETED") {
      throw new CustomError(400, "BAD_REQUEST", "이미 완료된 퀘스트는 취소할 수 없습니다.");
    }

    await prisma.userQuest.delete({
      where: { userId_questId: { userId, questId } },
    });

    return { success: true, message: "퀘스트 수락을 취소했습니다." };
  }

  // 8. 퀘스트 도달 인증 및 보상 지급 (3영역)
  static async verifyQuest(dto: VerifyQuestDto) {
    const existingCompletion = await prisma.questCompletion.findUnique({
      where: { requestId: dto.requestId },
    });

    if (existingCompletion) {
      return {
        isAlreadyProcessed: true,
        completion: existingCompletion,
      };
    }

    if (dto.accuracyM > 100) {
      throw new CustomError(
        400,
        "ACCURACY_TOO_LOW",
        "위치 정확도가 낮습니다 (100m 이내 필요). 다시 시도해 주세요."
      );
    }

    const user = await prisma.user.findUnique({
      where: { id: dto.userId },
    });

    if (!user) {
      throw new CustomError(404, "USER_NOT_FOUND", "존재하지 않는 유저입니다.");
    }

    const quest = await prisma.quest.findUnique({
      where: { id: dto.questId },
      include: { place: true },
    });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    const distance = calculateHaversineDistance(
      dto.lat,
      dto.lng,
      quest.place.lat,
      quest.place.lng
    );

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

    const now = new Date();
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

    let dailyExpEarned = user.dailyExpEarned;
    const isSameDay = user.lastExpResetAt.toDateString() === now.toDateString();
    if (!isSameDay) {
      dailyExpEarned = 0;
    }

    const expResult = calculateRewardExp(
      {
        baseExp: quest.baseExp,
        halfStep: quest.halfStep,
        congestionScore: quest.place.congestionScore,
        isNewArea: true,
        isOffPeak: false,
        streakDays: user.streakDays,
        isReattempt: userQuest?.status === "COMPLETED" || userQuest?.status === "done",
        isAbused,
      },
      dailyExpEarned
    );

    const levelTable = await prisma.levelTable.findMany();
    const levelResult = processLevelUp(
      user.level,
      user.expCurrent,
      expResult.finalExp,
      levelTable
    );

    return await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: dto.userId },
        data: {
          level: levelResult.level,
          expCurrent: levelResult.expCurrent,
          expTotal: { increment: expResult.finalExp },
          dailyExpEarned: isSameDay
            ? { increment: expResult.finalExp }
            : expResult.finalExp,
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

      return {
        completionId: completion.id,
        expAwarded: expResult.finalExp,
        breakdown: expResult.breakdown,
        levelInfo: levelResult,
        isAbused,
      };
    });
  }
}