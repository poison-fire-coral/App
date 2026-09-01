import cron from "node-cron";
import { prisma } from "../utils/prisma";
import { PushService } from "../services/push.service";

/**
 * "주변 퀘스트 알림" 발송 배치 — 체크리스트 24번.
 *
 * 설정 화면과 온보딩이 사용자에게 약속한 그 알림이다. 스위치만 있고 보내는
 * 쪽이 없던 자리를 채운다.
 *
 * **누구에게.** 알림을 켠 기기가 있고, 홈 지역(`homeRegion`)을 고른 사람.
 * 홈 지역이 없으면 "주변"을 정할 근거가 없으므로 건너뛴다 — 아무 데나 골라
 * 보내면 알림을 끄는 이유가 된다.
 *
 * **무엇을.** 그 지역에서 아직 완료하지 않은 퀘스트 하나. 여러 개를 나열하면
 * 알림 한 줄에 안 들어가고, 무엇을 하라는 것인지도 흐려진다.
 *
 * **언제.** 하루 한 번, KST 오전 10시. 서버가 UTC 로 도는 경우가 많아
 * node-cron 의 timezone 을 명시한다 — 15번에서 KST 를 놓쳐 배율이 9시간
 * 어긋났던 것과 같은 함정이다.
 */

export async function runNearbyQuestPush() {
  try {
    const users = await prisma.user.findMany({
      where: {
        homeRegion: { not: null },
        devices: { some: { enabled: true } },
      },
      select: { id: true, nickname: true, homeRegion: true },
    });

    if (users.length === 0) {
      console.log("[NearbyQuestPush] 보낼 대상이 없습니다.");
      return;
    }

    let sent = 0;

    for (const user of users) {
      // 이미 완료한 퀘스트는 권하지 않는다 - 22번과 같은 규칙이다.
      const quest = await prisma.quest.findFirst({
        where: {
          active: true,
          place: { regionCode: user.homeRegion! },
          completions: { none: { userId: user.id, isAbused: false } },
        },
        include: { place: { select: { name: true } } },
        // 매일 같은 퀘스트만 권하지 않도록 최근 것부터 돌려 준다.
        orderBy: { id: "desc" },
      });

      if (!quest) continue;

      const count = await PushService.sendToUser(user.id, {
        title: "가까운 곳에 퀘스트가 있어요",
        body: `${quest.place.name} · ${quest.title}`,
        data: { type: "NEARBY_QUEST", questId: String(quest.id) },
      });

      sent += count;
    }

    console.log(`[NearbyQuestPush] ${users.length}명 대상, ${sent}건 발송`);
  } catch (error) {
    console.error("[NearbyQuestPush] 배치 실행 중 오류 발생:", error);
  }
}

/**
 * 스케줄러 등록.
 *
 * **혼잡도 배치와 달리 서버 기동 시 즉시 보내지 않는다.** 서버를 재시작할
 * 때마다 모든 사용자에게 알림이 가면 그게 곧 스팸이다. 개발 중에 한 번
 * 보내 보려면 `runNearbyQuestPush()` 를 직접 부른다.
 */
export const startNearbyQuestPushJob = () => {
  cron.schedule(
    "0 10 * * *",
    async () => {
      console.log("[NearbyQuestPush] 주변 퀘스트 알림 배치 시작");
      await runNearbyQuestPush();
    },
    { timezone: "Asia/Seoul" }
  );
};
