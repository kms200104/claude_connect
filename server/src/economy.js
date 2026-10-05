// 마을 경제 서비스: 증권(주문), 아파트(사고팔기·월세), 은행(대출·주간 이자·신용), 동사무소(민원·지원금·정책대출·혼인신고).
// 식당은 kitchen.js. server.js 가 메시지를 넘기고, 방 상태·소켓 도우미는 deps 로 받는다. 판정은 전부 서버가 한다.
// v0.9: 혼인신고한 두 사람은 한 세대 — 지갑(솔)이 하나이고(rooms.js linkWallet), 소득·자산·빚·집을 세대 단위로 본다.
import { ErrorCode } from './protocol.js';
import { buyCost, sellProceeds } from './market.js';
import { purchaseCost, saleProceeds, stepIndex, unitPrice, weeklyRent } from './realestate.js';
import { annualIncome, chargeWeek, creditLimit, creditScore, dsrOk, gradeOf, mortgageLimit, rateFor, stepBaseRate, weekOf, weeklyInterest } from './bank.js';
import { cardCashback, didimdolTerms, eligibility, sunshineRate } from './civic.js';
import { eligible, exposureByBank, failurePayout, parkingWeek, principalOf, productRate, settle } from './savings.js';

/** 번 돈 기록 (대출 한도·신용점수의 소득). */
export function earn(profile, amount) {
  if (!profile.income) profile.income = { amount: 0, history: [] };
  if (amount > 0) profile.income.amount += amount;
}

/** 여러 사람의 소득 기록을 합친다 (부부합산): 주별로 끝에서부터 더한다. */
export function combineIncome(list) {
  const len = Math.max(0, ...list.map((i) => i?.history?.length ?? 0));
  const history = [];
  for (let k = len; k > 0; k--) history.push(list.reduce((a, i) => a + (i?.history?.[i.history.length - k] ?? 0), 0));
  return { amount: list.reduce((a, i) => a + (i?.amount ?? 0), 0), history };
}

