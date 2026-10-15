// v0.28 게이트(균열, 서버 권위): 도시 곳곳에 게이트가 열리고 (재난문자), 헌터가 들어가 웨이브 · 우두머리를 쓰러뜨리면 공략,
// 시간 안에 공략하지 못하면 '던전 브레이크' — 크리처가 쏟아져 나온다 (낮에도). data/hunter/hunter.json gates.
//   클라이언트 요청: gate_enter { g } (게이트 곁, 헌터 등급 확인).
//   서버 → gate { g: { id, rank, spot, name, x, z, st: open|raid|break, left, wave, waves, alive, raiders } } · gate_gone { g, why: clear|closed|reset }
//          gate_clear { g, rank, by: [id], items(나만), sol, pts } (진입한 사람마다) · alert (재난문자).
// 크리처 자체(움직임 · 공격 · 맞기)는 survival.js 가 그대로 돌리고, 게이트 크리처는 c.g = 게이트 id (낮에도 남는다) · c.boss.
import { ErrorCode } from './protocol.js';
import { addItem } from './inventory.js';
import { earn } from './economy.js';
import { groundProblem } from './world.js';

const round = (v) => Math.round(v * 100) / 100;

export function createGates({ data, cfg, random, now, send, sendTo, sendInventory, sendProfile, saveRoom, dropAt, hunter, inShop, canStand, pickEntry, rollLoot, broadcastCreatures }) {
  const G = data.hunter?.gates;
  const H = data.hunter;
  const S = data.survival;

  const firstMs = () => (Number.isFinite(cfg.gateFirstMs) ? cfg.gateFirstMs : G.first_ms);
  const lifeMs = () => (Number.isFinite(cfg.gateLifeMs) ? cfg.gateLifeMs : G.life_ms);
  const rankIndex = (id) => H.rankById.get(id)?.index ?? 0;

  function gateWire(room, g) {
    const alive = [...(room.creatures?.values() ?? [])].filter((c) => c.g === g.id).length;
    return {
      id: g.id, rank: g.rank, spot: g.spot, name: g.name, x: g.x, z: g.z, st: g.st,
      left: Math.max(0, (g.st === 'break' ? g.breakUntil : g.until) - now()),
      wave: g.wave, waves: G.ranks[g.rank].waves.length, alive, boss: g.bossUp ? 1 : 0, raiders: [...g.raiders],
    };
  }
  const gatesWire = (room) => [...(room.gates?.values() ?? [])].map((g) => gateWire(room, g));
  const broadcastGate = (room, g) => room.broadcast({ t: 'gate', g: gateWire(room, g) });

  function alert(room, id, level, text) {
    room.broadcast({ t: 'alert', id, level, sender: '헌터 협회', text, at: Date.now() });
  }

  /** 게이트 등급 뽑기 (weight). */
  function pickRank() {
    if (cfg.gateForceRank && G.ranks[cfg.gateForceRank]) return cfg.gateForceRank;
    return pickEntry(Object.entries(G.ranks).map(([id, r]) => ({ id, w: r.weight })), random).id;
  }

  function open(room, t) {
    const used = new Set([...room.gates.values()].map((g) => g.spot));
    const free = G.spots.filter((s) => !used.has(s.id));
    if (free.length === 0) return null;
    const spot = cfg.gateForceSpot ? (free.find((s) => s.id === cfg.gateForceSpot) ?? free[0]) : free[Math.floor(random() * free.length)];
    room.gateSeq = (room.gateSeq ?? 0) + 1;
    const rank = pickRank();
    const g = { id: `gt${room.gateSeq}`, rank, spot: spot.id, name: spot.name, x: spot.x, z: spot.z, st: 'open', until: now() + lifeMs(), wave: 0, bossUp: false, raiders: new Set(), awayAt: 0, breakUntil: 0, nextBreakAt: 0 };
    room.gates.set(g.id, g);
    broadcastGate(room, g);
    alert(room, `gate_${g.id}`, rank === 'C' ? 'emergency' : 'safety', `[헌터 협회] ${spot.name}에 ${rank}급 게이트 발생. ${Math.round(lifeMs() / 60000)}분 안에 공략하지 못하면 던전 브레이크가 일어납니다. 일반인은 접근 금지.`);
    return g;
  }

  /** 게이트 크리처 하나 (게이트 둘레 · 우두머리면 가운데). */
  function spawnFor(room, g, k, def, boss = null) {
    const R = G.ranks[g.rank];
    const kind = S.creatures.kinds[k];
    if (!kind) return null;
    for (let i = 0; i < 12; i++) {
      const a = random() * Math.PI * 2;
      const r = boss ? random() * 1.5 : 3 + random() * (G.arena * 0.5);
      const x = g.x + Math.cos(a) * r;
      const z = g.z + Math.sin(a) * r;
      if (!canStand(x, z, def) || groundProblem(data, x, z) !== null) continue;
      room.creatureSeq = (room.creatureSeq ?? 0) + 1;
      const hp = Math.round(kind.hp * (boss ? boss.hp_mult : R.hp_mult));
      const c = { id: `z${room.creatureSeq}`, k, x, z, yaw: Math.atan2(g.x - x, g.z - z), hp, max: hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {}, g: g.id, dmg: boss ? boss.dmg_mult : R.dmg_mult };
      if (boss) {
        c.boss = boss.name;
        c.scale = boss.scale;
      }
      room.creatures.set(c.id, c);
      return c;
    }
    return null;
  }

  function spawnWave(room, g, def) {
    const R = G.ranks[g.rank];
    if (g.wave < R.waves.length) {
      for (const [k, n] of R.waves[g.wave]) for (let i = 0; i < n; i++) spawnFor(room, g, k, def);
    } else {
      g.bossUp = true;
      spawnFor(room, g, R.boss.k, def, R.boss);
    }
  }

  function remove(room, g, why) {
    room.gates.delete(g.id);
    for (const c of [...room.creatures.values()]) {
      if (c.g !== g.id) continue;
      if (why === 'break') {
        // 브레이크 크리처는 바깥으로 흩어진다 (낮에도 남는다).
        c.g = undefined;
        c.brk = true;
        continue;
      }
      room.creatures.delete(c.id);
      room.broadcast({ t: 'creature_dead', id: c.id, by: 0, x: round(c.x), z: round(c.z), gone: true });
    }
    room.broadcast({ t: 'gate_gone', g: g.id, why });
  }

  /** 우두머리를 쓰러뜨렸다: 진입한 사람마다 보상. */
  function clear(room, g, by) {
    const R = G.ranks[g.rank];
    const ids = [...g.raiders];
    for (const id of ids) {
      const p = room.players.get(id);
      if (!p) continue;
      const items = rollLoot(R.loot, random);
      const got = [];
      for (const it of items) {
        if (addItem(p.slots, it.id, it.n, cfg, data.limitOf)) got.push(it);
        else dropAt(room, it.id, it.n, p.x, p.z);
      }
      p.profile.sol += R.sol;
      earn(p.profile, R.sol);
      sendInventory(p);
      sendProfile(p);
      sendTo(p, { t: 'gate_clear', g: g.id, rank: g.rank, name: g.name, by: ids, killer: by, items, got, sol: R.sol, pts: R.pts });
      hunter?.onGate(room, p, R.pts, g.rank);
    }
    alert(room, `gate_${g.id}_clear`, 'safety', `[헌터 협회] ${g.name} ${g.rank}급 게이트 공략 완료. 협조해 주신 헌터께 감사드립니다.`);
    remove(room, g, 'clear');
    saveRoom(room);
  }

  /** survival.kill 이 부른다. */
  function onKill(room, c, by) {
    if (!G || !c.g) return;
    const g = room.gates?.get(c.g);
    if (!g || g.st !== 'raid') return;
    if (c.boss) return clear(room, g, by);
    const left = [...room.creatures.values()].some((x) => x.g === g.id);
    if (!left) {
      g.wave++;
      spawnWave(room, g, room.gateDef ?? { blocks: [], traps: [], lights: [] });
    }
    broadcastGate(room, g);
  }

  function handleEnter(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!G) return fail(ErrorCode.badMessage);
    const g = room.gates?.get(msg.g);
    if (!g) return fail(ErrorCode.noGate);
    if (player.downed) return fail(ErrorCode.downed);
    if (player.home || inShop(player) || Math.hypot(player.x - g.x, player.z - g.z) > G.enter_range + 0.4) return fail(ErrorCode.tooFar);
    if (g.st === 'break') return fail(ErrorCode.gateBroken);
    const mine = rankIndex(player.profile.hunter?.rank ?? 'E');
    if (mine < rankIndex(g.rank) - 1) return fail(ErrorCode.rankTooLow);
    if (g.raiders.has(player.id)) return fail(ErrorCode.alreadyBoarded);
    g.raiders.add(player.id);
    g.awayAt = 0;
    if (g.st === 'open') {
      g.st = 'raid';
      g.wave = 0;
      g.bossUp = false;
      spawnWave(room, g, room.gateDef ?? { blocks: [], traps: [], lights: [] });
    }
    send(ctx.ws, { t: 'gate_entered', rid: msg.rid, g: g.id });
    broadcastGate(room, g);
    broadcastCreatures(room);
  }

  /** survival.tick 이 부른다 (낮 · 밤 모두). 크리처가 바뀌었으면 true. */
  function tick(room, t, people, def) {
    if (!G) return false;
    room.gates ??= new Map();
    room.gateDef = def;
    let changed = false;
    if (room.gateNextAt === undefined) room.gateNextAt = t + firstMs();
    if (t >= room.gateNextAt) {
      if (people.length > 0 && room.gates.size < G.max_open) {
        if (open(room, t)) room.gateNextAt = t + G.every_ms;
        else room.gateNextAt = t + 10000;
      } else room.gateNextAt = t + 10000;
    }
    const nowMs = now();
    for (const g of [...room.gates.values()]) {
      if (g.st === 'open' && nowMs >= g.until) {
        // 던전 브레이크.
        g.st = 'break';
        g.breakUntil = nowMs + G.break.ms;
        g.nextBreakAt = t;
        alert(room, `gate_${g.id}_break`, 'emergency', `[긴급] ${g.name} ${g.rank}급 게이트 던전 브레이크! 크리처가 쏟아져 나옵니다. 가까운 대피소 · 거점으로 피하세요.`);
        broadcastGate(room, g);
      }
      if (g.st === 'raid') {
        // 진입한 사람이 모두 멀리 가 있으면 공략이 풀린다.
        const near = [...g.raiders].some((id) => {
          const p = room.players.get(id);
          return p && p.online && !p.downed && Math.hypot(p.x - g.x, p.z - g.z) <= G.arena * 2;
        });
        if (near) g.awayAt = 0;
        else if (!g.awayAt) g.awayAt = nowMs;
        else if (nowMs - g.awayAt > G.abandon_ms) {
          for (const c of [...room.creatures.values()]) {
            if (c.g !== g.id) continue;
            room.creatures.delete(c.id);
            room.broadcast({ t: 'creature_dead', id: c.id, by: 0, x: round(c.x), z: round(c.z), gone: true });
          }
          g.st = 'open';
          g.wave = 0;
          g.bossUp = false;
          g.raiders.clear();
          g.awayAt = 0;
          broadcastGate(room, g);
          changed = true;
        }
        // 시간이 다 돼도 공략 중이면 브레이크 대신 기다린다 (until 을 미룬다).
        if (nowMs >= g.until) g.until = nowMs + 60000;
      }
      if (g.st === 'break') {
        if (nowMs >= g.breakUntil) {
          remove(room, g, 'break');
          changed = true;
          continue;
        }
        if (t >= g.nextBreakAt) {
          g.nextBreakAt = t + G.break.every_ms;
          const R = G.ranks[g.rank];
          const kinds = R.waves.flat().map(([k]) => k);
          for (const p of people) {
            for (let i = 0; i < G.break.per_player; i++) {
              if (room.creatures.size >= S.creatures.max_per_room + 6) break;
              const k = kinds[Math.floor(random() * kinds.length)];
              const a = random() * Math.PI * 2;
              const r = S.creatures.spawn_min + random() * (S.creatures.spawn_max - S.creatures.spawn_min);
              const x = p.x + Math.cos(a) * r;
              const z = p.z + Math.sin(a) * r;
              if (!canStand(x, z, def) || groundProblem(data, x, z) !== null) continue;
              const kind = S.creatures.kinds[k];
              room.creatureSeq = (room.creatureSeq ?? 0) + 1;
              const hp = Math.round(kind.hp * R.hp_mult);
              room.creatures.set(`z${room.creatureSeq}`, { id: `z${room.creatureSeq}`, k, x, z, yaw: Math.atan2(p.x - x, p.z - z), hp, max: hp, target: p.id, nextAttack: 0, attackAt: 0, trapAt: {}, brk: true, dmg: R.dmg_mult });
              changed = true;
            }
          }
        }
      }
    }
    // 1초에 한 번쯤 남은 시간 · 남은 크리처를 다시 알린다.
    if (t >= (room.gateWireAt ?? 0) && room.gates.size > 0) {
      room.gateWireAt = t + 1000;
      for (const g of room.gates.values()) broadcastGate(room, g);
    }
    return changed;
  }

  return { tick, onKill, handleEnter, gatesWire };
}
