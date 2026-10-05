// v0.12 이벤트: 종류(kind)로 일반화 · 광장 손님 · 계절 축제 · 한 주짜리 경제 소식(기준금리 · 집값 · 상점 값 · 저축은행 영업정지).
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { activeEvents, buyMultiplier, eventKind, findKind, planDay, sellMultiplier } from '../src/events.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const econ = (id) => ({ id, def: data.events.economy.find((e) => e.id === id) });

function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: Date.UTC(2026, 9, 5, 3) };
  return c;
}

describe('이벤트 종류 · 경제 소식 규칙', () => {
  it('예전 이벤트도 종류를 안다, 광장 손님은 여럿', () => {
    assert.equal(eventKind({ id: 'merchant' }), 'visitor');
    const visitors = data.events.daily.filter((d) => eventKind(d) === 'visitor');
    assert.ok(visitors.length >= 3);
    for (const v of visitors) assert.ok(v.npc?.id && v.spot && v.stock.length > 0, v.id);
  });

  it('중고 가구상이 오면 그 손님이 찾는 물건만 사고, 경제 소식은 한 주 내내 칩에 보인다', () => {
    const plan = planDay({ seed: 1, day: 1, events: data.events, data, force: 'antique_dealer', forcedWanted: 'fossil' });
    const active = activeEvents(plan, 12, 'clear', econ('fish_boom'));
    assert.equal(findKind(active, 'visitor').id, 'antique_dealer');
    assert.equal(sellMultiplier(active, 'fossil', 'merchant'), 2.5);
    assert.equal(sellMultiplier(active, 'wood', 'merchant'), 0);
    assert.deepEqual(active.map((e) => e.id).sort(), ['antique_dealer', 'fish_boom']);
  });

  it('수산물 값 급등이면 상점이 물고기를 1.5배, 장바구니 물가가 오르면 재료가 1.3배', () => {
    const boom = activeEvents({ daily: null, meteor: null }, 12, 'clear', econ('fish_boom'));
    assert.equal(sellMultiplier(boom, 'crucian', 'shop', data.kindOf), 1.5);
    assert.equal(sellMultiplier(boom, 'wood', 'shop', data.kindOf), 1);
    const inflation = activeEvents({ daily: null, meteor: null }, 12, 'clear', econ('grocery_inflation'));
    assert.equal(buyMultiplier(inflation, 'egg', data.kindOf), 1.3);
    assert.equal(buyMultiplier(inflation, 'wood_chair', data.kindOf), 1);
  });
});

describe('경제 소식 서버', () => {
  const made = [];
  after(async () => {
    for (const m of made) {
      for (const c of m.clients) c.kill();
      await m.server.close();
      rmSync(m.dir, { recursive: true, force: true });
    }
  });
  async function world(econForce) {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-econ-'));
    const clock = fakeClock();
    const server = createServer({ port: 0, saveDir: dir, clock, random: () => 0.5, weatherForce: 'clear', econForce, startSol: 300000000 });
    const m = { dir, server, clock, clients: [] };
    made.push(m);
    const c = new Client(server.port);
    m.clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    m.c = c;
    m.room = [...server.rooms.rooms.values()].find((r) => r.code === w.code);
    m.player = [...m.room.players.values()].find((p) => p.id === w.id);
    return m;
  }

  it('기준금리 인상: 주간 정산 때 0.5%p 오르고, 이번 주 이벤트 목록과 마을 공지에 뜬다', async () => {
    const m = await world('rate_hike');
    m.clock.d += 7;
    const first = await m.c.type('week', 3000);
    const base0 = first.base;
    m.clock.d += 7;
    const w = await m.c.type('week', 3000);
    assert.equal(w.econ.id, 'rate_hike');
    assert.ok(Math.abs(w.base - Math.min(data.bank.base_rate_range[1], base0 + 0.005)) < 0.0026, `${base0} → ${w.base}`);
    const town = m.player.profile.chats['sys:town'];
    assert.ok(town.m.some((x) => x.tx.includes('기준금리 인상')));
    m.c.send({ t: 'ping', ct: 1 });
    assert.equal(m.room.econ.id, 'rate_hike');
  });

  it('저축은행 영업정지: 1억까지는 돌려받고 넘는 돈은 일부만, 그 은행은 몇 주 동안 가입이 안 된다', async () => {
    const m = await world('bank_failure');
    m.clock.d += 7;
    await m.c.type('week', 3000);
    m.room.closedBanks = {};
    m.c.send({ t: 'dep_open', rid: 'd1', product: 'byeolbit_special', weeks: 12, amount: 20000000 });
    await m.c.type('dep_result');
    m.c.send({ t: 'dep_open', rid: 'd2', product: 'deundeun_deposit', weeks: 24, amount: 150000000 });
    await m.c.type('dep_result');
    const before = m.player.profile.sol;
    m.clock.d += 7;
    const w = await m.c.type('week', 3000);
    assert.equal(w.econ.id, 'bank_failure');
    const bank = w.econ.bank;
    assert.ok(['byeolbit', 'deundeun'].includes(bank));
    assert.ok(w.failed && w.failed.paid > 0, '돌려받은 돈');
    assert.equal(m.player.profile.deposits.some((d) => d.bank === bank), false);
    if (bank === 'deundeun') assert.ok(w.failed.lost > 0, '1억 넘은 돈은 일부 손실');
    assert.ok(m.player.profile.sol >= before + w.failed.paid - 1000000);
    const product = bank === 'byeolbit' ? 'byeolbit_special' : 'deundeun_deposit';
    m.c.send({ t: 'dep_open', rid: 'd3', product, weeks: 12, amount: 1000000 });
    assert.equal((await m.c.type('error')).code, 'bank_closed');
    assert.ok(m.player.profile.chats['sys:bank'].m.some((x) => x.tx.includes('영업정지')));
  });
});
