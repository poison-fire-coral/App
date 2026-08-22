import { Prisma, PrismaClient } from "@prisma/client";
import { prisma } from "../utils/prisma";
import { CustomError } from "../utils/CustomError";

/**
 * 배지 규칙 (`Badge.ruleJson`).
 *
 * 규칙은 **DB에 데이터로** 산다 — 의뢰서 S4 BE 2 "코드에 하드코딩 금지".
 * 여기 있는 건 그 JSON을 읽는 해석기이지 규칙 자체가 아니다.
 * 배지를 추가·수정할 때 이 파일은 건드리지 않는다(새 `type`을 만들 때만 예외).
 */
export type BadgeRule =
  /** 유형·지역 무관, 완료한 퀘스트 전체 */
  | { type: "TOTAL" }
  /** 특정 지역에서 완료한 수 */
  | { type: "REGION"; value: string }
  /** 서로 다른 지역의 가짓수 */
  | { type: "REGION_COUNT" }
  /** 특정 퀘스트 유형을 완료한 수 */
  | { type: "QUEST_TYPE"; value: string };

/** 완료 기록 한 건에서 규칙 판정에 필요한 부분만 뽑은 것. */
interface CompletionFact {
  questType: string;
  regionCode: string | null;
}

export interface BadgeProgressDto {
  badgeId: number;
  name: string;
  description: string;
  /** 앱이 그릴 SVG를 고르는 열쇠. 서버는 파일 경로를 모른다. */
  artKey: string | null;
  progress: number;
  threshold: number;
  achieved: boolean;
  /** 이번 인증으로 막 달성했는지. 4c 보상 화면의 "배지 획득!" 연출에 쓴다. */
  justEarned: boolean;
  hidden: boolean;
}

/**
 * 완료 기록 목록에 규칙을 적용해 현재 카운트를 낸다.
 *
 * **증분 카운터를 따로 두지 않는다.** 완료 기록이 이미 진실의 원천이라,
 * 매번 다시 세면 중복 적립도 유실도 구조적으로 생길 수 없다.
 * 퀘스트 수가 수천 건이 되기 전까지는 이 편이 안전하고 단순하다.
 */
export function countForRule(rule: BadgeRule, facts: CompletionFact[]): number {
  switch (rule.type) {
    case "TOTAL":
      return facts.length;

    case "REGION":
      return facts.filter((f) => f.regionCode === rule.value).length;

    case "REGION_COUNT": {
      const regions = new Set(
        facts.map((f) => f.regionCode).filter((r): r is string => !!r)
      );
      return regions.size;
    }

    case "QUEST_TYPE":
      return facts.filter((f) => f.questType === rule.value).length;

    default:
      // 알 수 없는 규칙은 0으로 둔다. 배지 하나 때문에 인증 전체가 실패하면 안 된다.
      return 0;
  }
}

function parseRule(raw: Prisma.JsonValue | null): BadgeRule | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const obj = raw as Record<string, unknown>;
  const type = obj.type;
  if (typeof type !== "string") return null;

  if (type === "TOTAL" || type === "REGION_COUNT") {
    return { type } as BadgeRule;
  }
  if (type === "REGION" || type === "QUEST_TYPE") {
    return typeof obj.value === "string"
      ? ({ type, value: obj.value } as BadgeRule)
      : null;
  }
  return null;
}

type Tx = PrismaClient | Prisma.TransactionClient;

/**
 * 퀘스트 완료 직후 배지를 다시 계산해 저장한다.
 *
 * **반드시 `verifyQuest`와 같은 트랜잭션 안에서 부른다.** 따로 부르면
 * "EXP는 들어갔는데 배지는 안 오른" 상태가 생길 수 있다.
 *
 * 멱등성도 여기서 저절로 확보된다 — 완료 기록을 다시 세는 방식이라
 * 같은 requestId로 재요청해도(= 완료 기록이 안 늘어도) 카운트가 그대로다.
 */
