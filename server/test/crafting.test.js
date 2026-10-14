// v0.22 제작: 맨손 · 작업대 · 공용 작업대 등급, 재료 · 가방 검사, 요청 ID 중복.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { benchTier, craftProblem } from '../src/crafting.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const count = (inv, id) => inv.slots.reduce((sum, s) => sum + (s && s.id === id ? s.n : 0), 0);

describe('v0.22 제작 규칙', () => {
  it('모든 제작법은 아는 재료로, 등급은 0 · 1 · 2, 공용 작업대는 2등급', () => {
    assert.ok(data.crafting.recipes.size >= 15);
    for (const r of data.crafting.recipes.values()) assert.ok(r.needs.length >= 1, r.id);
    assert.ok(data.crafting.publicBenches.every((b) => b.tier === 2));
    // 생존용품: 붕대 · 횃불 · 바리케이드 · 덫 · 손전등 · 정수 물병 · 비상식량.
    for (const id of ['bandage', 'torch', 'barricade', 'spike_trap', 'flashlight', 'clean_water', 'hardtack']) assert.ok(data.crafting.recipes.has(id), id);
  });

  it('작업대 등급: 맨손 0, 내 작업대 곁 1, 공용 작업대 곁 2, 집 안은 그 집 작업대', () => {
    const c = data.crafting;
    const pub = c.publicBenches[0];
    assert.equal(benchTier(c, { x: 0, z: 0 }), 0);
    assert.equal(benchTier(c, { x: 10, z: 10, placed: [{ item: 'workbench', x: 11, z: 10 }] }), 1);
    assert.equal(benchTier(c, { x: 10, z: 10, placed: [{ item: 'workbench', x: 20, z: 10 }] }), 0, '멀면 안 된다');
    assert.equal(benchTier(c, { x: pub.x + 1, z: pub.z }), 2);
    assert.equal(benchTier(c, { x: pub.x + 1, z: pub.z, inside: true }), 0, '상점 안');
    assert.equal(benchTier(c, { x: 0, z: 1300, homeItems: [{ item: 'workbench' }] }), 1);
    assert.equal(benchTier(c, { x: 0, z: 1300, homeItems: [{ item: 'sofa' }] }), 0);
  });

  it('재료가 모자라면 not_enough_items, 만든 것이 들어갈 자리가 없으면 inventory_full', () => {
    const r = data.crafting.recipes.get('rope');
    assert.equal(craftProblem([{ id: 'cloth', n: 1 }, null], r, 1, data.limitOf), 'not_enough_items');
    assert.equal(craftProblem([{ id: 'cloth', n: 2 }, null], r, 1, data.limitOf), null);
    const full = [{ id: 'cloth', n: 30 }, { id: 'rod', n: 1 }];
    assert.equal(craftProblem(full, r, 1, data.limitOf), 'inventory_full');
  });
});

describe('v0.22 제작대에서 만들기', () => {
  let saveDir;
  let server;
  const clients = [];
  let n = 0;
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-craft-'));
    server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 2000,
      startItems: 'cloth:6,wood:8,branch:4,scrap_metal:3,hardwood:2',
    });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });
  const ask = async (c, msg) => {
    const rid = `cr-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, 3000);
  };
  const moveTo = async (c, x, z) => {
    c.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await sleep(150);
  };

  it('맨손 → 작업대 놓기 → 작업대 곁 → 공용 작업대 곁', async () => {
    const a = new Client(server.port);
    clients.push(a);
    await a.opened;
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await a.type('welcome');
    assert.equal(count(w.inv, 'cloth'), 6);
    // 맨손: 밧줄 (천 2 → 1), 두 개 한꺼번에.
    const rope = await ask(a, { t: 'craft', recipe: 'rope', n: 2 });
    assert.equal(rope.t, 'crafted');
    assert.deepEqual([rope.item, rope.n, rope.tier], ['rope', 2, 0]);
    let inv = await a.type('inventory');
    assert.equal(count(inv, 'cloth'), 2);
    assert.equal(count(inv, 'rope'), 2);
    // 같은 요청 ID 를 다시 보내도 한 번만 만든다.
    a.send({ t: 'craft', recipe: 'rope', n: 1, rid: `cr-${n}` });
    await sleep(200);
    assert.ok(!a.inbox.some((m) => m.t === 'crafted' && m.rid === `cr-${n}` && m !== rope));
    // 작업대 등급이 모자라면 거절.
    assert.equal((await ask(a, { t: 'craft', recipe: 'charcoal', n: 1 })).code, 'not_at_bench');
    // 맨손으로 작업대를 만들어 시내 빈 풀밭에 놓는다.
    assert.equal((await ask(a, { t: 'craft', recipe: 'workbench', n: 1 })).t, 'crafted');
    inv = await a.type('inventory');
    const spot = { x: -43, z: 64 };
    await moveTo(a, spot.x, spot.z + 1.5);
    const slot = inv.slots.findIndex((s) => s?.id === 'workbench');
    const placed = await ask(a, { t: 'place', slot, x: spot.x, z: spot.z, rot: 0 });
    assert.equal(placed.t, 'placed', placed.code);
    const charcoal = await ask(a, { t: 'craft', recipe: 'charcoal', n: 1 });
    assert.deepEqual([charcoal.t, charcoal.tier], ['crafted', 1]);
    assert.equal((await ask(a, { t: 'craft', recipe: 'nails', n: 1 })).code, 'not_at_bench', '못은 공구 창고에서');
    // 공용 작업대 (공구 창고).
    const pub = data.crafting.publicBenches[0];
    await moveTo(a, pub.x + 1.5, pub.z);
    const nails = await ask(a, { t: 'craft', recipe: 'nails', n: 3 });
    assert.deepEqual([nails.t, nails.n, nails.tier], ['crafted', 6, 2]);
    assert.equal((await ask(a, { t: 'craft', recipe: 'nails', n: 1 })).code, 'not_enough_items', '고철을 다 썼다');
    assert.equal((await ask(a, { t: 'craft', recipe: 'nope', n: 1 })).code, 'bad_item');
    assert.equal((await ask(a, { t: 'craft', recipe: 'rope', n: 99 })).code, 'bad_item', '한 번에 10개까지');
  });
});
