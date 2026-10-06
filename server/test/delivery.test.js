import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { storeIngredients } from '../src/delivery.js';
import { Client, uid } from './helpers.js';

const fakeClock = () => ({ hour: () => 12, day: () => 100, gameMs: () => 0, scale: 1 });
// 배달은 거의 바로 출발 (20~30초 × 0.01), 알바는 아주 빨리 달린다.
const BASE = { moveSlackMeters: 500, random: () => 0, saveIntervalMs: 60000, weatherForce: 'clear', startSol: 10_000_000, deliveryTimeScale: 0.01, npcTickRate: 50 };

describe('v13 상점 10개씩 · 식당 창고 · 식재료 배달', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const newRid = () => `d${++rid}`;
  const open = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  async function enter(client, id = uid()) {
    client.send({ t: 'create', v: PROTOCOL_VERSION, uid: id });
    return client.type('welcome');
  }
  async function moveTo(client, x, z) {
    client.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await client.next((m) => m.t === 'snap' && m.p.some((p) => p.x === x && p.z === z));
  }

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-deliv-'));
    server = createServer({ port: 0, saveDir, ...BASE, clock: fakeClock() });
    server.data.shop.delivery.speed = 40;
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('창고에 넣기: 아이템마다 최대치까지만', () => {
    const r = {};
    assert.equal(storeIngredients(r, 'rice', 5, 8), 5);
    assert.equal(storeIngredients(r, 'rice', 5, 8), 3);
    assert.deepEqual(r.storage, { rice: 8 });
  });

  it('상점에서 10개 사기: 도구·가구는 가방, 식재료는 가방 대신 식당 창고로', async () => {
    const a = await open();
    const welcome = await enter(a);
    const door = server.data.shop.door;
    await moveTo(a, door.x, door.z + 1);
    a.send({ t: 'shop_enter' });
    await a.type('shop_door');
    const before = welcome.prof.sol;
    a.send({ t: 'shop_buy', rid: newRid(), item: 'rice', n: 10 });
    const res = await a.type('shop_result');
    assert.equal(res.n, 10);
    assert.equal(res.stored, true, '식재료는 창고로');
    assert.equal(res.sol, before - res.amount);
    const rest = await a.next((m) => m.t === 'rest' && (m.store?.rice ?? 0) === 10);
    assert.equal(rest.store.rice, 10);
    a.send({ t: 'shop_buy', rid: newRid(), item: 'rice', n: 100 });
    assert.equal((await a.type('error')).code, 'bad_item', '한 번에 99개까지');
  });

  it('배달: 주문 → 20~30초(줄임) 뒤 마을톡 "배달 가고 있습니다~" → 알바가 달려와 건넨다 → 상점으로 돌아간다', async () => {
    const a = await open();
    const welcome = await enter(a);
    await moveTo(a, 6, 6);
    a.send({ t: 'deliv_order', rid: newRid(), item: 'egg', n: 10 });
    const ok = await a.type('deliv_ok');
    assert.equal(ok.n, 10);
    assert.ok(ok.eta >= 20 * 0.01 - 1 && ok.eta <= 30, `eta ${ok.eta}`);
    assert.equal(ok.sol, welcome.prof.sol - ok.amount);
    assert.equal(ok.fee, server.data.shop.delivery.fee);
    const start = await a.next((m) => m.t === 'msg' && m.th === 'sys:shop', 5000);
    assert.match(start.m.tx, /달걀 10개, 배달 가고 있습니다~/);
    assert.equal(start.m.f, 'courier');
    const walking = await a.next((m) => m.t === 'couriers' && m.c.some((c) => c.ph === 'walk'), 3000);
    const c = walking.c[0];
    assert.equal(c.to, welcome.id);
    const done = await a.type('deliv_done', 5000);
    assert.deepEqual({ item: done.item, n: done.n, where: done.where }, { item: 'egg', n: 10, where: 'bag' });
    const inv = await a.next((m) => m.t === 'inventory' && m.slots.some((s) => s?.id === 'egg' && s.n === 10));
    assert.ok(inv);
    const thanks = await a.next((m) => m.t === 'msg' && m.th === 'sys:shop');
    assert.match(thanks.m.tx, /배달 완료/);
    const hand = await a.next((m) => m.t === 'couriers' && m.c.some((x) => x.ph === 'hand'), 3000);
    const at = hand.c.find((x) => x.ph === 'hand');
    assert.ok(Math.hypot(at.x - 6, at.z - 6) <= server.data.shop.delivery.hand_range, '내 곁에서 건넨다');
    await a.next((m) => m.t === 'couriers' && m.c.length === 0, 6000);
  });

  it('배달: 식재료만, 한 사람이 동시에 3건까지', async () => {
    const a = await open();
    await enter(a);
    a.send({ t: 'deliv_order', rid: newRid(), item: 'axe', n: 1 });
    assert.equal((await a.type('error')).code, 'not_for_sale');
    server.data.shop.delivery.min_delay_s = 1000;
    server.data.shop.delivery.max_delay_s = 1000;
    try {
      for (let i = 0; i < 3; i++) {
        a.send({ t: 'deliv_order', rid: newRid(), item: 'flour', n: 1 });
        await a.type('deliv_ok');
      }
      a.send({ t: 'deliv_order', rid: newRid(), item: 'flour', n: 1 });
      assert.equal((await a.type('error')).code, 'delivery_busy');
    } finally {
      server.data.shop.delivery.min_delay_s = 20;
      server.data.shop.delivery.max_delay_s = 30;
    }
  });

  it('배달: 상점 안에 있으면 기다리다 식당 창고에 넣어 두고 알린다', async () => {
    const a = await open();
    await enter(a);
    const door = server.data.shop.door;
    await moveTo(a, door.x, door.z + 1);
    const wait = server.data.shop.delivery.wait_s;
    server.data.shop.delivery.wait_s = 0.2;
    try {
      a.send({ t: 'shop_enter' });
      await a.type('shop_door');
      a.send({ t: 'deliv_order', rid: newRid(), item: 'tofu', n: 4 });
      await a.type('deliv_ok');
      const done = await a.type('deliv_done', 5000);
      assert.equal(done.where, 'storage');
      const note = await a.next((m) => m.t === 'msg' && m.th === 'sys:shop' && /식당 창고/.test(m.m.tx), 3000);
      assert.match(note.m.tx, /두부 4개/);
    } finally {
      server.data.shop.delivery.wait_s = wait;
    }
  });
});
