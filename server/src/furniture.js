// 마을에 설치한 가구(서버 권위). 위치는 0.5m 격자, 방향은 90° 단위. 마을 공용으로 보이고, 놓은 사람만 다시 주울 수 있다.
// placed: Map<id, { id, item, x, z, rot, owner(uid) }>
import { distanceToSpot } from './gamedata.js';
import { inInterior } from './shop.js';

export const PLACE_RANGE = 3.0; // 내 위치에서 이 거리 안에만 놓을 수 있다
export const PICKUP_RANGE = 2.5;
const CLEARANCE = 1.0; // 다른 가구·나무 중심과 떨어져야 하는 거리
const SHOP_CLEARANCE = 5.5; // 상점 건물 앞·안 (문 막지 않게)

export const snap = (v) => Math.round(v * 2) / 2;

/** 놓을 수 있으면 null, 아니면 이유 문자열 (서버 로그·테스트용). */
export function placementProblem({ x, z, player, placed, data, cfg }) {
  if (![x, z].every((v) => typeof v === 'number' && Number.isFinite(v))) return 'bad';
  if (Math.hypot(x - player.x, z - player.z) > PLACE_RANGE) return 'far';
  if (Math.abs(x) > cfg.worldHalfExtent - 1 || Math.abs(z) > cfg.worldHalfExtent - 1) return 'edge';
  for (const spot of data.spots.values()) if (distanceToSpot(spot, x, z) < 0.6) return 'water';
  for (const t of data.trees.values()) if (Math.hypot(x - t.x, z - t.z) < CLEARANCE) return 'tree';
  for (const f of placed.values()) if (Math.hypot(x - f.x, z - f.z) < CLEARANCE) return 'furniture';
  const door = data.shop.door;
  if (Math.hypot(x - door.x, z - (door.z - 3)) < SHOP_CLEARANCE || inInterior(data.shop, x, z)) return 'shop';
  return null;
}

export function sanitizePlaced(raw, data) {
  const out = new Map();
  if (!Array.isArray(raw)) return out;
  for (const f of raw) {
    if (!f || typeof f.id !== 'string' || data.kindOf(f.item) !== 'furniture' || typeof f.owner !== 'string') continue;
    if (![f.x, f.z].every(Number.isFinite)) continue;
    out.set(f.id, { id: f.id, item: f.item, x: f.x, z: f.z, rot: Number.isInteger(f.rot) ? ((f.rot % 4) + 4) % 4 : 0, owner: f.owner });
  }
  return out;
}

/** 전송용: 주인 uid 대신 주인 자리 번호. */
export function placedWire(f, slotOfUid) {
  return { id: f.id, item: f.item, x: f.x, z: f.z, rot: f.rot, owner: slotOfUid(f.owner) };
}
