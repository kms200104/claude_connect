import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadGameData, distanceToSpot, nearestInSpot, nearSpot } from '../src/gamedata.js';
import { insideOutline, signedDistance } from '../src/outline.js';
import { shallowAt } from '../src/shoal.js';
import { lakeShoreSpot } from '../src/dig.js';

const dataDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../data');

test('다각형 안팎·부호 있는 거리', () => {
  const sq = [[0, 0], [4, 0], [4, 4], [0, 4]];
  assert.ok(insideOutline(sq, 2, 2));
  assert.ok(!insideOutline(sq, 5, 2));
  assert.ok(Math.abs(signedDistance(sq, 2, 1) + 1) < 1e-9);
  assert.ok(Math.abs(signedDistance(sq, 7, 2) - 3) < 1e-9);
});

test('성성호수 실제 윤곽: 거리·여울·호숫가', () => {
  const data = loadGameData(dataDir, {});
  const s = data.spots.get('seongseong');
  assert.ok(s.outline.length >= 100);
  // 윤곽 안 = 거리 0, 바깥 사각형 모서리(물 아님) = 0 보다 큼.
  const deep = { x: 10, z: 0 };
  assert.equal(distanceToSpot(s, deep.x, deep.z), 0);
  assert.ok(distanceToSpot(s, s.x - s.half_x, s.z - s.half_z) > 3);
  assert.ok(distanceToSpot(s, s.x + s.half_x + 40, s.z + s.half_z + 40) > 30);
  // 여울: 안쪽 점은 여울, 호수 가운데는 깊은 물, 호수 밖이라도 가장 가까운 물이 여울이면 여울.
  const ford = s.shallows.find((z) => z.id === 'seongseong_ford');
  assert.equal(shallowAt(s, ford.x, ford.z)?.id, 'seongseong_ford');
  assert.equal(shallowAt(s, deep.x, deep.z), null);
  const n = nearestInSpot(s, ford.x, s.z + s.half_z + 5);
  assert.ok(insideOutline(s.outline, n.x, n.z) || distanceToSpot(s, n.x, n.z) < 1e-6);
  // 호숫가 모래 자리는 항상 물 바깥, 가까이.
  let k = 0;
  const rnd = () => ((k = (k * 1103515245 + 12345) % 2147483648) / 2147483648);
  for (let i = 0; i < 200; i++) {
    const p = lakeShoreSpot(s, 1.6, rnd);
    const d = distanceToSpot(s, p.x, p.z);
    assert.ok(d > 0.2 && d < 2.4, `shore ${JSON.stringify(p)} d=${d}`);
  }
  assert.ok(nearSpot(s, deep.x, deep.z, 2));
});

test('성성호수공원: 방문자센터·정자 자리는 막힌다 (회전한 건물 사각형 포함)', async () => {
  const { groundProblem } = await import('../src/world.js');
  const data = loadGameData(dataDir, {});
  const v = data.layout.park.visitor_center;
  // yaw π/2: 앞면이 동쪽, 건물은 앞면에서 서쪽으로 depth 만큼.
  assert.equal(groundProblem(data, v.x - v.depth / 2, v.z), 'building');
  assert.equal(groundProblem(data, v.x - v.depth / 2, v.z + v.width / 2 - 0.5), 'building');
  assert.equal(groundProblem(data, v.x + 4, v.z), null); // 앞 광장은 열려 있다
  assert.equal(groundProblem(data, v.x - v.depth - 3, v.z), null);
  const p = data.layout.park.pavilion;
  assert.equal(groundProblem(data, p.x, p.z), 'building');
});
