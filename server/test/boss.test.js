// v0.28.5 게이트 우두머리 패턴: 내려치기 (경고 원 → 범위 피해) · 돌진 (경고 길 → 내달림) · 소환 (체력 60% · 30%).
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
const B = data.hunter.gates.boss_skills;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.5 우두머리 패턴', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function setup() {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-boss-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(12),
      creatureSpawnScale: 10000, random: () => 0.5, gateFirstMs: 99999999,
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
  const spot = { x: -150, z: 140 };
  const putBoss = (room, at, hp = 60) => {
    room.creatures ??= new Map();
    room.creatures.set('zboss', { id: 'zboss', k: 'brute', x: at.x, z: at.z, yaw: 0, hp, max: 60, target: 0, nextAttack: 0, attackAt: 0, trapAt: {}, boss: '시험 우두머리', scale: 1.6, g: 'gtX', nextCast: 0 });
  };

  it('가까우면 내려치기: 경고 원이 먼저 오고 (windup), 그 안에 있으면 맞는다', async () => {
    const { c, room, me } = await setup();
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putBoss(room, { x: spot.x + 2.4, z: spot.z });
    const warn = await c.next((m) => m.t === 'boss_cast' && m.k === 'slam', 3000);
    assert.equal(warn.ms, B.slam.windup_ms);
    assert.equal(warn.r, B.slam.r);
    assert.ok(Math.hypot(warn.x - spot.x, warn.z - spot.z) < 0.5, '내 자리에 경고');
    const hp0 = me.profile.hp;
    await c.next((m) => m.t === 'boss_cast' && m.k === 'slam_hit', 3000);
    await sleep(100);
    assert.ok(me.profile.hp < hp0, '피하지 않으면 맞는다');
  });

  it('멀면 돌진: 경고 길 → 내달려 길 위 사람을 친다 → 멈춘다', async () => {
    const { c, room } = await setup();
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putBoss(room, { x: spot.x + 7, z: spot.z });
    const warn = await c.next((m) => m.t === 'boss_cast' && m.k === 'charge', 3000);
    assert.equal(warn.w, B.charge.width);
    assert.ok(warn.x < spot.x + 1, '내 쪽으로 (지나쳐) 달린다');
    const hurt = await c.next((m) => m.t === 'hurt', 4000);
    assert.equal(hurt.by, 'zboss');
    await c.next((m) => m.t === 'boss_cast' && m.k === 'charge_end', 3000);
  });

  it('체력이 60% 아래로 떨어지면 부하를 부른다 (한 번만)', async () => {
    const { c, room } = await setup();
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putBoss(room, { x: spot.x + 12, z: spot.z }, 30);
    const cast = await c.next((m) => m.t === 'boss_cast' && m.k === 'summon', 3000);
    // v0.28.16 포효 (windup_ms) 동안 나올 자리를 먼저 알리고, 부하는 그 뒤에 나온다.
    assert.equal(cast.ms, B.summon.windup_ms);
    assert.equal(cast.spots.length, B.summon.n);
    assert.equal([...room.creatures.values()].filter((x) => x.k === B.summon.k && x.g === 'gtX').length, 0, '포효하는 동안은 아직 없다');
    await sleep(B.summon.windup_ms + 300);
    const minions = [...room.creatures.values()].filter((x) => x.k === B.summon.k && x.g === 'gtX');
    assert.equal(minions.length, B.summon.n);
    // 기어 나오는 동안은 맞지 않는다.
    assert.ok(minions.every((m) => Number.isFinite(m.riseUntil) && m.riseUntil > 0), '기어 나오는 동안 (riseUntil)');
    await sleep(600);
    assert.equal([...room.creatures.values()].filter((x) => x.k === B.summon.k).length, B.summon.n, '다시 부르지 않는다 (30% 전까지)');
  });
});
