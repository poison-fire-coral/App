import jwt from "jsonwebtoken";

import { env } from "../config/env";

const ACCESS_TOKEN_EXPIRES_IN = "1h";
const REFRESH_TOKEN_EXPIRES_IN = "14d";

/**
 * 토큰의 쓰임. **액세스와 리프레시를 구분하는 유일한 표시다.**
 *
 * 예전에는 둘이 같은 키로 같은 페이로드(`{userId}`)를 서명해서, 서로 완전히
 * 교환 가능했다. 리프레시 토큰 하나가 새면 그대로 14일짜리 액세스 토큰이 되고,
 * 모든 인증 경로를 통과했다. 만료가 짧다는 액세스 토큰의 성질이 무의미해진다.
 */
type TokenType = "access" | "refresh";

export interface JwtPayload {
  userId: number;
  type?: TokenType;
}

export const generateTokens = (userId: number) => {
  const accessToken = jwt.sign({ userId, type: "access" }, env.jwtSecret, {
    expiresIn: ACCESS_TOKEN_EXPIRES_IN,
  });
  const refreshToken = jwt.sign({ userId, type: "refresh" }, env.jwtSecret, {
    expiresIn: REFRESH_TOKEN_EXPIRES_IN,
  });
  return { accessToken, refreshToken };
};

/**
 * 서명과 쓰임을 함께 확인한다.
 *
 * `type`이 없는 토큰은 이 변경 전에 발급된 것이다. 리프레시 유효기간(14일)이
 * 지나면 자연히 사라지므로 그때까지는 받아 준다 — 안 그러면 배포하는 순간
 * 접속 중인 사람이 전부 로그아웃된다.
 */
function verify(token: string, expected: TokenType): JwtPayload {
  const payload = jwt.verify(token, env.jwtSecret) as JwtPayload;

  if (payload.type && payload.type !== expected) {
    throw new jwt.JsonWebTokenError(
      `${expected} 토큰이 필요한 자리에 ${payload.type} 토큰이 왔습니다.`
    );
  }

  return payload;
}

export const verifyAccessToken = (token: string): JwtPayload =>
  verify(token, "access");

export const verifyRefreshToken = (token: string): JwtPayload =>
  verify(token, "refresh");