export async function recalculateBadges(
  tx: Tx,
  userId: number
): Promise<BadgeProgressDto[]> {
  const [badges, completions, existing] = await Promise.all([
    tx.badge.findMany({ orderBy: { id: "asc" } }),
    tx.questCompletion.findMany({
      where: { userId, isAbused: false },
      select: { quest: { select: { questType: true, place: { select: { regionCode: true } } } } },
    }),
    tx.userBadge.findMany({ where: { userId } }),
  ]);

  const facts: CompletionFact[] = completions.map((c) => ({
    questType: String(c.quest.questType),
    regionCode: c.quest.place?.regionCode ?? null,
  }));

  const previous = new Map(existing.map((ub) => [ub.badgeId, ub]));
  const result: BadgeProgressDto[] = [];
  const now = new Date();

  for (const badge of badges) {
    const rule = parseRule(badge.ruleJson);
    if (!rule) continue;

    const raw = countForRule(rule, facts);
    // 목표를 넘겨도 표시는 목표치에서 멈춘다. "5 / 3"은 이상하다.
    const progress = Math.min(raw, badge.threshold);
    const achieved = raw >= badge.threshold;

    const before = previous.get(badge.id);
    const wasAchieved = !!before?.achievedAt;
    const justEarned = achieved && !wasAchieved;

    // 진행도가 그대로면 굳이 쓰지 않는다.
    if (!before || before.progress !== progress || justEarned) {
      await tx.userBadge.upsert({
        where: { userId_badgeId: { userId, badgeId: badge.id } },
        create: {
          userId,
          badgeId: badge.id,
          progress,
          achievedAt: achieved ? now : null,
        },
        update: {
          progress,
          // 한 번 딴 배지는 회수하지 않는다.
          achievedAt: before?.achievedAt ?? (achieved ? now : null),
        },
      });
    }

    result.push({
      badgeId: badge.id,
      name: badge.name,
      description: badge.description,
      artKey: badge.artUrl,
      progress,
      threshold: badge.threshold,
      achieved,
      justEarned,
      hidden: badge.hidden,
    });
  }

  return result;
}

/** 목록 API가 쓰는 3상태. */
export type BadgeState = "achieved" | "inProgress" | "locked";

/**
 * 내 배지 전체를 3상태로 정리해 돌려준다.
 *
 * 히든 배지는 아직 못 땄으면 **이름과 설명을 가린다.** 서버가 그대로 내려보내면
 * 앱을 뜯어 미리 볼 수 있어서, 가리는 일은 클라이언트가 아니라 여기서 해야 한다.
 */
export async function listBadges(
  userId: number,
  filter?: { region?: string; questType?: string }
) {
  const [badges, mine] = await Promise.all([
    prisma.badge.findMany({ orderBy: { id: "asc" } }),
    prisma.userBadge.findMany({ where: { userId } }),
  ]);

  const byBadgeId = new Map(mine.map((ub) => [ub.badgeId, ub]));

  const items = badges
    .filter((badge) => {
      if (!filter?.region && !filter?.questType) return true;
      const rule = parseRule(badge.ruleJson);
      if (!rule) return false;
      if (filter.region) {
        return rule.type === "REGION" && rule.value === filter.region;
      }
      return rule.type === "QUEST_TYPE" && rule.value === filter.questType;
    })
    .map((badge) => {
      const ub = byBadgeId.get(badge.id);
      const progress = ub?.progress ?? 0;
      const achieved = !!ub?.achievedAt;
      const state: BadgeState = achieved
        ? "achieved"
        : progress > 0
          ? "inProgress"
          : "locked";

      const conceal = badge.hidden && !achieved;

      return {
        badgeId: badge.id,
        name: conceal ? null : badge.name,
        description: conceal ? null : badge.description,
        artKey: conceal ? null : badge.artUrl,
        progress: conceal ? 0 : progress,
        threshold: conceal ? 0 : badge.threshold,
        state,
        hidden: badge.hidden,
        regionCode: badge.regionCode,
        achievedAt: ub?.achievedAt ?? null,
        isFeatured: ub?.isFeatured ?? false,
        featuredOrder: ub?.featuredOrder ?? null,
      };
    });

  return {
    total: badges.length,
    achieved: items.filter((i) => i.state === "achieved").length,
    items,
  };
}

