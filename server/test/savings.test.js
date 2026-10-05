// v0.12 예적금: 금리 · 이자 · 세금 · 우대 · 중도해지 · 예금자 보호, 그리고 서버에서 가입 → 매주 납입 → 만기.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { rateFor } from '../src/bank.js';
import { bonusRate, earlyFactor, failurePayout, grossInterest, interestTax, productRate, settle } from '../src/savings.js';
import { Client, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const sv = data.savings;

function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: Date.UTC(2026, 9, 5, 10) };
  return c;
}

describe('예적금 규칙', () => {
  it('금융기관 여섯 곳 (시중은행 둘 · 인터넷은행 · 저축은행 둘 · 상호금융), 가상의 이름', () => {
    const types = [...sv.institutions.values()].map((i) => i.type).sort();
    assert.deepEqual(types, ['commercial', 'commercial', 'coop', 'internet', 'savings_bank', 'savings_bank']);
    for (const p of sv.products.values()) assert.ok(sv.institutions.has(p.bank));
  });

  it('빌려서 예금하면 손해: 어떤 상품도 세후 금리가 가장 싼 신용대출 금리보다 낮다', () => {
    for (const base of [data.bank.base_rate_range[0], data.bank.base_rate, data.bank.base_rate_range[1]]) {
      const cheapestLoan = rateFor(data.bank, base, 1, 'credit');
      for (const p of sv.products.values()) {
        for (const w of p.weeks) {
          const best = productRate(p, base, w) + Object.values(p.bonus ?? {}).reduce((a, b) => a + b, 0);
          const net = best * (1 - (p.bank === 'hosu' ? sv.tax.coop_member : sv.tax.normal));
          assert.ok(net < cheapestLoan, `${p.id} ${w}주 세후 ${net.toFixed(4)} < 대출 ${cheapestLoan}`);
        }
      }
    }
  });

  it('예금은 원금 × 금리 × 주/52, 적금은 넣은 주마다 남은 주만큼', () => {
    assert.equal(grossInterest({ kind: 'deposit', principal: 10000000 }, 0.052, 12), 120000);
    // 매주 100만씩 4번 (0~3주) 넣고 4주 만기: 4+3+2+1 = 10 주·백만.
    assert.equal(grossInterest({ kind: 'savings', amount: 1000000, paidAt: [0, 1, 2, 3] }, 0.052, 4), 10000);
  });

  it('세금: 일반 15.4%, 마을금고 조합원은 3천만까지 1.4%', () => {
    assert.equal(interestTax(sv, 100000, { coopMember: false, principal: 10000000 }), 15400);
    assert.equal(interestTax(sv, 100000, { coopMember: true, principal: 10000000 }), 1400);
    // 6천만이면 절반만 세금우대.
    assert.equal(interestTax(sv, 100000, { coopMember: true, principal: 60000000 }), Math.ceil(100000 * 0.5 * 0.014 + 100000 * 0.5 * 0.154));
  });

  it('우대금리는 조건을 채운 것만, 중도해지는 기간 비율로 기본금리의 일부', () => {
    const p = sv.products.get('sol_savings');
    const ok = bonusRate(sv, p, { kind: 'savings', missed: 0 }, { card: true });
    assert.deepEqual(ok.got.sort(), ['auto', 'local_card']);
    const missed = bonusRate(sv, p, { kind: 'savings', missed: 1 }, { card: false });
    assert.equal(missed.rate, 0);
    assert.equal(earlyFactor(sv, 0.1), 0.1);
    assert.equal(earlyFactor(sv, 0.6), 0.5);
    const d = sv.products.get('sol_deposit');
    const account = { kind: 'deposit', bank: 'solbaram', principal: 10000000, rate: 0.03, week: 0, weeks: 12, first: true, incomeWeeks: 12 };
    const early = settle(sv, d, account, 3, {});
    const full = settle(sv, d, account, 12, {});
    assert.equal(early.early, true);
    assert.ok(early.gross < full.gross / 4, '석 주 만에 깨면 이자가 아주 적다');
    assert.deepEqual(full.got.sort(), ['first', 'income']);
    assert.equal(full.net, 10000000 + full.gross - full.tax);
  });

  it('예금자 보호: 한 기관에 1억까지는 원리금 그대로, 넘는 돈은 일부만', () => {
    const small = failurePayout(sv, [{ kind: 'deposit', principal: 50000000, rate: 0.03, week: 0, weeks: 12 }], 6);
    assert.equal(small.lost, 0);
    assert.ok(small.paid > 50000000);
    const big = failurePayout(sv, [{ kind: 'deposit', principal: 150000000, rate: 0.03, week: 0, weeks: 12 }], 0);
    assert.equal(big.total, 150000000);
    assert.equal(big.paid, 100000000 + Math.floor(50000000 * sv.recovery));
    assert.equal(big.lost, 50000000 - Math.floor(50000000 * sv.recovery));
  });
});

