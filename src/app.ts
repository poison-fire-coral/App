import express from "express";
import cors from "cors";
import authRoutes from "./routes/auth.routes";
import userRoutes from "./routes/user.routes";
import questRoutes from "./routes/quest.routes";
import badgeRoutes from "./routes/badge.routes";
import privacyRouter from "./routes/privacy.router";
import { errorHandler } from "./middlewares/errorHandler";

const app = express();

app.use(cors());
app.use(express.json());

// Health Check
app.get("/", (req, res) => {
  res.json({ status: "OK", message: "Local Quest API Server is running!" });
});

// 공개 약관 라우터 (Google Play Console 제출용 /privacy)
app.use(privacyRouter);

// API 라우터 연결
app.use("/api/v1/auth", authRoutes);
app.use("/api/v1/users", userRoutes);
app.use("/api/v1/quests", questRoutes);
app.use("/api/v1/badges", badgeRoutes);

// 전역 에러 핸들러
app.use(errorHandler);

export default app;