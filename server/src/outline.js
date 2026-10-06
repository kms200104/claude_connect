// 호수 윤곽(다각형) 계산: 안팎 판정, 부호 있는 거리(안쪽 음수), 가장 가까운 경계점.
// 클라이언트 core/types/spot_info.gd 와 같은 식을 써야 한다.

/** 점이 다각형 안인지 (짝홀 규칙). outline: [[x, z], ...] */
export function insideOutline(outline, x, z) {
  let inside = false;
  for (let i = 0, j = outline.length - 1; i < outline.length; j = i++) {
    const [ax, az] = outline[j];
    const [bx, bz] = outline[i];
    if ((az > z) !== (bz > z) && x < ((bx - ax) * (z - az)) / (bz - az) + ax) inside = !inside;
  }
  return inside;
}

/** 가장 가까운 경계점과 거리. */
export function nearestOnBoundary(outline, x, z) {
  let best = { x: outline[0][0], z: outline[0][1], d: Infinity };
  for (let i = 0, j = outline.length - 1; i < outline.length; j = i++) {
    const [ax, az] = outline[j];
    const [bx, bz] = outline[i];
    const dx = bx - ax;
    const dz = bz - az;
    const len2 = dx * dx + dz * dz;
    const t = len2 > 1e-9 ? Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / len2)) : 0;
    const px = ax + t * dx;
    const pz = az + t * dz;
    const d = Math.hypot(x - px, z - pz);
    if (d < best.d) best = { x: px, z: pz, d };
  }
  return best;
}

/** 부호 있는 거리: 안쪽이면 음수 (경계까지), 바깥이면 양수. */
export function signedDistance(outline, x, z) {
  const d = nearestOnBoundary(outline, x, z).d;
  return insideOutline(outline, x, z) ? -d : d;
}
