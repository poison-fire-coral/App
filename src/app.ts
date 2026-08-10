import express from "express";
import cors from "cors";
import authRoutes from "./routes/auth.routes";
import userRoutes from "./routes/user.routes";
import questRoutes from "./routes/quest.routes";
import { errorHandler } from "./middlewares/errorHandler";

const app = express();

app.use(cors());
app.use(express.json());

// Health Check
app.get("/", (req, res) => {
  res.json({ status: "OK", message: "Local Quest API Server is running!" });
});

// API 라우터 연결
app.use("/api/v1/auth", authRoutes);
app.use("/api/v1/users", userRoutes);
app.use("/api/v1/quests", questRoutes);

// 전역 에러 핸들러
app.use(errorHandler);

export default app;
