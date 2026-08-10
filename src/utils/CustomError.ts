export class CustomError extends Error {
  statusCode: number;
  errorCode: string;
  details?: any;

  constructor(arg1: any, arg2?: any, arg3?: any, arg4?: any) {
    let code = 400;
    let errCode = "BAD_REQUEST";
    let msg = "";
    let detailsData: any = undefined;

    if (typeof arg1 === "number") {
      code = arg1;
      if (typeof arg2 === "string") {
        errCode = arg2;
        if (typeof arg3 === "string") {
          msg = arg3;
          detailsData = arg4;
        } else {
          msg = errCode;
          detailsData = arg3;
        }
      }
    } else if (typeof arg1 === "string") {
      if (typeof arg2 === "number") {
        errCode = arg1;
        code = arg2;
        msg = typeof arg3 === "string" ? arg3 : errCode;
        detailsData = arg4;
      } else if (typeof arg2 === "string") {
        errCode = arg1;
        msg = arg2;
        detailsData = arg3;
      } else {
        errCode = arg1;
        msg = arg1;
        detailsData = arg2;
      }
    }

    super(msg || errCode);
    this.name = "CustomError";
    this.statusCode = code;
    this.errorCode = errCode;
    this.details = detailsData;
    Object.setPrototypeOf(this, CustomError.prototype);
  }
}

export const AppError = CustomError;
export type AppError = CustomError;
