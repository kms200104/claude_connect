// 낚시터 물고기 그림자 (v13). 호수마다 물고기 몇 마리가 늘 물 밑을 헤엄치고(모두 같은 그림자 모양, 몸 크기 S·M·L 로 크기가 다르고
// 희귀할수록 둘레에 아우라가 보인다), 바다는 바닷가에 선 사람 둘레에만 몇 마리 돌아다닌다. 서버가 위치를 정하고 'fishes' 로 방송한다.
//
// 낚시와의 관계 (fishing.js):
//   찌를 던진 자리(bobber) 둘레 notice 안에 있는 물고기 가운데, 머리 쪽(바라보는 방향 앞)에 찌가 떨어진 물고기가 가장 먼저 알아챈다.
//   알아챈 물고기는 찌 쪽으로 몸을 돌려 천천히 다가와 찌 앞에 멈추고(engaged), 톡·톡 건드리다가 문다. 그 물고기가 곧 낚일 물고기다.
//   아무도 못 알아채면 기다리는 동안 notice 가 조금씩 넓어져, 지나가던 물고기가 결국 찾아온다.
//   낚으면 그 물고기는 사라지고 잠시 뒤 새로 나타난다. 놓치면 휙 달아나 한동안 찌를 무시한다.
import { SEA_STAND_MAX, distanceToSpot, pickFish } from './gamedata.js';
import { signedDistance } from './outline.js';
import { islandShape } from './world.js';
import { shallowAt } from './shoal.js';
import { yawToward } from './npcs.js';

export const SWIM = {
  perLake: 6,
  perSeaPlayer: 4,
  roamSpeed: [0.25, 0.55], // m/s
  approachSpeed: 0.8,
  fleeSpeed: 2.2,
  notice: 2.6, // 찌를 알아채는 거리 (m)
  noticeGrowth: 1.5, // 기다리는 1초마다 넓어지는 거리 (지나가던 물고기가 금방 찾아온다)
  approachMaxS: 3.5, // 멀리서 알아챈 물고기도 이 시간 안에 다가온다 (더 빨리 헤엄친다)
  lakeMargin: 0.9, // 물가에서 이만큼 안쪽에서만 헤엄친다
  seaMinShape: 1.03, // 바다: 해안선 바깥 (섬 모양 값 ≥ 이것)
  seaRange: 22, // 바다 물고기는 이 거리 안에 사람이 없으면 사라진다
  respawnMs: 20000,
  waryMs: 8000,
  lifeMs: [150000, 260000], // 이만큼 지나면 다른 물고기로 바뀐다 (시각·날씨에 맞춰)
  viewRange: 28, // 이 거리 안에 사람이 있는 낚시터만 방송
};

/** 그림자 크기 배율 (몸 크기). 클라이언트 FishSchool 과 같다. */
export const SIZE_SCALE = { S: 0.75, M: 1.0, L: 1.35 };

const round = (v) => Math.round(v * 1000) / 1000;

