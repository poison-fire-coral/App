import { Request, Response, NextFunction } from "express";
import { AuthenticatedRequest } from "../middlewares/auth.middleware";
import { UserService } from "../services/user.service";
import { PushService } from "../services/push.service";
import { AppError } from "../utils/CustomError";

export class UserController {
  // 1. 내 프로필 조회
  static async getProfile(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const profile = await UserService.getMyProfile(userId);
      return res.status(200).json({ data: profile, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 2. 프로필 수정 (온보딩 정보 및 키워드 수정 포함)
  static async updateProfile(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const { nickname, avatarId, homeRegion, activityLevel, keywords } = req.body;

      const updatedUser = await UserService.updateProfile({
        userId,
        nickname,
        avatarId,
        homeRegion,
        activityLevel,
        keywords,
      });

      return res.status(200).json({ data: updatedUser, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 3. 닉네임 중복 확인 (User 엔드포인트용)
  static async checkNickname(req: Request, res: Response, next: NextFunction) {
    try {
      const nickname = req.query.nickname as string;
      const result = await UserService.checkNickname(nickname);
      return res.status(200).json({ data: result, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 4. 프로필 화면(5c) — 통계 + 최근 발자국
  static async getProfileSummary(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const summary = await UserService.getProfileSummary(userId);
      return res.status(200).json({ data: summary, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 5. 회원 탈퇴 (본인 계정 삭제)
  static async deleteMe(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      await UserService.deleteAccount(userId);
      return res.status(200).json({
        data: { message: "회원 탈퇴가 완료되었습니다." },
        error: null,
      });
    } catch (error) {
      next(error);
    }
  }

  // 6. 푸시 기기 등록 (체크리스트 24번)
  //
  // 앱이 로그인할 때마다 부른다. FCM 토큰은 앱을 지웠다 깔거나 데이터를
  // 지우면 바뀌므로, 한 번 보내고 마는 값이 아니라 **매번 확인하는 값**이다.
  static async registerDevice(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const { fcmToken, platform, enabled } = req.body;
      if (typeof fcmToken !== "string" || fcmToken.trim().length === 0) {
        throw new AppError("BAD_REQUEST", "fcmToken이 필요합니다.");
      }

      await PushService.registerDevice({
        userId,
        fcmToken: fcmToken.trim(),
        platform: typeof platform === "string" ? platform : undefined,
        enabled: enabled !== false,
      });

      return res.status(200).json({ data: { registered: true }, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 7. 푸시 기기 해제 — 로그아웃할 때 부른다.
  //
  // 안 부르면 로그아웃한 기기로 알림이 계속 간다. 토큰을 body로 받는 이유는
  // 어느 기기를 빼는지 서버가 알 방법이 그것뿐이기 때문이다.
  static async unregisterDevice(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const { fcmToken } = req.body;
      if (typeof fcmToken !== "string" || fcmToken.trim().length === 0) {
        throw new AppError("BAD_REQUEST", "fcmToken이 필요합니다.");
      }

      await PushService.unregisterDevice(userId, fcmToken.trim());
      return res.status(200).json({ data: { registered: false }, error: null });
    } catch (error) {
      next(error);
    }
  }

  // 8. 알림 스위치 — 토큰은 두고 발송 대상에서만 뺀다.
  //
  // 토큰까지 지우면 다시 켤 때 OS 권한 팝업을 또 띄워야 하고, 한 번 거절한
  // 사용자는 설정 앱까지 들어가야 한다.
  static async setPushEnabled(req: AuthenticatedRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) {
        throw new AppError("UNAUTHORIZED", "인증 정보가 유효하지 않습니다.");
      }

      const enabled = req.body?.enabled;
      if (typeof enabled !== "boolean") {
        throw new AppError("BAD_REQUEST", "enabled(boolean)가 필요합니다.");
      }

      await PushService.setEnabled(userId, enabled);
      return res.status(200).json({ data: { enabled }, error: null });
    } catch (error) {
      next(error);
    }
  }
}