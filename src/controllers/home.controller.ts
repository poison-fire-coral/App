import { Request, Response, NextFunction } from "express";
import { HomeService } from "../services/home.service";

export const getHomeData = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const userId = (req as any).user?.id || Number(req.query.userId);
    const summary = await HomeService.getHomeSummary(userId);
    
    return res.status(200).json({
      success: true,
      data: summary,
    });
  } catch (error) {
    next(error);
  }
};