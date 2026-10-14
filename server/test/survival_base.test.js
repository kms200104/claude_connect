// v0.24 거점 · 같이 하기: 빈집 현관 · 깨진 창에 판자 대기, 크리처가 뚫린 곳으로 들어오고 막힌 곳은 두드린다,
// 쓰러짐 → 동료가 일으키기 · 포기 · 동료가 떠나면 기절.
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
const H = S.houseById.get('h01');
const count = (inv, id) => inv.slots.reduce((sum, s) => sum + (s && s.id === id ? s.n : 0), 0);
const at = (lx, lz) => ({ x: H.x + lx * H.cos + lz * H.sin, z: H.z - lx * H.sin + lz * H.cos });
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.24 빈집 거점 규칙', () => {
  it('집마다 뚫린 곳 = 현관 + 깨진 창 2개', () => {
    for (const h of S.houses) {
      assert.equal(h.breaches.length, 3, h.id);
      assert.equal(h.breaches.filter((b) => b.kind === 'door').length, 1);
    }
    assert.equal(S.breaches.size, 48);
  });
});

describe('v0.24 판자 대기 · 크리처 · 쓰러짐', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  function start(hour, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-base-'));
    dirs.push(saveDir);
    // 저절로 나타나는 크리처는 거의 없게 (시험은 직접 놓는다).
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour), random: () => 0.5, creatureSpawnScale: 10000, ...extra });
    servers.push(server);
    return server;
  }
  async function join(server, code = '') {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `bs-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];
  const put = (room, id, p, k = 'shambler') => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: S.creatures.kinds[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };

  it('낮: 현관 · 깨진 창에 판자를 댄다 (목재 2 · 못 1), 멀쩡하면 거절, 재료가 없으면 거절', async () => {
    const server = start(12, { startItems: 'wood:4,nails:2' });
    const { c } = await join(server);
    const door = H.breaches.find((b) => b.id === 'door');
    await moveTo(c, at(-3, 6.5));
    assert.equal((await ask(c, { t: 'board', h: 'h01', o: 'door' })).code, 'too_far');
    await moveTo(c, { x: door.outX, z: door.outZ });
    const ok = await ask(c, { t: 'board', h: 'h01', o: 'door' });
    assert.equal(ok.t, 'boarding');
    assert.equal(ok.need, S.fortify.board_ms);
    const done = await c.next((m) => m.t === 'boarded' && m.o === 'door', S.fortify.board_ms + 2000);
    assert.equal(done.hp, S.fortify.hp.door);
    const inv = await c.type('inventory');
    assert.equal(count(inv, 'wood'), 2);
    assert.equal(count(inv, 'nails'), 1);
    assert.equal((await ask(c, { t: 'board', h: 'h01', o: 'door' })).code, 'already_boarded');
    // 멀쩡한 창(깨지지 않은 곳)은 댈 자리가 아니다.
    const intact = ['w1', 'w2', 'w3', 'w4', 'w5'].find((id) => !H.broken.includes(id));
    assert.equal((await ask(c, { t: 'board', h: 'h01', o: intact })).code, 'bad_item');
    const win = H.breaches.find((b) => b.kind === 'window');
    await moveTo(c, { x: win.inX, z: win.inZ });
    assert.equal((await ask(c, { t: 'board', h: 'h01', o: win.id })).t, 'boarding');
    await c.next((m) => m.t === 'boarded' && m.o === win.id, S.fortify.board_ms + 2000);
    assert.equal((await ask(c, { t: 'board', h: 'h01', o: H.breaches.find((b) => b.kind === 'window' && b !== win).id })).code, 'too_far');
    assert.deepEqual(roomOf(server).boards, { [door.key]: S.fortify.hp.door, [win.key]: S.fortify.hp.window });
  });

  it('밤: 막지 않은 빈집에는 크리처가 뚫린 곳으로 (집을 둘러) 들어와 때린다', async () => {
    const server = start(23);
    const { c } = await join(server);
    await moveTo(c, at(1, 2));
    const room = roomOf(server);
    put(room, 'zt1', at(0, -8)); // 집 뒤
    const hurt = await c.next((m) => m.t === 'hurt', 30000);
    assert.ok(hurt.hp < hurt.max);
    assert.equal(room.creatures.get('zt1')?.inside, 'h01', '집 안으로 들어왔다');
  });

  it('밤: 다 막은 빈집은 크리처가 판자를 두드릴 뿐 들어오지 못한다 (안에서 창 너머로 때릴 수 있다)', async () => {
    const server = start(23, { startItems: 'pipe_spear:1' });
    const { c } = await join(server);
    await moveTo(c, at(1, 2));
    const room = roomOf(server);
    room.boards = Object.fromEntries(H.breaches.map((b) => [b.key, b.max]));
    put(room, 'zt2', at(0, -8));
    const bashed = await c.next((m) => m.t === 'board' && m.by === 0 && m.hp < m.max, 30000);
    assert.equal(bashed.h, 'h01');
    assert.ok(!c.inbox.some((m) => m.t === 'hurt'), '맞지 않았다');
    assert.equal(room.creatures.get('zt2').inside, undefined);
    // 판자 앞 크리처를 안에서 창 너머로 친다 (쇠파이프 창 2.5m).
    const z = room.creatures.get('zt2');
    const b = H.breaches.find((x) => `${x.house}:${x.id}` === `${bashed.h}:${bashed.o}`);
    await moveTo(c, { x: b.inX, z: b.inZ });
    const me = [...room.players.values()][0];
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    assert.equal(me.heldItem, 'pipe_spear');
    const swing = await ask(c, { t: 'attack' });
    assert.equal(swing.hit, z.id);
  });

  it('쓰러지면 동료가 곁에서 일으킨다 (솔을 잃지 않는다), 쓰러진 동안은 움직이지 못하고 맞지 않는다', async () => {
    const server = start(23, { startSol: 1000000 });
    const { c: a, w } = await join(server);
    const { c: b } = await join(server, w.code);
    const room = roomOf(server);
    const spot = { x: -150, z: 140 };
    await moveTo(a, spot);
    await moveTo(b, { x: spot.x + 1, z: spot.z });
    const [pa, pb] = [...room.players.values()];
    pa.profile.hp = 1;
    put(room, 'zt3', { x: spot.x - 0.6, z: spot.z });
    const downed = await b.next((m) => m.t === 'downed' && m.id === pa.id, 10000);
    assert.ok(downed.left > 0);
    assert.ok(!a.inbox.some((m) => m.t === 'ko'), '바로 기절하지 않는다');
    // 움직이지 못한다.
    await moveTo(a, { x: spot.x + 5, z: spot.z });
    assert.ok(Math.hypot(pa.x - spot.x, pa.z - spot.z) < 0.5);
    assert.equal((await ask(a, { t: 'attack' })).code, 'downed');
    const reviving = await ask(b, { t: 'revive', p: pa.id });
    assert.equal(reviving.t, 'reviving');
    const up = await a.next((m) => m.t === 'up' && m.id === pa.id, 6000);
    assert.equal(up.by, pb.id);
    assert.equal(up.ko, false);
    assert.equal(pa.profile.hp, S.downed.revive_hp);
    assert.equal(pa.profile.sol, 1000000, '솔을 잃지 않았다');
    assert.equal((await ask(b, { t: 'revive', p: pa.id })).code, 'not_downed');
  });

  it('쓰러진 채 포기하면 기절 · 동료가 나가면 바로 기절', async () => {
    const server = start(23, { startSol: 1000000 });
    const { c: a, w } = await join(server);
    const { c: b } = await join(server, w.code);
    const room = roomOf(server);
    const spot = { x: -150, z: 140 };
    await moveTo(a, spot);
    await moveTo(b, { x: spot.x + 3, z: spot.z });
    const [pa, pb] = [...room.players.values()];
    pa.profile.hp = 1;
    put(room, 'zt4', { x: spot.x - 0.6, z: spot.z });
    await a.next((m) => m.t === 'downed' && m.id === pa.id, 10000);
    room.creatures.clear();
    a.send({ t: 'give_up', rid: 'gu-1' });
    const ko = await a.next((m) => m.t === 'ko', 3000);
    assert.equal(ko.lost, 30000);
    const up = await b.next((m) => m.t === 'up' && m.id === pa.id, 3000);
    assert.equal(up.ko, true);
    // 이번엔 b 가 쓰러지고 a 가 나간다.
    await moveTo(a, spot);
    await moveTo(b, { x: spot.x + 1, z: spot.z });
    pb.profile.hp = 1;
    pb.hurtUntil = 0;
    put(room, 'zt5', { x: spot.x + 1.6, z: spot.z });
    await b.next((m) => m.t === 'downed' && m.id === pb.id, 10000);
    a.kill();
    await b.next((m) => m.t === 'ko', 5000);
  });
});
