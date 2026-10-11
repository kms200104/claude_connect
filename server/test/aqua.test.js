import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { distanceAt, duration, pointAt, timeAt } from '../src/aqua.js';
import { isLand, waterAt } from '../src/water.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const rules = data.aqua;

describe('v21 물놀이 체험 규칙', () => {
  it('바나나 보트 · 유람선: 노선은 모두 호수 물 위, 닫힌 고리, 선착장 곁에서 출발한다', () => {
    assert.deepEqual([...rules.rides.keys()], ['banana', 'cruise']);
    for (const ride of rules.rides.values()) {
      for (const [x, z] of ride.path) assert.notEqual(waterAt(data, x, z), '', `${ride.id} (${x}, ${z}) 는 물`);
      const a = ride.path[0];
      const b = ride.path[ride.path.length - 1];
      assert.ok(Math.hypot(a[0] - b[0], a[1] - b[1]) < 0.01, `${ride.id} 닫힌 고리`);
      assert.ok(Math.hypot(a[0] - rules.dock.x, a[1] - rules.dock.z) < 12, `${ride.id} 선착장 곁 대기 자리`);
      assert.ok(duration(ride) >= 30 && duration(ride) <= 120, `${ride.id} ${duration(ride)}초`);
    }
    assert.ok(isLand(data, ...rules.dock.land), '내리는 자리는 땅');
    assert.ok(rules.rides.get('banana').turns.length >= 3, '바나나 보트 급회전');
    assert.ok(rules.rides.get('cruise').stops.length >= 5, '유람선 안내 방송');
  });

  it('처음 · 끝은 천천히, 가운데는 일정한 빠르기 · 거리 ↔ 시각이 서로 맞다', () => {
    const ride = rules.rides.get('banana');
    const total = duration(ride);
    assert.equal(distanceAt(ride, 0), 0);
    assert.equal(distanceAt(ride, total), ride.length);
    assert.ok(distanceAt(ride, 1) < ride.speed * 0.5, '출발은 천천히');
    for (const s of [0, 3, 10, 50, 120, ride.length - 5, ride.length]) assert.ok(Math.abs(distanceAt(ride, timeAt(ride, s)) - s) < 1e-6, `s ${s}`);
    let last = -1;
    for (let tau = 0; tau <= total; tau += 0.25) {
      const s = distanceAt(ride, tau);
      assert.ok(s >= last, '뒤로 가지 않는다');
      last = s;
    }
    const p = pointAt(ride, ride.length + 4);
    const q = pointAt(ride, 4);
    assert.ok(Math.hypot(p.x - q.x, p.z - q.z) < 1e-6, '한 바퀴 넘으면 처음부터');
  });
});

