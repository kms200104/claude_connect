// 생존 (v0.23, 서버 권위): 빈집 가구 뒤지기 · 체력 · 밤 크리처 · 맞서 싸우기 · 회복 · 쓰러뜨리면 떨어지는 아이템.
// data/survival/survival.json (규칙) · data/survival/houses.json (빈집촌 · 가구 자리). 시각은 세상 시각(clock.hour · worldMs, 60배).
//   클라이언트는 요청만: loot { c } · attack {} · use { slot }. 거리 · 쿨다운 · 확률 · 피해는 모두 여기서.
import { ErrorCode } from './protocol.js';
import { addItem, removeAt } from './inventory.js';
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
  const containers = new Map();
  for (const h of houses?.houses ?? []) {
    for (const c of h.containers) {
      if (!rules.loot.kinds[c.kind]) throw new Error(`container ${c.id}: unknown kind ${c.kind}`);
      containers.set(c.id, { ...c, house: h.id });
    }
  }
  return { ...rules, houses: houses?.houses ?? [], walls: houses?.walls ?? [], containers };
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
    if (t < (player.hurtUntil ?? 0)) return;
    player.hurtUntil = t + (S.player.hurt_grace_ms ?? 700);
    setHp(player, hpOf(player) - damage);
    sendTo(player, { t: 'hurt', ...hpWire(player), by });
    if (hpOf(player) <= 0) knockOut(room, player);
  }

  /** 낮에는 체력이 천천히 돌아온다 (worldTick, 1초마다). */
  function regen(room, dtMs) {
    if (night()) return;
    const perMs = (S.player.day_regen_per_world_hour ?? 1) * (clock.worldScale ?? 1) / HOUR_MS;
    for (const p of room.players.values()) {
      if (!p.online || hpOf(p) >= maxHp) continue;
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
    const people = [...room.players.values()].filter(outdoors);
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
      const pace = c.target ? kind.speed : kind.speed * (S.creatures.wander ?? 0.45);
      if (!safeAt(best.x, best.z)) {
        if (bestD > kind.reach * 0.8) {
          const step = Math.min(pace * dt, bestD - kind.reach * 0.8);
          const nx = c.x + ((best.x - c.x) / bestD) * step;
          const nz = c.z + ((best.z - c.z) / bestD) * step;
          if (canStand(nx, nz, def)) {
            c.x = nx;
            c.z = nz;
          } else {
            // 막히면 옆으로 비켜 본다.
            const side = (c.id.charCodeAt(c.id.length - 1) % 2 ? 1 : -1) * step;
            const sx = c.x + (-(best.z - c.z) / bestD) * side;
            const sz = c.z + ((best.x - c.x) / bestD) * side;
            if (canStand(sx, sz, def)) {
              c.x = sx;
              c.z = sz;
            }
          }
          changed = true;
        }
        c.yaw = Math.atan2(best.x - c.x, best.z - c.z);
        if (c.target && bestD <= kind.reach && t >= c.nextAttack) {
          c.nextAttack = t + kind.attack_ms;
          c.attackAt = t;
          hurt(room, best, kind.damage, c.k);
          changed = true;
        }
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
    return { ...hpWire(player), looted: lootedWire(room), creatures: [...(room.creatures?.values() ?? [])].map(creatureWire), night: night() };
  }

  return { handleLoot, handleUse, handleAttack, tick, regen, welcomeWire, hpWire, hpOf, night };
}
