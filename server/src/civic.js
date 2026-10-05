// 솔바람동 행정복지센터 (서버 권위, 순수 함수): 민원·지원금·정책대출의 자격과 조건.
// 정책은 data/civic/civic.json (천안시·정부 실제 제도를 본뜸). 소득은 세대(혼인하면 부부합산) 기준, 마을 한 주 = 한 달.
// ctx = { age, resident, married, homes(세대가 가진 집 수), income(세대 연 소득), weekIncome(세대 이번 주 소득),
//         sol, liquid(솔 + 주식), received{프로그램: {times, lastWeek, weeksLeft}}, week }

export const DESKS = ['civil', 'welfare', 'finance'];

/** 자격 검사: { ok, reasons[] } — 이유는 화면에 그대로 보여 준다. */
export function eligibility(program, ctx) {
  const r = program.rules ?? {};
  const reasons = [];
  if (r.age_min !== undefined && ctx.age < r.age_min) reasons.push(`만 ${r.age_min}세 이상`);
  if (r.age_max !== undefined && ctx.age > r.age_max) reasons.push(`만 ${r.age_max}세 이하`);
  if (r.resident && !ctx.resident) reasons.push('전입신고가 필요해요');
  if (r.no_home && ctx.homes > 0) reasons.push('무주택 세대만');
  const incomeMax = program.kind === 'policy_mortgage' && ctx.married ? program.income_max_newlywed : r.income_max ?? program.income_max;
  if (incomeMax !== undefined && ctx.income > incomeMax) reasons.push(`세대 연 소득 ${won(incomeMax)} 이하`);
  if (r.sol_max !== undefined && ctx.sol > r.sol_max) reasons.push(`가진 솔 ${won(r.sol_max)} 이하 (생계 위기)`);
  if (r.week_income_max !== undefined && ctx.weekIncome > r.week_income_max) reasons.push('이번 주 소득이 없어야 해요');
  if (r.liquid_max !== undefined && ctx.liquid > r.liquid_max) reasons.push(`현금·주식 ${won(r.liquid_max)} 이하`);
  const got = ctx.received?.[program.id];
  if (program.kind === 'grant_weekly' && got?.weeksLeft > 0) reasons.push('이미 받고 있어요');
  if (program.kind === 'grant_once' && got) {
    if (got.times >= (program.max_times ?? 1)) reasons.push(`최대 ${program.max_times}번까지`);
    else if (ctx.week - got.lastWeek < (program.cooldown_weeks ?? 0)) reasons.push(`${program.cooldown_weeks}주에 한 번`);
  }
  if (program.kind === 'card' && got) reasons.push('이미 발급받았어요');
  return { ok: reasons.length === 0, reasons };
}

/** 디딤돌대출 조건: 소득 구간 금리(신혼 우대), 한도, 집값 상한, LTV. */
export function didimdolTerms(program, ctx) {
  let rate = program.rates[program.rates.length - 1][1];
  for (const [upTo, r] of program.rates) {
    if (ctx.income <= upTo) {
      rate = r;
      break;
    }
  }
  if (ctx.married) rate -= program.newlywed_discount ?? 0;
  return {
    rate: Math.round(rate * 10000) / 10000,
    limit: ctx.married ? program.limit_newlywed : program.limit,
    priceMax: ctx.married ? program.price_max_newlywed : program.price_max,
    ltv: ctx.homesEver ? program.ltv : program.ltv_first,
    fixed: true,
  };
}

/** 햇살론유스 금리 (소득이 없으면 미취업 청년 금리). */
export function sunshineRate(program, ctx) {
  return ctx.income > 0 ? program.rate_low_income : program.rate_no_income;
}

/** 천안사랑카드 캐시백: 이번 주 한도 안에서 쓴 돈의 cashback 비율. card = { week, back } */
export function cardCashback(program, card, week, spent) {
  if (!card) return 0;
  const used = card.week === week ? card.back : 0;
  const back = Math.min(Math.floor((spent * program.cashback) / 10) * 10, Math.max(0, program.weekly_cap - used));
  return Math.max(0, back);
}

/** 프로필의 동사무소 기록 정리. */
export function sanitizeCivic(raw) {
  const out = { resident: false, movedIn: null, received: {}, card: null, approvals: {}, docs: 0 };
  if (!raw || typeof raw !== 'object') return out;
  out.resident = !!raw.resident;
  out.movedIn = Number.isInteger(raw.movedIn) ? raw.movedIn : null;
  for (const [id, r] of Object.entries(raw.received ?? {})) {
    if (r && typeof r === 'object') out.received[id] = { times: int(r.times), lastWeek: int(r.lastWeek, -99), weeksLeft: int(r.weeksLeft) };
  }
  if (raw.card && typeof raw.card === 'object') out.card = { week: int(raw.card.week, -1), back: int(raw.card.back), total: int(raw.card.total) };
  for (const [id, a] of Object.entries(raw.approvals ?? {})) {
    if (a && Number.isFinite(a.rate) && Number.isFinite(a.limit)) out.approvals[id] = { rate: a.rate, limit: Math.trunc(a.limit), priceMax: Math.trunc(a.priceMax ?? 0), ltv: Number(a.ltv) || 0.7, until: int(a.until) };
  }
  out.docs = int(raw.docs);
  return out;
}

const int = (v, fallback = 0) => (Number.isInteger(v) ? v : fallback);
const won = (n) => (n >= 100000000 ? `${n / 100000000}억` : n >= 10000 ? `${Math.round(n / 10000).toLocaleString('en-US')}만` : `${n}`) + ' 솔';
