// 모의 증권시장 (서버 전체에 하나, 모든 방이 같은 시세를 본다).
// 1분마다(tick_minutes) 가격이 움직인다. 시세는 두 가지 중 하나에서 온다:
//   - 내장 모의 거래소 (기본): 종목마다 변동성·추세·평균 회귀·가끔 뉴스(급등락)로 움직이는 무작위 걸음.
//   - 외부 시세 서버 (MARKET_FEED_URL): 1분마다 GET 해서 { quotes: { 종목id: 가격 } } 을 받는다.
//     실패하면 그 분은 모의 거래소로 대신 움직인다 (게임은 멈추지 않는다). server/tools/market_server.js 가 같은 형식의 서버.
// 주문은 지금 가격으로 바로 체결된다 (시장가). 수수료·매도세·호가 단위·하루 ±30% 제한은 한국 주식시장을 따른다.
import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import path from 'node:path';

/** 호가 단위 (KRX 2023~): 가격대별 최소 움직임. */
export function tickSize(price) {
  if (price < 2000) return 1;
  if (price < 5000) return 5;
  if (price < 20000) return 10;
  if (price < 50000) return 50;
  if (price < 200000) return 100;
  if (price < 500000) return 500;
  return 1000;
}

export function roundToTick(price) {
  const t = tickSize(price);
  return Math.max(t, Math.round(price / t) * t);
}

/** 정규분포 난수 (Box-Muller). */
function gaussian(random) {
  const u = Math.max(random(), 1e-12);
  const v = random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/** 한 종목을 1분 움직인다 (모의 거래소). ref = 오늘 기준가 (±daily_limit). */
export function simStep(stock, def, rules, random) {
  let r = (def.drift ?? 0) + (def.vol ?? 0.002) * gaussian(random);
  // 처음 가격에서 너무 멀어지면 조금씩 돌아온다 (게임이 수십 년 돌아도 터무니없는 값이 되지 않게).
  r += (rules.reversion ?? 0) * Math.log(def.price / stock.price);
  if (random() < (rules.news_chance ?? 0)) {
    const [lo, hi] = rules.news_size ?? [0.02, 0.06];
    r += (random() < 0.5 ? -1 : 1) * (lo + random() * (hi - lo));
  }
  return clampToLimit(stock.price * Math.exp(r), stock.ref, rules.daily_limit ?? 0.3);
}

export function clampToLimit(price, ref, limit) {
  const lo = roundToTick(ref * (1 - limit));
  const hi = roundToTick(ref * (1 + limit));
  return Math.min(hi, Math.max(lo, roundToTick(price)));
}

/** 장이 열려 있는지 (always_open 이면 늘). gameMs = 마을 시계(KST 벽시계를 epoch 로 나타낸 값). */
export function marketOpen(rules, gameMs, forceHours = false) {
  if (rules.always_open && !forceHours) return true;
  const d = new Date(gameMs);
  const weekday = d.getUTCDay();
  const hour = d.getUTCHours() + d.getUTCMinutes() / 60;
  const h = rules.hours ?? { open: 9, close: 15.5, weekdays: [1, 2, 3, 4, 5] };
  return h.weekdays.includes(weekday) && hour >= h.open && hour < h.close;
}

/** 매수에 드는 돈 (가격 × 수량 + 수수료, 원 단위 올림). */
export function buyCost(rules, price, qty) {
  const gross = price * qty;
  const fee = Math.ceil(gross * rules.fee_rate);
  return { gross, fee, tax: 0, total: gross + fee };
}

/** 매도로 받는 돈 (가격 × 수량 − 수수료 − 증권거래세, 원 단위 내림). */
export function sellProceeds(rules, price, qty) {
  const gross = price * qty;
  const fee = Math.ceil(gross * rules.fee_rate);
  const tax = Math.ceil(gross * rules.sell_tax_rate);
  return { gross, fee, tax, total: gross - fee - tax };
}

/** 프로필의 보유 주식 (모르는 종목·이상한 값은 버린다). { id: { q: 수량, cost: 산 돈 합계 } } */
export function sanitizeHoldings(raw, rules) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  const ids = new Set(rules.stocks.map((s) => s.id));
  for (const [id, h] of Object.entries(raw)) {
    const q = Math.trunc(Number(h?.q));
    const cost = Math.trunc(Number(h?.cost));
    if (ids.has(id) && Number.isFinite(q) && q > 0 && Number.isFinite(cost) && cost >= 0) out[id] = { q, cost };
  }
  return out;
}

/**
 * 시장 하나를 만든다.
 * opts: { saveDir, feedUrl, random, now(): ms, gameMs(): ms, day(): 마을 날짜, fetch, forceHours }
 */
