// 삽 (서버 권위): 조개 숨구멍(바닷가 모래밭·호숫가)과 땅 고치기(구덩이·메우기·흙길).
// 숨구멍은 hp 번 파야 나온다 — 다른 사람이 coop_window 안에 같이 파면 한 번에 두 번 판 셈이고, 다 파면 판 사람 모두 하나씩 받는다.
import { islandShape } from './world.js';
import { insideOutline, signedDistance } from './outline.js';

export const TileKind = Object.freeze({ hole: 'hole', path: 'path' });

export const tileKey = (x, z) => `${x},${z}`;
export const snapTile = (v) => Math.round(v);

/** 바닷가 모래밭의 빈 자리 하나 (섬 해안선 안쪽 1.5m ~ 모래사장 폭 −1m). */
export function beachSpot(island, random) {
  if (!island) return null;
  const p = island.power ?? 4;
  const beach = island.beach ?? 8;
  const a = random() * Math.PI * 2;
  const c = Math.abs(Math.cos(a));
  const s = Math.abs(Math.sin(a));
  const edge = island.half / (c ** p + s ** p) ** (1 / p);
  const inset = 1.5 + random() * Math.max(0.5, beach - 2.5);
  const r = edge - inset;
  return { x: Math.round(Math.cos(a) * r * 10) / 10, z: Math.round(Math.sin(a) * r * 10) / 10 };
}

/** 호숫가 모래(수역 둘레 shore 폭 안)의 자리 하나. */
export function lakeShoreSpot(spot, shore, random) {
  if (spot.outline) {
    // 윤곽 수역: 경계의 한 점에서 물 바깥쪽으로 off 만큼 나간 자리. 좁은 물줄기 건너편(물)에 떨어지면 다시 뽑는다.
    const o = spot.outline;
    let out = null;
    for (let tries = 0; tries < 30; tries++) {
      const i = Math.floor(random() * o.length);
      const [ax, az] = o[i];
      const [bx, bz] = o[(i + 1) % o.length];
      const t = random();
      const px = ax + (bx - ax) * t;
      const pz = az + (bz - az) * t;
      const len = Math.hypot(bx - ax, bz - az) || 1;
      let nx = -(bz - az) / len;
      let nz = (bx - ax) / len;
      const off = 0.5 + random() * Math.max(0.3, shore - 0.6);
      if (insideOutline(o, px + nx * 0.2, pz + nz * 0.2)) [nx, nz] = [-nx, -nz];
      out = { x: Math.round((px + nx * off) * 10) / 10, z: Math.round((pz + nz * off) * 10) / 10 };
      if (signedDistance(o, out.x, out.z) > 0.3) break;
    }
    return out;
  }
  const side = Math.floor(random() * 4);
  const off = 0.5 + random() * Math.max(0.3, shore - 0.6);
  const u = random() * 2 - 1;
  let x = spot.x;
  let z = spot.z;
  if (side === 0) [x, z] = [spot.x + u * spot.half_x, spot.z - spot.half_z - off];
  else if (side === 1) [x, z] = [spot.x + u * spot.half_x, spot.z + spot.half_z + off];
  else if (side === 2) [x, z] = [spot.x - spot.half_x - off, spot.z + u * spot.half_z];
  else [x, z] = [spot.x + spot.half_x + off, spot.z + u * spot.half_z];
  return { x: Math.round(x * 10) / 10, z: Math.round(z * 10) / 10 };
}

/** 모래사장 안인지 (구덩이·흙길은 풀밭에만). */
export function onBeach(island, x, z) {
  if (!island) return false;
  const coast = (islandShape(island, x, z) - 1) * island.half;
  return coast > -(island.beach ?? 8);
}

/**
 * 숨구멍을 한 번 판다. spot = { id, kind, x, z, hp, hits: [{by, at}] }.
 * 돌려주는 값: { done, coop } — coop 이면 다른 사람과 같이 판 것 (한 번에 두 칸).
 */
export function hitSpot(spot, by, t, coopWindowMs) {
  const partner = spot.hits.some((h) => h.by !== by && t - h.at <= coopWindowMs);
  spot.hits.push({ by, at: t });
  if (spot.hits.length > 12) spot.hits.shift();
  spot.hp -= partner ? 2 : 1;
  return { done: spot.hp <= 0, coop: partner };
}

/** 이 숨구멍을 판 사람들 (자리 번호, 중복 없이). */
export function diggers(spot) {
  return [...new Set(spot.hits.map((h) => h.by))];
}

/** 저장 파일의 땅 칸 [[x, z, kind]] → Map. */
export function sanitizeTiles(raw, max) {
  const out = new Map();
  if (!Array.isArray(raw)) return out;
  for (const t of raw.slice(0, max)) {
    if (!Array.isArray(t) || !Number.isInteger(t[0]) || !Number.isInteger(t[1]) || !Object.values(TileKind).includes(t[2])) continue;
    out.set(tileKey(t[0], t[1]), { x: t[0], z: t[1], s: t[2] });
  }
  return out;
}

export function digSpotWire(d) {
  return { id: d.id, kind: d.kind, x: d.x, z: d.z, hp: d.hp };
}
