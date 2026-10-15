// v0.28.2 크리처 종류: 철갑이(갑옷만큼 덜 받는다) · 비명이(알아채면 비명 — 둘레 크리처가 몰려온다) · 독침이(멀리서 침).
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
const K = data.survival.creatures.kinds;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.2 크리처 종류', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function setup(extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-kinds-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(23), creatureSpawnScale: 10000, random: () => 0.5, startItems: 'pipe_spear:1', gateFirstMs: 99999999, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    const room = [...server.rooms.rooms.values()][0];
    return { server, c, room, me: [...room.players.values()][0] };
  }
  const ask = async (c, msg) => {
    const rid = `ck-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, 3000);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const put = (room, id, p, k, hp) => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: hp ?? K[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };
  const spot = { x: -150, z: 140 };

  it('새 종류 넷이 있고, 철갑이는 갑옷만큼 덜 받는다', async () => {
    for (const k of ['crawler', 'screamer', 'brute', 'spitter']) assert.ok(K[k]?.name, k);
    const { c, room, me } = await setup({ creatureFreeze: true });
    await moveTo(c, spot);
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    put(room, 'zb', { x: spot.x + 1, z: spot.z }, 'brute');
    const sw = await ask(c, { t: 'attack' });
    assert.equal(sw.hp, K.brute.hp - (4 - K.brute.armor));
  });

  it('비명이가 사람을 알아채면 비명 — 둘레 크리처가 그 사람을 쫓는다', async () => {
    const { c, room, me } = await setup();
    await moveTo(c, spot);
    put(room, 'zs', { x: spot.x + 8, z: spot.z }, 'screamer');
    put(room, 'zf', { x: spot.x + 30, z: spot.z }, 'shambler');
    const sc = await c.next((m) => m.t === 'creature_scream' && m.id === 'zs', 5000);
    assert.ok(sc.n >= 1);
    assert.equal(room.creatures.get('zf').alertBy, me.id);
  });

  it('배리어: 크리처는 들어오지 못하고, 안의 사람은 노리지 않는다', async () => {
    const { c, room } = await setup();
    const b = data.survival.barriers.list.find((x) => x.id === 'civic');
    await moveTo(c, { x: b.x, z: b.z - b.r + 3 });
    put(room, 'zw', { x: b.x, z: b.z - b.r - 3 }, 'runner');
    await sleep(2500);
    const z = room.creatures.get('zw');
    assert.ok(Math.hypot(z.x - b.x, z.z - b.z) >= b.r - 0.01, '배리어 밖에 머문다');
    assert.ok(!c.inbox.some((m) => m.t === 'hurt'), '맞지 않았다');
  });

  it('독침이는 떨어져서 침을 뱉는다 (맞으면 피를 흘린다)', async () => {
    const { c, room } = await setup();
    await moveTo(c, spot);
    put(room, 'zp', { x: spot.x + 4, z: spot.z }, 'spitter');
    await c.next((m) => m.t === 'creature_spit' && m.id === 'zp', 6000);
    const hurt = await c.next((m) => m.t === 'hurt', 2000);
    assert.equal(hurt.by, 'spitter');
    const z = room.creatures.get('zp');
    assert.ok(Math.hypot(z.x - spot.x, z.z - spot.z) > 2.5, '붙지 않고 떨어져서');
  });
});
