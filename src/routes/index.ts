import { Router } from "express";
import authRouter from "./auth.routes";
import userRouter from "./user.routes";
import questRouter from "./quest.routes"; // 기존 작성해둔 퀘스트 라우터

const router = Router();

// /api/v1 하위 라우트 등록
router.use("/auth", authRouter);
router.use("/users", userRouter);
router.use("/quests", questRouter);

export default router;