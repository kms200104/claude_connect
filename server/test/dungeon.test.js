// v0.28.2 게이트 안 던전: 진입하면 별도 공간(무너진 지하철역 · 이끼 낀 동굴)으로 옮겨 가 그 안에서 싸우고,
// 나가는 균열 곁에서 나가면 게이트 앞 (혼자였으면 공략이 풀린다), 공략하면 잠시 뒤 게이트 앞으로, 끝난 던전에서 다시 접속하면 밖.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { dungeonAt, dungeonOrigin, dungeonStandLocal } from '../src/dungeon.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const G = data.hunter.gates;
const D = G.dungeon;
const spot = G.spots.find((s) => s.id === 'g01');
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28.2 던전 자리', () => {
  it('게이트 자리마다 따로, 도시 · 집 안과 겹치지 않는다', () => {
    const seen = new Set();
    for (const s of G.spots) {
      const o = dungeonOrigin(G, s.id);
      assert.equal(dungeonAt(G, o.x, o.z).spot, s.id);
      seen.add(`${o.x},${o.z}`);
      assert.ok(Math.abs(o.x) <= defaultConfig.worldHalfExtent && Math.abs(o.z) <= defaultConfig.worldHalfExtent);
    }
    assert.equal(seen.size, G.spots.length);
    assert.equal(dungeonAt(G, spot.x, spot.z), null, '도시는 던전이 아니다');
    assert.equal(dungeonAt(G, -185, 1215), null, '집 안도 아니다');
    for (const [id, map] of Object.entries(D.maps)) {
      for (const k of ['spawn', 'exit', 'center']) assert.ok(dungeonStandLocal(map, map[k][0], map[k][1]), `${id} ${k} 에 설 수 있다`);
    }
  });
});

describe('v0.28.2 게이트 던전', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  function start(extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-dgn-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(12),
      creatureSpawnScale: 10000, creatureFreeze: true, random: () => 0.5, gateFirstMs: 200, gateForceRank: 'E', gateForceSpot: 'g01', gateForceMap: 'subway',
      dungeonReturnMs: 600, startItems: 'pipe_spear:1', startSol: 0, ...extra,
    });
    servers.push(server);
    return server;
  }
  async function join(server, msg) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ v: PROTOCOL_VERSION, ...msg });
    const w = await c.type('welcome');
    return { c, w };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `dg-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];

  it('진입하면 던전 안으로, 크리처도 던전 안에. 나가는 균열에서 나가면 게이트 앞 · 공략이 풀린다', async () => {
    const server = start();
    const { c } = await join(server, { t: 'create', uid: uid() });
    await moveTo(c, { x: spot.x + 2, z: spot.z });
    const opened = (await c.next((m) => m.t === 'gate' && m.g.st === 'open', 3000)).g;
    assert.equal(opened.map, 'subway');
    const map = D.maps.subway;
    const o = dungeonOrigin(G, 'g01');
    const entered = await ask(c, { t: 'gate_enter', g: opened.id });
    assert.equal(entered.t, 'gate_entered');
    assert.equal(entered.map, 'subway');
    assert.deepEqual([entered.x, entered.z], [o.x + map.spawn[0], o.z + map.spawn[1]]);
    const moved = await c.next((m) => m.t === 'correct', 2000);
    assert.equal(moved.x, entered.x);
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    assert.equal(me.dungeon, opened.id);
    const mine = [...room.creatures.values()].filter((x) => x.g === opened.id);
    assert.ok(mine.length >= 1);
    for (const z of mine) {
      assert.equal(dungeonAt(G, z.x, z.z)?.spot, 'g01', '크리처는 던전 안');
      assert.ok(dungeonStandLocal(map, z.x - o.x, z.z - o.z), '기둥 · 잔해 밖');
    }
    // 가운데에서는 못 나간다 (옮겨 간 직후의 먼 이동은 문 통과처럼 잠깐 버려진다).
    await sleep(defaultConfig.doorGraceMs + 100);
    await moveTo(c, { x: o.x + map.center[0], z: o.z + map.center[1] });
    assert.equal((await ask(c, { t: 'gate_leave', g: opened.id })).code, 'too_far');
    await moveTo(c, { x: o.x + map.exit[0], z: o.z + map.exit[1] - 0.5 });
    const left = await ask(c, { t: 'gate_leave', g: opened.id });
    assert.equal(left.t, 'gate_left');
    assert.ok(Math.hypot(left.x - spot.x, left.z - spot.z) < 4, '게이트 앞');
    assert.equal(me.dungeon, null);
    await c.next((m) => m.t === 'gate' && m.g.id === opened.id && m.g.st === 'open', 2000);
    assert.equal([...room.creatures.values()].filter((x) => x.g === opened.id).length, 0, '게이트 크리처가 사라졌다');
  });

  it('공략하면 잠시 뒤 게이트 앞으로 돌아온다 · 끝난 던전에서 다시 접속하면 밖', async () => {
    const server = start();
    const id = uid();
    const { c, w } = await join(server, { t: 'create', uid: id });
    await moveTo(c, { x: spot.x + 2, z: spot.z });
    const opened = (await c.next((m) => m.t === 'gate' && m.g.st === 'open', 3000)).g;
    assert.equal((await ask(c, { t: 'gate_enter', g: opened.id })).t, 'gate_entered');
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    await sleep(defaultConfig.doorGraceMs + 100);
    for (let i = 0; i < 40; i++) {
      const left = [...room.creatures.values()].filter((x) => x.g === opened.id);
      if (left.length === 0) break;
      left[0].hp = 1;
      await moveTo(c, { x: left[0].x + 0.8, z: left[0].z });
      await ask(c, { t: 'attack' });
      await sleep(Math.max(0, (data.survival.weapons.pipe_spear?.cooldown_ms ?? 600) - 100));
    }
    const done = await c.next((m) => m.t === 'gate_clear', 3000);
    assert.equal(done.back, 600);
    assert.ok(dungeonAt(G, me.x, me.z), '공략 직후는 아직 던전 안 (떨어진 것을 주울 틈)');
    const back = await c.next((m) => m.t === 'correct' && Math.hypot(m.x - spot.x, m.z - spot.z) < 4, 3000);
    assert.ok(back);
    assert.equal(me.dungeon, null);

    // 던전 안에서 끊긴 채 게이트가 사라졌다 → 다시 들어오면 대피소.
    me.x = dungeonOrigin(G, 'g01').x;
    me.z = dungeonOrigin(G, 'g01').z;
    c.kill();
    await sleep(150);
    const again = await join(server, { t: 'join', uid: id, code: w.code });
    const shelter = data.safety.drill.shelter;
    const you = again.w.players.find((p) => p.id === again.w.id);
    assert.ok(Math.hypot(you.x - shelter.x, you.z - shelter.z) < 4, JSON.stringify(you));
  });
});
