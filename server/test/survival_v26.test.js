// v0.26 피 냄새 · 탈것 내구도 · 들이받기 · 보급 낙하.
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
const S = data.survival;
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.26 피 냄새', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function start(hour, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-v26-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour), random: () => 0.5, creatureSpawnScale: 10000, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    return { server, c, room: [...server.rooms.rooms.values()][0] };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `v26-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const put = (room, id, p, k = 'shambler') => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: S.creatures.kinds[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };

  it('맞으면 피를 흘려 핏자국을 남기고, 크리처가 더 멀리서 알아채고, 붕대로 멈춘다', async () => {
    const { c, room } = await start(23, { startItems: 'bandage:2' });
    const spot = { x: -150, z: 140 };
    await moveTo(c, spot);
    put(room, 'zs1', { x: spot.x - 0.6, z: spot.z });
    const bleed = await c.next((m) => m.t === 'bleed' && m.on, 8000);
    const me = [...room.players.values()][0];
    assert.equal(bleed.id, me.id);
    room.creatures.clear();
    me.hurtUntil = Infinity;
    const drop = await c.next((m) => m.t === 'scent', 4000);
    assert.ok(Math.hypot(drop.x - spot.x, drop.z - spot.z) < 1);
    // 퉁퉁이 aggro 12 밖 18m — 피 냄새 (× 1.8) 면 알아챈다.
    put(room, 'zs2', { x: spot.x, z: spot.z + 18 }, 'bloated');
    await sleep(300);
    assert.equal(room.creatures.get('zs2').target, me.id, '피 냄새로 알아챘다');
    // 붕대로 멈춘다 → 18m 밖은 다시 못 알아챈다.
    const slot = me.slots.findIndex((x) => x?.id === 'bandage');
    await ask(c, { t: 'use', slot });
    const stop = await c.next((m) => m.t === 'bleed' && !m.on, 2000);
    assert.equal(stop.id, me.id);
    room.creatures.get('zs2').target = 0;
    room.creatures.get('zs2').z = spot.z + 18;
    await sleep(300);
    assert.equal(room.creatures.get('zs2').target, 0, '멈춘 뒤에는 알아채지 못한다');
  });

  it('아무도 쫓지 않는 크리처는 핏자국을 따라온다', async () => {
    const { c, room } = await start(23);
    const me = [...room.players.values()][0];
    const spot = { x: -150, z: 140 };
    await moveTo(c, spot);
    me.hurtUntil = Infinity;
    // 핏자국을 길게 남긴 것처럼 놓고, 사람은 멀리 (aggro 밖).
    room.scent = [{ id: me.id, x: spot.x + 30, z: spot.z + 12, t: performance.now() }];
    put(room, 'zs3', { x: spot.x + 38, z: spot.z + 12 }, 'shambler');
    const before = room.creatures.get('zs3').x;
    await sleep(1500);
    const z = room.creatures.get('zs3');
    assert.equal(z.target, 0);
    assert.ok(before - z.x > 0.9, `핏자국 쪽으로 왔다 (${before} → ${z.x})`);
    assert.ok(Math.abs(z.z - (spot.z + 12)) < 0.2, `사람 쪽이 아니라 핏자국 쪽 (${z.z})`);
  });
});

