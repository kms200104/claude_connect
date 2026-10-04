// 마을 상점(서버 권위). 사고팔 때마다 거래한 솔만큼 상점 포인트가 쌓이고, 포인트가 문턱을 넘으면 상점이 커진다.
// 포인트·단계는 마을(방) 공용 — 두 사람이 함께 키운다. 상점 안은 마을 멀리 떨어진 실내 공간이고, 문으로 드나든다.

/** 포인트로 정해지는 상점 단계 정보 (levels 는 points 오름차순). */
export function levelFor(points, levels) {
  let current = levels[0];
  for (const lv of levels) if (points >= lv.points) current = lv;
  return current;
}

export function nextLevel(points, levels) {
  return levels.find((lv) => lv.points > points) ?? null;
}

/** 지금 단계까지 열린 물건 전부 (단계가 오르면 이전 물건도 계속 판다). */
export function stockFor(points, levels) {
  const level = levelFor(points, levels).level;
  return levels.filter((lv) => lv.level <= level).flatMap((lv) => lv.stock);
}

/** n개를 팔 때 받는 솔 (단계 보너스 포함, 내림). */
export function sellValue(basePrice, n, points, levels) {
  return Math.floor(basePrice * n * (1 + levelFor(points, levels).sell_bonus));
}

export function inInterior(shop, x, z) {
  const r = shop.interior;
  return Math.abs(x - r.x) <= r.half_x && Math.abs(z - r.z) <= r.half_z;
}

export function nearPoint(p, x, z, range) {
  return Math.hypot(x - p.x, z - p.z) <= range;
}

export function shopWire(points, levels) {
  const lv = levelFor(points, levels);
  const next = nextLevel(points, levels);
  return { level: lv.level, points, next: next ? next.points : null };
}
