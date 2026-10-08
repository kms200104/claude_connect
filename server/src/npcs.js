// 주민 NPC 이동(서버 권위). 데이터의 길목(waypoints) 사이만 걸어 다녀서 건물·나무·호수를 피한다.
// 비·뇌우·밤에는 집 앞(첫 번째 길목)으로 돌아가 머문다. 누군가와 대화 중이면 멈춰서 그 사람을 바라본다.

const round = (v) => Math.round(v * 1000) / 1000;

/** 모델 정면이 -Z 인 캐릭터가 (dx, dz) 방향을 볼 때의 yaw (클라이언트 Player 와 같은 식). */
export function yawToward(dx, dz) {
  return Math.atan2(-dx, -dz);
}

export function createNpcRuntime(defs, now, random) {
  const npcs = new Map();
  for (const def of defs.values()) {
    const [x, z] = def.waypoints[0];
    npcs.set(def.id, {
      id: def.id,
      def,
      x,
      z,
      yaw: 0,
      wp: 0,
      target: null,
      waitUntil: now + random() * 3000,
      talkingWith: null,
      talkTouchedAt: 0,
      baseMood: 'calm', // social.js: 오늘의 바탕 기분
      moodOverride: null, // 감정표현·대화로 잠시 바뀐 기분 { m, until }
      mood: 'calm', // 지금 기분 (방송용)
      reactAt: -Infinity, // 마지막으로 감정표현에 반응한 시각
      approaching: null, // v0.11: 먼저 말을 걸러 다가가는 중 { pid, since }
      approachAt: -Infinity, // 마지막으로 누군가에게 다가간 시각
      act: null, // v0.16: 길목에 멈춰 하는 몸짓 (npcs.json activities 의 id, 예: stretch · sit · fish)
    });
  }
  return npcs;
}

/**
 * 한 틱 진행. mode: 'roam'(평소) | 'home'(비·밤: 집 앞에 머묾). 움직였으면 true.
 */
export function stepNpcs(npcs, { dtMs, now, random, mode, speed, idleMinMs, idleMaxMs, pickActivity = null }) {
  let moved = false;
  for (const n of npcs.values()) {
    if (n.talkingWith !== null) continue;
    if (n.target === null) {
      if (n.approaching) continue;
      if (now < n.waitUntil) continue;
      // 몸짓을 마치고 다시 걷는다.
      if (n.act !== null) {
        n.act = null;
        moved = true;
      }
      const next = chooseWaypoint(n, mode, random);
      if (next === null) {
        n.waitUntil = now + idleMinMs + random() * (idleMaxMs - idleMinMs);
        continue;
      }
      n.wp = next;
      const [tx, tz] = n.def.waypoints[next];
      n.target = { x: tx, z: tz };
    }
    const dx = n.target.x - n.x;
    const dz = n.target.z - n.z;
    const dist = Math.hypot(dx, dz);
    const step = (speed * dtMs) / 1000;
    if (dist <= step) {
      n.x = n.target.x;
      n.z = n.target.z;
      n.target = null;
      if (!n.approaching) {
        n.waitUntil = now + idleMinMs + random() * (idleMaxMs - idleMinMs);
        // 길목에 닿으면 가끔 그 자리에서 몸짓을 한다 (기지개 · 몸풀기 · 해 바라보기 · 앉기 · 물가면 낚시). 그동안 머문다.
        const a = pickActivity ? pickActivity(n, mode) : null;
        if (a) {
          n.act = a.id;
          n.waitUntil = now + a.ms;
          if (Number.isFinite(a.yaw)) n.yaw = a.yaw;
        }
      }
    } else {
      n.x += (dx / dist) * step;
      n.z += (dz / dist) * step;
      n.yaw = yawToward(dx, dz);
    }
    moved = true;
  }
  return moved;
}

function chooseWaypoint(n, mode, random) {
  const count = n.def.waypoints.length;
  if (mode === 'home') return n.wp === 0 ? null : 0;
  if (count < 2) return null;
  let next = Math.floor(random() * (count - 1));
  if (next >= n.wp) next += 1;
  return next;
}

/** 감정표현에 반응: 잠깐 멈춰 서서 그 사람을 바라본다. */
export function pauseFor(n, x, z, now, ms) {
  if (n.talkingWith !== null) return;
  n.act = null;
  n.target = null;
  n.waitUntil = Math.max(n.waitUntil, now + ms);
  n.yaw = yawToward(x - n.x, z - n.z);
}

/** 대화 시작: 걷던 걸 멈추고 상대를 바라본다. */
export function beginTalk(n, player, now) {
  n.talkingWith = player.id;
  n.talkTouchedAt = now;
  n.act = null;
  n.target = null;
  n.yaw = yawToward(player.x - n.x, player.z - n.z);
}

