// 생존 (v0.23, 서버 권위): 빈집 가구 뒤지기 · 체력 · 밤 크리처 · 맞서 싸우기 · 회복 · 쓰러뜨리면 떨어지는 아이템.
// v0.24: 빈집 현관 · 깨진 창에 판자 대기 (거점) — 크리처는 뚫린 곳으로 들어오고 막힌 곳은 두드려 부순다 ·
//        쓰러짐 (동료가 곁에서 일으키면 기절하지 않는다).
// data/survival/survival.json (규칙) · data/survival/houses.json (빈집촌 · 가구 자리). 시각은 세상 시각(clock.hour · worldMs, 60배).
//   클라이언트는 요청만: loot { c } · attack {} · use { slot } · board { h, o } · revive { p } · give_up {}.
//   거리 · 쿨다운 · 확률 · 피해는 모두 여기서.
import { ErrorCode } from './protocol.js';
import { addItem, countWhere, removeAt, removeWhere } from './inventory.js';
import { inHours, HOUR_MS } from './clock.js';
import { groundProblem } from './world.js';
import { isLand } from './water.js';

const round = (v) => Math.round(v * 100) / 100;

/** 두 파일을 읽어 검사한다 (모르는 아이템이면 켜지 않는다). */
export function loadSurvival(rules, houses, isKnown) {
  if (!rules) return null;
  const check = (list, where) => {
    for (const e of list ?? []) if (!isKnown(e.id)) throw new Error(`${where}: unknown item ${e.id}`);
  };
  for (const [kind, table] of Object.entries(rules.loot?.kinds ?? {})) check(table.items, `loot ${kind}`);
  for (const [kind, c] of Object.entries(rules.creatures?.kinds ?? {})) check(c.drops, `creature ${kind}`);
  for (const id of Object.keys(rules.heal ?? {})) if (!id.startsWith('_') && !isKnown(id)) throw new Error(`heal: unknown ${id}`);
  check(rules.fortify?.cost, 'fortify');
  const containers = new Map();
  // v0.24 뚫린 곳 (판자를 댈 수 있는 현관 · 깨진 창): "집:자리" → 월드 가운데 · 안쪽 · 바깥쪽 자리.
  const breaches = new Map();
  const openings = houses?.openings ?? [];
  const list = [];
  for (const h of houses?.houses ?? []) {
    for (const c of h.containers) {
      if (!rules.loot.kinds[c.kind]) throw new Error(`container ${c.id}: unknown kind ${c.kind}`);
      containers.set(c.id, { ...c, house: h.id });
    }
    const house = { ...h, cos: Math.cos(h.yaw), sin: Math.sin(h.yaw), breaches: [] };
    const at = (lx, lz) => ({ x: house.x + lx * house.cos + lz * house.sin, z: house.z - lx * house.sin + lz * house.cos });
    for (const o of openings) {
      if (o.kind !== 'door' && !(h.broken ?? []).includes(o.id)) continue;
      const mid = at(o.lx, o.lz);
      const inner = at(o.lx - o.nx * 0.7, o.lz - o.nz * 0.7);
      const outer = at(o.lx + o.nx * 0.8, o.lz + o.nz * 0.8);
      const b = {
        key: `${h.id}:${o.id}`, house: h.id, id: o.id, kind: o.kind, max: rules.fortify?.hp?.[o.kind] ?? 10,
        x: mid.x, z: mid.z, inX: inner.x, inZ: inner.z, outX: outer.x, outZ: outer.z, inL: { x: o.lx - o.nx * 0.7, z: o.lz - o.nz * 0.7 },
      };
      house.breaches.push(b);
      breaches.set(b.key, b);
    }
    list.push(house);
  }
  return { ...rules, houses: list, houseById: new Map(list.map((h) => [h.id, h])), walls: houses?.walls ?? [], rooms: houses?.rooms ?? [], containers, breaches };
}

