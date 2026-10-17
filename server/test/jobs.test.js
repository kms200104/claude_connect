// v0.28.8 전직 · 기술 나무: Lv.10 에 직업 하나, 레벨마다 기술 포인트, 줄 · 앞 기술 조건, 기술 효과 (피해 · 치명타 · 체력), 액티브 (회전 베기 · 치유의 빛), 초기화.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { jobPointsAt, jobFx } from '../src/hunter.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const J = data.hunter.level.jobs;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.8 전직 · 기술 나무', () => {
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
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-job-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(12),
      creatureSpawnScale: 10000, random: () => 0.5, gateFirstMs: 99999999, startSol: 100000, ...extra,
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
    const rid = `job-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, 3000);
  };
  const spot = { x: -150, z: 140 };
  const putCreature = (room, id, x, z, hp = 40) => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k: 'shambler', x, z, yaw: 0, hp, max: hp, target: 0, nextAttack: 9e15, attackAt: 0, trapAt: {} });
  };

  it('Lv.10 전에는 전직하지 못하고, 하면 지난 레벨 몫까지 포인트를 받는다 (다시 바꿀 수 없다)', async () => {
    assert.equal(jobPointsAt(data.hunter, 9), 0);
    assert.equal(jobPointsAt(data.hunter, 12), 3 * J.per_level);
    const { c, me } = await setup();
    assert.equal((await ask(c, { t: 'class_pick', j: 'warrior' })).code, 'job_level');
    me.profile.hunter.lv = 12;
    const r = await ask(c, { t: 'class_pick', j: 'warrior' });
    assert.equal(r.kind, 'job');
    assert.equal(r.jp, 3);
    const h = await c.next((m) => m.t === 'hunter', 2000);
    assert.equal(h.job, 'warrior');
    assert.equal((await ask(c, { t: 'class_pick', j: 'medic' })).code, 'job_taken');
  });

  it('줄 · 앞 기술 조건을 지켜야 배우고, 레벨이 오르면 포인트가 는다', async () => {
    const { c, me, room } = await setup();
    me.profile.hunter.lv = 10;
    await ask(c, { t: 'class_pick', j: 'warrior' });
    assert.equal((await ask(c, { t: 'skill_up', n: 'w_cleave' })).code, 'skill_locked', '앞 기술 (강타) 이 없다');
    assert.equal((await ask(c, { t: 'skill_up', n: 'w_power' })).v, 1);
    assert.equal((await ask(c, { t: 'skill_up', n: 'w_power' })).code, 'no_skill_point');
    me.profile.hunter.jp = 2;
    assert.equal((await ask(c, { t: 'skill_up', n: 'w_cleave' })).code, 'skill_locked', '2줄은 포인트 2를 쓴 뒤');
    await ask(c, { t: 'skill_up', n: 'w_power' });
    assert.equal((await ask(c, { t: 'skill_up', n: 'w_cleave' })).v, 1);
    me.profile.hunter.jp = 1;
    assert.equal((await ask(c, { t: 'skill_up', n: 'w_cleave' })).code, 'skill_maxed');
    assert.ok(Math.abs(jobFx(data.hunter, me.profile, 'melee') - 0.16) < 1e-9);
    // 레벨이 오르면 +1.
    const jp0 = me.profile.hunter.jp;
    me.profile.hunter.xp = 999999;
    room.creatures ??= new Map();
    me.profile.hunter.lv = 10;
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putCreature(room, 'zx', spot.x + 1, spot.z, 1);
    await ask(c, { t: 'attack' });
    await sleep(100);
    assert.ok(me.profile.hunter.jp > jp0, `레벨이 올라 포인트 (${jp0} → ${me.profile.hunter.jp})`);
  });

  it('강철 몸은 최대 체력, 강타는 근접 피해를 올린다', async () => {
    const { c, me, room } = await setup();
    me.profile.hunter.lv = 20;
    await ask(c, { t: 'class_pick', j: 'warrior' });
    const hpMsg = c.next((m) => m.t === 'hp', 2000);
    await ask(c, { t: 'skill_up', n: 'w_tough' });
    const hp = await hpMsg;
    assert.equal(hp.max, data.survival.player.max_hp + 1, '최대 체력 +1');
    for (let i = 0; i < 4; i++) await ask(c, { t: 'skill_up', n: 'w_power' });
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putCreature(room, 'za', spot.x + 1, spot.z, 40);
    const hit = await ask(c, { t: 'attack' });
    // 맨손 1 × (1 + 0.32) → 1.32 → random 0.5 < 0.32 아니면 1. 피해 배율이 붙었는지는 jobFx 로 본다.
    assert.equal(hit.hit, 'za');
    assert.ok(Math.abs(jobFx(data.hunter, me.profile, 'melee') - 0.32) < 1e-9);
  });

  it('암살자 급소: 치명타가 터지면 creature_hit 에 crit, 그림자 일격은 다음 한 번 반드시 치명타', async () => {
    const { c, me, room } = await setup({ random: () => 0.01 });
    me.profile.hunter.lv = 20;
    await ask(c, { t: 'class_pick', j: 'assassin' });
    await ask(c, { t: 'skill_up', n: 'a_crit' });
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putCreature(room, 'zc', spot.x + 1, spot.z, 40);
    const r = await ask(c, { t: 'attack' });
    assert.equal(r.crit, 1);
    const ch = await c.next((m) => m.t === 'creature_hit' && m.id === 'zc', 2000);
    assert.equal(ch.crit, 1);
    assert.equal(ch.w, 'hands');
    assert.ok(ch.hp <= 40 - 2, `치명타 ×2 (${ch.hp})`);
    // 그림자 일격: 배우지 않았으면 못 쓴다.
    assert.equal((await ask(c, { t: 'skill_use', a: 'ambush' })).code, 'no_active');
  });

  it('회전 베기: 둘레 모두를 베고 밀쳐내며, 다시 쓰기까지 기다린다', async () => {
    const { c, me, room } = await setup();
    me.profile.hunter.lv = 20;
    me.profile.hunter.job = 'warrior';
    me.profile.hunter.jt = { w_power: 1, w_cleave: 1, w_tough: 2, w_whirl: 1 };
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    putCreature(room, 'z1', spot.x + 1.5, spot.z, 40);
    putCreature(room, 'z2', spot.x - 1.2, spot.z + 1.0, 40);
    putCreature(room, 'z3', spot.x + 8, spot.z, 40);
    const fx = c.next((m) => m.t === 'skill_fx' && m.a === 'whirl', 3000);
    const r = await ask(c, { t: 'skill_use', a: 'whirl' });
    assert.equal(r.t, 'skill_ok');
    assert.equal(r.n, 2, '가까운 둘만');
    assert.equal(r.cd, J.actives.whirl.cooldown_ms);
    assert.equal((await fx).r, J.actives.whirl.r);
    assert.ok(room.creatures.get('z1').hp < 40 && room.creatures.get('z2').hp < 40 && room.creatures.get('z3').hp === 40);
    assert.ok(Math.hypot(room.creatures.get('z1').x - spot.x, room.creatures.get('z1').z - spot.z) > 1.5, '밀려났다');
    assert.equal((await ask(c, { t: 'skill_use', a: 'whirl' })).code, 'cooling_down');
  });

  it('치유의 빛: 체력이 차고 피가 멈춘다 · 초기화하면 솔을 내고 포인트를 돌려받는다', async () => {
    const { c, me } = await setup();
    me.profile.hunter.lv = 20;
    me.profile.hunter.job = 'medic';
    me.profile.hunter.jt = { m_care: 1, m_hands: 1, m_mend: 1 };
    me.profile.hunter.jp = 0;
    me.profile.hp = 3;
    const r = await ask(c, { t: 'skill_use', a: 'mend' });
    assert.equal(r.t, 'skill_ok');
    assert.equal(me.profile.hp, 3 + J.actives.mend.heal);
    const sol0 = me.profile.sol;
    const z = await ask(c, { t: 'skill_reset' });
    assert.equal(z.kind, 'skill_reset');
    assert.equal(z.jp, 3);
    assert.equal(me.profile.sol, sol0 - J.reset_sol);
    assert.deepEqual(me.profile.hunter.jt, {});
    assert.equal(me.profile.hunter.job, 'medic', '직업은 그대로');
  });

  it('v0.28.9 2차 전직: Lv.30 에, 포인트를 더 받고 5 · 6줄이 열린다', async () => {
    const { c, me } = await setup();
    assert.equal((await ask(c, { t: 'class_advance' })).code, 'no_job_yet');
    me.profile.hunter.lv = 25;
    await ask(c, { t: 'class_pick', j: 'warrior' });
    assert.equal((await ask(c, { t: 'class_advance' })).code, 'job_level');
    // 5줄 (불굴) 은 2차 전직 전에는 잠겨 있다 (앞 기술 · 줄 조건을 채워도).
    me.profile.hunter.jt = { w_power: 5, w_tough: 4, w_cleave: 1, w_guard: 3, w_whirl: 1, w_fury: 2 };
    me.profile.hunter.jp = 3;
    assert.equal((await ask(c, { t: 'skill_up', n: 'b_iron' })).code, 'skill_locked');
    me.profile.hunter.lv = 30;
    const r = await ask(c, { t: 'class_advance' });
    assert.equal(r.kind, 'advance');
    assert.equal(r.a, 'berserker');
    assert.equal(r.jp, 3 + J.advance_points);
    assert.equal((await ask(c, { t: 'class_advance' })).code, 'job_taken');
    assert.equal((await ask(c, { t: 'skill_up', n: 'b_iron' })).v, 1);
    assert.equal(jobFx(data.hunter, me.profile, 'hp'), 4 + 2);
  });

  it('v0.28.9 직업 전용 무기: 그 직업만 쓰고 (아니면 맨손) 만든다', async () => {
    const { c, me, room } = await setup();
    me.profile.hunter.lv = 12;
    assert.equal((await ask(c, { t: 'craft', recipe: 'greatsword' })).code, 'job_only');
    c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
    const hold = () => {
      me.profile.slots[4] = { id: 'greatsword', n: 1 };
      me.profile.held = 4;
    };
    hold();
    putCreature(room, 'g1', spot.x + 1, spot.z, 40);
    await ask(c, { t: 'attack' });
    const h1 = await c.next((m) => m.t === 'creature_hit' && m.id === 'g1', 2000);
    assert.equal(h1.w, 'hands', '전사가 아니면 맨손');
    await ask(c, { t: 'class_pick', j: 'warrior' });
    hold();
    await sleep(1300);
    // (낮이라 크리처가 흩어지므로 휘두르기 바로 앞에 둔다.)
    putCreature(room, 'g1', spot.x + 1, spot.z, 40);
    putCreature(room, 'g2', spot.x + 1.2, spot.z, 40);
    putCreature(room, 'g3', spot.x - 1.2, spot.z, 40);
    const r = await ask(c, { t: 'attack' });
    assert.equal(r.n, 3, '대검은 셋까지 벤다');
    const h2 = await c.next((m) => m.t === 'creature_hit' && m.w === 'greatsword', 2000);
    assert.ok(h2.hp < 40 - 5);
  });
});
