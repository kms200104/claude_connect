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
    });
  }
  return npcs;
}

/**
 * 한 틱 진행. mode: 'roam'(평소) | 'home'(비·밤: 집 앞에 머묾). 움직였으면 true.
 */
export function stepNpcs(npcs, { dtMs, now, random, mode, speed, idleMinMs, idleMaxMs }) {
  let moved = false;
  for (const n of npcs.values()) {
    if (n.talkingWith !== null) continue;
    if (n.target === null) {
      if (now < n.waitUntil) continue;
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
      n.waitUntil = now + idleMinMs + random() * (idleMaxMs - idleMinMs);
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
  n.target = null;
  n.waitUntil = Math.max(n.waitUntil, now + ms);
  n.yaw = yawToward(x - n.x, z - n.z);
}

/** 대화 시작: 걷던 걸 멈추고 상대를 바라본다. */
export function beginTalk(n, player, now) {
  n.talkingWith = player.id;
  n.talkTouchedAt = now;
  n.target = null;
  n.yaw = yawToward(player.x - n.x, player.z - n.z);
}

export function endTalk(n, now) {
  n.talkingWith = null;
  n.waitUntil = now + 1500;
}

export function npcWire(n) {
  return { id: n.id, x: round(n.x), z: round(n.z), yaw: round(n.yaw), talk: n.talkingWith ?? 0, m: n.mood };
}
