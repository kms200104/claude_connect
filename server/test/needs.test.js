// v0.28.7 배고픔 · 목마름: 시간이 지나면 준다, 바닥나면 체력이 돌아오지 않고 조금씩 잃는다, 먹고 마시면 채운다.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const NE = data.survival.needs;

describe('v0.28.7 배고픔 · 목마름', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  async function setup(extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-needs-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, gateFirstMs: 99999999, startItems: 'canned_food:2,clean_water:1', ...extra });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    const room = [...server.rooms.rooms.values()][0];
    return { c, w, room, me: [...room.players.values()][0] };
  }
  const ask = async (c, msg) => {
    const rid = `nd-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, 3000);
  };
  const slotOf = (me, id) => me.slots.findIndex((x) => x?.id === id);

  it('처음엔 가득, 시간이 지나면 준다 (welcome · needs)', async () => {
    const { c, w } = await setup({ worldTimeScale: 3600 });
    assert.deepEqual([w.surv.needs.food, w.surv.needs.water], [NE.max, NE.max]);
    const m = await c.next((x) => x.t === 'needs' && x.water < NE.max, 4000);
    assert.ok(m.water < NE.max && m.food <= NE.max);
    assert.ok(NE.max - m.water >= NE.max - m.food, '목이 더 빨리 마른다');
  });

  it('먹고 마시면 채운다, 가득하면 not_hungry', async () => {
    const { c, me } = await setup();
    assert.equal((await ask(c, { t: 'use', slot: slotOf(me, 'canned_food') })).code, 'not_hungry');
    me.profile.food = 20;
    me.profile.water = 30;
    const r = await ask(c, { t: 'use', slot: slotOf(me, 'canned_food') });
    assert.equal(r.food, NE.nourish.canned_food.food);
    assert.equal(Math.round(me.profile.food), 20 + NE.nourish.canned_food.food);
    await ask(c, { t: 'use', slot: slotOf(me, 'clean_water') });
    assert.equal(Math.round(me.profile.water), Math.min(NE.max, 30 + (NE.nourish.canned_food.water ?? 0) + NE.nourish.clean_water.water));
  });

  it('바닥나면 체력을 조금씩 잃는다 (굶주림)', async () => {
    const { c, me } = await setup({ worldTimeScale: 3600 });
    me.profile.food = 0;
    const hp0 = me.profile.hp;
    const h = await c.next((x) => x.t === 'hurt' && x.by === 'starve', (NE.starve_world_hours + 3) * 1000);
    assert.equal(h.hp, hp0 - 1);
  });
});
