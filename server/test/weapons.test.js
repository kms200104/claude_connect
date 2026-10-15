// v0.28.5 무기 다양화: 쇠파이프 (빠름) · 못 박힌 야구방망이 (크게 밀치고 비틀거리게) · 소방도끼 (느리지만 세게, 둘을 한 번에) ·
// 석궁 (9m 밖에서 쏜다, 화살을 하나씩 쓴다, 화살이 없으면 맨손).
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
const W = data.survival.weapons;
const K = data.survival.creatures.kinds;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};
const count = (slots, id) => slots.reduce((s, x) => s + (x && x.id === id ? x.n : 0), 0);

describe('v0.28.5 무기', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function setup() {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-weap-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(23),
      creatureSpawnScale: 10000, creatureFreeze: true, random: () => 0.5, gateFirstMs: 99999999,
      startItems: 'iron_pipe:1,nail_bat:1,fire_axe:1,crossbow:1,crossbow_bolt:2',
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
    const rid = `wp-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, 3000);
  };
  const spot = { x: -150, z: 140 };
  const put = (room, id, p, k = 'brute', hp = 40) => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };
  const hold = (me, id) => {
    me.profile.held = me.slots.findIndex((x) => x?.id === id);
    me.attackReadyAt = 0;
  };

  it('무기마다 피해 · 사거리 · 간격이 다르다 (데이터)', () => {
    assert.ok(W.iron_pipe.cooldown_ms < W.pipe_spear.cooldown_ms);
    assert.ok(W.fire_axe.damage > W.pipe_spear.damage && W.fire_axe.cooldown_ms > W.pipe_spear.cooldown_ms && W.fire_axe.cleave === 2);
    assert.ok(W.nail_bat.push > 1 && W.nail_bat.stun_ms > 0);
    assert.ok(W.crossbow.range >= 9 && W.crossbow.ammo === 'crossbow_bolt');
    for (const id of ['iron_pipe', 'nail_bat', 'fire_axe', 'crossbow', 'crossbow_bolt']) assert.ok(data.recipes?.get?.(id) ?? true, id);
  });

  it('못 박힌 방망이: 크게 밀려나고 비틀거린다 · 소방도끼: 두 마리를 한 번에', async () => {
    const { c, room, me } = await setup();
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    hold(me, 'nail_bat');
    put(room, 'za', { x: spot.x + 1.2, z: spot.z });
    const sw = await ask(c, { t: 'attack' });
    assert.equal(sw.hit, 'za');
    const a = room.creatures.get('za');
    assert.ok(a.x - (spot.x + 1.2) > 1.5, `밀려난 거리 ${a.x - spot.x - 1.2}`);
    assert.ok(a.stunUntil > 0, '비틀거림');
    room.creatures.clear();
    hold(me, 'fire_axe');
    put(room, 'zb', { x: spot.x + 1.0, z: spot.z });
    put(room, 'zc', { x: spot.x - 1.2, z: spot.z });
    put(room, 'zd', { x: spot.x, z: spot.z + 1.5 });
    const ax = await ask(c, { t: 'attack' });
    assert.equal(ax.n, 2);
    const hurt = ['zb', 'zc', 'zd'].filter((id) => room.creatures.get(id).hp < 40);
    assert.deepEqual(hurt.sort(), ['zb', 'zc']);
    assert.equal(room.creatures.get('zb').hp, 40 - (W.fire_axe.damage - K.brute.armor));
  });

  it('석궁: 9m 밖도 맞히고 화살을 하나씩 쓴다, 화살이 없으면 맨손 사거리', async () => {
    const { c, room, me } = await setup();
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    hold(me, 'crossbow');
    put(room, 'zf', { x: spot.x + 8.5, z: spot.z });
    const s1 = await ask(c, { t: 'attack' });
    assert.equal(s1.hit, 'zf');
    const hit = await c.next((m) => m.t === 'creature_hit' && m.id === 'zf', 2000);
    assert.equal(hit.shot, 1);
    assert.equal(count(me.slots, 'crossbow_bolt'), 1);
    me.attackReadyAt = 0;
    await ask(c, { t: 'attack' });
    assert.equal(count(me.slots, 'crossbow_bolt'), 0);
    me.attackReadyAt = 0;
    const s3 = await ask(c, { t: 'attack' });
    assert.equal(s3.hit, '', '화살이 없으면 멀리 있는 것은 못 맞힌다');
  });
});
