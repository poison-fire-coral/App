import axios from "axios";
import { QuestType } from "@prisma/client";
import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";
import { calculateHaversineDistance, checkSpeedAbuse } from "../utils/geo.util";
import {
  getKSTDateString,
  isOffPeakKST,
  calculateStreak,
  isWithinTimeWindowKST,
} from "../utils/date.util";
import { calculateRewardExp, processLevelUp } from "./exp-engine.service";
import { recalculateBadges } from "./badge.service";

/**
 * Place.congestionScore(0~100 백분위)를 EXP 엔진이 기대하는 1/2/3 등급으로 옮긴다.
 */
/**
 * TourAPI `areacode`(숫자) → 지역 이름.
 *
 * **왜 필요한가:** 지역 배지 규칙은 `{ type: "REGION", value: "서울" }`처럼
 * 한글 이름으로 쓰여 있고, 시드와 카카오 장소도 한글로 저장한다. 그런데
 * TourAPI로 만든 장소만 `areacode`를 그대로 넣어 `"1"`·`"31"`이 들어갔다.
 * 그 결과 서울에서 아무리 완료해도 "서울 산책자"가 열리지 않았고,
 * "팔도 유람"은 같은 지역을 `"서울"`과 `"1"` 둘로 세었다.
 *
 * 표기는 하나여야 한다 — 지역 이름으로 통일한다.
 */
export const TOUR_AREA_CODE_TO_REGION: Record<string, string> = {
  "1": "서울",
  "2": "인천",
  "3": "대전",
  "4": "대구",
  "5": "광주",
  "6": "부산",
  "7": "울산",
  "8": "세종",
  "31": "경기",
  "32": "강원",
  "33": "충북",
  "34": "충남",
  "35": "경북",
  "36": "경남",
  "37": "전북",
  "38": "전남",
  "39": "제주",
};

/** 모르는 코드는 "전국"으로 떨어뜨린다. 숫자를 그대로 남기면 또 갈라진다. */
export function regionNameFromAreaCode(areaCode?: string | number | null): string {
  if (areaCode === undefined || areaCode === null || areaCode === "") return "전국";
  return TOUR_AREA_CODE_TO_REGION[String(areaCode)] ?? "전국";
}

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
  /**
   * 처리된 위치(Mock location) 여부 — 체크리스트 18번.
   *
   * 앱이 `Position.isMocked`를 그대로 실어 보낸다. 클라이언트 값을 믿는 것이라
   * 작정하면 뚫린다 — 그래도 가짜 위치 앱을 그냥 쓴 대부분은 여기서 걸리고,
   * 무엇보다 `is_abused` 로그가 남아 32번 조회 경로에서 보인다.
   */
  isMocked?: boolean;

  /**
   * 09 퀴즈형 · 10 탐색형이 고른 답. 화면의 선택지 문자열 그대로.
   *
   * 정답(`quizAnswer`)은 앱에 내려보내지 않으므로(`toClientQuest`) 채점은
   * 서버에서만 일어난다.
   */
  answer?: string;
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

  /**
   * 거리순 정렬의 기준점. 검색(`search`)에서만 쓴다 — 체크리스트 12번 BE 몫.
   *
   * 전국 검색은 뷰포트가 없어 "가까운 순"의 기준이 없다. 앱이 마지막으로
   * 아는 내 위치를 실어 보내면 그걸 쓰고, 없으면 id 순으로 자른다.
   */
  originLat?: number;
  originLng?: number;
}

export interface NearbyQueryDto {
  /** 보고 있는 사람. 있으면 완료한 퀘스트를 목록에서 뺀다 (22번). */
  userId?: number;
  lat: number;
  lng: number;
  radiusM?: number; // 기본값 3000m (3km)
  keywords?: string[];
}

export interface TourApiPlace {
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