/** 선분 p→q 가 가운데 기준 사각형 |x| ≤ a, |z| ≤ b 를 지나는지 (Liang–Barsky). */
function segmentHitsRect(p, q, a, b) {
  let t0 = 0;
  let t1 = 1;
  const dx = q.x - p.x;
  const dz = q.z - p.z;
  for (const [pp, qq] of [[-dx, p.x + a], [dx, a - p.x], [-dz, p.z + b], [dz, b - p.z]]) {
    if (pp === 0) {
      if (qq < 0) return false;
      continue;
    }
    const r = qq / pp;
    if (pp < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
  }
  return t0 <= t1;
}

/** 가중치 표에서 하나. */
export function pickEntry(list, random) {
  const total = list.reduce((s, e) => s + (e.w ?? e.weight ?? 1), 0);
  let r = random() * total;
  for (const e of list) {
    r -= e.w ?? e.weight ?? 1;
    if (r < 0) return e;
  }
  return list[list.length - 1];
}

/** 가구 하나를 뒤져 나오는 것 [{ id, n }] (빈손이면 []). */
export function rollLoot(table, random) {
  const out = [];
  for (let i = 0; i < (table.rolls ?? 1); i++) {
    if (random() < (table.empty ?? 0)) continue;
    const e = pickEntry(table.items, random);
    const [lo, hi] = e.n ?? [1, 1];
    const n = lo + Math.floor(random() * (hi - lo + 1));
    const same = out.find((o) => o.id === e.id);
    if (same) same.n += n;
    else out.push({ id: e.id, n });
  }
  return out;
}

export function createSurvival({ data, cfg, clock, random, now, send, sendTo, sendInventory, sendProfile, inShop, saveRoom, dropAt, act }) {
  const S = data.survival;
  const worldMs = () => (clock.worldMs ? clock.worldMs() : clock.gameMs());
  const maxHp = S?.player?.max_hp ?? 10;
  const night = () => inHours(S.creatures.night, clock.hour());
  const shelter = data.safety?.drill?.shelter ?? { x: 0, z: 0 };

  /** 프로필 체력 (없으면 가득). */
  const hpOf = (player) => {
    const hp = player.profile.hp;
    return Number.isFinite(hp) ? Math.max(0, Math.min(maxHp, hp)) : maxHp;
  };
  const hpWire = (player) => ({ hp: hpOf(player), max: maxHp });

  /** 크리처가 들어오지 못하는 안전한 곳: 대피소 · 광장 둘레, 상점 · 집 안. */
  function safeAt(x, z) {
    const r = S.creatures.safe_radius ?? 12;
    if (Math.hypot(x - shelter.x, z - shelter.z) < r) return true;
    const plaza = data.layout?.plaza;
    if (plaza && Math.hypot(x - plaza.x, z - plaza.z) < r) return true;
    return false;
  }

  const outdoors = (p) => p.online && !p.home && !inShop(p);

  // ---- 빈집 모양 (로컬 좌표: 가운데 기준, 앞면 +z) ----

  const toLocal = (h, x, z) => {
    const dx = x - h.x;
    const dz = z - h.z;
    return { x: dx * h.cos - dz * h.sin, z: dx * h.sin + dz * h.cos };
  };
  const toWorld = (h, lx, lz) => ({ x: h.x + lx * h.cos + lz * h.sin, z: h.z - lx * h.sin + lz * h.cos });

  /** 이 자리가 들어 있는 빈집 (없으면 null). */
  function houseAt(x, z, margin = 0) {
    for (const h of S?.houses ?? []) {
      const q = toLocal(h, x, z);
      if (Math.abs(q.x) <= h.w / 2 + margin && Math.abs(q.z) <= h.d / 2 + margin) return h;
    }
    return null;
  }

  /** 안쪽 방 (앞방이면 null). */
  const roomOf = (q) => S.rooms.find((r) => q.x >= r.x0 && q.x < r.x1 && q.z >= r.z0 && q.z < r.z1) ?? null;

  /** 집 안에서 goal 로 가려면 지금 향할 곳 (방이 다르면 문틈을 거친다, 로컬). */
  function innerAim(q, goal) {
    const rc = roomOf(q);
    const rg = roomOf(goal);
    if (rc === rg) return goal;
    const r = rc ?? rg;
    const inside = { x: r.door[0], z: r.door[1] - 0.6 };
    const front = { x: r.door[0], z: r.door[1] + 0.6 };
    // 안쪽 방에서는 문틈 안 → 앞방으로, 앞방에서는 문틈 앞 → 안쪽 방으로.
    if (rc) return Math.hypot(q.x - inside.x, q.z - inside.z) < 0.35 ? front : inside;
    return Math.hypot(q.x - front.x, q.z - front.z) < 0.35 ? inside : front;
  }

  /** 집 밖에서 (tx, tz) 로 가는 길이 집을 가로지르면 둘러 갈 모서리 (아니면 그대로). */
  function detour(h, x, z, tx, tz) {
    const a = h.w / 2 + 0.4;
    const b = h.d / 2 + 0.4;
    const q = toLocal(h, x, z);
    const g = toLocal(h, tx, tz);
    if (!segmentHitsRect(q, g, a, b)) return { x: tx, z: tz };
    let best = null;
    let bestCost = Infinity;
    for (const [sx, sz] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
      const k = { x: sx * (h.w / 2 + 1.1), z: sz * (h.d / 2 + 1.1) };
      if (Math.hypot(k.x - q.x, k.z - q.z) < 0.3 || segmentHitsRect(q, k, a, b)) continue;
      const cost = Math.hypot(k.x - q.x, k.z - q.z) + Math.hypot(g.x - k.x, g.z - k.z);
      if (cost < bestCost) {
        bestCost = cost;
        best = k;
      }
    }
    return best ? toWorld(h, best.x, best.z) : { x: tx, z: tz };
  }

  // ---- 판자 대기 (거점) ----

  const boardHp = (room, b) => room.boards?.[b.key] ?? 0;

  function boardsWire(room) {
    return { ...(room.boards ?? {}) };
  }

  function handleBoard(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const b = S?.breaches.get(`${msg.h}:${msg.o}`);
    if (!b) return fail(ErrorCode.badItem);
    if (player.home || inShop(player) || Math.hypot(player.x - b.x, player.z - b.z) > S.fortify.range + 0.3) return fail(ErrorCode.tooFar);
    room.boards ??= {};
    if (boardHp(room, b) >= b.max) return fail(ErrorCode.alreadyBoarded);
    for (const need of S.fortify.cost) if (countWhere(player.slots, (id) => id === need.id) < need.n) return fail(ErrorCode.notEnoughItems);
    for (const need of S.fortify.cost) removeWhere(player.slots, (id) => id === need.id, need.n);
    const repaired = boardHp(room, b) > 0;
    room.boards[b.key] = b.max;
    sendInventory(player);
    send(ctx.ws, { t: 'boarded', rid: msg.rid, h: b.house, o: b.id, hp: b.max, max: b.max, repaired });
    room.broadcast({ t: 'board', h: b.house, o: b.id, hp: b.max, max: b.max, by: player.id });
    act(room, player, 'board', b.key);
    saveRoom(room);
  }

  /** 크리처가 판자를 두드린다 (0 이 되면 부서져 다시 뚫린다). */
  function bash(room, b, damage, c) {
    const hp = Math.max(0, boardHp(room, b) - damage);
    if (hp > 0) room.boards[b.key] = hp;
    else delete room.boards[b.key];
    room.broadcast({ t: 'board', h: b.house, o: b.id, hp, max: b.max, by: 0, c: c.id });
    if (hp === 0) saveRoom(room);
  }

  // ---- 빈집 뒤지기 ----

  function lootedWire(room) {
    const out = {};
    const w = worldMs();
    for (const [id, until] of Object.entries(room.looted ?? {})) if (until > w) out[id] = until;
    return out;
  }

  function handleLoot(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const c = S?.containers.get(msg.c);
    if (!c) return fail(ErrorCode.badItem);
    if (player.home || inShop(player) || Math.hypot(player.x - c.x, player.z - c.z) > S.loot.range + 0.3) return fail(ErrorCode.tooFar);
    room.looted ??= {};
    const w = worldMs();
    if ((room.looted[c.id] ?? 0) > w) return fail(ErrorCode.alreadyLooted);
    const found = rollLoot(S.loot.kinds[c.kind], random);
    // 가방에 다 들어가지 않는 건 발밑에 내려놓는다 (잃지 않게).
    const got = [];
    for (const it of found) {
      if (addItem(player.slots, it.id, it.n, cfg, data.limitOf)) got.push(it);
      else dropAt(room, it.id, it.n, player.x, player.z);
    }
    room.looted[c.id] = w + (S.loot.restock_world_hours ?? 48) * HOUR_MS;
    sendInventory(player);
    send(ctx.ws, { t: 'looted', rid: msg.rid, c: c.id, items: found, got });
    room.broadcast({ t: 'container', c: c.id, until: room.looted[c.id] });
    act(room, player, 'loot', c.kind);
    saveRoom(room);
  }

  // ---- 체력 · 회복 · 기절 ----

  function setHp(player, hp) {
    player.profile.hp = Math.max(0, Math.min(maxHp, hp));
  }

  function handleUse(ctx, msg, fail) {
    const { player } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
    const heal = slot ? S?.heal?.[slot.id] : undefined;
    if (!slot || !heal) return fail(ErrorCode.badItem);
    if (hpOf(player) >= maxHp) return fail(ErrorCode.hpFull);
    removeAt(player.slots, msg.slot, 1);
    setHp(player, hpOf(player) + heal);
    sendInventory(player);
    send(ctx.ws, { t: 'hp', rid: msg.rid, ...hpWire(player), item: slot.id, heal });
  }

  function knockOut(room, player) {
    if (player.downed) getUp(room, player, 0, true);
    const lost = Math.min(S.player.ko_sol_max ?? 0, Math.floor((player.profile.sol ?? 0) * (S.player.ko_sol_rate ?? 0)));
    player.profile.sol = Math.max(0, (player.profile.sol ?? 0) - lost);
    setHp(player, maxHp);
    player.x = shelter.x;
    player.z = shelter.z + 2;
    player.y = 0.1;
    player.vx = 0;
    player.vz = 0;
    player.lastMoveAt = now();
    player.hurtUntil = now() + 3000;
    room.dirty = true;
    sendTo(player, { t: 'correct', x: player.x, y: player.y, z: player.z });
    sendTo(player, { t: 'ko', lost, ...hpWire(player), x: player.x, z: player.z });
    sendProfile(player);
    // 쫓던 크리처는 흩어진다.
    for (const c of room.creatures?.values() ?? []) if (c.target === player.id) c.target = 0;
  }

  function hurt(room, player, damage, by) {
    const t = now();
    if (player.downed || t < (player.hurtUntil ?? 0)) return;
    player.hurtUntil = t + (S.player.hurt_grace_ms ?? 700);
    setHp(player, hpOf(player) - damage);
    sendTo(player, { t: 'hurt', ...hpWire(player), by });
    if (hpOf(player) > 0) return;
    if (canBeRevived(room, player)) down(room, player);
    else knockOut(room, player);
  }

  // ---- 쓰러짐 · 일으키기 (v0.24 같이 하기) ----

  const D = S?.downed;

  /** 일으켜 줄 동료가 있는지 (같은 방, 접속 중, 쓰러지지 않음). */
  function canBeRevived(room, player) {
    if (!D) return false;
    for (const p of room.players.values()) if (p !== player && p.online && !p.downed) return true;
    return false;
  }

  function down(room, player) {
    player.downed = { until: now() + D.ms, by: 0, doneAt: 0 };
    setHp(player, 0);
    for (const c of room.creatures?.values() ?? []) if (c.target === player.id) c.target = 0;
    room.broadcast({ t: 'downed', id: player.id, left: D.ms, x: round(player.x), z: round(player.z) });
  }

  function getUp(room, player, by, ko) {
    delete player.downed;
    room.broadcast({ t: 'up', id: player.id, by, ko });
  }

  function handleRevive(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const target = room.players.get(msg.p);
    if (!target?.downed || target === player) return fail(ErrorCode.notDowned);
    if (Math.hypot(target.x - player.x, target.z - player.z) > D.revive_range + 0.3) return fail(ErrorCode.tooFar);
    target.downed.by = player.id;
    target.downed.doneAt = now() + D.revive_ms;
    send(ctx.ws, { t: 'reviving', rid: msg.rid, id: target.id, ms: D.revive_ms });
    room.broadcast({ t: 'revive', id: target.id, by: player.id, ms: D.revive_ms });
  }

  function handleGiveUp(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!player.downed) return fail(ErrorCode.notDowned);
    knockOut(room, player);
  }

  /** 쓰러진 사람: 일으키는 중이면 다 됐는지 · 동료가 떠났는지, 시간이 다 되면 기절 (낮에도). */
  function tickDowned(room, t) {
    if (!D) return;
    for (const p of room.players.values()) {
      const d = p.downed;
      if (!d) continue;
      if (d.by) {
        const r = room.players.get(d.by);
        if (!r || !r.online || r.downed || Math.hypot(r.x - p.x, r.z - p.z) > D.revive_range + 0.6) {
          d.by = 0;
          d.doneAt = 0;
          room.broadcast({ t: 'revive', id: p.id, by: 0, ms: 0 });
        } else if (t >= d.doneAt) {
          setHp(p, D.revive_hp);
          p.hurtUntil = t + 2000;
          getUp(room, p, r.id, false);
          sendTo(p, { t: 'hp', ...hpWire(p) });
          room.dirty = true;
          continue;
        }
      }
      if (t >= d.until || !canBeRevived(room, p)) knockOut(room, p);
    }
  }

  function downedWire(room) {
    const t = now();
    return [...room.players.values()].filter((p) => p.downed).map((p) => ({ id: p.id, left: Math.max(0, p.downed.until - t), by: p.downed.by }));
  }

  /** 낮에는 체력이 천천히 돌아온다 (worldTick, 1초마다). */
  function regen(room, dtMs) {
    if (night()) return;
    const perMs = (S.player.day_regen_per_world_hour ?? 1) * (clock.worldScale ?? 1) / HOUR_MS;
    for (const p of room.players.values()) {
      if (!p.online || p.downed || hpOf(p) >= maxHp) continue;
      p.regenAcc = (p.regenAcc ?? 0) + perMs * dtMs;
      if (p.regenAcc >= 1) {
        const add = Math.floor(p.regenAcc);
        p.regenAcc -= add;
        setHp(p, hpOf(p) + add);
        sendTo(p, { t: 'hp', ...hpWire(p) });
      }
    }
  }

  // ---- 크리처 ----

  const creatureWire = (c) => ({ id: c.id, k: c.k, x: round(c.x), z: round(c.z), yaw: round(c.yaw), hp: c.hp, a: c.attackAt > now() - 350 ? 1 : 0 });

  /** 놓인 가구로 막힌 곳 (바리케이드) · 불빛 (모닥불 · 든 횃불 · 손전등). */
  function defenses(room) {
    const blocks = [];
    const lights = [];
    const traps = [];
    for (const f of room.placed.values()) {
      const d = S.defense?.[f.item];
      if (!d) continue;
      if (d.block) blocks.push({ x: f.x, z: f.z, r: d.block });
      if (d.light) lights.push({ x: f.x, z: f.z, r: d.light });
      if (d.trap) traps.push({ id: f.id, x: f.x, z: f.z, r: d.trap, damage: d.trap_damage ?? 1, every: d.trap_cooldown_ms ?? 1000 });
    }
    for (const p of room.players.values()) {
      const w = S.weapons[p.heldItem];
      if (p.online && w?.light) lights.push({ x: p.x, z: p.z, r: w.light });
    }
    return { blocks, lights, traps };
  }

  function canStand(x, z, def) {
    if (!isLand(data, x, z)) return false;
    if (groundProblem(data, x, z) === 'building') return false;
    if (safeAt(x, z)) return false;
    for (const b of def.blocks) if (Math.hypot(x - b.x, z - b.z) < b.r) return false;
    for (const l of def.lights) if (Math.hypot(x - l.x, z - l.z) < l.r) return false;
    return true;
  }

  /** 빈집 안 (벽에서 조금 떨어진 곳). 불빛은 안에서도 꺼린다. */
  function standInside(h, x, z, def) {
    const q = toLocal(h, x, z);
    if (Math.abs(q.x) > h.w / 2 - 0.35 || Math.abs(q.z) > h.d / 2 - 0.35) return false;
    for (const l of def.lights) if (Math.hypot(x - l.x, z - l.z) < l.r) return false;
    return true;
  }

  /** aim 쪽으로 한 걸음 (stop 만큼 앞에서 멈춘다). 막히면 옆으로 비켜 본다. 움직였으면 true. */
  function moveToward(c, aim, stop, step, stand) {
    const d = Math.hypot(aim.x - c.x, aim.z - c.z);
    if (d <= stop + 0.01) return false;
    const len = Math.min(step, d - stop);
    const nx = c.x + ((aim.x - c.x) / d) * len;
    const nz = c.z + ((aim.z - c.z) / d) * len;
    if (stand(nx, nz)) {
      c.x = nx;
      c.z = nz;
      return true;
    }
    const side = (c.id.charCodeAt(c.id.length - 1) % 2 ? 1 : -1) * len;
    const sx = c.x + (-(aim.z - c.z) / d) * side;
    const sz = c.z + ((aim.x - c.x) / d) * side;
    if (stand(sx, sz)) {
      c.x = sx;
      c.z = sz;
      return true;
    }
    return false;
  }

  function spawnNear(room, player, def, t) {
    const kinds = Object.entries(S.creatures.kinds).map(([k, v]) => ({ k, ...v }));
    const kind = pickEntry(kinds, random);
    for (let i = 0; i < 10; i++) {
      const a = random() * Math.PI * 2;
      const r = S.creatures.spawn_min + random() * (S.creatures.spawn_max - S.creatures.spawn_min);
      const x = player.x + Math.cos(a) * r;
      const z = player.z + Math.sin(a) * r;
      if (!canStand(x, z, def) || groundProblem(data, x, z) !== null) continue;
      room.creatureSeq = (room.creatureSeq ?? 0) + 1;
      const c = { id: `z${room.creatureSeq}`, k: kind.k, x, z, yaw: Math.atan2(player.x - x, player.z - z), hp: kind.hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} };
      room.creatures.set(c.id, c);
      return c;
    }
    return null;
  }

  function kill(room, c, by) {
    room.creatures.delete(c.id);
    room.broadcast({ t: 'creature_dead', id: c.id, by, x: round(c.x), z: round(c.z) });
    const kind = S.creatures.kinds[c.k];
    if (kind && random() < (kind.drop_chance ?? 1)) {
      const e = pickEntry(kind.drops, random);
      const [lo, hi] = e.n ?? [1, 1];
      dropAt(room, e.id, lo + Math.floor(random() * (hi - lo + 1)), c.x, c.z);
    }
  }

  /** npcTick 마다. 바뀌었으면 true (방송은 여기서). */
  function tick(room, dtMs, t) {
    if (!S) return;
    room.creatures ??= new Map();
    tickDowned(room, t);
    const dt = dtMs / 1000;
    let changed = false;
    if (!night()) {
      if (room.creatures.size > 0) {
        // 해가 뜨면 흩어진다.
        for (const c of room.creatures.values()) room.broadcast({ t: 'creature_dead', id: c.id, by: 0, x: round(c.x), z: round(c.z), sun: true });
        room.creatures.clear();
        room.broadcast({ t: 'creatures', st: t, c: [] });
      }
      return;
    }
    const people = [...room.players.values()].filter((p) => outdoors(p) && !p.downed);
    const def = defenses(room);
    // 나타나기.
    if (t >= (room.nextCreatureAt ?? 0)) {
      room.nextCreatureAt = t + (S.creatures.spawn_every_ms ?? 9000) * (cfg.creatureSpawnScale ?? 1);
      for (const p of people) {
        if (room.creatures.size >= S.creatures.max_per_room) break;
        if (safeAt(p.x, p.z)) continue;
        const near = [...room.creatures.values()].filter((c) => Math.hypot(c.x - p.x, c.z - p.z) < S.creatures.despawn_far).length;
        if (near < S.creatures.per_player && spawnNear(room, p, def, t)) changed = true;
      }
    }
    for (const c of [...room.creatures.values()]) {
      const kind = S.creatures.kinds[c.k];
      // 아무도 가까이 없으면 사라진다.
      let best = null;
      let bestD = Infinity;
      for (const p of people) {
        const d = Math.hypot(p.x - c.x, p.z - c.z);
        if (d < bestD) {
          bestD = d;
          best = p;
        }
      }
      if (!best || bestD > S.creatures.despawn_far) {
        room.creatures.delete(c.id);
        room.broadcast({ t: 'creature_dead', id: c.id, by: 0, x: round(c.x), z: round(c.z), gone: true });
        changed = true;
        continue;
      }
      const aggro = c.target === best.id ? kind.aggro * 1.5 : kind.aggro;
      c.target = bestD <= aggro && !safeAt(best.x, best.z) ? best.id : 0;
      // 아직 알아채지 못했어도 사람 냄새를 따라 천천히 (wander) 다가온다.
      const step = (c.target ? kind.speed : kind.speed * (S.creatures.wander ?? 0.45)) * dt;
      if (safeAt(best.x, best.z)) continue;
      const ph = houseAt(best.x, best.z); // 사람이 있는 빈집 (밖이면 null)
      const ch = c.inside ? S.houseById.get(c.inside) : null; // 크리처가 있는 빈집
      const stand = ch ? (x, z) => standInside(ch, x, z, def) : (x, z) => canStand(x, z, def);
      if (ph === ch) {
        // 같은 곳 (둘 다 밖 · 같은 집 안): 쫓는다. 집 안에서는 방 사이 문틈으로, 밖에서는 가까운 집을 둘러서.
        let aim = { x: best.x, z: best.z };
        let stop = kind.reach * 0.8;
        let sameRoom = true;
        if (ch) {
          const q = toLocal(ch, c.x, c.z);
          const g = toLocal(ch, best.x, best.z);
          const a = innerAim(q, g);
          sameRoom = a === g;
          if (!sameRoom) {
            aim = toWorld(ch, a.x, a.z);
            stop = 0;
          }
        } else {
          const near = houseAt(c.x, c.z, 3);
          if (near) {
            const d = detour(near, c.x, c.z, best.x, best.z);
            if (d.x !== best.x || d.z !== best.z) {
              aim = d;
              stop = 0;
            }
          }
        }
        if (moveToward(c, aim, stop, step, stand)) changed = true;
        c.yaw = Math.atan2(best.x - c.x, best.z - c.z);
        if (c.target && sameRoom && Math.hypot(best.x - c.x, best.z - c.z) <= kind.reach && t >= c.nextAttack) {
          c.nextAttack = t + kind.attack_ms;
          c.attackAt = t;
          hurt(room, best, kind.damage, c.k);
          changed = true;
        }
      } else if (!ch) {
        // 사람이 빈집 안: 뚫린 곳(막혔으면 판자를 두드려)으로 들어간다.
        let b = null;
        let bestScore = Infinity;
        for (const x of ph.breaches) {
          const score = Math.hypot(x.outX - c.x, x.outZ - c.z) + (boardHp(room, x) > 0 ? 8 : 0);
          if (score < bestScore) {
            bestScore = score;
            b = x;
          }
        }
        if (!b) continue;
        if (Math.hypot(b.outX - c.x, b.outZ - c.z) > 0.45) {
          const aim = detour(ph, c.x, c.z, b.outX, b.outZ);
          if (moveToward(c, aim, 0, step, stand)) changed = true;
          c.yaw = Math.atan2(aim.x - c.x, aim.z - c.z);
        } else if (boardHp(room, b) <= 0) {
          c.x = b.inX;
          c.z = b.inZ;
          c.inside = ph.id;
          changed = true;
        } else {
          c.yaw = Math.atan2(b.x - c.x, b.z - c.z);
          if (c.target && t >= c.nextAttack) {
            c.nextAttack = t + kind.attack_ms;
            c.attackAt = t;
            bash(room, b, kind.damage, c);
            changed = true;
          }
        }
      } else {
        // 크리처는 집 안인데 사람은 밖 (또는 다른 집): 뚫린 곳으로 나간다 (다 막혔으면 갇힌다).
        let b = null;
        let bestDist = Infinity;
        for (const x of ch.breaches) {
          const d = Math.hypot(x.inX - c.x, x.inZ - c.z);
          if (boardHp(room, x) <= 0 && d < bestDist) {
            bestDist = d;
            b = x;
          }
        }
        if (!b) continue;
        if (bestDist <= 0.45) {
          c.x = b.outX;
          c.z = b.outZ;
          c.inside = undefined;
        } else {
          const a = innerAim(toLocal(ch, c.x, c.z), b.inL);
          const aim = toWorld(ch, a.x, a.z);
          moveToward(c, aim, 0, step, stand);
          c.yaw = Math.atan2(aim.x - c.x, aim.z - c.z);
        }
        changed = true;
      }
      // 덫.
      for (const trap of def.traps) {
        if (Math.hypot(c.x - trap.x, c.z - trap.z) < trap.r && t >= (c.trapAt[trap.id] ?? 0)) {
          c.trapAt[trap.id] = t + trap.every;
          c.hp -= trap.damage;
          room.broadcast({ t: 'creature_hit', id: c.id, hp: c.hp, by: 0, trap: trap.id });
          changed = true;
          if (c.hp <= 0) {
            kill(room, c, 0);
            break;
          }
        }
      }
    }
    if (changed) room.broadcast({ t: 'creatures', st: t, c: [...room.creatures.values()].map(creatureWire) });
  }

  function handleAttack(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const w = S.weapons[player.heldItem] ?? S.weapons.hands;
    const t = now();
    if (t < (player.attackReadyAt ?? 0)) return fail(ErrorCode.tooFast);
    player.attackReadyAt = t + w.cooldown_ms - 60;
    act(room, player, 'swing', player.heldItem ?? '');
    let target = null;
    let bestD = w.range + 0.3;
    for (const c of room.creatures?.values() ?? []) {
      const d = Math.hypot(c.x - player.x, c.z - player.z);
      if (d <= bestD) {
        bestD = d;
        target = c;
      }
    }
    if (!target) return send(ctx.ws, { t: 'swing', rid: msg.rid, hit: '' });
    target.hp -= w.damage;
    // 맞으면 조금 밀려난다.
    if (bestD > 0.01) {
      const push = 0.7;
      const nx = target.x + ((target.x - player.x) / bestD) * push;
      const nz = target.z + ((target.z - player.z) / bestD) * push;
      if (isLand(data, nx, nz)) {
        target.x = nx;
        target.z = nz;
      }
    }
    send(ctx.ws, { t: 'swing', rid: msg.rid, hit: target.id, hp: Math.max(0, target.hp) });
    room.broadcast({ t: 'creature_hit', id: target.id, hp: Math.max(0, target.hp), by: player.id });
    if (target.hp <= 0) kill(room, target, player.id);
    room.broadcast({ t: 'creatures', st: t, c: [...room.creatures.values()].map(creatureWire) });
  }

  function welcomeWire(room, player) {
    return {
      ...hpWire(player), looted: lootedWire(room), creatures: [...(room.creatures?.values() ?? [])].map(creatureWire), night: night(),
      boards: boardsWire(room), downed: downedWire(room),
    };
  }

  const isDowned = (player) => Boolean(player.downed);

  return { handleLoot, handleUse, handleAttack, handleBoard, handleRevive, handleGiveUp, tick, regen, welcomeWire, hpWire, hpOf, night, isDowned };
}
