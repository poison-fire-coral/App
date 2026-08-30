import axios from "axios";
import { QuestType } from "@prisma/client";
import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";
import { calculateHaversineDistance, checkSpeedAbuse } from "../utils/geo.util";
import { getKSTDateString, calculateStreak } from "../utils/date.util";
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
}

export interface NearbyQueryDto {
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
  firstimage?: string; // 대표 이미지 원본
  firstimage2?: string; // 대표 이미지 썸네일
  areacode?: string;
}

export class QuestService {
  private static isCompletedStatus(status?: string | null) {
    return status === "COMPLETED" || status === "done";
  }

  // -------------------------------------------------------------
  // [TourAPI Ver4.3 연동 헬퍼] 위치 기반 한국관광공사 데이터 조회
  // -------------------------------------------------------------

  /** TourAPI 위치 기반 관광정보 조회 API (locationBasedList2 - KorService2) */
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
          numOfRows: 50, // 💡 기존 30개에서 50개로 상향 (더 많은 장소 수집)
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

  /** TourAPI 관광지 카테고리(contentTypeId) 기반 다양한 퀘스트 메타데이터 자동 생성 규칙 */
  private static generateQuestMetadata(place: TourApiPlace) {
    const typeId = place.contenttypeid;
    const name = place.title;

    switch (typeId) {
      case "12": // 관광지 -> 퀴즈형
        return {
          title: `${name} 역사·문화 탐방`,
          story: `${name}에 도달하여 지역 고유의 특별한 매력을 발견해보세요!`,
          difficulty: 3,
          baseExp: 220,
          keywords: ["명소", "탐험", "관광"],
          questType: "QUIZ" as QuestType,
          quizQuestion: `${name} 방문 인증: 이곳은 어떤 유형의 명소일까요?`,
          quizOptions: ["역사/문화 관광지", "대형 백화점", "첨단 연구소"],
          quizAnswer: "역사/문화 관광지",
          quizExplanation: "이곳은 주요 역사 및 문화 관광지입니다.",
        };
      case "14": // 문화시설 -> 피사체 지정 사진형
        return {
          title: `${name} 로컬 전시 인증`,
          story: `${name}에서 펼쳐지는 문화와 예술 공간을 조용히 관람해보세요.`,
          difficulty: 2,
          baseExp: 150,
          keywords: ["문화", "전시", "힐링"],
          questType: "PHOTO_SINGLE" as QuestType,
          photoPrompt: `${name}의 건물 입구 또는 대표 안내판을 촬영하세요.`,
        };
      case "15": // 축제/공연/행사 -> 수집 사진형
        return {
          title: `${name} 현장 스냅 사진`,
          story: `${name} 축제 현장의 생생한 분위기를 담아보세요!`,
          difficulty: 2,
          baseExp: 180,
          keywords: ["축제", "이벤트", "체험"],
          questType: "PHOTO_COLLECT" as QuestType,
          requiredCount: 2,
        };
      case "28": // 레포츠 -> 탐색형
        return {
          title: `${name} 액티비티 도전`,
          story: `${name} 주변을 둘러보며 숨겨진 활동 장소를 탐색해 보세요.`,
          difficulty: 3,
          baseExp: 200,
          keywords: ["액티비티", "모험", "스포츠"],
          questType: "EXPLORATION" as QuestType,
        };
      case "32": // 숙박 -> 기록형
        return {
          title: `${name} 로컬 쉼터 한줄평`,
          story: `${name} 주변 공간을 거닐며 정겨운 소도시 휴식의 소감을 기록해보세요.`,
          difficulty: 1,
          baseExp: 50,
          keywords: ["휴식", "숙소", "힐링"],
          questType: "RECORD" as QuestType,
        };
      case "38": // 쇼핑/전통시장 -> 피사체 지정 사진형
        return {
          title: `${name} 전통시장 간판 찾기`,
          story: `${name}의 풍성한 로컬 정취와 가게 간판을 담아보세요.`,
          difficulty: 2,
          baseExp: 110,
          keywords: ["시장", "탐방", "쇼핑"],
          questType: "PHOTO_SINGLE" as QuestType,
          photoPrompt: `${name}의 정겨운 가게 간판 사진`,
        };
      case "39": // 음식점 -> 기록형
        return {
          title: `${name} NPC 맛집 방명록`,
          story: `${name}에서 느낀 분위기와 맛에 대한 생각을 한 줄로 남겨보세요.`,
          difficulty: 1,
          baseExp: 60,
          keywords: ["맛집", "음식", "로컬"],
          questType: "RECORD" as QuestType,
        };
      default: // 기본 -> 방문형
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

  /** 주변 TourAPI 장소를 실시간 수집 및 DB 동기화 */
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
              place: {
                connect: { id: place.id },
              },
              active: true,
              radiusM: 50,
              halfStep: false,
              questType: meta.questType,
              photoPrompt: (meta as any).photoPrompt || null,
              
              // ⭕ [해결 핵심] requiredCount가 Int(non-null)이므로 null을 주면 Prisma 에러 발생!
              // ?? 1 을 사용하여 null/undefined 시 기본값 1이 들어가게 함.
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

      return { isClustered: true, zoom, totalQuests: quests.length, clusters };
    }

    return { isClustered: false, zoom, totalQuests: quests.length, quests };
  }

  // 2. 내 위치 기반 근처 퀘스트 조회 (TourAPI 실시간 연동)
  static async getNearbyQuests(dto: NearbyQueryDto) {
    const { lat, lng, radiusM = 3000, keywords } = dto;

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

    return nearbyQuests;
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
        throw new CustomError(
          409,
          "QUEST_ALREADY_DONE",
          "이미 완료한 퀘스트입니다. 다시 진행할 수 없습니다."
        );
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

  static async verifyQuest(dto: VerifyQuestDto) {
    const existingCompletion = await prisma.questCompletion.findUnique({
      where: { requestId: dto.requestId },
    });

    if (existingCompletion) {
      return { isAlreadyProcessed: true, completion: existingCompletion };
    }

    const [priorCompletion, userQuest] = await Promise.all([
      prisma.questCompletion.findFirst({
        where: { userId: dto.userId, questId: dto.questId },
      }),
      prisma.userQuest.findUnique({
        where: { userId_questId: { userId: dto.userId, questId: dto.questId } },
      }),
    ]);

    if (priorCompletion || this.isCompletedStatus(userQuest?.status)) {
      throw new CustomError(
        409,
        "QUEST_ALREADY_DONE",
        "이미 완료한 퀘스트입니다. 다시 진행할 수 없습니다."
      );
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

    const quest = await prisma.quest.findUnique({
      where: { id: dto.questId },
      include: { place: true },
    });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    const distance = calculateHaversineDistance(dto.lat, dto.lng, quest.place.lat, quest.place.lng);

    if (distance > quest.radiusM) {
      throw new CustomError(
        400,
        "OUT_OF_RANGE",
        `인증 반경(${quest.radiusM}m) 밖에 있습니다. (현재 거리: ${Math.round(distance)}m)`
      );
    }

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
        congestionScore: toCongestionTier(quest.place.congestionScore),
        isNewArea: true,
        isOffPeak: false,
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
          dailyExpEarned: isSameDay ? { increment: expResult.finalExp } : expResult.finalExp,
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