export function createSwimmers({ data, random, now, environment, weightFor, spotIds }) {
  const rand = (a, b) => a + random() * (b - a);

  /** 이 자리가 그 낚시터 물(헤엄칠 수 있는 곳)인지. */
  function inWater(spot, x, z, margin = SWIM.lakeMargin) {
    // 바다: 물고기는 해안선 조금 바깥(seaMinShape)부터, 찌는(margin < lakeMargin) 해안선 바깥이면 어디든.
    if (spot.kind === 'sea') return spot.island ? islandShape(spot.island, x, z) >= (margin < SWIM.lakeMargin ? 1.0 : SWIM.seaMinShape) : false;
    if (spot.outline) return Math.abs(x - spot.x) <= spot.half_x && Math.abs(z - spot.z) <= spot.half_z && signedDistance(spot.outline, x, z) <= -margin;
    return Math.abs(x - spot.x) <= spot.half_x - margin && Math.abs(z - spot.z) <= spot.half_z - margin;
  }

  function lakePoint(spot) {
    const pick = () => ({ x: spot.x + rand(-1, 1) * (spot.half_x - SWIM.lakeMargin), z: spot.z + rand(-1, 1) * (spot.half_z - SWIM.lakeMargin) });
    if (!spot.outline) return pick();
    // 윤곽 호수: 바깥 사각형에서 뽑아 물 안쪽인 자리만 쓴다.
    for (let i = 0; i < 40; i++) {
      const p = pick();
      if (inWater(spot, p.x, p.z)) return p;
    }
    return { x: spot.x, z: spot.z };
  }

  /** 바다: 바닷가에 선 사람 앞바다 (해안선 바깥 2~7m, 옆으로 ±4m). */
  function seaPointNear(spot, px, pz) {
    const len = Math.hypot(px, pz) || 1;
    const ox = px / len;
    const oz = pz / len;
    for (let i = 0; i < 12; i++) {
      const side = rand(-4, 4);
      const out = rand(1.5, 4.5);
      // 해안선까지 바깥으로 걸어 나간 다음 out 만큼 더.
      let x = px;
      let z = pz;
      for (let k = 0; k < 40 && islandShape(spot.island, x, z) < SWIM.seaMinShape; k++) {
        x += ox * 0.5;
        z += oz * 0.5;
      }
      x += ox * out - oz * side;
      z += oz * out + ox * side;
      if (inWater(spot, x, z)) return { x, z };
    }
    return null;
  }

  function zoneOf(spot, x, z) {
    return spot.kind !== 'sea' && shallowAt(spot, x, z) ? 'shallow' : 'deep';
  }

  function spawn(room, spot, at, t) {
    const env = environment(spot);
    const zone = zoneOf(spot, at.x, at.z);
    const fish = pickFish(spot, data.fish, random, env.hour, env.weather, weightFor(room, spot, zone), env.season);
    room.swimSeq = (room.swimSeq ?? 0) + 1;
    const s = {
      id: `f${room.swimSeq}`,
      spot: spot.id,
      fish,
      x: round(at.x),
      z: round(at.z),
      yaw: round(rand(-Math.PI, Math.PI)),
      tx: at.x,
      tz: at.z,
      speed: rand(...SWIM.roamSpeed),
      st: 'roam', // roam | engaged | flee
      until: t + rand(500, 3000),
      dies: t + rand(...SWIM.lifeMs),
      wary: 0,
      owner: 0,
      anchor: { x: at.x, z: at.z },
    };
    room.swimmers.set(s.id, s);
    return s;
  }

  function newRoamTarget(spot, s) {
    for (let i = 0; i < 8; i++) {
      // 주로 머리 쪽으로 (yaw 의 정면 = (-sin, -cos)). 막히면 점점 옆·뒤로.
      const a = s.yaw + rand(-1.4, 1.4) * (1 + i * 0.3);
      const d = rand(1, 3.2);
      const x = s.x - Math.sin(a) * d;
      const z = s.z - Math.cos(a) * d;
      const near = spot.kind !== 'sea' || Math.hypot(x - s.anchor.x, z - s.anchor.z) < 9;
      if (inWater(spot, x, z) && near) return { x, z };
    }
    return { x: s.anchor.x, z: s.anchor.z };
  }

  /** 한 걸음 (목표 쪽으로, 몸을 돌리며). 닿았으면 true. */
  function swimToward(s, tx, tz, speed, dt, stopAt = 0.05) {
    const dx = tx - s.x;
    const dz = tz - s.z;
    const dist = Math.hypot(dx, dz);
    if (dist <= stopAt) return true;
    const want = yawToward(dx, dz);
    let diff = want - s.yaw;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    s.yaw = round(s.yaw + diff * Math.min(1, dt * 4));
    // 몸이 다 돌기 전에는 천천히 (물고기는 제자리에서 돌며 나아간다).
    const facing = Math.max(0.25, Math.cos(Math.min(Math.abs(diff), Math.PI / 2)));
    const step = Math.min(speed * facing * dt, dist - stopAt);
    s.x = round(s.x + (dx / dist) * step);
    s.z = round(s.z + (dz / dist) * step);
    return dist - step <= stopAt + 1e-6;
  }

  /** npcTick 마다. 바뀐 낚시터 id 들. */
  function tick(room, dtMs, t, people) {
    room.swimmers ??= new Map();
    const dt = dtMs / 1000;
    const changed = new Set();
    for (const id of spotIds()) {
      const spot = data.fishingSpot(id);
      if (!spot) continue;
      const list = [...room.swimmers.values()].filter((s) => s.spot === id);
      if (spot.kind === 'sea') {
        if (!spot.island) continue;
        // 바닷가에 선 사람만 (바다 건너 실내 — 상점 · 집 안 — 는 빼고).
        const shore = people.filter((p) => !p.home && islandShape(spot.island, p.x, p.z) > 0.82 && islandShape(spot.island, p.x, p.z) <= SEA_STAND_MAX);
        for (const s of list) {
          if (s.st !== 'engaged' && !shore.some((p) => Math.hypot(p.x - s.x, p.z - s.z) < SWIM.seaRange)) {
            room.swimmers.delete(s.id);
            changed.add(id);
          }
        }
        for (const p of shore) {
          const near = [...room.swimmers.values()].filter((s) => s.spot === id && Math.hypot(p.x - s.x, p.z - s.z) < 12).length;
          if (near < SWIM.perSeaPlayer && t >= (room.swimNext?.[`${id}:${p.id}`] ?? 0)) {
            const at = seaPointNear(spot, p.x, p.z);
            if (at) {
              spawn(room, spot, at, t);
              changed.add(id);
            }
            room.swimNext ??= {};
            room.swimNext[`${id}:${p.id}`] = t + (near === 0 ? 300 : 2500);
          }
        }
      } else {
        const watched = people.some((p) => distanceToSpot(spot, p.x, p.z) < SWIM.viewRange);
        room.swimNext ??= {};
        if (list.length < SWIM.perLake && t >= (room.swimNext[id] ?? 0)) {
          spawn(room, spot, lakePoint(spot), t);
          room.swimNext[id] = t + (list.length < SWIM.perLake / 2 ? 0 : SWIM.respawnMs / 4);
          changed.add(id);
        }
        if (!watched) continue; // 아무도 안 보는 호수는 멈춰 둔다
      }
      for (const s of [...room.swimmers.values()].filter((x) => x.spot === id)) {
        if (s.st === 'roam' && t >= s.dies && s.owner === 0) {
          room.swimmers.delete(s.id);
          changed.add(id);
          continue;
        }
        switch (s.st) {
          case 'roam':
            if (t >= s.until) {
              const n = newRoamTarget(spot, s);
              s.tx = n.x;
              s.tz = n.z;
              s.speed = rand(...SWIM.roamSpeed);
              s.until = t + rand(3000, 7000);
            }
            if (!swimToward(s, s.tx, s.tz, s.speed, dt, 0.1)) changed.add(id);
            break;
          case 'engaged':
            if (!swimToward(s, s.tx, s.tz, s.approach ?? SWIM.approachSpeed, dt, 0.02)) changed.add(id);
            else {
              // 찌를 똑바로 바라본다.
              const want = round(yawToward(s.bx - s.x, s.bz - s.z));
              if (want !== s.yaw) {
                s.yaw = want;
                changed.add(id);
              }
            }
            break;
          case 'flee':
            swimToward(s, s.tx, s.tz, SWIM.fleeSpeed, dt, 0.1);
            if (t >= s.until) {
              s.st = 'roam';
              s.until = t;
            }
            changed.add(id);
            break;
        }
      }
    }
    return changed;
  }

  /**
   * 찌가 (bx, bz) 에 떨어졌다: 알아챌 물고기를 고른다 (없으면 null). 머리 앞쪽에 떨어질수록, 가까울수록 먼저.
   * 고른 물고기는 찌 앞(머리가 찌를 향하게)으로 다가가기 시작한다. 돌려주는 값: { swimmer, approachMs }.
   */
  function engage(room, spotId, bx, bz, owner, t, notice = SWIM.notice) {
    room.swimmers ??= new Map();
    let best = null;
    let bestScore = Infinity;
    for (const s of room.swimmers.values()) {
      if (s.spot !== spotId || s.st === 'engaged' || s.owner !== 0 || t < s.wary) continue;
      const dx = bx - s.x;
      const dz = bz - s.z;
      const dist = Math.hypot(dx, dz);
      if (dist > notice) continue;
      // 바라보는 방향과 찌 방향의 차이 (0 = 바로 앞).
      let diff = Math.abs(yawToward(dx, dz) - s.yaw) % (Math.PI * 2);
      if (diff > Math.PI) diff = Math.PI * 2 - diff;
      const score = dist + (diff > (Math.PI * 2) / 3 ? 2.5 : diff > Math.PI / 3 ? 0.8 : 0);
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    if (!best) return null;
    const dx = bx - best.x;
    const dz = bz - best.z;
    const dist = Math.hypot(dx, dz) || 1;
    const hover = 0.28 + 0.12 * (SIZE_SCALE[best.fish.size] ?? 1);
    const speed = Math.max(SWIM.approachSpeed, Math.max(0, dist - 0.4) / SWIM.approachMaxS);
    best.st = 'engaged';
    best.owner = owner;
    best.approach = speed;
    best.bx = bx;
    best.bz = bz;
    best.tx = round(bx - (dx / dist) * hover);
    best.tz = round(bz - (dz / dist) * hover);
    // 몸을 돌리는 시간 + 헤엄쳐 오는 시간.
    let diff = Math.abs(yawToward(dx, dz) - best.yaw) % (Math.PI * 2);
    if (diff > Math.PI) diff = Math.PI * 2 - diff;
    const approachMs = Math.round((Math.max(0, dist - hover) / speed + (diff / Math.PI) * 0.8) * 1000);
    return { swimmer: best, approachMs };
  }

  /** 낚시가 끝났다: caught = 사라지고 나중에 새로, 아니면 휙 달아나 한동안 찌를 무시. */
  function release(room, id, caught, t) {
    const s = room.swimmers?.get(id);
    if (!s) return;
    if (caught) {
      room.swimmers.delete(id);
      room.swimNext ??= {};
      room.swimNext[s.spot] = Math.max(room.swimNext[s.spot] ?? 0, t + SWIM.respawnMs);
      return;
    }
    const spot = data.fishingSpot(s.spot);
    const away = Math.hypot(s.x - s.bx, s.z - s.bz) || 1;
    let tx = s.x + ((s.x - s.bx) / away) * 3;
    let tz = s.z + ((s.z - s.bz) / away) * 3;
    if (spot && !inWater(spot, tx, tz)) {
      tx = s.anchor.x;
      tz = s.anchor.z;
    }
    s.st = 'flee';
    s.owner = 0;
    s.tx = tx;
    s.tz = tz;
    s.until = t + 1500;
    s.wary = t + SWIM.waryMs;
  }

  function wire(room, spotId) {
    return [...(room.swimmers?.values() ?? [])]
      .filter((s) => s.spot === spotId)
      .map((s) => ({ id: s.id, x: s.x, z: s.z, yaw: s.yaw, s: s.fish.size ?? 'M', r: s.fish.rarity ?? 'common', st: s.st, o: s.owner }));
  }

  return { tick, engage, release, wire, inWater };
}
