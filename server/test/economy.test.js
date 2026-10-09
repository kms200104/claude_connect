import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { buyCost, clampToLimit, createMarket, marketOpen, roundToTick, sellProceeds, tickSize } from '../src/market.js';
import { listUnits, purchaseCost, unitPrice, weeklyRent } from '../src/realestate.js';
import { chargeWeek, creditLimit, creditScore, dsrOk, gradeOf, rateFor, stepBaseRate, weeklyInterest } from '../src/bank.js';
import { capacity, chooseOrder, cookQuality, menuOf, minCookMs, pickIngredients, ratingOf, starsFor, stepQuality, tierOf, updateRegular } from '../src/restaurant.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: Date.UTC(2026, 9, 5, 10) };
  return c;
}

describe('증권: 호가·수수료·시세', () => {
  it('호가 단위와 수수료·거래세는 한국 주식시장을 따른다', () => {
    assert.equal(tickSize(1500), 1);
    assert.equal(tickSize(72000), 100);
    assert.equal(tickSize(215000), 500);
    assert.equal(roundToTick(72049), 72000);
    assert.equal(roundToTick(215300), 215500);
    const buy = buyCost(data.market, 72000, 10);
    assert.deepEqual(buy, { gross: 720000, fee: 108, tax: 0, total: 720108 });
    const sell = sellProceeds(data.market, 72000, 10);
    assert.deepEqual(sell, { gross: 720000, fee: 108, tax: 1296, total: 718596 });
  });

  it('하루 ±30% 를 넘지 못하고, 장 시간(MARKET_HOURS=krx)엔 평일 9시~15시30분만 열린다', () => {
    assert.equal(clampToLimit(200000, 100000, 0.3), 130000);
    assert.equal(clampToLimit(1000, 100000, 0.3), 70000);
    const mon10 = Date.UTC(2026, 9, 5, 10); // 월요일 10시 (마을 시계)
    const sat10 = Date.UTC(2026, 9, 10, 10);
    assert.equal(marketOpen(data.market, mon10, true), true);
    assert.equal(marketOpen(data.market, sat10, true), false);
    assert.equal(marketOpen(data.market, Date.UTC(2026, 9, 5, 16), true), false);
    assert.equal(marketOpen(data.market, sat10, false), true, '기본은 언제나 열린 모의 시장');
  });

  it('외부 시세 서버의 값을 쓰고, 실패하면 모의 거래소로 대신 움직인다', async () => {
    let fail = false;
    const fetch = async () => (fail ? { ok: false, status: 503 } : { ok: true, json: async () => ({ quotes: { SBE: 75000, HSB: 1 } }) });
    const m = createMarket(data.market, { feedUrl: 'http://feed', fetch, random: () => 0.5, day: () => 1 });
    const first = await m.tick();
    assert.equal(m.state.source, 'feed');
    assert.equal(first.SBE, 75000);
    const hsb = data.market.stocks.find((s) => s.id === 'HSB');
    assert.equal(first.HSB, roundToTick(hsb.price * 0.7), '말도 안 되는 시세는 하루 제한으로 자른다');
    fail = true;
    const second = await m.tick();
    assert.equal(m.state.source, 'sim');
    assert.ok(second.SBE > 0);
    assert.equal(m.wire().stocks.find((s) => s.id === 'SBE').hist.length, 3);
  });
});

