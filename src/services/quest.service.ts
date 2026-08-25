import axios from "axios";
import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";
import { calculateHaversineDistance, checkSpeedAbuse } from "../utils/geo.util";
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
      
      // 💡 승인받은 상세기능에 맞추어 KorService2 / locationBasedList2 엔드포인트 적용
      const baseUrl = "https://apis.data.go.kr/B551011/KorService2/locationBasedList2";

      const response = await axios.get(`${baseUrl}?serviceKey=${encodedKey}`, {
        params: {
          numOfRows: 30,
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

  /** TourAPI 관광지 카테고리(contentTypeId) 기반 퀘스트 메타데이터 자동 생성 규칙 */
  private static generateQuestMetadata(place: TourApiPlace) {
    const typeId = place.contenttypeid;
    const name = place.title;

    switch (typeId) {
      case "12": // 관광지
        return {
          title: `${name} 역사·문화 탐방`,
          story: `${name}에 도달하여 지역 고유의 특별한 매력을 발견해보세요!`,
          difficulty: 3,
          baseExp: 220,
          keywords: ["명소", "탐험", "관광"],
        };
      case "14": // 문화시설
        return {
          title: `${name} 로컬 전시 체험`,
          story: `${name}에서 펼쳐지는 문화와 예술 공간을 조용히 관람해보세요.`,
          difficulty: 2,
          baseExp: 150,
          keywords: ["문화", "전시", "힐링"],
        };
      case "15": // 축제/공연/행사
        return {
          title: `${name} 돌발 필드 퀘스트`,
          story: `${name} 축제 현장을 방문하여 활기찬 분위기를 만끽해보세요!`,
          difficulty: 2,
          baseExp: 180,
          keywords: ["축제", "이벤트", "체험"],
        };
      case "28": // 레포츠
        return {
          title: `${name} 액티비티 도전`,
          story: `${name}에서 제공하는 짜릿한 활동으로 에너지를 충전해보세요.`,
          difficulty: 3,
          baseExp: 200,
          keywords: ["액티비티", "모험", "스포츠"],
        };
      case "32": // 숙박
        return {
          title: `${name} 로컬 쉼터 방문`,
          story: `${name} 주변 공간을 거닐며 정겨운 소도시의 휴식을 느껴보세요.`,
          difficulty: 1,
          baseExp: 50,
          keywords: ["휴식", "숙소", "힐링"],
        };
      case "38": // 쇼핑/전통시장
        return {
          title: `${name} 전통시장·상점 탐방`,
          story: `${name}의 풍성한 로컬 먹거리와 활기찬 정취를 느껴보세요.`,
          difficulty: 2,
          baseExp: 110,
          keywords: ["시장", "탐방", "쇼핑"],
        };
      case "39": // 음식점
        return {
          title: `${name} NPC 맛집 탐방`,
          story: `${name}에서 현지 주민(NPC)이 추천하는 로컬 맛을 즐겨보세요.`,
          difficulty: 1,
          baseExp: 60,
          keywords: ["맛집", "음식", "로컬"],
        };
      default:
        return {
          title: `${name} 스팟 도달`,
          story: `${name} 목표 지점에 도달하여 로컬 인증을 완료해보세요.`,
          difficulty: 1,
          baseExp: 50,
          keywords: ["방문", "탐험"],
        };
    }
  }

  /** 주변 TourAPI 장소를 실시간 수집 및 DB 동기화 (대표 이미지 포함) */
  private static async syncNearbyTourQuests(lat: number, lng: number, radiusM: number) {
    const tourPlaces = await this.searchTourApiPlaces(lat, lng, radiusM);

    for (const tPlace of tourPlaces) {
      const placeLat = parseFloat(tPlace.mapy);
      const placeLng = parseFloat(tPlace.mapx);

      if (isNaN(placeLat) || isNaN(placeLng)) continue;

      const meta = this.generateQuestMetadata(tPlace);
      const regionCode = tPlace.areacode ? String(tPlace.areacode) : "전국";
      // TourAPI 대표 이미지 extraction (firstimage -> firstimage2 순서)
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
              imageUrl: imageUrl, // 💡 TourAPI 대표 이미지 URL 저장
              regionCode: regionCode,
              congestionScore: 50,
            },
          });
        } else if (!place.imageUrl && imageUrl) {
          // 이미지가 기존에 없었으면 업데이트
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
              placeId: place.id,
              active: true,
              radiusM: 50,
              halfStep: false,
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

    // 💡 TourAPI를 호출하여 내 위치 주변 관광 스팟을 퀘스트화 DB 등록
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