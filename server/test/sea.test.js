// v0.12 바다 낚시 · 계절: 섬 둘레 바닷가 어디서나, 물고기는 계절(마을 날짜의 달)마다 다르다.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { SEASONS, seasonOf } from '../src/clock.js';
import { availableFish, distanceToSpot, loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { menuOf } from '../src/restaurant.js';
import { Client, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const sea = data.seaSpot;
/** 섬 가운데에서 +X 쪽, 해안선 안쪽 inset 미터. */
const coastPoint = (inset) => ({ x: data.layout.island.half - inset, z: 0 });

describe('계절', () => {
  it('달로 정한다: 3~5 봄 · 6~8 여름 · 9~11 가을 · 12~2 겨울', () => {
    const at = (m) => seasonOf(Date.UTC(2026, m - 1, 15, 12));
    assert.deepEqual([1, 3, 6, 9, 11, 12].map(at), ['winter', 'spring', 'summer', 'autumn', 'autumn', 'winter']);
  });

  it('제철 물고기만: 빙어는 여름에 없고 겨울에 있다', () => {
    const lake = data.spots.get('lake');
    const has = (season) => availableFish(lake, data.fish, 7, 'clear', season).some((f) => f.id === 'smelt');
    assert.equal(has('summer'), false);
    assert.equal(has('winter'), true);
    assert.equal(availableFish(lake, data.fish, 7, 'clear', null).some((f) => f.id === 'smelt'), true, '계절을 안 보면 예전 그대로');
  });

  it('어느 계절·시각에도 낚시터마다 낚을 물고기가 넉넉하다', () => {
    for (const season of SEASONS) {
      for (const spot of data.allSpots()) {
        for (const [hour, min] of [[12, 5], [2, 3]]) {
          const n = availableFish(spot, data.fish, hour, 'clear', season).length;
          assert.ok(n >= min, `${spot.id} ${season} ${hour}시: ${n}종`);
        }
      }
    }
  });
});

describe('제철 · 시간 메뉴', () => {
  it('제철 메뉴는 그 계절에만, 아침상은 아침에만, 야식은 자정을 넘겨서도', () => {
    const ids = (when) => menuOf(data.recipes, 5, when).map((r) => r.id);
    assert.ok(ids({ season: 'autumn', hour: 12 }).includes('gizzard_shad_grill'));
    assert.ok(!ids({ season: 'spring', hour: 12 }).includes('gizzard_shad_grill'));
    assert.ok(ids({ season: 'winter', hour: 7 }).includes('rockfish_breakfast'));
    assert.ok(!ids({ season: 'winter', hour: 13 }).includes('rockfish_breakfast'));
    assert.ok(ids({ season: 'summer', hour: 1 }).includes('conger_grill'));
    assert.ok(!ids({ season: 'summer', hour: 12 }).includes('conger_grill'));
    assert.ok(ids({}).includes('gizzard_shad_grill'), '계절·시각을 안 보면 모두');
  });

  it('제철 메뉴의 재료 물고기는 그 계절에 실제로 낚인다', () => {
    for (const r of data.recipes.filter((x) => x.seasons)) {
      for (const ing of r.ingredients.filter((i) => i.item_any)) {
        for (const season of r.seasons) {
          const ok = ing.item_any.some((id) => {
            const f = data.fish.get(id);
            return !f || !f.seasons || f.seasons.includes(season);
          });
          assert.ok(ok, `${r.id} ${season}`);
        }
      }
    }
  });
});

describe('바다 낚시', () => {
  let saveDir;
  let server;
  const clients = [];
  before(() => {
    saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-sea-'));
    server = createServer({ port: 0, saveDir, random: () => 0, weatherForce: 'clear', seasonForce: 'winter', fishTimeScale: 0.01 });
  });
  after(async () => {
    for (const c of clients) c.kill();
    await server.close();
    rmSync(saveDir, { recursive: true, force: true });
  });

  it('해안선까지의 거리로 판정한다', () => {
    assert.ok(distanceToSpot(sea, 0, 0) > 90);
    assert.ok(Math.abs(distanceToSpot(sea, coastPoint(2).x, 0) - 2) < 1e-6);
    assert.equal(distanceToSpot(sea, coastPoint(-3).x, 0), 0);
  });

  it('바닷가 젖은 모래에서 던지면 제철 바다 물고기가 문다, 섬 안쪽에서는 못 던진다', async () => {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    assert.equal(w.clock.se, 'winter');
    const room = [...server.rooms.rooms.values()].find((r) => r.code === w.code);
    const player = [...room.players.values()].find((p) => p.id === w.id);
    Object.assign(player, coastPoint(20));
    c.send({ t: 'fish_cast', rid: 'c1', spot: 'sea' });
    assert.equal((await c.type('error')).code, 'not_at_spot');
    Object.assign(player, coastPoint(2));
    c.send({ t: 'fish_cast', rid: 'c2', spot: 'sea' });
    await c.type('fish_started');
    const fish = player.fishing.fish;
    assert.ok(sea.fish.includes(fish.id), fish.id);
    assert.ok(!fish.seasons || fish.seasons.includes('winter'), `${fish.id} 는 겨울 물고기`);
  });
});
