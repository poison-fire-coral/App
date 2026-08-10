import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";

export class QuestService {
  static async acceptQuest(userId: number, questId: number) {
    // 1. 퀘스트 존재 여부 확인
    const quest = await prisma.quest.findUnique({
      where: { id: questId },
    });

    if (!quest) {
      throw new CustomError(404, "QUEST_NOT_FOUND", "존재하지 않는 퀘스트입니다.");
    }

    // 2. 이미 수락/완료한 퀘스트인지 확인
    const existingUserQuest = await prisma.userQuest.findFirst({
      where: {
        userId,
        questId,
      },
    });

    if (existingUserQuest) {
      throw new CustomError(409, "QUEST_ALREADY_DONE", "이미 수락했거나 완료한 퀘스트입니다.");
    }

    // 3. UserQuest 생성 (진행 중 상태)
    const userQuest = await prisma.userQuest.create({
      data: {
        userId,
        questId,
        status: "IN_PROGRESS",
      },
    });

    return userQuest;
  }
}
