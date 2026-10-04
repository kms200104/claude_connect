import { readFileSync } from 'node:fs';
import path from 'node:path';
import { inHours } from './clock.js';

/** data/ 아래 JSON 을 읽는다 (클라이언트와 같은 파일). 서로 참조하는 id 가 맞는지도 검사한다. */
export function loadGameData(dataDir, cfg) {
  const read = (rel) => JSON.parse(readFileSync(path.join(dataDir, rel), 'utf8'));
  const fish = new Map(read('fish/fish.json').fish.map((f) => [f.id, f]));
  const spots = new Map();
  for (const s of read('fish/spots.json').spots) {
    for (const id of s.fish) if (!fish.has(id)) throw new Error(`spot ${s.id}: unknown fish ${id}`);
    spots.set(s.id, s);
  }

  const itemsFile = read('items/items.json');
  const items = new Map(itemsFile.items.map((it) => [it.id, it]));
  for (const id of items.keys()) if (fish.has(id)) throw new Error(`item ${id} 가 물고기 id 와 겹침`);
  // 나무 종류별로 나오는 목재·소지품 가중치.
  const chopDrops = itemsFile.chop_drops;
  for (const [kind, drops] of Object.entries(chopDrops)) {
    for (const d of drops) if (!items.has(d.id)) throw new Error(`chop_drops.${kind}: unknown item ${d.id}`);
  }

  const treesFile = read('world/trees.json');
  const trees = new Map(treesFile.trees.map((t) => [t.id, t]));
  for (const t of trees.values()) if (!chopDrops[t.kind]) throw new Error(`tree ${t.id}: chop_drops 에 ${t.kind} 없음`);

  const shop = read('shop/shop.json');
  for (const lv of shop.levels) {
    for (const id of lv.stock) if (!items.get(id)?.buy) throw new Error(`shop level ${lv.level}: ${id} 에 buy 가격이 없음`);
  }

  const npcsFile = read('npcs/npcs.json');
  const npcs = new Map(npcsFile.npcs.map((n) => [n.id, n]));

  const quests = read('quests/quests.json');
  for (const t of quests.templates) if (t.item && !items.has(t.item)) throw new Error(`quest ${t.id}: unknown item ${t.item}`);

  const isFish = (id) => fish.has(id);
  const isKnown = (id) => fish.has(id) || items.has(id);
  const limitOf = (id) => (fish.has(id) ? cfg.inventoryStackSize : (items.get(id)?.stack ?? 1));
  const isTool = (id) => items.get(id)?.kind === 'tool';
  const kindOf = (id) => (fish.has(id) ? 'fish' : (items.get(id)?.kind ?? ''));
  // 상점에 팔 때 받는 기본 가격 (도구는 못 판다 → 0).
  const priceOf = (id) => (fish.has(id) ? fish.get(id).price ?? 0 : isTool(id) ? 0 : (items.get(id)?.price ?? 0));

  return {
    fish,
    spots,
    items,
    chopDrops,
    trees,
    treeRules: { chopRange: treesFile.chop_range, chopsToFell: treesFile.chops_to_fell },
    npcs,
    npcRules: { talkRange: npcsFile.talk_range, walkSpeed: npcsFile.walk_speed },
    quests,
    shop,
    kindOf,
    priceOf,
    isFish,
    isKnown,
    isTool,
    limitOf,
  };
}

/** 점과 낚시터 사각형 사이의 거리(안쪽이면 0). */
export function distanceToSpot(spot, x, z) {
  const dx = Math.max(Math.abs(x - spot.x) - spot.half_x, 0);
  const dz = Math.max(Math.abs(z - spot.z) - spot.half_z, 0);
  return Math.hypot(dx, dz);
}

/** 지금 시각·날씨에 이 낚시터에서 낚일 수 있는 물고기. */
export function availableFish(spot, fishById, hour, weather) {
  return spot.fish
    .map((id) => fishById.get(id))
    .filter((f) => inHours(f.hours, hour) && (!Array.isArray(f.weather) || f.weather.includes(weather)));
}

/** 가중치 뽑기. 시각·날씨 조건에 맞는 물고기가 없으면 낚시터 전체에서 뽑는다. */
export function pickFish(spot, fishById, random, hour = 12, weather = 'clear') {
  let pool = availableFish(spot, fishById, hour, weather);
  if (pool.length === 0) pool = spot.fish.map((id) => fishById.get(id));
  return pickWeighted(pool, (f) => f.weight, random);
}

export function pickWeighted(list, weightOf, random) {
  const total = list.reduce((sum, x) => sum + weightOf(x), 0);
  let r = random() * total;
  for (const x of list) {
    r -= weightOf(x);
    if (r < 0) return x;
  }
  return list[list.length - 1];
}
