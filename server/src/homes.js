// 아파트 집 안 (v0.10): 평면도(data/realestate/floorplans.json)를 미터로 바꾸고, 호수마다 집 안이 놓이는 자리(섬 바깥 먼 곳),
// 바닥 안인지 검사, 처음 놓이는 가구를 만든다. 가구 위치는 평면도 기준(왼쪽 위 = 0, 0) 미터, rot 는 45° 단위(0~7).

/**
 * 평면도 하나를 미터 단위로: { id, name, pyeong, size{x,z}, rooms[{id, kind, rects[[x0,z0,x1,z1]]}], doors[[x,z]], front[x,z], spawn[x,z], defaults[] }
 * sizeScale (v0.12, floorplans.json 의 size_scale): 평면도 모두를 가로·세로 이만큼 키운다.
 */
export function planInMeters(id, raw, sizeScale = 1) {
  const s = raw.scale * sizeScale;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const room of raw.rooms) {
    for (const [x0, y0, x1, y1] of room.r) {
      minX = Math.min(minX, x0);
      minY = Math.min(minY, y0);
      maxX = Math.max(maxX, x1);
      maxY = Math.max(maxY, y1);
    }
  }
  const mx = (x) => Math.round((x - minX) * s * 1000) / 1000;
  const mz = (y) => Math.round((y - minY) * s * 1000) / 1000;
  const rooms = raw.rooms.map((room) => ({ id: room.id, kind: room.kind, rects: room.r.map(([x0, y0, x1, y1]) => [mx(x0), mz(y0), mx(x1), mz(y1)]) }));
  const entry = rooms.find((r) => r.kind === 'entry');
  const e = entry?.rects[0] ?? [0, 0, 1, 1];
  return {
    id,
    name: raw.name,
    pyeong: raw.pyeong,
    size: { x: mx(maxX), z: mz(maxY) },
    rooms,
    doors: raw.doors.map(([x, y]) => [mx(x), mz(y)]),
    front: [mx(raw.front[0]), mz(raw.front[1])],
    spawn: [Math.round(((e[0] + e[2]) / 2) * 1000) / 1000, Math.round(((e[1] + e[3]) / 2 + 0.15) * 1000) / 1000],
    defaults: (raw.defaults ?? []).map((d) => ({ item: d.item, x: mx(d.at[0]), z: mz(d.at[1]), rot: normRot(d.rot ?? 0) })),
  };
}

export function loadPlans(raw) {
  const plans = new Map();
  for (const [id, p] of Object.entries(raw.plans)) plans.set(id, planInMeters(id, p, raw.size_scale ?? 1));
  return plans;
}

export function normRot(rot) {
  return ((Math.trunc(Number(rot) || 0) % 8) + 8) % 8;
}

/** 그 호수의 평면도 id: 동의 plans 가 평형별로 바꿀 수 있고, 아니면 평형의 plan. */
export function planIdOf(realestate, unit) {
  const building = realestate.buildings.find((b) => b.id === unit.building);
  return building?.plans?.[unit.type] ?? realestate.types[unit.type]?.plan ?? '';
}

/** 그 호수의 집 안이 놓이는 월드 원점 (평면도 왼쪽 위). 호수마다 겹치지 않는 자리. */
export function interiorOrigin(rules, units, unitId) {
  const index = units.findIndex((u) => u.id === unitId);
  if (index < 0) return null;
  const g = rules.interiors;
  return { x: g.x0 + (index % g.cols) * g.dx, z: g.z0 + Math.floor(index / g.cols) * g.dz };
}

/** 동 공동 현관 앞 (집 구경을 시작하는 자리). */
export function lobbyOf(realestate, rules, buildingId) {
  const b = realestate.buildings.find((x) => x.id === buildingId);
  if (!b) return null;
  // 앞면(로컬 +Z)으로 front 만큼. 기본 깊이(6m)보다 얕은 동은 그만큼 가깝게.
  const front = rules.lobby.front - (6 - (b.d ?? 6)) / 2;
  const yaw = b.yaw ?? 0;
  return { x: b.x + Math.sin(yaw) * front, z: b.z + Math.cos(yaw) * front };
}

/** 평면도 기준 (x, z) 가 바닥(방 사각형 하나) 안인지. margin 만큼 안쪽이어야 한다. */
export function onFloor(plan, x, z, margin = 0) {
  return plan.rooms.some((room) => room.rects.some(([x0, z0, x1, z1]) => x >= x0 + margin && x <= x1 - margin && z >= z0 + margin && z <= z1 - margin));
}

/** 그 자리가 어느 방인지 (없으면 null). */
export function roomAt(plan, x, z) {
  return plan.rooms.find((room) => room.rects.some(([x0, z0, x1, z1]) => x >= x0 && x <= x1 && z >= z0 && z <= z1)) ?? null;
}

/** 격자에 맞춘 좌표 (보이지 않는 격자, 0.25m). */
export function snapGrid(v, grid) {
  return Math.round(v / grid) * grid;
}

/** 처음 집에 놓이는 가구 (TV · 에어컨 · 선풍기 · 침대). id 는 d1, d2, … */
export function defaultFurniture(plan) {
  return plan.defaults.map((d, i) => ({ id: `d${i + 1}`, item: d.item, x: d.x, z: d.z, rot: d.rot }));
}

export function furnitureWire(list) {
  return list.map((f) => [f.id, f.item, Math.round(f.x * 1000) / 1000, Math.round(f.z * 1000) / 1000, f.rot]);
}

/** 저장된 집 가구: { 호수: [{id, item, x, z, rot}] }. 모르는 호수·아이템·바닥 밖은 버린다. */
export function sanitizeHomeItems(raw, units, plansOf, isFurniture) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [unitId, list] of Object.entries(raw)) {
    const unit = units.find((u) => u.id === unitId);
    const plan = unit ? plansOf(unit) : null;
    if (!plan || !Array.isArray(list)) continue;
    out[unitId] = list
      .filter((f) => f && typeof f.id === 'string' && isFurniture(f.item) && Number.isFinite(f.x) && Number.isFinite(f.z) && onFloor(plan, f.x, f.z, -0.3))
      .slice(0, 80)
      .map((f) => ({ id: f.id, item: f.item, x: f.x, z: f.z, rot: normRot(f.rot) }));
  }
  return out;
}
