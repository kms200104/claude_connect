// 제작 (v0.22, 서버 권위): 작업대 곁에서 재료를 써서 생존용품을 만든다. data/crafting/crafting.json.
//   등급(tier): 0 = 맨손(어디서나), 1 = 작업대(마을에 놓은 내 · 친구 작업대 곁, 또는 작업대를 둔 집 안), 2 = 공용 작업대(공구 창고).
//   클라이언트가 보내는 건 { t: 'craft', rid, recipe, n } 요청뿐 — 작업대 거리 · 재료 · 가방 자리는 서버가 본다.
import { ErrorCode } from './protocol.js';
import { addItem, canAdd, countWhere, removeWhere } from './inventory.js';

export const MAX_BATCH = 10;

/** crafting.json 을 읽어 검사한다 (모르는 아이템이면 서버를 켜지 않는다). */
export function loadCrafting(raw, isKnown) {
  if (!raw) return null;
  const recipes = new Map();
  for (const r of raw.recipes ?? []) {
    if (!isKnown(r.out)) throw new Error(`recipe ${r.id}: unknown out ${r.out}`);
    if (!Number.isInteger(r.n) || r.n < 1) throw new Error(`recipe ${r.id}: bad n`);
    for (const need of r.needs ?? []) if (!isKnown(need.item) || !Number.isInteger(need.n) || need.n < 1) throw new Error(`recipe ${r.id}: bad need ${need.item}`);
    if (![0, 1, 2].includes(r.tier)) throw new Error(`recipe ${r.id}: bad tier`);
    recipes.set(r.id, r);
  }
  const benchItems = new Map(Object.entries(raw.bench_items ?? {}));
  for (const id of benchItems.keys()) if (!isKnown(id)) throw new Error(`bench item ${id} unknown`);
  return { range: raw.range ?? 2.6, publicBenches: raw.public_benches ?? [], benchItems, recipes, categories: raw.categories ?? [] };
}

/** 이 사람이 지금 쓸 수 있는 가장 높은 작업대 등급. */
export function benchTier(crafting, { x, z, inside = false, homeItems = null, placed = [] }) {
  let tier = 0;
  const near = (bx, bz) => Math.hypot(x - bx, z - bz) <= crafting.range;
  if (homeItems) {
    // 집 안: 그 집에 둔 작업대 (집 안 어디서나 — 작은 방이라 거리는 보지 않는다).
    for (const f of homeItems) tier = Math.max(tier, crafting.benchItems.get(f.item) ?? 0);
    return tier;
  }
  if (inside) return tier;
  for (const b of crafting.publicBenches) if (near(b.x, b.z)) tier = Math.max(tier, b.tier ?? 2);
  for (const f of placed) {
    const t = crafting.benchItems.get(f.item);
    if (t !== undefined && near(f.x, f.z)) tier = Math.max(tier, t);
  }
  return tier;
}

/** 재료가 충분하고, 재료를 뺀 뒤 만든 것이 가방에 들어가는지. 문제 코드 또는 null. */
export function craftProblem(slots, recipe, n, limitOf) {
  for (const need of recipe.needs) if (countWhere(slots, (id) => id === need.item) < need.n * n) return ErrorCode.notEnoughItems;
  const after = slots.map((s) => (s ? { ...s } : null));
  for (const need of recipe.needs) removeWhere(after, (id) => id === need.item, need.n * n);
  if (!canAdd(after, recipe.out, recipe.n * n, limitOf)) return ErrorCode.inventoryFull;
  return null;
}

export function createCrafting({ data, cfg, send, sendInventory, inShop, homeItemsOf, act }) {
  const crafting = data.crafting;

  function tierOf(room, player) {
    return benchTier(crafting, {
      x: player.x,
      z: player.z,
      inside: inShop(player),
      homeItems: player.home ? homeItemsOf(room, player.home) : null,
      placed: [...room.placed.values()],
    });
  }

  function handleCraft(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const recipe = crafting?.recipes.get(msg.recipe);
    if (!recipe) return fail(ErrorCode.badItem);
    // v0.28.9 직업 전용 (그 직업으로 전직한 사람만).
    if (recipe.job && player.profile.hunter?.job !== recipe.job) return fail(ErrorCode.jobOnly);
    const n = Number.isInteger(msg.n) ? msg.n : 1;
    if (n < 1 || n > MAX_BATCH) return fail(ErrorCode.badItem);
    const tier = tierOf(room, player);
    if (recipe.tier > tier) return fail(ErrorCode.notAtBench);
    const problem = craftProblem(player.slots, recipe, n, data.limitOf);
    if (problem) return fail(problem);
    for (const need of recipe.needs) removeWhere(player.slots, (id) => id === need.item, need.n * n);
    addItem(player.slots, recipe.out, recipe.n * n, cfg, data.limitOf);
    sendInventory(player);
    send(ctx.ws, { t: 'crafted', rid: msg.rid, recipe: recipe.id, item: recipe.out, n: recipe.n * n, tier });
    act?.(room, player, 'craft', recipe.out);
  }

  return { handleCraft, tierOf };
}
