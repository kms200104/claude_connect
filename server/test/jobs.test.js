// v0.12 일거리 (배달 알바): 받기 → 받을 곳에서 들기 → 주민 집에 갖다주기, 시간 안 팁, 같이 배달, 하루 건수.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { quoteJob } from '../src/jobs.js';
import { Client, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

describe('일거리 규칙', () => {
  it('멀수록 삯과 시간이 늘고, 도시락은 시간이 빠듯한 대신 팁이 크다', () => {
    const parcel = data.jobs.kindById.get('parcel');
    const lunch = data.jobs.kindById.get('lunchbox');
    const from = { x: 0, z: 0 };
    const near = quoteJob(data.jobs, parcel, from, { x: 20, z: 0 });
    const far = quoteJob(data.jobs, parcel, from, { x: 80, z: 0 });
    assert.ok(far.pay > near.pay && far.limitS > near.limitS);
    const l = quoteJob(data.jobs, lunch, from, { x: 80, z: 0 });
    assert.ok(l.limitS < far.limitS && l.tip / l.pay > far.tip / far.pay);
  });

  it('받을 곳은 모두 섬 안, 주민 집마다 갖다줄 수 있다', () => {
    for (const p of data.jobs.pickups.values()) assert.ok(Math.abs(p.x) < 100 && Math.abs(p.z) < 100, p.id);
    assert.ok(data.jobs.houses.length >= 4);
  });
});

describe('일거리 서버', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const newRid = () => `j${++rid}`;
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-jobs-'));
    server = createServer({ port: 0, saveDir, random: () => 0.1, weatherForce: 'clear' });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });
  async function enter(code = null) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    const room = [...server.rooms.rooms.values()].find((r) => r.code === w.code);
    const player = [...room.players.values()].find((p) => p.id === w.id);
    return { c, room, player, code: w.code };
  }
  const put = (player, at) => {
    player.x = at.x;
    player.z = at.z;
  };

  it('받을 곳 곁이 아니면 못 들고, 들면 다른 사람에게 들고 있는 모습이 보인다 → 집에 갖다주면 삯 + 팁', async () => {
    const { c, player, code } = await enter();
    const friend = await enter(code);
    c.send({ t: 'job_take', rid: newRid(), kind: 'parcel' });
    const j = (await c.type('job')).job;
    assert.equal(j.stage, 'pickup');
    assert.equal(j.from.id, 'shop');
    put(player, { x: j.from.x + 20, z: j.from.z });
    c.send({ t: 'job_pick', rid: newRid() });
    assert.equal((await c.type('error')).code, 'not_at_job');
    put(player, j.from);
    c.send({ t: 'job_pick', rid: newRid() });
    assert.equal((await c.type('job')).job.stage, 'carry');
    const seen = await friend.c.type('act');
    assert.deepEqual([seen.kind, seen.e], ['carry', 'parcel']);
    const before = player.profile.sol;
    put(player, j.to);
    put(friend.player, { x: 200, z: 200 });
    c.send({ t: 'job_drop', rid: newRid() });
    const r = await c.type('job_result');
    assert.equal(r.onTime, true);
    assert.equal(r.total, j.pay + j.tip);
    assert.equal(player.profile.sol, before + r.total);
    assert.ok(player.profile.npcs[j.to.npc].f >= data.jobs.friend, '받은 주민과 친해진다');
    assert.equal((await c.type('job')).job, null);
  });

  it('같이 배달: 친구가 곁에 있으면 두 사람 모두 보너스', async () => {
    const { c, player, code } = await enter();
    const friend = await enter(code);
    c.send({ t: 'job_take', rid: newRid() });
    const j = (await c.type('job')).job;
    put(player, j.from);
    c.send({ t: 'job_pick', rid: newRid() });
    await c.type('job');
    put(player, j.to);
    put(friend.player, { x: j.to.x + 2, z: j.to.z });
    const fb = friend.player.profile.sol;
    c.send({ t: 'job_drop', rid: newRid() });
    const r = await c.type('job_result');
    assert.ok(r.bonus > 0);
    assert.deepEqual(r.with, [friend.player.id]);
    const fr = await friend.c.type('job_result');
    assert.equal(fr.helper, true);
    assert.equal(friend.player.profile.sol, fb + r.bonus);
  });

  it('하루 건수를 넘으면 못 받는다 · 하던 배달이 있으면 새로 못 받는다', async () => {
    const { c, player } = await enter();
    c.send({ t: 'job_take', rid: newRid() });
    await c.type('job');
    c.send({ t: 'job_take', rid: newRid() });
    assert.equal((await c.type('error')).code, 'job_busy');
    c.send({ t: 'job_quit' });
    assert.equal((await c.type('job')).job, null);
    player.profile.jobDay.done = data.jobs.daily_max;
    c.send({ t: 'job_take', rid: newRid() });
    assert.equal((await c.type('error')).code, 'job_limit');
  });
});
