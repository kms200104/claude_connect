import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { cardCashback, didimdolTerms, eligibility } from '../src/civic.js';
import { combineIncome } from '../src/economy.js';
import { zoneWeight } from '../src/fishing.js';
import { netCatch, newShoal, shallowAt, stepShoal } from '../src/shoal.js';
import { beachSpot, hitSpot, onBeach } from '../src/dig.js';
import { lenientSteps, stepMinMs } from '../src/kitchen.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: Date.UTC(2026, 9, 5, 10) };
  return c;
}

describe('v0.9 계산', () => {
  it('동사무소 자격: 나이·전입·무주택·소득, 신혼부부는 디딤돌 조건이 넉넉하다', () => {
    const youth = data.programs.get('youth_rent');
    const base = { age: 29, resident: true, married: false, homes: 0, income: 10000000, weekIncome: 0, sol: 0, liquid: 0, received: {}, week: 10 };
    assert.equal(eligibility(youth, base).ok, true);
    assert.deepEqual(eligibility(youth, { ...base, resident: false }).reasons, ['전입신고가 필요해요']);
    assert.equal(eligibility(youth, { ...base, age: 35 }).ok, false);
    assert.equal(eligibility(youth, { ...base, homes: 1 }).ok, false);
    assert.equal(eligibility(youth, { ...base, received: { youth_rent: { weeksLeft: 3 } } }).ok, false, '이미 받는 중');
    const didim = data.programs.get('didimdol');
    const single = didimdolTerms(didim, { ...base, income: 30000000 });
    const couple = didimdolTerms(didim, { ...base, income: 30000000, married: true });
    assert.equal(single.rate, 0.0315);
    assert.equal(couple.rate, 0.0295, '신혼 우대 0.2%p');
    assert.equal(single.limit, 250000000);
    assert.equal(couple.limit, 320000000);
    assert.equal(single.ltv, 0.8, '생애최초 LTV 80%');
    assert.equal(eligibility(didim, { ...base, income: 70000000 }).ok, false, '혼자면 6천만 이하');
    assert.equal(eligibility(didim, { ...base, income: 70000000, married: true }).ok, true, '신혼은 8천5백만 이하');
  });

  it('천안사랑카드 캐시백은 10%, 주마다 4만 6천 솔까지', () => {
    const card = data.programs.get('local_card');
    assert.equal(cardCashback(card, { week: 3, back: 0 }, 3, 100000), 10000);
    assert.equal(cardCashback(card, { week: 3, back: 40000 }, 3, 100000), 6000);
    assert.equal(cardCashback(card, { week: 2, back: 46000 }, 3, 100000), 10000, '새 주에는 한도가 다시');
    assert.equal(cardCashback(card, null, 3, 100000), 0);
  });

  it('부부합산 소득: 주별로 끝에서부터 더한다', () => {
    const c = combineIncome([{ amount: 5, history: [1, 2, 3] }, { amount: 7, history: [10, 20] }]);
    assert.deepEqual(c, { amount: 12, history: [1, 12, 23] });
  });

  it('얕은 물은 작은 물고기, 깊은 물은 큰 물고기가 잘 문다', () => {
    const lake = data.spots.get('lake');
    const zone = lake.shallows[0];
    assert.ok(shallowAt(lake, zone.x - zone.half_x - 1, zone.z), '여울 곁 물가');
    assert.equal(shallowAt(lake, lake.x + lake.half_x + 1, lake.z), null, '반대쪽은 깊은 물');
    assert.equal(zoneWeight('shallow', { size: 'L' }), 0);
    assert.ok(zoneWeight('shallow', { size: 'S' }) > zoneWeight('deep', { size: 'S' }));
    assert.ok(zoneWeight('deep', { size: 'L' }) > 1);
  });

  it('여울 물고기는 사람에게서 달아나고, 구석에 몰리면 뜰채에 걸린다', () => {
    const rules = data.dig.net;
    const zone = data.spots.get('lake').shallows[0];
    const shoal = newShoal(zone);
    shoal.fish.push({ id: 1, sp: 'loach', size: 'S', x: zone.x, z: zone.z, vx: 0, vz: 0, turnAt: 1e12 });
    const person = { x: zone.x, z: zone.z - 1 };
    for (let i = 0; i < 20; i++) stepShoal(shoal, [person], rules, 0.1, 0, Math.random);
    const f = shoal.fish[0];
    assert.ok(f.z > zone.z + 1, '사람 반대쪽으로 달아난다');
    assert.ok(f.z <= zone.z + zone.half_z, '여울 밖으로는 못 나간다');
    // 벽에 몰리면 잠깐 지쳐서 옆으로도 느리게 빠져나간다.
    for (let i = 0; i < 20; i++) stepShoal(shoal, [{ x: f.x, z: f.z - 1 }], rules, 0.1, 0, Math.random);
    assert.ok(f.tiredUntil > 0, '구석에 몰리면 지친다');
    const before = f.x;
    stepShoal(shoal, [{ x: f.x - 0.4, z: f.z - 0.4 }], rules, 0.1, 0, Math.random);
    assert.ok(Math.abs(f.x - before) <= rules.flee_speed * rules.cornered_slow * 0.1 + 1e-6, '지친 물고기는 느리다');
    // 두 사람이 들어오면 우왕좌왕.
    stepShoal(shoal, [person, { x: zone.x + 0.5, z: zone.z }], rules, 0.1, 0, Math.random);
    assert.equal(shoal.panic, true);
    assert.equal(netCatch(shoal, f.x, f.z, 1.1, 3).length, 1);
    assert.equal(shoal.fish.length, 0);
  });

  it('조개 숨구멍: 둘이 같이 파면 한 번에 두 칸', () => {
    const spot = { hp: 3, hits: [] };
    assert.deepEqual(hitSpot(spot, 1, 0, 3000), { done: false, coop: false });
    assert.deepEqual(hitSpot(spot, 2, 500, 3000), { done: true, coop: true });
    const island = data.layout.island;
    for (let i = 0; i < 30; i++) {
      const at = beachSpot(island, Math.random);
      assert.ok(onBeach(island, at.x, at.z), `${at.x},${at.z} 가 모래밭`);
    }
  });

  it('요리 분담: 동작마다 최소 시간, 둘이 만들면 판정 창이 넓다', () => {
    assert.equal(stepMinMs(data.cookSteps.mix), 1300);
    assert.equal(lenientSteps(data.cookSteps, 1.15).grill.window_ms, data.cookSteps.grill.window_ms * 1.15);
  });
});

