import { Request, Response, NextFunction } from "express";

import { env } from "../config/env";

/**
 * 마지막 그물.
 *
 * **운영에서는 예상하지 못한 오류의 내용을 밖으로 내보내지 않는다.**
 * 예전에는 `err.message`를 그대로 실어 보내서, Prisma가 던진 문구가 그대로
 * 나갔다 — 테이블·컬럼 이름과 때로는 쿼리 파라미터까지 담겨 있다.
 * 우리가 의도적으로 만든 오류(`CustomError`)는 사용자에게 보여 주려고 쓴
 * 문장이므로 그대로 두고, 그 밖의 것만 가린다.
 *
 * 서버 로그에는 언제나 원문을 남긴다. 가리는 것은 응답이지 기록이 아니다.
 */
export const errorHandler = (
  err: any,
  _req: Request,
  res: Response,
  _next: NextFunction
) => {
  console.error("❌ [Error Caught]:", err);

  // instanceof 대신 속성 기반 검사 — CustomError 가 여러 경로로 만들어진다.
  const statusCode =
    err?.statusCode || (typeof err?.status === "number" ? err.status : null);
  const isIntentional = Boolean(statusCode || err?.errorCode || err?.name === "CustomError");

  if (isIntentional) {
    return res.status(statusCode || 400).json({
      data: null,
      error: {
        code: err?.errorCode || err?.code || "BAD_REQUEST",
        message: err?.message || "요청 처리 중 오류가 발생했습니다.",
        ...(err?.details && { details: err.details }),
      },
    });
  }

  return res.status(500).json({
    data: null,
    error: {
      code: "INTERNAL_SERVER_ERROR",
      message: env.isProduction
        ? "서버 내부 오류가 발생했습니다."
        : err?.message || "서버 내부 오류가 발생했습니다.",
    },
  });
};

/**
 * 어느 라우터에도 걸리지 않은 요청.
 *
  * 없으면 Express 기본 HTML 오류 페이지가 나가서, 앱의 `{data, error}` 파서가
 * 파싱에 실패하고 "알 수 없는 오류"로 뭉개진다.
 */
export const notFoundHandler = (req: Request, res: Response) => {
  res.status(404).json({
    data: null,
    error: {
      code: "NOT_FOUND",
      message: `${req.method} ${req.path} 경로가 없습니다.`,
    },
  });
};
