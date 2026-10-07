import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { SIZE_SCALE } from '../src/swimmers.js';
import { Client, sleep, uid } from './helpers.js';

// 같은 순서로 나오는 난수 (물고기가 여기저기 흩어지게).
function seeded(seed = 7) {
  let s = seed;
  return () => {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s / 2147483648;
  };
}
const FAST = { fishTimeScale: 0.01, fishHookGraceMs: 500, moveSlackMeters: 200, reconnectGraceMs: 300, saveIntervalMs: 60000, npcTickRate: 30, weatherForce: 'clear' };
// 서쪽 연못(lake) 동쪽 물가 (성성호수공원 배치, fishing.test.js 와 같은 자리).
const AT_POND = { x: -42.6, z: 35.4 };

describe('v13 물고기 그림자 · 겨눠 던지기', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const newRid = () => `w${++rid}`;
  const open = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  async function enter(client) {
    client.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await client.type('welcome');
    client.send({ t: 'move', x: AT_POND.x, y: 0.1, z: AT_POND.z, yaw: 0, vx: 0, vz: 0 });
    return w;
  }
  /** 이 물고기를 캐릭터 가까이로 옮겨 둔다 (테스트용: 서버 방 상태를 직접 고친다). */
  function placeFish(code, x, z, yaw) {
    const room = server.rooms.getRoom(code);
    const s = [...room.swimmers.values()].find((f) => f.spot === 'lake' && f.st === 'roam');
    Object.assign(s, { x, z, yaw, tx: x, tz: z, until: Infinity, speed: 0 });
    return s;
  }

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-swim-'));
    server = createServer({ port: 0, saveDir, ...FAST, random: seeded() });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('호숫가에 서면 물고기 그림자들이 보인다 (크기 S·M·L, 희귀도)', async () => {
    const a = await open();
    await enter(a);
    const m = await a.next((x) => x.t === 'fishes' && x.spot === 'lake' && x.f.length >= 3, 3000);
    const lake = server.data.fishingSpot('lake');
    for (const f of m.f) {
      assert.ok(Object.keys(SIZE_SCALE).includes(f.s), `크기 ${f.s}`);
      assert.ok(['common', 'uncommon', 'rare'].includes(f.r), `희귀도 ${f.r}`);
      assert.ok(Math.abs(f.x - lake.x) <= lake.half_x && Math.abs(f.z - lake.z) <= lake.half_z, '물 안');
    }
    // 시간이 지나면 헤엄쳐 다닌다.
    const later = await a.next((x) => x.t === 'fishes' && x.spot === 'lake' && x.f.some((f) => { const o = m.f.find((p) => p.id === f.id); return o && (o.x !== f.x || o.z !== f.z); }), 4000);
    assert.ok(later);
  });

  it('물고기 머리 앞에 찌를 던지면 그 물고기가 다가와 톡·톡 건드리고 문다 → 낚으면 사라진다', async () => {
    const a = await open();
    const w = await enter(a);
    await a.type('fishes', 3000);
    // 캐릭터 앞 4m 물속에, 캐릭터 쪽을 바라보는 물고기.
    const fish = placeFish(w.code, AT_POND.x - 4.5, AT_POND.z, -Math.PI / 2);
    // 머리 앞 1m (yaw 의 정면 = (-sin, -cos)).
    const bx = fish.x - Math.sin(fish.yaw) * 1.0;
    const bz = fish.z - Math.cos(fish.yaw) * 1.0;
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake', x: bx, z: bz });
    const started = await a.type('fish_started');
    assert.equal(started.fid, fish.id, '그 물고기가 알아챔');
    assert.ok(started.shadow > 0 && started.ms > 0);
    const engaged = await a.next((x) => x.t === 'fishes' && x.f.some((f) => f.id === fish.id && f.st === 'engaged'), 2000);
    assert.ok(engaged);
    let nibbles = 0;
    for (;;) {
      const m = await a.next((x) => x.t === 'fish_nibble' || x.t === 'fish_bite', 5000);
      if (m.t === 'fish_bite') break;
      nibbles += 1;
    }
    assert.ok(nibbles >= 2, `톡·톡 (${nibbles}번) 뒤에 문다`);
    // 무는 순간 물고기는 찌 바로 앞에서 찌를 바라보고 있다.
    const at = server.rooms.getRoom(w.code).swimmers.get(fish.id);
    assert.ok(Math.hypot(at.x - bx, at.z - bz) < 0.6, `찌 앞 (${Math.hypot(at.x - bx, at.z - bz).toFixed(2)}m)`);
    await sleep(100);
    a.send({ t: 'fish_hook', rid: r, reaction: 100 });
    const reel = await a.type('fish_reel');
    await sleep(reel.taps * 45 + 20);
    a.send({ t: 'fish_reel', rid: r, taps: Array.from({ length: reel.taps }, (_, i) => i * 45 + 10) });
    const result = await a.type('fish_result');
    assert.equal(result.ok, true);
    assert.equal(result.fish, fish.fish.id, '낚인 것 = 다가온 그 물고기');
    assert.ok(!server.rooms.getRoom(w.code).swimmers.has(fish.id), '낚은 물고기는 사라진다');
  });

  it('둘레에 물고기가 없으면 기다리는 동안 지나가던 물고기가 찾아온다 (fish_found)', async () => {
    const a = await open();
    const w = await enter(a);
    await a.type('fishes', 3000);
    const room = server.rooms.getRoom(w.code);
    // 모든 물고기를 멀리 (연못 반대편) 옮겨 둔다.
    const pond = server.data.fishingSpot('lake');
    const far = { x: pond.x - pond.half_x + 2, z: pond.z };
    for (const s of room.swimmers.values()) if (s.spot === 'lake') Object.assign(s, { x: far.x, z: far.z, tx: far.x, tz: far.z, until: Infinity, speed: 0 });
    const r = newRid();
    a.send({ t: 'fish_cast', rid: r, spot: 'lake', x: AT_POND.x - 3, z: AT_POND.z });
    const started = await a.type('fish_started');
    assert.equal(started.fid, '', '처음엔 아무도 없음');
    const found = await a.type('fish_found', 60000);
    assert.ok(found.fid.length > 0 && found.shadow > 0);
    a.send({ t: 'fish_cancel', rid: newRid() });
    await a.type('fish_result');
  });

  it('바닷가에 서면 앞바다에 물고기 그림자가 몇 마리 나타난다', async () => {
    const a = await open();
    await enter(a);
    const half = server.data.layout.island.half;
    const beach = { x: half - 2, z: 0 };
    a.send({ t: 'move', x: beach.x, y: 0.1, z: beach.z, yaw: 0, vx: 0, vz: 0 });
    const m = await a.next((x) => x.t === 'fishes' && x.spot === 'sea' && x.f.length >= 2, 6000);
    for (const f of m.f) {
      assert.ok(f.x > half - 1, `바다 쪽 (${f.x.toFixed(1)})`);
      assert.ok(Math.hypot(f.x - beach.x, f.z - beach.z) < 16, '내 앞바다');
    }
  });

  it('상점 · 집 안에서는 낚시를 못 한다 (실내가 바다 건너에 있어도)', async () => {
    const a = await open();
    await enter(a);
    const door = server.data.shop.door;
    a.send({ t: 'move', x: door.x, y: 0.1, z: door.z + 1, yaw: 0, vx: 0, vz: 0 });
    await a.next((m) => m.t === 'snap' && m.p.some((p) => p.x === door.x && p.z === door.z + 1));
    a.send({ t: 'shop_enter' });
    await a.type('shop_door');
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'sea' });
    assert.equal((await a.type('error')).code, 'not_at_spot');
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'sea', x: 0, z: 300 });
    assert.equal((await a.type('error')).code, 'not_at_spot');
  });

  it('겨눈 자리가 땅이거나 너무 멀면 거절 (bad_cast)', async () => {
    const a = await open();
    await enter(a);
    await sleep(50);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake', x: AT_POND.x + 3, z: AT_POND.z });
    assert.equal((await a.type('error')).code, 'bad_cast');
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake', x: -27, z: 2 });
    assert.equal((await a.type('error')).code, 'bad_cast');
  });
});