describe('v21 물놀이 타기 · 같이 타기 · 꽉 잡기 · 내리기', () => {
  let saveDir;
  let server;
  const clients = [];
  let n = 0;
  const ask = async (c, msg) => {
    const r = `aqua-${++n}`;
    c.send({ ...msg, rid: r });
    return c.next((m) => m.rid === r, 3000);
  };
  const join = async (code = '') => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  };
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-aqua-'));
    server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', startSol: 100000, moveSlackMeters: 1000, aquaBoardMs: 600, aquaSpeedScale: 20 });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('선착장 곁에서만 · 요금 · 둘이 같은 배 · 타는 동안 자리는 서버가 · 급회전 판정 · 끝나면 선착장 땅에', async () => {
    const { c: a, w } = await join();
    const me = w.players.find((p) => p.id === w.id);
    assert.deepEqual(w.aqua, [], '처음엔 놀이배가 쉰다');
    assert.equal((await ask(a, { t: 'aqua_join', ride: 'banana' })).code, 'not_near_dock', '선착장에서 멀면 못 탄다');
    a.send({ t: 'move', x: rules.dock.land[0], y: me.y, z: rules.dock.land[1], yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
    assert.equal((await ask(a, { t: 'aqua_join', ride: 'jetpack' })).code, 'bad_message');
    const fee = rules.rides.get('banana').fee;
    const ok = await ask(a, { t: 'aqua_join', ride: 'banana' });
    assert.equal(ok.kind, 'join');
    assert.equal(ok.cost, fee);
    assert.equal(ok.sol, 100000 - fee);
    const trips = await a.next((m) => m.t === 'aqua_trips' && m.list.length === 1, 1000);
    assert.equal(trips.list[0].ride, 'banana');
    // 친구가 같은 배에 탄다 (다른 자리).
    const { c: b, w: wb } = await join(w.code);
    const meb = wb.players.find((p) => p.id === wb.id);
    b.send({ t: 'move', x: rules.dock.land[0], y: meb.y, z: rules.dock.land[1], yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
    const okb = await ask(b, { t: 'aqua_join', ride: 'banana' });
    assert.equal(okb.trip, ok.trip, '손님 받는 중이면 같은 배');
    assert.notEqual(okb.seat, ok.seat);
    // 타는 동안 할 수 없는 일 · 다른 놀이배.
    assert.equal((await ask(a, { t: 'aqua_join', ride: 'cruise' })).code, 'aqua_busy');
    assert.equal((await ask(a, { t: 'fish_cast', spot: 'seongseong' })).code, 'aqua_busy');
    // 출발 전에는 내릴 수 있다 (요금 돌려받기). 떠난 배에는 못 탄다.
    const left = await ask(b, { t: 'aqua_leave' });
    assert.equal(left.kind, 'leave');
    assert.equal(left.sol, 100000);
    await sleep(700);
    assert.equal((await ask(b, { t: 'aqua_join', ride: 'banana' })).code, 'aqua_busy', '돌고 있는 배에는 못 탄다');
    // 출발: 이동 요청과 상관없이 노선 위에 있다.
    a.send({ t: 'move', x: 0, y: 0, z: 60, yaw: 1, vx: 0, vz: 0 });
    const snap = await a.next((m) => m.t === 'snap' && m.p.some((p) => p.id === w.id && waterAt(data, p.x, p.z) !== ''), 1500);
    assert.ok(snap, '자리는 물 위 노선');
    assert.equal((await ask(a, { t: 'aqua_leave' })).code, 'aqua_busy', '떠난 뒤에는 못 내린다');
    // 급회전: 제때 누르면 버티고 못 누르면 빠진다 (방 전체에 알린다).
    a.send({ t: 'aqua_hold', rid: `aqua-${++n}`, trip: ok.trip, turn: 0, ms: 420 });
    const fx = await b.next((m) => m.t === 'aqua_fx' && m.id === w.id, 1500);
    assert.equal(fx.fell, false);
    assert.equal((await ask(b, { t: 'aqua_hold', trip: ok.trip, turn: 0, ms: 100 })).code, 'bad_message', '안 탄 사람은 못 보낸다');
    a.send({ t: 'aqua_hold', rid: `aqua-${++n}`, trip: ok.trip, turn: 1, ms: -1 });
    assert.equal((await b.next((m) => m.t === 'aqua_fx' && m.id === w.id && m.turn === 1, 1500)).fell, true, '못 누르면 빠진다');
    a.send({ t: 'aqua_hold', rid: `aqua-${++n}`, trip: ok.trip, turn: 2, ms: 99999 });
    assert.equal((await b.next((m) => m.t === 'aqua_fx' && m.id === w.id && m.turn === 2, 1500)).fell, true, '너무 늦게 누르면 빠진다');
    // 끝: 선착장 땅에 내려 주고 결과.
    const end = await a.next((m) => m.t === 'aqua_end', 5000);
    assert.equal(end.ride, 'banana');
    assert.equal(end.held, 1);
    assert.equal(end.turns, rules.rides.get('banana').turns.length);
    const fix = await a.next((m) => m.t === 'correct', 1000);
    assert.ok(isLand(data, fix.x, fix.z), '선착장 땅');
    await a.next((m) => m.t === 'aqua_trips' && m.list.length === 0, 1000);
    // 다시 탈 수 있다.
    assert.equal((await ask(a, { t: 'aqua_join', ride: 'cruise' })).kind, 'join');
  });
});
