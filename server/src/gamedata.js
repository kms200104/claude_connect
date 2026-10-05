import { readFileSync } from 'node:fs';
import path from 'node:path';
import { inHours } from './clock.js';
import { blockedAreas } from './world.js';
import { loadFace } from './face.js';
import { listUnits } from './realestate.js';
import { loadPlans, planIdOf } from './homes.js';

/** data/ 아래 JSON 을 읽는다 (클라이언트와 같은 파일). 서로 참조하는 id 가 맞는지도 검사한다. */
export function loadGameData(dataDir, cfg) {
  const read = (rel) => JSON.parse(readFileSync(path.join(dataDir, rel), 'utf8'));
  const fish = new Map(read('fish/fish.json').fish.map((f) => [f.id, f]));
  const spots = new Map();
  for (const s of read('fish/spots.json').spots) {
    for (const id of s.fish) if (!fish.has(id)) throw new Error(`spot ${s.id}: unknown fish ${id}`);
    // 여울(얕은 물, v0.9): 수역 안쪽 사각형. 들어가서 뜰채로 물고기를 몬다.
    for (const z of s.shallows ?? []) {
      if (Math.abs(z.x - s.x) + z.half_x > s.half_x + 1e-6 || Math.abs(z.z - s.z) + z.half_z > s.half_z + 1e-6) throw new Error(`spot ${s.id}: shallow ${z.id} 가 수역 밖`);
      for (const id of z.fish) if (!fish.has(id)) throw new Error(`shallow ${z.id}: unknown fish ${id}`);
    }
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

  const events = read('events/events.json');
  for (const ev of [...events.daily, ...events.night]) {
    for (const id of ev.stock ?? []) if (!items.get(id)?.buy) throw new Error(`event ${ev.id}: ${id} 에 buy 가격이 없음`);
    for (const p of ev.pool ?? []) if (!items.has(p.id)) throw new Error(`event ${ev.id}: unknown item ${p.id}`);
    if (ev.item && !items.has(ev.item)) throw new Error(`event ${ev.id}: unknown item ${ev.item}`);
  }
  let layout = null;
  try {
    layout = read('world/village_layout.json');
  } catch {
    layout = null; // 꾸밈 배치는 없어도 된다 (선물이 바위 위에 떨어질 수 있을 뿐)
  }

  const quests = read('quests/quests.json');
  for (const t of quests.templates) if (t.item && !items.has(t.item)) throw new Error(`quest ${t.id}: unknown item ${t.item}`);

  // 씨앗 심기·꽃
  const plants = read('plants/plants.json');
  const flowerDefs = new Map(plants.flowers.map((f) => [f.id, f]));
  for (const f of flowerDefs.values()) if (!items.has(f.item)) throw new Error(`flower ${f.id}: unknown item ${f.item}`);
  const treeKinds = Object.keys(chopDrops);
  /** 씨앗 아이템 → { tree: 나무 종류 } | { flower: 꽃 종류 } */
  const seedOf = (id) => {
    const plant = items.get(id)?.plant;
    if (!plant) return null;
    if (plant.tree && treeKinds.includes(plant.tree)) return { tree: plant.tree };
    if (plant.flower && flowerDefs.has(plant.flower)) return { flower: plant.flower };
    return null;
  };
  for (const it of items.values()) if (it.plant && !seedOf(it.id)) throw new Error(`item ${it.id}: plant 대상을 모름`);

  // 감정표현
  const emotes = read('emotes/emotes.json');
  // 주민 MBTI (T/F 공감 방식, E/I 반응 거리)
  const mbti = read('npcs/mbti.json');
  for (const n of npcs.values()) if (n.mbti && !mbti.types[n.mbti]) throw new Error(`npc ${n.id}: unknown mbti ${n.mbti}`);
  const emoteIds = new Set(emotes.emotes.map((e) => e.id));
  for (const n of npcs.values()) {
    for (const [e] of n.teaches ?? []) if (!emoteIds.has(e)) throw new Error(`npc ${n.id}: unknown emote ${e}`);
    for (const g of n.gifts ?? []) if (!items.has(g)) throw new Error(`npc ${n.id}: unknown gift ${g}`);
  }
  for (const [p, table] of Object.entries(emotes.reactions)) {
    for (const list of Object.values(table)) for (const e of list) if (!emoteIds.has(e)) throw new Error(`emote reaction ${p}: unknown ${e}`);
  }

  // 박물관 · 공항
  const museum = read('places/museum.json');
  for (const m of museum.milestones) if (!items.has(m.item)) throw new Error(`museum milestone: unknown item ${m.item}`);
  const airport = read('places/airport.json');
  for (const id of airport.stock) if (!items.get(id)?.buy) throw new Error(`airport: ${id} 에 buy 가격이 없음`);

  // 얼굴 꾸미기 · 거울
  const face = loadFace(read('looks/face_parts.json'));
  const mirrors = (layout?.mirrors ?? []).filter((m) => Number.isFinite(m.x) && Number.isFinite(m.z));

  // 경제: 증권시장 · 아파트 · 은행
  const market = read('market/stocks.json');
  const realestate = read('realestate/apartments.json');
  const units = listUnits(realestate);
  for (const u of units) if (!realestate.types[u.type]) throw new Error(`apartment ${u.id}: unknown type ${u.type}`);
  const bank = read('bank/bank.json');
  // 집 안 (v0.10): 평면도 · 집 안 자리 · 처음 놓이는 가구.
  const floorplans = read('realestate/floorplans.json');
  const plans = loadPlans(floorplans);
  for (const u of units) if (!plans.has(planIdOf(realestate, u))) throw new Error(`apartment ${u.id}: unknown plan ${planIdOf(realestate, u)}`);
  for (const p of plans.values()) {
    for (const d of p.defaults) if (items.get(d.item)?.kind !== 'furniture') throw new Error(`plan ${p.id}: ${d.item} is not furniture`);
  }

  // 마을톡 (v0.11)
  const messenger = read('messenger/messenger.json');

  // 식당: 요리 · 동작 · 손님
  const recipesFile = read('restaurant/recipes.json');
  const restaurant = read('restaurant/restaurant.json');
  const recipes = recipesFile.recipes;
  const cookSteps = recipesFile.steps;
  for (const r of recipes) {
    for (const s of r.steps) if (!cookSteps[s]) throw new Error(`recipe ${r.id}: unknown step ${s}`);
    for (const ing of r.ingredients) {
      if (ing.item && !items.has(ing.item)) throw new Error(`recipe ${r.id}: unknown item ${ing.item}`);
      for (const id of ing.item_any ?? []) if (!fish.has(id) && !items.has(id)) throw new Error(`recipe ${r.id}: unknown ${id}`);
    }
  }
  for (const f of restaurant.forage.items) if (!items.has(f.id)) throw new Error(`forage: unknown item ${f.id}`);

  // 동사무소 (v0.9) · 삽
  const civic = read('civic/civic.json');
  const programs = new Map(civic.programs.map((p) => [p.id, p]));
  const dig = read('world/dig.json');
  for (const list of [dig.beach.items, dig.lake.items, dig.hole_finds.items]) for (const it of list) if (!items.has(it.id)) throw new Error(`dig: unknown item ${it.id}`);
  // 손님: 주민(취향은 restaurant.json 의 tastes) + 지나가는 손님(visitors).
  const customers = new Map();
  for (const n of npcs.values()) customers.set(n.id, { id: n.id, name: n.name, mbti: n.mbti ?? '', villager: true, ...(restaurant.tastes[n.id] ?? { likes: [], dislikes: [] }) });
  for (const v of restaurant.visitors) customers.set(v.id, { ...v, villager: false });

  const isFish = (id) => fish.has(id);
  const isKnown = (id) => fish.has(id) || items.has(id);
  const limitOf = (id) => (fish.has(id) ? cfg.inventoryStackSize : (items.get(id)?.stack ?? 1));
  const isTool = (id) => items.get(id)?.kind === 'tool';
  const kindOf = (id) => (fish.has(id) ? 'fish' : (items.get(id)?.kind ?? ''));
  // 상점에 팔 때 받는 기본 가격 (도구는 못 판다 → 0).
  const priceOf = (id) => (fish.has(id) ? fish.get(id).price ?? 0 : isTool(id) ? 0 : (items.get(id)?.price ?? 0));

  const data = {
    fish,
    spots,
    items,
    chopDrops,
    trees,
    treeRules: { chopRange: treesFile.chop_range, chopsToFell: treesFile.chops_to_fell, regrowMinutes: treesFile.regrow_minutes ?? {} },
    npcs,
    npcRules: {
      talkRange: npcsFile.talk_range,
      walkSpeed: npcsFile.walk_speed,
      gift: npcsFile.gift_rules ?? { min_friendship: 12, chance: 0.45, cooldown_days: 1 },
      topicFriendPerDay: npcsFile.topic_friend_per_day ?? 3,
      talkExtraFriend: npcsFile.talk_extra_friend ?? 1,
      approach: npcsFile.approach ?? null,
    },
    quests,
    shop,
    events,
    layout,
    plants,
    flowerDefs,
    treeKinds,
    seedOf,
    emotes,
    emoteIds,
    mbti,
    museum,
    airport,
    face,
    mirrors,
    market,
    realestate,
    units,
    floorplans,
    plans,
    planOf: (unit) => plans.get(planIdOf(realestate, unit)) ?? null,
    bank,
    recipes,
    recipeById: new Map(recipes.map((r) => [r.id, r])),
    cookSteps,
    restaurant,
    messenger,
    customers,
    civic,
    programs,
    dig,
    kindOf,
    priceOf,
    isFish,
    isKnown,
    isTool,
    limitOf,
  };
  data.blocked = blockedAreas(data);
  return data;
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
export function pickFish(spot, fishById, random, hour = 12, weather = 'clear', weightOf = (f) => f.weight) {
  let pool = availableFish(spot, fishById, hour, weather);
  if (pool.length === 0) pool = spot.fish.map((id) => fishById.get(id));
  return pickWeighted(pool, weightOf, random);
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
