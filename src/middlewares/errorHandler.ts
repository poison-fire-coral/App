import { Request, Response, NextFunction } from "express";

export const errorHandler = (
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  console.error("❌ [Error Caught]:", err);

  // instanceof 사용 대신 안전한 속성 기반(Duck Typing) 검사
  const statusCode = err?.statusCode || (typeof err?.status === "number" ? err.status : null);
  const errorCode = err?.errorCode || err?.code || "BAD_REQUEST";
  const message = err?.message || "요청 처리 중 오류가 발생했습니다.";

  // statusCode나 errorCode가 존재하는 예외 객체 처리
  if (statusCode || err?.errorCode || err?.name === "CustomError") {
    return res.status(statusCode || 400).json({
      data: null,
      error: {
        code: errorCode,
        message,
        ...(err?.details && { details: err.details }),
      },
    });
  }

  // 예측하지 못한 500 에러 처리
  return res.status(500).json({
    data: null,
    error: {
      code: "INTERNAL_SERVER_ERROR",
      message: err?.message || "서버 내부 오류가 발생했습니다.",
    },
  });
};