  /**
   * 자동 생성 퀘스트의 **유형 비율**.
   *
   * 실사용자가 앱을 켜면 그 자리에서 퀘스트가 만들어진다. 그래서 이 표가 곧
   * "처음 온 사람이 보게 될 퀘스트 구성"이다. 세 가지를 지키도록 짰다.
   *
   * 1. **인증할 수 없는 유형은 만들지 않는다.** 퀴즈·탐색(정답 입력)과 수집형
   *    (사진 N장)은 4b 인증 화면에 입력 자리가 없어, 지금 만들면 걸어가기만 해도
   *    완료된다. 이름만 퀴즈인 퀘스트를 실사용자에게 뿌릴 수는 없다.
   *    화면이 생기면(체크리스트 26번) 여기 `special`만 바꾸면 된다.
   *
   * 2. **방문형이 다수여야 한다.** 처음 쓰는 사람이 처음 받는 퀘스트가 타이핑이나
   *    촬영을 요구하면 이탈한다. 도달만으로 끝나는 것이 기본값이고,
   *    특수 유형은 양념이다.
   *
   * 3. **특수 유형은 장소 성격에 맞아야 한다.** 식당에서 한 줄 남기기(기록),
   *    시장·전시에서 사진 한 장은 자연스럽지만 뒤바뀌면 어색하다.
   *
   * `sharePercent`는 그 장소 유형 중 특수 유형이 될 비율이다. 나머지는 방문형.
   */
  private static readonly TYPE_MIX: Record<
    string,
    { special: QuestType; sharePercent: number }
  > = {
    "12": { special: "PHOTO_SINGLE", sharePercent: 20 }, // 관광지
    "14": { special: "PHOTO_SINGLE", sharePercent: 35 }, // 문화시설
    "15": { special: "PHOTO_SINGLE", sharePercent: 35 }, // 축제·행사
    "28": { special: "VISIT", sharePercent: 0 }, // 레포츠 — 도달 자체가 목표
    "32": { special: "RECORD", sharePercent: 25 }, // 숙박·쉼터
    "38": { special: "PHOTO_SINGLE", sharePercent: 30 }, // 쇼핑 — 간판
    "39": { special: "RECORD", sharePercent: 25 }, // 음식점 — 한줄평
  };

