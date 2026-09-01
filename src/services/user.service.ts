import { prisma } from "../utils/prisma";
import { AppError } from "../utils/CustomError";

/**
 * `/users` 라우트가 쓰는 서비스.
 *
 * **주의 — 이 파일은 한 번 통째로 날아간 적이 있다.** 커밋 a411a9a에서
 * `quest.service.ts`의 내용이 여기 덮어써지면서 `UserService`가 사라졌고,
 * 컨트롤러가 부르는 대상이 `undefined`가 되어 프로필·탈퇴가 전부 500이 됐다.
 * `tsx`는 타입을 보지 않아 서버가 멀쩡히 뜨는 바람에 아무도 눈치채지 못했다.
 * CI의 `npm run typecheck`(체크리스트 27번)가 이제 이런 걸 잡는다.
 */

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

  /**
   * 회원 탈퇴 — 체크리스트 06번, 스토어 심사 요건.
   *
   * **자식 레코드를 손으로 지우지 않는다.** `UserKeyword`·`UserQuest`·
   * `QuestCompletion`·`UserBadge` 네 관계가 스키마에서 모두
   * `onDelete: Cascade`라 사용자 한 줄을 지우면 DB가 함께 정리한다.
   * 여기서 또 지우면 순서를 잘못 잡았을 때 외래키로 막히기만 하고
   * 얻는 게 없다.
   *
   * **되돌릴 수 없다.** 유예 기간을 두는 편이 친절하지만 그러려면
   * `deletedAt` 컬럼과 그걸 걸러 주는 모든 쿼리의 수정이 필요하다.
   * 앱이 "즉시 삭제되며 복구할 수 없습니다"라고 고지하고 있으므로
   * 지금은 고지대로 동작하는 쪽을 택한다.
   */
  static async deleteAccount(userId: number) {
    try {
      await prisma.user.delete({ where: { id: userId } });
    } catch (error: any) {
      // P2025 = 지울 레코드가 없다. 이미 지운 계정의 토큰으로 다시 부른
      // 경우라 실패로 볼 이유가 없다 — 원하는 상태(계정 없음)는 같다.
      if (error?.code === "P2025") return;
      throw error;
    }
  }
}