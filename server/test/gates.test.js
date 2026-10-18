// v0.28 게이트: 열리면 재난문자, 진입하면 웨이브 → 우두머리, 공략하면 진입한 사람마다 보상, 시간이 지나면 던전 브레이크 (낮에도).
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const G = data.hunter.gates;
const spot = G.spots.find((s) => s.id === 'g01');
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28 게이트', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  function start(hour, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-gate-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour),
      creatureSpawnScale: 10000, creatureFreeze: true, random: () => 0.5, gateFirstMs: 200, gateForceRank: 'E', gateForceSpot: 'g01', startItems: 'pipe_spear:1', startSol: 0, ...extra,
    });
    servers.push(server);
    return server;
  }
  async function join(server, code = '') {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `gt-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];

  it('낮: 게이트가 열리고 (재난문자), 진입하면 웨이브 → 우두머리, 공략하면 진입한 사람마다 보상', async () => {
    const server = start(12);
    const { c, w } = await join(server);
    assert.deepEqual(w.surv.gates, []);
    await moveTo(c, { x: spot.x + 8, z: spot.z });
    const opened = (await c.next((m) => m.t === 'gate' && m.g.st === 'open', 3000)).g;
    assert.deepEqual({ rank: opened.rank, spot: opened.spot }, { rank: 'E', spot: 'g01' });
    const al = await c.next((m) => m.t === 'alert' && m.id === `gate_${opened.id}`, 2000);
    assert.ok(al.text.includes('E급 게이트'));
    assert.equal((await ask(c, { t: 'gate_enter', g: opened.id })).code, 'too_far');
    await moveTo(c, { x: spot.x + 2, z: spot.z });
    assert.equal((await ask(c, { t: 'gate_enter', g: opened.id })).t, 'gate_entered');
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    const waves = G.ranks.E.waves;
    let boss = null;
    for (let i = 0; i < 40; i++) {
      const left = [...room.creatures.values()].filter((x) => x.g === opened.id);
      if (left.length === 0) break;
      const target = left[0];
      if (target.boss) boss = target;
      target.hp = 1;
      await moveTo(c, { x: target.x + 0.8, z: target.z });
      await ask(c, { t: 'attack' });
      await sleep(Math.max(0, (data.survival.weapons.pipe_spear?.cooldown_ms ?? 600) - 100));
    }
    assert.ok(boss, '우두머리가 나왔다');
    assert.equal(boss.boss, G.ranks.E.boss.name);
    const done = await c.next((m) => m.t === 'gate_clear', 3000);
    assert.equal(done.sol, G.ranks.E.sol);
    assert.ok(done.items.length >= 1);
    // v0.28.12 처치 보상 (던전 안에서 잡은 수) · 협회 지급 보상 (E급 게이트 × E급 헌터, 빨리 깼고 우두머리를 쓰러뜨렸다).
    const A = G.assoc;
    assert.ok(done.kills.n >= 3, `처치 ${done.kills.n}`);
    assert.ok(done.kills.xp > 0);
    assert.equal(done.assoc.hr, 'E');
    assert.equal(done.assoc.fast, true);
    assert.equal(done.assoc.mvp, true);
    const mult = A.hunter_mult.E * (1 + A.fast_bonus + A.mvp_bonus);
    assert.equal(done.assoc.sol, Math.round(A.by_gate.E.sol * mult));
    assert.deepEqual(done.assoc.items.map((x) => x.id), A.by_gate.E.items.map((x) => x.id));
    // v0.28.13 기여도: 들어간 사람 모두의 처치 수 · 준 피해 · 받은 피해.
    assert.equal(done.team.length, 1);
    assert.equal(done.team[0].n, done.kills.n);
    assert.ok(done.team[0].dmg >= done.kills.n, `준 피해 ${done.team[0].dmg}`);
    assert.equal(done.team[0].mvp, true);
    assert.ok(done.team[0].hurt >= 0);
    await c.next((m) => m.t === 'gate_gone' && m.g === opened.id && m.why === 'clear', 2000);
    assert.equal(me.profile.hunter.gates, 1);
    assert.ok(me.profile.hunter.pts >= G.ranks.E.pts);
    // v0.28.15 마일리지: 받은 점수만큼 + 게이트 덤.
    assert.ok(me.profile.hunter.mi >= me.profile.hunter.pts * data.hunter.mileage.per_point + data.hunter.mileage.gate.E - 0, `마일리지 ${me.profile.hunter.mi}`);
    assert.equal(room.gates.size, 0);
    assert.ok(waves.length >= 2);
  });

  it('v0.28.13 B · A · S 게이트는 그 등급에 들어갈 수 있는 헌터가 방에 있을 때만 열린다', async () => {
    // random 0.99 → 가중치 목록의 맨 끝 등급. E급 헌터만 있으면 C 까지, A급 헌터가 있으면 S 까지.
    const lowServer = start(12, { gateForceRank: '', random: () => 0.99, gateFirstMs: 600 });
    const a = await join(lowServer);
    await moveTo(a.c, { x: spot.x + 8, z: spot.z });
    const low = (await a.c.next((m) => m.t === 'gate' && m.g.st === 'open', 3000)).g;
    assert.equal(low.rank, 'C');
    // v0.28.14 전용 지도가 없는 등급은 ranks 가 없는 지도 (지하철역 · 동굴), B · A · S 는 용암 · 얼음.
    assert.ok(['subway', 'cave'].includes(low.map), low.map);
    const high = start(12, { gateForceRank: '', random: () => 0.99, gateFirstMs: 600 });
    const b = await join(high);
    [...roomOf(high).players.values()][0].profile.hunter.rank = 'A';
    await moveTo(b.c, { x: spot.x + 8, z: spot.z });
    const g = (await b.c.next((m) => m.t === 'gate' && m.g.st === 'open', 3000)).g;
    assert.equal(g.rank, 'S');
    assert.ok(['lava', 'ice'].includes(g.map), g.map);
    const al = await b.c.next((m) => m.t === 'alert' && m.id === `gate_${g.id}`, 2000);
    assert.equal(al.level, 'emergency');
  });

  it('등급이 모자라면 못 들어간다 · 시간이 지나면 던전 브레이크 (낮에도 크리처가 쏟아진다)', async () => {
    const server = start(12, { gateForceRank: 'C', gateLifeMs: 600 });
    const { c } = await join(server);
    await moveTo(c, { x: spot.x + 2, z: spot.z });
    const opened = (await c.next((m) => m.t === 'gate' && m.g.st === 'open', 3000)).g;
    assert.equal(opened.rank, 'C');
    assert.equal((await ask(c, { t: 'gate_enter', g: opened.id })).code, 'rank_too_low');
    await moveTo(c, { x: -150, z: 140 });
    const brk = await c.next((m) => m.t === 'alert' && m.id === `gate_${opened.id}_break`, 3000);
    assert.equal(brk.level, 'emergency');
    await c.next((m) => m.t === 'gate' && m.g.st === 'break', 2000);
    const room = roomOf(server);
    await c.next((m) => m.t === 'creatures' && m.c.some((x) => x.g === ''), 4000);
    assert.ok([...room.creatures.values()].some((x) => x.brk), '브레이크 크리처 (한낮)');
    assert.equal((await ask(c, { t: 'gate_enter', g: opened.id })).code, 'too_far');
  });
});
