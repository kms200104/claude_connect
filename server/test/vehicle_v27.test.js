// v0.27 탈것 배터리 · 짐칸 · 개조.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

describe('v0.27 탈것 배터리 · 짐칸 · 개조', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  const ask = async (c, msg, ms = 3000) => {
    const rid = `v27-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  /** 그 모델을 사서 불러 올라탄다. */
  async function drive(model, spot, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v27-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, startSol: 30000000, vehicleEtaMs: 200, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    await moveTo(c, spot);
    const v = (await ask(c, { t: 'veh_buy', model })).v;
    await ask(c, { t: 'veh_call', v, x: spot.x, z: spot.z, yaw: 0 });
    await sleep(300);
    assert.equal((await ask(c, { t: 'veh_ride', v })).t, 'veh_ride');
    const room = [...server.rooms.rooms.values()][0];
    const me = [...room.players.values()][0];
    return { server, c, v, room, me, veh: me.profile.vehicles.find((x) => x.id === v) };
  }

  it('배터리: 달린 만큼 닳고 바닥나면 걷는 빠르기까지만, 배터리 팩 · 공구 창고 충전기로 충전', async () => {
    const spot = { x: -150, z: 140 };
    const { c, v, veh, me } = await drive('car_atv', spot, { startItems: 'battery_pack:1' });
    const max = data.garage.models.get('car_atv').range;
    assert.equal(veh.charge, max);
    veh.charge = 30;
    for (let i = 1; i <= 4; i++) {
      c.send({ t: 'move', x: spot.x, y: 0.1, z: spot.z - i * 10, yaw: 0, vx: 0, vz: -8 });
      await sleep(60);
    }
    const empty = await c.next((m) => m.t === 'veh_charge' && m.empty, 2000);
    assert.equal(empty.charge, 0);
    assert.equal(empty.max, max);
    // 바닥나면 걷는 빠르기까지만 받아 준다.
    const z0 = me.z;
    c.send({ t: 'move', x: spot.x, y: 0.1, z: z0 - 30, yaw: 0, vx: 0, vz: -12 });
    await sleep(100);
    assert.ok(Math.hypot(me.vx, me.vz) < 12, '빠르기를 깎았다');
    const pack = await ask(c, { t: 'veh_refuel', v, how: 'pack' });
    assert.equal(pack.how, 'pack');
    assert.equal(pack.charge, Math.round(max * data.garage.charge.pack_fix));
    assert.equal((await ask(c, { t: 'veh_refuel', v, how: 'pack' })).code, 'not_enough_items');
    assert.equal((await ask(c, { t: 'veh_refuel', v, how: 'station' })).code, 'too_far', '공구 창고에서 멀다');
    // 공구 창고 곁으로 (타고 간다).
    const bench = data.crafting.publicBenches[0];
    me.x = bench.x + 3;
    me.z = bench.z;
    const st = await ask(c, { t: 'veh_refuel', v, how: 'station' });
    assert.equal(st.charge, max);
    assert.equal((await ask(c, { t: 'veh_refuel', v, how: 'station' })).code, 'bad_part', '이미 가득');
  });

  it('짐칸: 트럭 곁에서 넣고 꺼내고, 칸이 차면 거절, 실은 채로 다닌다 (저장)', async () => {
    const spot = { x: -150, z: 140 };
    const { c, v, veh, server } = await drive('car_truck', spot, { startItems: 'wood:30,nails:5,cloth:3' });
    const me = [...[...server.rooms.rooms.values()][0].players.values()][0];
    const slotOf = (id) => me.slots.findIndex((x) => x?.id === id);
    const put = await ask(c, { t: 'veh_cargo', v, op: 'put', slot: slotOf('wood'), n: 20 });
    assert.equal(put.kind, 'cargo');
    assert.deepEqual(put.items, [{ id: 'wood', n: 20 }]);
    await ask(c, { t: 'veh_cargo', v, op: 'put', slot: slotOf('nails') });
    const took = await ask(c, { t: 'veh_cargo', v, op: 'take', id: 'wood', n: 5 });
    assert.deepEqual(took.items, [{ id: 'wood', n: 15 }, { id: 'nails', n: 5 }]);
    assert.deepEqual(veh.cargo, [{ id: 'wood', n: 15 }, { id: 'nails', n: 5 }], '탈것에 실렸다');
    // 타고 멀리 가도 실은 채로.
    me.x += 40;
    assert.equal((await ask(c, { t: 'veh_cargo', v, op: 'take', id: 'nails' })).items.length, 1);
    // 세워 두고 멀리 가면 못 꺼낸다.
    await ask(c, { t: 'veh_ride', v: '' });
    me.x += 20;
    assert.equal((await ask(c, { t: 'veh_cargo', v, op: 'take', id: 'wood' })).code, 'not_near_vehicle');
    const saved = server.rooms.rooms.values().next().value.toSave();
    const prof = Object.values(saved.profiles)[0] ?? saved.profiles[0];
    assert.ok(JSON.stringify(prof).includes('"cargo":[{"id":"wood","n":15}]'), '저장된다');
    // ATV 는 4칸.
    assert.equal(data.garage.models.get('car_atv').cargo, 4);
  });

  it('개조: 스파이크 범퍼는 들이받는 피해를 키우고 차는 덜 닳고, 철판 장갑은 내구도를 늘리고 벽 충돌을 덜 받는다', async () => {
    const spot = { x: -150, z: 140 };
    const { c, v, veh, room, me } = await drive('car_truck', spot, { startItems: 'bumper_spikes:1,armor_plate:1', clockOffsetMin: 0, worldTimeScale: 1 });
    const base = data.garage.models.get('car_truck').durability;
    assert.equal((await ask(c, { t: 'veh_mod', v, item: 'wood' })).code, 'bad_part');
    const plate = await ask(c, { t: 'veh_mod', v, item: 'armor_plate' });
    assert.equal(plate.kind, 'mod');
    assert.equal(plate.max, Math.round(base * data.garage.mods.armor_plate.durability));
    assert.equal(plate.hp, plate.max, '늘어난 만큼 채운다');
    assert.equal((await ask(c, { t: 'veh_mod', v, item: 'armor_plate' })).code, 'already_boarded', '이미 달았다');
    const spikes = await ask(c, { t: 'veh_mod', v, item: 'bumper_spikes' });
    assert.deepEqual(spikes.mods, ['armor_plate', 'bumper_spikes']);
    const snap = await c.next((m) => m.t === 'snap' && m.p.some((p) => p.mount?.mx?.length === 2), 2000);
    assert.ok(snap);
    // 벽 충돌: 장갑이면 덜 닳는다.
    c.send({ t: 'veh_crash', s: 10, rid: 'm-crash' });
    const hp = await c.next((m) => m.t === 'veh_hp' && m.why === 'crash', 2000);
    assert.equal(hp.max - hp.hp, Math.ceil((10 - data.garage.repair.crash_min) * data.garage.repair.crash_k * data.garage.mods.armor_plate.crash));
    // 들이받기: 스파이크면 피해가 크다.
    room.creatures ??= new Map();
    room.creatures.set('zm1', { id: 'zm1', k: 'bloated', x: me.x, z: me.z - 2, yaw: 0, hp: 50, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
    const hit = await ask(c, { t: 'ram', c: 'zm1', s: 10, dx: 0, dz: -1 });
    const M = data.garage.models.get('car_truck').mass + data.garage.mods.armor_plate.mass;
    const m = data.survival.creatures.kinds.bloated.mass;
    const u = ((1 + data.survival.ram.restitution) * M) / (M + m) * 10;
    assert.equal(hit.dmg, Math.ceil(u * u * data.survival.ram.dmg_k * data.garage.mods.bumper_spikes.ram_dmg));
    void veh;
  });
});
