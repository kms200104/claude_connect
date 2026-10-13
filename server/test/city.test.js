// v0.21 탕정 제2지구 강변도시: 강 건너 · 도시 끝 · 갯벌 조개 · 도시 건물 · 긴 강 물고기.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { distanceToSpot, loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { groundProblem, islandShape, onIsland } from '../src/world.js';
import { isLand, waterAt } from '../src/water.js';
import { Client, riverNorthZ, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

describe('v0.21 강변도시 땅', () => {
  it('south 줄 너머(곡교천 한가운데 · 강 건너)는 땅이 아니고, 도시 밖 실내는 실내로 남는다', () => {
    const island = data.layout.island;
    assert.ok(islandShape(island, 0, island.south - 1) < 1);
    assert.ok(islandShape(island, 0, island.south + 30) > 1, '강 건너');
    assert.ok(islandShape(island, 0, data.shop.interior.z) > 1.06, '상점 실내는 도시 밖 멀리');
    assert.ok(!onIsland(island, -100, 250) && !isLand(data, -100, 250), '침수 구시가지에는 내리지 않는다');
    assert.equal(groundProblem(data, -100, 250), 'edge');
  });

  it('곡교천: 보 위는 상류(seongseong) · 아래는 하류(sea), 둘 다 긴 강 (물가에 선 사람 둘레에만 물고기)', () => {
    const weir = data.city.weir.x;
    assert.equal(waterAt(data, weir - 20, 189), 'seongseong');
    assert.equal(waterAt(data, weir + 20, 189), 'sea');
    assert.equal(data.seaSpot, null, '섬 둘레 바다 띠는 없다');
    assert.ok(data.spots.get('seongseong').near_people && data.spots.get('sea').near_people);
  });

  it('도시 건물 · 리버파크 시설 자리는 놓기 · 심기 금지, 도로 가운데는 열려 있다', () => {
    for (const b of data.city.buildings.filter((x) => x.kind !== 'flooded').slice(0, 30)) {
      assert.equal(groundProblem(data, b.x, b.z), 'building', `${b.id} ${b.kind}`);
    }
    for (const f of data.realestate.estate.facilities) assert.equal(groundProblem(data, f.x, f.z), 'building', f.id);
    assert.equal(groundProblem(data, 30, 104), null, '강변로');
  });
});

describe('v0.21 갯벌 조개 · 강 물고기', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });

  it('조개 숨구멍(beach)은 곡교천 하류 북쪽 갯벌에만 돋는다 (도시 끝 · 강 건너 아님)', async () => {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-city-'));
    dirs.push(saveDir);
    const server = createServer({ port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', eventSpawnScale: 0.001 });
    servers.push(server);
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send({ t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    await c.type('welcome');
    const sea = data.spots.get('sea');
    const seen = [];
    while (seen.length < 3) {
      const m = await c.next((x) => x.t === 'digspot' && x.d.kind === 'beach', 8000);
      seen.push(m.d);
    }
    for (const d of seen) {
      assert.ok(distanceToSpot(sea, d.x, d.z) < 4, `하류 물가 (${d.x}, ${d.z})`);
      assert.ok(d.z < riverNorthZ(data, d.x) + 0.5, '도시 쪽 (북쪽) 물가');
      assert.ok(onIsland(data.layout.island, d.x, d.z), '도시 땅');
    }
  });
});
