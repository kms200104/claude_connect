// 솔바람 식당 (서버 권위). 순수 함수만 — 소켓·방 상태는 server.js 가 다룬다.
// 흐름: 문을 연다 → 문을 연 사람 가방의 재료로 만들 수 있는 요리만 손님이 주문하고, 주문이 들어오는 순간 그 재료를 떼어 둔다
// (그래서 재료가 모자란 주문은 들어오지 않는다) → 요리(동작별 박자 맞추기) → 서버가 박자·맛·시간으로 별점과 값을 매긴다.
// 별점이 오르면 까다롭지만 남는 게 많은 요리가 열리고, 같은 요리에 만족한 손님은 단골이 되어 그것만 시킨다.

import { inHours } from './clock.js';

export const RARITY_RANK = { common: 0, uncommon: 1, rare: 2 };

/** 가방 칸 → 재료 개수 { id: n }. */
export function pantryOf(slots) {
  const out = {};
  for (const s of slots) if (s) out[s.id] = (out[s.id] ?? 0) + s.n;
  return out;
}

/**
 * 요리 하나에 쓸 재료를 avail 에서 고른다 (avail 은 바꾸지 않는다). 못 만들면 null.
 * item: 그 아이템, item_any: 목록 중 하나(앞에서부터), fish: 그 희귀도 이하 아무 물고기 — 값싼 것부터.
 */
export function pickIngredients(recipe, avail, data) {
  const left = { ...avail };
  const used = {};
  const take = (id, n) => {
    left[id] -= n;
    used[id] = (used[id] ?? 0) + n;
  };
  for (const ing of recipe.ingredients) {
    let need = ing.n;
    if (ing.item) {
      if ((left[ing.item] ?? 0) < need) return null;
      take(ing.item, need);
      continue;
    }
    const pool = ing.item_any
      ? ing.item_any
      : [...data.fish.values()]
          .filter((f) => RARITY_RANK[f.rarity] <= RARITY_RANK[ing.fish ?? 'common'])
          .sort((a, b) => a.price - b.price)
          .map((f) => f.id);
    for (const id of pool) {
      const n = Math.min(need, left[id] ?? 0);
      if (n > 0) {
        take(id, n);
        need -= n;
      }
      if (need === 0) break;
    }
    if (need > 0) return null;
  }
  return used;
}

/** 지금 재료로 한 그릇씩 몇 그릇까지 만들 수 있는지 (열린 메뉴, 욕심껏 비싼 것부터 — 표시용 예상치). */
export function capacity(menu, avail, data) {
  const left = { ...avail };
  let count = 0;
  const sorted = [...menu].sort((a, b) => b.price - a.price);
  for (let guard = 0; guard < 200; guard++) {
    const r = sorted.find((rec) => pickIngredients(rec, left, data));
    if (!r) break;
    for (const [id, n] of Object.entries(pickIngredients(r, left, data))) left[id] -= n;
    count += 1;
  }
  return count;
}

/** 별점(최근 window 개 평균, 처음엔 prior 로 기운다). */
export function ratingOf(rules, history) {
  const recent = history.slice(-rules.rating.window);
  const sum = recent.reduce((a, b) => a + b, 0) + rules.rating.prior * rules.rating.prior_weight;
  return Math.round((sum / (recent.length + rules.rating.prior_weight)) * 100) / 100;
}

/** 별점으로 열린 가장 높은 요리 단계 (1~5). */
export function tierOf(rules, rating) {
  let tier = 1;
  for (let t = 1; t < rules.tier_stars.length; t++) if (rating >= rules.tier_stars[t]) tier = t;
  return tier;
}

/**
 * 열린 메뉴: 별점 단계 안, 그리고 (v0.12) 제철 메뉴는 그 계절에만 · 시간 메뉴(아침상 · 야식)는 그 시간에만.
 * when = { season, hour } — 빠진 값은 보지 않는다.
 */
export function menuOf(recipes, tier, when = {}) {
  return recipes.filter(
    (r) =>
      r.tier <= tier &&
      (!when.season || !Array.isArray(r.seasons) || r.seasons.includes(when.season)) &&
      (when.hour === undefined || inHours(r.hours, when.hour)),
  );
}

/** 손님 취향과 요리의 맞음 (0~1). 좋아하는 맛 하나에 +, 싫어하는 맛 하나에 −. */
export function tasteMatch(taste, recipe) {
  const likes = recipe.tags.filter((t) => taste.likes?.includes(t)).length;
  const dislikes = recipe.tags.filter((t) => taste.dislikes?.includes(t)).length;
  return Math.max(0, Math.min(1, 0.45 + 0.25 * likes - 0.4 * dislikes));
}

