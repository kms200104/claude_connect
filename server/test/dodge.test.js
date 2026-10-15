// v0.28.7 회피 구르기: dodge → dodge_ok, 다시 쓰기까지 거절, 구르는 동안은 맞지 않는다.
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
const D = data.survival.dodge;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.7 회피 구르기', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  it('구르면 잠깐 맞지 않고, 다시 쓰기까지 기다린다', async () => {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-dodge-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(23), creatureSpawnScale: 10000, random: () => 0.5, gateFirstMs: 99999999 });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    const room = [...server.rooms.rooms.values()][0];
    const me = [...room.players.values()][0];
    const ask = async (msg) => {
      const rid = `dg-${++n}`;
      c.send({ ...msg, rid });
      return c.next((m) => m.rid === rid, 3000);
    };
    c.send({ t: 'move', x: -150, y: 0.1, z: 140, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    const ok = await ask({ t: 'dodge' });
    assert.equal(ok.t, 'dodge_ok');
    assert.equal(ok.dist, D.dist);
    assert.equal((await ask({ t: 'dodge' })).code, 'cooling_down');
    // 구르는 동안 크리처 곁이어도 맞지 않는다.
    const hp0 = me.profile.hp;
    room.creatures ??= new Map();
    room.creatures.set('zd', { id: 'zd', k: 'runner', x: -149.4, z: 140, yaw: 0, hp: 50, target: me.id, nextAttack: 0, attackAt: 0, trapAt: {} });
    await sleep(Math.max(0, D.iframe_ms - 150));
    assert.equal(me.profile.hp, hp0, '구르는 동안은 맞지 않았다');
    await sleep(D.cooldown_ms);
    assert.equal((await ask({ t: 'dodge' })).t, 'dodge_ok', '다시 구를 수 있다');
  });
});