describe('v0.26 차량 · 내구도 · 들이받기 · 보급 낙하', () => {
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
    const rid = `car-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const put = (room, id, p, k = 'shambler') => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp: S.creatures.kinds[k].hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };
  /** 미니트럭을 사서 불러 올라탄다. */
  async function truck(hour, spot, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-car-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour), random: () => 0.5, creatureSpawnScale: 10000, startSol: 30000000, vehicleEtaMs: 200, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    await moveTo(c, spot);
    const v = (await ask(c, { t: 'veh_buy', model: 'car_truck' })).v;
    await ask(c, { t: 'veh_call', v, x: spot.x, z: spot.z, yaw: 0 });
    await sleep(300);
    const rode = await ask(c, { t: 'veh_ride', v });
    assert.equal(rode.t, 'veh_ride', JSON.stringify(rode));
    const room = [...server.rooms.rooms.values()][0];
    return { server, c, v, room, me: [...room.players.values()][0] };
  }

  it('차량이 매장에 있고 내구도가 있다', () => {
    const atv = data.garage.models.get('car_atv');
    const t = data.garage.models.get('car_truck');
    assert.equal(atv.kind, 'car');
    assert.ok(t.mass > atv.mass && t.durability > atv.durability);
    assert.ok(data.garage.kinds.car);
  });

  it('빠르게 들이받으면 크리처가 빠르기만큼 멀리 날아가고 크게 다치며, 차도 조금 닳는다', async () => {
    const spot = { x: -150, z: 140 };
    const { c, room } = await truck(23, spot);
    put(room, 'zr1', { x: spot.x, z: spot.z - 2 });
    const hit = await ask(c, { t: 'ram', c: 'zr1', s: 12, dx: 0, dz: -1 });
    assert.equal(hit.t, 'rammed');
    assert.equal(hit.hard, true);
    const M = data.garage.models.get('car_truck').mass;
    const m = S.creatures.kinds.shambler.mass;
    const u = ((1 + S.ram.restitution) * M) / (M + m) * 12;
    assert.ok(Math.abs(hit.u - u) < 0.05, `날아가는 빠르기 ${hit.u} ≈ ${u}`);
    assert.equal(hit.dmg, Math.ceil(u * u * S.ram.dmg_k));
    assert.ok(hit.slow < 0.15, '무거운 트럭은 거의 안 느려진다');
    const hp = await c.next((x) => x.t === 'veh_hp', 2000);
    assert.ok(hp.hp < hp.max && hp.hp > hp.max - 10, `트럭 내구도 ${hp.hp}/${hp.max}`);
    const dead = await c.next((x) => x.t === 'creature_dead' && x.id === 'zr1', 5000);
    const flew = Math.hypot(dead.x - spot.x, dead.z - (spot.z - 2));
    assert.ok(flew > (u * u) / (2 * S.ram.slide_decel) * 0.6, `멀리 날아갔다 (${flew.toFixed(1)}m)`);
    // 더 빠르면 더 멀리 (공식).
    assert.ok((u * 1.5) ** 2 / (2 * S.ram.slide_decel) > (u * u) / (2 * S.ram.slide_decel));
  });

  it('느리게 닿으면 크리처는 넘어지기만 하고 차는 확 느려진다 · 날아가 벽에 부딪히면 더 다친다', async () => {
    const spot = { x: -150, z: 140 };
    const { c, room } = await truck(23, spot);
    put(room, 'zr2', { x: spot.x, z: spot.z - 1.5 }, 'bloated');
    const soft = await ask(c, { t: 'ram', c: 'zr2', s: 2, dx: 0, dz: -1 });
    assert.equal(soft.hard, false);
    assert.ok(soft.slow > 0.5);
    assert.ok(room.creatures.get('zr2').downUntil > performance.now(), '넘어졌다');
    const w = await c.next((x) => x.t === 'creatures' && x.c.some((k) => k.id === 'zr2' && k.f === 2), 1000);
    assert.ok(w);
    // 빈집 h01 벽 쪽으로 날린다.
    const H = S.houseById.get('h01');
    room.creatures.clear();
    const wallSpot = { x: H.x, z: H.z + H.d / 2 + 3.2 };
    const me = [...room.players.values()][0];
    me.x = wallSpot.x;
    me.z = wallSpot.z + 2;
    put(room, 'zr3', wallSpot, 'bloated');
    const hard = await ask(c, { t: 'ram', c: 'zr3', s: 12, dx: 0, dz: -1 });
    assert.equal(hard.hard, true);
    const wall = await c.next((x) => x.t === 'creature_hit' && x.id === 'zr3' && x.wall > 0, 3000);
    assert.ok(wall.wall >= 1, `벽 추가 피해 ${wall.wall}`);
  });

  it('벽에 세게 부딪치면 차가 닳고, 0 이 되면 고장 — 고치기(재료) · 정비(솔)', async () => {
    const spot = { x: -150, z: 140 };
    const { c, v, me } = await truck(12, spot, { startItems: 'scrap_metal:2,nails:2' });
    c.send({ t: 'veh_crash', s: 10, rid: 'cr-1' });
    const hp = await c.next((x) => x.t === 'veh_hp' && x.why === 'crash', 2000);
    assert.equal(hp.max - hp.hp, Math.ceil((10 - data.garage.repair.crash_min) * data.garage.repair.crash_k));
    // v0.28.16 고장 나기 전에도 타는 채로 재료로 고친다 (HUD '수리').
    const early = await ask(c, { t: 'veh_repair', v, how: 'kit' });
    assert.equal(early.kind, 'repair');
    assert.equal(early.hp, Math.min(hp.max, hp.hp + Math.ceil(hp.max * data.garage.repair.kit_fix)));
    assert.equal(me.mount, v, '타는 채로');
    me.slots[10] = { id: 'scrap_metal', n: 1 };
    me.slots[11] = { id: 'nails', n: 1 };
    const veh = me.profile.vehicles.find((x) => x.id === v);
    veh.hp = 5;
    await sleep(450);
    c.send({ t: 'veh_crash', s: 12, rid: 'cr-2' });
    const broke = await c.next((x) => x.t === 'veh_hp' && x.broken, 2000);
    assert.equal(broke.hp, 0);
    assert.equal(me.mount, null, '고장나면 내린다');
    assert.equal((await ask(c, { t: 'veh_ride', v })).code, 'vehicle_broken');
    const kit = await ask(c, { t: 'veh_repair', v, how: 'kit' });
    assert.equal(kit.hp, Math.ceil(hp.max * data.garage.repair.kit_fix));
    const sol = me.profile.sol;
    const shop = await ask(c, { t: 'veh_repair', v, how: 'shop' });
    assert.equal(shop.hp, shop.max);
    assert.equal(me.profile.sol, sol - shop.cost);
    assert.equal((await ask(c, { t: 'veh_ride', v })).t, 'veh_ride', '고치면 다시 탄다');
  });

  it('보급 낙하로 부르면 헬기(heli)가 솔을 받고 떨어뜨린다', async () => {
    const spot = { x: -150, z: 140 };
    const { c, v, me, room } = await truck(12, spot);
    await ask(c, { t: 'veh_ride', v: '' });
    await moveTo(c, { x: spot.x + 20, z: spot.z });
    const sol = me.profile.sol;
    const called = await ask(c, { t: 'veh_call', v, mode: 'air', x: spot.x + 21, z: spot.z, yaw: 0 });
    assert.equal(called.npc, 'heli');
    assert.equal(called.cost, data.garage.delivery.air_cost);
    assert.equal(me.profile.sol, sol - data.garage.delivery.air_cost);
    const parked = await c.next((x) => x.t === 'veh_parked' && x.list.some((p) => p.v === v && p.npc === 'heli'), 2000);
    assert.ok(parked);
    void room;
  });
});