describe('아파트 · 은행 계산', () => {
  it('e편한세상 13개 동 × 10층 × 2호, 동마다 라인별 평형(84A~191㎡)이고 높을수록 비싸다', () => {
    const units = listUnits(data.realestate);
    assert.equal(units.length, 260);
    const top = units.find((u) => u.id === '101-1001');
    assert.equal(top.type, '84A');
    assert.equal(units.find((u) => u.id === '101-1002').type, '84B');
    assert.equal(units.find((u) => u.id === '102-501').type, '84A');
    assert.equal(units.find((u) => u.id === '102-502').type, '84C');
    assert.equal(units.find((u) => u.id === '107-302').type, '191');
    const low = unitPrice(data.realestate, units.find((u) => u.id === '101-101'), 1);
    const mid = unitPrice(data.realestate, units.find((u) => u.id === '101-701'), 1);
    assert.ok(low < mid);
    assert.equal(mid, 485000000);
    const cost = purchaseCost(data.realestate, mid);
    assert.equal(cost.total, mid + Math.round(mid * 0.011) + Math.round(mid * 0.004));
    assert.equal(weeklyRent(data.realestate, mid), Math.round((mid * 0.035) / 52));
  });

  it('신용점수 → 등급 → 금리. 연체하면 점수가 깎이고 금리가 오른다', () => {
    const b = data.bank;
    const base = { credit: { paid: 0, missed: 0, weeks: 0 }, income: { amount: 0, history: [] }, debt: 0, assets: 0 };
    const start = creditScore(b, base);
    assert.equal(start, b.credit.start_score);
    const late = creditScore(b, { ...base, credit: { paid: 0, missed: 3, weeks: 3 } });
    const good = creditScore(b, { ...base, credit: { paid: 20, missed: 0, weeks: 20 }, income: { amount: 0, history: [2000000, 2000000] } });
    assert.ok(late < start && good > start);
    assert.ok(rateFor(b, b.base_rate, gradeOf(b, late), 'credit') > rateFor(b, b.base_rate, gradeOf(b, good), 'credit'));
    assert.ok(rateFor(b, b.base_rate, 5, 'mortgage') < rateFor(b, b.base_rate, 5, 'credit'), '담보대출이 더 싸다');
    const heavy = creditScore(b, { ...base, debt: 300000000, assets: 310000000 });
    assert.ok(heavy < start, '빚이 자산의 절반을 넘으면 깎인다');
  });

  it('한도·DSR: 소득이 없으면 최소 신용대출만, 소득이 있으면 연 이자가 소득의 40% 이하', () => {
    const b = data.bank;
    assert.equal(creditLimit(b, 5, { amount: 0, history: [] }, 0), 3000000);
    assert.equal(dsrOk(b, { amount: 0, history: [] }, [], { kind: 'credit', principal: 3000000, rate: 0.05 }), true);
    assert.equal(dsrOk(b, { amount: 0, history: [] }, [], { kind: 'mortgage', principal: 100000000, rate: 0.04 }), false);
    const income = { amount: 0, history: [1000000, 1000000, 1000000, 1000000] }; // 연 5,200만
    assert.equal(dsrOk(b, income, [], { kind: 'mortgage', principal: 200000000, rate: 0.04 }), true);
    assert.equal(dsrOk(b, income, [], { kind: 'mortgage', principal: 500000000, rate: 0.04 }), false);
  });

  it('한 주 이자: 솔이 모자라면 남은 이자는 원금에 붙고 연체로 남는다', () => {
    const b = data.bank;
    const profile = { sol: 1000, loans: [{ id: 'L1', kind: 'credit', principal: 10000000, rate: 0, unit: '' }], credit: { paid: 0, missed: 0, weeks: 0 } };
    const r = chargeWeek(b, profile, b.base_rate, 5);
    const interest = weeklyInterest(10000000, rateFor(b, b.base_rate, 5, 'credit'));
    assert.equal(r.paid, 1000);
    assert.equal(r.capitalized, interest - 1000);
    assert.equal(profile.loans[0].principal, 10000000 + interest - 1000);
    assert.deepEqual(profile.credit, { paid: 0, missed: 1, weeks: 1 });
    let rate = b.base_rate;
    for (let i = 0; i < 500; i++) rate = stepBaseRate(b, rate, Math.random);
    assert.ok(rate >= b.base_rate_range[0] && rate <= b.base_rate_range[1]);
  });
});

