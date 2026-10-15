// v0.28.5 헌터 각성: 레벨 5 · 10 · 15 마다 하나 고르기, 마력 방패 (공격을 막는다) · 그림자 걸음 (크리처가 보지 못한다) · 다시 쓰기까지.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { awakenSlots } from '../src/hunter.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const A = data.hunter.level.awaken;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.5 헌터 각성', () => {
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
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-aw-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(23),
      creatureSpawnScale: 10000, random: () => 0.5, gateFirstMs: 99999999, ...extra,
    });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    const room = [...server.rooms.rooms.values()][0];
    return { c, room, me: [...room.players.values()][0] };
  }
  const ask = async (c, msg) => {
    const rid = `aw-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, 3000);
  };
  const spot = { x: -150, z: 140 };

  it('레벨이 되어야 고를 수 있고, 자리마다 하나 (바꿀 수 없다)', async () => {
    assert.deepEqual(A.slots, [5, 10, 15]);
    assert.equal(awakenSlots(data.hunter, 4), 0);
    assert.equal(awakenSlots(data.hunter, 10), 2);
    const { c, me } = await setup();
    assert.equal((await ask(c, { t: 'awaken', a: 'shield' })).code, 'no_awaken_slot');
    me.profile.hunter.lv = 5;
    const ok = await ask(c, { t: 'awaken', a: 'shield' });
    assert.equal(ok.kind, 'awaken');
    const h = await c.next((m) => m.t === 'hunter' && m.aw?.includes('shield'), 2000);
    assert.equal(h.awSlots, 1);
    assert.equal((await ask(c, { t: 'awaken', a: 'shadow' })).code, 'no_awaken_slot');
    assert.equal((await ask(c, { t: 'awaken_use', a: 'shadow' })).code, 'not_awakened');
    assert.equal((await ask(c, { t: 'awaken_use', a: 'sense' })).code, 'not_awakened', '늘 켜진 각성은 쓰는 게 아니다');
  });

  it('마력 방패: 공격을 3번 막고, 다시 쓰기까지 기다린다', async () => {
    const { c, room, me } = await setup();
    me.profile.hunter.lv = 5;
    await ask(c, { t: 'awaken', a: 'shield' });
    const used = await ask(c, { t: 'awaken_use', a: 'shield' });
    assert.equal(used.kind, 'awaken_use');
    assert.equal(used.cd, A.list.find((x) => x.id === 'shield').cooldown_ms);
    await c.next((m) => m.t === 'awaken_fx' && m.a === 'shield', 2000);
    assert.equal((await ask(c, { t: 'awaken_use', a: 'shield' })).code, 'cooling_down');
    // 크리처 곁에서 맞아도 막는다.
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    const hp0 = me.profile.hp;
    room.creatures ??= new Map();
    room.creatures.set('zz', { id: 'zz', k: 'shambler', x: spot.x + 0.6, z: spot.z, yaw: 0, hp: 50, target: me.id, nextAttack: 0, attackAt: 0, trapAt: {} });
    const blocked = await c.next((m) => m.t === 'shield_block' && m.id === me.id, 6000);
    assert.equal(blocked.left, 2);
    assert.equal(me.profile.hp, hp0);
  });

  it('그림자 걸음: 그 동안 크리처가 나를 노리지 않는다', async () => {
    const { c, room, me } = await setup();
    me.profile.hunter.lv = 10;
    await ask(c, { t: 'awaken', a: 'shadow' });
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    await ask(c, { t: 'awaken_use', a: 'shadow' });
    const hp0 = me.profile.hp;
    room.creatures ??= new Map();
    room.creatures.set('zy', { id: 'zy', k: 'shambler', x: spot.x + 0.6, z: spot.z, yaw: 0, hp: 50, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
    await sleep(1500);
    assert.equal(me.profile.hp, hp0, '맞지 않았다');
    assert.notEqual(room.creatures.get('zy')?.target, me.id);
  });
});
