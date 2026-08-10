// src/jobs/congestion.job.ts
import cron from "node-cron";
import { prisma } from "../utils/prisma";

export const startCongestionBatchJob = () => {
  // 10분마다 실행
  cron.schedule("*/10 * * * *", async () => {
    const places = await prisma.place.findMany();
    const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);

    for (const place of places) {
      const recentCompletions = await prisma.userQuest.count({
        where: {
          quest: { placeId: place.id },
          status: "done",
          completedAt: { gte: twoHoursAgo },
        },
      });

      const updatedScore = Math.min(100, Math.max(1, Math.round(recentCompletions * 10 + 1)));

      await prisma.place.update({
        where: { id: place.id },
        data: { congestionScore: updatedScore },
      });
    }
  });
};