describe('식당 계산', () => {
  const recipe = (id) => data.recipeById.get(id);

  it('재료가 있는 요리만 고르고, 물고기는 싼 것부터 쓴다', () => {
    const avail = { crucian: 1, golden_carp: 1, rice: 1, laver: 1 };
    assert.deepEqual(pickIngredients(recipe('grilled_fish'), avail, data), { crucian: 1 });
    assert.equal(pickIngredients(recipe('egg_rice'), avail, data), null);
    const menu = menuOf(data.recipes, 1);
    for (let i = 0; i < 20; i++) {
      const pick = chooseOrder({ menu, avail, data, taste: data.customers.get('haerang'), regularDish: null, random: Math.random });
      assert.ok(['grilled_fish', 'rice_ball'].includes(pick.recipe.id));
    }
    assert.equal(capacity(menu, avail, data), 2, '붕어구이 1 + 주먹밥 1 (금붕어는 귀해서 1단계 요리에 안 쓴다)');
    assert.equal(chooseOrder({ menu, avail: { rice: 1 }, data, taste: data.customers.get('haerang'), regularDish: null, random: Math.random }), null);
  });

  it('단골은 그 요리만, 재료가 없으면 아무것도 시키지 않는다', () => {
    const menu = menuOf(data.recipes, 1);
    const avail = { crucian: 2, rice: 1, laver: 1 };
    const pick = chooseOrder({ menu, avail, data, taste: data.customers.get('morak'), regularDish: 'rice_ball', random: () => 0.99 });
    assert.equal(pick.recipe.id, 'rice_ball');
    assert.equal(pick.regular, true);
    assert.equal(chooseOrder({ menu, avail: { crucian: 2 }, data, taste: data.customers.get('morak'), regularDish: 'rice_ball', random: () => 0 }), null);
  });

  it('별점이 오르면 높은 단계 메뉴가 열린다', () => {
    const rules = data.restaurant;
    assert.equal(ratingOf(rules, []), 2);
    assert.equal(tierOf(rules, 2), 1);
    assert.equal(tierOf(rules, 3.4), 3);
    assert.equal(tierOf(rules, 4.7), 5);
    assert.ok(menuOf(data.recipes, 1).every((r) => r.tier === 1));
    const t1 = Math.max(...menuOf(data.recipes, 1).map((r) => r.price));
    const t5 = Math.max(...menuOf(data.recipes, 5).map((r) => r.price));
    assert.ok(t5 > t1 * 10, '높은 단계일수록 비싸다');
    assert.ok(recipe('sturgeon_steak').steps.length > recipe('grilled_fish').steps.length, '높은 단계일수록 까다롭다');
  });

  it('박자·타이밍·연타 판정', () => {
    const steps = data.cookSteps;
    assert.equal(stepQuality(steps.chop, [480, 960, 1440, 1920]), 1);
    assert.ok(stepQuality(steps.chop, [100, 200]) < 0.4);
    assert.ok(stepQuality(steps.boil, [3000]) === 1);
    assert.ok(stepQuality(steps.boil, [4500]) < 0.3);
    // 굽기 (v0.11): 한 면 2초씩 — 2초에 뒤집고 4초에 꺼내면 완벽, 한쪽을 태우면 깎인다, 안 뒤집으면 반만.
    assert.equal(stepQuality(steps.grill, [2000, 4000]), 1);
    assert.ok(stepQuality(steps.grill, [3200, 5200]) < 0.75, '첫 면을 태움');
    assert.ok(stepQuality(steps.grill, [2000]) <= 0.5, '한 면만 구움');
    // 찌기: 재료 3개 → 물 1.6초 붓기(선에 딱) → 2.6초 찌고 뚜껑 열기.
    assert.equal(stepQuality(steps.steam, [100, 300, 500, 800, 2400, 5000]), 1);
    assert.ok(stepQuality(steps.steam, [100, 300, 500, 800, 3600, 6200]) < 0.8, '물을 너무 많이 부음');
    assert.ok(stepQuality(steps.steam, [100, 300]) < 0.25, '재료만 넣다 맒');
    assert.equal(stepQuality(steps.mix, Array.from({ length: 12 }, (_, i) => i * 150)), 1);
    assert.ok(stepQuality(steps.mix, Array.from({ length: 30 }, (_, i) => i * 10)) <= 0.6, '50ms 보다 촘촘한 자동 연타는 세지 않는다');
    const r = recipe('grilled_fish');
    assert.equal(cookQuality(r, steps, [[2000, 4000], [1300]]), 1);
    assert.ok(minCookMs(r, steps) > 2000);
  });

  it('요리 장면 (v20): 동작마다 scene, 새 동작도 기존 판정 종류로 매긴다', () => {
    const steps = data.cookSteps;
    const scenes = ['chop', 'season', 'skewer', 'wok', 'grill', 'flip', 'boil', 'simmer', 'fry', 'plate', 'mix', 'knead', 'steam'];
    for (const [id, s] of Object.entries(steps)) {
      assert.ok(scenes.includes(s.scene), `${id}: scene ${s.scene}`);
      assert.ok(['beats', 'timing', 'grill', 'steam', 'mash'].includes(s.kind), `${id}: kind ${s.kind}`);
    }
    assert.equal(stepQuality(steps.season, [420, 840, 1260, 1680]), 1);
    assert.equal(stepQuality(steps.stir_fry, [440, 880, 1320, 1760, 2200]), 1);
    assert.equal(stepQuality(steps.deep_fry, [2600]), 1);
    assert.ok(stepQuality(steps.deep_fry, [4000]) < 0.4, '너무 오래 튀김');
    assert.equal(stepQuality(steps.knead, Array.from({ length: 12 }, (_, i) => i * 150)), 1);
    // 고기 요리: 상점 재료로 만든다.
    const avail = { pork_belly: 1, garlic: 1 };
    assert.deepEqual(pickIngredients(recipe('samgyeopsal'), avail, data), { pork_belly: 1, garlic: 1 });
    for (const id of ['samgyeopsal', 'chicken_skewer', 'potato_jeon', 'bulgogi', 'jeyuk', 'dumplings', 'fried_chicken', 'beef_steak', 'galbijjim']) {
      const r = recipe(id);
      const cost = r.ingredients.reduce((a, i) => a + (data.items.get(i.item)?.buy ?? 0) * i.n, 0);
      assert.ok(r.price > cost * 1.5, `${id}: 값 ${r.price} > 재료값 ${cost} × 1.5`);
    }
  });

  it('F 손님은 늦어도 너그럽고, T 손님은 솜씨를 깐깐하게 본다', () => {
    const rules = data.restaurant;
    const late = { quality: 1, taste: 0.7, timeLeft: 0 };
    assert.ok(starsFor(rules, { ...late, mbti: 'ENFP' }) >= starsFor(rules, { ...late, mbti: 'ESTJ' }));
    const sloppy = { quality: 0.5, taste: 0.7, timeLeft: 0.8 };
    assert.ok(starsFor(rules, { ...sloppy, mbti: 'INFP' }) > starsFor(rules, { ...sloppy, mbti: 'INTJ' }) || starsFor(rules, { ...sloppy, mbti: 'INFP' }) === starsFor(rules, { ...sloppy, mbti: 'INTJ' }));
    assert.equal(starsFor(rules, { quality: 1, taste: 1, timeLeft: 1, mbti: 'ISTJ' }), 5);
  });

  it('같은 요리에 4점 이상 세 번 → 단골, 3점 아래면 풀린다', () => {
    const rules = data.restaurant;
    let rec = null;
    let became = false;
    for (let i = 0; i < 3; i++) ({ rec, became } = updateRegular(rules, rec, 'rice_ball', 5));
    assert.equal(became, true);
    assert.equal(rec.regular, true);
    ({ rec } = updateRegular(rules, rec, 'rice_ball', 4));
    assert.equal(rec.regular, true);
    const r = updateRegular(rules, rec, 'rice_ball', 2);
    assert.equal(r.lost, true);
    assert.equal(r.rec.regular, false);
  });
});

