// v18 탈것 (접이식 킥보드): 가방에 있어야 탄다, 친구에게 타고 있는 모습이 보인다, 가방에서 빠지면 내린다.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { Client, sleep, uid } from './helpers.js';

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
