// v0.20 폰다운 기능: 솔걸음(만보기) 보상 · 재난문자 · 민방위 훈련.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { acceptSteps, drillWindow } from '../src/safety.js';
import { Client, uid } from './helpers.js';

function fakeClock(hour = 12, day = 100) {
  const c = { hour: () => c.h, day: () => c.d, gameMs: () => c.g, scale: 1, h: hour, d: day, g: 0 };
  return c;
}

const BASE = { moveSlackMeters: 200, random: () => 0, reconnectGraceMs: 300, saveIntervalMs: 60000, chopCooldownMs: 0, weatherForce: 'clear', questChance: 0, eventForce: 'none' };
const RULES = { daily_cap: 40000, max_rate: 4, slack: 80, tiers: [[1000, 3000], [3000, 8000], [5000, 15000], [10000, 30000]] };

describe('폰다운 기능 (v0.20)', () => {
  const clients = [];
  after(() => {
    for (const c of clients) c.kill();
  });
  async function withServer(extra, fn) {
    const dir = mkdtempSync(path.join(tmpdir(), 'solbaram-safety-'));
    const s = createServer({ port: 0, saveDir: dir, ...BASE, clock: fakeClock(), ...extra });
    try {
      await fn(s);
    } finally {
      await s.close();
      rmSync(dir, { recursive: true, force: true });
    }
  }
  async function enter(s, code = '') {
    const c = new Client(s.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  }

  it('걸음: 사람이 걸을 수 있는 빠르기만 인정하고, 목표마다 하루 한 번 보상', () => {
    const st = { day: 7, today: 0, got: [], last: 0, at: 0 };
    // 1초 만에 5000 걸음이라고 하면 4 + 80 만 인정.
    assert.equal(acceptSteps(RULES, st, 5000, 1000, 7), 0);
    assert.equal(st.today, 84);
    // 20분(1200초) 걸었다 → 1000 걸음 목표 달성 (3000솔).
    assert.equal(acceptSteps(RULES, st, 6200, 1201000, 7), 3000);
    assert.equal(st.today, 84 + 1200, '늘어난 1200 걸음이 다 인정된다');
    assert.equal(acceptSteps(RULES, st, 6300, 1300000, 7), 0, '같은 목표는 다시 주지 않는다');
    // 더 걸어 3000 · 5000 을 한꺼번에 넘으면 둘 다.
    assert.equal(acceptSteps(RULES, st, 10300, 3000000, 7), 8000 + 15000);
    // 하루 상한.
    acceptSteps(RULES, st, 99999, 99000000, 7);
    assert.equal(st.today, 40000);
    // 날이 바뀌면 0부터, 클라가 다시 0부터 세도(줄어들어도) 늘어난 만큼.
    assert.equal(acceptSteps(RULES, st, 300, 99060000, 8), 0);
    assert.equal(st.today, 300);
    assert.deepEqual(st.got, []);
  });

  it('걸음 보고 → steps_ok (오늘 인정된 걸음 · 솔), 프로필에도 오늘 걸음', () => withServer({}, async (s) => {
    const { c, w } = await enter(s);
    assert.deepEqual(w.prof.steps, { today: 0, got: [] });
    c.send({ t: 'steps', rid: 's1', n: 50 });
    const ok = await c.type('steps_ok');
    assert.equal(ok.today, 50);
    assert.equal(ok.reward, 0);
    c.send({ t: 'steps', rid: 's2', n: -5 });
    assert.equal((await c.type('error')).code, 'bad_message');
  }));

  it('뇌우면 긴급재난문자, 늦게 들어온 사람도 오늘 문자를 받는다', () => withServer({ weatherForce: 'thunder', lightningMinMs: 60000, lightningMaxMs: 60000 }, async (s) => {
    const { c, w } = await enter(s);
    const a = await c.next((m) => m.t === 'alert' && m.id === 'thunder', 3500);
    assert.equal(a.level, 'emergency');
    assert.ok(a.text.includes('낙뢰'));
    const late = await enter(s, w.code);
    const b = await late.c.next((m) => m.t === 'alert' && m.id === 'thunder', 2000);
    assert.equal(b.late, true);
  }));

  it('민방위 훈련: 사이렌(경보 문자 · drill) → 대피소에 들어가면 보상 한 번, 주민은 제자리로', () => withServer({ drillForce: true }, async (s) => {
    const { c } = await enter(s);
    const start = await c.next((m) => m.t === 'alert' && m.id === 'drill_start', 3500);
    assert.equal(start.level, 'emergency');
    const drill = await c.next((m) => m.t === 'drill' && m.on, 3500);
    assert.equal(drill.shelter.name, '솔바람동 행정복지센터 대피소');
    c.send({ t: 'move', x: drill.shelter.x, y: 0.1, z: drill.shelter.z, yaw: 0, vx: 0, vz: 0 });
    const done = await c.type('drill_done', 3500);
    assert.equal(done.reward, s.data.safety.drill.reward);
  }));

  it('훈련 시각: 매달 15일 14시부터 15분', () => {
    const rules = { day: 15, hour: 14, minutes: 15, notice_minutes: 10 };
    const g = Date.UTC(2026, 9, 15, 14, 5);
    const w = drillWindow(rules, g);
    assert.ok(g >= w.start && g < w.end);
    assert.equal(w.end - w.start, 15 * 60000);
    assert.equal(new Date(w.start).getUTCDate(), 15);
    assert.ok(Date.UTC(2026, 9, 15, 13, 55) >= w.notice);
  });
});
