// 생존 (v0.23, 서버 권위): 빈집 가구 뒤지기 · 체력 · 밤 크리처 · 맞서 싸우기 · 회복 · 쓰러뜨리면 떨어지는 아이템.
// v0.24: 빈집 현관 · 깨진 창에 판자 대기 (거점) — 크리처는 뚫린 곳으로 들어오고 막힌 곳은 두드려 부순다 ·
//        쓰러짐 (동료가 곁에서 일으키면 기절하지 않는다).
// v0.25: 소리(휘두르기 · 달리기 · 망치질)가 크리처를 부른다 · 판자는 시간 들여 대고 함께 대면 빨라진다 ·
//        거점(다 막은 빈집)의 상자 · 침대.
// v0.26: 피 냄새 — 다치면 핏자국을 남기고, 크리처가 더 멀리서 알아채고 핏자국을 따라온다 (붕대로 멈춘다) ·
//        탈것으로 들이받기 ram { c, s, dx, dz } — 빠르면 날아가고(빠를수록 멀리 · 세게, 벽에 부딪히면 더), 느리면 넘어진다.
// v0.27: 보급 상자 (survival.json supply) — 밤마다 헬기가 낙하산 상자를 떨어뜨린다 (supply 방송), 먼저 연 사람이 갖는다
//        supply_open { s } → supply_got (나) · supply_gone (모두). 가까이 오면 지키던 크리처가 나타난다.
// v0.28: 게이트 (gates.js) — 게이트 크리처(c.g · 우두머리 c.boss)는 낮에도 남고, 멀어도 사라지지 않는다. 브레이크 크리처(c.brk)도 낮에 남는다.
// data/survival/survival.json (규칙) · data/survival/houses.json (빈집촌 · 가구 자리). 시각은 세상 시각(clock.hour · worldMs, 60배).
//   클라이언트는 요청만: loot { c } · attack {} · use { slot } · board { h, o } · revive { p } · give_up {} ·
//   stash { h, op: put|take, slot|id, n? } · sleep { on } · supply_open { s }.
//   거리 · 쿨다운 · 확률 · 피해는 모두 여기서.
import { ErrorCode } from './protocol.js';
import { addItem, countWhere, removeAt, removeWhere } from './inventory.js';
import { inHours, HOUR_MS } from './clock.js';
import { groundProblem } from './world.js';
import { isLand } from './water.js';
import { createGates } from './gates.js';
import { createGuardians } from './guardians.js';

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
  for (const id of Object.keys(rules.needs?.nourish ?? {})) if (!isKnown(id)) throw new Error(`needs.nourish: unknown ${id}`);
  check(rules.fortify?.cost, 'fortify');
  check(rules.supply?.loot?.items, 'supply');
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

