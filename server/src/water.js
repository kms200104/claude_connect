// 보트가 다니는 물 · 내릴 땅 (v20). 클라이언트 core/rules/water_rules.gd 와 같은 규칙 · 같은 값.
//   호수: 윤곽(또는 사각형) 안쪽 LAKE_MARGIN m 부터. 바다: 섬 모양 값 SEA_MIN ~ SEA_MAX (그 너머 바다 건너에는 실내가 있다).
//   내릴 땅: 호수 윤곽 바깥 LAND_LAKE m, 바닷가는 해안선 안쪽 LAND_COAST m — 그리고 섬 안.
import { signedDistance } from './outline.js';
import { islandShape, onIsland } from './world.js';

export const WATER = { LAKE_MARGIN: 1.0, SEA_MIN: 1.05, SEA_MAX: 1.3, LAND_LAKE: 0.8, LAND_COAST: 1.5 };

function lakeDistance(spot, x, z) {
  if (spot.outline) {
    const dx = Math.abs(x - spot.x) - spot.half_x;
    const dz = Math.abs(z - spot.z) - spot.half_z;
    if (Math.max(dx, dz) > 8) return Math.hypot(Math.max(dx, 0), Math.max(dz, 0));
    return signedDistance(spot.outline, x, z);
  }
  const dx = Math.abs(x - spot.x) - spot.half_x;
  const dz = Math.abs(z - spot.z) - spot.half_z;
  return Math.hypot(Math.max(dx, 0), Math.max(dz, 0)) + Math.min(Math.max(dx, dz), 0);
}

/** 이 자리의 보트 물 (낚시터 id, 물이 아니면 ''). slack = 서버가 봐주는 여유 (m, 클라이언트와 어긋나는 몇 cm). */
export function waterAt(data, x, z, slack = 0) {
  for (const spot of data.spots.values()) {
    if (Math.abs(x - spot.x) > spot.half_x || Math.abs(z - spot.z) > spot.half_z) continue;
    if (lakeDistance(spot, x, z) <= -WATER.LAKE_MARGIN + slack) return spot.id;
  }
  const sea = data.seaSpot;
  if (sea?.island) {
    const s = islandShape(sea.island, x, z);
    const k = slack / sea.island.half;
    if (s >= WATER.SEA_MIN - k && s <= WATER.SEA_MAX + k) return sea.id;
  }
  return '';
}

/** 걸어 내릴 수 있는 땅인지. */
export function isLand(data, x, z, slack = 0) {
  for (const spot of data.spots.values()) if (lakeDistance(spot, x, z) < WATER.LAND_LAKE - slack) return false;
  // v0.21: 도시 땅 밖(강 건너 · 도시 끝)에는 내리지 않는다.
  if (data.layout?.island && !onIsland(data.layout.island, x, z, WATER.LAND_COAST - slack)) return false;
  const island = data.seaSpot?.island;
  if (!island) return true;
  return (islandShape(island, x, z) - 1) * island.half <= -WATER.LAND_COAST + slack;
}
