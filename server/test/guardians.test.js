// v0.28.2 가디언 · 주민: 초소의 가디언이 크리처를 쏜다, 크리처는 가까운 가디언 · 주민을 노린다,
// 가디언은 쓰러지면 세상 시간 20분 뒤 부활, 주민은 쓰러져 누워 있다가 일어난다.
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
const GD = data.survival.guardians;
const post = GD.posts.find((p) => p.id === 'gd1');
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.2 가디언 · 주민', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function setup(extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-guard-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(23), random: () => 0.5, creatureSpawnScale: 10000, gateFirstMs: 99999999, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    const room = [...server.rooms.rooms.values()][0];
    return { server, c, w, room };
  }
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const put = (room, id, p, k = 'shambler', hp) => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: hp ?? data.survival.creatures.kinds[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };

  it('초소마다 가디언이 서 있고 (welcome), 범위 안 크리처를 쏴서 쓰러뜨린다', async () => {
    const { c, w, room } = await setup({ creatureFreeze: true });
    assert.equal(w.surv.guards.length, GD.posts.length);
    assert.equal(w.surv.guards[0].hp, GD.hp);
    await moveTo(c, { x: post.x + 6, z: post.z - 6 });
    put(room, 'zg1', { x: post.x + 8, z: post.z }, 'shambler');
    const shot = await c.next((m) => m.t === 'guard_shot' && m.c === 'zg1', 3000);
    assert.equal(shot.g, 'gd1');
    await c.next((m) => m.t === 'creature_dead' && m.id === 'zg1', 6000);
  });

  it('크리처는 가까운 가디언을 노린다 — 쓰러지면 세상 시간 20분 뒤 부활', async () => {
    const { c, room } = await setup();
    await moveTo(c, { x: post.x + 20, z: post.z - 20 });
    room.guards.get('gd1').hp = 1;
    room.guards.get('gd1').nextShot = Infinity; // 이번엔 쏘지 않는다
    put(room, 'zg2', { x: post.x + 1.2, z: post.z }, 'brute', 99);
    const down = await c.next((m) => m.t === 'guard_down' && m.g === 'gd1', 6000);
    assert.ok(Math.abs(down.left - GD.respawn_world_min * 60000) < 5000, `left ${down.left}`);
    room.creatures.clear();
    room.guards.get('gd1').deadUntil = 1; // 세상 시간이 흘렀다
    await c.next((m) => m.t === 'guard_up' && m.g === 'gd1', 3000);
    assert.equal(room.guards.get('gd1').hp, GD.hp);
  });

  it('밖을 다니는 주민도 맞는다 — 쓰러지면 누워 있다가 일어난다', async () => {
    const { c, room } = await setup();
    const npc = [...room.npcs.values()].find((n) => n.id === 'rara');
    npc.x = -60;
    npc.z = 0;
    npc.target = null;
    npc.waitUntil = Infinity;
    npc.hp = 1;
    for (const g of room.guards?.values() ?? []) g.nextShot = Infinity;
    await moveTo(c, { x: -60, z: -15 });
    put(room, 'zg3', { x: -60.8, z: 0 }, 'shambler');
    const d = await c.next((m) => m.t === 'npc_down' && m.id === 'rara', 6000);
    assert.ok(d.left > 0);
    assert.equal(npc.down, true);
    const snap = await c.next((m) => m.t === 'npcs' && m.n.some((x) => x.id === 'rara' && x.dn === 1), 3000);
    assert.ok(snap);
    room.creatures.clear();
    npc.downUntil = 1;
    await c.next((m) => m.t === 'npc_up' && m.id === 'rara', 3000);
  });
});
