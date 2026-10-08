// v18 탈것 (접이식 킥보드): 가방에 있어야 탄다, 친구에게 타고 있는 모습이 보인다, 가방에서 빠지면 내린다.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';
import { addItem } from '../src/inventory.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { chooseActivity, createNpcRuntime, npcWire, stepNpcs } from '../src/npcs.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

describe('탈것은 퀵슬롯에 먼저 (v0.16)', () => {
  it('킥보드는 빈 퀵슬롯으로, 다른 물건은 가방 칸으로', () => {
    const slots = Array.from({ length: 20 }, () => null);
    slots[0] = { id: 'rod', n: 1 };
    slots[1] = { id: 'axe', n: 1 };
    const cfg = { quickSlots: 5 };
    assert.ok(addItem(slots, 'wood', 1, cfg, data.limitOf));
    assert.ok(addItem(slots, 'kickboard', 1, cfg, data.limitOf));
    assert.equal(slots[2]?.id, 'kickboard');
    assert.equal(slots[5]?.id, 'wood');
  });
});

describe('주민 몸짓 (v0.16)', () => {
  const rules = data.npcRules.activities;
  it('맑은 낮 · 물가 조건에 맞는 몸짓만 고르고, 비 · 밤(home)에는 안 한다', () => {
    const n = { x: 0, z: 0 };
    const seen = new Set();
    let i = 0;
    const random = () => ((i++ * 0.6180339) % 1);
    for (let k = 0; k < 200; k++) {
      const a = chooseActivity(n, rules, { random, mode: 'roam', sunny: false, waterNear: () => null });
      if (a) seen.add(a.id);
    }
    assert.ok(seen.has('stretch') && seen.has('sit') && seen.has('warmup'));
    assert.ok(!seen.has('sun') && !seen.has('fish'), '흐린 날 · 물에서 먼 곳');
    assert.equal(chooseActivity(n, rules, { random: () => 0, mode: 'home', sunny: true, waterNear: () => null }), null);
    const fish = chooseActivity({ x: 0, z: 0 }, { chance: 1, list: rules.list.filter((a) => a.id === 'fish') }, { random: () => 0.5, mode: 'roam', sunny: true, waterNear: () => ({ x: 3, z: 0 }) });
    assert.equal(fish.id, 'fish');
    assert.ok(Math.abs(fish.yaw - Math.atan2(-3, 0)) < 1e-9, '물 쪽을 본다');
  });

  it('길목에 닿으면 몸짓을 하며 머물고, 다시 걸을 때 그만둔다 (방송에 a)', () => {
    const npcs = createNpcRuntime(data.npcs, 0, () => 0.5);
    const n = npcs.get('morak');
    n.target = { x: n.x + 0.01, z: n.z };
    const pick = () => ({ id: 'sit', ms: 10000 });
    stepNpcs(npcs, { dtMs: 100, now: 1000, random: () => 0.5, mode: 'roam', speed: 1.4, idleMinMs: 1000, idleMaxMs: 2000, pickActivity: pick });
    assert.equal(n.act, 'sit');
    assert.equal(npcWire(n).a, 'sit');
    assert.equal(n.waitUntil, 11000);
    stepNpcs(npcs, { dtMs: 100, now: 11001, random: () => 0.5, mode: 'roam', speed: 1.4, idleMinMs: 1000, idleMaxMs: 2000, pickActivity: () => null });
    assert.equal(n.act, null);
    assert.equal(npcWire(n).a, '');
  });
});

describe('탈것', () => {
  let saveDir;
  let server;
  const clients = [];
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-ride-'));
    server = createServer({ port: 0, saveDir, random: () => 0.1, weatherForce: 'clear' });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });
  async function enter(code = null) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    const room = [...server.rooms.rooms.values()].find((r) => r.code === w.code);
    const player = [...room.players.values()].find((p) => p.id === w.id);
    return { c, room, player, code: w.code };
  }

  it('킥보드가 가방에 없으면 못 타고, 있으면 타서 모두에게 보이며, 가방에서 빠지면 내린 것으로', async () => {
    const { c, player, code } = await enter();
    const friend = await enter(code);
    c.send({ t: 'ride', on: true, item: 'kickboard' });
    await sleep(80);
    assert.equal(player.toWire().ride, '', '가방에 없으면 못 탄다');
    c.send({ t: 'ride', on: true, item: 'rod' });
    await sleep(80);
    assert.equal(player.toWire().ride, '', '탈것이 아닌 아이템');
    const free = player.profile.slots.findIndex((s) => !s);
    player.profile.slots[free] = { id: 'kickboard', n: 1 };
    c.send({ t: 'ride', on: true, item: 'kickboard' });
    const seen = await friend.c.next((m) => m.t === 'snap' && m.p?.some((p) => p.id === player.id && p.ride === 'kickboard'), 2000);
    assert.ok(seen, '친구 스냅샷에 타고 있는 모습');
    player.profile.slots[free] = null;
    assert.equal(player.toWire().ride, '', '가방에서 빠지면 내린 것으로');
    player.profile.slots[free] = { id: 'kickboard', n: 1 };
    c.send({ t: 'ride', on: false });
    await sleep(80);
    assert.equal(player.toWire().ride, '');
  });
});
