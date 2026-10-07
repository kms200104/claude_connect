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

/** 아파트 동 바닥(가운데 기준, w×d 를 yaw 만큼 돌린 것)을 감싸는 사각형. 앞 공동현관 쪽(+Z 로컬)은 front 만큼 더. */
export function towerRect(b, defaults = {}, pad = 0.6, front = 1.6) {
  const w = b.w ?? defaults.w ?? 9;
  const d = b.d ?? defaults.d ?? 6;
  const c = Math.cos(b.yaw ?? 0);
  const s = Math.sin(b.yaw ?? 0);
  const corners = [[-w / 2 - pad, -d / 2 - pad], [w / 2 + pad, -d / 2 - pad], [w / 2 + pad, d / 2 + front], [-w / 2 - pad, d / 2 + front]]
    .map(([u, v]) => [b.x + u * c + v * s, b.z - u * s + v * c]);
  return { x0: Math.min(...corners.map((q) => q[0])), x1: Math.max(...corners.map((q) => q[0])), z0: Math.min(...corners.map((q) => q[1])), z1: Math.max(...corners.map((q) => q[1])) };
}

/** 건물 바닥 사각형 (앞면 가운데 기준, 앞면이 +Z). 여유 pad 만큼 넓힌다. */
function buildingRect(b, pad) {
  return { x0: b.x - b.width / 2 - pad, x1: b.x + b.width / 2 + pad, z0: b.z - b.depth - pad, z1: b.z + pad };
}

/** 무엇이든 놓거나 심으면 안 되는 자리 목록 (사각형 · 원 · 선분 둘레). data 로 한 번 만든다. */
export function blockedAreas(data) {
  const rects = [];
  const circles = [];
  const segments = [];
  // v0.12: 꾸밈 (village_layout.json) — 바위 둘레 · 선착장 · 울타리 줄. 예전엔 서버가 몰라 그 위에 가구를 놓을 수 있었다.
  const layout = data.layout;
  for (const r of layout?.rocks ?? []) if (Number.isFinite(r.x) && Number.isFinite(r.z)) circles.push({ x: r.x, z: r.z, r: (r.size ?? 1) * 1.2 });
  if (layout?.dock) {
    const d = layout.dock;
    rects.push({ x0: d.x - d.length / 2 - 0.3, x1: d.x + d.length / 2 + 0.3, z0: d.z - d.width / 2 - 0.3, z1: d.z + d.width / 2 + 0.3 });
  }
  for (const line of layout?.fences ?? []) {
    for (let i = 0; i + 1 < line.length; i++) segments.push({ ax: line[i][0], az: line[i][1], bx: line[i + 1][0], bz: line[i + 1][1], r: 0.6 });
  }
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
  // v0.8~0.9 건물: 식당(앞 테라스까지), 아파트 동, 부동산 부스, 동사무소.
  const rest = data.restaurant?.building;
  if (rest) rects.push({ x0: rest.x - rest.width / 2 - 1, x1: rest.x + rest.width / 2 + 1, z0: rest.z - rest.depth / 2 - 1, z1: rest.z + rest.depth / 2 + 12 });
  for (const b of data.realestate?.buildings ?? []) rects.push(b.w || b.d || b.yaw ? towerRect(b) : { x0: b.x - 5.5, x1: b.x + 5.5, z0: b.z - 4, z1: b.z + 4.5 });
  // 둘레 단지 (겉모습만): 단지 기본 크기·층을 동마다 덮어쓸 수 있다.
  for (const complex of data.realestate?.samples ?? []) for (const b of complex.buildings) rects.push(towerRect(b, complex, 0.6, 1.2));
  const office = data.realestate?.office;
  if (office) circles.push({ x: office.x, z: office.z - 1, r: 2.2 });
  const civic = data.civic?.building;
  if (civic) rects.push(buildingRect(civic, 1.5));
  for (const m of data.mirrors ?? []) circles.push({ x: m.x, z: m.z, r: 1.3 });
  // 성성호수공원: 방문자센터(앞면 가운데 기준, yaw 는 90° 단위)와 정자.
  const park = data.layout?.park;
  if (park?.visitor_center) {
    const v = park.visitor_center;
    const pad = 1.5;
    const c = Math.cos(v.yaw ?? 0);
    const s = Math.sin(v.yaw ?? 0);
    // 로컬 (u, w): u = 앞면 가운데 기준 가로, w = 앞(+)·뒤(-) 방향. 월드 = 회전 후 이동.
    const corners = [[-v.width / 2 - pad, -v.depth - pad], [v.width / 2 + pad, -v.depth - pad], [v.width / 2 + pad, pad], [-v.width / 2 - pad, pad]]
      .map(([u, w]) => [v.x + u * c + w * s, v.z - u * s + w * c]);
    rects.push({ x0: Math.min(...corners.map((q) => q[0])), x1: Math.max(...corners.map((q) => q[0])), z0: Math.min(...corners.map((q) => q[1])), z1: Math.max(...corners.map((q) => q[1])) });
  }
  if (park?.pavilion) circles.push({ x: park.pavilion.x, z: park.pavilion.z, r: park.pavilion.size / 2 + 0.8 });
  return { rects, circles, segments };
}

/** 점에서 선분까지 거리. */
function segmentDistance(x, z, s) {
  const dx = s.bx - s.ax;
  const dz = s.bz - s.az;
  const len2 = dx * dx + dz * dz;
  const t = len2 > 0 ? Math.max(0, Math.min(1, ((x - s.ax) * dx + (z - s.az) * dz) / len2)) : 0;
  return Math.hypot(x - (s.ax + dx * t), z - (s.az + dz * t));
}

/** 이 자리가 물·섬 밖·건물 자리인지. 문제 이름(문자열) 또는 null. */
export function groundProblem(data, x, z) {
  if (!onIsland(data.layout?.island, x, z, data.layout?.island?.beach ?? 0)) return 'edge';
  for (const spot of data.spots.values()) if (distanceToSpot(spot, x, z) < 0.6) return 'water';
  const { rects, circles, segments = [] } = data.blocked;
  for (const r of rects) if (x >= r.x0 && x <= r.x1 && z >= r.z0 && z <= r.z1) return 'building';
  for (const c of circles) if (Math.hypot(x - c.x, z - c.z) < c.r) return 'building';
  for (const sg of segments) if (segmentDistance(x, z, sg) < sg.r) return 'fence';
  return null;
}
