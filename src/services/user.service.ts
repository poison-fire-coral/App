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
      where: { nickname: nickname.trim() },
    });

    return { isAvailable: !user };
  }

  // 내 프로필 조회
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

  // 프로필 업데이트
  static async updateProfile(dto: UpdateProfileDTO) {
    const { userId, nickname, avatarId, homeRegion, activityLevel, keywords } = dto;

    // 1. 닉네임 변경 시 본인 제외 중복 체크
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

    // 2. 키워드가 배열 형태로 전달된 경우 삭제 후 재등록 (빈 배열 입력 시 전체 삭제)
    if (keywords !== undefined && Array.isArray(keywords)) {
      await prisma.userKeyword.deleteMany({
        where: { userId },
      });

      if (keywords.length > 0) {
        await prisma.userKeyword.createMany({
          data: keywords.map((keywordId) => ({
            userId,
            keywordId,
          })),
        });
      }
    }

    // 3. 프로필 기본 정보 업데이트
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

  /**
   * 프로필 화면(5c) 요약 — 통계 + 최근 발자국.
   *
   * 앱이 그동안 `completedQuestIds`·`visitedRegions`를 SharedPreferences에만
   * 들고 있었는데, 그건 기기를 바꾸면 사라진다. 진실은 `quest_completions`에 있다.
   */
  static async getProfileSummary(userId: number, footprintLimit = 20) {
    const [completions, badgeCount] = await Promise.all([
      prisma.questCompletion.findMany({
        where: { userId, isAbused: false },
        orderBy: { createdAt: "desc" },
        select: {
          createdAt: true,
          expAwarded: true,
          quest: {
            select: {
              title: true,
              questType: true,
              difficulty: true,
              place: { select: { name: true, regionCode: true } },
            },
          },
        },
      }),
      prisma.userBadge.count({ where: { userId, achievedAt: { not: null } } }),
    ]);

    const regions = new Set(
      completions
        .map((c) => c.quest.place?.regionCode)
        .filter((r): r is string => !!r)
    );

    return {
      stats: {
        completed: completions.length,
        regions: regions.size,
        badges: badgeCount,
      },
      footprints: completions.slice(0, footprintLimit).map((c) => ({
        date: c.createdAt,
        questTitle: c.quest.title,
        questType: String(c.quest.questType),
        difficulty: c.quest.difficulty,
        placeName: c.quest.place?.name ?? null,
        regionCode: c.quest.place?.regionCode ?? null,
        expAwarded: c.expAwarded,
      })),
    };
  }

  // 💡 회원 탈퇴 (Prisma Cascade에 의해 연관 데이터 자동 삭제)
  static async deleteAccount(userId: number) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new AppError("NOT_FOUND", "사용자를 찾을 수 없습니다.");
    }

    await prisma.user.delete({
      where: { id: userId },
    });
  }
}