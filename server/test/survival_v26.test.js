// v0.26 피 냄새 · 탈것 내구도 · 들이받기 · 보급 낙하.
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
const S = data.survival;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.26 피 냄새', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function start(hour, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v26-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour), random: () => 0.5, creatureSpawnScale: 10000, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    return { server, c, room: [...server.rooms.rooms.values()][0] };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `v26-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const put = (room, id, p, k = 'shambler') => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: S.creatures.kinds[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };

  it('맞으면 피를 흘려 핏자국을 남기고, 크리처가 더 멀리서 알아채고, 붕대로 멈춘다', async () => {
    const { c, room } = await start(23, { startItems: 'bandage:2' });
    const spot = { x: -150, z: 140 };
    await moveTo(c, spot);
    put(room, 'zs1', { x: spot.x - 0.6, z: spot.z });
    const bleed = await c.next((m) => m.t === 'bleed' && m.on, 8000);
    const me = [...room.players.values()][0];
    assert.equal(bleed.id, me.id);
    room.creatures.clear();
    me.hurtUntil = Infinity;
    const drop = await c.next((m) => m.t === 'scent', 4000);
    assert.ok(Math.hypot(drop.x - spot.x, drop.z - spot.z) < 1);
    // 퉁퉁이 aggro 12 밖 18m — 피 냄새 (× 1.8) 면 알아챈다.
    put(room, 'zs2', { x: spot.x, z: spot.z + 18 }, 'bloated');
    await sleep(300);
    assert.equal(room.creatures.get('zs2').target, me.id, '피 냄새로 알아챘다');
    // 붕대로 멈춘다 → 18m 밖은 다시 못 알아챈다.
    const slot = me.slots.findIndex((x) => x?.id === 'bandage');
    await ask(c, { t: 'use', slot });
    const stop = await c.next((m) => m.t === 'bleed' && !m.on, 2000);
    assert.equal(stop.id, me.id);
    room.creatures.get('zs2').target = 0;
    room.creatures.get('zs2').z = spot.z + 18;
    await sleep(300);
    assert.equal(room.creatures.get('zs2').target, 0, '멈춘 뒤에는 알아채지 못한다');
  });

  it('아무도 쫓지 않는 크리처는 핏자국을 따라온다', async () => {
    const { c, room } = await start(23);
    const me = [...room.players.values()][0];
    const spot = { x: -150, z: 140 };
    await moveTo(c, spot);
    me.hurtUntil = Infinity;
    // 핏자국을 길게 남긴 것처럼 놓고, 사람은 멀리 (aggro 밖).
    room.scent = [{ id: me.id, x: spot.x + 30, z: spot.z + 12, t: performance.now() }];
    put(room, 'zs3', { x: spot.x + 38, z: spot.z + 12 }, 'shambler');
    const before = room.creatures.get('zs3').x;
    await sleep(1500);
    const z = room.creatures.get('zs3');
    assert.equal(z.target, 0);
    assert.ok(before - z.x > 0.9, `핏자국 쪽으로 왔다 (${before} → ${z.x})`);
    assert.ok(Math.abs(z.z - (spot.z + 12)) < 0.2, `사람 쪽이 아니라 핏자국 쪽 (${z.z})`);
  });
});
