// v0.25 소리 · 함께 판자 대기 · 거점 상자와 침대.
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

describe('v0.25 소리 · 함께 판자 · 거점', () => {
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
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v25-'));
    dirs.push(saveDir);
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
    const rid = `v25-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p, v = 0) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: v, vz: 0 });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];
  const put = (room, id, p, k = 'shambler') => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: S.creatures.kinds[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };

  it('둘이 같은 곳에 판자를 대면 빨라지고, 재료는 시작한 사람만 낸다', async () => {
    const server = start(12, { startItems: 'wood:2,nails:1' });
    const { c: a, w } = await join(server);
    const { c: b } = await join(server, w.code);
    const door = H.breaches.find((x) => x.id === 'door');
    await moveTo(a, { x: door.outX - 0.4, z: door.outZ });
    await moveTo(b, { x: door.outX + 0.4, z: door.outZ });
    const t0 = Date.now();
    assert.equal((await ask(a, { t: 'board', h: 'h01', o: 'door' })).joined, false);
    const joined = await ask(b, { t: 'board', h: 'h01', o: 'door' });
    assert.equal(joined.joined, true);
    assert.equal(joined.helpers.length, 2);
    const done = await b.next((m) => m.t === 'boarded', 4000);
    assert.equal(done.helpers, 2);
    assert.ok(Date.now() - t0 < S.fortify.board_ms * 0.8, `빨라졌다 (${Date.now() - t0}ms)`);
    const inv = (await ask(b, { t: 'board', h: 'h01', o: 'door' })).code;
    assert.equal(inv, 'already_boarded');
    const [pa, pb] = [...roomOf(server).players.values()];
    assert.equal(count({ slots: pa.slots }, 'wood'), 0, '시작한 사람이 냈다');
    assert.equal(count({ slots: pb.slots }, 'wood'), 2, '도운 사람은 안 냈다');
  });

  it('판자를 대다 모두 떠나면 그만두고 재료를 돌려받는다', async () => {
    const server = start(12, { startItems: 'wood:2,nails:1' });
    const { c } = await join(server);
    const door = H.breaches.find((x) => x.id === 'door');
    await moveTo(c, { x: door.outX, z: door.outZ });
    await ask(c, { t: 'board', h: 'h01', o: 'door' });
    await moveTo(c, at(-3, 12));
    const cancel = await c.next((m) => m.t === 'board_job' && m.cancel, 2000);
    assert.equal(cancel.o, 'door');
    const me = [...roomOf(server).players.values()][0];
    await sleep(100);
    assert.equal(count({ slots: me.slots }, 'wood'), 2);
    assert.equal(count({ slots: me.slots }, 'nails'), 1);
    assert.equal(roomOf(server).boards?.[door.key], undefined);
  });

  it('밤: 망치질 소리에 멀리 있던 크리처가 몰려오고 한 마리를 더 부른다, 달리면 소리가 난다', async () => {
    const server = start(23, { startItems: 'wood:2,nails:1' });
    const { c } = await join(server);
    const door = H.breaches.find((x) => x.id === 'door');
    await moveTo(c, { x: door.outX, z: door.outZ });
    const room = roomOf(server);
    // 퉁퉁이 aggro 12 밖 (13m) — 소리가 없으면 알아채지 못한다.
    put(room, 'zn1', { x: door.outX, z: door.outZ + 13 }, 'bloated');
    await sleep(300);
    assert.equal(room.creatures.get('zn1').target, 0);
    await ask(c, { t: 'board', h: 'h01', o: 'door' });
    const heard = await c.next((m) => m.t === 'noise' && m.k === 'board', 2000);
    assert.ok(heard.n >= 2, `들은 크리처 ${heard.n}`);
    await sleep(200);
    const me = [...room.players.values()][0];
    assert.equal(room.creatures.get('zn1').target, me.id, '소리 낸 사람을 쫓는다');
    assert.ok(room.creatures.size >= 2, '한 마리를 더 불렀다');
    await moveTo(c, { x: door.outX + 0.2, z: door.outZ }, 7);
    const run = await c.next((m) => m.t === 'noise' && m.k === 'run', 2000);
    assert.equal(run.r, S.noise.run);
  });

  it('상자는 언제나 (v0.28.16), 침대는 거점(다 막은 빈집)에서만 — 자면 빨리 회복하고 움직이면 깬다', async () => {
    const server = start(12, { startItems: 'wood:5' });
    const { c } = await join(server);
    const room = roomOf(server);
    const stash = at(S.base.stash[0] - 0.8, S.base.stash[1] - 0.5);
    await moveTo(c, stash);
    const me = [...room.players.values()][0];
    const slot = me.slots.findIndex((x) => x?.id === 'wood');
    // v0.28.16 판자를 다 대지 않아도 상자는 열린다.
    const put1 = await ask(c, { t: 'stash', h: 'h01', op: 'put', slot, n: 3 });
    assert.deepEqual(put1.items, [{ id: 'wood', n: 3 }]);
    assert.equal(count({ slots: me.slots }, 'wood'), 2);
    const took = await ask(c, { t: 'stash', h: 'h01', op: 'take', id: 'wood', n: 1 });
    assert.deepEqual(took.items, [{ id: 'wood', n: 2 }]);
    assert.equal(count({ slots: me.slots }, 'wood'), 3);
    assert.equal((await ask(c, { t: 'stash', h: 'h02', op: 'take', id: 'wood' })).code, 'too_far');
    // 판자가 부서져도 넣어 둔 것은 남는다 (저장).
    assert.deepEqual(room.toSave().world.stash.h01, [{ id: 'wood', n: 2 }]);
    // 침대 (거점이어야 잔다 — 판자를 다 대기 전엔 못 잔다).
    me.profile.hp = 4;
    await moveTo(c, at(S.base.bed[0] + 1.1, S.base.bed[1]));
    assert.equal((await ask(c, { t: 'sleep', on: true })).code, 'not_base');
    room.boards = Object.fromEntries(H.breaches.map((b) => [b.key, b.max]));
    await moveTo(c, at(S.base.bed[0] + 1.1, S.base.bed[1]));
    assert.equal((await ask(c, { t: 'sleep', on: true })).t, 'slept');
    const hp = await c.next((m) => m.t === 'hp' && m.hp === 5, S.base.sleep_regen_ms + 1500);
    assert.equal(hp.hp, 5);
    await moveTo(c, at(S.base.bed[0] + 1.3, S.base.bed[1]), 2);
    const woke = await c.next((m) => m.t === 'sleep' && m.on === false, 2000);
    assert.equal(woke.id, me.id);
  });
});