/**
 * 손님이 무엇을 시킬지. 단골이면 그 요리(재료가 있을 때만), 아니면 열린 메뉴 중 재료가 있는 것을 취향 무게로.
 * 돌려주는 값: { recipe, used } 또는 null (시킬 게 없다).
 */
export function chooseOrder({ menu, avail, data, taste, regularDish, random, seasonWeight = 1 }) {
  if (regularDish) {
    const r = menu.find((m) => m.id === regularDish);
    const used = r ? pickIngredients(r, avail, data) : null;
    return used ? { recipe: r, used, regular: true } : null;
  }
  const options = [];
  for (const r of menu) {
    const used = pickIngredients(r, avail, data);
    if (!used) continue;
    // 좋아하는 맛일수록, 높은 단계일수록 조금 더 자주 시킨다.
    // 제철 메뉴(v0.12)는 그 계절에만 메뉴에 오르고, 오르면 더 자주 시킨다.
    const seasonal = Array.isArray(r.seasons) ? seasonWeight : 1;
    options.push({ recipe: r, used, w: Math.max(0.05, tasteMatch(taste, r) ** 2) * (1 + 0.15 * (r.tier - 1)) * seasonal });
  }
  if (options.length === 0) return null;
  let roll = random() * options.reduce((a, o) => a + o.w, 0);
  for (const o of options) {
    roll -= o.w;
    if (roll <= 0) return { recipe: o.recipe, used: o.used, regular: false };
  }
  const last = options[options.length - 1];
  return { recipe: last.recipe, used: last.used, regular: false };
}

/** 요리에 걸리는 가장 짧은 시간 (ms) — 이보다 빨리 낸 요리는 받지 않는다. */
/** 동작 하나를 하는 데 걸리는 가장 짧은 시간 (ms). 이보다 빨리 낸 동작은 받지 않는다. */
export function stepMinMs(step) {
  if (step.kind === 'beats') return step.beats * step.interval_ms - step.window_ms;
  if (step.kind === 'timing') return step.ideal_ms - step.window_ms * 2;
  if (step.kind === 'grill') return step.sides * (step.side_ms - step.window_ms * 2);
  if (step.kind === 'steam') return step.fill_ms * 0.5 + step.steam_ms - step.window_ms * 2;
  return step.duration_ms * 0.5;
}

export function minCookMs(recipe, steps) {
  let ms = 0;
  for (const id of recipe.steps) ms += stepMinMs(steps[id]);
  return Math.max(0, ms);
}

/**
 * 동작 하나의 솜씨 (0~1). taps = 그 동작을 시작하고 누른 시각들 (ms).
 *  beats: 박자마다 가장 가까운 누름과의 차이 / timing: 한 번 누른 시각과 딱 좋은 때의 차이 / mash: 시간 안에 누른 횟수.
 *  grill (v0.11): 면마다 노릇해졌을 때 뒤집기·꺼내기 — 누름 간격(한 면을 구운 시간)과 side_ms 의 차이.
 *  steam (v0.11): 재료 items 번 넣기 → 물 붓기 시작·멈춤(물 높이 = 부은 시간 / fill_ms, 선에 맞추기) → 뚜껑 열기(찐 시간과 steam_ms 의 차이).
 */
export function timingScore(off, window) {
  if (off <= window) return 1 - 0.3 * (off / window);
  return Math.max(0, 0.7 - 0.7 * ((off - window) / (window * 2)));
}

export function stepQuality(step, taps) {
  const t = Array.isArray(taps) ? taps.filter((x) => Number.isFinite(x) && x >= 0 && x < 20000).sort((a, b) => a - b) : [];
  if (step.kind === 'beats') {
    let total = 0;
    for (let i = 1; i <= step.beats; i++) {
      const ideal = i * step.interval_ms;
      const off = t.length ? Math.min(...t.map((x) => Math.abs(x - ideal))) : Infinity;
      total += Math.max(0, 1 - off / (step.window_ms * 2));
    }
    const extra = Math.max(0, t.length - step.beats) * 0.05;
    return Math.max(0, total / step.beats - extra);
  }
  if (step.kind === 'timing') {
    if (t.length === 0) return 0;
    return timingScore(Math.abs(t[0] - step.ideal_ms), step.window_ms);
  }
  if (step.kind === 'grill') {
    let total = 0;
    for (let k = 0; k < step.sides; k++) {
      if (k >= t.length) break;
      total += timingScore(Math.abs(t[k] - (k === 0 ? 0 : t[k - 1]) - step.side_ms), step.window_ms);
    }
    // 더 누른 건(뒤집개를 마구 휘두름) 조금 깎는다.
    return Math.max(0, total / step.sides - Math.max(0, t.length - step.sides) * 0.1);
  }
  if (step.kind === 'steam') {
    const n = step.items;
    const items = Math.min(t.length, n) / n;
    if (t.length < n + 3) return items / 3;
    const level = (t[n + 1] - t[n]) / step.fill_ms;
    const water = timingScore(Math.abs(level - 1), step.water_window);
    const steamed = timingScore(Math.abs(t[n + 2] - t[n + 1] - step.steam_ms), step.window_ms);
    return (items + water + steamed) / 3;
  }
  // mash: 50ms 보다 촘촘한 누름(자동 연타)은 세지 않는다.
  let count = 0;
  let last = -Infinity;
  for (const x of t) {
    if (x > step.duration_ms) break;
    if (x - last >= 50) {
      count += 1;
      last = x;
    }
  }
  return Math.min(1, count / step.taps);
}

