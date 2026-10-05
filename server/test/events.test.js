import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { activeEvents, planDay, sellMultiplier } from '../src/events.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, sleep, uid } from './helpers.js';

const clockAt = (hour) => ({ hour: () => hour, day: () => 100, gameMs: () => 0, scale: 1 });
// random=0: 둥근 나무에서는 항상 '목재', 낚시는 항상 붕어.
const BASE = { port: 0, moveSlackMeters: 200, random: () => 0, saveIntervalMs: 60000, chopCooldownMs: 0, weatherForce: 'clear', fishTimeScale: 0.01, fishHookGraceMs: 500, fishReelScale: 0 };

describe('마을 이벤트', () => {
  const servers = [];
  const clients = [];
  const dirs = [];
  let rid = 0;
  const newRid = () => `e${++rid}`;

  async function start(overrides, hour = 12) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-events-'));
    dirs.push(saveDir);
    const server = createServer({ ...BASE, saveDir, ...overrides, clock: clockAt(hour) });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const welcome = await c.type('welcome');
    return { server, c, welcome };
  }
  async function moveTo(c, x, z) {
    c.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await c.next((m) => m.t === 'snap' && m.p.some((p) => p.x === x && p.z === z));
  }
  async function chopOnce(server, c, treeId = 't01') {
    const t = server.data.trees.get(treeId);
    await moveTo(c, t.x + 1, t.z);
    c.send({ t: 'equip', slot: 1 });
    c.send({ t: 'chop', rid: newRid(), tree: treeId });
    return c.type('chop_result');
  }

  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });

  it('하루 계획: 같은 마을·같은 날은 늘 같고, 열흘 중 대략 daily_chance 만큼 이벤트가 열린다', () => {
    const data = loadGameData(defaultConfig.dataDir, defaultConfig);
    const a = planDay({ seed: 1234, day: 50, events: data.events, data });
    const b = planDay({ seed: 1234, day: 50, events: data.events, data });
    assert.deepEqual(a.daily && { id: a.daily.id, wanted: a.daily.wanted }, b.daily && { id: b.daily.id, wanted: b.daily.wanted });
    let opened = 0;
    const seen = new Set();
    for (let day = 0; day < 400; day++) {
      const plan = planDay({ seed: 777, day, events: data.events, data });
      if (!plan.daily) continue;
      opened += 1;
      seen.add(plan.daily.id);
      for (const id of plan.daily.wanted) assert.ok(data.priceOf(id) > 0, `${id} 는 팔 수 있는 물건`);
    }
    assert.ok(opened > 400 * 0.65 && opened < 400 * 0.85, `이벤트가 열린 날 ${opened}/400`);
    assert.deepEqual([...seen].sort(), data.events.daily.map((d) => d.id).sort(), '계절을 안 보면 모든 하루 이벤트가 나온다');
    // v0.12 계절 축제: 그 계절에만 뽑힌다.
    for (const season of ['spring', 'summer', 'autumn', 'winter']) {
      const ids = new Set();
      for (let day = 0; day < 300; day++) {
        const plan = planDay({ seed: 99, day, events: data.events, data, season });
        if (plan.daily) ids.add(plan.daily.id);
      }
      for (const d of data.events.daily.filter((x) => x.seasons)) assert.equal(ids.has(d.id), d.seasons.includes(season), `${season}: ${d.id}`);
    }
    // 시간대·날씨: 떠돌이 상인은 9~21시, 유성우는 밤의 맑음·흐림에만.
    const forced = planDay({ seed: 1, day: 1, events: data.events, data, force: 'merchant,meteor_shower', forcedWanted: 'wood' });
    assert.deepEqual(activeEvents(forced, 8, 'clear').map((e) => e.id), []);
    assert.deepEqual(activeEvents(forced, 12, 'clear').map((e) => e.id), ['merchant']);
    assert.deepEqual(activeEvents(forced, 22, 'rain').map((e) => e.id), []);
    assert.deepEqual(activeEvents(forced, 23, 'clear').map((e) => e.id), ['meteor_shower']);
    assert.equal(sellMultiplier(activeEvents(forced, 12, 'clear'), 'wood', 'merchant'), 2);
    assert.equal(sellMultiplier(activeEvents(forced, 12, 'clear'), 'crucian', 'merchant'), 0, '상인은 찾는 물건만 산다');
  });

  it('특가 매입의 날: 상점이 고른 물건을 2배 값에 사 준다', async () => {
    const { server, c, welcome } = await start({ eventForce: 'bargain', eventWanted: 'wood' });
    assert.deepEqual(welcome.ev.list, [{ id: 'bargain', wanted: ['wood'], mult: 2 }]);
    await chopOnce(server, c);
    const door = server.data.shop.door;
    await moveTo(c, door.x, door.z + 1);
    c.send({ t: 'shop_enter' });
    await c.type('shop_door');
    c.send({ t: 'shop_sell', rid: newRid(), slot: 5, n: 1 });
    const sold = await c.type('shop_result');
    assert.equal(sold.amount, 12000, '목재 6,000솔 × 2');
  });

  it('떠돌이 상인: 곁에서만, 찾는 물건만 2배로 사고, 귀한 물건을 판다', async () => {
    const { server, c, welcome } = await start({ eventForce: 'merchant', eventWanted: 'wood', startSol: 500000 });
    const merchant = welcome.ev.list.find((e) => e.id === 'merchant');
    assert.deepEqual(merchant.wanted, ['wood']);
    assert.ok(merchant.stock.includes('star_lamp'));
    await chopOnce(server, c);
    c.send({ t: 'shop_sell', rid: newRid(), slot: 5, n: 1, at: 'merchant' });
    assert.equal((await c.type('error')).code, 'merchant_away', '멀리서는 안 된다');
    const spot = server.data.events.daily.find((d) => d.id === 'merchant').spot;
    await moveTo(c, spot.x + 1, spot.z);
    c.send({ t: 'shop_sell', rid: newRid(), slot: 1, n: 1, at: 'merchant' });
    assert.equal((await c.type('error')).code, 'not_wanted', '도끼는 안 산다');
    c.send({ t: 'shop_sell', rid: newRid(), slot: 5, n: 1, at: 'merchant' });
    const sold = await c.type('shop_result');
    assert.deepEqual({ amount: sold.amount, at: sold.at }, { amount: 12000, at: 'merchant' });
    c.send({ t: 'shop_buy', rid: newRid(), item: 'star_lamp', n: 1, at: 'merchant' });
    const bought = await c.type('shop_result');
    assert.deepEqual({ item: bought.item, sol: bought.sol }, { item: 'star_lamp', sol: 500000 + 12000 - 300000 });
    c.send({ t: 'shop_buy', rid: newRid(), item: 'sofa', n: 1, at: 'merchant' });
    assert.equal((await c.type('error')).code, 'not_for_sale');
  });

  it('나무꾼의 날: 한 번 찍으면 두 개', async () => {
    const { server, c, welcome } = await start({ eventForce: 'lumber_day' });
    assert.deepEqual(welcome.ev.list, [{ id: 'lumber_day' }]);
    const result = await chopOnce(server, c);
    assert.equal(result.n, 2);
    const inv = await c.next((m) => m.t === 'inventory' && m.slots[5] !== null);
    assert.deepEqual(inv.slots[5], { id: 'wood', n: 2 });
  });

  it('낚시 대회: 낚을 때마다 상금', async () => {
    const { c } = await start({ eventForce: 'fishing_derby' });
    await moveTo(c, -10.5, 2);
    const r = newRid();
    c.send({ t: 'fish_cast', rid: r, spot: 'lake' });
    await c.type('fish_bite');
    await sleep(120);
    c.send({ t: 'fish_hook', rid: r, reaction: 110 });
    const result = await c.type('fish_result');
    assert.deepEqual({ ok: result.ok, fish: result.fish, bonus: result.bonus }, { ok: true, fish: 'crucian', bonus: 4000 });
    const prof = await c.type('profile');
    assert.equal(prof.sol, 4000);
  });

  it('선물 풍선의 날: 선물이 떨어지고, 가까이 가야 주울 수 있다', async () => {
    const { c } = await start({ eventForce: 'gift_day', eventSpawnScale: 0.001 });
    const dropped = await c.type('drop', 3000);
    assert.equal(dropped.d.kind, 'gift');
    assert.equal(dropped.d.item, undefined, '선물 속은 주울 때까지 비밀');
    c.send({ t: 'collect', rid: newRid(), id: dropped.d.id });
    assert.equal((await c.type('error')).code, 'no_drop');
    await moveTo(c, dropped.d.x + 0.5, dropped.d.z);
    c.send({ t: 'collect', rid: newRid(), id: dropped.d.id });
    const got = await c.type('collect_result');
    assert.equal(got.id, dropped.d.id);
    assert.ok(got.item.length > 0);
    await c.next((m) => m.t === 'drop_gone' && m.id === dropped.d.id && m.by === 1);
  });

  it('유성우: 맑은 밤에 별 조각이 떨어진다', async () => {
    const { welcome, c } = await start({ eventForce: 'meteor_shower', eventSpawnScale: 0.001 }, 22);
    const dropped = welcome.drops.length > 0 ? { d: welcome.drops[0] } : await c.type('drop', 3000);
    assert.deepEqual({ kind: dropped.d.kind, item: dropped.d.item }, { kind: 'star', item: 'star_fragment' });
    const ev = welcome.ev.list.length > 0 ? welcome.ev : await c.type('ev', 3000);
    assert.deepEqual(ev.list.map((e) => e.id), ['meteor_shower']);
  });
});