export function endTalk(n, now) {
  n.talkingWith = null;
  n.waitUntil = now + 1500;
}

/**
 * 먼저 다가가 말 걸기 (v0.11). 친한 사람이 가까이 있으면 가끔 그 사람 쪽으로 걸어가고, 닿으면 onGreet(n, player).
 * players: 이 방의 온라인 플레이어들. friendOf(player, npcId) = 친밀도. canBeApproached(player) = 낚시·대화 중이 아님.
 * 사람에게 걸어가는 동안은 stepNpcs 가 목표(그 사람 옆)를 따라 걷는다.
 */
export function updateApproaches(npcs, players, { rules, now, dtMs, random, mode, friendOf, lastApproached, canBeApproached, onGreet }) {
  if (!rules) return false;
  let changed = false;
  for (const n of npcs.values()) {
    if (n.talkingWith !== null) {
      n.approaching = null;
      continue;
    }
    if (n.approaching) {
      const p = players.find((q) => q.id === n.approaching.pid);
      const d = p ? Math.hypot(p.x - n.x, p.z - n.z) : Infinity;
      if (!p || !canBeApproached(p) || d > rules.range * 1.6 || now - n.approaching.since > rules.give_up_ms) {
        n.approaching = null;
        n.target = null;
        n.waitUntil = now + 1500;
        changed = true;
        continue;
      }
      if (d <= rules.stop_distance + 0.35) {
        n.approaching = null;
        n.target = null;
        n.waitUntil = now + rules.wait_ms;
        n.yaw = yawToward(p.x - n.x, p.z - n.z);
        onGreet(n, p);
        changed = true;
        continue;
      }
      // 그 사람 옆 (stop_distance 앞) 을 목표로 계속 고친다.
      const k = (d - rules.stop_distance) / d;
      n.target = { x: n.x + (p.x - n.x) * k, z: n.z + (p.z - n.z) * k };
      continue;
    }
    if (mode !== 'roam' || now - n.approachAt < rules.npc_cooldown_ms) continue;
    if (random() > rules.chance_per_s * (dtMs / 1000)) continue;
    const near = players.filter(
      (p) =>
        canBeApproached(p) &&
        friendOf(p, n.id) >= rules.min_friendship &&
        now - lastApproached(p, n.id) >= rules.cooldown_ms &&
        Math.hypot(p.x - n.x, p.z - n.z) <= rules.range &&
        Math.hypot(p.x - n.x, p.z - n.z) > rules.stop_distance + 0.5,
    );
    if (near.length === 0) continue;
    // 가장 친한 사람에게.
    near.sort((a, b) => friendOf(b, n.id) - friendOf(a, n.id));
    n.approaching = { pid: near[0].id, since: now };
    n.act = null;
    n.approachAt = now;
    n.target = null;
    n.waitUntil = 0;
    changed = true;
  }
  return changed;
}

export function npcWire(n) {
  return { id: n.id, x: round(n.x), z: round(n.z), yaw: round(n.yaw), talk: n.talkingWith ?? 0, m: n.mood, ap: n.approaching?.pid ?? 0, a: n.act ?? '' };
}

/**
 * 길목에 멈췄을 때의 몸짓 고르기 (v0.16). rules = npcs.json activities. 비 · 밤(mode home)에는 하지 않는다.
 * sun: 맑은 낮에만 (해 쪽은 클라이언트가 돌아본다). water: 물가(낚시터 윤곽 · 사각형에서 water_range 안)에서만, 물 쪽을 본다.
 * 반환 { id, ms, yaw? } 또는 null.
 */
export function chooseActivity(n, rules, { random, mode, sunny, waterNear }) {
  if (!rules || mode !== 'roam' || random() > rules.chance) return null;
  const options = [];
  for (const a of rules.list) {
    if (a.need === 'sun' && !sunny) continue;
    let yaw;
    if (a.need === 'water') {
      const w = waterNear(n.x, n.z, a.water_range ?? 4);
      if (!w) continue;
      yaw = yawToward(w.x - n.x, w.z - n.z);
    }
    options.push({ a, yaw });
  }
  if (options.length === 0) return null;
  const total = options.reduce((sum, o) => sum + (o.a.weight ?? 1), 0);
  let r = random() * total;
  let pick = options[options.length - 1];
  for (const o of options) {
    r -= o.a.weight ?? 1;
    if (r <= 0) {
      pick = o;
      break;
    }
  }
  const ms = (pick.a.min_s + random() * (pick.a.max_s - pick.a.min_s)) * 1000;
  return { id: pick.a.id, ms, yaw: pick.yaw };
}
