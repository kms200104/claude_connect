// 솔바람은행 (서버 권위): 신용점수·등급, 변동금리, 대출 한도, 매주 이자.
// 금리 = 기준금리 + 등급별 가산금리 (신용대출 / 주택담보대출). 한 주마다 기준금리가 가끔 움직이고(±0.25%p),
// 내 신용점수도 다시 매겨서 금리가 바뀐다 — 이자를 꼬박꼬박 내고 소득이 늘면 오르고, 연체하거나 빚이 자산보다 크면 깎인다.

export const WEEK_DAYS = 7;

/** 마을 날짜 → 주 번호. */
export function weekOf(day) {
  return Math.floor(day / WEEK_DAYS);
}

/** 신용점수 → 등급 (1~10). */
export function gradeOf(rules, score) {
  const g = rules.credit.grades.findIndex((min) => score >= min);
  return g < 0 ? 10 : g + 1;
}

/** 지금 금리 (연). kind = 'credit' | 'mortgage'. */
export function rateFor(rules, baseRate, grade, kind) {
  const spreads = kind === 'mortgage' ? rules.credit.spread_mortgage : rules.credit.spread_credit;
  return Math.min(rules.max_rate, Math.round((baseRate + spreads[grade - 1]) * 10000) / 10000);
}

/** 한 주 이자 (원 단위 올림). */
export function weeklyInterest(principal, rate) {
  return Math.ceil((principal * rate) / 52);
}

/** 프로필의 신용 기록 기본값. */
export function newCredit(rules) {
  return { paid: 0, missed: 0, weeks: 0 };
}

/** 소득(최근 4주 평균 × 52) — 대출 한도와 신용점수에 쓴다. */
export function annualIncome(income) {
  const weeks = [...(income?.history ?? [])].slice(-4);
  if (weeks.length === 0) return (income?.amount ?? 0) * 52;
  return Math.round((weeks.reduce((a, b) => a + b, 0) / weeks.length) * 52);
}

/**
 * 신용점수 (0~1000). 시작 점수 + 꼬박꼬박 낸 이자 주 × on_time + 연체 × missed + 소득 가점 + 거래 기간 가점
 * − (빚 / 자산 이 debt_ratio_free 를 넘은 만큼) × debt_ratio_penalty.
 */
export function creditScore(rules, { credit, income, debt, assets }) {
  const c = rules.credit;
  const incomeBonus = Math.min(c.income_bonus_max, Math.floor(annualIncome(income) / 10000000) * c.income_bonus_per_10m);
  const tenure = Math.min(c.tenure_bonus_max, (credit?.weeks ?? 0) * c.tenure_bonus_per_week);
  const ratio = assets > 0 ? debt / assets : debt > 0 ? 3 : 0;
  const debtPenalty = Math.max(0, ratio - c.debt_ratio_free) * c.debt_ratio_penalty;
  const score = c.start_score + (credit?.paid ?? 0) * c.on_time + (credit?.missed ?? 0) * c.missed + incomeBonus + tenure - debtPenalty;
  return Math.max(0, Math.min(1000, Math.round(score)));
}

/** 신용대출 한도 (이미 빌린 신용대출을 뺀 남은 한도). */
export function creditLimit(rules, grade, income, creditDebt) {
  const l = rules.credit_limit;
  const raw = Math.max(l.min, annualIncome(income) * l.income_multiple) * l.grade_factor[grade - 1];
  return Math.max(0, Math.floor(Math.min(l.max, raw) / 10000) * 10000 - creditDebt);
}

/** 주택담보대출 한도 (집값 × LTV). */
export function mortgageLimit(ltv, price) {
  return Math.floor((price * ltv) / 10000) * 10000;
}

/** DSR: 1년 이자(+원금 1/30 상환을 가정) / 연소득 이 dsr 을 넘으면 안 된다. 소득이 없으면 신용 최소 한도만. */
export function dsrOk(rules, income, loans, extra) {
  const yearly = [...loans, extra].reduce((sum, l) => sum + l.principal * l.rate + l.principal / 30, 0);
  const inc = annualIncome(income);
  if (inc <= 0) return extra.kind === 'credit' && extra.principal <= rules.credit_limit.min;
  return yearly / inc <= rules.dsr;
}

/** 프로필 대출 목록 정리. */
export function sanitizeLoans(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((l) => l && (l.kind === 'credit' || l.kind === 'mortgage') && Number.isFinite(l.principal) && l.principal > 0)
    .map((l) => ({ id: String(l.id), kind: l.kind, principal: Math.trunc(l.principal), rate: Number(l.rate) || 0, unit: typeof l.unit === 'string' ? l.unit : '', since: Number.isInteger(l.since) ? l.since : 0 }));
}

/**
 * 한 주 이자를 받는다 (금리를 새 신용점수로 다시 매긴 뒤). 솔이 모자라면 낸 만큼 내고 나머지는 원금에 붙고 연체 1회.
 * 돌려주는 값: { paid, capitalized, missed }
 */
export function chargeWeek(rules, profile, baseRate, grade) {
  let paid = 0;
  let capitalized = 0;
  let missed = false;
  for (const loan of profile.loans) {
    loan.rate = rateFor(rules, baseRate, grade, loan.kind);
    const interest = weeklyInterest(loan.principal, loan.rate);
    const pay = Math.min(interest, Math.max(0, profile.sol));
    profile.sol -= pay;
    paid += pay;
    if (pay < interest) {
      loan.principal += interest - pay;
      capitalized += interest - pay;
      missed = true;
    }
  }
  if (profile.loans.length > 0) {
    profile.credit.weeks += 1;
    if (missed) profile.credit.missed += 1;
    else profile.credit.paid += 1;
  }
  return { paid, capitalized, missed };
}

/** 기준금리를 한 주 움직인다 (가끔 ±0.25%p). */
export function stepBaseRate(rules, rate, random) {
  if (random() >= rules.base_rate_change_chance) return rate;
  const next = rate + (random() < 0.5 ? -1 : 1) * rules.base_rate_step;
  const [lo, hi] = rules.base_rate_range;
  return Math.round(Math.min(hi, Math.max(lo, next)) * 10000) / 10000;
}
