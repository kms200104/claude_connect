// 예적금 (v0.12, 서버 권위): 정기예금 · 정기적금 · 파킹통장. 데이터는 data/bank/savings.json.
// 금리 = 그 주 기준금리 + 상품 가산, 가입할 때 고정. 대출처럼 연 금리를 52주로 나눠 주마다 계산한다 (빌려서 예금하면 손해).
// 우대금리는 만기에 조건(첫 거래 · 급여 이체 · 자동이체 성실 · 지역화폐 카드 · 청년)을 보고 더한다.
// 이자에는 세금이 붙는다 (일반 15.4%, 마을금고 조합원은 3천만까지 1.4%). 중도해지는 기본금리의 일부만.
// 예금자 보호: 기관마다 원금+이자 합계 protection 까지 — 저축은행이 문을 닫으면 그만큼은 바로, 넘는 돈은 recovery 비율만 돌려준다.

/** savings.json → { institutions(Map), products(Map), ... } (모르는 기관의 상품은 버린다). */
export function loadSavings(raw) {
  if (!raw) return null;
  const institutions = new Map((raw.institutions ?? []).map((i) => [i.id, i]));
  const products = new Map();
  for (const p of raw.products ?? []) {
    if (!institutions.has(p.bank)) throw new Error(`savings: ${p.id} 의 은행 ${p.bank} 이(가) 없음`);
    if (!['deposit', 'savings', 'parking'].includes(p.kind)) throw new Error(`savings: ${p.id} 종류 ${p.kind}`);
    if (!Array.isArray(p.weeks) || p.weeks.length !== p.spread.length) throw new Error(`savings: ${p.id} weeks·spread 길이`);
    products.set(p.id, p);
  }
  return { ...raw, institutions, products };
}

/** 상품의 가입 기간별 기본 금리 (지금 기준금리로). */
export function productRate(product, baseRate, weeks) {
  const i = product.weeks.indexOf(weeks);
  if (i < 0) return null;
  return Math.max(0.001, Math.round((baseRate + product.spread[i]) * 10000) / 10000);
}

/** 이자 (세전, 원 단위 버림). deposit: 원금 × 금리 × 주/52. savings: 넣은 주마다 남은 주만큼. */
export function grossInterest(account, rate, weeksHeld) {
  if (account.kind === 'savings') {
    let sum = 0;
    for (const at of account.paidAt ?? []) sum += account.amount * rate * Math.max(0, weeksHeld - at) / 52;
    return Math.floor(sum);
  }
  return Math.floor((account.principal * rate * weeksHeld) / 52);
}

/** 세금 (원 단위 올림). 마을금고 조합원은 원금 coop_limit 까지 낮은 세율. */
export function interestTax(rules, gross, { coopMember, principal }) {
  if (gross <= 0) return 0;
  if (!coopMember) return Math.ceil(gross * rules.tax.normal);
  const share = Math.min(1, rules.tax.coop_limit / Math.max(principal, 1));
  return Math.ceil(gross * share * rules.tax.coop_member + gross * (1 - share) * rules.tax.normal);
}

/** 만기에 받는 우대금리 합 (조건마다 확인). ctx = { first, incomeWeeks, missed, card, age }. */
export function bonusRate(rules, product, account, ctx) {
  let sum = 0;
  const got = [];
  for (const [kind, rate] of Object.entries(product.bonus ?? {})) {
    let ok = false;
    if (kind === 'first') ok = !!account.first;
    else if (kind === 'income') ok = (account.incomeWeeks ?? 0) * 2 >= account.weeks;
    else if (kind === 'auto') ok = account.kind === 'savings' && (account.missed ?? 0) === 0;
    else if (kind === 'local_card') ok = !!ctx.card;
    else if (kind === 'youth') ok = (ctx.age ?? 99) <= (rules.bonuses?.youth?.max_age ?? 34);
    if (ok) {
      sum += rate;
      got.push(kind);
    }
  }
  return { rate: Math.round(sum * 10000) / 10000, got };
}

/** 중도해지 금리 배율 (지난 기간 비율로). */
export function earlyFactor(rules, fraction) {
  for (const step of rules.early) if (fraction < step.under) return step.factor;
  return 1;
}

/** 가입 자격 (only: youth). */
export function eligible(rules, product, ctx) {
  if (product.only === 'youth') return (ctx.age ?? 99) <= (rules.bonuses?.youth?.max_age ?? 34);
  return true;
}

