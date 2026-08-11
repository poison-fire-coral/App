import axios from "axios";

export interface SocialUserInfo {
  providerUid: string;
  email?: string;
}

export class SocialUtil {
  // 카카오 토큰 검증
  static async verifyKakaoToken(accessToken: string): Promise<SocialUserInfo> {
    try {
      const response = await axios.get("https://kapi.kakao.com/v2/user/me", {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        },
      });

      const { id, kakao_account } = response.data;
      return {
        providerUid: String(id),
        email: kakao_account?.email || null,
      };
    } catch (error) {
      throw new Error("유효하지 않은 카카오 액세스 토큰입니다.");
    }
  }

  // 구글 ID 토큰 검증
  static async verifyGoogleToken(idToken: string): Promise<SocialUserInfo> {
    try {
      const response = await axios.get(
        `https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`
      );

      const { sub, email } = response.data;
      return {
        providerUid: sub,
        email: email || null,
      };
    } catch (error) {
      throw new Error("유효하지 않은 구글 ID 토큰입니다.");
    }
  }
}