import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';

/** 테스트가 마음대로 돌리는 시계. */
function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: 0 };
  return c;
}

// random=0: 나무에서는 항상 '목재', 부탁은 항상 첫 템플릿(목재 3개). 비가 오면 주민이 집 앞에 머물러서 찾아가기 쉽다.
const BASE = { moveSlackMeters: 200, random: () => 0, reconnectGraceMs: 300, saveIntervalMs: 60000, chopCooldownMs: 0, weatherForce: 'rain', questChance: 1, eventForce: 'none' };

describe('마을: 나무 베기 · 주민 대화 · 부탁 · 날씨', () => {
  let saveDir;
  let server;
  let clock;
  const clients = [];
  const open = async (s = server) => {
    const c = new Client(s.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  /** 설정이 다른 서버를 따로 띄운다. 검사가 실패해도 서버를 닫는다. */
  async function withServer(extra, fn) {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-village-x-'));
    const s = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock(), ...extra });
    try {
      await fn(s, dir);
    } finally {
      await s.close();
      rmSync(dir, { recursive: true, force: true });
    }
  }
  async function enter(client, { code, id = uid() } = {}) {
    client.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: id, code } : { t: 'create', v: PROTOCOL_VERSION, uid: id });
    return client.type('welcome');
  }
  async function moveTo(client, x, z) {
    client.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await client.next((m) => m.t === 'snap' && m.p.some((p) => p.x === x && p.z === z));
  }
  let rid = 0;
  const newRid = () => `v${++rid}`;
  const tree = (id) => server.data.trees.get(id);

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-village-'));
    clock = fakeClock();
    server = createServer({ port: 0, saveDir, ...BASE, clock });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('입장하면 시계·날씨·나무·주민·프로필을 받는다', async () => {
    const a = await open();
    const w = await enter(a);
    assert.equal(w.w, 'rain');
    assert.equal(w.trees.length, server.data.trees.size);
    assert.ok(w.trees.every((t) => t.s === 'grown'));
    assert.deepEqual(w.npcs.map((n) => n.id).sort(), ['danchu', 'haerang', 'morak', 'mujin', 'rara', 'tongtong']);
    assert.ok(w.npcs.every((n) => typeof n.m === 'string'), '주민 기분이 함께 온다');
    const { stocks, trades, loans, credit, income, worth, civ, ...prof } = w.prof;
    assert.deepEqual({ partner: civ.partner, resident: civ.resident, card: civ.card }, { partner: 0, resident: false, card: false }, '처음엔 혼자 · 전입 전 · 카드 없음');
    assert.deepEqual(prof, { sol: 0, quests: [], friends: {}, outfit: { hat: '', top: '' }, emotes: { known: ['hello'], quick: ['hello'] }, face: { eyes: 'round', eye_color: 'cocoa', nose: 'button', mouth: 'smile', skin: 'peach', hair: 'bob', hair_color: 'brown' } });
    assert.deepEqual({ stocks, trades, loans, income, worth }, { stocks: {}, trades: [], loans: [], income: { week: 0, year: 0 }, worth: { assets: 0, debt: 0, net: 0 } }, '처음엔 주식·대출·소득이 없다');
    assert.ok(credit.score > 0 && credit.grade >= 1 && credit.grade <= 10);
    assert.equal(w.market.stocks.length, server.data.market.stocks.length, '입장하면 증권 시세를 받는다');
    assert.equal(w.homes.index, 1);
    assert.equal(w.rest.open, false);
    assert.deepEqual(w.flowers, []);
    assert.deepEqual(w.museum, { fish: {} });
    assert.deepEqual(w.shop, { level: 1, points: 0, next: 150000 });
    assert.deepEqual(w.placed, []);
    assert.equal(typeof w.clock.g, 'number');
    assert.equal(w.players[0].held, 'rod');
  });

  it('도끼를 들고 다 자란 나무 곁에서만 벨 수 있고, 목재가 인벤토리로 들어온다', async () => {
    const a = await open();
    const w = await enter(a);
    const b = await open();
    await enter(b, { code: w.code });
    const t = tree('t13');
    await moveTo(a, t.x + 1, t.z);
    a.send({ t: 'chop', rid: newRid(), tree: 't13' });
    assert.equal((await a.type('error')).code, 'no_tool', '낚싯대를 든 채로는 못 벤다');

    a.send({ t: 'equip', slot: 1 });
    assert.equal((await a.type('inventory')).held, 1);
    const held = await b.next((m) => m.t === 'snap' && m.p.find((p) => p.id === 1)?.held === 'axe');
    assert.ok(held, '상대에게 손에 든 도구가 보인다');

    a.send({ t: 'chop', rid: newRid(), tree: 't01' });
    assert.equal((await a.type('error')).code, 'not_near_tree');

    for (let i = 1; i <= 3; i++) {
      const r = newRid();
      a.send({ t: 'chop', rid: r, tree: 't13' });
      const res = await a.type('chop_result');
      assert.deepEqual({ rid: res.rid, item: res.item, felled: res.felled }, { rid: r, item: 'wood', felled: i === 3 });
      const inv = await a.type('inventory');
      assert.deepEqual(inv.slots[5], { id: 'wood', n: i });
      const tb = await b.next((m) => m.t === 'tree' && m.id === 't13');
      assert.equal(tb.s, i === 3 ? 'stump' : 'grown');
      assert.equal((await b.type('act')).kind, 'chop', '상대 화면에서도 도끼질이 보인다');
    }
    a.send({ t: 'chop', rid: newRid(), tree: 't13' });
    assert.equal((await a.type('error')).code, 'tree_not_ready', '그루터기는 못 벤다');
  });

  it('시간이 지나면 그루터기가 묘목 → 어린 나무 → 나무로 자란다', async () => {
    const a = await open();
    const w = await enter(a);
    await moveTo(a, tree('t14').x + 1, tree('t14').z);
    a.send({ t: 'equip', slot: 1 });
    for (let i = 0; i < 3; i++) {
      a.send({ t: 'chop', rid: newRid(), tree: 't14' });
      await a.type('chop_result');
    }
    assert.equal(server.rooms.getRoom(w.code).trees.get('t14').s, 'stump');
    a.inbox.length = 0; // 도끼질 때 받은 tree 메시지는 버린다
    const minutes = server.data.treeRules.regrowMinutes;
    clock.g += minutes.stump * 60000;
    assert.equal((await a.next((m) => m.t === 'tree' && m.id === 't14', 2500)).s, 'sapling');
    clock.g += minutes.sapling * 60000;
    assert.equal((await a.next((m) => m.t === 'tree' && m.id === 't14', 2500)).s, 'young');
    a.send({ t: 'chop', rid: newRid(), tree: 't14' });
    assert.equal((await a.type('error')).code, 'tree_not_ready', '어린 나무는 못 벤다');
    clock.g += minutes.young * 60000;
    assert.equal((await a.next((m) => m.t === 'tree' && m.id === 't14', 2500)).s, 'grown');
  });

  it('가방이 가득 차면 나무를 찍지 않는다', () => withServer({ quickSlots: 2, inventoryCapacity: 0 }, async (s) => {
    const a = await open(s);
    const w = await enter(a);
    assert.equal(w.inv.slots.length, 2);
    const t = s.data.trees.get('t15');
    a.send({ t: 'move', x: t.x + 1, y: 0.1, z: t.z, yaw: 0, vx: 0, vz: 0 });
    await a.next((m) => m.t === 'snap');
    a.send({ t: 'equip', slot: 1 });
    a.send({ t: 'chop', rid: newRid(), tree: 't15' });
    assert.equal((await a.type('error')).code, 'inventory_full');
    assert.equal(s.rooms.getRoom(w.code).trees.get('t15').c, 0);
  }));

  it('주민과 대화 → 부탁 수락 → 아이템을 모아 완료하면 솔·친밀도를 받는다', async () => {
    const a = await open();
    const w = await enter(a);
    const mujin = w.npcs.find((n) => n.id === 'mujin');
    a.send({ t: 'talk', rid: newRid(), npc: 'mujin' });
    assert.equal((await a.type('error')).code, 'not_near_npc');

    await moveTo(a, mujin.x + 1.5, mujin.z);
    a.send({ t: 'talk', rid: newRid(), npc: 'mujin' });
    const open1 = await a.type('talk_open');
    assert.equal(open1.first, true);
    assert.equal(open1.teach, 'angry');
    assert.equal(typeof open1.m, 'string');
    assert.equal(open1.f, 2, '오늘 처음 말 걸면 친밀도 +2');
    assert.deepEqual({ kind: open1.offer.kind, item: open1.offer.item, n: open1.offer.n, reward: open1.offer.reward }, { kind: 'deliver', item: 'wood', n: 3, reward: 22000 });
    const talking = await a.next((m) => m.t === 'npcs' && m.n.find((n) => n.id === 'mujin')?.talk === 1);
    assert.ok(talking, '대화 중인 주민은 상대가 누구인지 방송된다');

    a.send({ t: 'quest_accept', rid: newRid() });
    const accepted = await a.type('quest_accepted');
    assert.equal(accepted.quest.have, 0);
    const prof = await a.next((m) => m.t === 'profile' && m.quests.length === 1);
    assert.deepEqual(prof.emotes.known, ['hello', 'angry'], '처음 말 건 날 무진이 감정표현을 가르쳐 줬다');
    a.send({ t: 'quest_turnin', rid: newRid(), quest: accepted.quest.id });
    assert.equal((await a.type('error')).code, 'quest_not_ready');
    a.send({ t: 'talk_end' });

    // 다른 주민과 이야기하는 중에는 그 부탁을 완료할 수 없다
    // 목재 3개 모으기
    const t = tree('t09');
    await moveTo(a, t.x + 1, t.z);
    a.send({ t: 'equip', slot: 1 });
    for (let i = 0; i < 3; i++) {
      a.send({ t: 'chop', rid: newRid(), tree: 't09' });
      await a.type('chop_result');
    }
    const progressed = await a.next((m) => m.t === 'profile' && m.quests[0]?.have === 3);
    assert.ok(progressed, '부탁 진행도가 갱신된다');

    a.send({ t: 'quest_turnin', rid: newRid(), quest: accepted.quest.id });
    assert.equal((await a.type('error')).code, 'not_talking', '부탁한 주민과 대화 중이어야 한다');
    await moveTo(a, mujin.x + 1.5, mujin.z);
    a.send({ t: 'talk', rid: newRid(), npc: 'mujin' });
    const open2 = await a.type('talk_open');
    assert.equal(open2.first, false);
    assert.equal(open2.ready, true);
    assert.equal(open2.offer, undefined);
    a.send({ t: 'quest_turnin', rid: newRid(), quest: accepted.quest.id });
    const done = await a.type('quest_done');
    assert.deepEqual({ reward: done.reward, sol: done.sol }, { reward: 22000, sol: 22000 });
    const inv = await a.next((m) => m.t === 'inventory' && !m.slots.some((s) => s?.id === 'wood'));
    assert.ok(inv, '목재 3개가 빠진다');
    const final = await a.next((m) => m.t === 'profile' && m.quests.length === 0 && m.sol === 22000);
    assert.equal(final.friends.mujin, 8, '처음 대화 +2, 같은 날 두 번째 대화 +1, 부탁 완료 +5');
    a.send({ t: 'talk', rid: newRid(), npc: 'mujin' });
    assert.equal((await a.type('talk_open')).offer, undefined, '같은 날 같은 주민은 부탁을 한 번만 한다');
  });

  it('다른 사람과 이야기 중인 주민에게는 말을 걸 수 없고, 멀어지면 대화가 끝난다', async () => {
    const a = await open();
    const w = await enter(a);
    const b = await open();
    await enter(b, { code: w.code });
    const morak = w.npcs.find((n) => n.id === 'morak');
    await moveTo(a, morak.x + 1, morak.z);
    await moveTo(b, morak.x - 1, morak.z);
    a.send({ t: 'talk', rid: newRid(), npc: 'morak' });
    await a.type('talk_open');
    b.send({ t: 'talk', rid: newRid(), npc: 'morak' });
    assert.equal((await b.type('error')).code, 'npc_busy');
    a.send({ t: 'move', x: morak.x + 20, y: 0.1, z: morak.z, yaw: 0, vx: 0, vz: 0 });
    assert.equal((await a.type('talk_closed')).npc, 'morak');
    b.send({ t: 'talk', rid: newRid(), npc: 'morak' });
    assert.equal((await b.type('talk_open')).npc, 'morak');
  });

  it('수락하지 않은 부탁은 받을 수 없고, 낚시 중에는 말을 걸 수 없다', async () => {
    const a = await open();
    const w = await enter(a);
    a.send({ t: 'quest_accept', rid: newRid() });
    assert.equal((await a.type('error')).code, 'no_offer');
    const haerang = w.npcs.find((n) => n.id === 'haerang');
    // 해랑의 집 앞은 호숫가: 낚시를 시작한 뒤 말을 걸어 본다
    await moveTo(a, haerang.x, haerang.z - 3.5);
    a.send({ t: 'fish_cast', rid: newRid(), spot: 'lake' });
    await a.type('fish_started');
    a.send({ t: 'talk', rid: newRid(), npc: 'haerang' });
    assert.equal((await a.type('error')).code, 'already_fishing');
  });

  it('뇌우에는 번개가 방송되고, 날씨가 바뀌면 알린다', () => withServer({ weatherForce: 'thunder', lightningMinMs: 10, lightningMaxMs: 20 }, async (s) => {
    const a = await open(s);
    const w = await enter(a);
    assert.equal(w.w, 'thunder');
    const bolt = await a.type('lightning', 3500);
    assert.ok(bolt.power >= 0.6 && bolt.power <= 1);
    s.config.weatherForce = 'clear';
    assert.ok(await a.next((m) => m.t === 'weather' && m.w === 'clear', 2500));
  }));

  it('옛 저장 파일(schema 1)은 칸 인벤토리로 옮기고 도구를 챙겨 준다', async () => {
    const A = uid();
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-legacy-'));
    writeFileSync(
      path.join(dir, 'GCYABH.json'),
      JSON.stringify({ schema: 1, code: 'GCYABH', createdAt: 1, world: { totalCatches: 2, species: { carp: 2 } }, profiles: { [A]: { slot: 1, items: [{ id: 'carp', n: 2 }], catches: 2, x: 1, y: 0.1, z: 2, yaw: 0 } } }),
    );
    const s = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock() });
    const a = await open(s);
    const w = await enter(a, { code: 'GCYABH', id: A });
    assert.deepEqual(w.inv.slots.slice(0, 2), [{ id: 'rod', n: 1 }, { id: 'axe', n: 1 }]);
    assert.deepEqual(w.inv.slots[5], { id: 'carp', n: 2 });
    assert.equal(w.inv.held, 0);
    await s.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('schema 4 저장은 솔·상점 포인트를 현실 단위(×100)로 옮겨 읽는다', async () => {
    const A = uid();
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-money-'));
    writeFileSync(
      path.join(dir, 'MNYRSV.json'),
      JSON.stringify({ schema: 4, code: 'MNYRSV', createdAt: 1, world: { shopPoints: 1600 }, profiles: { [A]: { slot: 1, slots: [], sol: 345, x: 1, y: 0.1, z: 2, yaw: 0 } } }),
    );
    const s = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock() });
    const a = await open(s);
    const w = await enter(a, { code: 'MNYRSV', id: A });
    assert.equal(w.prof.sol, 34500);
    assert.deepEqual({ level: w.shop.level, points: w.shop.points }, { level: 2, points: 160000 });
    await s.close();
    rmSync(dir, { recursive: true, force: true });
  });

  it('부탁·솔은 서버를 껐다 켜도 남는다', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-quest-save-'));
    const A = uid();
    const s1 = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock() });
    const a = await open(s1);
    const w = await enter(a, { id: A });
    const npc = w.npcs.find((n) => n.id === 'tongtong');
    a.send({ t: 'move', x: npc.x + 1, y: 0.1, z: npc.z, yaw: 0, vx: 0, vz: 0 });
    await a.next((m) => m.t === 'snap');
    a.send({ t: 'talk', rid: newRid(), npc: 'tongtong' });
    await a.type('talk_open');
    a.send({ t: 'quest_accept', rid: newRid() });
    const { quest } = await a.type('quest_accepted');
    await s1.close();
    const s2 = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock() });
    const a2 = await open(s2);
    const w2 = await enter(a2, { code: w.code, id: A });
    assert.equal(w2.prof.quests[0].id, quest.id);
    assert.equal(w2.prof.friends.tongtong, 2);
    await sleep(10);
    await s2.close();
    rmSync(dir, { recursive: true, force: true });
  });
});
