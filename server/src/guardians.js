// v0.28.2 가디언 · 주민 (서버 권위): 시내 둘레 초소의 총을 든 아군이 다가오는 크리처를 쏜다.
// 크리처는 사람보다 가까운 가디언 · 주민도 노린다 — 가디언은 쓰러지면 세상 시간 20분 뒤 다시 서고, 주민은 쓰러져 한동안 누워 있다.
// data/survival/survival.json guardians. 크리처의 움직임 · 공격 거리는 survival.js 가 정하고, 여기서는 쏘기 · 맞기 · 부활만.
//   서버 → guard_shot { g, c, hp } · guard_hit { g, hp } · guard_down { g, left } · guard_up { g } · npc_hit { id, hp } · npc_down { id, left } · npc_up { id }.
const round = (v) => Math.round(v * 100) / 100;

export function createGuardians({ data, worldMs, random, kill, armorOf }) {
  const G = data.survival?.guardians;
  const minMs = 60 * 1000;

  function ensure(room) {
    if (!G) return new Map();
    if (!room.guards) {
      room.guards = new Map(G.posts.map((p) => [p.id, { id: p.id, x: p.x, z: p.z, yaw: 0, hp: G.hp, deadUntil: 0, nextShot: 0 }]));
    }
    return room.guards;
  }

  const alive = (g) => g.deadUntil === 0;

  function guardWire(g) {
    return { id: g.id, x: g.x, z: g.z, yaw: round(g.yaw), hp: g.hp, max: G.hp, left: alive(g) ? 0 : Math.max(0, g.deadUntil - worldMs()) };
  }
  const guardsWire = (room) => [...ensure(room).values()].map(guardWire);
  const npcDownWire = (room) => [...(room.npcs?.values() ?? [])].filter((n) => n.down).map((n) => ({ id: n.id, left: Math.max(0, n.downUntil - worldMs()) }));

  /** 크리처가 사람(bestD)보다 가까이 노릴 아군 (가디언 · 밖의 주민) — aggro 안. 없으면 null. */
  function allyNear(room, c, kind, bestD, safeAt) {
    if (!G || c.inside) return null;
    let best = null;
    let d0 = Math.min(bestD, kind.aggro);
    for (const g of ensure(room).values()) {
      if (!alive(g)) continue;
      const d = Math.hypot(g.x - c.x, g.z - c.z);
      if (d < d0) {
        d0 = d;
        best = { kind: 'guard', ref: g, x: g.x, z: g.z, d };
      }
    }
    for (const n of room.npcs?.values() ?? []) {
      if (n.down || safeAt(n.x, n.z)) continue;
      const d = Math.hypot(n.x - c.x, n.z - c.z);
      if (d < d0) {
        d0 = d;
        best = { kind: 'npc', ref: n, x: n.x, z: n.z, d };
      }
    }
    return best;
  }

  /** 크리처가 아군을 때렸다. */
  function hitAlly(room, ally, damage) {
    if (ally.kind === 'guard') {
      const g = ally.ref;
      g.hp -= damage;
      if (g.hp <= 0) {
        g.hp = 0;
        g.deadUntil = worldMs() + G.respawn_world_min * minMs;
        room.broadcast({ t: 'guard_down', g: g.id, left: g.deadUntil - worldMs() });
      } else room.broadcast({ t: 'guard_hit', g: g.id, hp: g.hp });
      return;
    }
    const n = ally.ref;
    n.hp = (n.hp ?? G.npc_hp) - damage;
    if (n.hp <= 0) {
      n.down = true;
      n.downUntil = worldMs() + G.npc_down_world_min * minMs;
      n.target = null;
      room.npcsDirty = true;
      room.broadcast({ t: 'npc_down', id: n.id, left: n.downUntil - worldMs() });
    } else room.broadcast({ t: 'npc_hit', id: n.id, hp: n.hp });
  }

  /** npcTick 마다 (낮 · 밤): 부활 · 일어나기 · 쏘기. 크리처가 바뀌었으면 true. */
  function tick(room, t) {
    if (!G) return false;
    const w = worldMs();
    let changed = false;
    for (const g of ensure(room).values()) {
      if (!alive(g)) {
        if (w >= g.deadUntil) {
          g.deadUntil = 0;
          g.hp = G.hp;
          room.broadcast({ t: 'guard_up', g: g.id });
        }
        continue;
      }
      if (t < g.nextShot) continue;
      let target = null;
      let bestD = G.range;
      for (const c of room.creatures?.values() ?? []) {
        if (c.inside) continue;
        const d = Math.hypot(c.x - g.x, c.z - g.z);
        if (d < bestD) {
          bestD = d;
          target = c;
        }
      }
      if (!target) continue;
      g.nextShot = t + G.shot_ms * (0.85 + random() * 0.3);
      g.yaw = Math.atan2(target.x - g.x, target.z - g.z);
      target.hp -= Math.max(1, G.damage - armorOf(target));
      room.broadcast({ t: 'guard_shot', g: g.id, c: target.id, hp: Math.max(0, target.hp), x: round(target.x), z: round(target.z) });
      if (target.hp <= 0) kill(room, target, 0);
      changed = true;
    }
    for (const n of room.npcs?.values() ?? []) {
      if (n.down && w >= n.downUntil) {
        n.down = false;
        n.hp = G.npc_hp;
        room.npcsDirty = true;
        room.broadcast({ t: 'npc_up', id: n.id });
      }
    }
    return changed;
  }

  return { tick, allyNear, hitAlly, guardsWire, npcDownWire, ensure };
}
