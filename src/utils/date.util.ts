/**
 * KST(UTC+9) 기준 날짜 문자열(YYYY-MM-DD) 추출
 */
export function getKSTDateString(date: Date = new Date()): string {
  const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  return kst.toISOString().split("T")[0];
}

/**
 * KST 기준 비피크 시간대 판정 (평일 오전 06:00 ~ 11:59)
 */
export function isOffPeakKST(now: Date = new Date()): boolean {
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const day = kst.getUTCDay(); // 0: 일, 1: 월 ... 5: 금, 6: 토
  const hour = kst.getUTCHours();

  const isWeekday = day >= 1 && day <= 5;
  const isMorning = hour >= 6 && hour < 12;

  return isWeekday && isMorning;
}

/**
 * KST 기준 연속 수행일(streakDays) 계산
 */
export function calculateStreak(
  lastEarnedAt: Date | null,
  currentStreak: number,
  now: Date = new Date()
): number {
  if (!lastEarnedAt) return 1;

  const todayStr = getKSTDateString(now);
  const lastStr = getKSTDateString(lastEarnedAt);

  // 당일 재수행: 기존 스트릭 유지 (최소 1)
  if (todayStr === lastStr) {
    return currentStreak === 0 ? 1 : currentStreak;
  }

  // 일자 차이 계산
  const todayDate = new Date(todayStr);
  const lastDate = new Date(lastStr);
  const diffTime = todayDate.getTime() - lastDate.getTime();
  const diffDays = Math.round(diffTime / (1000 * 3600 * 24));

  // 어제 수행 후 오늘 수행: +1
  if (diffDays === 1) {
    return currentStreak + 1;
  }

  // 2일 이상 단절: 1로 리셋
  return 1;
}