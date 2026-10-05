import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Room } from '../src/rooms.js';
import { defaultFurniture, interiorOrigin, lobbyOf, onFloor, planIdOf, roomAt } from '../src/homes.js';
import { Client, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

const floorplans = JSON.parse(readFileSync(new URL('../../data/realestate/floorplans.json', import.meta.url), 'utf8'));

describe('v0.10 집 안 계산', () => {
  it('평면도 다섯 가지: 26평 A/B · 27평 · 34평 · 35평, 크기가 평형에 맞다', () => {
    assert.deepEqual([...data.plans.keys()].sort(), ['26a', '26b', '27', '34', '35']);
    for (const p of data.plans.values()) {
      // v0.12: 게임 안 집은 가로·세로 size_scale 배 (넓이 size_scale² 배) 로 키웠다. 평면도 자체의 넓이는 그 배율을 나눠 본다.
      const k = floorplans.size_scale ?? 1;
      const area = p.rooms.reduce((a, r) => a + r.rects.reduce((b, [x0, z0, x1, z1]) => b + (x1 - x0) * (z1 - z0), 0), 0) / (k * k);
      const small = p.pyeong < 30;
      // 전용 59㎡ 는 발코니 확장 포함 70~90㎡, 84㎡ 는 95~125㎡ 정도.
      assert.ok(small ? area > 65 && area < 92 : area > 92 && area < 128, `${p.id} 바닥 ${area.toFixed(1)}㎡`);
      const bedrooms = p.rooms.filter((r) => r.kind === 'bedroom' || r.kind === 'master').length;
      assert.equal(bedrooms, small ? 3 : 4, `${p.id} 방 수`);
      assert.ok(onFloor(p, p.spawn[0], p.spawn[1]), `${p.id} 현관에서 시작`);
      assert.equal(roomAt(p, p.spawn[0], p.spawn[1]).kind, 'entry');
    }
  });

  it('동·라인마다 평형과 평면, 호수마다 겹치지 않는 집 안 자리', () => {
    const plan = (id) => planIdOf(data.realestate, data.units.find((u) => u.id === id));
    assert.equal(plan('101-501'), '26a');
    assert.equal(plan('101-502'), '27');
    assert.equal(plan('102-301'), '34');
    assert.equal(plan('102-302'), '35');
    assert.equal(plan('103-301'), '26b');
    const origins = data.units.map((u) => interiorOrigin(data.floorplans, data.units, u.id));
    for (let i = 0; i < origins.length; i++) {
      assert.ok(Math.abs(origins[i].x) <= 200 && origins[i].z + 10 <= 200 && origins[i].x < -110, '섬 밖, 서버 경계 안');
      for (let j = i + 1; j < origins.length; j++) {
        assert.ok(Math.abs(origins[i].x - origins[j].x) >= 15 || Math.abs(origins[i].z - origins[j].z) >= 12, '집끼리 겹치지 않는다');
      }
    }
  });

  it('처음 놓이는 가구: TV · 에어컨 · 선풍기 · 침대(방마다), 모두 바닥 위', () => {
    for (const p of data.plans.values()) {
      const list = defaultFurniture(p);
      const items = list.map((f) => f.item);
      for (const need of ['tv', 'air_conditioner', 'electric_fan', 'bed_double']) assert.ok(items.includes(need), `${p.id}: ${need}`);
      const beds = items.filter((i) => i.startsWith('bed_')).length;
      assert.equal(beds, p.rooms.filter((r) => r.kind === 'bedroom' || r.kind === 'master').length, `${p.id}: 방마다 침대`);
      for (const f of list) {
        assert.ok(onFloor(p, f.x, f.z), `${p.id}: ${f.item} 바닥 위`);
        assert.equal(data.kindOf(f.item), 'furniture');
      }
      assert.equal(roomAt(p, list.find((f) => f.item === 'bed_double').x, list.find((f) => f.item === 'bed_double').z).kind, 'master', `${p.id}: 더블 침대는 안방`);
      assert.equal(roomAt(p, list.find((f) => f.item === 'tv').x, list.find((f) => f.item === 'tv').z).kind, 'living', `${p.id}: TV 는 거실`);
    }
  });
});

describe('v0.10 집 안 서버 연동', () => {
  let saveDir;
  let server;
  const clients = [];
  let rid = 0;
  const newRid = () => `h${++rid}`;
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
  const roomOf = (code) => [...server.rooms.rooms.values()].find((r) => r.code === code);

  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v10-'));
    server = createServer({ port: 0, saveDir, moveSlackMeters: 400, weatherForce: 'clear', eventForce: 'none', startSol: 2000000000, startItems: 'fabric_sofa:1' });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('공동 현관에서 집 구경 → 기본 가구, 내 집이면 옮기기·돌리기·회수·놓기, 남의 집은 구경만', async () => {
    const a = await open();
    const wa = await enter(a);
    const b = await open();
    await enter(b, { code: wa.code });
    const room = roomOf(wa.code);
    a.send({ t: 'home_enter', rid: newRid(), unit: '102-501' });
    assert.equal((await a.type('error')).code, 'not_at_lobby');
    const lobby = lobbyOf(data.realestate, data.floorplans, '102');
    await moveTo(a, lobby.x, lobby.z);
    a.send({ t: 'apt_buy', rid: newRid(), unit: '102-501', loan: 0 });
    await a.type('apt_result');
    a.send({ t: 'home_enter', rid: newRid(), unit: '102-501' });
    const home = await a.type('home');
    assert.equal(home.plan, '34');
    assert.equal(home.edit, true);
    assert.equal(home.f.length, 7, 'TV · 에어컨 · 선풍기 · 침대 4');
    const o = interiorOrigin(data.floorplans, data.units, '102-501');
    assert.deepEqual([home.ox, home.oz], [o.x, o.z]);
    // 침대 하나를 옆으로 옮기고 90° 돌린다 (보이지 않는 0.25m 격자에 맞춘다).
    const bed = home.f.find((f) => f[1] === 'bed_single');
    a.send({ t: 'home_move', rid: newRid(), id: bed[0], x: bed[2] + 0.31, z: bed[3] - 0.12, rot: 2 });
    const moved = await a.type('home_f');
    const after = moved.f.find((f) => f[0] === bed[0]);
    assert.equal(after[2] % 0.25, 0);
    assert.equal(after[4], 2);
    // 벽 밖(바닥 아님)으로는 못 옮긴다.
    a.send({ t: 'home_move', rid: newRid(), id: bed[0], x: -3, z: 2, rot: 0 });
    assert.equal((await a.type('error')).code, 'bad_place');
    // 회수 → 가방, 다시 놓기.
    const fan = home.f.find((f) => f[1] === 'electric_fan');
    a.send({ t: 'home_pickup', rid: newRid(), id: fan[0] });
    const picked = await a.type('home_f');
    assert.ok(!picked.f.some((f) => f[0] === fan[0]));
    const inv = await a.next((m) => m.t === 'inventory' && m.slots.some((s) => s?.id === 'electric_fan'));
    const sofaSlot = inv.slots.findIndex((s) => s?.id === 'fabric_sofa');
    a.send({ t: 'home_place', rid: newRid(), slot: sofaSlot, x: 9.0, z: 7.0, rot: 4 });
    const placed = await a.type('home_f');
    assert.ok(placed.f.some((f) => f[1] === 'fabric_sofa' && f[4] === 4));
    assert.equal(room.homeItems['102-501'].length, 7, '선풍기 하나 빼고 소파 하나 더');
    // 친구는 구경만.
    await moveTo(b, lobby.x + 0.5, lobby.z);
    b.send({ t: 'home_enter', rid: newRid(), unit: '102-501' });
    const visit = await b.type('home');
    assert.equal(visit.edit, false);
    assert.equal(visit.f.length, 7);
    b.send({ t: 'home_pickup', rid: newRid(), id: bed[0] });
    assert.equal((await b.type('error')).code, 'not_editable');
    // 주인이 옮기면 같이 있는 친구에게도 보인다.
    a.send({ t: 'home_move', rid: newRid(), id: bed[0], x: after[2], z: after[3], rot: 3 });
    const seen = await b.next((m) => m.t === 'home_f' && m.f.some((f) => f[0] === bed[0] && f[4] === 3));
    assert.equal(seen.rid, null);
    // 현관문 곁에서 나가기 → 공동 현관 앞.
    a.send({ t: 'home_exit', rid: newRid() });
    const out = await a.type('home');
    assert.equal(out.unit, '');
    assert.ok(Math.hypot(out.x - lobby.x, out.z - lobby.z) < 1.5);
    // 아직 아무도 산 적 없는 집은 모델하우스처럼 기본 가구로 구경만.
    await moveTo(a, lobby.x, lobby.z);
    a.send({ t: 'home_enter', rid: newRid(), unit: '102-1002' });
    const model = await a.type('home');
    assert.equal(model.plan, '35');
    assert.equal(model.edit, false);
    assert.equal(model.owner, 0);
  });

  it('v0.12: 집을 1.4배로 키우기 전(schema 5) 저장의 집 가구는 같은 배율로 옮겨진다', () => {
    const unit = data.units[0];
    const plan = data.plans.get(planIdOf(data.realestate, unit));
    const def = defaultFurniture(plan)[0];
    const k = floorplans.size_scale;
    const old = { id: 'h1', item: def.item, x: def.x / k, z: def.z / k, rot: 0 };
    const saved = (schema) => ({ schema, code: 'ABCDEF', createdAt: 1, profiles: {}, world: { homeItems: { [unit.id]: [old] } } });
    const moved = Room.fromSave(saved(5), 2, defaultConfig, data).homeItems[unit.id][0];
    assert.ok(Math.abs(moved.x - def.x) < 1e-9 && Math.abs(moved.z - def.z) < 1e-9, `옛 자리 ×${k}: ${moved.x}, ${moved.z}`);
    const kept = Room.fromSave(saved(6), 2, defaultConfig, data).homeItems[unit.id]?.[0];
    assert.ok(!kept || (kept.x === old.x && kept.z === old.z), '새 저장은 그대로');
  });
});
