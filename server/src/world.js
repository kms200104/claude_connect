// 섬 지형 판정 (서버는 물리 없이 영역·거리만 본다): 섬 경계, 물, 건물·집 자리.
// 가구 설치와 씨앗 심기가 같은 규칙을 쓴다.
import { distanceToSpot } from './gamedata.js';

/** 섬 모양 값: 1 이면 해안선, 작을수록 안쪽 (둥근 사각형, |x/h|^p + |z/h|^p). */
export function islandShape(island, x, z) {
  if (!island) return 0;
  const p = island.power ?? 4;
  return (Math.abs(x / island.half) ** p + Math.abs(z / island.half) ** p) ** (1 / p);
}

/** 섬 안쪽인지 (margin: 해안선에서 안쪽으로 떨어져야 하는 거리, 미터). */
export function onIsland(island, x, z, margin = 0) {
  if (!island) return true;
  return islandShape(island, x, z) <= 1 - margin / island.half;
}

/** 건물 바닥 사각형 (앞면 가운데 기준, 앞면이 +Z). 여유 pad 만큼 넓힌다. */
function buildingRect(b, pad) {
  return { x0: b.x - b.width / 2 - pad, x1: b.x + b.width / 2 + pad, z0: b.z - b.depth - pad, z1: b.z + pad };
}

/** 무엇이든 놓거나 심으면 안 되는 자리 목록 (사각형과 원). data 로 한 번 만든다. */
export function blockedAreas(data) {
  const rects = [];
  const circles = [];
  const shop = data.shop;
  // 상점은 단계마다 커지므로 가장 큰 건물 크기로 막는다.
  rects.push({ x0: shop.door.x - 5.2, x1: shop.door.x + 5.2, z0: shop.door.z - 7.5, z1: shop.door.z + 2.5 });
  if (data.museum) {
    rects.push(buildingRect(data.museum.building, 1.5));
    const a = data.museum.aquarium;
    rects.push({ x0: a.x - a.width / 2 - 0.8, x1: a.x + a.width / 2 + 0.8, z0: a.z - a.depth / 2 - 0.8, z1: a.z + a.depth / 2 + 0.8 });
    circles.push({ x: data.museum.curator.x, z: data.museum.curator.z, r: 1.6 });
  }
  if (data.airport) {
    rects.push(buildingRect(data.airport.building, 1.5));
    const w = data.airport.runway;
    rects.push({ x0: w.x0 - 2, x1: w.x1 + 2, z0: w.z - w.width / 2 - 1, z1: w.z + w.width / 2 + 1 });
    circles.push({ x: data.airport.pilot.x, z: data.airport.pilot.z, r: 1.6 });
  }
  for (const n of data.npcs.values()) if (n.house) circles.push({ x: n.house.x, z: n.house.z, r: 4.2 });
  return { rects, circles };
}

/** 이 자리가 물·섬 밖·건물 자리인지. 문제 이름(문자열) 또는 null. */
export function groundProblem(data, x, z) {
  if (!onIsland(data.layout?.island, x, z, data.layout?.island?.beach ?? 0)) return 'edge';
  for (const spot of data.spots.values()) if (distanceToSpot(spot, x, z) < 0.6) return 'water';
  const { rects, circles } = data.blocked;
  for (const r of rects) if (x >= r.x0 && x <= r.x1 && z >= r.z0 && z <= r.z1) return 'building';
  for (const c of circles) if (Math.hypot(x - c.x, z - c.z) < c.r) return 'building';
  return null;
}
