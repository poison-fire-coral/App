import axios from "axios";
import { prisma } from "../utils/prisma";
import { generateTokens, verifyRefreshToken } from "../utils/jwt";
import { AppError } from "../utils/CustomError";

export type AuthProvider = "KAKAO" | "GOOGLE" | "GUEST";

interface LoginDTO {
  provider: AuthProvider;
  token?: string;
  providerUid?: string;
}

interface SignupDTO {
  provider: AuthProvider;
  providerUid: string;
  email?: string;
  nickname: string;
  avatarId?: string;
  homeRegion?: string;
  activityLevel?: string;
  keywords?: string[];
  termsAgreed: boolean;
  termsVersion: string;
}

export class AuthService {
  // 1. 소셜 로그인 (미가입 시 AUTH_NOT_REGISTERED 에러 반환)
  static async login(dto: LoginDTO) {
    const { provider, token, providerUid } = dto;
    let targetUid = providerUid;
    let email: string | undefined = undefined;

    if (provider === "KAKAO") {
      if (!token) throw new AppError("BAD_REQUEST", "카카오 토큰이 필요합니다.");
      const kakaoUser = await this.verifyKakaoToken(token);
      targetUid = String(kakaoUser.id);
      email = kakaoUser.kakao_account?.email;
    } else if (provider === "GOOGLE") {
      if (!token) throw new AppError("BAD_REQUEST", "구글 토큰이 필요합니다.");
      const googleUser = await this.verifyGoogleToken(token);
      targetUid = googleUser.sub;
      email = googleUser.email;
    } else if (provider === "GUEST") {
      if (!targetUid) {
        targetUid = `guest_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
      }
    } else {
      throw new AppError("BAD_REQUEST", "지원하지 않는 인증 수단입니다.");
    }

    const user = await prisma.user.findFirst({
      where: { provider, providerUid: targetUid },
    });

    // 미가입 유저일 경우 가입 불가 에러 반환 (자동 회원가입 금지)
    if (!user) {
      throw new AppError("AUTH_NOT_REGISTERED", "가입되지 않은 사용자입니다. 회원가입을 진행해 주세요.", {
        provider,
        providerUid: targetUid,
        email,
      });
    }

    // 토큰 생성 및 DB 저장
    const tokens = generateTokens(user.id);
    await prisma.user.update({
      where: { id: user.id },
      data: { refreshToken: tokens.refreshToken },
    });

    return {
      ...tokens,
      isNewUser: false,
      user,
    };
  }

  // 2. 닉네임 중복 확인 API (추가)
  static async checkNickname(nickname: string) {
    if (!nickname || nickname.trim().length === 0) {
      throw new AppError("BAD_REQUEST", "검사할 닉네임을 입력해 주세요.");
    }

    const existingUser = await prisma.user.findUnique({
      where: { nickname: nickname.trim() },
    });

    return {
      nickname: nickname.trim(),
      isAvailable: !existingUser,
    };
  }

  // 3. 회원가입 API (약관동의 및 온보딩 정보 동시 저장)
  static async signup(dto: SignupDTO) {
    const {
      provider,
      providerUid,
      email,
      nickname,
      avatarId,
      homeRegion,
      activityLevel,
      keywords,
      termsAgreed,
      termsVersion,
    } = dto;

    if (!termsAgreed) {
      throw new AppError("BAD_REQUEST", "필수 서비스 이용약관에 동의해야 합니다.");
    }

    const existingUser = await prisma.user.findFirst({
      where: { provider, providerUid },
    });

    if (existingUser) {
      throw new AppError("BAD_REQUEST", "이미 가입된 사용자입니다.");
    }

    const existingNickname = await prisma.user.findUnique({
      where: { nickname },
    });

    if (existingNickname) {
      throw new AppError("DUPLICATE_NICKNAME", "이미 사용 중인 닉네임입니다.");
    }

    const user = await prisma.user.create({
      data: {
        provider,
        providerUid,
        email,
        nickname,
        avatarId,
        homeRegion,
        activityLevel,
        termsAgreed,
        termsAgreedAt: new Date(),
        termsVersion,
        level: 1,
        expTotal: 0,
        expCurrent: 0,
        keywords:
          keywords && keywords.length > 0
            ? {
                create: keywords.map((keywordId) => ({ keywordId })),
              }
            : undefined,
      },
      include: {
        keywords: true,
      },
    });

    const tokens = generateTokens(user.id);
    await prisma.user.update({
      where: { id: user.id },
      data: { refreshToken: tokens.refreshToken },
    });

    return {
      ...tokens,
      user,
    };
  }

  // 4. Refresh Token으로 Access Token 갱신
  static async refreshTokens(refreshToken: string) {
    if (!refreshToken) {
      throw new AppError("BAD_REQUEST", "리프레시 토큰이 필요합니다.");
    }

    try {
      const decoded = verifyRefreshToken(refreshToken);
      const user = await prisma.user.findUnique({
        where: { id: decoded.userId },
      });

      if (!user || user.refreshToken !== refreshToken) {
        throw new AppError("UNAUTHORIZED", "유효하지 않거나 만료된 리프레시 토큰입니다.");
      }

      const tokens = generateTokens(user.id);
      await prisma.user.update({
        where: { id: user.id },
        data: { refreshToken: tokens.refreshToken },
      });

      return tokens;
    } catch {
      throw new AppError("UNAUTHORIZED", "만료되었거나 유효하지 않은 리프레시 토큰입니다.");
    }
  }

  private static async verifyKakaoToken(token: string) {
    try {
      const response = await axios.get("https://kapi.kakao.com/v2/user/me", {
        headers: { Authorization: `Bearer ${token}` },
      });
      return response.data;
    } catch {
      throw new AppError("UNAUTHORIZED", "유효하지 않은 카카오 토큰입니다.");
    }
  }

  private static async verifyGoogleToken(token: string) {
    try {
      const response = await axios.get("https://www.googleapis.com/oauth2/v3/userinfo", {
        headers: { Authorization: `Bearer ${token}` },
      });
      return response.data;
    } catch {
      throw new AppError("UNAUTHORIZED", "유효하지 않은 구글 토큰입니다.");
    }
  }
}