/** 요리 전체 솜씨 = 동작 솜씨 평균. stepTaps[i] = i 번째 동작의 누름 시각들. */
export function cookQuality(recipe, steps, stepTaps) {
  if (!Array.isArray(stepTaps)) return 0;
  const q = recipe.steps.map((id, i) => stepQuality(steps[id], stepTaps[i]));
  return q.reduce((a, b) => a + b, 0) / q.length;
}

/**
 * 손님 별점 (1~5). quality(솜씨) · taste(취향) · timeLeft(남은 기다림 비율 0~1).
 * MBTI: F 손님은 늦어도 너그럽고(time_floor), T 손님은 솜씨를 깐깐하게 본다(quality_power).
 */
export function starsFor(rules, { quality, taste, timeLeft, mbti }) {
  const style = rules.mbti_style?.[typeof mbti === 'string' && mbti.length === 4 ? mbti[2] : ''] ?? { time_floor: 0.25, quality_power: 1 };
  const w = rules.score_weights;
  const time = style.time_floor + (1 - style.time_floor) * Math.max(0, Math.min(1, timeLeft));
  const score = w.quality * quality ** style.quality_power + w.taste * taste + w.time * time;
  return Math.max(1, Math.min(5, Math.round(1 + 4 * score)));
}

/** 받는 돈 (별점 배율 × 단골 덤). */
export function payFor(rules, recipe, stars, regular) {
  return Math.round((recipe.price * rules.pay_by_stars[stars] * (regular ? 1 + rules.regular.bonus : 1)) / 100) * 100;
}

/**
 * 단골 기록 갱신. 같은 요리에 min_stars 이상을 streak 번 연속 → 단골. break_below 미만이면 단골이 풀린다.
 * rec = { dish, streak, regular } (없으면 새로). 돌려주는 값: { rec, became, lost }
 */
export function updateRegular(rules, rec, dish, stars) {
  const r = rec ? { ...rec } : { dish, streak: 0, regular: false };
  let became = false;
  let lost = false;
  if (r.regular && r.dish === dish && stars < rules.regular.break_below) {
    r.regular = false;
    r.streak = 0;
    lost = true;
    return { rec: r, became, lost };
  }
  if (r.regular) return { rec: r, became, lost };
  if (stars >= rules.regular.min_stars) {
    r.streak = r.dish === dish ? r.streak + 1 : 1;
    r.dish = dish;
    if (r.streak >= rules.regular.streak) {
      r.regular = true;
      became = true;
    }
  } else {
    r.streak = 0;
    r.dish = dish;
  }
  return { rec: r, became, lost };
}

/** 저장 파일의 식당 기록 정리: { history: [별점…], regulars: { 손님: rec }, served, revenue } */
export function sanitizeRestaurant(raw, recipes) {
  const out = { history: [], regulars: {}, served: 0, revenue: 0 };
  if (!raw || typeof raw !== 'object') return out;
  if (Array.isArray(raw.history)) out.history = raw.history.filter((s) => Number.isInteger(s) && s >= 1 && s <= 5).slice(-100);
  const ids = new Set(recipes.map((r) => r.id));
  for (const [c, rec] of Object.entries(raw.regulars ?? {})) {
    if (rec && ids.has(rec.dish)) out.regulars[c] = { dish: rec.dish, streak: Math.max(0, Math.trunc(rec.streak ?? 0)), regular: !!rec.regular };
  }
  out.served = Math.max(0, Math.trunc(Number(raw.served) || 0));
  out.revenue = Math.max(0, Math.trunc(Number(raw.revenue) || 0));
  return out;
}