export function createMarket(rules, opts = {}) {
  const random = opts.random ?? Math.random;
  const defs = new Map(rules.stocks.map((s) => [s.id, s]));
  const file = opts.saveDir ? path.join(opts.saveDir, 'market.json') : null;
  const historyLen = rules.history_minutes ?? 240;
  const state = { minute: 0, day: null, source: 'sim', stocks: new Map() };
  let feedWarned = false;

  for (const def of rules.stocks) state.stocks.set(def.id, { price: def.price, ref: def.price, open: def.price, hist: [def.price] });
  // 저장된 시세가 있으면 이어서.
  if (file) {
    try {
      const saved = JSON.parse(readFileSync(file, 'utf8'));
      state.minute = Number.isInteger(saved.minute) ? saved.minute : 0;
      state.day = Number.isInteger(saved.day) ? saved.day : null;
      for (const [id, s] of Object.entries(saved.stocks ?? {})) {
        if (!defs.has(id) || !(s.price > 0)) continue;
        const hist = Array.isArray(s.hist) ? s.hist.filter((p) => p > 0).slice(-historyLen) : [];
        state.stocks.set(id, { price: s.price, ref: s.ref > 0 ? s.ref : s.price, open: s.open > 0 ? s.open : s.price, hist: hist.length ? hist : [s.price] });
      }
    } catch {
      // 처음이거나 깨진 파일: 데이터의 첫 가격으로 시작.
    }
  }

  function save() {
    if (!file) return;
    try {
      mkdirSync(path.dirname(file), { recursive: true });
      const out = { minute: state.minute, day: state.day, stocks: Object.fromEntries([...state.stocks].map(([id, s]) => [id, s])) };
      writeFileSync(`${file}.tmp`, JSON.stringify(out));
      renameSync(`${file}.tmp`, file);
    } catch (err) {
      console.warn('[market] 저장 실패:', err.message);
    }
  }

  /** 날이 바뀌면 어제 마지막 가격이 오늘 기준가(±30% 제한의 기준)가 된다. */
  function rollDay() {
    const day = opts.day ? opts.day() : null;
    if (day === null || day === state.day) return;
    state.day = day;
    for (const s of state.stocks.values()) {
      s.ref = s.price;
      s.open = s.price;
    }
  }

  async function fetchFeed() {
    if (!opts.feedUrl) return null;
    try {
      const doFetch = opts.fetch ?? fetch;
      const res = await doFetch(opts.feedUrl, { signal: AbortSignal.timeout(5000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = await res.json();
      const quotes = {};
      const raw = body?.quotes;
      if (Array.isArray(raw)) for (const q of raw) quotes[q.id] = Number(q.price);
      else if (raw && typeof raw === 'object') for (const [id, p] of Object.entries(raw)) quotes[id] = Number(p);
      return quotes;
    } catch (err) {
      if (!feedWarned) console.warn(`[market] 시세 서버(${opts.feedUrl})를 못 읽어 모의 거래소로 대신 움직입니다: ${err.message}`);
      feedWarned = true;
      return null;
    }
  }

  /** 1분 진행. 바뀐 가격 { id: price } 를 돌려준다. 장이 닫혀 있으면 null. */
  async function tick() {
    rollDay();
    if (!marketOpen(rules, opts.gameMs ? opts.gameMs() : Date.now(), opts.forceHours)) return null;
    const quotes = await fetchFeed();
    state.source = quotes ? 'feed' : 'sim';
    if (quotes) feedWarned = false;
    state.minute += 1;
    const changed = {};
    for (const [id, s] of state.stocks) {
      const def = defs.get(id);
      const fed = quotes?.[id];
      s.price = Number.isFinite(fed) && fed > 0 ? clampToLimit(fed, s.ref, rules.daily_limit ?? 0.3) : simStep(s, def, rules, random);
      s.hist.push(s.price);
      if (s.hist.length > historyLen) s.hist.shift();
      changed[id] = s.price;
    }
    save();
    return changed;
  }

  function price(id) {
    return state.stocks.get(id)?.price ?? null;
  }

  function isOpen() {
    return marketOpen(rules, opts.gameMs ? opts.gameMs() : Date.now(), opts.forceHours);
  }

  /** 입장할 때 보내는 시장 전체 (최근 histMinutes 분 가격 포함). */
  function wire(histMinutes = 120) {
    return {
      minute: state.minute,
      open: isOpen(),
      source: state.source,
      fee: rules.fee_rate,
      tax: rules.sell_tax_rate,
      stocks: rules.stocks.map((def) => {
        const s = state.stocks.get(def.id);
        return { id: def.id, name: def.name, sector: def.sector, about: def.about ?? '', price: s.price, ref: s.ref, hist: s.hist.slice(-histMinutes) };
      }),
    };
  }

  /** 보유 주식의 지금 평가액. */
  function holdingsValue(holdings) {
    let total = 0;
    for (const [id, h] of Object.entries(holdings ?? {})) total += (price(id) ?? 0) * h.q;
    return total;
  }

  return { state, tick, price, isOpen, wire, holdingsValue, rollDay, save };
}
