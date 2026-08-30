import app from "./app";
import dotenv from "dotenv";
import { startCongestionBatchJob } from "./jobs/congestionScore.job";

dotenv.config();

const PORT = Number(process.env.PORT) || 5001;

// 💡 혼잡도 계산 배치 스케줄러 등록
startCongestionBatchJob();

// '0.0.0.0'을 추가하여 외부 기기(핸드폰) 접속을 허용합니다.
app.listen(PORT, "0.0.0.0", () => {
  console.log(`서버가 http://0.0.0.0:${PORT} 에서 실행 중입니다.`);
});