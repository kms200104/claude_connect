// 씨앗 심기와 꽃 (서버 권위). 나무 씨앗(도토리·솔방울·자작나무 씨앗)은 새싹부터 자라는 나무가 되고,
// 꽃 씨앗은 새싹 → 꽃봉오리 → 꽃으로 자란다. 핀 꽃을 따면 꽃 아이템이 되고, 봉오리로 돌아가 다시 핀다.
// flowers: Map<id, { id, sp(종류), c(색 번호), x, z, s('sprout'|'bud'|'bloom'), t(단계 시작 게임 ms), by(심은 자리) }>
import { groundProblem } from './world.js';

export const FlowerStage = Object.freeze({ sprout: 'sprout', bud: 'bud', bloom: 'bloom' });

const MINUTE_MS = 60000;
export const snapPlant = (v) => Math.round(v * 2) / 2;

/** 시간이 지난 만큼 자란다 (비 오면 rain_bonus 배 빠르게). 바뀌었으면 true. */
export function refreshFlower(f, def, nowMs, scale = 1, rainy = false) {
  const before = f.s;
  const speed = rainy && def.rain_bonus ? def.rain_bonus : 1;
  let guard = 0;
  while (f.s !== FlowerStage.bloom && guard++ < 4) {
    const stay = ((def.minutes?.[f.s] ?? 6) * MINUTE_MS * scale) / speed;
    if (nowMs - f.t < stay) break;
    f.t += stay;
    f.s = f.s === FlowerStage.sprout ? FlowerStage.bud : FlowerStage.bloom;
  }
  return before !== f.s;
}

/** 핀 꽃 따기: 봉오리로 돌아가 rebloom_minutes 뒤에 다시 핀다. */
export function pickFlower(f, def, nowMs, scale = 1) {
  if (f.s !== FlowerStage.bloom) return false;
  const bud = (def.minutes?.bud ?? 6) * MINUTE_MS * scale;
  const rebloom = (def.rebloom_minutes ?? 6) * MINUTE_MS * scale;
  f.s = FlowerStage.bud;
  f.t = nowMs - Math.max(bud - rebloom, 0);
  return true;
}

/** 길·광장 위인지 (길에는 심지 않는다). */
export function onPath(layout, x, z) {
  if (!layout) return false;
  const half = (layout.path_width ?? 2.6) * 0.5 + 0.2;
  const plazas = [layout.plaza, ...(layout.plazas ?? [])].filter(Boolean);
  for (const p of plazas) if (Math.hypot(x - p.x, z - p.z) < p.r + 0.2) return true;
  for (const line of layout.paths ?? []) {
    for (let i = 0; i < line.length - 1; i++) {
      const [ax, az] = line[i];
      const [bx, bz] = line[i + 1];
      const dx = bx - ax;
      const dz = bz - az;
      const t = Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / Math.max(dx * dx + dz * dz, 1e-6)));
      if (Math.hypot(x - (ax + t * dx), z - (az + t * dz)) < half) return true;
    }
  }
  return false;
}

/**
 * 심을 수 있으면 null, 아니면 이유. kind: 'tree' | 'flower'.
 * trees: 모든 나무 자리 [{x, z}], flowers: 꽃 Map, placed: 가구 Map.
 */
export function plantProblem({ kind, x, z, player, data, trees, flowers, placed }) {
  const rules = data.plants;
  if (![x, z].every(Number.isFinite)) return 'bad';
  if (Math.hypot(x - player.x, z - player.z) > rules.plant_range + 0.5) return 'far';
  const ground = groundProblem(data, x, z);
  if (ground) return ground;
  if (onPath(data.layout, x, z)) return 'path';
  const treeGap = kind === 'tree' ? rules.tree_clearance : 1.0;
  for (const t of trees) if (Math.hypot(x - t.x, z - t.z) < treeGap) return 'tree';
  const flowerGap = kind === 'tree' ? 1.0 : rules.flower_clearance;
  for (const f of flowers.values()) if (Math.hypot(x - f.x, z - f.z) < flowerGap) return 'flower';
  for (const f of placed.values()) if (Math.hypot(x - f.x, z - f.z) < 0.9) return 'furniture';
  return null;
}

export function sanitizeFlowers(raw, data) {
  const out = new Map();
  if (!Array.isArray(raw)) return out;
  for (const f of raw.slice(0, data.plants.max_flowers)) {
    const def = f && data.flowerDefs.get(f.sp);
    if (!def || typeof f.id !== 'string' || !/^g\d+$/.test(f.id) || ![f.x, f.z].every(Number.isFinite)) continue;
    out.set(f.id, {
      id: f.id,
      sp: f.sp,
      c: Number.isInteger(f.c) && f.c >= 0 && f.c < def.colors.length ? f.c : 0,
      x: f.x,
      z: f.z,
      s: Object.values(FlowerStage).includes(f.s) ? f.s : FlowerStage.sprout,
      t: Number.isFinite(f.t) ? f.t : 0,
      by: Number.isInteger(f.by) ? f.by : 0,
    });
  }
  return out;
}

export function flowerWire(f) {
  return { id: f.id, sp: f.sp, c: f.c, x: f.x, z: f.z, s: f.s };
}
