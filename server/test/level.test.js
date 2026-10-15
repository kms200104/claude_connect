// v0.28.1 레벨 · 스탯 · 기술: 경험치로 레벨이 오르고 스탯 포인트를 받는다, 힘 · 체력 · 민첩 · 행운, Lv.3 "달리며 공격".
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { xpToNext } from '../src/hunter.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const H = data.hunter;
const L = H.level;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.1 레벨 · 스탯', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  function start(extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-level-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(23),
      creatureSpawnScale: 10000, creatureFreeze: true, random: () => 0.5, startItems: 'pipe_spear:1', gateFirstMs: 99999999, ...extra,
    });
    servers.push(server);
    return server;
  }
  async function join(server) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `lv-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p, v = { x: 0, z: 0 }) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: v.x, vz: v.z });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];
  const put = (room, id, p, k = 'shambler', hp = 1) => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };
  const spot = { x: -150, z: 140 };

  it('처치 경험치로 레벨이 오르고 스탯 포인트를 받는다, 스탯을 쓰면 힘 · 체력이 오른다', async () => {
    const server = start();
    const { c, w } = await join(server);
    assert.deepEqual({ lv: w.hunter.lv, xp: w.hunter.xp, sp: w.hunter.sp, next: w.hunter.xpNext }, { lv: 1, xp: 0, sp: 0, next: xpToNext(H, 1) });
    assert.deepEqual(w.hunter.st, { str: 0, vit: 0, agi: 0, luk: 0 });
    await moveTo(c, spot);
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    me.profile.hunter.xp = xpToNext(H, 1) - 5;
    put(room, 'zl1', { x: spot.x + 1, z: spot.z });
    await ask(c, { t: 'attack' });
    const up = await c.next((m) => m.t === 'hunter_result' && m.kind === 'level', 2000);
    assert.deepEqual({ lv: up.lv, sp: up.sp }, { lv: 2, sp: L.points_per_level });
    assert.equal((await ask(c, { t: 'stat_up', s: 'nope' })).code, 'bad_item');
    const st = await ask(c, { t: 'stat_up', s: 'vit' });
    assert.deepEqual({ v: st.v, sp: st.sp }, { v: 1, sp: 2 });
    await ask(c, { t: 'stat_up', s: 'vit' });
    const hp = await c.next((m) => m.t === 'hp' && m.max === 11, 2000);
    assert.equal(hp.max, 11, '체력 2점 → 최대 체력 +1');
    await ask(c, { t: 'stat_up', s: 'str' });
    assert.equal((await ask(c, { t: 'stat_up', s: 'str' })).code, 'no_stat_point');
    // 힘 1 → 피해 4 × 1.05 = 4.2 (random 0.5 > 0.2 라 4).
    put(room, 'zl2', { x: spot.x + 1, z: spot.z }, 'bloated', 10);
    await sleep(800);
    const sw = await ask(c, { t: 'attack' });
    assert.equal(sw.hp, 6);
  });

  it('달리며 공격: 배우기 전엔 사거리 그대로, Lv.3 이 되면 달리며 휘두를 때 사거리 +0.8m', async () => {
    const server = start();
    const { c } = await join(server);
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    await moveTo(c, spot);
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    put(room, 'zr1', { x: spot.x + 3.2, z: spot.z }, 'bloated', 10);
    await moveTo(c, spot, { x: 0, z: 0 });
    assert.equal((await ask(c, { t: 'attack', run: true })).hit, '', '배우기 전 (Lv.1)');
    me.profile.hunter.lv = L.skills.find((s) => s.id === 'run_attack').level;
    await sleep(800);
    const hit = await ask(c, { t: 'attack', run: true });
    assert.equal(hit.hit, 'zr1');
    assert.equal(hit.run, true);
    await sleep(800);
    assert.equal((await ask(c, { t: 'attack' })).hit, '', '서서 휘두르면 그대로');
  });
});
