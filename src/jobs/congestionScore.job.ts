import cron from "node-cron";
import { prisma } from "../utils/prisma";

// 💡 주요 관광지/지역별 초기 기본 혼잡도 등급 상수 (Seed Score)
const INITIAL_REGION_SEED_SCORES: Record<string, number> = {
  서울: 35,
  제주: 30,
  부산: 25,
  경주: 20,
  강릉: 20,
};

/**
 * 장소별 혼잡도 계산 실행
 */
export async function runCongestionCalculation() {
  try {
    const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);

    // 1. 최근 2시간 내 완료된 퀘스트 수 집계 (어뷰징 제외)
    const recentCompletions = await prisma.questCompletion.groupBy({
      by: ["questId"],
      where: {
        createdAt: { gte: twoHoursAgo },
        isAbused: false,
      },
      _count: { id: true },
    });

    const questCountMap = new Map<number, number>();
    recentCompletions.forEach((item) => {
      questCountMap.set(item.questId, item._count.id);
    });

    // 2. 전체 장소 및 연결된 퀘스트 데이터 조회
    const places = await prisma.place.findMany({
      include: {
        quests: { select: { id: true } },
      },
    });

    // 3. 장소별 혼잡도 스코어 산출 및 일괄 반영
    const updatePromises = places.map((place) => {
      let totalCompletions = 0;
      for (const quest of place.quests) {
        totalCompletions += questCountMap.get(quest.id) || 0;
      }

      // 지역 초기 상수값(Seed) 확인 (기본값: 5)
      let baseScore = 5;
      for (const [regionKey, seedValue] of Object.entries(INITIAL_REGION_SEED_SCORES)) {
        if (
          place.address?.includes(regionKey) ||
          place.regionCode?.includes(regionKey) ||
          place.name.includes(regionKey)
        ) {
          baseScore = seedValue;
          break;
        }
      }

      // 혼잡도 계산: (수행 횟수 * 10) + 초기 기본점수 (최소 1, 최대 100)
      const updatedScore = Math.min(
        100,
        Math.max(1, Math.round(totalCompletions * 10 + baseScore))
      );

      return prisma.place.update({
        where: { id: place.id },
        data: { congestionScore: updatedScore },
      });
    });

    await Promise.all(updatePromises);
    console.log(`[CongestionBatch] ${places.length}개 장소 혼잡도 스코어 갱신 완료`);
  } catch (error) {
    console.error("[CongestionBatch] 혼잡도 배치 실행 중 오류 발생:", error);
  }
}

/**
 * 혼잡도 배치 스케줄러 (서버 시작 시 1회 실행 + 10분 주기 실행)
 */
export const startCongestionBatchJob = () => {
  // 서버 기동 시 즉시 1회 실행
  runCongestionCalculation();

  // 매 10분마다 정기 execution
  cron.schedule("*/10 * * * *", async () => {
    console.log("[CongestionBatch] 혼잡도 주기적 배치 시작");
    await runCongestionCalculation();
  });
};