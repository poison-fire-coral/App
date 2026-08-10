import { prisma } from "../utils/prisma";
import { AppError } from "../utils/CustomError";

interface UpdateProfileDTO {
  userId: number;
  nickname?: string;
  avatarId?: string;
  homeRegion?: string;
  activityLevel?: string;
  keywords?: string[];
}

export class UserService {
  // 닉네임 중복 확인 단독 API
  static async checkNickname(nickname: string) {
    if (!nickname || nickname.trim().length === 0) {
      throw new AppError("BAD_REQUEST", "닉네임을 입력해 주세요.");
    }

    const user = await prisma.user.findUnique({
      where: { nickname },
    });

    return { isAvailable: !user };
  }

  static async updateProfile(dto: UpdateProfileDTO) {
    const { userId, nickname, avatarId, homeRegion, activityLevel, keywords } = dto;

    if (nickname) {
      const existingUser = await prisma.user.findFirst({
        where: {
          nickname,
          NOT: { id: userId },
        },
      });

      if (existingUser) {
        throw new AppError("DUPLICATE_NICKNAME", "이미 사용 중인 닉네임입니다.");
      }
    }

    if (keywords && keywords.length > 0) {
      await prisma.userKeyword.deleteMany({
        where: { userId },
      });

      await prisma.userKeyword.createMany({
        data: keywords.map((keywordId) => ({
          userId,
          keywordId,
        })),
      });
    }

    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: {
        ...(nickname && { nickname }),
        ...(avatarId !== undefined && { avatarId }),
        ...(homeRegion !== undefined && { homeRegion }),
        ...(activityLevel !== undefined && { activityLevel }),
      },
      include: {
        keywords: true,
      },
    });

    return updatedUser;
  }

  static async getMyProfile(userId: number) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        keywords: true,
      },
    });

    if (!user) {
      throw new AppError("NOT_FOUND", "사용자를 찾을 수 없습니다.");
    }

    return user;
  }
}