/** 배지 상세 — 어떤 퀘스트로 채웠는지 이력을 함께 준다. */
export async function getBadgeDetail(userId: number, badgeId: number) {
  const badge = await prisma.badge.findUnique({ where: { id: badgeId } });
  if (!badge) {
    throw new CustomError(404, "BADGE_NOT_FOUND", "존재하지 않는 배지입니다.");
  }

  const ub = await prisma.userBadge.findUnique({
    where: { userId_badgeId: { userId, badgeId } },
  });
  const achieved = !!ub?.achievedAt;

  if (badge.hidden && !achieved) {
    throw new CustomError(403, "BADGE_HIDDEN", "아직 공개되지 않은 배지입니다.");
  }

  const rule = parseRule(badge.ruleJson);

  // 이 배지에 기여한 완료 기록만 골라 이력으로 보여준다.
  const completions = await prisma.questCompletion.findMany({
    where: { userId, isAbused: false },
    orderBy: { createdAt: "desc" },
    select: {
      createdAt: true,
      quest: {
        select: {
          title: true,
          questType: true,
          place: { select: { name: true, regionCode: true } },
        },
      },
    },
  });

  const contributed = completions.filter((c) => {
    if (!rule) return false;
    if (rule.type === "TOTAL" || rule.type === "REGION_COUNT") return true;
    if (rule.type === "REGION") return c.quest.place?.regionCode === rule.value;
    return String(c.quest.questType) === rule.value;
  });

  return {
    badgeId: badge.id,
    name: badge.name,
    description: badge.description,
    artKey: badge.artUrl,
    threshold: badge.threshold,
    progress: ub?.progress ?? 0,
    achieved,
    achievedAt: ub?.achievedAt ?? null,
    isFeatured: ub?.isFeatured ?? false,
    history: contributed.slice(0, badge.threshold).map((c) => ({
      date: c.createdAt,
      questTitle: c.quest.title,
      placeName: c.quest.place?.name ?? null,
      regionCode: c.quest.place?.regionCode ?? null,
    })),
  };
}

/** 대표 배지 상한. DB에 제약이 없으므로 여기서 강제한다. */
export const MAX_FEATURED = 3;

export async function setFeaturedBadges(userId: number, badgeIds: number[]) {
  if (badgeIds.length > MAX_FEATURED) {
    throw new CustomError(
      400,
      "TOO_MANY_FEATURED",
      `대표 배지는 최대 ${MAX_FEATURED}개까지 지정할 수 있습니다.`
    );
  }

  const unique = [...new Set(badgeIds)];
  if (unique.length !== badgeIds.length) {
    throw new CustomError(400, "BAD_REQUEST", "같은 배지를 중복 지정할 수 없습니다.");
  }

  if (unique.length > 0) {
    // 획득하지 않은 배지를 대표로 세울 수 없다.
    const owned = await prisma.userBadge.findMany({
      where: { userId, badgeId: { in: unique }, achievedAt: { not: null } },
      select: { badgeId: true },
    });
    if (owned.length !== unique.length) {
      throw new CustomError(
        400,
        "BADGE_NOT_ACHIEVED",
        "아직 획득하지 않은 배지는 대표로 지정할 수 없습니다."
      );
    }
  }

  await prisma.$transaction(async (tx) => {
    await tx.userBadge.updateMany({
      where: { userId },
      data: { isFeatured: false, featuredOrder: null },
    });
    for (let i = 0; i < unique.length; i++) {
      await tx.userBadge.update({
        where: { userId_badgeId: { userId, badgeId: unique[i] } },
        data: { isFeatured: true, featuredOrder: i },
      });
    }
  });

  return listFeatured(userId);
}

/** 홈 화면 3칸에 쓰는 대표 배지. */
export async function listFeatured(userId: number) {
  const rows = await prisma.userBadge.findMany({
    where: { userId, isFeatured: true },
    orderBy: { featuredOrder: "asc" },
    include: { badge: true },
  });

  return rows.map((r) => ({
    badgeId: r.badgeId,
    name: r.badge.name,
    artKey: r.badge.artUrl,
    achievedAt: r.achievedAt,
    featuredOrder: r.featuredOrder,
  }));
}
