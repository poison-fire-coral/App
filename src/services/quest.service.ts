import axios from "axios";
import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";
import { calculateHaversineDistance, checkSpeedAbuse } from "../utils/geo.util";
import { calculateRewardExp, processLevelUp } from "./exp-engine.service";


/**
 * Place.congestionScore(0~100 백분위)를 EXP 엔진이 기대하는 1/2/3 등급으로 옮긴다.
 *
 * 엔진(exp-engine.service.ts:19)은 1=한산(x1.4) · 2=보통(x1.0) · 3=혼잡(x0.7)만 안다.
 * 그런데 DB에는 50, 80 같은 백분위가 들어 있어 어떤 값이든 "보통"으로 떨어졌고,
 * 결과적으로 기획서 6b가 "오버투어리즘 완화의 핵심"이라고 한 혼잡도 배율이
 * 한 번도 적용되지 않았다.
 *
 * 기준은 기획서 6b 그대로 — 방문자 하위 30%는 한산, 상위 10%는 혼잡.
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

interface KakaoPlace {
  id: string;
  place_name: string;
  category_name: string;
  address_name: string;
  x: string; // lng
  y: string; // lat;
}

export class QuestService {
  // -------------------------------------------------------------
  // [카카오 연동 헬퍼] 카카오 API 검색 및 퀘스트 자동 생성을 위한 모듈
  // -------------------------------------------------------------

  /** 카카오 로컬 API 키워드 검색 */
  private static async searchKakaoPlaces(
    lat: number,
    lng: number,
    keyword: string,
    radiusM: number
  ): Promise<KakaoPlace[]> {
    const kakaoApiKey = process.env.KAKAO_REST_API_KEY;
    if (!kakaoApiKey) {
      console.warn("⚠️ KAKAO_REST_API_KEY가 설정되지 않았습니다. 실시간 검색을 스킵합니다.");
      return [];
    }

    try {
      const response = await axios.get("https://dapi.kakao.com/v2/local/search/keyword.json", {
        headers: { Authorization: `KakaoAK ${kakaoApiKey}` },
        params: {
          query: keyword,
          x: lng.toString(),
          y: lat.toString(),
          radius: Math.min(radiusM, 20000), // 카카오 최대 반경 20km
          sort: "distance",
        },
      });
      return response.data?.documents || [];
    } catch (error) {
      console.error(`카카오 API 호출 실패 (${keyword}):`, error);
      return [];
    }
  }

  /** 카카오 카테고리/장소명 기반 퀘스트 메타데이터 자동 생성 규칙 */
  private static generateQuestMetadata(place: KakaoPlace) {
    const category = place.category_name;
    const name = place.place_name;

    if (category.includes("공원") || name.includes("공원") || name.includes("산책")) {
      return {
        title: `${name} 산책 퀘스트`,
        story: `${name} 주변을 가볍게 거닐며 힐링하는 시간을 가져보세요!`,
        difficulty: 1,
        baseExp: 50,
        keywords: ["산책", "공원", "힐링"],
      };
    } else if (category.includes("시장") || name.includes("시장")) {
      return {
        title: `${name} 활기찬 시장 탐방`,
        story: `${name}의 풍성한 먹거리와 활기찬 정취를 느껴보세요.`,
        difficulty: 2,
        baseExp: 110,
        keywords: ["시장", "탐방", "쇼핑"],
      };
    } else if (category.includes("카페") || category.includes("음료")) {
      return {
        title: `${name} 여유 스팟 방문`,
        story: `${name}에서 향기로운 음료와 함께 휴식을 취해보세요.`,
        difficulty: 1,
        baseExp: 50,
        keywords: ["카페", "휴식"],
      };
    } else if (category.includes("관광") || category.includes("문화") || name.includes("명소")) {
      return {
        title: `${name} 역사·문화 탐방`,
        story: `${name}에 도달하여 장소의 특별한 매력을 발견해보세요!`,
        difficulty: 3,
        baseExp: 220,
        keywords: ["명소", "탐험", "문화"],
      };
    }

    return {
      title: `${name} 스팟 도달`,
      story: `${name} 목표 지점에 도달하여 인증을 완료해보세요.`,
      difficulty: 1,
      baseExp: 50,
      keywords: ["방문", "탐험"],
    };
  }

  /** 주변 카카오 장소를 실시간 수집 및 DB 동기화 */
  private static async syncNearbyKakaoQuests(lat: number, lng: number, radiusM: number) {
    const searchKeywords = ["공원", "시장", "명소", "카페"];
    const kakaoPlaces: KakaoPlace[] = [];

    // 1. 카카오 API에서 주요 키워드별 주변 장소 검색
    for (const kw of searchKeywords) {
      const places = await this.searchKakaoPlaces(lat, lng, kw, radiusM);
      kakaoPlaces.push(...places);
    }

    // 2. 검색된 장소를 DB Place 및 Quest 테이블에 Upsert (중복 방지)
    for (const kPlace of kakaoPlaces) {
      const placeLat = parseFloat(kPlace.y);
      const placeLng = parseFloat(kPlace.x);
      const meta = this.generateQuestMetadata(kPlace);
      const regionCode = kPlace.address_name ? kPlace.address_name.split(" ")[0] : "전국";

      try {
        // 기존 동일 이름/좌표 근처 장소가 있는지 확인
        let place = await prisma.place.findFirst({
          where: {
            name: kPlace.place_name,
            lat: { gte: placeLat - 0.0005, lte: placeLat + 0.0005 },
            lng: { gte: placeLng - 0.0005, lte: placeLng + 0.0005 },
          },
        });

        // 장소가 없으면 생성
        if (!place) {
          place = await prisma.place.create({
            data: {
              name: kPlace.place_name,
              lat: placeLat,
              lng: placeLng,
              address: kPlace.address_name || "",
              regionCode: regionCode,
              congestionScore: 50,
            },
          });
        }

        // 해당 장소에 연결된 퀘스트가 없으면 생성
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
        console.error(`퀘스트 동적 생성 실패 (${kPlace.place_name}):`, err);
      }
    }
  }

  // -------------------------------------------------------------
  // [메인 서비스 메서드]
  // -------------------------------------------------------------

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

  // 2. 내 위치 기반 근처 퀘스트 조회 (실시간 카카오 탐지 연동)
  static async getNearbyQuests(dto: NearbyQueryDto) {
    const { lat, lng, radiusM = 3000, keywords } = dto;

    // 💡 [추가] 카카오 API를 호출하여 내 위치 주변 스팟을 실시간으로 퀘스트화 DB 등록
    await this.syncNearbyKakaoQuests(lat, lng, radiusM);

    // DB에서 실시간 생성된 항목을 포함하여 근처 퀘스트 조회
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

  // 3. 사용자 맞춤 추천 퀘스트 조회
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

  // 8. 퀘스트 도달 인증 및 보상 지급
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
        congestionScore: toCongestionTier(quest.place.congestionScore),
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
        // 클라이언트가 진행 링을 그리려면 "다음 레벨까지 얼마"가 필요하다.
        // 이 값을 안 주면 앱이 자체 하드코딩 테이블로 계산해 서버와 어긋난다.
        levelInfo: {
          ...levelResult,
          nextRequiredExp:
            levelTable.find((l) => l.level === levelResult.level + 1)
              ?.requiredExp ?? null,
        },
        isAbused,
      };
    });
  }
}