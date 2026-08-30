export interface ExpFactors {
  baseExp: number;
  halfStep: boolean; // 반개(★½) 여부 (x1.15)
  congestionScore: number; // 1: 하위30%(x1.4), 2: 보통(x1.0), 3: 상위10%(x0.7)
  isNewArea: boolean; // 처음 방문한 시·군 (x1.5)
  isOffPeak: boolean; // 평일 오전 비피크 (x1.2)
  streakDays: number; // 연속 접속 스트릭 (일당 +5%, 상한 x1.5)
  isAbused: boolean; // 속도 초과 어뷰징 여부
  isRepeat?: boolean; // 💡 16번: 24h 경과 후 재수행 여부 (x0.3)
}

// 1. EXP 배율 산출 및 상한 제한 계산
export function calculateRewardExp(factors: ExpFactors, dailyExpEarned: number) {
  if (factors.isAbused) {
    return { finalExp: 0, breakdown: { abusePenalty: true } };
  }

  const mHalf = factors.halfStep ? 1.15 : 1.0;
  const mCong = factors.congestionScore === 1 ? 1.4 : factors.congestionScore === 3 ? 0.7 : 1.0;
  const mArea = factors.isNewArea ? 1.5 : 1.0;
  const mTime = factors.isOffPeak ? 1.2 : 1.0;
  const mStreak = Math.min(1.0 + factors.streakDays * 0.05, 1.5);
  const mRepeat = factors.isRepeat ? 0.3 : 1.0; // 💡 16번: 재수행 시 0.3배 적용

  // 공식 적용 후 소수점 버림(floor)
  const calculatedExp = Math.floor(
    factors.baseExp * mHalf * mCong * mArea * mTime * mStreak * mRepeat
  );

  // 단일 퀘스트 상한 1,600 EXP
  const singleCappedExp = Math.min(calculatedExp, 1600);

  // 1일 획득 상한 3,000 EXP (이월 없음)
  const DAILY_MAX_EXP = 3000;
  const availableDailyExp = Math.max(0, DAILY_MAX_EXP - dailyExpEarned);
  const finalExp = Math.min(singleCappedExp, availableDailyExp);

  return {
    finalExp,
    breakdown: {
      baseExp: factors.baseExp,
      mHalf,
      mCong,
      mArea,
      mTime,
      mStreak,
      mRepeat, // 💡 breakdown 결과에 포함
      calculatedExp,
      singleCappedExp,
      finalExp,
    },
  };
}

// 2. 레벨업 및 초과 EXP 이월 계산
export function processLevelUp(
  currentLevel: number,
  currentExp: number,
  gainedExp: number,
  levelTable: { level: number; requiredExp: number }[]
) {
  let level = currentLevel;
  let exp = currentExp + gainedExp;
  let isLevelUp = false;

  while (true) {
    const nextLevelReq = levelTable.find((l) => l.level === level + 1);
    if (!nextLevelReq) break; // 최대 레벨 도달 시 종료

    if (exp >= nextLevelReq.requiredExp) {
      exp -= nextLevelReq.requiredExp;
      level += 1;
      isLevelUp = true;
    } else {
      break;
    }
  }

  return { isLevelUp, level, expCurrent: exp };
}