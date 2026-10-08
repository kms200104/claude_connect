import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { resaleValue, sanitizeVehicles, vehicleStats, partPrice } from '../src/garage.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const rules = data.garage;

describe('v19 차고 탈것 규칙', () => {
  it('모델: 자전거 넷 · 전기오토바이 셋, 실제 시세 근처 값, 오토바이가 더 빠르다', () => {
    const kinds = [...rules.models.values()].map((m) => m.kind);
    assert.equal(kinds.filter((k) => k === 'bike').length, 4);
    assert.equal(kinds.filter((k) => k === 'moto').length, 3);
    for (const m of rules.models.values()) {
      if (m.kind === 'bike') assert.ok(m.price >= 150000 && m.price <= 3000000, `${m.id} ${m.price}`);
      else assert.ok(m.price >= 1500000 && m.price <= 9000000, `${m.id} ${m.price}`);
    }
    const fastestBike = Math.max(...[...rules.models.values()].filter((m) => m.kind === 'bike').map((m) => m.top));
    const slowestMoto = Math.min(...[...rules.models.values()].filter((m) => m.kind === 'moto').map((m) => m.top));
    assert.ok(slowestMoto > fastestBike);
  });

  it('꾸미기 부품이 많고 칸마다 고를 거리가 있다 (도색 · 조명 · 성능 · 액세서리)', () => {
    assert.ok(rules.parts.size >= 60, `${rules.parts.size}개`);
    for (const slot of rules.slotIds) {
      for (const kind of ['bike', 'moto']) {
        const n = [...rules.parts.values()].filter((p) => p.slot === slot && p.kinds.includes(kind)).length;
        assert.ok(n >= 1, `${kind} 의 ${slot} 칸`);
      }
    }
    assert.ok([...rules.parts.values()].some((p) => p.light?.range >= 15), '밤길을 멀리 비추는 전조등');
  });

  it('성능 = 모델 × 끼운 부품 배율, 되팔 때는 산 값의 resale', () => {
    const v = { id: 'V1', model: 'moto_scooter', owned: ['drive_motor', 'drive_ctrl', 'paint_mint'], fit: { drive: 'drive_motor', paint: 'paint_mint' } };
    const s = vehicleStats(rules, v);
    const m = rules.models.get('moto_scooter');
    assert.ok(Math.abs(s.top - m.top * 1.12) < 1e-9);
    assert.ok(Math.abs(s.accel - m.accel * 1.2) < 1e-9);
    const spent = m.price + partPrice(rules, 'drive_motor', 'moto') + partPrice(rules, 'drive_ctrl', 'moto') + partPrice(rules, 'paint_mint', 'moto');
    assert.equal(resaleValue(rules, v), Math.round((spent * rules.resale) / 100) * 100);
    assert.equal(partPrice(rules, 'drive_motor', 'bike'), 0, '오토바이 모터는 자전거에 안 맞는다');
  });

  it('저장된 차고 다듬기: 모르는 모델 · 안 산 부품 · 칸이 틀린 부품은 버린다', () => {
    const out = sanitizeVehicles([
      { id: 'V1', model: 'bike_city', owned: ['paint_mint', 'drive_motor', 'nope'], fit: { paint: 'paint_mint', drive: 'drive_motor', trim: 'paint_mint' } },
      { id: 'V2', model: 'jet_ski', owned: [], fit: {} },
      { id: 'V1', model: 'bike_road', owned: [], fit: {} },
    ], rules);
    assert.deepEqual(out, [{ id: 'V1', model: 'bike_city', owned: ['paint_mint'], fit: { paint: 'paint_mint' } }]);
  });
});

