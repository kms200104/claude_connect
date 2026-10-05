// 얕은 물(여울)의 물고기 떼와 뜰채 몰이 (서버 권위, 순수 함수 + 상태).
// 물고기는 가까운 사람에게서 달아나고(flee_speed, 사람 걸음보다 빠르다), 여울 사각형 밖으로는 못 나간다 — 그래서 혼자서는 잘 안 잡히고
// 구석으로 몰거나 둘이 양쪽에서 막아야 한다. 같은 여울에 두 사람 이상 들어오면 물고기가 우왕좌왕(panic_speed)해 느려지고 뜰채도 넓게 뜬다.

/** 여울 목록: [{ id, name, spot(낚시터 id), x, z, half_x, half_z, max, fish[] }] */
export function shallowZones(spots) {
  const zones = [];
  for (const spot of spots.values()) for (const z of spot.shallows ?? []) zones.push({ ...z, spot: spot.id });
  return zones;
}

export function inZone(zone, x, z, margin = 0) {
  return Math.abs(x - zone.x) <= zone.half_x + margin && Math.abs(z - zone.z) <= zone.half_z + margin;
}

/** 이 자리에서 가장 가까운 물이 여울이면 그 여울 (낚시가 얕은 곳인지 깊은 곳인지 가를 때). */
export function shallowAt(spot, x, z) {
  // 수역 사각형에서 가장 가까운 점.
  const cx = Math.max(spot.x - spot.half_x, Math.min(spot.x + spot.half_x, x));
  const cz = Math.max(spot.z - spot.half_z, Math.min(spot.z + spot.half_z, z));
  for (const s of spot.shallows ?? []) if (Math.abs(cx - s.x) <= s.half_x + 0.4 && Math.abs(cz - s.z) <= s.half_z + 0.4) return s;
  return null;
}

/** 새 떼 상태. */
export function newShoal(zone) {
  return { zone, fish: [], seq: 0, nextSpawnAt: 0, moving: false };
}

function spawnOne(shoal, data, random) {
  const zone = shoal.zone;
  const pool = zone.fish.map((id) => data.fish.get(id)).filter(Boolean);
  let roll = random() * pool.reduce((a, f) => a + (f.weight ?? 1), 0);
  let sp = pool[0];
  for (const f of pool) {
    roll -= f.weight ?? 1;
    if (roll <= 0) {
      sp = f;
      break;
    }
  }
  shoal.seq += 1;
  const a = random() * Math.PI * 2;
  shoal.fish.push({
    id: shoal.seq,
    sp: sp.id,
    size: sp.size ?? 'S',
    x: zone.x + (random() * 2 - 1) * (zone.half_x - 0.5),
    z: zone.z + (random() * 2 - 1) * (zone.half_z - 0.5),
    vx: Math.cos(a) * 0.3,
    vz: Math.sin(a) * 0.3,
    turnAt: 0,
    tiredUntil: 0,
  });
}

/** 비어 있으면 채우고, 시간이 되면 하나씩 다시 채운다. 바뀌었으면 true. */
export function refillShoal(shoal, data, rules, t, random) {
  let changed = false;
  if (shoal.fish.length === 0 && shoal.nextSpawnAt === 0) {
    for (let i = 0; i < shoal.zone.max; i++) spawnOne(shoal, data, random);
    shoal.nextSpawnAt = t + rules.respawn_s * 1000;
    return true;
  }
  if (shoal.fish.length < shoal.zone.max && t >= shoal.nextSpawnAt) {
    spawnOne(shoal, data, random);
    shoal.nextSpawnAt = t + rules.respawn_s * 1000;
    changed = true;
  }
  return changed;
}

/**
 * dt 초 움직인다. people = [{x, z}] (여울 근처 사람들). 여울 안에 두 사람 이상이면 우왕좌왕.
 * 돌려주는 값: 움직였는지.
 */
export function stepShoal(shoal, people, rules, dt, t, random) {
  const zone = shoal.zone;
  const wading = people.filter((p) => inZone(zone, p.x, p.z, 0.3)).length;
  const panic = wading >= 2;
  const fleeSpeed = panic ? rules.panic_speed : rules.flee_speed;
  let moved = false;
  for (const f of shoal.fish) {
    let ax = 0;
    let az = 0;
    for (const p of people) {
      const dx = f.x - p.x;
      const dz = f.z - p.z;
      const d = Math.hypot(dx, dz);
      if (d < rules.flee_radius && d > 1e-3) {
        const w = (rules.flee_radius - d) / rules.flee_radius;
        ax += (dx / d) * w;
        az += (dz / d) * w;
      }
    }
    const fleeing = ax !== 0 || az !== 0;
    if (fleeing) {
      const len = Math.hypot(ax, az);
      // 우왕좌왕하면 방향이 조금씩 흔들린다.
      const wobble = panic ? (random() - 0.5) * 1.2 : 0;
      const ang = Math.atan2(az, ax) + wobble;
      // 벽·구석에 몰린 물고기는 잠깐 지쳐서 느려진다 (몰이 사냥의 노림수).
      const tired = t < (f.tiredUntil ?? 0) ? rules.cornered_slow ?? 0.35 : 1;
      const speed = fleeSpeed * tired * Math.min(1, len * 1.6);
      f.vx = Math.cos(ang) * speed;
      f.vz = Math.sin(ang) * speed;
    } else if (t >= f.turnAt) {
      const a = random() * Math.PI * 2;
      f.vx = Math.cos(a) * rules.wander_speed * random();
      f.vz = Math.sin(a) * rules.wander_speed * random();
      f.turnAt = t + 1200 + random() * 2400;
    }
    if (f.vx === 0 && f.vz === 0) continue;
    f.x += f.vx * dt;
    f.z += f.vz * dt;
    // 여울 밖으로는 못 나간다: 벽에 붙고 그 방향 속도는 버린다 (구석에 몰린다).
    const hx = zone.half_x - 0.25;
    const hz = zone.half_z - 0.25;
    if (f.x < zone.x - hx || f.x > zone.x + hx) {
      f.x = Math.max(zone.x - hx, Math.min(zone.x + hx, f.x));
      f.vx = fleeing ? 0 : -f.vx;
      if (fleeing) f.tiredUntil = t + (rules.cornered_ms ?? 1500);
    }
    if (f.z < zone.z - hz || f.z > zone.z + hz) {
      f.z = Math.max(zone.z - hz, Math.min(zone.z + hz, f.z));
      f.vz = fleeing ? 0 : -f.vz;
      if (fleeing) f.tiredUntil = t + (rules.cornered_ms ?? 1500);
    }
    moved = true;
  }
  shoal.panic = panic;
  return moved;
}

/** 뜰채질: (x, z) 둘레 radius 안의 물고기를 max 마리까지 건진다. 건진 물고기 목록. */
export function netCatch(shoal, x, z, radius, max) {
  const caught = shoal.fish
    .map((f) => ({ f, d: Math.hypot(f.x - x, f.z - z) }))
    .filter((e) => e.d <= radius)
    .sort((a, b) => a.d - b.d)
    .slice(0, max)
    .map((e) => e.f);
  if (caught.length) shoal.fish = shoal.fish.filter((f) => !caught.includes(f));
  return caught;
}

export function shoalWire(shoal) {
  return { id: shoal.zone.id, panic: !!shoal.panic, f: shoal.fish.map((f) => [f.id, Math.round(f.x * 100) / 100, Math.round(f.z * 100) / 100, f.size]) };
}
