import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { levelFor, sellValue, stockFor } from '../src/shop.js';
import { Client, uid } from './helpers.js';

const fakeClock = () => ({ hour: () => 12, day: () => 100, gameMs: () => 0, scale: 1 });
// random=0: 둥근 나무에서는 항상 '목재'. 상점 포인트는 10배로 쌓여서 단계가 빨리 오른다.
const BASE = { moveSlackMeters: 200, random: () => 0, saveIntervalMs: 60000, chopCooldownMs: 0, weatherForce: 'clear', shopPointsScale: 10 };

describe('상점 · 가구 설치 · 옷', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const newRid = () => `s${++rid}`;
  const open = async (s = server) => {
    const c = new Client(s.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  async function enter(client, { code, id = uid() } = {}) {
    client.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: id, code } : { t: 'create', v: PROTOCOL_VERSION, uid: id });
    return client.type('welcome');
  }
  async function moveTo(client, x, z) {
    client.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await client.next((m) => m.t === 'snap' && m.p.some((p) => p.x === x && p.z === z));
  }
  /** 둥근 나무 하나를 세 번 찍어 목재 3개를 얻는다. */
  async function chopWood(client, treeId) {
    const t = server.data.trees.get(treeId);
    await moveTo(client, t.x + 1, t.z);
    client.send({ t: 'equip', slot: 1 });
    for (let i = 0; i < 3; i++) {
      client.send({ t: 'chop', rid: newRid(), tree: treeId });
      await client.type('chop_result');
    }
  }
  async function goInside(client) {
    const door = server.data.shop.door;
    await moveTo(client, door.x, door.z + 1);
    client.send({ t: 'shop_enter' });
    return client.type('shop_door');
  }

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-shop-'));
    server = createServer({ port: 0, saveDir, ...BASE, clock: fakeClock() });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('단계 계산: 포인트로 단계가 정해지고, 오른 단계는 이전 물건도 계속 판다', () => {
    const levels = server.data.shop.levels;
    assert.equal(levelFor(0, levels).level, 1);
    assert.equal(levelFor(1500, levels).level, 2);
    assert.equal(levelFor(999999, levels).level, 3);
    assert.ok(!stockFor(0, levels).includes('sofa'));
    assert.ok(stockFor(6000, levels).includes('sofa') && stockFor(6000, levels).includes('tea_leaves'));
    assert.equal(sellValue(100, 3, 0, levels), 300);
    assert.equal(sellValue(100, 3, 6000, levels), 330, '백화점은 10% 더 쳐준다');
  });

  it('문 앞에서만 들어가고, 상점 안에서만 사고팔 수 있다', async () => {
    const a = await open();
    await enter(a);
    a.send({ t: 'shop_enter' });
    assert.equal((await a.type('error')).code, 'not_near_door');
    a.send({ t: 'shop_sell', rid: newRid(), slot: 5, n: 1 });
    assert.equal((await a.type('error')).code, 'not_in_shop');
    const inside = await goInside(a);
    assert.equal(inside.inside, true);
    assert.deepEqual([inside.x, inside.z], [server.data.shop.inside_spawn.x, inside.z]);
    assert.ok(inside.z > 50, '실내는 마을 멀리 떨어진 공간');
    // 문 반대편에서 늦게 도착한 이동 요청은 무시된다 (되돌리지 않음)
    const door = server.data.shop.door;
    a.send({ t: 'move', x: door.x, y: 0.1, z: door.z + 1, yaw: 0, vx: 0, vz: 0 });
    a.send({ t: 'shop_exit' });
    const out = await a.type('shop_door');
    assert.equal(out.inside, false);
    assert.equal(a.inbox.some((m) => m.t === 'correct'), false);
  });

  it('목재·물고기를 팔면 솔과 상점 포인트가 오르고, 포인트가 차면 상점이 커진다', async () => {
    const a = await open();
    const w = await enter(a);
    const b = await open();
    await enter(b, { code: w.code });
    await chopWood(a, 't13');
    await chopWood(a, 't15');
    await goInside(a);
    a.send({ t: 'shop_sell', rid: newRid(), slot: 0, n: 1 });
    assert.equal((await a.type('error')).code, 'cant_sell', '도구는 못 판다');
    a.send({ t: 'shop_sell', rid: newRid(), slot: 5, n: 99 });
    assert.equal((await a.type('error')).code, 'bad_item', '가진 것보다 많이는 못 판다');
    a.send({ t: 'shop_sell', rid: newRid(), slot: 5, n: 6 });
    const sold = await a.type('shop_result');
    assert.deepEqual({ kind: sold.kind, item: sold.item, n: sold.n, amount: sold.amount, sol: sold.sol }, { kind: 'sell', item: 'wood', n: 6, amount: 360, sol: 360 });
    const shop = await b.type('shop');
    assert.deepEqual({ level: shop.level, points: shop.points, up: shop.up }, { level: 2, points: 3600, up: true }, '상대도 상점이 커진 걸 안다');
    assert.ok(await a.next((m) => m.t === 'inventory' && m.slots[5] === null), '판 목재가 빠진다');
  });

  it('살 때: 지금 단계 진열품만, 솔이 모자라면 못 산다', async () => {
    const a = await open();
    await enter(a);
    await goInside(a);
    a.send({ t: 'shop_buy', rid: newRid(), item: 'tea_leaves', n: 1 });
    assert.equal((await a.type('error')).code, 'not_enough_sol');
    a.send({ t: 'shop_buy', rid: newRid(), item: 'sofa', n: 1 });
    assert.equal((await a.type('error')).code, 'not_for_sale', '구멍가게에는 소파가 없다');
    a.send({ t: 'shop_buy', rid: newRid(), item: 'dragon', n: 1 });
    assert.equal((await a.type('error')).code, 'not_for_sale');
  });

  it('사고, 가구를 설치했다 줍고, 옷을 갈아입는다 — 상대에게도 보인다', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-shop2-'));
    // 이 테스트는 문을 지나자마자 멀리 순간이동하므로 낡은 이동 무시 시간을 끈다.
    const s = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock(), doorGraceMs: 0 });
    const A = uid();
    try {
      const a = await open(s);
      const w = await enter(a, { id: A });
      const b = await open(s);
      await enter(b, { code: w.code });
      // 솔 마련: 프로필에 직접 넣는다 (사고파는 흐름만 본다)
      s.rooms.getRoom(w.code).profiles.get(A).sol = 5000;
      const door = s.data.shop.door;
      a.send({ t: 'move', x: door.x, y: 0.1, z: door.z + 1, yaw: 0, vx: 0, vz: 0 });
      await a.next((m) => m.t === 'snap');
      a.send({ t: 'shop_enter' });
      await a.type('shop_door');
      for (const item of ['wood_chair', 'straw_hat', 'striped_tee']) {
        a.send({ t: 'shop_buy', rid: newRid(), item, n: 1 });
        const r = await a.type('shop_result');
        assert.equal(r.item, item);
      }
      const inv = await a.next((m) => m.t === 'inventory' && m.slots.some((x) => x?.id === 'striped_tee'));
      const chairSlot = inv.slots.findIndex((x) => x?.id === 'wood_chair');
      const hatSlot = inv.slots.findIndex((x) => x?.id === 'straw_hat');
      const teeSlot = inv.slots.findIndex((x) => x?.id === 'striped_tee');
      assert.equal((await a.next((m) => m.t === 'profile' && m.sol === 5000 - 600 - 500 - 450)).sol, 3450);

      // 옷
      a.send({ t: 'wear', rid: newRid(), slot: chairSlot });
      assert.equal((await a.type('error')).code, 'not_wearable');
      a.send({ t: 'wear', rid: newRid(), slot: hatSlot });
      a.send({ t: 'wear', rid: newRid(), slot: teeSlot });
      const dressed = await a.next((m) => m.t === 'profile' && m.outfit.top === 'striped_tee');
      assert.deepEqual(dressed.outfit, { hat: 'straw_hat', top: 'striped_tee' });
      const seen = await b.next((m) => m.t === 'snap' && m.p.find((p) => p.id === 1)?.top === 'striped_tee');
      assert.equal(seen.p.find((p) => p.id === 1).hat, 'straw_hat', '상대 화면에도 옷이 보인다');
      a.send({ t: 'unwear', rid: newRid(), part: 'hat' });
      assert.ok(await a.next((m) => m.t === 'profile' && m.outfit.hat === '' && m.outfit.top === 'striped_tee'), '모자만 벗음');

      // 가구: 상점 안·물·너무 먼 곳에는 못 놓는다
      a.send({ t: 'place', rid: newRid(), slot: chairSlot, x: 0, z: 60, rot: 0 });
      assert.equal((await a.type('error')).code, 'bad_place', '상점 안');
      a.send({ t: 'shop_exit' });
      await a.type('shop_door');
      a.send({ t: 'move', x: 10, y: 0.1, z: 14, yaw: 0, vx: 0, vz: 0 });
      await a.next((m) => m.t === 'snap' && m.p.some((p) => p.x === 10));
      a.send({ t: 'place', rid: newRid(), slot: chairSlot, x: 20, z: 14, rot: 0 });
      assert.equal((await a.type('error')).code, 'bad_place', '너무 멀다');
      a.send({ t: 'place', rid: newRid(), slot: chairSlot, x: 11.2, z: 14.9, rot: 5 });
      const placed = await b.type('placed');
      assert.deepEqual({ item: placed.f.item, x: placed.f.x, z: placed.f.z, rot: placed.f.rot, owner: placed.f.owner }, { item: 'wood_chair', x: 11, z: 15, rot: 1, owner: 1 });
      assert.ok(await a.next((m) => m.t === 'inventory' && m.slots[chairSlot] === null), '설치한 의자는 가방에서 빠진다');

      // 남의 가구는 못 줍는다
      b.send({ t: 'move', x: 11, y: 0.1, z: 14, yaw: 0, vx: 0, vz: 0 });
      await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === 2 && p.x === 11));
      b.send({ t: 'pickup', rid: newRid(), id: placed.f.id });
      assert.equal((await b.type('error')).code, 'not_owner');

      // 저장 → 재시작해도 남는다
      await s.close();
      const s2 = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock() });
      try {
        const a2 = await open(s2);
        const w2 = await enter(a2, { code: w.code, id: A });
        assert.deepEqual(w2.placed.map((f) => f.item), ['wood_chair']);
        assert.equal(w2.prof.outfit.top, 'striped_tee');
        assert.equal(w2.prof.sol, 3450);
        a2.send({ t: 'pickup', rid: newRid(), id: placed.f.id });
        assert.equal((await a2.type('unplaced')).id, placed.f.id);
        const back = await a2.next((m) => m.t === 'inventory' && m.slots.some((x) => x?.id === 'wood_chair'));
        assert.ok(back);
        const saved = JSON.parse(readFileSync(path.join(dir, `${w.code}.json`), 'utf8'));
        assert.equal(saved.schema, 4);
      } finally {
        await s2.close();
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
