// v0.12 임대 방식: 월세 ↔ 전세. 전세 보증금은 그때 받고 빚으로 세며, 만기에 돌려주고(모자라면 전세금 반환 대출) 다시 월세.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, uid } from './helpers.js';

function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: Date.UTC(2026, 9, 5, 10) };
  return c;
}

describe('전세', () => {
  let saveDir;
  let server;
  let clock;
  const clients = [];
  let rid = 0;
  const newRid = () => `e${++rid}`;
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-jeonse-'));
    clock = fakeClock();
    server = createServer({ port: 0, saveDir, clock, random: () => 0.5, weatherForce: 'clear', startSol: 2000000000 });
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

  it('전세로 놓으면 보증금을 바로 받고 월세가 멈춘다, 만기에 돌려주고 다시 월세', async () => {
    const { c, room, player } = await enter();
    c.send({ t: 'apt_buy', rid: newRid(), unit: '101-501' });
    const bought = await c.type('apt_result');
    const before = player.profile.sol;
    c.send({ t: 'apt_lease', rid: newRid(), unit: '101-501', kind: 'jeonse' });
    const r = await c.type('apt_result');
    assert.equal(r.lease, 'jeonse');
    assert.equal(r.deposit, Math.round((bought.price * 0.6) / 10000) * 10000);
    assert.equal(player.profile.sol, before + r.deposit);
    c.send({ t: 'apt_lease', rid: newRid(), unit: '101-501', kind: 'jeonse' });
    assert.equal((await c.type('error')).code, 'bad_lease');
    clock.d += 7;
    const w1 = await c.type('week', 3000);
    assert.equal(w1.rent, 0, '전세 중에는 월세가 없다');
    // 만기 직전까지 건너뛰고, 지갑을 비워 둬서 반환 대출이 생기게 한다.
    room.homes['101-501'].lease.until = w1.week + 1;
    player.profile.sol = 1000;
    clock.d += 7;
    const w2 = await c.type('week', 3000);
    assert.equal(w2.jeonse.length, 1);
    assert.equal(w2.jeonse[0].loan, r.deposit - 1000);
    assert.equal(room.homes['101-501'].lease, undefined);
    assert.ok(player.profile.loans.some((l) => l.product === 'jeonse_return' && l.principal === r.deposit - 1000));
    assert.ok(player.profile.chats['sys:bank'].m.some((m) => m.tx.includes('전세 계약이 끝나')));
  });

  it('전세 중에 팔면 보증금을 빼고 받는다 · 월세로 되돌리면 보증금을 지금 돌려준다', async () => {
    const { c, room, player } = await enter();
    c.send({ t: 'apt_buy', rid: newRid(), unit: '102-301' });
    await c.type('apt_result');
    c.send({ t: 'apt_lease', rid: newRid(), unit: '102-301', kind: 'jeonse' });
    const r = await c.type('apt_result');
    const s0 = player.profile.sol;
    c.send({ t: 'apt_lease', rid: newRid(), unit: '102-301', kind: 'rent' });
    await c.type('apt_result');
    assert.equal(player.profile.sol, s0 - r.deposit);
    c.send({ t: 'apt_lease', rid: newRid(), unit: '102-301', kind: 'jeonse' });
    const r2 = await c.type('apt_result');
    const s1 = player.profile.sol;
    c.send({ t: 'apt_sell', rid: newRid(), unit: '102-301' });
    const sold = await c.type('apt_result');
    assert.equal(sold.deposit, r2.deposit);
    assert.equal(player.profile.sol, s1 + (sold.price - sold.fee) - r2.deposit);
    assert.equal(room.homes['102-301'], undefined);
  });
});
