import {
  App,
  applicationDefault,
  cert,
  getApps,
  initializeApp,
} from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { prisma } from "../utils/prisma";

/**
 * 푸시 발송 — 체크리스트 24번.
 *
 * **자격 증명이 없으면 조용히 꺼진다.** TOUR_API_SERVICE_KEY 와 같은 규칙이다.
 * 서비스 계정 키가 없다고 서버가 안 뜨면 알림과 무관한 개발자까지 막힌다.
 * 대신 처음 한 번 경고를 찍고, 이후 발송 요청은 전부 no-op 이 된다.
 *
 * **키를 주는 법 (둘 중 하나)**
 *  - `GOOGLE_APPLICATION_CREDENTIALS` 에 서비스 계정 JSON 파일 경로
 *  - `FIREBASE_SERVICE_ACCOUNT_JSON` 에 그 JSON 을 통째로 (배포 환경용)
 */

let cachedApp: App | null = null;
let disabled = false;

function ensureApp(): App | null {
  if (disabled) return null;
  if (cachedApp) return cachedApp;

  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const filePath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (!inlineJson && !filePath) {
    console.warn(
      "⚠️ FIREBASE_SERVICE_ACCOUNT_JSON / GOOGLE_APPLICATION_CREDENTIALS 가 없습니다. 푸시 발송을 건너뜁니다."
    );
    disabled = true;
    return null;
  }

  try {
    // 이미 초기화된 앱이 있으면 그걸 쓴다. 테스트에서 모듈이 두 번 로드되면
    // initializeApp 이 중복 오류를 낸다.
    const existing = getApps();
    cachedApp =
      existing.length > 0
        ? existing[0]
        : initializeApp({
            credential: inlineJson
              ? cert(JSON.parse(inlineJson))
              : applicationDefault(),
          });
    return cachedApp;
  } catch (error) {
    console.error("❌ Firebase Admin 초기화 실패. 푸시 발송을 끕니다.", error);
    disabled = true;
    return null;
  }
}

export interface PushMessage {
  title: string;
  body: string;
  /** 앱이 탭했을 때 어디로 갈지 정하는 값들. 값은 전부 문자열이어야 한다. */
  data?: Record<string, string>;
}

export class PushService {
  /**
   * 기기 토큰을 등록하거나 갱신한다.
   *
   * **upsert 인 이유.** 같은 폰에서 A가 로그아웃하고 B가 로그인하면 FCM 토큰은
   * 그대로다. `fcm_token` 이 유니크라 upsert 한 번에 소유자가 B로 넘어가고,
   * A의 알림이 B의 폰에 뜨는 일이 없다.
   */
  static async registerDevice(params: {
    userId: number;
    fcmToken: string;
    platform?: string;
    enabled?: boolean;
  }) {
    const { userId, fcmToken, platform, enabled = true } = params;

    return prisma.userDevice.upsert({
      where: { fcmToken },
      create: { userId, fcmToken, platform, enabled },
      update: { userId, platform, enabled },
    });
  }

  /**
   * 기기를 등록 해제한다.
   *
   * 남의 토큰을 지울 수 없도록 userId 를 조건에 함께 건다. 없는 토큰을 지우는
   * 것은 실패가 아니다 — 원하는 상태(등록 안 됨)는 이미 같다.
   */
  static async unregisterDevice(userId: number, fcmToken: string) {
    await prisma.userDevice.deleteMany({ where: { userId, fcmToken } });
  }

  /** 설정 화면의 스위치. 토큰은 지우지 않고 발송 대상에서만 뺀다. */
  static async setEnabled(userId: number, enabled: boolean) {
    await prisma.userDevice.updateMany({ where: { userId }, data: { enabled } });
  }

  /**
   * 한 사람의 모든 기기로 보낸다. 보낸 건수를 돌려준다.
   *
   * **죽은 토큰을 지운다.** 앱을 지운 기기의 토큰은 영원히 실패하는데,
   * 그대로 두면 발송할 때마다 헛돈다. FCM 이 `registration-token-not-registered`
   * 로 알려 주므로 그때 정리한다.
   */
  static async sendToUser(userId: number, message: PushMessage): Promise<number> {
    const app = ensureApp();
    if (!app) return 0;

    const devices = await prisma.userDevice.findMany({
      where: { userId, enabled: true },
      select: { fcmToken: true },
    });
    if (devices.length === 0) return 0;

    const tokens = devices.map((d) => d.fcmToken);

    const response = await getMessaging(app).sendEachForMulticast({
      tokens,
      notification: { title: message.title, body: message.body },
      data: message.data,
    });

    const dead: string[] = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;

      const code = (result.error as { code?: string } | undefined)?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        dead.push(tokens[index]);
      }
    });

    if (dead.length > 0) {
      await prisma.userDevice.deleteMany({ where: { fcmToken: { in: dead } } });
      console.log(`🧹 죽은 푸시 토큰 ${dead.length}개를 지웠습니다.`);
    }

    return response.successCount;
  }
}
