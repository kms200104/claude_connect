// v0.27 보급 상자: 밤에 헬기가 낙하산 상자를 떨어뜨리고, 먼저 연 사람이 갖는다. 다가가면 지키던 크리처가 나타난다.
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
const SU = data.survival.supply;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.27 보급 상자', () => {
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
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-supply-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour),
      creatureSpawnScale: 10000, supplyFirstMs: 300, supplyFallMs: 800, ...extra,
    });
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
    const rid = `su-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];
  const spot = { x: -150, z: 140 };

  it('밤: 상자가 떨어지고 (떨어지는 동안은 못 연다), 다가가면 지키던 크리처, 먼저 연 사람이 다 갖는다', async () => {
    const server = start(23);
    const { c: a, w } = await join(server);
    const { c: b } = await join(server, w.code);
    await moveTo(a, spot);
    await moveTo(b, { x: spot.x + 2, z: spot.z });
    const drop = (await a.next((m) => m.t === 'supply', 5000)).s;
    assert.ok(drop.left > 0, '떨어지는 중');
    const d = Math.hypot(drop.x - spot.x, drop.z - spot.z);
    assert.ok(d >= SU.dist[0] - 3 && d <= SU.dist[1] + 3, `거리 ${d}`);
    await b.next((m) => m.t === 'supply' && m.s.id === drop.id, 1000);
    await moveTo(a, { x: drop.x + 1, z: drop.z });
    if (drop.left > 300) assert.equal((await ask(a, { t: 'supply_open', s: drop.id })).code, 'supply_falling');
    await a.next((m) => m.t === 'supply_land' && m.s === drop.id, 3000);
    // 다가오면 지키던 크리처가 둘레에.
    const room = roomOf(server);
    const guards = [...room.creatures.values()].filter((c) => Math.hypot(c.x - drop.x, c.z - drop.z) < 9);
    assert.ok(guards.length >= 1, '지키던 크리처');
    // b 는 멀다.
    assert.equal((await ask(b, { t: 'supply_open', s: drop.id })).code, 'too_far');
    await moveTo(b, { x: drop.x - 1, z: drop.z });
    const got = await ask(b, { t: 'supply_open', s: drop.id });
    assert.equal(got.t, 'supply_got');
    assert.ok(got.items.length >= 1);
    const gone = await a.next((m) => m.t === 'supply_gone' && m.s === drop.id, 2000);
    assert.equal(gone.by, [...room.players.values()][1].id);
    assert.equal((await ask(a, { t: 'supply_open', s: drop.id })).code, 'already_looted');
    // 상자는 사라졌다.
    assert.equal(room.supply.size, 0);
  });

  it('남은 상자는 welcome 에 실려 오고, 낮에는 떨어지지 않는다', async () => {
    const server = start(23, { supplyFallMs: 60000 });
    const { c: a, w } = await join(server);
    await moveTo(a, spot);
    const drop = (await a.next((m) => m.t === 'supply', 5000)).s;
    const { w: w2 } = await join(server, w.code);
    assert.equal(w2.surv.supply.length, 1);
    assert.equal(w2.surv.supply[0].id, drop.id);
    assert.ok(w2.surv.supply[0].left > 0);

    const day = start(12);
    const { c: d } = await join(day);
    await moveTo(d, spot);
    await sleep(1200);
    assert.ok(!d.inbox.some((m) => m.t === 'supply'));
  });
});
