// 아파트 (서버 권위): 단지·동·호수와 시세, 사고팔기, 월세. 소유는 방(마을) 단위로 저장한다 — 한 집은 한 사람만.
// 가격 = 평형 기준가 × (1 + 층 할증 + 동 할증) × 마을 집값 지수. 지수는 마을 시계로 한 주마다 조금씩 움직인다.

/** 단지의 모든 호수: [{ id: '101-803', building, floor, line, type }]. 동마다 line_types 로 라인별 평형을 정할 수 있다 (v0.10). */
export function listUnits(rules) {
  const units = [];
  for (const b of rules.buildings) {
    for (let floor = 1; floor <= b.floors; floor++) {
      for (let line = 1; line <= b.lines; line++) {
        const lineTypes = b.line_types ?? rules.line_types;
        const type = floor === b.floors && rules.top_floor_type ? rules.top_floor_type : lineTypes[(line - 1) % lineTypes.length];
        units.push({ id: `${b.id}-${floor}${String(line).padStart(2, '0')}`, building: b.id, floor, line, type });
      }
    }
  }
  return units;
}

/** 층 할증 (floor_premium 의 [층, 할증] 표에서 그 층 이하 중 가장 높은 줄). */
export function floorPremium(rules, floor) {
  let p = 0;
  for (const [from, premium] of rules.floor_premium) if (floor >= from) p = premium;
  return p;
}

/** 이 호수의 지금 시세 (만 원 단위로 반올림). */
export function unitPrice(rules, unit, index) {
  const type = rules.types[unit.type];
  const building = rules.buildings.find((b) => b.id === unit.building);
  const raw = type.price * (1 + floorPremium(rules, unit.floor) + (building?.premium ?? 0)) * index;
  return Math.round(raw / 10000) * 10000;
}

/** 살 때 드는 돈: 집값 + 취득세 + 중개보수. */
export function purchaseCost(rules, price) {
  const tax = Math.round(price * rules.acquisition_tax);
  const fee = Math.round(price * rules.broker_fee);
  return { price, tax, fee, total: price + tax + fee };
}

/** 팔 때 받는 돈: 집값 − 중개보수 (1주택 양도세는 없는 것으로). */
export function saleProceeds(rules, price) {
  const fee = Math.round(price * rules.broker_fee);
  return { price, fee, total: price - fee };
}

/** 한 주 월세 (연 수익률 / 52). */
export function weeklyRent(rules, price) {
  return Math.round((price * rules.rent_yield) / 52);
}

/** 전세 보증금 (v0.12): 지금 시세 × ratio, 만 원 단위. */
export function jeonseDeposit(rules, price) {
  return Math.round((price * (rules.jeonse?.ratio ?? 0.6)) / 10000) * 10000;
}

/** 집값 지수를 한 주 움직인다 (로그 정규 + 범위 제한). */
export function stepIndex(rules, index, random) {
  const u = Math.max(random(), 1e-12);
  const g = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * random());
  const next = index * Math.exp(rules.index.weekly_drift + rules.index.weekly_vol * g);
  return Math.min(rules.index.max, Math.max(rules.index.min, Math.round(next * 10000) / 10000));
}

/** 저장 파일의 소유 목록 { unitId: { owner: uid, price, day } } 에서 모르는 호수를 버린다. */
export function sanitizeHomes(raw, units) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  const ids = new Set(units.map((u) => u.id));
  for (const [id, h] of Object.entries(raw)) {
    if (!ids.has(id) || typeof h?.owner !== 'string' || !Number.isFinite(h.price)) continue;
    out[id] = { owner: h.owner, price: Math.trunc(h.price), day: Number.isInteger(h.day) ? h.day : 0 };
    const l = h.lease;
    if (l?.kind === 'jeonse' && Number.isInteger(l.deposit) && l.deposit > 0 && Number.isInteger(l.until)) out[id].lease = { kind: 'jeonse', deposit: l.deposit, until: l.until };
  }
  return out;
}

/** 이 사람이 가진 집들의 지금 시세 합. */
export function homesValue(rules, units, homes, uid, index) {
  let total = 0;
  for (const u of units) if (homes[u.id]?.owner === uid) total += unitPrice(rules, u, index);
  return total;
}
