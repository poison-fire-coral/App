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
/**
 * KST 기준으로 지금이 시간대 창 안인지 — 05 시간대 제한형 검증.
 *
 * 값은 시드가 쓰는 두 형식을 받는다:
 *   "04:00"        절대 시각
 *   "SUNSET-40"    일몰 기준 상대 (아직 일몰 계산이 없어 **판정을 건너뛴다**)
 *
 * 상대 표기를 만나면 `true`를 돌려준다. 계산하지 못하는 조건 때문에 인증을
 * 막으면, 유저는 이유를 알 수 없는 채로 문 앞에서 되돌아가게 된다.
 * 일몰 계산이 들어오면 여기만 고치면 된다.
 */
export function isWithinTimeWindowKST(
  start: string,
  end: string,
  now: Date = new Date()
): boolean {
  const toMinutes = (v: string): number | null => {
    const m = /^(\d{1,2}):(\d{2})$/.exec(v.trim());
    if (!m) return null;
    return Number(m[1]) * 60 + Number(m[2]);
  };

  const s = toMinutes(start);
  const e = toMinutes(end);
  if (s === null || e === null) return true;

  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const cur = kst.getUTCHours() * 60 + kst.getUTCMinutes();

  // 자정을 넘는 창(예: 22:00~02:00)도 다룬다.
  return s <= e ? cur >= s && cur <= e : cur >= s || cur <= e;
}
