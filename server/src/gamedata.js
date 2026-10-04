import { readFileSync } from 'node:fs';
import path from 'node:path';

/** data/fish/fish.json, spots.json 을 읽는다 (클라이언트와 같은 파일). */
export function loadGameData(dataDir) {
  const read = (rel) => JSON.parse(readFileSync(path.join(dataDir, rel), 'utf8'));
  const fish = new Map(read('fish/fish.json').fish.map((f) => [f.id, f]));
  const spots = new Map();
  for (const s of read('fish/spots.json').spots) {
    for (const id of s.fish) if (!fish.has(id)) throw new Error(`spot ${s.id}: unknown fish ${id}`);
    spots.set(s.id, s);
  }
  return { fish, spots };
}

/** 점과 낚시터 사각형 사이의 거리(안쪽이면 0). */
export function distanceToSpot(spot, x, z) {
  const dx = Math.max(Math.abs(x - spot.x) - spot.half_x, 0);
  const dz = Math.max(Math.abs(z - spot.z) - spot.half_z, 0);
  return Math.hypot(dx, dz);
}

export function pickFish(spot, fishById, random) {
  const pool = spot.fish.map((id) => fishById.get(id));
  const total = pool.reduce((sum, f) => sum + f.weight, 0);
  let r = random() * total;
  for (const f of pool) {
    r -= f.weight;
    if (r < 0) return f;
  }
  return pool[pool.length - 1];
}
