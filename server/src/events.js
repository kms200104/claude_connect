// 마을 이벤트(서버 권위). 날마다 마을 시드로 하루 이벤트 하나를 뽑고, 밤 이벤트(유성우)는 따로 굴린다.
// 저장할 필요 없이 언제 계산해도 같은 결과가 나온다 (날씨와 같은 방식). 바닥에 떨어진 선물·별 조각은 메모리에만 둔다.
import { inHours, seededRandom } from './clock.js';
import { pickWeighted } from './gamedata.js';

const EVENT_SALT = 0x5eed;

/**
 * 하루 계획: { daily: { id, def, wanted: [아이템 id] } | null, meteor: def | null }.
 * force(쉼표 목록)·forcedWanted 는 시연·테스트용 (cfg.eventForce, cfg.eventWanted).
 */
export function planDay({ seed, day, events, data, force = '', forcedWanted = '' }) {
  const random = seededRandom(seed, day + EVENT_SALT);
  const forced = force ? force.split(',').map((s) => s.trim()).filter(Boolean) : null;
  let dailyDef = null;
  if (forced) {
    dailyDef = events.daily.find((d) => forced.includes(d.id)) ?? null;
  } else if (random() < events.daily_chance) {
    dailyDef = pickWeighted(events.daily, (d) => d.weight, random);
  }
  let daily = null;
  if (dailyDef) {
    const wanted = forcedWanted ? forcedWanted.split(',').map((s) => s.trim()).filter((id) => data.isKnown(id)) : pickWanted(dailyDef.wanted, data, random);
    daily = { id: dailyDef.id, def: dailyDef, wanted };
  }
  const meteorDef = events.night.find((n) => n.id === 'meteor_shower') ?? null;
  const meteorRoll = seededRandom(seed, day + EVENT_SALT * 2)();
  const meteor = meteorDef && (forced ? forced.includes(meteorDef.id) : meteorRoll < meteorDef.chance) ? meteorDef : null;
  return { day, daily, meteor };
}

/** 종류별 개수만큼 팔 수 있는 아이템을 겹치지 않게 고른다 (예: 물고기 2 + 재료 1). */
function pickWanted(spec, data, random) {
  if (!spec) return [];
  const out = [];
  for (const [kind, count] of Object.entries(spec)) {
    const pool = [...data.fish.keys(), ...data.items.keys()].filter((id) => data.kindOf(id) === kind && data.priceOf(id) > 0 && !out.includes(id));
    pool.sort();
    for (let i = 0; i < count && pool.length > 0; i++) out.push(pool.splice(Math.floor(random() * pool.length), 1)[0]);
  }
  return out;
}

/** 지금 열려 있는 이벤트 [{ id, def, wanted }]. 하루 이벤트는 시간대, 유성우는 시간대와 날씨도 맞아야 한다. */
export function activeEvents(plan, hour, weather) {
  const list = [];
  if (plan.daily && inHours(plan.daily.def.hours, hour)) list.push(plan.daily);
  const m = plan.meteor;
  if (m && inHours(m.hours, hour) && (!Array.isArray(m.weather) || m.weather.includes(weather))) list.push({ id: m.id, def: m, wanted: [] });
  return list;
}

export function findEvent(active, id) {
  return active.find((e) => e.id === id) ?? null;
}

/** 상점(where='shop') 또는 떠돌이 상인(where='merchant')이 이 아이템을 사 줄 때의 배율. 상인은 찾는 물건만 산다(그 밖은 0). */
export function sellMultiplier(active, itemId, where) {
  if (where === 'merchant') {
    const m = findEvent(active, 'merchant');
    return m && m.wanted.includes(itemId) ? m.def.multiplier : 0;
  }
  const b = findEvent(active, 'bargain');
  return b && b.wanted.includes(itemId) ? b.def.multiplier : 1;
}

/** 클라이언트에 보내는 이벤트 목록 (이름·설명은 클라이언트가 같은 데이터로 안다). */
export function eventsWire(active, day) {
  return {
    day,
    list: active.map((e) => {
      const w = { id: e.id };
      if (e.wanted.length > 0) w.wanted = e.wanted;
      if (e.def.multiplier) w.mult = e.def.multiplier;
      if (e.def.stock) w.stock = e.def.stock;
      return w;
    }),
  };
}

/**
 * 선물·별 조각이 떨어질 자리: 광장 둘레 28m 안에서 호수·상점·집·나무·바위를 피한다.
 * 30번 안에 못 찾으면 null.
 */
export function dropPosition({ random, data, layout, near = { x: -3, z: 2 }, radius = 28 }) {
  for (let i = 0; i < 30; i++) {
    const a = random() * Math.PI * 2;
    const r = Math.sqrt(random()) * radius;
    const x = Math.round((near.x + Math.cos(a) * r) * 10) / 10;
    const z = Math.round((near.z + Math.sin(a) * r) * 10) / 10;
    if (blocked(x, z, data, layout)) continue;
    return { x, z };
  }
  return null;
}

function blocked(x, z, data, layout) {
  for (const s of data.spots.values()) {
    if (Math.abs(x - s.x) < s.half_x + 2 && Math.abs(z - s.z) < s.half_z + 2) return true;
  }
  const door = data.shop.door;
  if (Math.abs(x - door.x) < 6 && z < door.z + 2 && z > door.z - 9) return true;
  for (const n of data.npcs.values()) if (Math.hypot(x - n.house.x, z - n.house.z) < 4) return true;
  for (const t of data.trees.values()) if (Math.hypot(x - t.x, z - t.z) < 1.4) return true;
  for (const rock of layout?.rocks ?? []) if (Math.hypot(x - rock.x, z - rock.z) < rock.size + 1) return true;
  return false;
}