  /**
   * 장소마다 **늘 같은** 0~99 값. 유형을 여기에 걸어 둔다.
   *
   * `syncNearbyTourQuests`는 사람이 지나갈 때마다 도는데, 그때그때 무작위로
   * 정하면 같은 가게가 어제는 사진형, 오늘은 방문형이 된다. contentid만으로
   * 정하면 언제 돌아도 결과가 같다.
   *
   * 단순 나머지(`% 100`)를 쓰지 않는 이유: TourAPI contentid는 지역·시기별로
   * 뭉쳐 발급돼서 끝 두 자리가 고르지 않다. 섞어서 흩뜨린다.
   */
  private static bucketOf(contentId: string): number {
    let h = 2166136261;
    for (let i = 0; i < contentId.length; i++) {
      h ^= contentId.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return Math.abs(h) % 100;
  }

  private static resolveQuestType(place: TourApiPlace): QuestType {
    const mix = QuestService.TYPE_MIX[place.contenttypeid];
    if (!mix || mix.sharePercent <= 0) return "VISIT";
    return QuestService.bucketOf(place.contentid) < mix.sharePercent
      ? mix.special
      : "VISIT";
  }

  /**
   * 장소 하나로 퀘스트 한 건을 만든다.
   *
   * **제목과 유형이 따로 놀면 안 된다.** 식당이 방문형으로 뽑혔는데 제목이
   * "방명록"이면 무엇을 해야 하는지 어긋난다. 그래서 유형을 먼저 정하고
   * 그 유형에 맞는 문구를 고른다.
   */
  /// 일회성 마이그레이션이 같은 규칙을 그대로 쓰도록 공개해 둔다.
  /// 규칙을 두 벌로 베끼면 곧 갈라진다.
  static generateQuestMetadata(place: TourApiPlace) {
    const name = place.title;
    const questType = this.resolveQuestType(place);

    const visitOf = (
      title: string,
      story: string,
      difficulty: number,
      baseExp: number,
      keywords: string[]
    ) => ({ title, story, difficulty, baseExp, keywords, questType });

    switch (place.contenttypeid) {
      case "12": // 관광지
        return questType === "PHOTO_SINGLE"
          ? {
              ...visitOf(
                `${name} 한 컷`,
                `${name}에서 가장 마음에 남는 장면을 한 장에 담아보세요.`,
                3,
                220,
                ["명소", "사진", "관광"]
              ),
              photoPrompt: `${name}을(를) 알아볼 수 있는 장면 한 장`,
            }
          : visitOf(
              `${name} 역사·문화 탐방`,
              `${name}에 도달하여 지역 고유의 특별한 매력을 발견해보세요!`,
              3,
              220,
              ["명소", "탐험", "관광"]
            );

      case "14": // 문화시설
        return questType === "PHOTO_SINGLE"
          ? {
              ...visitOf(
                `${name} 전시 한 장`,
                `${name}의 입구나 대표 안내판을 한 장 남겨보세요.`,
                2,
                150,
                ["문화", "전시", "사진"]
              ),
              photoPrompt: `${name}의 건물 입구 또는 대표 안내판`,
            }
          : visitOf(
              `${name} 로컬 전시 관람`,
              `${name}에서 펼쳐지는 문화와 예술 공간을 조용히 관람해보세요.`,
              2,
              150,
              ["문화", "전시", "힐링"]
            );

      case "15": // 축제·행사
        return questType === "PHOTO_SINGLE"
          ? {
              ...visitOf(
                `${name} 현장 스냅`,
                `${name} 현장의 생생한 분위기를 한 장에 담아보세요!`,
                2,
                180,
                ["축제", "사진", "체험"]
              ),
              photoPrompt: `${name} 현장의 분위기가 드러나는 한 장`,
            }
          : visitOf(
              `${name} 현장 방문`,
              `${name} 현장에 도착해 축제의 공기를 직접 느껴보세요.`,
              2,
              180,
              ["축제", "이벤트", "체험"]
            );

      case "28": // 레포츠 — 도달 자체가 목표라 항상 방문형
        return visitOf(
          `${name} 액티비티 도전`,
          `${name} 주변을 둘러보며 숨겨진 활동 장소를 탐색해 보세요.`,
          3,
          200,
          ["액티비티", "모험", "스포츠"]
        );

      case "32": // 숙박·쉼터
        return questType === "RECORD"
          ? visitOf(
              `${name} 로컬 쉼터 한줄평`,
              `${name} 주변을 거닐며 소도시 휴식의 소감을 한 줄로 남겨보세요.`,
              1,
              50,
              ["휴식", "기록", "힐링"]
            )
          : visitOf(
              `${name} 쉼터 들르기`,
              `${name} 주변 공간을 거닐며 잠시 숨을 돌려보세요.`,
              1,
              50,
              ["휴식", "숙소", "힐링"]
            );

      case "38": // 쇼핑
        return questType === "PHOTO_SINGLE"
          ? {
              ...visitOf(
                `${name} 간판 찾기`,
                `${name}의 정겨운 가게 간판을 한 장 담아보세요.`,
                2,
                110,
                ["시장", "사진", "쇼핑"]
              ),
              photoPrompt: `${name}의 정겨운 가게 간판`,
            }
          : visitOf(
              `${name} 전통시장 둘러보기`,
              `${name}의 풍성한 로컬 정취를 천천히 둘러보세요.`,
              2,
              110,
              ["시장", "탐방", "쇼핑"]
            );

      case "39": // 음식점
        return questType === "RECORD"
          ? visitOf(
              `${name} 맛집 한줄평`,
              `${name}에서 느낀 분위기와 맛을 한 줄로 남겨보세요.`,
              1,
              60,
              ["맛집", "기록", "로컬"]
            )
          : visitOf(
              `${name} 맛집 방문`,
              `${name}에 들러 이 동네의 맛을 확인해보세요.`,
              1,
              60,
              ["맛집", "음식", "로컬"]
            );

      default:
        return visitOf(
          `${name} 스팟 도달`,
          `${name} 목표 지점에 도달하여 로컬 인증을 완료해보세요.`,
          1,
          50,
          ["방문", "탐험"]
        );
    }
  }

  private static async syncNearbyTourQuests(lat: number, lng: number, radiusM: number) {
    const tourPlaces = await this.searchTourApiPlaces(lat, lng, radiusM);

    for (const tPlace of tourPlaces) {
      const placeLat = parseFloat(tPlace.mapy);
      const placeLng = parseFloat(tPlace.mapx);

      if (isNaN(placeLat) || isNaN(placeLng)) continue;

      const meta = this.generateQuestMetadata(tPlace);
      const regionCode = regionNameFromAreaCode(tPlace.areacode);
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

  /**
   * 한 번에 마커로 내려보낼 수 있는 최대 개수 — 체크리스트 08번 BE 몫.
   *
   * 지금까지 `findMany`에 상한이 없어서, 뷰포트를 전국으로 벌리면 퀘스트가
   * 통째로 나갔다. 시드 21개라 드러나지 않았을 뿐이고 콘텐츠가 늘면 그대로
   * 최다 호출 경로의 사고가 된다. 넘치면 잘라 버리는 대신 **클러스터로 바꿔서**
   * 돌려준다 — 개수는 보존되고, 앱은 이미 그 응답을 파싱할 줄 안다.
   */
  private static readonly VIEWPORT_MAX_MARKERS = 200;

  /** 뷰포트 없는 전국 검색의 결과 상한 — 체크리스트 12번 BE 몫. */
  private static readonly SEARCH_MAX_RESULTS = 100;

  /**
   * 격자로 묶어 클러스터를 만든다.
   *
   * `step`은 줌이 낮을수록 넓어진다. 다만 마커가 상한을 넘겨 **강제로** 클러스터가
   * 될 때는 줌이 14 이상일 수 있는데, 그때는 14의 격자(약 0.02°)를 그대로 쓴다.
   * 그보다 잘게 쪼개면 클러스터가 다시 200개를 넘어 상한이 무의미해진다.
   */
  private static buildClusters(
    places: { lat: number; lng: number }[],
    zoom: number
  ) {
    const step = 0.02 * Math.pow(2, 14 - Math.min(zoom, 14));
    const clustersMap = new Map<string, { latSum: number; lngSum: number; count: number }>();

    for (const place of places) {
      const gridLat = Math.floor(place.lat / step) * step;
      const gridLng = Math.floor(place.lng / step) * step;
      const key = `${gridLat.toFixed(4)}_${gridLng.toFixed(4)}`;

      if (!clustersMap.has(key)) {
        clustersMap.set(key, { latSum: 0, lngSum: 0, count: 0 });
      }
      const cluster = clustersMap.get(key)!;
      cluster.latSum += place.lat;
      cluster.lngSum += place.lng;
      cluster.count += 1;
    }

    return Array.from(clustersMap.values()).map((c) => ({
      lat: Number((c.latSum / c.count).toFixed(6)),
      lng: Number((c.lngSum / c.count).toFixed(6)),
      count: c.count,
    }));
  }

  /**
   * 앱에 내려보내기 전에 **정답을 지운다**.
   *
   * `include: { place: true }`는 Quest 행 전체를 담아 오는데 거기에는
   * `quizAnswer`·`quizExplanation`이 들어 있다. 그대로 내려보내면 앱을 뜯거나
   * 프록시로 응답만 봐도 정답이 보인다 — 히든 배지를 서버에서 가리는 것과 같은 이유다.
   *
   * 문제와 선택지는 화면에 그려야 하므로 남긴다. 해설은 채점 응답에서 준다.
   */
  static toClientQuest<T extends { quizAnswer?: string | null; quizExplanation?: string | null }>(
    quest: T
  ): Omit<T, "quizAnswer" | "quizExplanation"> {
    const { quizAnswer: _a, quizExplanation: _e, ...rest } = quest;
    return rest;
  }

  static toClientQuests<T extends { quizAnswer?: string | null; quizExplanation?: string | null }>(
    quests: T[]
  ) {
    return quests.map((q) => QuestService.toClientQuest(q));
  }

  static async getQuestsByViewport(dto: ViewportQueryDto) {
    const {
      swLat,
      swLng,
      neLat,
      neLng,
      zoom = 15,
      keywords,
      search,
      userId,
      originLat,
      originLng,
    } = dto;
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

    const hasViewport =
      swLat !== undefined && swLng !== undefined && neLat !== undefined && neLng !== undefined;
    const hasSearch = !!(search && search.trim().length > 0);

    /** 클러스터를 만들 때는 좌표만 있으면 된다 — 행 전체를 끌어올 이유가 없다. */
    const clusterResponse = async (forced: boolean) => {
      const rows = await prisma.quest.findMany({
        where: whereClause,
        select: { place: { select: { lat: true, lng: true } } },
      });

      // 클러스터는 원 안의 개수만 보여 준다. 완료 여부는 개별 마커의 성질이라
      // 여기서는 붙일 자리가 없다 - 확대해서 마커가 갈라지면 그때 붙는다.
      return {
        isClustered: true,
        zoom,
        totalQuests: rows.length,
        clusters: this.buildClusters(
          rows.map((r) => r.place),
          zoom
        ),
        /** 줌 때문이 아니라 개수가 상한을 넘겨 묶인 응답인지. */
        forced,
      };
    };

    if (zoom < 14 && hasViewport) {
      return clusterResponse(false);
    }

    // 상한 + 1을 읽어 "넘쳤는지"를 한 번의 쿼리로 안다.
    const limit = hasViewport
      ? QuestService.VIEWPORT_MAX_MARKERS
      : QuestService.SEARCH_MAX_RESULTS;

    let quests = await prisma.quest.findMany({
      where: whereClause,
      include: { place: true },
      orderBy: { id: "asc" },
      take: limit + 1,
    });

    let totalQuests = quests.length;

    if (quests.length > limit) {
      // 뷰포트를 보고 있다면 잘라 내는 대신 클러스터로 바꾼다 — 앱은 이미
      // `isClustered`를 보고 갈라 파싱하므로 화면 쪽에 추가 작업이 없다.
      if (hasViewport) {
        return clusterResponse(true);
      }

      // 전국 검색은 격자로 묶어 봐야 지도 밖이라 의미가 없다. 상한에서 자르고
      // 진짜 개수만 따로 세어 알려 준다("100개 넘게 있음"을 앱이 알 수 있게).
      quests = quests.slice(0, limit);
      totalQuests = await prisma.quest.count({ where: whereClause });
    }

    // 검색 결과 거리순 정렬 — 체크리스트 12번.
    //
    // **상한이 정렬보다 먼저 걸린다.** 즉 "가장 가까운 100개"가 아니라
    // "찾은 것 중 100개를 가까운 순으로"다. 진짜 거리순 상한은 공간 인덱스가
    // 있어야 하고, 그건 13번(PostGIS 판단)에서 결론이 난 뒤의 일이다.
    if (hasSearch && originLat !== undefined && originLng !== undefined) {
      quests = [...quests].sort(
        (a, b) =>
          calculateHaversineDistance(originLat, originLng, a.place.lat, a.place.lng) -
          calculateHaversineDistance(originLat, originLng, b.place.lat, b.place.lng)
      );
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
      totalQuests,
      quests: QuestService.toClientQuests(
        completed
          ? quests.map((q) => ({ ...q, isCompleted: completed.has(q.id) }))
          : quests
      ),
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
    if (!userId) return QuestService.toClientQuests(nearbyQuests);

    const completed = await this.completedQuestIds(
      userId,
      nearbyQuests.map((q) => q.id)
    );
    return QuestService.toClientQuests(
      nearbyQuests.filter((q) => !completed.has(q.id))
    );
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

    return QuestService.toClientQuests(quests);
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

    return userQuests.map((uq) => ({
      ...uq,
      quest: QuestService.toClientQuest(uq.quest),
    }));
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

    return QuestService.toClientQuest(quest);
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

    // ── 유형별 검증 ─────────────────────────────────────────────────────
    //
    // 지금까지 `verifyQuest`는 유형을 보지 않고 거리만 봤다(체크리스트 26번).
    // 아래 둘은 **앱을 고치지 않아도** 서버에서 판정할 수 있어 먼저 붙인다.
    // 나머지(퀴즈·탐색의 정답, 수집형의 N장, 기록형의 한 줄)는 인증 화면에
    // 입력 자리가 없어 아직 강제하지 못한다 — 그건 26번 본작업이다.

    // 06 피사체 지정형 — 사진이 없으면 인증이 성립하지 않는다.
    if (quest.questType === "PHOTO_SINGLE" && !dto.photoUrl) {
      throw new CustomError(
        400,
        "PHOTO_REQUIRED",
        "이 퀘스트는 사진 인증이 필요합니다. 사진을 찍고 다시 시도해 주세요."
      );
    }

    // 09 퀴즈형 · 10 탐색형 — 정답을 맞혀야 인증이다.
    //
    // 정답이 비어 있는 퀘스트(자동 생성분)는 채점할 것이 없으므로 통과시킨다.
    // 지금은 자동 생성에서 이 유형을 만들지 않지만, 과거 데이터가 남아 있을 수 있다.
    if (
      (quest.questType === "QUIZ" || quest.questType === "EXPLORATION") &&
      quest.quizAnswer
    ) {
      const picked = dto.answer?.trim();
      if (!picked) {
        throw new CustomError(
          400,
          "ANSWER_REQUIRED",
          "이 퀘스트는 정답을 골라야 인증됩니다."
        );
      }
      if (picked !== quest.quizAnswer.trim()) {
        throw new CustomError(
          400,
          "WRONG_ANSWER",
          "정답이 아니에요. 다시 살펴보고 골라 주세요."
        );
      }
    }

    // 13 기록형 — 한 줄이 인증의 알맹이다. 4b 화면이 입력을 받아 보낸다.
    if (quest.questType === "RECORD" && !dto.userText?.trim()) {
      throw new CustomError(
        400,
        "NOTE_REQUIRED",
        "이 퀘스트는 한 줄 기록이 필요합니다."
      );
    }

    // 05 시간대 제한형 — 창이 정해진 퀘스트만 판정한다.
    // 값이 비어 있으면(자동 생성 퀘스트 대부분) 그냥 통과시킨다.
    if (
      quest.questType === "TIME_WINDOW" &&
      quest.timeWindowStart &&
      quest.timeWindowEnd &&
      !isWithinTimeWindowKST(quest.timeWindowStart, quest.timeWindowEnd, now)
    ) {
      throw new CustomError(
        400,
        "OUT_OF_TIME_WINDOW",
        `이 퀘스트는 ${quest.timeWindowStart}~${quest.timeWindowEnd}에만 인증할 수 있습니다.`
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

    // 체크리스트 18번 — 위치 위조도 속도 어뷰징과 같은 줄에 세운다.
    // 404나 400으로 돌려보내지 않는 이유: 막았다는 사실을 알려 주면
    // 가짜 위치 앱을 끄고 다시 시도하면 그만이다. 완료는 기록하되 EXP를 0으로
    // 주고(`calculateRewardExp`의 abusePenalty), `is_abused`로 남긴다.
    if (dto.isMocked === true) {
      isAbused = true;
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

    // 체크리스트 15번 — 지금까지 `streak_days`는 읽히기만 하고 아무도 쓰지 않아
    // 영원히 0이었다(→ mStreak이 항상 1.0). `lastActiveAt`은 이 메서드에서만
    // 쓰이므로 "마지막 완료 시각"과 같다 — 그걸 기준으로 KST 하루 단위 연속일을 센다.
    //
    // 배율에는 **오늘을 포함한** 값을 쓴다. 이틀 연속 완료면 2가 되어 x1.1이 붙는다.
    const streakDays = calculateStreak(user.lastActiveAt, user.streakDays, now);

    const expResult = calculateRewardExp(
      {
        baseExp: quest.baseExp,
        // halfStep은 퀘스트의 난이도 성질(★½)이지 재수행 여부가 아니다.
        // 재수행에 true를 먹이면 x1.15 보너스가 붙어 바로 아래 x0.3 패널티와 서로
        // 상쇄된다 — 6b 배율표에도 그런 항목은 없다.
        halfStep: quest.halfStep,
        congestionScore: toCongestionTier(quest.place.congestionScore),
        isNewArea,
        isOffPeak,
        streakDays,
        isAbused,
        // 체크리스트 16번 — 엔진에 mRepeat(x0.3)가 있는데 넘기지앨아
        // 재수행이 정가로 지급되고 있었다.
        isRepeat,
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
          streakDays,
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