export function createEconomy(deps) {
  const { data, clock, random, market, send, sendTo, sendProfile, rooms } = deps;
  const civicRules = data.civic;

  // ---- 세대 · 자산 · 신용 ----

  const membersOf = (room, profile) => (room ? room.householdOf(profile) : [profile]);
  const uidsOf = (room, profile) => membersOf(room, profile).map((p) => p.uid);
  const debtOf = (room, profile) => membersOf(room, profile).reduce((a, p) => a + p.loans.reduce((b, l) => b + l.principal, 0), 0);
  const homesOfUids = (room, uids) => data.units.filter((u) => uids.includes(room.homes[u.id]?.owner));
  const homesValueOf = (room, profile) => homesOfUids(room, uidsOf(room, profile)).reduce((a, u) => a + unitPrice(data.realestate, u, room.aptIndex), 0);
  /** 세대 소득 (혼자면 자기 것). */
  const incomeOf = (room, profile) => {
    const list = membersOf(room, profile);
    return list.length > 1 ? combineIncome(list.map((p) => p.income)) : profile.income;
  };
  /** 예적금에 넣어 둔 돈 (원금, v0.12). */
  const depositsOf = (profile) => (profile.deposits ?? []).reduce((a, d) => a + principalOf(d), 0);
  /** 세대 자산 = 지갑(하나) + 세대원 주식 + 세대원 예적금 + 세대원 집. */
  const assetsOf = (room, profile) =>
    profile.sol + membersOf(room, profile).reduce((a, p) => a + market.holdingsValue(p.stocks) + depositsOf(p), 0) + (room ? homesValueOf(room, profile) : 0);

  function creditOf(room, profile) {
    const score = creditScore(data.bank, { credit: profile.credit, income: incomeOf(room, profile), debt: debtOf(room, profile), assets: assetsOf(room, profile) });
    return { score, grade: gradeOf(data.bank, score) };
  }

  /** 은행 창구에 보이는 것: 신용·금리·한도·내 대출. */
  function bankWire(room, profile) {
    const { score, grade } = creditOf(room, profile);
    const creditDebt = profile.loans.filter((l) => l.kind === 'credit' && !l.product).reduce((a, l) => a + l.principal, 0);
    const income = incomeOf(room, profile);
    return {
      base: room.baseRate,
      score,
      grade,
      rate_credit: rateFor(data.bank, room.baseRate, grade, 'credit'),
      rate_mortgage: rateFor(data.bank, room.baseRate, grade, 'mortgage'),
      credit_limit: creditLimit(data.bank, grade, income, creditDebt),
      ltv: data.realestate.ltv,
      dsr: data.bank.dsr,
      income_year: annualIncome(income),
      income_week: income?.amount ?? 0,
      week: weekOf(clock.day()),
      joint: membersOf(room, profile).length > 1,
      loans: profile.loans.map((l) => ({ ...l, weekly: weeklyInterest(l.principal, l.rate) })),
      sv: savingsWire(room, profile),
    };
  }

  // ---- 예적금 (v0.12) ----

  const sv = data.savings;
  /** 우대 조건을 볼 때 쓰는 이 사람의 상황. */
  const depositCtx = (profile) => ({ card: !!profile.civic?.card, age: profile.age ?? 29, coopMember: !!profile.coopMember });

  /** 은행 앱 예적금 화면: 기관 · 상품(지금 금리) · 내 계좌(지금 해지하면 / 만기에 받을 돈) · 기관별 보호 한도. */
  function savingsWire(room, profile) {
    if (!sv) return null;
    const week = weekOf(clock.day());
    const ctx = depositCtx(profile);
    const products = [...sv.products.values()].map((p) => ({
      id: p.id,
      bank: p.bank,
      kind: p.kind,
      name: p.name,
      weeks: p.weeks,
      rates: p.weeks.map((w) => productRate(p, room.baseRate, w)),
      min: p.min,
      max: p.max,
      bonus: p.bonus,
      only: p.only ?? '',
      ok: eligible(sv, p, ctx),
    }));
    const accounts = (profile.deposits ?? []).map((a) => {
      const product = sv.products.get(a.product);
      const now = settle(sv, product, a, week, ctx);
      const atEnd = a.kind === 'parking' ? now : settle(sv, product, { ...a, paidAt: a.kind === 'savings' ? Array.from({ length: a.weeks }, (_, i) => i) : a.paidAt }, a.week + a.weeks, { ...ctx });
      return {
        id: a.id,
        product: a.product,
        bank: a.bank,
        kind: a.kind,
        rate: a.rate,
        weeks: a.weeks,
        left: a.kind === 'parking' ? 0 : Math.max(0, a.week + a.weeks - week),
        principal: principalOf(a),
        amount: a.amount,
        missed: a.missed,
        now: now.net,
        early: now.early,
        maturity: atEnd.net,
        bonus: atEnd.got,
      };
    });
    return {
      institutions: [...sv.institutions.values()].map((i) => ({ ...i, used: (profile.banksUsed ?? []).includes(i.id) })),
      products,
      accounts,
      exposure: exposureByBank(profile.deposits ?? []),
      protection: sv.protection,
      parking_cap: sv.parking_cap,
      parking_over_rate: sv.parking_over_rate,
      tax: sv.tax,
      bonuses: sv.bonuses,
      coop: !!profile.coopMember,
      week,
    };
  }

  /** 예적금 요청: dep_open { product, weeks, amount } · dep_close { id } · park_move { amount (+넣기 / -빼기) }. */
  function handleSavings(ctx, msg, fail) {
    const { player, room } = ctx;
    const p = player.profile;
    if (!sv) return fail(ErrorCode.badProduct);
    if (!player.acceptRid(msg.rid)) return;
    const week = weekOf(clock.day());
    const dctx = depositCtx(p);
    let result = { t: 'dep_result', rid: msg.rid, kind: msg.t };
    if (msg.t === 'dep_open') {
      const product = sv.products.get(msg.product);
      if (!product || product.kind === 'parking') return fail(ErrorCode.badProduct);
      if (!eligible(sv, product, dctx)) return fail(ErrorCode.notEligible);
      const weeks = msg.weeks;
      const rate = productRate(product, room.baseRate, weeks);
      const amount = msg.amount;
      if (rate === null || !Number.isInteger(amount) || amount < product.min || (product.max > 0 && amount > product.max)) return fail(ErrorCode.badProduct);
      if ((p.deposits ?? []).length >= sv.max_accounts) return fail(ErrorCode.accountLimit);
      const inst = sv.institutions.get(product.bank);
      const fee = inst.member_fee && !p.coopMember ? inst.member_fee : 0;
      if (p.sol < amount + fee) return fail(ErrorCode.notEnoughSol);
      p.sol -= amount + fee;
      if (fee > 0) p.coopMember = true;
      p.depSeq += 1;
      const first = !(p.banksUsed ?? []).includes(product.bank);
      if (first) p.banksUsed = [...(p.banksUsed ?? []), product.bank];
      const account = {
        id: `D${p.depSeq}`,
        product: product.id,
        bank: product.bank,
        kind: product.kind,
        week,
        weeks,
        rate,
        principal: product.kind === 'deposit' ? amount : 0,
        amount: product.kind === 'savings' ? amount : 0,
        paidAt: product.kind === 'savings' ? [0] : [],
        missed: 0,
        incomeWeeks: 0,
        first,
      };
      p.deposits.push(account);
      result = { ...result, id: account.id, product: product.id, fee, sol: p.sol };
    } else if (msg.t === 'dep_close') {
      const a = (p.deposits ?? []).find((d) => d.id === msg.id);
      if (!a) return fail(ErrorCode.badAccount);
      const s = settle(sv, sv.products.get(a.product), a, week, dctx);
      p.deposits = p.deposits.filter((d) => d !== a);
      p.sol += s.net;
      earn(p, s.gross - s.tax);
      result = { ...result, id: a.id, product: a.product, ...s, sol: p.sol };
    } else {
      // 파킹통장: 넣기(+) · 빼기(-). 처음 넣으면 계좌를 연다.
      const amount = msg.amount;
      if (!Number.isInteger(amount) || amount === 0) return fail(ErrorCode.badProduct);
      const product = [...sv.products.values()].find((x) => x.kind === 'parking');
      let a = (p.deposits ?? []).find((d) => d.kind === 'parking');
      if (amount > 0) {
        if (p.sol < amount) return fail(ErrorCode.notEnoughSol);
        if (!a) {
          if ((p.deposits ?? []).length >= sv.max_accounts) return fail(ErrorCode.accountLimit);
          p.depSeq += 1;
          a = { id: `D${p.depSeq}`, product: product.id, bank: product.bank, kind: 'parking', week, weeks: 0, rate: productRate(product, room.baseRate, 0), principal: 0, amount: 0, paidAt: [], missed: 0, incomeWeeks: 0, first: false };
          p.deposits.push(a);
          if (!(p.banksUsed ?? []).includes(product.bank)) p.banksUsed = [...(p.banksUsed ?? []), product.bank];
        }
        p.sol -= amount;
        a.principal += amount;
      } else {
        if (!a || a.principal < -amount) return fail(ErrorCode.notEnoughSol);
        a.principal += amount;
        p.sol -= amount;
        if (a.principal === 0) p.deposits = p.deposits.filter((d) => d !== a);
      }
      result = { ...result, id: a.id, balance: a.principal, sol: p.sol };
    }
    send(ctx.ws, result);
    sendProfile(player);
    send(ctx.ws, { t: 'bank', ...bankWire(room, p) });
    rooms.save(room);
  }

  /**
   * 한 주 지나면 계좌마다: 파킹통장 이자(세후)를 붙이고, 파킹 금리를 새 기준금리로 고치고, 적금은 지갑에서 한 주 치를 넣고(모자라면 거름),
   * 급여 이체 우대를 세고, 만기가 된 예적금은 저절로 해지해 지갑으로. 돌려준 목록을 week 보고에 싣는다.
   */
  function tickDeposits(room, p, week) {
    if (!sv || !(p.deposits?.length > 0)) return [];
    const ctx = depositCtx(p);
    const matured = [];
    const minIncome = sv.bonuses?.income?.min_week_income ?? 0;
    for (const a of [...p.deposits]) {
      const product = sv.products.get(a.product);
      if (a.kind === 'parking') {
        a.principal += parkingWeek(sv, a, ctx);
        a.rate = productRate(product, room.baseRate, 0);
        continue;
      }
      const held = week - a.week;
      if ((p.income?.amount ?? 0) >= minIncome) a.incomeWeeks += 1;
      if (a.kind === 'savings' && held < a.weeks) {
        if (p.sol >= a.amount) {
          p.sol -= a.amount;
          a.paidAt.push(held);
        } else {
          a.missed += 1;
        }
      }
      if (held >= a.weeks) {
        const s = settle(sv, product, a, week, ctx);
        p.deposits = p.deposits.filter((d) => d !== a);
        p.sol += s.net;
        earn(p, s.gross - s.tax);
        matured.push({ id: a.id, product: a.product, name: product.name, ...s });
      }
    }
    return matured;
  }

  /** 금융기관이 문을 닫았다 (경제 이벤트): 그 기관 계좌를 모두 정리해 보호 한도까지 + 넘는 돈의 일부를 지갑으로. */
  function failInstitution(room, bankId) {
    if (!sv) return [];
    const week = weekOf(clock.day());
    const out = [];
    for (const p of room.profiles.values()) {
      const list = (p.deposits ?? []).filter((d) => d.bank === bankId);
      if (list.length === 0) continue;
      const r = failurePayout(sv, list, week);
      p.deposits = p.deposits.filter((d) => d.bank !== bankId);
      p.sol += r.paid;
      out.push({ uid: p.uid, ...r });
    }
    return out;
  }

  /** 동사무소 판단에 쓰는 이 사람(세대)의 상황. */
  function civicContext(room, profile) {
    const members = membersOf(room, profile);
    const income = incomeOf(room, profile);
    return {
      age: profile.age ?? 29,
      resident: !!profile.civic?.resident,
      married: members.length > 1,
      homes: homesOfUids(room, uidsOf(room, profile)).length,
      homesEver: members.some((p) => p.loans.some((l) => l.kind === 'mortgage')),
      income: annualIncome(income),
      weekIncome: income?.amount ?? 0,
      sol: profile.sol,
      liquid: profile.sol + members.reduce((a, p) => a + market.holdingsValue(p.stocks), 0),
      received: profile.civic?.received ?? {},
      week: weekOf(clock.day()),
    };
  }

  /** 프로필에 덧붙는 경제 정보 (profile 메시지). */
  function profileWire(room, profile) {
    const assets = room ? assetsOf(room, profile) : profile.sol;
    const debt = room ? debtOf(room, profile) : 0;
    const members = membersOf(room, profile);
    const partner = members.find((p) => p.uid !== profile.uid);
    const income = room ? incomeOf(room, profile) : profile.income;
    return {
      stocks: Object.fromEntries(Object.entries(profile.stocks).map(([id, h]) => [id, { ...h }])),
      trades: profile.trades.slice(-10),
      loans: profile.loans.map((l) => ({ ...l, weekly: weeklyInterest(l.principal, l.rate) })),
      credit: room ? creditOf(room, profile) : { score: data.bank.credit.start_score, grade: gradeOf(data.bank, data.bank.credit.start_score) },
      income: { week: income?.amount ?? 0, year: annualIncome(income) },
      worth: { assets, debt, net: assets - debt },
      civ: {
        age: profile.age ?? 29,
        resident: !!profile.civic?.resident,
        card: !!profile.civic?.card,
        partner: partner ? partner.slot : 0,
        household: profile.household ?? '',
        since: profile.household && room ? room.households.get(profile.household)?.since ?? 0 : 0,
        approvals: Object.fromEntries(Object.entries(profile.civic?.approvals ?? {}).map(([id, a]) => [id, { ...a }])),
      },
    };
  }

  // ---- 증권 ----

  function handleStock(ctx, msg, fail) {
    const { player } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const def = data.market.stocks.find((s) => s.id === msg.id);
    const qty = msg.qty;
    if (!def || !Number.isInteger(qty) || qty < 1 || qty > data.market.max_order_qty || (msg.side !== 'buy' && msg.side !== 'sell')) return fail(ErrorCode.badOrder);
    if (!market.isOpen()) return fail(ErrorCode.marketClosed);
    const price = market.price(def.id);
    const p = player.profile;
    const holding = p.stocks[def.id] ?? { q: 0, cost: 0 };
    let deal;
    if (msg.side === 'buy') {
      deal = buyCost(data.market, price, qty);
      if (p.sol < deal.total) return fail(ErrorCode.notEnoughSol);
      p.sol -= deal.total;
      holding.q += qty;
      holding.cost += deal.total;
    } else {
      if (holding.q < qty) return fail(ErrorCode.notEnoughShares);
      deal = sellProceeds(data.market, price, qty);
      p.sol += deal.total;
      holding.cost -= Math.round((holding.cost * qty) / holding.q);
      holding.q -= qty;
    }
    if (holding.q > 0) p.stocks[def.id] = holding;
    else delete p.stocks[def.id];
    p.trades.push({ id: def.id, side: msg.side, qty, price, amount: deal.total, day: clock.day() });
    if (p.trades.length > 20) p.trades.shift();
    send(ctx.ws, { t: 'stock_result', rid: msg.rid, id: def.id, side: msg.side, qty, price, amount: deal.total, fee: deal.fee, tax: deal.tax, sol: p.sol, holding: p.stocks[def.id] ?? { q: 0, cost: 0 } });
    sendProfile(player);
    ctx.room.saveDirty = true;
  }

  /** 1분마다 바뀐 시세를 모든 방에 알린다. */
  function broadcastMarket(changed) {
    const msg = { t: 'market_tick', minute: market.state.minute, open: market.isOpen(), source: market.state.source, q: changed ?? {} };
    for (const room of rooms.rooms.values()) room.broadcast(msg);
  }

  // ---- 아파트 ----

  const homesWire = (room) => ({
    index: room.aptIndex,
    owners: Object.fromEntries(Object.entries(room.homes).map(([id, h]) => [id, room.slotOfUid(h.owner) ?? 0])),
    bought: Object.fromEntries(Object.entries(room.homes).map(([id, h]) => [id, h.price])),
  });

  function handleHome(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const unit = data.units.find((u) => u.id === msg.unit);
    if (!unit) return fail(ErrorCode.badUnit);
    const p = player.profile;
    const price = unitPrice(data.realestate, unit, room.aptIndex);
    if (msg.t === 'apt_buy') {
      if (room.homes[unit.id]) return fail(ErrorCode.unitTaken);
      const loan = Number.isInteger(msg.loan) ? msg.loan : 0;
      if (loan < 0) return fail(ErrorCode.loanLimit);
      const cost = purchaseCost(data.realestate, price);
      let record = null;
      if (loan > 0 && msg.policy === 'didimdol') {
        // 디딤돌대출: 동사무소에서 받은 승인(기한·한도·고정금리) 안에서. DSR 대신 승인 때 소득·무주택을 봤다.
        const approval = p.civic?.approvals?.didimdol;
        if (!approval || approval.until < weekOf(clock.day())) return fail(ErrorCode.notEligible);
        if (price > approval.priceMax || loan > Math.min(approval.limit, mortgageLimit(approval.ltv, price))) return fail(ErrorCode.loanLimit);
        if (p.loans.length >= data.bank.max_loans) return fail(ErrorCode.loanLimit);
        record = { kind: 'mortgage', principal: loan, rate: approval.rate, unit: unit.id, product: 'didimdol', fixed: true };
      } else if (loan > 0) {
        if (loan > mortgageLimit(data.realestate.ltv, price)) return fail(ErrorCode.loanLimit);
        const { grade } = creditOf(room, p);
        const rate = rateFor(data.bank, room.baseRate, grade, 'mortgage');
        const householdLoans = membersOf(room, p).flatMap((m) => m.loans);
        if (!dsrOk(data.bank, incomeOf(room, p), householdLoans, { kind: 'mortgage', principal: loan, rate }) || p.loans.length >= data.bank.max_loans) return fail(ErrorCode.loanLimit);
        record = { kind: 'mortgage', principal: loan, rate, unit: unit.id, product: '', fixed: false };
      }
      if (p.sol + loan < cost.total) return fail(ErrorCode.notEnoughSol);
      if (record) {
        if (record.product === 'didimdol') delete p.civic.approvals.didimdol;
        p.loanSeq += 1;
        p.loans.push({ id: `L${p.loanSeq}`, since: clock.day(), ...record });
      }
      p.sol += loan - cost.total;
      room.homes[unit.id] = { owner: p.uid, price, day: clock.day() };
      send(ctx.ws, { t: 'apt_result', rid: msg.rid, kind: 'buy', unit: unit.id, price, tax: cost.tax, fee: cost.fee, loan, policy: record?.product ?? '', rate: record?.rate ?? 0, sol: p.sol });
    } else {
      // 세대원이 가진 집이면 팔 수 있다 (같은 지갑).
      if (!uidsOf(room, p).includes(room.homes[unit.id]?.owner)) return fail(ErrorCode.notYourUnit);
      const sale = saleProceeds(data.realestate, price);
      // 이 집을 담보로 빌린 돈부터 갚는다. 모자라면 남은 빚은 신용대출로 바뀐다.
      let cash = sale.total;
      for (const m of membersOf(room, p)) {
        for (const l of m.loans.filter((x) => x.unit === unit.id)) {
          const pay = Math.min(cash, l.principal);
          cash -= pay;
          l.principal -= pay;
          l.unit = '';
          l.kind = 'credit';
          l.product = '';
          l.fixed = false;
        }
        m.loans = m.loans.filter((l) => l.principal > 0);
      }
      p.sol += cash;
      delete room.homes[unit.id];
      send(ctx.ws, { t: 'apt_result', rid: msg.rid, kind: 'sell', unit: unit.id, price, fee: sale.fee, repaid: sale.total - cash, sol: p.sol });
    }
    sendProfile(player);
    room.broadcast({ t: 'homes', ...homesWire(room) });
    rooms.save(room);
  }

  // ---- 은행 ----

  function handleBank(ctx, msg, fail) {
    const { player, room } = ctx;
    const p = player.profile;
    if (msg.t === 'bank_quote') {
      send(ctx.ws, { t: 'bank', ...bankWire(room, p) });
      return;
    }
    if (!player.acceptRid(msg.rid)) return;
    if (msg.t === 'loan_take') {
      const amount = msg.amount;
      if (!Number.isInteger(amount) || amount < data.bank.min_loan) return fail(ErrorCode.badLoan);
      if (p.loans.length >= data.bank.max_loans) return fail(ErrorCode.loanLimit);
      let loan;
      if (msg.product === 'sunshine_youth') {
        // 햇살론유스: 동사무소 서민금융 창구에서만, 자격(나이·소득) 안에서, 고정금리.
        if (!deps.nearDesk(player, 'finance')) return fail(ErrorCode.notAtCivic);
        const program = data.programs.get('sunshine_youth');
        const c = civicContext(room, p);
        if (!eligibility(program, c).ok) return fail(ErrorCode.notEligible);
        const used = p.loans.filter((l) => l.product === 'sunshine_youth').reduce((a, l) => a + l.principal, 0);
        if (amount > program.limit - used) return fail(ErrorCode.loanLimit);
        loan = { kind: 'credit', principal: amount, rate: sunshineRate(program, c), unit: '', product: 'sunshine_youth', fixed: true };
      } else {
        const { grade } = creditOf(room, p);
        const income = incomeOf(room, p);
        const creditDebt = p.loans.filter((l) => l.kind === 'credit' && !l.product).reduce((a, l) => a + l.principal, 0);
        const rate = rateFor(data.bank, room.baseRate, grade, 'credit');
        if (amount > creditLimit(data.bank, grade, income, creditDebt)) return fail(ErrorCode.loanLimit);
        if (!dsrOk(data.bank, income, membersOf(room, p).flatMap((m) => m.loans), { kind: 'credit', principal: amount, rate })) return fail(ErrorCode.loanLimit);
        loan = { kind: 'credit', principal: amount, rate, unit: '', product: '', fixed: false };
      }
      p.loanSeq += 1;
      loan = { id: `L${p.loanSeq}`, since: clock.day(), ...loan };
      p.loans.push(loan);
      p.sol += amount;
      send(ctx.ws, { t: 'loan_result', rid: msg.rid, kind: 'take', loan: { ...loan, weekly: weeklyInterest(amount, loan.rate) }, sol: p.sol });
    } else {
      const loan = p.loans.find((l) => l.id === msg.id);
      const amount = msg.amount;
      if (!loan || !Number.isInteger(amount) || amount < 1) return fail(ErrorCode.badLoan);
      const pay = Math.min(amount, loan.principal);
      if (p.sol < pay) return fail(ErrorCode.notEnoughSol);
      p.sol -= pay;
      loan.principal -= pay;
      p.loans = p.loans.filter((l) => l.principal > 0);
      send(ctx.ws, { t: 'loan_result', rid: msg.rid, kind: 'repay', id: loan.id, paid: pay, left: loan.principal, sol: p.sol });
    }
    sendProfile(player);
    send(ctx.ws, { t: 'bank', ...bankWire(room, p) });
    room.saveDirty = true;
  }

  /**
   * 마을 시계로 한 주가 지나면: 집마다 월세, 대출마다 이자(변동금리는 새 신용점수로 다시 매겨서, 정책대출은 고정),
   * 청년월세 지원 지급, 소득 기록, 그리고 기준금리·집값 지수가 한 걸음. 오래 비웠던 마을은 최대 4주까지만 몰아서 계산한다.
   */
  function tickWeek(room) {
    const week = weekOf(clock.day());
    if (room.week === null || room.week === undefined) {
      room.week = week;
      room.saveDirty = true;
      return;
    }
    if (week <= room.week) return;
    const weeks = Math.min(4, week - room.week);
    room.week = week;
    const reports = new Map();
    const rentProgram = data.programs.get('youth_rent');
    for (let w = 0; w < weeks; w++) {
      for (const p of room.profiles.values()) {
        const r = reports.get(p.uid) ?? { rent: 0, paid: 0, capitalized: 0, missed: false, grant: 0, matured: [] };
        // 예적금: 이번 주 소득을 보고(급여 이체 우대), 적금 납입 · 파킹 이자 · 만기 해지 (v0.12).
        r.matured.push(...tickDeposits(room, p, week - weeks + w + 1));
        let rent = 0;
        for (const u of homesOfUids(room, [p.uid])) rent += weeklyRent(data.realestate, unitPrice(data.realestate, u, room.aptIndex));
        p.sol += rent;
        earn(p, rent);
        const got = p.civic?.received?.youth_rent;
        if (got?.weeksLeft > 0 && rentProgram) {
          p.sol += rentProgram.amount;
          got.weeksLeft -= 1;
          r.grant += rentProgram.amount;
        }
        const { grade } = creditOf(room, p);
        const charged = chargeWeek(data.bank, p, room.baseRate, grade);
        r.rent += rent;
        r.paid += charged.paid;
        r.capitalized += charged.capitalized;
        r.missed = r.missed || charged.missed;
        p.income.history.push(p.income.amount);
        if (p.income.history.length > 8) p.income.history.shift();
        p.income.amount = 0;
        for (const [id, a] of Object.entries(p.civic?.approvals ?? {})) if (a.until < week) delete p.civic.approvals[id];
        reports.set(p.uid, r);
      }
      room.baseRate = stepBaseRate(data.bank, room.baseRate, random);
      room.aptIndex = stepIndex(data.realestate, room.aptIndex, random);
    }
    // 마을톡 은행 알림 (끊겨 있는 사람도 다음에 들어오면 보인다).
    for (const [uid, r] of reports) {
      const profile = room.profiles.get(uid);
      if (profile) deps.onWeekReport?.(room, profile, { interest: r.paid, capitalized: r.capitalized, missed: r.missed, rent: r.rent, grant: r.grant, matured: r.matured });
    }
    for (const player of room.players.values()) {
      const r = reports.get(player.uid);
      if (!r) continue;
      sendTo(player, { t: 'week', week, rent: r.rent, interest: r.paid, capitalized: r.capitalized, missed: r.missed, grant: r.grant, matured: r.matured, base: room.baseRate, index: room.aptIndex, sol: player.profile.sol });
      sendProfile(player);
    }
    room.broadcast({ t: 'homes', ...homesWire(room) });
    rooms.save(room);
  }

  // ---- 동사무소 ----

  /** 동사무소 창구 정보: 전입·카드·세대, 프로그램마다 자격과 조건. */
  function civicWire(room, profile) {
    const c = civicContext(room, profile);
    const programs = civicRules.programs.map((program) => {
      const e = eligibility(program, c);
      const out = { id: program.id, ok: e.ok, reasons: e.reasons };
      if (program.kind === 'policy_mortgage') out.terms = didimdolTerms(program, c);
      if (program.kind === 'policy_credit') {
        const used = profile.loans.filter((l) => l.product === program.id).reduce((a, l) => a + l.principal, 0);
        out.terms = { rate: sunshineRate(program, c), limit: program.limit, left: Math.max(0, program.limit - used), fixed: true };
      }
      const got = profile.civic.received[program.id];
      if (got) out.got = { ...got };
      return out;
    });
    const members = membersOf(room, profile);
    return {
      resident: c.resident,
      movedIn: profile.civic.movedIn,
      age: c.age,
      married: c.married,
      partner: members.find((m) => m.uid !== profile.uid)?.slot ?? 0,
      income_year: c.income,
      homes: c.homes,
      card: profile.civic.card ? { ...profile.civic.card } : null,
      approvals: Object.fromEntries(Object.entries(profile.civic.approvals).map(([id, a]) => [id, { ...a }])),
      programs,
    };
  }

  function sendCivic(player, room) {
    sendTo(player, { t: 'civic', ...civicWire(room, player.profile) });
  }

  /** 서류 내용 (등본·가족관계증명서). */
  function documentOf(room, profile, kind) {
    const members = membersOf(room, profile);
    const homes = homesOfUids(room, uidsOf(room, profile)).map((u) => u.id);
    const address = homes.length ? `솔바람동 ${data.realestate.complex.short} ${homes[0]}호` : '솔바람동 섬마을 1길';
    if (kind === 'resident_copy') {
      return { kind, title: '주민등록표 등본', address, movedIn: profile.civic.movedIn, members: members.map((m) => ({ slot: m.slot, relation: m.uid === profile.uid ? '본인' : '배우자', age: m.age })) };
    }
    const partner = members.find((m) => m.uid !== profile.uid);
    return { kind, title: '가족관계증명서', self: profile.slot, spouse: partner?.slot ?? 0, since: profile.household ? room.households.get(profile.household)?.since ?? 0 : 0 };
  }

  /** 혼인신고 뒤 세대원 모두에게 프로필·동사무소 정보를 다시 보낸다. */
  function refreshHousehold(room, profile) {
    for (const m of membersOf(room, profile)) {
      const live = room.players.get(m.slot);
      if (live && live.uid === m.uid) sendProfile(live);
    }
  }

  /**
   * 동사무소 메시지: civic_info · civic_civil{service} · civic_apply{program} · marry_propose{to} · marry_answer{accept}.
   * 창구마다 그 직원 곁(service_range)에서만 한다.
   */
  function handleCivic(ctx, msg, fail) {
    const { player, room } = ctx;
    const p = player.profile;
    const week = weekOf(clock.day());
    if (msg.t === 'civic_info') {
      sendCivic(player, room);
      return;
    }
    if (!player.acceptRid(msg.rid)) return;
    if (msg.t === 'civic_civil') {
      const service = civicRules.civil.find((s) => s.id === msg.service);
      if (!service || service.id === 'marriage') return fail(ErrorCode.badProgram);
      if (!deps.nearDesk(player, 'civil')) return fail(ErrorCode.notAtCivic);
      if (p.sol < service.fee) return fail(ErrorCode.notEnoughSol);
      if (service.id === 'family_cert' && !p.household) return fail(ErrorCode.notEligible);
      if (service.id === 'move_in' && p.civic.resident) return fail(ErrorCode.notEligible);
      p.sol -= service.fee;
      let doc = null;
      if (service.id === 'move_in') {
        // 세대원도 함께 전입된다.
        for (const m of membersOf(room, p)) {
          m.civic.resident = true;
          m.civic.movedIn = clock.day();
        }
      } else {
        p.civic.docs += 1;
        doc = documentOf(room, p, service.id);
      }
      send(ctx.ws, { t: 'civic_result', rid: msg.rid, service: service.id, fee: service.fee, doc, sol: p.sol });
      refreshHousehold(room, p);
      sendCivic(player, room);
      rooms.save(room);
      return;
    }
    if (msg.t === 'civic_apply') {
      const program = data.programs.get(msg.program);
      if (!program || program.kind === 'policy_credit') return fail(ErrorCode.badProgram);
      if (!deps.nearDesk(player, program.desk)) return fail(ErrorCode.notAtCivic);
      const c = civicContext(room, p);
      if (!eligibility(program, c).ok) return fail(ErrorCode.notEligible);
      const result = { t: 'civic_result', rid: msg.rid, program: program.id };
      if (program.kind === 'grant_weekly') {
        p.civic.received[program.id] = { times: (p.civic.received[program.id]?.times ?? 0) + 1, lastWeek: week, weeksLeft: program.weeks };
        result.weekly = program.amount;
        result.weeks = program.weeks;
      } else if (program.kind === 'grant_once') {
        const got = p.civic.received[program.id] ?? { times: 0, lastWeek: -99, weeksLeft: 0 };
        p.civic.received[program.id] = { times: got.times + 1, lastWeek: week, weeksLeft: 0 };
        p.sol += program.amount;
        result.amount = program.amount;
      } else if (program.kind === 'card') {
        p.civic.card = { week, back: 0, total: 0 };
        p.civic.received[program.id] = { times: 1, lastWeek: week, weeksLeft: 0 };
      } else if (program.kind === 'policy_mortgage') {
        const terms = didimdolTerms(program, c);
        p.civic.approvals[program.id] = { rate: terms.rate, limit: terms.limit, priceMax: terms.priceMax, ltv: terms.ltv, until: week + (program.approval_weeks ?? 2) };
        result.approval = { ...p.civic.approvals[program.id] };
      }
      result.sol = p.sol;
      send(ctx.ws, result);
      refreshHousehold(room, p);
      sendCivic(player, room);
      rooms.save(room);
      return;
    }
    if (msg.t === 'marry_propose') {
      // 혼인신고: 두 사람 모두 민원 창구 곁에서. 한 사람이 신청하면 상대에게 묻는다.
      const other = Number.isInteger(msg.to) ? room.players.get(msg.to) : null;
      if (!other || other === player || !other.online) return fail(ErrorCode.noPartner);
      if (p.household || other.profile.household) return fail(ErrorCode.alreadyMarried);
      if (!deps.nearDesk(player, 'civil', 2.5) || !deps.nearDesk(other, 'civil', 2.5)) return fail(ErrorCode.notAtCivic);
      room.proposal = { from: player.id, to: other.id, at: deps.now() };
      send(ctx.ws, { t: 'civic_result', rid: msg.rid, service: 'marriage_asked', to: other.id, sol: p.sol });
      sendTo(other, { t: 'marry_proposal', from: player.id });
      return;
    }
    if (msg.t === 'marry_answer') {
      const prop = room.proposal;
      if (!prop || prop.to !== player.id || deps.now() - prop.at > 120000) return fail(ErrorCode.noPartner);
      const from = room.players.get(prop.from);
      room.proposal = null;
      if (!from || !from.online) return fail(ErrorCode.noPartner);
      if (!msg.accept) {
        sendTo(from, { t: 'marry_declined', by: player.id });
        send(ctx.ws, { t: 'civic_result', rid: msg.rid, service: 'marriage_declined', sol: p.sol });
        return;
      }
      if (p.household || from.profile.household) return fail(ErrorCode.alreadyMarried);
      if (!deps.nearDesk(player, 'civil', 2.5) || !deps.nearDesk(from, 'civil', 2.5)) return fail(ErrorCode.notAtCivic);
      // 두 지갑을 합치고 한 세대가 된다. 전입은 한 사람이라도 했으면 둘 다.
      room.householdSeq += 1;
      const id = `h${room.householdSeq}`;
      const sol = from.profile.sol + p.sol;
      const resident = from.profile.civic.resident || p.civic.resident;
      room.linkHousehold(id, [from.uid, player.uid], sol, clock.day());
      for (const m of [from.profile, p]) {
        if (resident && !m.civic.resident) {
          m.civic.resident = true;
          m.civic.movedIn = clock.day();
        }
      }
      room.broadcast({ t: 'household', id, members: [from.id, player.id], since: clock.day(), sol });
      send(ctx.ws, { t: 'civic_result', rid: msg.rid, service: 'marriage', partner: from.id, sol });
      for (const pl of [from, player]) {
        sendProfile(pl);
        sendCivic(pl, room);
      }
      rooms.save(room);
    }
  }

  /** 천안사랑카드 캐시백 (상점·상인·공항에서 산 뒤). 돌려준 솔. */
  function cashback(room, player, spent) {
    const program = data.programs.get('local_card');
    const card = player.profile.civic?.card;
    if (!program || !card || spent <= 0) return 0;
    const week = weekOf(clock.day());
    const back = cardCashback(program, card, week, spent);
    if (card.week !== week) {
      card.week = week;
      card.back = 0;
    }
    if (back <= 0) return 0;
    card.back += back;
    card.total += back;
    player.profile.sol += back;
    return back;
  }

  return {
    earn,
    membersOf,
    debtOf,
    assetsOf,
    creditOf,
    incomeOf,
    bankWire,
    profileWire,
    homesWire,
    handleStock,
    broadcastMarket,
    handleHome,
    handleBank,
    handleSavings,
    savingsWire,
    failInstitution,
    tickWeek,
    handleCivic,
    civicWire,
    cashback,
  };
}
