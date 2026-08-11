import { Router } from "express";
import { AuthController } from "../controllers/auth.controller";

const router = Router();

// 소셜 로그인 (미가입 시 AUTH_NOT_REGISTERED 에러 반환)
router.post("/login", AuthController.login);

// 닉네임 중복 확인 (회원가입 단계용)
router.get("/check-nickname", AuthController.checkNickname);

// 회원가입 (약관 동의 + 온보딩 정보 동시 처리)
router.post("/signup", AuthController.signup);

// Access Token 재발급
router.post("/refresh", AuthController.refresh);

export default router;