/** 지금까지 넣은 돈 (적금은 낸 횟수 × 금액). */
export function principalOf(account) {
  return account.kind === 'savings' ? account.amount * (account.paidAt?.length ?? 0) : account.principal;
}

/**
 * 계좌를 닫을 때 받는 돈: { principal, gross, tax, net, bonus, early }.
 * 만기 전이면 중도해지 (기본금리 × 배율, 우대 없음), 만기면 기본 + 우대. 파킹통장은 이자가 주마다 이미 붙어 원금뿐.
 */
export function settle(rules, product, account, week, ctx) {
  const principal = principalOf(account);
  if (account.kind === 'parking') return { principal, gross: 0, tax: 0, net: principal, bonus: 0, early: false, got: [] };
  const held = Math.max(0, week - account.week);
  const matured = held >= account.weeks;
  let rate = account.rate;
  let got = [];
  let bonus = 0;
  if (matured) {
    const b = bonusRate(rules, product, account, ctx);
    bonus = b.rate;
    got = b.got;
    rate += bonus;
  } else {
    rate *= earlyFactor(rules, held / account.weeks);
  }
  const gross = grossInterest(account, rate, Math.min(held, account.weeks));
  const tax = interestTax(rules, gross, { coopMember: ctx.coopMember && product.bank === 'hosu', principal });
  return { principal, gross, tax, net: principal + gross - tax, bonus, early: !matured, got };
}

/** 파킹통장 한 주 이자 (세후): 한도까지는 상품 금리, 넘는 돈은 parking_over_rate. */
export function parkingWeek(rules, account, ctx) {
  const capped = Math.min(account.principal, rules.parking_cap);
  const over = Math.max(0, account.principal - rules.parking_cap);
  const gross = Math.floor((capped * account.rate + over * rules.parking_over_rate) / 52);
  return gross - interestTax(rules, gross, { coopMember: false, principal: account.principal });
}

/** 저장된 계좌 목록 정리 (모르는 상품·모양이 틀린 것은 버린다). */
export function sanitizeDeposits(raw, savings) {
  if (!Array.isArray(raw) || !savings) return [];
  return raw
    .filter((a) => a && typeof a.id === 'string' && savings.products.has(a.product) && Number.isInteger(a.week) && Number.isFinite(a.rate))
    .slice(0, savings.max_accounts ?? 8)
    .map((a) => ({
      id: a.id,
      product: a.product,
      bank: savings.products.get(a.product).bank,
      kind: savings.products.get(a.product).kind,
      week: a.week,
      weeks: Number.isInteger(a.weeks) ? a.weeks : 0,
      rate: a.rate,
      principal: Math.max(0, Math.trunc(Number(a.principal) || 0)),
      amount: Math.max(0, Math.trunc(Number(a.amount) || 0)),
      paidAt: Array.isArray(a.paidAt) ? a.paidAt.filter(Number.isInteger).slice(0, 60) : [],
      missed: Math.max(0, Math.trunc(Number(a.missed) || 0)),
      incomeWeeks: Math.max(0, Math.trunc(Number(a.incomeWeeks) || 0)),
      first: !!a.first,
    }));
}

/** 기관마다 맡긴 돈 (원금 + 쌓인 이자 추정) — 예금자 보호 한도 확인용. */
export function exposureByBank(accounts) {
  const out = {};
  for (const a of accounts) out[a.bank] = (out[a.bank] ?? 0) + principalOf(a);
  return out;
}

/**
 * 문을 닫은 기관의 계좌 정리: 계좌마다 원금 + 지금까지 약정 금리로 쌓인 이자(세후)를 더하고,
 * 그 합이 보호 한도까지는 그대로, 넘는 돈은 recovery 비율만 돌려준다.
 */
export function failurePayout(rules, accounts, week) {
  let total = 0;
  for (const a of accounts) {
    const principal = principalOf(a);
    if (a.kind === 'parking') {
      total += principal;
      continue;
    }
    const held = Math.max(0, Math.min(a.weeks, week - a.week));
    const gross = grossInterest(a, a.rate, held);
    total += principal + gross - interestTax(rules, gross, { coopMember: false, principal });
  }
  const over = Math.max(0, total - rules.protection);
  const recovered = Math.floor(over * rules.recovery);
  return { total, paid: Math.min(total, rules.protection) + recovered, lost: over - recovered };
}