describe('v19 차고 탈것 사기 · 꾸미기 · 타기', () => {
  let saveDir;
  let server;
  const clients = [];
  const open = async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    return c;
  };
  let n = 0;
  const rid = () => `veh-${++n}`;
  const ask = async (c, msg) => {
    const r = rid();
    c.send({ ...msg, rid: r });
    return c.next((m) => m.rid === r, 3000);
  };

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-veh-'));
    server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', startSol: 12000000 });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('사고 · 부품 사서 끼우고 · 산 부품은 공짜로 바꿔 끼우고 · 타면 친구 화면에 보인다', async () => {
    const a = await open();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const wa = await a.type('welcome');
    const b = await open();
    b.send({ t: 'join', v: PROTOCOL_VERSION, uid: uid(), code: wa.code });
    await b.type('welcome');

    assert.equal((await ask(a, { t: 'veh_buy', model: 'hoverboard' })).code, 'bad_vehicle');
    const bought = await ask(a, { t: 'veh_buy', model: 'moto_sport' });
    assert.equal(bought.t, 'veh_result');
    assert.equal(bought.cost, 6890000);
    assert.equal(bought.sol, 12000000 - 6890000);
    const prof = await a.next((m) => m.t === 'profile' && m.vehicles?.length === 1, 2000);
    assert.deepEqual(prof.vehicles, [{ id: bought.v, model: 'moto_sport', owned: [], fit: {} }]);
    assert.equal((await ask(a, { t: 'veh_buy', model: 'moto_sport' })).code, 'not_enough_sol', '두 대째는 돈이 모자란다');

    const v = bought.v;
    assert.equal((await ask(a, { t: 'veh_part', v, part: 'front_basket' })).code, 'bad_part', '자전거 바구니는 오토바이에 안 맞는다');
    const paint = await ask(a, { t: 'veh_part', v, part: 'paint_cherry' });
    assert.equal(paint.cost, 180000);
    const pearl = await ask(a, { t: 'veh_part', v, part: 'paint_pearl' });
    assert.equal(pearl.cost, 390000, '특수 도장은 더 비싸다');
    const back = await ask(a, { t: 'veh_part', v, part: 'paint_cherry' });
    assert.equal(back.cost, 0, '산 적 있는 색은 공짜로 다시 칠한다');
    const light = await ask(a, { t: 'veh_part', v, part: 'light_hi' });
    assert.equal(light.cost, 189000);
    const unfit = await ask(a, { t: 'veh_unfit', v, slot: 'light' });
    assert.equal(unfit.kind, 'unfit');
    assert.equal((await ask(a, { t: 'veh_unfit', v, slot: 'light' })).code, 'bad_part');
    await ask(a, { t: 'veh_part', v, part: 'light_hi' });

    const rode = await ask(a, { t: 'veh_ride', v });
    assert.deepEqual(rode.mount, { v, m: 'moto_sport', f: { paint: 'paint_cherry', light: 'light_hi' } });
    const seen = await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === wa.id && p.mount?.m === 'moto_sport'), 3000);
    assert.deepEqual(seen.p.find((p) => p.id === wa.id).mount.f, { paint: 'paint_cherry', light: 'light_hi' });

    // 타는 동안 부품을 바꾸면 친구 화면의 모양도 바뀐다.
    await ask(a, { t: 'veh_part', v, part: 'rear_topbox' });
    await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === wa.id && p.mount?.f?.rear === 'rear_topbox'), 3000);

    const off = await ask(a, { t: 'veh_ride', v: '' });
    assert.equal(off.mount, null);
    await b.next((m) => m.t === 'snap' && m.p.some((p) => p.id === wa.id && !p.mount), 3000);
  });

  it('이동 속도 검사: 걸을 때는 고쳐지는 빠르기도 오토바이를 타면 받아 준다', async () => {
    const a = await open();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await a.type('welcome');
    const me = w.players.find((p) => p.id === w.id);
    const bought = await ask(a, { t: 'veh_buy', model: 'moto_scooter' });
    const run = async () => {
      let x = me.x;
      let corrected = false;
      const watch = a.next((m) => m.t === 'correct', 1500).then(() => (corrected = true)).catch(() => {});
      for (let i = 0; i < 8; i++) {
        await sleep(100);
        x += 2.1; // 0.1초에 2.1m — 걷기 · 달리기 한도(7.2 × 1.6 × 0.1 + 0.6)를 넘고 스쿠터(11 × 1.6 × 0.1 + 0.6) 안
        a.send({ t: 'move', x, y: me.y, z: me.z, yaw: 0, vx: 21, vz: 0 });
      }
      await watch;
      return { corrected, x };
    };
    const walking = await run();
    assert.ok(walking.corrected, '걸어서는 너무 빠르다');
    // 서버가 고쳐 준 마지막 자리에서 다시 출발한다.
    await sleep(300);
    const fixes = a.inbox.filter((m) => m.t === 'correct');
    a.inbox = a.inbox.filter((m) => m.t !== 'correct');
    me.x = fixes.length ? fixes[fixes.length - 1].x : walking.x;
    await ask(a, { t: 'veh_ride', v: bought.v });
    const riding = await run();
    assert.equal(riding.corrected, false, '스쿠터로는 받아 준다');
  });

  it('차고는 max_owned 대까지 · 팔면 resale 만큼 돌려받고 타던 탈것에서 내린다', async () => {
    const a = await open();
    a.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await a.type('welcome');
    const ids = [];
    for (let i = 0; i < rules.max_owned; i++) ids.push((await ask(a, { t: 'veh_buy', model: 'bike_city' })).v);
    assert.equal((await ask(a, { t: 'veh_buy', model: 'bike_city' })).code, 'garage_full');
    await ask(a, { t: 'veh_ride', v: ids[0] });
    const sold = await ask(a, { t: 'veh_sell', v: ids[0] });
    assert.equal(sold.cost, -Math.round((239000 * rules.resale) / 100) * 100);
    const prof = await a.next((m) => m.t === 'profile' && m.vehicles?.length === rules.max_owned - 1, 2000);
    assert.ok(prof);
    assert.equal((await ask(a, { t: 'veh_ride', v: ids[0] })).code, 'bad_vehicle', '판 탈것은 탈 수 없다');
  });
});