describe('예적금 서버', () => {
  let saveDir;
  let server;
  let clock;
  const clients = [];
  let rid = 0;
  const newRid = () => `s${++rid}`;
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-savings-'));
    clock = fakeClock();
    server = createServer({ port: 0, saveDir, clock, random: () => 0.5, weatherForce: 'clear', startSol: 100000000 });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });
  async function enter() {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    const room = [...server.rooms.rooms.values()].find((r) => r.code === w.code);
    const player = [...room.players.values()].find((p) => p.id === w.id);
    return { c, room, player };
  }

  it('예금에 넣으면 지갑에서 빠지고, 만기 전에 깨면 이자가 적다', async () => {
    const { c, player } = await enter();
    c.send({ t: 'bank_quote' });
    const quote = await c.type('bank');
    assert.equal(quote.sv.institutions.length, 6);
    const before = player.profile.sol;
    c.send({ t: 'dep_open', rid: newRid(), product: 'sol_deposit', weeks: 12, amount: 10000000 });
    const opened = await c.type('dep_result');
    assert.equal(opened.sol, before - 10000000);
    assert.equal(player.profile.deposits.length, 1);
    assert.equal(player.profile.deposits[0].first, true, '첫 거래');
    clock.d += 14;
    c.send({ t: 'dep_close', rid: newRid(), id: opened.id });
    const closed = await c.type('dep_result');
    assert.equal(closed.early, true);
    assert.ok(closed.net >= 10000000 && closed.net < 10000000 + 10000);
    assert.equal(player.profile.deposits.length, 0);
  });

  it('적금은 매주 지갑에서 넣고, 만기에 저절로 이자와 함께 돌아온다 (마을톡 은행 알림)', async () => {
    const { c, player } = await enter();
    c.send({ t: 'dep_open', rid: newRid(), product: 'gureum_savings', weeks: 4, amount: 1000000 });
    await c.type('dep_result');
    const acct = player.profile.deposits[0];
    assert.deepEqual(acct.paidAt, [0]);
    for (let w = 1; w <= 4; w++) {
      clock.d += 7;
      await c.type('week', 3000);
    }
    assert.equal(player.profile.deposits.length, 0, '만기 해지');
    const thread = player.profile.chats['sys:bank'];
    assert.ok(thread?.m.some((m) => m.tx.includes('구름 한 주 적금 만기')), '은행 알림');
  });

  it('파킹통장은 언제든 넣고 빼고, 주마다 이자가 붙는다', async () => {
    const { c, player } = await enter();
    c.send({ t: 'park_move', rid: newRid(), amount: 20000000 });
    const put = await c.type('dep_result');
    assert.equal(put.balance, 20000000);
    clock.d += 7;
    await c.type('week', 3000);
    const a = player.profile.deposits.find((d) => d.kind === 'parking');
    assert.ok(a.principal > 20000000, `이자 ${a.principal - 20000000}`);
    c.send({ t: 'park_move', rid: newRid(), amount: -a.principal });
    const out = await c.type('dep_result');
    assert.equal(out.balance, 0);
    assert.equal(player.profile.deposits.some((d) => d.kind === 'parking'), false);
  });

  it('마을금고는 처음에 출자금을 내고 조합원이 된다 · 청년 적금은 나이 조건', async () => {
    const { c, player } = await enter();
    const before = player.profile.sol;
    c.send({ t: 'dep_open', rid: newRid(), product: 'hosu_deposit', weeks: 8, amount: 2000000 });
    const r = await c.type('dep_result');
    assert.equal(r.fee, 10000);
    assert.equal(player.profile.sol, before - 2000000 - 10000);
    assert.equal(player.profile.coopMember, true);
    player.profile.age = 40;
    c.send({ t: 'dep_open', rid: newRid(), product: 'haneul_youth', weeks: 12, amount: 300000 });
    assert.equal((await c.type('error')).code, 'not_eligible');
  });
});