describe('v0.9 서버 연동 (같이 하기 · 동사무소 · 여울 · 삽)', () => {
  let saveDir;
  let server;
  let clock;
  const clients = [];
  const open = async () => {
    const c = new Client(server.port);
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
  let rid = 0;
  const newRid = () => `n${++rid}`;
  const roomOf = (code) => [...server.rooms.rooms.values()].find((r) => r.code === code);
  async function pair() {
    const a = await open();
    const wa = await enter(a);
    const b = await open();
    const wb = await enter(b, { code: wa.code });
    return { a, b, wa, wb, room: roomOf(wa.code) };
  }
  /** 가방에서 그 도구를 퀵슬롯 3번(2)으로 옮겨 든다. */
  async function hold(client, welcome, item) {
    const from = welcome.inv.slots.findIndex((s) => s?.id === item);
    if (from !== 2) {
      client.send({ t: 'inv_move', rid: newRid(), from, to: 2 });
      await client.next((m) => m.t === 'inventory' && m.slots[2]?.id === item);
    }
    client.send({ t: 'equip', slot: 2 });
    await client.next((m) => m.t === 'inventory' && m.held === 2);
  }

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v09-'));
    clock = fakeClock();
    server = createServer({
      port: 0,
      saveDir,
      clock,
      moveSlackMeters: 400,
      random: () => 0.5,
      weatherForce: 'clear',
      eventForce: 'none',
      startSol: 1000000,
      startItems: 'rice:1,laver:1,shovel:1,fishing_net:1',
      restSpawnScale: 0.02,
      chopCooldownMs: 0,
    });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('혼인신고: 두 사람이 민원 창구에서 → 한 세대, 지갑이 하나로 합쳐진다', async () => {
    const { a, b, wa, wb, room } = await pair();
    const clerk = data.civic.staff.find((s) => s.desk === 'civil');
    a.send({ t: 'marry_propose', rid: newRid(), to: wb.id });
    assert.equal((await a.type('error')).code, 'not_at_civic');
    await moveTo(a, clerk.x - 0.5, clerk.z + 1.5);
    await moveTo(b, clerk.x + 0.5, clerk.z + 1.5);
    a.send({ t: 'marry_propose', rid: newRid(), to: wb.id });
    assert.equal((await a.type('civic_result')).service, 'marriage_asked');
    assert.equal((await b.type('marry_proposal')).from, wa.id);
    b.send({ t: 'marry_answer', rid: newRid(), accept: true });
    const h = await a.type('household');
    assert.deepEqual(h.members.sort(), [wa.id, wb.id].sort());
    assert.equal(h.sol, 2000000, '두 지갑을 합쳤다');
    const pa = await a.next((m) => m.t === 'profile' && m.civ.partner === wb.id);
    assert.equal(pa.sol, 2000000);
    // a 가 쓴 돈이 b 의 지갑에서도 빠진다.
    a.send({ t: 'stock_order', rid: newRid(), id: 'SBE', side: 'buy', qty: 1 });
    const trade = await a.type('stock_result');
    const pb = await b.next((m) => m.t === 'profile' && m.sol === trade.sol, 2000);
    assert.equal(pb.sol, 2000000 - trade.amount, '같은 지갑');
    a.send({ t: 'marry_propose', rid: newRid(), to: wb.id });
    assert.equal((await a.type('error')).code, 'already_married');
    // 가족관계증명서
    a.send({ t: 'civic_civil', rid: newRid(), service: 'family_cert' });
    const cert = await a.type('civic_result');
    assert.equal(cert.doc.spouse, wb.id);
    // 저장했다가 다시 읽어도 세대가 그대로.
    server.rooms.save(room);
    await server.store.flush?.();
    const saved = room.toSave();
    assert.equal(saved.world.households.length, 1);
    assert.equal(saved.profiles[room.players.get(wa.id).uid].household, h.id);
  });

  it('동사무소: 전입신고 → 청년월세(주마다 지급) · 천안사랑카드 캐시백 · 디딤돌(고정금리) · 햇살론유스', async () => {
    const a = await open();
    const w = await enter(a);
    const room = roomOf(w.code);
    const desk = (d) => data.civic.staff.find((s) => s.desk === d);
    assert.equal(w.civic.resident, false);
    const welfare = desk('welfare');
    await moveTo(a, welfare.x, welfare.z + 1.6);
    a.send({ t: 'civic_apply', rid: newRid(), program: 'youth_rent' });
    assert.equal((await a.type('error')).code, 'not_eligible', '전입신고 전');
    const civil = desk('civil');
    await moveTo(a, civil.x, civil.z + 1.6);
    a.send({ t: 'civic_civil', rid: newRid(), service: 'move_in' });
    assert.equal((await a.type('civic_result')).service, 'move_in');
    a.send({ t: 'civic_civil', rid: newRid(), service: 'resident_copy' });
    const copy = await a.type('civic_result');
    assert.equal(copy.fee, 400);
    assert.equal(copy.doc.title, '주민등록표 등본');
    a.send({ t: 'civic_apply', rid: newRid(), program: 'local_card' });
    await a.type('civic_result');
    await moveTo(a, welfare.x, welfare.z + 1.6);
    a.send({ t: 'civic_apply', rid: newRid(), program: 'youth_rent' });
    const rent = await a.type('civic_result');
    assert.deepEqual([rent.weekly, rent.weeks], [200000, 24]);
    const finance = desk('finance');
    await moveTo(a, finance.x, finance.z + 1.6);
    a.send({ t: 'civic_apply', rid: newRid(), program: 'didimdol' });
    const appr = await a.type('civic_result');
    assert.equal(appr.approval.rate, 0.0285, '소득 2천만 이하 구간');
    a.send({ t: 'loan_take', rid: newRid(), amount: 5000000, product: 'sunshine_youth' });
    const sun = await a.type('loan_result');
    assert.equal(sun.loan.rate, 0.04, '소득이 없으면 4.0%');
    assert.equal(sun.loan.fixed, true);
    // 디딤돌로 아파트 사기 (승인 한도·LTV 80% 안).
    const p = room.players.get(w.id).profile;
    p.sol = 200000000;
    a.send({ t: 'apt_buy', rid: newRid(), unit: '103-301', loan: 150000000, policy: 'didimdol' });
    const apt = await a.type('apt_result');
    assert.deepEqual([apt.policy, apt.rate], ['didimdol', 0.0285]);
    // 공항 기념품을 사면 캐시백.
    const pilot = data.airport.pilot;
    await moveTo(a, pilot.x + 1, pilot.z + 1);
    const item = data.airport.stock[0];
    a.send({ t: 'shop_buy', rid: newRid(), item, n: 1, at: 'airport' });
    const bought = await a.type('shop_result');
    assert.equal(bought.back, Math.min(46000, Math.floor((bought.amount * 0.1) / 10) * 10), '10% 캐시백');
    // 한 주가 지나면 청년월세가 들어오고, 정책대출 금리는 그대로.
    room.baseRate = 0.04;
    clock.d += 7;
    const week = await a.type('week', 3000);
    assert.equal(week.grant, 200000);
    assert.ok(p.loans.filter((l) => l.fixed).every((l) => l.rate === 0.0285 || l.rate === 0.04));
  });

  it('식당 같이 하기: 재료를 합치고, 요리 동작을 나눠 동시에 → 팀 보너스를 나눠 갖는다', async () => {
    const { a, b, wa, wb } = await pair();
    const rest = data.restaurant;
    await moveTo(a, rest.counter.x, rest.counter.z);
    await moveTo(b, rest.counter.x + 1, rest.counter.z);
    a.send({ t: 'rest_open', rid: newRid() });
    await a.type('rest_opened');
    b.send({ t: 'rest_cook', rid: newRid(), order: 'o1', step: 0 });
    assert.equal((await b.type('error')).code, 'not_staff');
    b.send({ t: 'rest_join', rid: newRid() });
    await b.type('rest_joined');
    // 쌀·김이 한 사람에 하나씩 → 합치면 주먹밥 두 그릇.
    const o1 = await a.type('rest_order', 3000);
    const o2 = await a.type('rest_order', 3000);
    assert.ok([o1, o2].every((o) => o.dish === 'rice_ball'));
    const state = await a.next((m) => m.t === 'rest' && m.team === true && m.orders.length >= 1);
    assert.equal(state.orders[0].patience, rest.patience_s[1] * 1000 * 1.25, '둘이면 손님이 더 기다려 준다');
    // a 는 섞기, b 는 담기를 동시에.
    a.send({ t: 'rest_cook', rid: newRid(), order: o1.order, step: 0 });
    b.send({ t: 'rest_cook', rid: newRid(), order: o1.order, step: 1 });
    await a.type('rest_claim');
    await b.type('rest_claim');
    a.send({ t: 'rest_cook', rid: newRid(), order: o1.order, step: 1 });
    assert.equal((await a.type('error')).code, 'step_taken');
    await sleep(1300);
    b.send({ t: 'rest_step', rid: newRid(), order: o1.order, step: 1, taps: [1300] });
    await b.type('rest_stepped');
    a.send({ t: 'rest_step', rid: newRid(), order: o1.order, step: 0, taps: Array.from({ length: 12 }, (_, i) => i * 150) });
    const ra = await a.type('rest_result');
    const rb = await b.type('rest_result');
    assert.equal(ra.team, true);
    assert.ok(ra.stars >= 4);
    assert.equal(ra.share, rb.share, '나눠 갖는다');
    assert.equal(ra.pay, Math.round((2800 * [0, 0, 0.8, 0.95, 1.05, 1.2][ra.stars] * 1.1) / 100) * 100, '팀 보너스 10%');
    void wa;
    void wb;
  });

  it('같이 베기: 둘이 번갈아 찍으면 빨리 쓰러지고 둘 다 하나씩 더', async () => {
    const { a, b } = await pair();
    const tree = data.trees.get('t13');
    a.send({ t: 'equip', slot: 1 });
    b.send({ t: 'equip', slot: 1 });
    await moveTo(a, tree.x + 1, tree.z);
    await moveTo(b, tree.x - 1, tree.z);
    a.send({ t: 'chop', rid: newRid(), tree: 't13' });
    const r1 = await a.type('chop_result');
    assert.equal(r1.coop, false);
    b.send({ t: 'chop', rid: newRid(), tree: 't13' });
    const r2 = await b.type('chop_result');
    assert.equal(r2.coop, true);
    assert.equal(r2.felled, true, '세 번 찍을 나무가 두 번 만에');
    const bonus = await a.type('coop_bonus');
    assert.equal(bonus.kind, 'chop');
  });

  it('여울 몰이: 뜰채로 앞쪽 물고기를 떠 올린다, 둘이 들어가면 넓게 뜬다', async () => {
    const { a, b, wa, room } = await pair();
    await hold(a, wa, 'fishing_net');
    // 이 검사 동안 물고기를 멈춰 둔다 (뜰채 판정만 본다).
    const rules = server.data.dig.net;
    const saved = { flee: rules.flee_speed, panic: rules.panic_speed, wander: rules.wander_speed };
    Object.assign(rules, { flee_speed: 0, panic_speed: 0, wander_speed: 0 });
    const zone = data.spots.get('lake').shallows[0];
    a.send({ t: 'net', rid: newRid() });
    assert.equal((await a.type('error')).code, 'not_in_shallow');
    await moveTo(a, zone.x, zone.z);
    const shoal = room.shoals.get(zone.id);
    // 물고기 하나를 a 앞(−Z) 1.3m 에 둔다: 혼자면 반경 밖, 둘이면 안.
    shoal.fish = [{ id: 99, sp: 'loach', size: 'S', x: zone.x, z: zone.z - 0.9 - 1.3, vx: 0, vz: 0, turnAt: 1e15 }];
    shoal.nextSpawnAt = 1e15;
    a.send({ t: 'net', rid: newRid() });
    const miss = await a.type('net_result');
    assert.deepEqual(miss.fish, []);
    await moveTo(b, zone.x + 1.5, zone.z + 2);
    const pa = room.players.get(wa.id);
    pa.lastNetAt = -Infinity;
    shoal.fish = [{ id: 98, sp: 'loach', size: 'S', x: zone.x, z: zone.z - 0.9 - 1.3, vx: 0, vz: 0, turnAt: 1e15 }];
    a.send({ t: 'net', rid: newRid() });
    const hit = await a.type('net_result');
    assert.equal(hit.coop, true);
    assert.deepEqual(hit.fish, ['loach']);
    Object.assign(rules, { flee_speed: saved.flee, panic_speed: saved.panic, wander_speed: saved.wander });
  });

  it('삽: 숨구멍을 둘이 파면 둘 다 조개, 풀밭은 구덩이 → 메우기 → 흙길', async () => {
    const { a, b, wa, wb, room } = await pair();
    await hold(a, wa, 'shovel');
    await hold(b, wb, 'shovel');
    const at = beachSpot(data.layout.island, () => 0.3);
    room.digSpots.set('sX', { id: 'sX', kind: 'beach', spot: '', x: at.x, z: at.z, hp: 3, hits: [] });
    await moveTo(a, at.x + 1, at.z);
    await moveTo(b, at.x - 1, at.z);
    a.send({ t: 'dig', rid: newRid(), x: at.x, z: at.z, mode: 'dig' });
    assert.equal((await a.type('dig_result')).hp, 2);
    b.send({ t: 'dig', rid: newRid(), x: at.x, z: at.z, mode: 'dig' });
    const ca = await a.next((m) => m.t === 'dig_result' && m.kind === 'clam');
    const cb = await b.next((m) => m.t === 'dig_result' && m.kind === 'clam');
    assert.equal(ca.coop, true);
    assert.ok(['clam_manila', 'surf_clam', 'razor_clam', 'pen_shell'].includes(ca.item));
    assert.ok(cb.item);
    await sleep(450);
    a.send({ t: 'dig', rid: newRid(), x: at.x, z: at.z, mode: 'dig' });
    assert.equal((await a.type('error')).code, 'bad_dig', '모래밭은 구덩이를 못 판다');
    // 풀밭: 구덩이 → 메우기 → 흙길 → 걷기
    const gx = 18;
    const gz = 14;
    await moveTo(a, gx + 1, gz);
    await sleep(450);
    a.send({ t: 'dig', rid: newRid(), x: gx, z: gz, mode: 'fill' });
    assert.equal((await a.type('error')).code, 'bad_dig', '메울 구덩이가 없다');
    await sleep(450);
    a.send({ t: 'dig', rid: newRid(), x: gx, z: gz, mode: 'dig' });
    assert.equal((await a.type('dig_result')).s, 'hole');
    const tile = await b.type('tile');
    assert.deepEqual([tile.x, tile.z, tile.s], [gx, gz, 'hole']);
    await sleep(450);
    a.send({ t: 'dig', rid: newRid(), x: gx, z: gz, mode: 'fill' });
    assert.equal((await a.type('dig_result')).s, '');
    await sleep(450);
    a.send({ t: 'dig', rid: newRid(), x: gx, z: gz, mode: 'path' });
    assert.equal((await a.type('dig_result')).s, 'path');
    assert.deepEqual(room.toSave().world.tiles, [[gx, gz, 'path']]);
  });
});