export function createSurvival({ data, cfg, clock, random, now, send, sendTo, sendInventory, sendProfile, inShop, saveRoom, dropAt, act, garage, hunter, teleport }) {
  const S = data.survival;
  const worldMs = () => (clock.worldMs ? clock.worldMs() : clock.gameMs());
  const maxHp = S?.player?.max_hp ?? 10;
  const night = () => inHours(S.creatures.night, clock.hour());
  const shelter = data.safety?.drill?.shelter ?? { x: 0, z: 0 };

  /** v0.28.1 사람마다 최대 체력 (체력 스탯만큼 더). */
  const maxOf = (player) => maxHp + (hunter?.bonus.hp(player) ?? 0);
  /** 프로필 체력 (없으면 가득). */
  const hpOf = (player) => {
    const hp = player.profile.hp;
    return Number.isFinite(hp) ? Math.max(0, Math.min(maxOf(player), hp)) : maxOf(player);
  };
  const hpWire = (player) => ({ hp: hpOf(player), max: maxOf(player) });
  // v0.28.7 배고픔 · 목마름.
  const NE = S?.needs;
  const needsWire = (player) => ({ t: 'needs', food: Math.round(player.profile.food ?? 100), water: Math.round(player.profile.water ?? 100), max: NE?.max ?? 100 });
  const starving = (player) => NE && ((player.profile.food ?? 100) <= 0 || (player.profile.water ?? 100) <= 0);
  hunter?.setOnVit((room, player) => sendTo(player, { t: 'hp', ...hpWire(player) }));

  /** 크리처가 들어오지 못하는 안전한 곳: 대피소 · 광장 둘레 · v0.28.2 배리어, 상점 · 집 안. */
  function safeAt(x, z) {
    const r = S.creatures.safe_radius ?? 12;
    if (Math.hypot(x - shelter.x, z - shelter.z) < r) return true;
    const plaza = data.layout?.plaza;
    if (plaza && Math.hypot(x - plaza.x, z - plaza.z) < r) return true;
    // v0.28.2 배리어 (상점 · 주요 건물 둘레): 크리처가 들어오지 못하고, 안의 사람은 노리지 않는다.
    for (const b of S?.barriers?.list ?? []) if (Math.hypot(x - b.x, z - b.z) < b.r) return true;
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

  const F = S?.fortify;
  const jobWire = (j) => ({ h: j.b.house, o: j.b.id, progress: Math.round(j.progress), need: j.need, helpers: [...j.helpers] });

  /** 판자 대기 시작 (v0.25: board_ms 동안 망치질) · 이미 누가 대는 중이면 함께 (빨라지고 재료는 안 낸다). */
  function handleBoard(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const b = S?.breaches.get(`${msg.h}:${msg.o}`);
    if (!b) return fail(ErrorCode.badItem);
    if (player.home || inShop(player) || Math.hypot(player.x - b.x, player.z - b.z) > F.range + 0.3) return fail(ErrorCode.tooFar);
    room.boards ??= {};
    if (boardHp(room, b) >= b.max) return fail(ErrorCode.alreadyBoarded);
    room.boardJobs ??= new Map();
    const job = room.boardJobs.get(b.key);
    if (job) {
      if (!job.helpers.includes(player.id)) job.helpers.push(player.id);
      wake(room, player);
      send(ctx.ws, { t: 'boarding', rid: msg.rid, ...jobWire(job), joined: true });
      room.broadcast({ t: 'board_job', ...jobWire(job) });
      return;
    }
    for (const need of F.cost) if (countWhere(player.slots, (id) => id === need.id) < need.n) return fail(ErrorCode.notEnoughItems);
    for (const need of F.cost) removeWhere(player.slots, (id) => id === need.id, need.n);
    sendInventory(player);
    wake(room, player);
    const j = { b, helpers: [player.id], payer: player.id, progress: 0, need: F.board_ms ?? 0, repaired: boardHp(room, b) > 0, nextNoise: 0, nextWire: 0 };
    send(ctx.ws, { t: 'boarding', rid: msg.rid, ...jobWire(j), joined: false });
    if (j.need <= 0) return finishJob(room, j);
    room.boardJobs.set(b.key, j);
    room.broadcast({ t: 'board_job', ...jobWire(j) });
  }

  function finishJob(room, j) {
    const b = j.b;
    room.boards[b.key] = b.max;
    for (const id of j.helpers) {
      const p = room.players.get(id);
      if (p) sendTo(p, { t: 'boarded', h: b.house, o: b.id, hp: b.max, max: b.max, repaired: j.repaired, helpers: j.helpers.length });
      if (p) hunter?.act(room, p, 'board');
    }
    room.broadcast({ t: 'board_job', h: b.house, o: b.id, done: true });
    room.broadcast({ t: 'board', h: b.house, o: b.id, hp: b.max, max: b.max, by: j.payer, helpers: j.helpers.length });
    const payer = room.players.get(j.payer);
    if (payer) act(room, payer, 'board', b.key);
    saveRoom(room);
  }

  /** 망치질: 곁에 남은 사람 수만큼 빨리, 소리를 낸다. 모두 떠나면 그만두고 재료를 돌려준다 (낮에도). */
  function tickJobs(room, dtMs, t) {
    for (const [key, j] of room.boardJobs ?? []) {
      const before = j.helpers.length;
      j.helpers = j.helpers.filter((id) => {
        const p = room.players.get(id);
        return p && p.online && !p.downed && !p.home && Math.hypot(p.x - j.b.x, p.z - j.b.z) <= F.range + 0.6;
      });
      if (j.helpers.length === 0) {
        room.boardJobs.delete(key);
        const payer = room.players.get(j.payer);
        if (payer) {
          for (const need of F.cost) addItem(payer.slots, need.id, need.n, cfg, data.limitOf);
          sendInventory(payer);
        }
        room.broadcast({ t: 'board_job', h: j.b.house, o: j.b.id, cancel: true });
        continue;
      }
      j.progress += dtMs * j.helpers.length;
      if (t >= j.nextNoise) {
        j.nextNoise = t + 1500;
        noise(room, room.players.get(j.helpers[0]), 'board', j.b.x, j.b.z);
      }
      if (j.progress >= j.need) {
        room.boardJobs.delete(key);
        finishJob(room, j);
        continue;
      }
      if (t >= j.nextWire || j.helpers.length !== before) {
        j.nextWire = t + 400;
        room.broadcast({ t: 'board_job', ...jobWire(j) });
      }
    }
  }

  // ---- 소리 (v0.25) ----

  const N = S?.noise;

  /** 밤에 (x, z) 에서 소리: 반경 안 크리처가 소리 낸 사람을 쫓는다. 망치질은 가끔 한 마리를 더 부른다. */
  function noise(room, player, kind, x = player.x, z = player.z) {
    if (!N || !player || !night()) return;
    const r = N[kind];
    if (!r) return;
    const t = now();
    let heard = 0;
    for (const c of room.creatures?.values() ?? []) {
      if (Math.hypot(c.x - x, c.z - z) > r) continue;
      c.alertUntil = t + N.alert_ms;
      c.alertBy = player.id;
      heard++;
    }
    if (kind === 'board' && t >= (room.noiseSpawnAt ?? 0) && outdoors(player) && !player.downed) {
      room.noiseSpawnAt = t + N.spawn_every_ms;
      room.creatures ??= new Map();
      if (room.creatures.size < S.creatures.max_per_room) {
        const c = spawnNear(room, player, defenses(room), t);
        if (c) {
          c.alertUntil = t + N.alert_ms;
          c.alertBy = player.id;
          heard++;
        }
      }
    }
    sendTo(player, { t: 'noise', k: kind, r, n: heard });
  }

  /** 이동 요청마다 (server.js): 달리면 소리, 움직이면 잠에서 깬다. */
  function moved(room, player, speed) {
    if (speed > 0.6) wake(room, player);
    if (speed <= (N?.run_speed ?? 5.5)) return;
    const t = now();
    if (t < (player.runNoiseAt ?? 0)) return;
    player.runNoiseAt = t + 1000;
    noise(room, player, 'run');
  }

  // ---- 피 냄새 (v0.26) ----

  const SC = S?.scent;

  function stopBleeding(room, player) {
    if (!player.bleeding) return;
    player.bleeding = false;
    room?.broadcast({ t: 'bleed', id: player.id, on: false });
  }

  /** 피 흘리는 사람 발밑에 핏자국 (drop_every_ms 마다), 오래된 것은 지운다. */
  function tickScent(room, t) {
    if (!SC) return;
    room.scent ??= [];
    const before = room.scent.length;
    room.scent = room.scent.filter((s) => t - s.t < SC.trail_ms);
    for (const p of room.players.values()) {
      if (!p.bleeding || !p.online || !outdoors(p) || p.downed || t < (p.scentNext ?? 0)) continue;
      p.scentNext = t + SC.drop_every_ms;
      const s = { id: p.id, x: round(p.x), z: round(p.z), t };
      room.scent.push(s);
      const mine = room.scent.filter((x) => x.id === p.id);
      if (mine.length > SC.max_points) room.scent.splice(room.scent.indexOf(mine[0]), 1);
      room.broadcast({ t: 'scent', id: p.id, x: s.x, z: s.z, ms: SC.trail_ms });
    }
    return room.scent.length !== before;
  }

  /** 아무도 쫓지 않는 크리처가 따라갈 핏자국 (follow_range 안의 가장 새 것). */
  function scentFor(room, c) {
    let best = null;
    for (const s of room.scent ?? []) {
      if (Math.hypot(s.x - c.x, s.z - c.z) > SC.follow_range) continue;
      if (!best || s.t > best.t) best = s;
    }
    return best;
  }

  // ---- 거점: 상자 · 침대 (v0.25) ----

  const B = S?.base;
  /** 뚫린 곳을 모두 막은 빈집. */
  const isBase = (room, h) => h.breaches.length > 0 && h.breaches.every((b) => boardHp(room, b) > 0);
  const stashAt = (h) => toWorld(h, B.stash[0], B.stash[1]);
  const bedAt = (h) => toWorld(h, B.bed[0], B.bed[1]);

  function handleStash(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const h = S?.houseById.get(msg.h);
    if (!h || !B) return fail(ErrorCode.badItem);
    const at = stashAt(h);
    if (player.home || Math.hypot(player.x - at.x, player.z - at.z) > B.range + 0.3) return fail(ErrorCode.tooFar);
    // v0.28.16 집 안 상자는 판자를 다 대지 않아도 연다 (침대는 그대로 거점이어야 잔다).
    room.stash ??= {};
    const box = (room.stash[h.id] ??= []);
    if (msg.op === 'put') {
      const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
      if (!slot) return fail(ErrorCode.badItem);
      const id = slot.id;
      const entry = box.find((e) => e.id === id);
      if (!entry && box.length >= B.slots + (room.stashExtra ?? 0)) return fail(ErrorCode.stashFull);
      const n = Math.min(Number.isInteger(msg.n) && msg.n > 0 ? msg.n : slot.n, slot.n, B.max - (entry?.n ?? 0));
      if (n <= 0) return fail(ErrorCode.stashFull);
      removeAt(player.slots, msg.slot, n);
      if (entry) entry.n += n;
      else box.push({ id, n });
    } else if (msg.op === 'take') {
      const entry = box.find((e) => e.id === msg.id);
      if (!entry) return fail(ErrorCode.badItem);
      const want = Math.min(Number.isInteger(msg.n) && msg.n > 0 ? msg.n : entry.n, entry.n);
      let got = 0;
      while (got < want && addItem(player.slots, entry.id, 1, cfg, data.limitOf)) got++;
      if (got === 0) return fail(ErrorCode.inventoryFull);
      entry.n -= got;
      if (entry.n <= 0) box.splice(box.indexOf(entry), 1);
    } else {
      return fail(ErrorCode.badMessage);
    }
    sendInventory(player);
    send(ctx.ws, { t: 'stash', rid: msg.rid, h: h.id, items: box.map((e) => ({ ...e })) });
    room.broadcast({ t: 'stash', h: h.id, items: box.map((e) => ({ ...e })) }, player.id);
    act(room, player, 'stash', h.id);
    saveRoom(room);
  }

  function handleSleep(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!msg.on) {
      wake(room, player);
      return send(ctx.ws, { t: 'slept', rid: msg.rid, on: false });
    }
    if (player.downed) return fail(ErrorCode.downed);
    const h = B ? houseAt(player.x, player.z) : null;
    const bed = h ? bedAt(h) : null;
    if (!h || Math.hypot(player.x - bed.x, player.z - bed.z) > B.range + 0.3) return fail(ErrorCode.tooFar);
    if (!isBase(room, h)) return fail(ErrorCode.notBase);
    if (hpOf(player) >= maxOf(player)) return fail(ErrorCode.hpFull);
    player.sleeping = { h: h.id, next: now() + B.sleep_regen_ms };
    send(ctx.ws, { t: 'slept', rid: msg.rid, on: true });
    room.broadcast({ t: 'sleep', id: player.id, on: true });
  }

  function wake(room, player) {
    if (!player.sleeping) return;
    delete player.sleeping;
    room.broadcast({ t: 'sleep', id: player.id, on: false });
  }

  /** 자는 사람: sleep_regen_ms 마다 체력 1, 가득 차거나 거점이 뚫리면 깬다 (낮 · 밤). */
  function tickSleep(room, t) {
    for (const p of room.players.values()) {
      const sl = p.sleeping;
      if (!sl) continue;
      const h = S.houseById.get(sl.h);
      if (!p.online || !h || !isBase(room, h)) {
        wake(room, p);
        continue;
      }
      if (t < sl.next) continue;
      sl.next = t + B.sleep_regen_ms;
      setHp(p, hpOf(p) + 1);
      sendTo(p, { t: 'hp', ...hpWire(p) });
      if (hpOf(p) >= maxOf(p)) {
        wake(room, p);
        stopBleeding(room, p);
      }
    }
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
    hunter?.onLoot(room, player);
    saveRoom(room);
  }

  // ---- 체력 · 회복 · 기절 ----

  function setHp(player, hp) {
    player.profile.hp = Math.max(0, Math.min(maxOf(player), hp));
  }

  function handleUse(ctx, msg, fail) {
    const { player } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
    const heal = slot ? S?.heal?.[slot.id] : undefined;
    // v0.28.7 먹고 마실 것: 배고픔 · 목마름을 채운다 (체력이 가득해도).
    const nour = slot ? NE?.nourish?.[slot.id] : undefined;
    if (!slot || (!heal && !nour)) return fail(ErrorCode.badItem);
    const pr = player.profile;
    const needFood = nour?.food && (pr.food ?? NE.max) < NE.max - 1;
    const needWater = nour?.water && (pr.water ?? NE.max) < NE.max - 1;
    if (hpOf(player) >= maxOf(player) && !needFood && !needWater) return fail(nour ? ErrorCode.notHungry : ErrorCode.hpFull);
    removeAt(player.slots, msg.slot, 1);
    // v0.28.8 치유사 '응급 처치': 치료 아이템이 더 채운다.
    const healed = heal ? heal + (hunter?.bonus.fx(player, 'heal') ?? 0) : 0;
    if (heal) setHp(player, hpOf(player) + healed);
    if (nour) {
      pr.food = Math.min(NE.max, (pr.food ?? NE.max) + (nour.food ?? 0));
      pr.water = Math.min(NE.max, (pr.water ?? NE.max) + (nour.water ?? 0));
      sendTo(player, needsWire(player));
    }
    sendInventory(player);
    send(ctx.ws, { t: 'hp', rid: msg.rid, ...hpWire(player), item: slot.id, heal: healed, food: nour?.food ?? 0, water: nour?.water ?? 0 });
    if ((SC?.stops ?? []).includes(slot.id) || hpOf(player) >= maxOf(player)) stopBleeding(ctx.room, player);
  }

  /** v0.28.7 회피 구르기: dodge {} → dodge_ok { ms, dist } (재사용 대기 · 쓰러짐이면 거절). */
  function handleDodge(ctx, msg, fail) {
    const { player } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const D = S.dodge;
    if (!D) return fail(ErrorCode.badMessage);
    if (player.downed || player.sleeping) return fail(ErrorCode.downed);
    const t = now();
    if (t < (player.dodgeReadyAt ?? 0)) return fail(ErrorCode.coolingDown);
    player.dodgeReadyAt = t + D.cooldown_ms * (hunter?.bonus.cooldown(player) ?? 1) * Math.max(0.4, 1 - (hunter?.bonus.fx(player, 'dodge_cd') ?? 0)) - 60;
    player.dodgeUntil = t + D.ms + 150;
    player.dodgeIframeUntil = t + D.iframe_ms + (hunter?.bonus.fx(player, 'iframe') ?? 0);
    send(ctx.ws, { t: 'dodge_ok', rid: msg.rid, ms: D.ms, dist: D.dist });
  }

  /** 구르는 중이면 그 빠르기 (m/s), 아니면 0 (server.js handleMove 가 쓴다). */
  function dodgeSpeed(player) {
    return S.dodge && now() < (player.dodgeUntil ?? 0) ? S.dodge.dist / (S.dodge.ms / 1000) : 0;
  }

  function knockOut(room, player) {
    if (player.downed) getUp(room, player, 0, true);
    garage?.unboard(player, room);
    stopBleeding(room, player);
    const lost = Math.min(S.player.ko_sol_max ?? 0, Math.floor((player.profile.sol ?? 0) * (S.player.ko_sol_rate ?? 0)));
    player.profile.sol = Math.max(0, (player.profile.sol ?? 0) - lost);
    setHp(player, maxOf(player));
    // v0.28.7 대피소에서 조금 먹고 마시고 깨어난다.
    if (NE) {
      player.profile.food = Math.max(player.profile.food ?? 0, NE.ko_refill);
      player.profile.water = Math.max(player.profile.water ?? 0, NE.ko_refill);
      sendTo(player, needsWire(player));
    }
    // v0.28.2 던전에서 기절하면 그 공략에서 빠진다.
    gates.left(room, player);
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
    // v0.28.7 구르는 동안은 맞지 않는다.
    if (t < (player.dodgeIframeUntil ?? 0)) return;
    // v0.28.9 성역 안이면 맞지 않는다.
    if ((room.sanctuaries ?? []).some((sa) => sa.until > t && Math.hypot(player.x - sa.x, player.z - sa.z) <= sa.r)) {
      room.broadcast({ t: 'guard_block', id: player.id, sanct: 1 });
      player.hurtUntil = t + (S.player.hurt_grace_ms ?? 700);
      return;
    }
    player.hurtUntil = t + (S.player.hurt_grace_ms ?? 700);
    // v0.28.5 마력 방패가 막는다.
    if (hunter?.bonus.block(player)) {
      room.broadcast({ t: 'shield_block', id: player.id, left: player.shieldHits ?? 0 });
      return;
    }
    // v0.28.8 전사 '버티기': 확률로 막는다.
    const guard = hunter?.bonus.fx(player, 'block') ?? 0;
    if (guard > 0 && random() < guard) {
      room.broadcast({ t: 'guard_block', id: player.id });
      return;
    }
    wake(room, player);
    setHp(player, hpOf(player) - damage);
    gates.onHurt(room, player, damage);
    sendTo(player, { t: 'hurt', ...hpWire(player), by });
    if (hpOf(player) > 0) {
      if (SC && !player.bleeding) {
        player.bleeding = true;
        player.scentNext = 0;
        room.broadcast({ t: 'bleed', id: player.id, on: true });
      }
      return;
    }
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
    garage?.unboard(player, room);
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
    // v0.28.8 치유사 '빠른 손'.
    const ms = Math.round(D.revive_ms * Math.max(0.3, 1 - (hunter?.bonus.fx(player, 'revive') ?? 0)));
    target.downed.doneAt = now() + ms;
    send(ctx.ws, { t: 'reviving', rid: msg.rid, id: target.id, ms });
    room.broadcast({ t: 'revive', id: target.id, by: player.id, ms });
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
          // v0.28.12 동료를 일으키면 경험치.
          hunter?.act(room, r, 'revive');
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
    tickNeeds(room, dtMs);
    if (night()) return;
    const perMs = (S.player.day_regen_per_world_hour ?? 1) * (clock.worldScale ?? 1) / HOUR_MS;
    for (const p of room.players.values()) {
      if (!p.online || p.downed || hpOf(p) >= maxOf(p) || starving(p)) continue;
      p.regenAcc = (p.regenAcc ?? 0) + perMs * dtMs * (1 + (hunter?.bonus.fx(p, 'regen') ?? 0));
      if (p.regenAcc >= 1) {
        const add = Math.floor(p.regenAcc);
        p.regenAcc -= add;
        setHp(p, hpOf(p) + add);
        sendTo(p, { t: 'hp', ...hpWire(p) });
        if (hpOf(p) >= maxOf(p)) stopBleeding(room, p);
      }
    }
  }

  /** v0.28.7 배고픔 · 목마름이 준다 (접속 중 · 쓰러지지 않았을 때). 바닥나면 체력을 조금씩 잃는다. */
  function tickNeeds(room, dtMs) {
    if (!NE) return;
    const hours = (dtMs * (clock.worldScale ?? 1)) / HOUR_MS;
    for (const p of room.players.values()) {
      if (!p.online || p.downed || p.sleeping) continue;
      const pr = p.profile;
      const before = [Math.round(pr.food ?? NE.max), Math.round(pr.water ?? NE.max)];
      // v0.28.8 치유사 '절제': 덜 준다.
      const slow = Math.max(0.2, 1 - (hunter?.bonus.fx(p, 'needs') ?? 0));
      pr.food = Math.max(0, (pr.food ?? NE.max) - NE.food_per_world_hour * hours * slow);
      pr.water = Math.max(0, (pr.water ?? NE.max) - NE.water_per_world_hour * hours * slow);
      if (Math.round(pr.food) !== before[0] || Math.round(pr.water) !== before[1]) sendTo(p, needsWire(p));
      if (starving(p)) {
        p.starveAcc = (p.starveAcc ?? 0) + hours;
        if (p.starveAcc >= NE.starve_world_hours) {
          p.starveAcc = 0;
          setHp(p, hpOf(p) - 1);
          sendTo(p, { t: 'hurt', ...hpWire(p), by: 'starve' });
          if (hpOf(p) <= 0) knockOut(room, p);
        }
      } else p.starveAcc = 0;
    }
  }

  // ---- 크리처 ----

  // f: 1 = 날아가는 중 (들이받혀서), 2 = 넘어져 있음.
  // v0.28.16 새로 나타나는 크리처: 기어 나오는 동안 (riseUntil) 맞지도 · 움직이지도 · 때리지도 않는다.
  const riseMs = () => (Number.isFinite(cfg.creatureRiseMs) ? cfg.creatureRiseMs : (S.creatures?.rise_ms ?? 0));
  const rising = (c) => (c.riseUntil ?? 0) > now();
  const creatureWire = (c) => {
    const w = { id: c.id, k: c.k, x: round(c.x), z: round(c.z), yaw: round(c.yaw), hp: c.hp, a: c.attackAt > now() - 350 ? 1 : 0, f: c.kb ? 1 : (c.downUntil ?? 0) > now() ? 2 : 0 };
    // v0.28 게이트 크리처: 게이트 id · 최대 hp · 우두머리 이름 · 크기.
    if (c.g || c.brk) {
      w.g = c.g ?? '';
      w.m = c.max ?? c.hp;
    }
    if (c.boss) {
      w.b = c.boss;
      w.s = c.scale ?? 1;
    }
    return w;
  };
  const broadcastCreatures = (room) => room.broadcast({ t: 'creatures', st: now(), c: [...(room.creatures?.values() ?? [])].map(creatureWire) });
  const guardians = createGuardians({ data, worldMs, random, kill: (room, c, by) => kill(room, c, by), armorOf: (c) => S.creatures.kinds[c.k]?.armor ?? 0 });
  const gates = createGates({ data, cfg, random, now, send, sendTo, sendInventory, sendProfile, saveRoom, dropAt, hunter, inShop, canStand: (x, z, def) => canStand(x, z, def), pickEntry, rollLoot, broadcastCreatures, teleport, shelter, riseMs: () => riseMs() });

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
    // v0.28.9 대치유사 '성역': 크리처가 들어오지 못한다.
    const t = now();
    for (const sa of room.sanctuaries ?? []) if (sa.until > t) lights.push({ x: sa.x, z: sa.z, r: sa.r });
    return { blocks, lights, traps, room };
  }

  function canStand(x, z, def) {
    // v0.28.2 게이트 던전 안이면 그 지도 (바닥 · 기둥 · 잔해).
    const inDungeon = def.room ? gates.standAt(def.room, x, z) : null;
    if (inDungeon !== null) return inDungeon && !def.lights.some((l) => Math.hypot(x - l.x, z - l.z) < l.r);
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
      const c = { id: `z${room.creatureSeq}`, k: kind.k, x, z, yaw: Math.atan2(player.x - x, player.z - z), hp: kind.hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {}, riseUntil: now() + riseMs() };
      room.creatures.set(c.id, c);
      return c;
    }
    return null;
  }

  function kill(room, c, by) {
    room.creatures.delete(c.id);
    room.broadcast({ t: 'creature_dead', id: c.id, by, x: round(c.x), z: round(c.z) });
    // v0.28 헌터: 처치 점수 · 마석 · 의뢰.
    const killRes = by ? hunter?.onKill(room, room.players.get(by), c) : null;
    // v0.28.8 암살자 '사냥감': 쓰러뜨리면 확률로 체력 1.
    const killer = by ? room.players.get(by) : null;
    const reap = killer ? (hunter?.bonus.fx(killer, 'kill_heal') ?? 0) : 0;
    if (reap > 0 && !killer.downed && hpOf(killer) < maxOf(killer) && random() < reap) {
      setHp(killer, hpOf(killer) + 1);
      sendTo(killer, { t: 'hp', ...hpWire(killer), reap: 1 });
    }
    gates.onKill(room, c, by, killRes);
    const kind = S.creatures.kinds[c.k];
    if (kind && random() < (kind.drop_chance ?? 1)) {
      const e = pickEntry(kind.drops, random);
      const [lo, hi] = e.n ?? [1, 1];
      dropAt(room, e.id, lo + Math.floor(random() * (hi - lo + 1)), c.x, c.z);
    }
  }

  // ---- v0.27 보급 상자 ----

  const SU = S?.supply;
  const supplyWire = (room, c) => ({ id: c.id, x: round(c.x), z: round(c.z), left: Math.max(0, c.land - now()) });

  /** 상자를 떨어뜨릴 자리: 바깥에 있는 사람 하나에게서 dist m, 걸을 수 있는 땅 (집 · 안전한 곳 밖). */
  function supplySpot(room, people, def) {
    const p = people[Math.floor(random() * people.length)];
    const [lo, hi] = SU.dist;
    for (let i = 0; i < 30; i++) {
      const a = random() * Math.PI * 2;
      const r = lo + random() * (hi - lo);
      const x = p.x + Math.cos(a) * r;
      const z = p.z + Math.sin(a) * r;
      if (groundProblem(data, x, z) !== null || !isLand(data, x, z) || safeAt(x, z) || houseAt(x, z, 1.5) || !canStand(x, z, def)) continue;
      return { x, z };
    }
    return null;
  }

  /** 지키던 크리처: 상자 둘레에 guards 마리 (방 상한 안에서). */
  function guard(room, c, def, t) {
    const kinds = Object.entries(S.creatures.kinds).map(([k, v]) => ({ k, ...v }));
    let n = 0;
    for (let i = 0; i < 20 && n < SU.guards && room.creatures.size < S.creatures.max_per_room; i++) {
      const a = random() * Math.PI * 2;
      const r = 3 + random() * 4;
      const x = c.x + Math.cos(a) * r;
      const z = c.z + Math.sin(a) * r;
      if (!canStand(x, z, def) || groundProblem(data, x, z) !== null) continue;
      const kind = pickEntry(kinds, random);
      room.creatureSeq = (room.creatureSeq ?? 0) + 1;
      const g = { id: `z${room.creatureSeq}`, k: kind.k, x, z, yaw: Math.atan2(c.x - x, c.z - z), hp: kind.hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {}, riseUntil: now() + riseMs() };
      room.creatures.set(g.id, g);
      n++;
    }
    return n;
  }

  /** npcTick 마다 (tick 안): 밤이면 때맞춰 떨어뜨리고, 땅에 닿으면 알리고, 다가오면 지키던 크리처. 해가 뜨면 회수. 바뀌었으면 true. */
  function tickSupply(room, t, people, def) {
    if (!SU) return false;
    room.supply ??= new Map();
    if (!night()) {
      for (const c of room.supply.values()) room.broadcast({ t: 'supply_gone', s: c.id, by: 0 });
      room.supply.clear();
      room.supplyNextAt = undefined;
      return false;
    }
    let changed = false;
    if (room.supplyNextAt === undefined) {
      room.supplyNextAt = t + (Number.isFinite(cfg.supplyFirstMs) ? cfg.supplyFirstMs : SU.first_ms);
      room.supplyCount = 0;
    }
    if (t >= room.supplyNextAt && room.supplyCount < SU.per_night) {
      const spot = people.length ? supplySpot(room, people, def) : null;
      if (!spot) room.supplyNextAt = t + 10000;
      else {
        room.supplyNextAt = t + SU.every_ms;
        room.supplyCount++;
        room.supplySeq = (room.supplySeq ?? 0) + 1;
        const fall = Number.isFinite(cfg.supplyFallMs) ? cfg.supplyFallMs : SU.fall_ms;
        const c = { id: `s${room.supplySeq}`, x: spot.x, z: spot.z, land: now() + fall, landed: false, guarded: false };
        room.supply.set(c.id, c);
        room.broadcast({ t: 'supply', s: supplyWire(room, c) });
      }
    }
    for (const c of room.supply.values()) {
      if (!c.landed && now() >= c.land) {
        c.landed = true;
        room.broadcast({ t: 'supply_land', s: c.id });
      }
      if (c.landed && !c.guarded && people.some((p) => Math.hypot(p.x - c.x, p.z - c.z) < SU.guard_near)) {
        c.guarded = true;
        if (guard(room, c, def, t) > 0) changed = true;
      }
    }
    return changed;
  }

  function handleSupply(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!SU) return fail(ErrorCode.badItem);
    if (player.downed) return fail(ErrorCode.downed);
    const c = room.supply?.get(msg.s);
    // 이미 누가 열었다 (먼저 연 사람이 갖는다).
    if (!c) return fail(ErrorCode.alreadyLooted);
    if (now() < c.land) return fail(ErrorCode.supplyFalling);
    if (player.home || inShop(player) || Math.hypot(player.x - c.x, player.z - c.z) > SU.range + 0.3) return fail(ErrorCode.tooFar);
    room.supply.delete(c.id);
    const found = rollLoot(SU.loot, random);
    const got = [];
    for (const it of found) {
      if (addItem(player.slots, it.id, it.n, cfg, data.limitOf)) got.push(it);
      else dropAt(room, it.id, it.n, player.x, player.z);
    }
    sendInventory(player);
    send(ctx.ws, { t: 'supply_got', rid: msg.rid, s: c.id, items: found, got });
    room.broadcast({ t: 'supply_gone', s: c.id, by: player.id });
    act(room, player, 'loot', 'supply');
    hunter?.onSupply(room, player);
    saveRoom(room);
  }

  /** npcTick 마다. 바뀌었으면 true (방송은 여기서). */
  function tick(room, dtMs, t) {
    if (!S) return;
    room.creatures ??= new Map();
    tickDowned(room, t);
    tickJobs(room, dtMs, t);
    tickSleep(room, t);
    tickScent(room, t);
    const dt = dtMs / 1000;
    let changed = false;
    const day = !night();
    if (day) {
      tickSupply(room, t, [], null);
      // 해가 뜨면 흩어진다 (게이트 · 브레이크 크리처는 남는다).
      for (const c of [...room.creatures.values()]) {
        if (c.g || c.brk) continue;
        room.creatures.delete(c.id);
        room.broadcast({ t: 'creature_dead', id: c.id, by: 0, x: round(c.x), z: round(c.z), sun: true });
        changed = true;
      }
    }
    // v0.28.5 그림자 걸음 중인 사람은 크리처가 보지 못한다.
    // (사라짐 · 나타남 · 게이트 · 보급은 숨은 사람도 센다 — 숨었다고 둘레 크리처가 모두 사라지면 안 된다.)
    const people = [...room.players.values()].filter((p) => outdoors(p) && !p.downed);
    const seen = people.filter((p) => !hunter?.bonus.hidden(p));
    const def = defenses(room);
    if (gates.tick(room, t, people, def)) changed = true;
    // v0.28.2 가디언: 쏘기 · 부활, 쓰러진 주민 일어나기 (낮 · 밤).
    if (guardians.tick(room, t)) changed = true;
    if (day && room.creatures.size === 0) {
      if (changed) broadcastCreatures(room);
      return;
    }
    if (!day && tickSupply(room, t, people, def)) changed = true;
    // 나타나기 (밤만).
    if (!day && t >= (room.nextCreatureAt ?? 0)) {
      room.nextCreatureAt = t + (S.creatures.spawn_every_ms ?? 9000) * (cfg.creatureSpawnScale ?? 1);
      for (const p of people) {
        if (room.creatures.size >= S.creatures.max_per_room) break;
        if (safeAt(p.x, p.z) || p.dungeon) continue;
        const near = [...room.creatures.values()].filter((c) => Math.hypot(c.x - p.x, c.z - p.z) < S.creatures.despawn_far).length;
        if (near < S.creatures.per_player && spawnNear(room, p, def, t)) changed = true;
      }
    }
    for (const c of [...room.creatures.values()]) {
      const kind = S.creatures.kinds[c.k];
      // 들이받혀 날아가는 중 · 넘어져 있는 동안은 움직이지도 때리지도 못한다.
      if (c.kb) {
        stepKnock(room, c, dt, t, def);
        changed = true;
        continue;
      }
      if ((c.downUntil ?? 0) > t || (c.stunUntil ?? 0) > t || cfg.creatureFreeze || rising(c)) continue;
      if (c.wasDown) {
        c.wasDown = false;
        changed = true;
      }
      // 아무도 가까이 없으면 사라진다.
      let nearD = Infinity;
      for (const p of people) nearD = Math.min(nearD, Math.hypot(p.x - c.x, p.z - c.z));
      // 게이트 크리처는 게이트를 지킨다 (사라지지 않고, 아무도 없으면 제자리).
      if (c.g && nearD > S.creatures.despawn_far) continue;
      if (nearD > S.creatures.despawn_far) {
        room.creatures.delete(c.id);
        room.broadcast({ t: 'creature_dead', id: c.id, by: 0, x: round(c.x), z: round(c.z), gone: true });
        changed = true;
        continue;
      }
      // 쫓을 사람은 보이는 사람 중에서 (그림자 걸음 중이면 못 본다 — 제자리).
      let best = null;
      let bestD = Infinity;
      for (const p of seen) {
        const d = Math.hypot(p.x - c.x, p.z - c.z);
        if (d < bestD) {
          bestD = d;
          best = p;
        }
      }
      if (!best) {
        if (c.target) {
          c.target = 0;
          changed = true;
        }
        continue;
      }
      // v0.28.5 게이트 우두머리 패턴 (내려치기 · 돌진 · 소환).
      if (c.boss && bossStep(room, c, best, bestD, t, dt, def)) {
        changed = true;
        continue;
      }
      // v0.28.2 사람보다 가까운 가디언 · 밖의 주민을 노린다 (소리를 듣고 쫓는 중이 아니면).
      const ally = (c.alertUntil ?? 0) > t ? null : guardians.allyNear(room, c, kind, bestD, safeAt);
      if (ally) {
        if (moveToward(c, { x: ally.x, z: ally.z }, kind.reach * 0.8, kind.speed * dt, (x, z) => canStand(x, z, def))) changed = true;
        c.yaw = Math.atan2(ally.x - c.x, ally.z - c.z);
        if (Math.hypot(ally.x - c.x, ally.z - c.z) <= kind.reach + 0.3 && t >= c.nextAttack) {
          c.nextAttack = t + kind.attack_ms;
          c.attackAt = t;
          guardians.hitAlly(room, ally, Math.round(kind.damage * (c.dmg ?? 1)));
          changed = true;
        }
        continue;
      }
      // 소리를 들었으면 소리 낸 사람을 쫓는다 (aggro 밖이라도).
      const alerted = (c.alertUntil ?? 0) > t ? seen.find((p) => p.id === c.alertBy) : null;
      if (alerted) {
        best = alerted;
        bestD = Math.hypot(alerted.x - c.x, alerted.z - c.z);
      }
      const aggro = (c.target === best.id ? kind.aggro * 1.5 : kind.aggro) * (best.bleeding && SC ? SC.aggro_mult : 1);
      c.target = (bestD <= aggro || alerted) && !safeAt(best.x, best.z) ? best.id : 0;
      // v0.28.2 비명이: 사람을 처음 알아채면 한 번 비명 — 둘레 크리처가 그 사람에게 몰려온다.
      if (kind.scream && c.target && !c.screamed) {
        c.screamed = true;
        let called = 0;
        for (const o of room.creatures.values()) {
          if (o === c || Math.hypot(o.x - c.x, o.z - c.z) > kind.scream) continue;
          o.alertUntil = t + (N?.alert_ms ?? 8000);
          o.alertBy = c.target;
          called++;
        }
        room.broadcast({ t: 'creature_scream', id: c.id, x: round(c.x), z: round(c.z), n: called });
      }
      // 아직 알아채지 못했어도 사람 냄새를 따라 천천히 (wander) 다가온다.
      // 아직 알아채지 못했으면 핏자국을 따라오거나 (냄새), 사람 냄새를 따라 천천히 (wander) 다가온다.
      const trail = !c.target && SC && !c.inside ? scentFor(room, c) : null;
      const step = (c.target ? kind.speed : kind.speed * (trail ? SC.follow_speed : (S.creatures.wander ?? 0.45))) * dt;
      if (safeAt(best.x, best.z)) continue;
      const ph = houseAt(best.x, best.z); // 사람이 있는 빈집 (밖이면 null)
      const ch = c.inside ? S.houseById.get(c.inside) : null; // 크리처가 있는 빈집
      const stand = ch ? (x, z) => standInside(ch, x, z, def) : (x, z) => canStand(x, z, def);
      if (ph === ch) {
        // 같은 곳 (둘 다 밖 · 같은 집 안): 쫓는다. 집 안에서는 방 사이 문틈으로, 밖에서는 가까운 집을 둘러서.
        let aim = trail ? { x: trail.x, z: trail.z } : { x: best.x, z: best.z };
        let stop = trail ? 0 : kind.reach * 0.8;
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
        // 탈것을 타고 달리는 사람(ram.immune_speed 넘게)은 붙잡지 못한다.
        const mover = best.passenger ? room.players.get(best.passenger.d) : best;
        const driving = mover?.mount && Math.hypot(mover.vx ?? 0, mover.vz ?? 0) > (RAM?.immune_speed ?? 2.0);
        if (c.target && sameRoom && !driving && Math.hypot(best.x - c.x, best.z - c.z) <= kind.reach && t >= c.nextAttack) {
          c.nextAttack = t + kind.attack_ms;
          c.attackAt = t;
          // v0.28.2 독침이는 멀리서 침을 뱉는다 (그림).
          if (kind.spit) room.broadcast({ t: 'creature_spit', id: c.id, to: best.id });
          hurt(room, best, Math.round(kind.damage * (c.dmg ?? 1)), c.k);
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

  // ---- 탈것으로 들이받기 (v0.26) ----

  const RAM = S?.ram;

  /** 날아가는 크리처를 지면에서 미끄러뜨린다. 벽에 부딪히면 추가 피해, 멈추면 쓰러져 있다. 죽었으면 멈춘 뒤에 쓰러뜨린다. */
  function stepKnock(room, c, dt, t, def) {
    const kb = c.kb;
    const sp = Math.hypot(kb.vx, kb.vz);
    const nx = c.x + kb.vx * dt;
    const nz = c.z + kb.vz * dt;
    const h = c.inside ? S.houseById.get(c.inside) : null;
    const solid = h ? !standInside(h, nx, nz, { lights: [] }) : !isLand(data, nx, nz) || groundProblem(data, nx, nz) === 'building' || safeAt(nx, nz) || def.blocks.some((b) => Math.hypot(nx - b.x, nz - b.z) < b.r);
    let stop = false;
    if (solid) {
      // 벽 · 건물 · 바리케이드에 쾅.
      const dmg = Math.ceil(sp * sp * RAM.wall_k);
      c.hp -= dmg;
      room.broadcast({ t: 'creature_hit', id: c.id, hp: Math.max(0, c.hp), by: kb.by, wall: dmg, x: round(c.x), z: round(c.z) });
      stop = true;
    } else {
      c.x = nx;
      c.z = nz;
      const ns = Math.max(0, sp - RAM.slide_decel * dt);
      kb.vx *= sp > 0 ? ns / sp : 0;
      kb.vz *= sp > 0 ? ns / sp : 0;
      stop = ns <= 0.05;
    }
    if (!stop) return;
    c.kb = null;
    if (c.hp <= 0) return kill(room, c, kb.by);
    c.downUntil = t + RAM.down_ms;
    c.wasDown = true;
    c.target = 0;
  }

  function handleRam(ctx, msg, fail) {
    const { player, room } = ctx;
    const t = now();
    const ride = garage?.mounted(player);
    if (!RAM || !ride || ride.kind === 'boat') return fail(ErrorCode.badVehicle);
    const c = room.creatures?.get(msg.c);
    if (!c || c.kb) return;
    const reach = Math.max(Math.abs(ride.model.anchors?.axle_f?.[2] ?? 0.7), Math.abs(ride.model.anchors?.axle_r?.[2] ?? 0.6)) + RAM.reach + 0.6;
    if (Math.hypot(c.x - player.x, c.z - player.z) > reach) return fail(ErrorCode.tooFar);
    c.ramAt ??= {};
    if (t < (c.ramAt[player.id] ?? 0)) return;
    c.ramAt[player.id] = t + RAM.cooldown_ms;
    // 빠르기는 그 탈것 최고 속도까지만 믿는다. 방향은 진행 방향 + 차에서 밀려나는 쪽.
    const v = Math.max(0, Math.min(Number(msg.s) || 0, ride.stats.top * 1.1));
    let hx = Number(msg.dx) || 0;
    let hz = Number(msg.dz) || 0;
    const hl = Math.hypot(hx, hz) || 1;
    hx /= hl;
    hz /= hl;
    const ax = c.x - player.x;
    const az = c.z - player.z;
    const al = Math.hypot(ax, az) || 1;
    let dx = hx * 0.8 + (ax / al) * 0.5;
    let dz = hz * 0.8 + (az / al) * 0.5;
    const dl = Math.hypot(dx, dz) || 1;
    dx /= dl;
    dz /= dl;
    const kind = S.creatures.kinds[c.k];
    const m = kind.mass ?? 70;
    const M = ride.mass;
    c.target = player.id;
    if (v >= RAM.fast) {
      const u = ((1 + RAM.restitution) * M) / (M + m) * v;
      const dmg = Math.ceil(u * u * RAM.dmg_k * (ride.ramDmg ?? 1));
      c.hp -= dmg;
      c.kb = { vx: dx * u, vz: dz * u, by: player.id };
      c.yaw = Math.atan2(-dx, -dz);
      const slow = ((1 + RAM.restitution) * m) / (M + m);
      send(ctx.ws, { t: 'rammed', rid: msg.rid, c: c.id, hard: true, u: round(u), dmg, slow: round(slow) });
      room.broadcast({ t: 'creature_hit', id: c.id, hp: Math.max(0, c.hp), by: player.id, ram: round(u), dx: round(dx), dz: round(dz) });
      garage.damage(player, room, m * u * RAM.veh_k * (ride.ramWear ?? 1), 'ram');
    } else {
      // 느리면 넘어진다 (조금 밀려나고, 탈것은 확 느려진다).
      const push = 0.4 + v * 0.15;
      const nx = c.x + dx * push;
      const nz = c.z + dz * push;
      if (isLand(data, nx, nz) && (c.inside || groundProblem(data, nx, nz) !== 'building')) {
        c.x = nx;
        c.z = nz;
      }
      c.downUntil = t + RAM.slow_down_ms;
      c.wasDown = true;
      send(ctx.ws, { t: 'rammed', rid: msg.rid, c: c.id, hard: false, u: 0, dmg: 0, slow: round(1 - RAM.slow_keep) });
      room.broadcast({ t: 'creature_hit', id: c.id, hp: c.hp, by: player.id, ram: 0 });
    }
    noise(room, player, 'swing');
    room.broadcast({ t: 'creatures', st: t, c: [...room.creatures.values()].map(creatureWire) });
  }

  function handleAttack(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.downed) return fail(ErrorCode.downed);
    let w = S.weapons[player.heldItem] ?? S.weapons.hands;
    // v0.28.9 직업 전용 무기는 그 직업만 (아니면 맨손).
    if (w.job && player.profile.hunter?.job !== w.job) w = S.weapons.hands;
    // v0.28.5 쏘는 무기 (석궁): 화살이 없으면 맨손.
    const ammo = w.ammo && countWhere(player.slots, (id) => id === w.ammo) > 0 ? w.ammo : null;
    if (w.ammo && !ammo) w = S.weapons.hands;
    const t = now();
    if (t < (player.attackReadyAt ?? 0)) return fail(ErrorCode.tooFast);
    // v0.28.9 광전사 '피의 광란': 공격 간격 · 피해.
    const frenzy = (player.frenzyUntil ?? 0) > t ? hunter?.bonus.activeDef('frenzy') : null;
    player.attackReadyAt = t + w.cooldown_ms * (hunter?.bonus.cooldown(player) ?? 1) * (frenzy ? 1 - frenzy.cd : 1) - 60;
    // v0.28.1 달리며 공격 (기술): 멈추지 않고 돌진해 벤다 — 사거리가 늘고, 달리는 쪽으로 조금 앞서 본다.
    const lunge = msg.run === true && hunter?.bonus.skill(player, 'run_attack');
    const reach = lunge ? (hunter.bonus.skillDef('run_attack')?.reach ?? 0) : 0;
    const ax = player.x + (lunge ? (player.vx ?? 0) * 0.15 : 0);
    const az = player.z + (lunge ? (player.vz ?? 0) * 0.15 : 0);
    act(room, player, 'swing', player.heldItem ?? '');
    wake(room, player);
    noise(room, player, 'swing');
    // 닿는 크리처 (가까운 순). 소방도끼는 cleave 만큼 한 번에 벤다.
    // v0.28.8 기술 나무: 원거리 사거리 · 근접 휩쓸기 · 화살 아끼기.
    const fx = (k) => hunter?.bonus.fx(player, k) ?? 0;
    const limit = w.range + 0.3 + reach + (w.ammo ? fx('range_ranged') : 0);
    const hits = [...(room.creatures?.values() ?? [])]
      .map((c) => ({ c, d: Math.hypot(c.x - ax, c.z - az) }))
      .filter((h) => h.d <= limit && !rising(h.c))
      .sort((a, b) => a.d - b.d)
      .slice(0, Math.max(1, (w.cleave ?? 1) + (w.ammo ? 0 : fx('cleave'))));
    if (hits.length === 0) return send(ctx.ws, { t: 'swing', rid: msg.rid, hit: '', run: lunge });
    if (ammo && !(fx('ammo_save') > 0 && random() < fx('ammo_save'))) {
      removeWhere(player.slots, (id) => id === ammo, 1);
      sendInventory(player);
    }
    const wid = w === S.weapons.hands ? 'hands' : player.heldItem;
    // v0.28.8 치명타 (암살자 '급소') · 그림자 일격 (다음 한 번은 반드시 치명타 × mult).
    const amb = (player.ambushUntil ?? 0) > t ? hunter?.bonus.activeDef('ambush') : null;
    if (amb) player.ambushUntil = 0;
    const critChance = fx('crit') + (w.crit ?? 0) + (w.ammo ? fx('crit_ranged') : 0);
    const crit = Boolean(amb) || (critChance > 0 && random() < critChance);
    const critMult = crit ? (hunter?.bonus.critBase() ?? 2) + fx('crit_mult') : 1;
    // v0.28.9 광전사 '광기': 체력이 절반 아래면 피해 +.
    const rage = hpOf(player) * 2 <= maxOf(player) ? 1 + fx('rage') : 1;
    const wmult = (hunter?.bonus.weapon(player, w) ?? 1) * critMult * (amb ? amb.mult + fx('ambush') : 1) * rage * (frenzy ? 1 + frenzy.dmg : 1);
    const target = hits[0].c;
    for (const { c, d } of hits) {
      // 힘 스탯만큼 피해 (소수는 그만큼의 확률로 1 더). v0.28.2 철갑이: 갑옷만큼 덜 받는다 (최소 1).
      // v0.28.9 그림자 사냥꾼 '처형': 30% 아래 크리처는 더 아프다.
      const exec = c.hp <= (c.max ?? c.hp) * 0.3 ? 1 + fx('execute') : 1;
      const dmg = w.damage * (hunter?.bonus.damage(player) ?? 1) * wmult * exec;
      const armor = S.creatures.kinds[c.k]?.armor ?? 0;
      const dealt = Math.max(1, Math.floor(dmg) + (random() < dmg - Math.floor(dmg) ? 1 : 0) - armor);
      c.hp -= dealt;
      gates.onDamage(room, c, player.id, dealt);
      // 맞으면 밀려난다 (못 박힌 방망이는 크게) · 비틀거린다.
      if (d > 0.01) {
        const push = w.push ?? 0.7;
        const nx = c.x + ((c.x - player.x) / d) * push;
        const nz = c.z + ((c.z - player.z) / d) * push;
        // 빈집 안이면 그 집 벽 안에서만 (밖으로 밀려나 갇히지 않게). 던전은 canStand 가 던전 지도로 본다.
        const ch = c.inside ? S.houseById.get(c.inside) : null;
        const def = defenses(room);
        if (ch ? standInside(ch, nx, nz, def) : canStand(nx, nz, def)) {
          c.x = nx;
          c.z = nz;
        }
      }
      // 비틀거림 뒤에는 잠깐 버틴다 (계속 때려 영영 묶어 두지 못하게). 우두머리는 절반만.
      let stun = 0;
      if (w.stun_ms && t >= (c.stunImmuneUntil ?? 0)) {
        stun = c.boss ? Math.round(w.stun_ms * 0.5) : w.stun_ms;
        c.stunUntil = t + stun;
        c.stunImmuneUntil = t + stun * 2.5;
      }
      room.broadcast({ t: 'creature_hit', id: c.id, hp: Math.max(0, c.hp), by: player.id, w: wid, ...(crit ? { crit: 1 } : {}), ...(ammo ? { shot: 1, sx: round(player.x), sz: round(player.z) } : {}), ...(stun ? { stun } : {}) });
    }
    send(ctx.ws, { t: 'swing', rid: msg.rid, hit: target.id, hp: Math.max(0, target.hp), run: lunge, n: hits.length, ...(crit ? { crit: 1 } : {}) });
    // v0.28.9 치유 지팡이: 맞힐 때 확률로 나와 6m 안 동료 체력 +1.
    if (w.mend_hit && random() < w.mend_hit) {
      const healed = [];
      for (const p of room.players.values()) {
        if (!p.online || p.downed || hpOf(p) >= maxOf(p) || Math.hypot(p.x - player.x, p.z - player.z) > 6) continue;
        setHp(p, hpOf(p) + 1);
        sendTo(p, { t: 'hp', ...hpWire(p), mend: 1 });
        healed.push(p.id);
      }
      if (healed.length) room.broadcast({ t: 'skill_fx', id: player.id, a: 'staff', x: round(player.x), z: round(player.z), yaw: round(player.yaw ?? 0), n: healed });
    }
    for (const { c } of hits) if (c.hp <= 0) kill(room, c, player.id);
    room.broadcast({ t: 'creatures', st: t, c: [...room.creatures.values()].map(creatureWire) });
  }

  /** v0.28.8 기술 한 대: 피해 (갑옷만큼 덜, 최소 1) · 밀쳐냄. creature_hit 에 kind (기술 id) 를 단다. */
  function strike(room, player, c, dmg, push, kind) {
    if (rising(c)) return;
    const armor = S.creatures.kinds[c.k]?.armor ?? 0;
    const dealt = Math.max(1, Math.floor(dmg) + (random() < dmg - Math.floor(dmg) ? 1 : 0) - armor);
    c.hp -= dealt;
    gates.onDamage(room, c, player.id, dealt);
    const d = Math.hypot(c.x - player.x, c.z - player.z);
    if (push > 0 && d > 0.01) {
      const nx = c.x + ((c.x - player.x) / d) * push;
      const nz = c.z + ((c.z - player.z) / d) * push;
      const ch = c.inside ? S.houseById.get(c.inside) : null;
      const def = defenses(room);
      if (ch ? standInside(ch, nx, nz, def) : canStand(nx, nz, def)) {
        c.x = nx;
        c.z = nz;
      }
    }
    room.broadcast({ t: 'creature_hit', id: c.id, hp: Math.max(0, c.hp), by: player.id, w: kind, sk: 1 });
  }

  /**
   * v0.28.8 직업 액티브 기술: skill_use { a } → skill_ok { a, cd } · 모두에게 skill_fx { id, a, x, z, yaw, ... }.
   * whirl (전사) 둘레 r m 모두 무기 피해 × mult · 밀쳐냄 / ambush (암살자) ms 안 다음 공격이 치명타 × mult /
   * pierce (사수) 석궁을 들고 보는 쪽 len m · 폭 width 의 모두에게 석궁 피해 × mult (화살 1) / mend (치유사) 나와 r m 안 동료 체력 + heal · 지혈.
   */
  function handleSkill(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const a = typeof msg.a === 'string' ? msg.a : '';
    const def = hunter?.bonus.activeDef(a);
    if (!def || !hunter.bonus.active(player, a)) return fail(ErrorCode.noActive);
    if (player.downed || player.sleeping) return fail(ErrorCode.downed);
    const t = now();
    player.skReady ??= {};
    if (t < (player.skReady[a] ?? 0)) return fail(ErrorCode.coolingDown);
    const fx = (k) => hunter.bonus.fx(player, k);
    const fwd = { x: -Math.sin(player.yaw ?? 0), z: -Math.cos(player.yaw ?? 0) };
    const extra = {};
    const struck = [];
    if (a === 'whirl') {
      const held = S.weapons[player.heldItem];
      const w = held && !held.ammo && !(held.job && player.profile.hunter?.job !== held.job) ? held : S.weapons.hands;
      const dmg = w.damage * hunter.bonus.damage(player) * hunter.bonus.weapon(player, w) * def.mult * (1 + fx('whirl'));
      const r = def.r + fx('whirl_r');
      for (const c of [...(room.creatures?.values() ?? [])]) {
        if (Math.hypot(c.x - player.x, c.z - player.z) > r) continue;
        strike(room, player, c, dmg, def.push, 'whirl');
        struck.push(c);
      }
      extra.r = r;
    } else if (a === 'ambush') {
      player.ambushUntil = t + def.ms;
      extra.ms = def.ms;
    } else if (a === 'pierce') {
      const w = S.weapons[player.heldItem];
      if (!w?.ammo || (w.job && player.profile.hunter?.job !== w.job) || countWhere(player.slots, (id) => id === w.ammo) <= 0) return fail(ErrorCode.noAmmo);
      removeWhere(player.slots, (id) => id === w.ammo, 1);
      sendInventory(player);
      const len = def.len + fx('range_ranged');
      const dmg = w.damage * hunter.bonus.damage(player) * hunter.bonus.weapon(player, w) * def.mult * (1 + fx('pierce'));
      for (const c of [...(room.creatures?.values() ?? [])]) {
        const rx = c.x - player.x;
        const rz = c.z - player.z;
        const along = rx * fwd.x + rz * fwd.z;
        if (along < 0 || along > len || Math.abs(rx * fwd.z - rz * fwd.x) > def.width + fx('pierce_w')) continue;
        strike(room, player, c, dmg, 0.3, 'pierce');
        struck.push(c);
      }
      extra.len = len;
      extra.w = def.width + fx('pierce_w');
    } else if (a === 'mend') {
      const amount = def.heal + fx('mend');
      const healed = [];
      for (const p of room.players.values()) {
        if (!p.online || Math.hypot(p.x - player.x, p.z - player.z) > def.r) continue;
        // v0.28.9 대치유사 '부활의 빛': 쓰러진 동료를 바로 일으킨다.
        if (p.downed) {
          if (fx('mend_revive') > 0 && p !== player) {
            setHp(p, Math.max(D?.revive_hp ?? 1, amount));
            p.hurtUntil = now() + 2000;
            getUp(room, p, player.id, false);
            sendTo(p, { t: 'hp', ...hpWire(p), mend: amount });
            healed.push(p.id);
          }
          continue;
        }
        setHp(p, hpOf(p) + amount);
        sendTo(p, { t: 'hp', ...hpWire(p), mend: amount });
        stopBleeding(room, p);
        healed.push(p.id);
      }
      extra.r = def.r;
      extra.n = healed;
    } else if (a === 'frenzy') {
      player.frenzyUntil = t + def.ms;
      extra.ms = def.ms;
    } else if (a === 'shadow_dash') {
      // 보는 쪽으로 서 있을 수 있는 데까지 (0.4m 씩), 지나간 길 둘레의 크리처를 벤다.
      if (houseAt(player.x, player.z)) return fail(ErrorCode.tooFar);
      const def2 = defenses(room);
      let dist = 0;
      for (let d = 0.4; d <= def.len + 1e-6; d += 0.4) {
        const nx = player.x + fwd.x * d;
        const nz = player.z + fwd.z * d;
        if (!canStand(nx, nz, { ...def2, lights: [] }) || houseAt(nx, nz)) break;
        dist = d;
      }
      if (dist < 0.8) return fail(ErrorCode.tooFar);
      const held = S.weapons[player.heldItem];
      const w = held && !held.ammo && !(held.job && player.profile.hunter?.job !== held.job) ? held : S.weapons.hands;
      const dmg = w.damage * hunter.bonus.damage(player) * hunter.bonus.weapon(player, w) * def.mult;
      const sx = player.x;
      const sz = player.z;
      for (const c of [...(room.creatures?.values() ?? [])]) {
        const rx = c.x - sx;
        const rz = c.z - sz;
        const along = rx * fwd.x + rz * fwd.z;
        if (along < -0.5 || along > dist + 0.8 || Math.abs(rx * fwd.z - rz * fwd.x) > def.width) continue;
        strike(room, player, c, dmg, 0.6, 'shadow_dash');
        struck.push(c);
      }
      player.x = sx + fwd.x * dist;
      player.z = sz + fwd.z * dist;
      player.dodgeIframeUntil = t + 350;
      player.dodgeUntil = t + 600;
      sendTo(player, { t: 'correct', x: player.x, y: player.y, z: player.z });
      room.dirty = true;
      extra.sx = round(sx);
      extra.sz = round(sz);
      extra.len = round(dist);
    } else if (a === 'arrow_rain') {
      const w = S.weapons[player.heldItem];
      if (!w?.ammo || (w.job && player.profile.hunter?.job !== w.job) || countWhere(player.slots, (id) => id === w.ammo) <= 0) return fail(ErrorCode.noAmmo);
      removeWhere(player.slots, (id) => id === w.ammo, Math.min(def.ammo ?? 1, countWhere(player.slots, (id) => id === w.ammo)));
      sendInventory(player);
      const cx = player.x + fwd.x * def.dist;
      const cz = player.z + fwd.z * def.dist;
      const dmg = w.damage * hunter.bonus.damage(player) * hunter.bonus.weapon(player, w) * def.mult;
      for (const c of [...(room.creatures?.values() ?? [])]) {
        if (Math.hypot(c.x - cx, c.z - cz) > def.r) continue;
        strike(room, player, c, dmg, 0.2, 'arrow_rain');
        struck.push(c);
      }
      extra.cx = round(cx);
      extra.cz = round(cz);
      extra.r = def.r;
    } else if (a === 'sanctuary') {
      room.sanctuaries = (room.sanctuaries ?? []).filter((sa) => sa.until > t);
      room.sanctuaries.push({ x: player.x, z: player.z, r: def.r, until: t + def.ms, by: player.id });
      extra.r = def.r;
      extra.ms = def.ms;
    } else {
      return fail(ErrorCode.noActive);
    }
    player.skReady[a] = t + Math.max(1000, def.cooldown_ms - (a === 'ambush' ? fx('ambush_cd') : 0));
    wake(room, player);
    if (!['mend', 'ambush', 'frenzy', 'sanctuary'].includes(a)) noise(room, player, 'swing');
    send(ctx.ws, { t: 'skill_ok', rid: msg.rid, a, cd: player.skReady[a] - t, n: struck.length });
    room.broadcast({ t: 'skill_fx', id: player.id, a, x: round(player.x), z: round(player.z), yaw: round(player.yaw ?? 0), ...extra });
    for (const c of struck) if (c.hp <= 0 && room.creatures.has(c.id)) kill(room, c, player.id);
    if (struck.length) room.broadcast({ t: 'creatures', st: t, c: [...room.creatures.values()].map(creatureWire) });
  }

  /** v0.28.5 우두머리 패턴: 이번 틱을 우두머리가 썼으면 true (평소 걸음 · 공격을 건너뛴다). */
  function bossStep(room, c, target, targetD, t, dt, def) {
    const B = data.hunter?.gates?.boss_skills;
    if (!B) return false;
    const victims = () => [...room.players.values()].filter((p) => p.online && !p.downed && !hunter?.bonus.hidden(p));
    // 소환: 체력이 기준 아래로 떨어질 때마다 (포효 · 부하가 기어 나온다).
    const frac = c.hp / Math.max(1, c.max ?? c.hp);
    c.summoned ??= 0;
    // v0.28.16 포효 (windup_ms) 동안 나올 자리를 붉게 보여 주고, 그 뒤에 부하가 기어 나온다 (riseUntil 동안은 맞지도 · 때리지도 않는다).
    if (c.summonCast) {
      if (t < c.summonCast.at) return true;
      for (const sp of c.summonCast.spots) {
        const kind = S.creatures.kinds[B.summon.k];
        room.creatureSeq = (room.creatureSeq ?? 0) + 1;
        const hp = kind.hp;
        room.creatures.set(`z${room.creatureSeq}`, { id: `z${room.creatureSeq}`, k: B.summon.k, x: sp.x, z: sp.z, yaw: c.yaw, hp, max: hp, target: target?.id ?? 0, nextAttack: 0, attackAt: 0, trapAt: {}, g: c.g, dmg: c.dmg ?? 1, riseUntil: t + riseMs() });
      }
      c.summonCast = null;
      c.nextCast = Math.max(c.nextCast ?? 0, t + 1500);
      return true;
    }
    if (B.summon && c.summoned < B.summon.hp_at.length && frac <= B.summon.hp_at[c.summoned]) {
      c.summoned++;
      const spots = [];
      for (let i = 0; i < B.summon.n; i++) {
        for (let k = 0; k < 8; k++) {
          const a = random() * Math.PI * 2;
          const x = c.x + Math.cos(a) * (1.5 + random() * 1.5);
          const z = c.z + Math.sin(a) * (1.5 + random() * 1.5);
          if (!canStand(x, z, def)) continue;
          spots.push({ x, z });
          break;
        }
      }
      const ms = B.summon.windup_ms ?? 0;
      c.summonCast = { at: t + ms, spots };
      room.broadcast({ t: 'boss_cast', id: c.id, k: 'summon', x: round(c.x), z: round(c.z), ms, spots: spots.map((sp) => [round(sp.x), round(sp.z)]) });
      return true;
    }
    // 돌진 중: 길을 따라 내달리고, 닿은 사람마다 한 번씩.
    if (c.dash) {
      const d = c.dash;
      const left = Math.hypot(d.tx - c.x, d.tz - c.z);
      const step = Math.min(left, B.charge.speed * dt);
      const nx = c.x + ((d.tx - c.x) / Math.max(left, 0.001)) * step;
      const nz = c.z + ((d.tz - c.z) / Math.max(left, 0.001)) * step;
      if (left < 0.05 || t > d.until || !canStand(nx, nz, def)) {
        c.dash = null;
        c.nextCast = t + B.every_ms;
        room.broadcast({ t: 'boss_cast', id: c.id, k: 'charge_end', x: round(c.x), z: round(c.z), ms: 0 });
        return true;
      }
      c.x = nx;
      c.z = nz;
      for (const p of victims()) {
        if (d.hit.has(p.id) || Math.hypot(p.x - c.x, p.z - c.z) > B.charge.width) continue;
        d.hit.add(p.id);
        hurt(room, p, Math.round(B.charge.damage * (c.dmg ?? 1)), c.id);
      }
      return true;
    }
    // 기 모으는 중 (경고가 보이는 동안 멈춰 선다) → 터진다.
    if (c.cast) {
      if (t < c.cast.at) return true;
      const k = c.cast;
      c.cast = null;
      if (k.k === 'slam') {
        for (const p of victims()) if (Math.hypot(p.x - k.x, p.z - k.z) <= B.slam.r) hurt(room, p, Math.round(B.slam.damage * (c.dmg ?? 1)), c.id);
        room.broadcast({ t: 'boss_cast', id: c.id, k: 'slam_hit', x: round(k.x), z: round(k.z), r: B.slam.r, ms: 0 });
        c.nextCast = t + B.every_ms;
      } else if (k.k === 'charge') {
        c.dash = { tx: k.x, tz: k.z, until: t + (B.charge.dist / B.charge.speed) * 1000 + 300, hit: new Set() };
      }
      return true;
    }
    if (!target) return false;
    c.nextCast ??= t + B.first_ms;
    if (t < c.nextCast) return false;
    if (targetD >= B.charge.min_range && targetD <= B.charge.dist) {
      // 돌진: 대상 쪽으로 dist 만큼 (막히면 그 앞까지).
      const ux = (target.x - c.x) / targetD;
      const uz = (target.z - c.z) / targetD;
      let reach = B.charge.dist;
      while (reach > 1 && !canStand(c.x + ux * reach, c.z + uz * reach, def)) reach -= 0.5;
      const ex = c.x + ux * reach;
      const ez = c.z + uz * reach;
      c.yaw = Math.atan2(ux, uz);
      c.cast = { k: 'charge', at: t + B.charge.windup_ms, x: ex, z: ez };
      room.broadcast({ t: 'boss_cast', id: c.id, k: 'charge', x: round(ex), z: round(ez), sx: round(c.x), sz: round(c.z), w: B.charge.width, ms: B.charge.windup_ms });
      return true;
    }
    if (targetD <= B.slam.range) {
      c.yaw = Math.atan2(target.x - c.x, target.z - c.z);
      c.cast = { k: 'slam', at: t + B.slam.windup_ms, x: target.x, z: target.z };
      room.broadcast({ t: 'boss_cast', id: c.id, k: 'slam', x: round(target.x), z: round(target.z), r: B.slam.r, ms: B.slam.windup_ms });
      return true;
    }
    return false;
  }

  function welcomeWire(room, player) {
    return {
      ...hpWire(player), needs: needsWire(player), looted: lootedWire(room), creatures: [...(room.creatures?.values() ?? [])].map(creatureWire), night: night(),
      boards: boardsWire(room), downed: downedWire(room),
      jobs: [...(room.boardJobs?.values() ?? [])].map(jobWire),
      stash: Object.fromEntries(Object.entries(room.stash ?? {}).map(([h, box]) => [h, box.map((e) => ({ ...e }))])),
      sleeping: [...room.players.values()].filter((p) => p.sleeping).map((p) => p.id),
      bleeding: [...room.players.values()].filter((p) => p.bleeding).map((p) => p.id),
      scent: (room.scent ?? []).map((s) => ({ id: s.id, x: s.x, z: s.z, left: Math.max(0, SC.trail_ms - (now() - s.t)) })),
      supply: [...(room.supply?.values() ?? [])].map((c) => supplyWire(room, c)),
      gates: gates.gatesWire(room),
      guards: guardians.guardsWire(room),
      npcDown: guardians.npcDownWire(room),
    };
  }

  const isDowned = (player) => Boolean(player.downed);

  return { handleRam, handleLoot, handleUse, handleAttack, handleBoard, handleRevive, handleGiveUp, handleStash, handleSleep, handleSupply, handleDodge, handleSkill, dodgeSpeed, handleGate: (ctx, msg, fail) => (msg.t === 'gate_leave' ? gates.handleLeave(ctx, msg, fail) : gates.handleEnter(ctx, msg, fail)), fixDungeon: (room, player) => gates.fixPosition(room, player), moved, tick, regen, welcomeWire, hpWire, hpOf, night, isDowned };
}
