// 마을 경제 서비스: 증권(주문), 아파트(사고팔기·월세), 은행(대출·주간 이자·신용), 식당(영업·주문·요리 판정), 채집.
// server.js 가 메시지를 넘기고, 방 상태·소켓 도우미는 deps 로 받는다. 판정은 전부 서버가 한다.
import { ErrorCode } from './protocol.js';
import { buyCost, sellProceeds } from './market.js';
import { homesValue, purchaseCost, saleProceeds, stepIndex, unitPrice, weeklyRent } from './realestate.js';
import { annualIncome, chargeWeek, creditLimit, creditScore, dsrOk, gradeOf, mortgageLimit, rateFor, stepBaseRate, weekOf, weeklyInterest } from './bank.js';
import { capacity, chooseOrder, cookQuality, menuOf, minCookMs, pantryOf, payFor, ratingOf, starsFor, tasteMatch, tierOf, updateRegular } from './restaurant.js';
import { addItem, countWhere, removeWhere } from './inventory.js';

/** 번 돈 기록 (대출 한도·신용점수의 소득). */
export function earn(profile, amount) {
  if (!profile.income) profile.income = { amount: 0, history: [] };
  if (amount > 0) profile.income.amount += amount;
}

export function createEconomy(deps) {
  const { data, cfg, clock, random, now, market, send, sendTo, sendProfile, sendInventory, rooms } = deps;
  const rest = data.restaurant;
  const steps = data.cookSteps;

  // ---- 자산 · 신용 ----

  const debtOf = (profile) => profile.loans.reduce((a, l) => a + l.principal, 0);
  const homesOf = (room, uid) => data.units.filter((u) => room.homes[u.id]?.owner === uid);
  const assetsOf = (room, profile) => profile.sol + market.holdingsValue(profile.stocks) + homesValue(data.realestate, data.units, room.homes, profile.uid, room.aptIndex);

  function creditOf(room, profile) {
    const score = creditScore(data.bank, { credit: profile.credit, income: profile.income, debt: debtOf(profile), assets: assetsOf(room, profile) });
    return { score, grade: gradeOf(data.bank, score) };
  }

  /** 은행 창구에 보이는 것: 신용·금리·한도·내 대출. */
  function bankWire(room, profile) {
    const { score, grade } = creditOf(room, profile);
    const creditDebt = profile.loans.filter((l) => l.kind === 'credit').reduce((a, l) => a + l.principal, 0);
    return {
      base: room.baseRate,
      score,
      grade,
      rate_credit: rateFor(data.bank, room.baseRate, grade, 'credit'),
      rate_mortgage: rateFor(data.bank, room.baseRate, grade, 'mortgage'),
      credit_limit: creditLimit(data.bank, grade, profile.income, creditDebt),
      ltv: data.realestate.ltv,
      dsr: data.bank.dsr,
      income_year: annualIncome(profile.income),
      income_week: profile.income?.amount ?? 0,
      week: weekOf(clock.day()),
      loans: profile.loans.map((l) => ({ ...l, weekly: weeklyInterest(l.principal, l.rate) })),
    };
  }

  /** 프로필에 덧붙는 경제 정보 (profile 메시지). */
  function profileWire(room, profile) {
    const assets = room ? assetsOf(room, profile) : profile.sol;
    const debt = debtOf(profile);
    return {
      stocks: Object.fromEntries(Object.entries(profile.stocks).map(([id, h]) => [id, { ...h }])),
      trades: profile.trades.slice(-10),
      loans: profile.loans.map((l) => ({ ...l, weekly: weeklyInterest(l.principal, l.rate) })),
      credit: room ? creditOf(room, profile) : { score: data.bank.credit.start_score, grade: gradeOf(data.bank, data.bank.credit.start_score) },
      income: { week: profile.income?.amount ?? 0, year: annualIncome(profile.income) },
      worth: { assets, debt, net: assets - debt },
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
      if (loan < 0 || loan > mortgageLimit(data.realestate.ltv, price)) return fail(ErrorCode.loanLimit);
      const cost = purchaseCost(data.realestate, price);
      const { grade } = creditOf(room, p);
      const rate = rateFor(data.bank, room.baseRate, grade, 'mortgage');
      if (loan > 0 && (!dsrOk(data.bank, p.income, p.loans, { kind: 'mortgage', principal: loan, rate }) || p.loans.length >= data.bank.max_loans)) return fail(ErrorCode.loanLimit);
      if (p.sol + loan < cost.total) return fail(ErrorCode.notEnoughSol);
      if (loan > 0) {
        p.loanSeq += 1;
        p.loans.push({ id: `L${p.loanSeq}`, kind: 'mortgage', principal: loan, rate, unit: unit.id, since: clock.day() });
      }
      p.sol += loan - cost.total;
      room.homes[unit.id] = { owner: p.uid, price, day: clock.day() };
      send(ctx.ws, { t: 'apt_result', rid: msg.rid, kind: 'buy', unit: unit.id, price, tax: cost.tax, fee: cost.fee, loan, sol: p.sol });
    } else {
      if (room.homes[unit.id]?.owner !== p.uid) return fail(ErrorCode.notYourUnit);
      const sale = saleProceeds(data.realestate, price);
      // 이 집을 담보로 빌린 돈부터 갚는다. 모자라면 남은 빚은 신용대출로 바뀐다.
      let cash = sale.total;
      for (const l of p.loans.filter((x) => x.unit === unit.id)) {
        const pay = Math.min(cash, l.principal);
        cash -= pay;
        l.principal -= pay;
        l.unit = '';
        l.kind = 'credit';
      }
      p.loans = p.loans.filter((l) => l.principal > 0);
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
      const { grade } = creditOf(room, p);
      const creditDebt = p.loans.filter((l) => l.kind === 'credit').reduce((a, l) => a + l.principal, 0);
      const rate = rateFor(data.bank, room.baseRate, grade, 'credit');
      if (amount > creditLimit(data.bank, grade, p.income, creditDebt) || p.loans.length >= data.bank.max_loans) return fail(ErrorCode.loanLimit);
      if (!dsrOk(data.bank, p.income, p.loans, { kind: 'credit', principal: amount, rate })) return fail(ErrorCode.loanLimit);
      p.loanSeq += 1;
      const loan = { id: `L${p.loanSeq}`, kind: 'credit', principal: amount, rate, unit: '', since: clock.day() };
      p.loans.push(loan);
      p.sol += amount;
      send(ctx.ws, { t: 'loan_result', rid: msg.rid, kind: 'take', loan: { ...loan, weekly: weeklyInterest(amount, rate) }, sol: p.sol });
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
   * 마을 시계로 한 주가 지나면: 집마다 월세, 대출마다 이자(새 신용점수로 금리를 다시 매겨서), 소득 기록,
   * 그리고 기준금리·집값 지수가 한 걸음. 오래 비웠던 마을은 최대 4주까지만 몰아서 계산한다.
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
    for (let w = 0; w < weeks; w++) {
      for (const p of room.profiles.values()) {
        const r = reports.get(p.uid) ?? { rent: 0, paid: 0, capitalized: 0, missed: false };
        let rent = 0;
        for (const u of homesOf(room, p.uid)) rent += weeklyRent(data.realestate, unitPrice(data.realestate, u, room.aptIndex));
        p.sol += rent;
        earn(p, rent);
        const { grade } = creditOf(room, p);
        const charged = chargeWeek(data.bank, p, room.baseRate, grade);
        r.rent += rent;
        r.paid += charged.paid;
        r.capitalized += charged.capitalized;
        r.missed = r.missed || charged.missed;
        p.income.history.push(p.income.amount);
        if (p.income.history.length > 8) p.income.history.shift();
        p.income.amount = 0;
        reports.set(p.uid, r);
      }
      room.baseRate = stepBaseRate(data.bank, room.baseRate, random);
      room.aptIndex = stepIndex(data.realestate, room.aptIndex, random);
    }
    for (const player of room.players.values()) {
      const r = reports.get(player.uid);
      if (!r) continue;
      sendTo(player, { t: 'week', week, rent: r.rent, interest: r.paid, capitalized: r.capitalized, missed: r.missed, base: room.baseRate, index: room.aptIndex, sol: player.profile.sol });
      sendProfile(player);
    }
    room.broadcast({ t: 'homes', ...homesWire(room) });
    rooms.save(room);
  }

  // ---- 식당 ----

  const ratingOfRoom = (room) => ratingOf(rest, room.restaurant.history);
  const ownerOf = (room) => (room.shift ? room.players.get(room.shift.owner) : null);
  /** 문을 연 사람 가방 재료 − 이미 주문에 떼어 둔 재료. */
  function available(room) {
    const owner = ownerOf(room);
    const avail = owner ? pantryOf(owner.slots) : {};
    for (const [id, n] of Object.entries(room.shift?.reserved ?? {})) avail[id] = (avail[id] ?? 0) - n;
    return avail;
  }

  function restWire(room) {
    const rating = ratingOfRoom(room);
    const tier = tierOf(rest, rating);
    const shift = room.shift;
    const t = now();
    const regulars = {};
    for (const [c, rec] of Object.entries(room.restaurant.regulars)) if (rec.regular) regulars[c] = rec.dish;
    return {
      open: !!shift,
      owner: shift?.owner ?? 0,
      rating,
      tier,
      served: room.restaurant.served,
      revenue: room.restaurant.revenue,
      regulars,
      capacity: shift ? capacity(menuOf(data.recipes, tier), available(room), data) : 0,
      shift: shift ? { served: shift.served, revenue: shift.revenue } : null,
      orders: shift
        ? [...shift.orders.values()].map((o) => ({ id: o.id, customer: o.customer, dish: o.dish, seat: o.seat, left: Math.max(0, o.at + o.patience - t), patience: o.patience, cooking: o.cookStart !== null, regular: o.regular }))
        : [],
    };
  }

  const broadcastRest = (room) => room.broadcast({ t: 'rest', ...restWire(room) });

  function closeShift(room, reason) {
    if (!room.shift) return;
    room.shift = null;
    room.broadcast({ t: 'rest_closed', reason });
    broadcastRest(room);
    room.saveDirty = true;
  }

  function handleRestaurant(ctx, msg, fail) {
    const { player, room } = ctx;
    const t = now();
    const shift = room.shift;
    if (msg.t === 'rest_open') {
      if (!player.acceptRid(msg.rid)) return;
      if (Math.hypot(player.x - rest.counter.x, player.z - rest.counter.z) > rest.open_range + 0.5) return fail(ErrorCode.notAtRestaurant);
      if (shift && shift.owner !== player.id) return fail(ErrorCode.restBusy);
      if (!shift) {
        room.shift = { owner: player.id, openedAt: t, nextSpawnAt: t + rest.first_customer_s * 1000 * cfg.restSpawnScale, lastActivity: t, orders: new Map(), seq: 0, reserved: {}, served: 0, revenue: 0 };
      }
      send(ctx.ws, { t: 'rest_opened', rid: msg.rid });
      broadcastRest(room);
      return;
    }
    if (!shift) return fail(ErrorCode.restClosed);
    if (shift.owner !== player.id) return fail(ErrorCode.restBusy);
    if (msg.t === 'rest_close') {
      closeShift(room, 'closed');
      return;
    }
    const order = typeof msg.order === 'string' ? shift.orders.get(msg.order) : null;
    if (!order) return fail(ErrorCode.orderGone);
    const recipe = data.recipeById.get(order.dish);
    if (msg.t === 'rest_cook') {
      if (order.cookStart === null) order.cookStart = t;
      broadcastRest(room);
      return;
    }
    // rest_serve: 요리를 냈다.
    if (!player.acceptRid(msg.rid)) return;
    if (order.cookStart === null || t - order.cookStart < minCookMs(recipe, steps) * 0.9) return fail(ErrorCode.cookTooFast);
    // 떼어 둔 재료를 가방에서 꺼낸다 (그새 팔았으면 주문이 취소된다).
    for (const [id, n] of Object.entries(order.used)) {
      if (countWhere(player.slots, (x) => x === id) < n) {
        dropOrder(room, order, 'missing');
        return fail(ErrorCode.missingIngredient);
      }
    }
    for (const [id, n] of Object.entries(order.used)) removeWhere(player.slots, (x) => x === id, n);
    release(shift, order);
    shift.orders.delete(order.id);
    const customer = data.customers.get(order.customer);
    const quality = cookQuality(recipe, steps, msg.taps);
    const taste = tasteMatch(customer, recipe);
    const timeLeft = (order.at + order.patience - t) / order.patience;
    const stars = starsFor(rest, { quality, taste, timeLeft, mbti: customer.mbti });
    const pay = payFor(rest, recipe, stars, order.regular);
    player.profile.sol += pay;
    earn(player.profile, pay);
    room.restaurant.history.push(stars);
    if (room.restaurant.history.length > 100) room.restaurant.history.shift();
    room.restaurant.served += 1;
    room.restaurant.revenue += pay;
    shift.served += 1;
    shift.revenue += pay;
    shift.lastActivity = t;
    const reg = updateRegular(rest, room.restaurant.regulars[order.customer], order.dish, stars);
    room.restaurant.regulars[order.customer] = reg.rec;
    send(ctx.ws, { t: 'rest_result', rid: msg.rid, order: order.id, stars, pay, quality: Math.round(quality * 100) / 100, taste: Math.round(taste * 100) / 100, sol: player.profile.sol });
    room.broadcast({ t: 'rest_served', order: order.id, customer: order.customer, dish: order.dish, stars, pay, regular: reg.rec.regular, became: reg.became, lost: reg.lost, by: player.id });
    sendInventory(player);
    sendProfile(player);
    broadcastRest(room);
    room.saveDirty = true;
  }

  function release(shift, order) {
    for (const [id, n] of Object.entries(order.used)) {
      shift.reserved[id] = (shift.reserved[id] ?? 0) - n;
      if (shift.reserved[id] <= 0) delete shift.reserved[id];
    }
  }

  /** 손님이 떠났다 (기다리다 지침 / 재료가 사라짐): 별 하나, 단골이면 풀릴 수도. */
  function dropOrder(room, order, reason) {
    const shift = room.shift;
    release(shift, order);
    shift.orders.delete(order.id);
    room.restaurant.history.push(1);
    if (room.restaurant.history.length > 100) room.restaurant.history.shift();
    const reg = updateRegular(rest, room.restaurant.regulars[order.customer], order.dish, 1);
    room.restaurant.regulars[order.customer] = reg.rec;
    room.broadcast({ t: 'rest_left', order: order.id, customer: order.customer, dish: order.dish, reason, lost: reg.lost });
    broadcastRest(room);
    room.saveDirty = true;
  }

  /** 1초마다: 주인이 떠났으면 닫기, 지친 손님 보내기, 새 손님 받기 (재료로 만들 수 있는 요리만). */
  function tickRestaurant(room) {
    const shift = room.shift;
    if (!shift) return;
    const t = now();
    const owner = ownerOf(room);
    if (!owner || !owner.online) return closeShift(room, 'owner_left');
    for (const o of [...shift.orders.values()]) if (t > o.at + o.patience) dropOrder(room, o, 'late');
    if (shift.orders.size === 0 && t - shift.lastActivity > rest.idle_close_s * 1000) return closeShift(room, 'idle');
    if (t < shift.nextSpawnAt || shift.orders.size >= rest.max_customers) return;
    const [lo, hi] = rest.spawn_every_s;
    shift.nextSpawnAt = t + (lo + random() * (hi - lo)) * 1000 * cfg.restSpawnScale;
    const seated = new Set([...shift.orders.values()].map((o) => o.customer));
    const freeSeats = rest.seats.map((_, i) => i).filter((i) => ![...shift.orders.values()].some((o) => o.seat === i));
    if (freeSeats.length === 0) return;
    const menu = menuOf(data.recipes, tierOf(rest, ratingOfRoom(room)));
    const avail = available(room);
    const pool = [...data.customers.values()].filter((c) => !seated.has(c.id));
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [pool[i], pool[j]] = [pool[j], pool[i]];
    }
    for (const c of pool) {
      const rec = room.restaurant.regulars[c.id];
      const pick = chooseOrder({ menu, avail, data, taste: c, regularDish: rec?.regular ? rec.dish : null, random });
      if (!pick) continue;
      shift.seq += 1;
      const seat = freeSeats[Math.floor(random() * freeSeats.length)];
      const order = { id: `o${shift.seq}`, customer: c.id, dish: pick.recipe.id, seat, at: t, patience: rest.patience_s[pick.recipe.tier] * 1000, cookStart: null, used: pick.used, regular: pick.regular };
      for (const [id, n] of Object.entries(pick.used)) shift.reserved[id] = (shift.reserved[id] ?? 0) + n;
      shift.orders.set(order.id, order);
      shift.lastActivity = t;
      room.broadcast({ t: 'rest_order', order: order.id, customer: c.id, dish: order.dish, seat, regular: order.regular });
      broadcastRest(room);
      return;
    }
    // 아무도 시킬 게 없다 = 재료가 떨어졌다. 남은 손님까지 다 대접하면 문을 닫는다.
    if (shift.orders.size === 0) closeShift(room, 'no_ingredients');
  }

  /** 시연·테스트용: 처음 별점 기록. */
  function seedRestaurant(room) {
    if (!cfg.restStartHistory || room.restaurant.history.length > 0) return;
    room.restaurant.history = cfg.restStartHistory.split(',').map(Number).filter((s) => Number.isInteger(s) && s >= 1 && s <= 5);
  }

  return { earn, debtOf, assetsOf, creditOf, bankWire, profileWire, homesWire, restWire, handleStock, broadcastMarket, handleHome, handleBank, tickWeek, handleRestaurant, tickRestaurant, seedRestaurant, closeShift, addItem };
}
