import { Router } from "express";
import { QuestController } from "../controllers/quest.controller";
import { authenticateToken, optionalAuth } from "../middlewares/auth.middleware";

const router = Router();

// 1. 전체 / 지도 뷰포트 / 클러스터링 조회
//
// optionalAuth: 로그인 없이도 지도는 보여야 하지만, 로그인했다면 각 퀘스트에
// isCompleted 를 붙여 준다(체크리스트 22번). 토큰이 없거나 깨져도 통과한다.
router.get("/", optionalAuth, QuestController.getQuests);

// 2. 근처 퀘스트 거리순 조회 (로그인했다면 완료한 퀘스트를 뺀다)
router.get("/nearby", optionalAuth, QuestController.getNearbyQuests);

// 3. 내 맞춤 추천 퀘스트 조회 (JWT 인증 필요)
router.get("/recommended", authenticateToken, QuestController.getRecommendedQuests);

// 4. 내 진행 중/완료 퀘스트 목록 조회 (JWT 인증 필요)
router.get("/my", authenticateToken, QuestController.getMyQuests);

// 5. 퀘스트 단건 상세 조회
router.get("/:id", QuestController.getQuestById);

// 6. 퀘스트 수락 (JWT 인증 필요)
router.post("/:id/accept", authenticateToken, QuestController.acceptQuest);

// 7. 퀘스트 취소/포기 (JWT 인증 필요)
router.delete("/:id/accept", authenticateToken, QuestController.abandonQuest);

// 8. 도달 인증 및 보상 지급 (JWT 인증 필요)
router.post("/:id/verify", authenticateToken, QuestController.verifyQuest);

// 9. 사진 업로드 Presigned URL 발급 (JWT 인증 필요)
router.post("/:id/upload-url", authenticateToken, QuestController.getUploadUrl);

export default router;