describe('경제 (서버 연동)', () => {
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
  const newRid = () => `e${++rid}`;

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-economy-'));
    clock = fakeClock();
    server = createServer({
      port: 0,
      saveDir,
      clock,
      moveSlackMeters: 400,
      random: () => 0.5,
      weatherForce: 'clear',
      startSol: 1000000000,
      startItems: 'rice:2,laver:2',
      marketTickMs: 120,
      restSpawnScale: 0.02,
    });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('주식을 사고팔면 수수료·거래세가 빠지고, 1분마다 시세가 방송된다', async () => {
    const a = await open();
    const w = await enter(a);
    const sol0 = w.prof.sol;
    const tick = await a.type('market_tick', 2000);
    assert.ok(tick.q.SBE > 0);
    const price = server.market.price('SBE');
    let r = newRid();
    a.send({ t: 'stock_order', rid: r, id: 'SBE', side: 'buy', qty: 10 });
    const buy = await a.type('stock_result');
    assert.equal(buy.rid, r);
    assert.equal(buy.amount, buyCost(server.data.market, buy.price, 10).total);
    assert.equal(buy.sol, sol0 - buy.amount);
    assert.deepEqual(buy.holding, { q: 10, cost: buy.amount });
    assert.ok(Math.abs(buy.price - price) / price < 0.05);
    a.send({ t: 'stock_order', rid: newRid(), id: 'SBE', side: 'sell', qty: 11 });
    assert.equal((await a.type('error')).code, 'not_enough_shares');
    a.send({ t: 'stock_order', rid: newRid(), id: 'NOPE', side: 'buy', qty: 1 });
    assert.equal((await a.type('error')).code, 'bad_order');
    a.send({ t: 'stock_order', rid: newRid(), id: 'SBE', side: 'sell', qty: 4 });
    const sell = await a.type('stock_result');
    assert.equal(sell.amount, sellProceeds(server.data.market, sell.price, 4).total);
    assert.equal(sell.holding.q, 6);
    const prof = await a.next((m) => m.t === 'profile' && m.stocks.SBE?.q === 6);
    assert.equal(prof.trades.length, 2);
  });

  it('아파트를 대출 끼고 사고, 한 주가 지나면 월세가 들어오고 이자가 나간다', async () => {
    const a = await open();
    const w = await enter(a);
    const b = await open();
    await enter(b, { code: w.code });
    const unit = server.data.units.find((u) => u.id === '102-501');
    const price = unitPrice(server.data.realestate, unit, w.homes.index);
    // 소득이 없으면 담보대출이 안 된다 (DSR).
    a.send({ t: 'apt_buy', rid: newRid(), unit: '102-501', loan: 100000000 });
    assert.equal((await a.type('error')).code, 'loan_limit');
    a.send({ t: 'apt_buy', rid: newRid(), unit: '102-501', loan: Math.round(price * 0.9) });
    assert.equal((await a.type('error')).code, 'loan_limit', 'LTV 70% 를 넘는 대출');
    // 소득을 만든다 (번 돈 기록).
    const room = [...server.rooms.rooms.values()].find((r) => r.code === w.code);
    const pa = [...room.players.values()].find((p) => p.id === w.id);
    pa.profile.income.history = [3000000, 3000000, 3000000, 3000000];
    const loan = 100000000;
    a.send({ t: 'apt_buy', rid: newRid(), unit: '102-501', loan });
    const res = await a.type('apt_result');
    assert.equal(res.kind, 'buy');
    assert.equal(res.loan, loan);
    const homes = await b.type('homes');
    assert.equal(homes.owners['102-501'], w.id, '다른 사람에게도 집 주인이 보인다');
    b.send({ t: 'apt_buy', rid: newRid(), unit: '102-501', loan: 0 });
    assert.equal((await b.type('error')).code, 'unit_taken');
    b.send({ t: 'apt_sell', rid: newRid(), unit: '102-501' });
    assert.equal((await b.type('error')).code, 'not_your_unit');

    const before = pa.profile.sol;
    clock.d += 7;
    const week = await a.type('week', 2500);
    const mortgage = pa.profile.loans.find((l) => l.kind === 'mortgage');
    assert.ok(week.rent > 0);
    assert.equal(week.interest, weeklyInterest(loan, mortgage.rate));
    assert.equal(pa.profile.sol, before + week.rent - week.interest);
    assert.equal(pa.profile.credit.paid, 1);

    a.send({ t: 'apt_sell', rid: newRid(), unit: '102-501' });
    const sold = await a.type('apt_result');
    assert.equal(sold.kind, 'sell');
    assert.equal(sold.repaid, loan, '판 돈으로 담보대출부터 갚는다');
    assert.equal(pa.profile.loans.length, 0);
  });

  it('신용대출: 한도 안에서 빌리고 갚는다', async () => {
    const a = await open();
    await enter(a);
    a.send({ t: 'bank_quote' });
    const q = await a.type('bank');
    assert.equal(q.grade, 5);
    assert.equal(q.credit_limit, 3000000);
    a.send({ t: 'loan_take', rid: newRid(), amount: 5000000 });
    assert.equal((await a.type('error')).code, 'loan_limit');
    a.send({ t: 'loan_take', rid: newRid(), amount: 50 });
    assert.equal((await a.type('error')).code, 'bad_loan');
    a.send({ t: 'loan_take', rid: newRid(), amount: 2000000 });
    const took = await a.type('loan_result');
    assert.equal(took.loan.principal, 2000000);
    assert.equal(took.loan.rate, q.rate_credit);
    a.send({ t: 'loan_repay', rid: newRid(), id: took.loan.id, amount: 500000 });
    const paid = await a.type('loan_result');
    assert.deepEqual({ paid: paid.paid, left: paid.left }, { paid: 500000, left: 1500000 });
    a.send({ t: 'loan_repay', rid: newRid(), id: took.loan.id, amount: 9000000 });
    const done = await a.type('loan_result');
    assert.equal(done.left, 0);
    const bank = await a.next((m) => m.t === 'bank' && m.loans.length === 0);
    assert.equal(bank.loans.length, 0);
  });

  it('식당: 가방 재료로 만들 수 있는 요리만, 재료 수만큼만 주문이 들어온다', async () => {
    const a = await open();
    const w = await enter(a);
    const rest = server.data.restaurant;
    a.send({ t: 'rest_open', rid: newRid() });
    assert.equal((await a.type('error')).code, 'not_at_restaurant');
    await moveTo(a, rest.counter.x, rest.counter.z);
    a.send({ t: 'rest_open', rid: newRid() });
    await a.type('rest_opened');
    // 가방: 쌀 2 · 김 2 → 주먹밥 2그릇만 가능.
    const orders = [await a.type('rest_order', 3000), await a.type('rest_order', 3000)];
    assert.ok(orders.every((o) => o.dish === 'rice_ball'));
    await assert.rejects(a.type('rest_order', 800), '재료가 떨어지면 더는 주문이 없다');
    const o = orders[0];
    // 요리 동작마다 맡고(rest_cook) 다 하면 보낸다(rest_step). 주먹밥 = 섞기 → 담기.
    a.send({ t: 'rest_cook', rid: newRid(), order: o.order, step: 0 });
    assert.equal((await a.type('rest_claim')).step, 0);
    a.send({ t: 'rest_step', rid: newRid(), order: o.order, step: 0, taps: [0] });
    assert.equal((await a.type('error')).code, 'cook_too_fast');
    await sleep(1300);
    a.send({ t: 'rest_step', rid: newRid(), order: o.order, step: 0, taps: Array.from({ length: 12 }, (_, i) => i * 150) });
    await a.type('rest_stepped');
    a.send({ t: 'rest_cook', rid: newRid(), order: o.order, step: 1 });
    await a.type('rest_claim');
    await sleep(900);
    const r = newRid();
    a.send({ t: 'rest_step', rid: r, order: o.order, step: 1, taps: [1300] });
    const res = await a.type('rest_result');
    assert.equal(res.rid, r);
    assert.ok(res.stars >= 4, `별점 ${res.stars}`);
    assert.equal(res.quality, 1);
    assert.ok(res.pay > 0);
    const inv = await a.type('inventory');
    const count = (id) => inv.slots.filter((s) => s?.id === id).reduce((n, s) => n + s.n, 0);
    assert.deepEqual([count('rice'), count('laver')], [1, 1]);
    a.send({ t: 'rest_close', rid: newRid() });
    const closed = await a.type('rest_closed');
    assert.equal(closed.reason, 'closed');
    assert.ok(w.rest.rating === 2);
  });

  it('들판에 채집물(나물·버섯·산딸기)이 돋아나고 주울 수 있다', async () => {
    const a = await open();
    const w = await enter(a);
    let drop = w.drops.find((d) => d.kind === 'forage');
    if (!drop) drop = (await a.next((m) => m.t === 'drop' && m.d.kind === 'forage', 2500)).d;
    assert.ok(server.data.restaurant.forage.items.some((f) => f.id === drop.item));
    await moveTo(a, drop.x, drop.z);
    a.send({ t: 'collect', rid: newRid(), id: drop.id });
    const got = await a.type('collect_result');
    assert.equal(got.item, drop.item);
  });
});
