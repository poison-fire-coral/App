export function calculateHaversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371e3; // 지구 반지름 (m)
  const rad = Math.PI / 180;
  const dLat = (lat2 - lat1) * rad;
  const dLon = (lon2 - lon1) * rad;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // 미터 단위 반환
}

export function checkSpeedAbuse(
  prevLat: number, prevLon: number, prevTime: Date,
  currLat: number, currLon: number, currTime: Date
): boolean {
  const distanceInMeters = calculateHaversineDistance(prevLat, prevLon, currLat, currLon);
  const timeInSeconds = (currTime.getTime() - prevTime.getTime()) / 1000;

  if (timeInSeconds <= 0) return true; // 시간 왜곡 예외

  const speedKmH = (distanceInMeters / 1000) / (timeInSeconds / 3600);
  return speedKmH > 40.0; // 40km/h 초과 시 어뷰징 판정
}