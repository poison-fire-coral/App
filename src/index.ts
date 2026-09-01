import app from "./app";
import dotenv from "dotenv";
import { startCongestionBatchJob } from "./jobs/congestionScore.job";
import { startNearbyQuestPushJob } from "./jobs/nearbyQuestPush.job";

dotenv.config();

const PORT = Number(process.env.PORT) || 5001;

// 💡 혼잡도 계산 배치 스케줄러 등록
startCongestionBatchJob();

// 주변 퀘스트 알림 배치 등록 (체크리스트 24번).
// 서비스 계정 키가 없으면 push.service 가 스스로 no-op 이 되므로,
// 알림을 안 쓰는 개발 환경에서도 이 줄 때문에 막히지 않는다.
startNearbyQuestPushJob();

// '0.0.0.0'을 추가하여 외부 기기(핸드폰) 접속을 허용합니다.
app.listen(PORT, "0.0.0.0", () => {
  console.log(`서버가 http://0.0.0.0:${PORT} 에서 실행 중입니다.`);
});