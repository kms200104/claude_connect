// v0.23 생존: 빈집 가구 뒤지기 · 밤 크리처 · 맞서 싸우기 · 쓰러뜨리면 떨어지는 아이템 · 체력 · 회복 · 기절.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { groundProblem } from '../src/world.js';
import { rollLoot } from '../src/survival.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const S = data.survival;
const count = (inv, id) => inv.slots.reduce((sum, s) => sum + (s && s.id === id ? s.n : 0), 0);
/** 한국 시각으로 그 시가 되게 하는 시계 옮김 (분). */
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.23 빈집촌 규칙', () => {
  it('빈집 32채 · 가구 192개 (v0.28.2), 집 안은 놓기 · 심기 금지 (크리처도 못 들어온다)', () => {
    assert.equal(S.houses.length, 32);
    assert.equal(S.containers.size, 192);
    for (const h of S.houses) assert.equal(groundProblem(data, h.x, h.z), 'building', h.id);
    for (const kind of ['fridge', 'drawer', 'wardrobe', 'sink', 'shoe_cabinet', 'medicine']) assert.ok(S.loot.kinds[kind], kind);
  });

  it('뒤지면 그 가구 표에서 나온다 (빈손일 수도)', () => {
    let k = 0;
    const seq = [0.9, 0.0, 0.0, 0.9, 0.99, 0.5];
    const r = () => seq[k++ % seq.length];
    const got = rollLoot(S.loot.kinds.fridge, r);
    assert.ok(got.length >= 1);
    for (const it of got) assert.ok(S.loot.kinds.fridge.items.some((e) => e.id === it.id));
    assert.deepEqual(rollLoot(S.loot.kinds.fridge, () => 0.01), [], 'empty 확률 아래면 빈손');
  });
});

describe('v0.23 뒤지기 · 크리처 · 체력', () => {
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
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-surv-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour), random: () => 0.5, ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { server, c, w };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `sv-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, x, z) => {
    c.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };

  it('낮: 가구를 뒤지면 아이템, 다시 뒤지면 이미 뒤짐, 멀면 거절, 다른 사람에게도 빈 가구로 보인다', async () => {
    const { c, w } = await start(12);
    assert.equal(w.surv.hp, w.surv.max);
    assert.equal(w.surv.night, false);
    const box = S.containers.get('h01_2'); // 냉장고
    assert.equal(box.kind, 'fridge');
    await moveTo(c, box.x + 2.5, box.z);
    assert.equal((await ask(c, { t: 'loot', c: box.id })).code, 'too_far');
    await moveTo(c, box.x + 0.8, box.z);
    const got = await ask(c, { t: 'loot', c: box.id });
    assert.equal(got.t, 'looted');
    assert.ok(got.items.length >= 1, JSON.stringify(got));
    const inv = await c.type('inventory');
    for (const it of got.got) assert.ok(count(inv, it.id) >= it.n, it.id);
    const seen = await c.next((m) => m.t === 'container' && m.c === box.id);
    assert.ok(seen.until > 0);
    assert.equal((await ask(c, { t: 'loot', c: box.id })).code, 'already_looted');
    // 체력이 가득하면 먹지 않는다.
    const slot = inv.slots.findIndex((s) => s && S.heal[s.id]);
    if (slot >= 0) assert.equal((await ask(c, { t: 'use', slot })).code, 'hp_full');
  });

  it('밤: 사람 둘레에 크리처가 나타나 쫓아와 때리고, 맞서 쓰러뜨리면 아이템이 떨어진다', async () => {
    const { server, c, w } = await start(23, { creatureSpawnScale: 0.01, startItems: 'bandage:3' });
    assert.equal(w.surv.night, true);
    // 둔치 (광장 · 대피소에서 멀리).
    await moveTo(c, -150, 140);
    const m = await c.next((x) => x.t === 'creatures' && x.c.length >= 1, 4000);
    const z = m.c[0];
    // v0.28.2 종류가 늘어 random 0.5 로는 달리미가 뽑힌다 (가중치 순서).
    assert.equal(z.k, 'runner');
    // 크리처가 다가와 때린다.
    const hurt = await c.next((x) => x.t === 'hurt', 30000);
    assert.ok(hurt.hp < hurt.max, `체력 ${hurt.hp}`);
    // 붕대로 회복.
    const inv = await c.next((x) => x.t === 'inventory' || x.t === 'hurt', 10).catch(() => null);
    void inv;
    const room = [...server.rooms.rooms.values()][0];
    const me = [...room.players.values()][0];
    const bandage = me.slots.findIndex((s) => s?.id === 'bandage');
    const healed = await ask(c, { t: 'use', slot: bandage });
    assert.equal(healed.t, 'hp');
    assert.ok(healed.hp > hurt.hp || healed.hp === healed.max);
    // 맨손으로 계속 때려 쓰러뜨린다 (달리미 체력 3).
    let dead = null;
    for (let i = 0; i < 20 && !dead; i++) {
      const target = [...room.creatures.values()].sort((a, b) => Math.hypot(a.x - me.x, a.z - me.z) - Math.hypot(b.x - me.x, b.z - me.z))[0];
      if (target) await moveTo(c, target.x + 0.6, target.z);
      await ask(c, { t: 'attack' }).catch(() => null);
      dead = c.inbox.find((x) => x.t === 'creature_dead' && x.by === me.id) ?? null;
      await sleep(700);
    }
    assert.ok(dead, '쓰러뜨렸다');
    // v0.28 마석(헌터)은 따로 떨어진다 — 크리처 drops 표의 것만 본다.
    const drop = await c.next((x) => x.t === 'drop' && !x.d.item?.startsWith('mana_') && Math.hypot(x.d.x - dead.x, x.d.z - dead.z) < 2, 2000);
    // v0.28.2 크리처 종류가 늘었다 — 어느 종류의 drops 표에든 있는 것.
    assert.ok(Object.values(S.creatures.kinds).some((k) => k.drops.some((e) => e.id === drop.d.item)), drop.d.item);
  });

  it('체력이 0 이 되면 기절: 대피소에서 깨어나고 솔을 조금 잃는다', async () => {
    const { server, c } = await start(23, { creatureSpawnScale: 0.01, startSol: 1000000 });
    await moveTo(c, -150, 140);
    const room = [...server.rooms.rooms.values()][0];
    const me = [...room.players.values()][0];
    me.profile.hp = 1;
    const ko = await c.next((x) => x.t === 'ko', 30000);
    assert.equal(ko.hp, ko.max, '깨어나면 체력 가득');
    assert.equal(ko.lost, 30000, '3% (최대 30만)');
    const shelter = data.safety.drill.shelter;
    assert.ok(Math.hypot(ko.x - shelter.x, ko.z - shelter.z) < 3, '대피소');
    assert.equal(me.profile.sol, 970000);
  });
});
