// 솔바람 식당 영업 (서버 권위). 계산은 restaurant.js 의 순수 함수.
// v0.9 같이 하기: 문을 연 사람 말고도 카운터 곁에서 "같이 일하기"(rest_join)로 직원이 될 수 있다.
//   · 재료: 직원 모두의 가방을 합친 것으로 주문을 받는다 (재료 분담).
//   · 요리 분담: 요리 동작(썰기·굽기·담기…)을 하나씩 맡아(rest_cook) 동시에 할 수 있다 — 둘이면 동작을 나눠 훨씬 빨리 낸다.
//     동작마다 다 하면(rest_step) 서버에 쌓이고, 마지막 동작이 들어오는 순간 판정한다.
//   · 직원이 둘 이상이면 손님이 1.25배 오래 기다려 주고 더 자주 오며, 두 사람이 나눠 만든 요리는 판정 창이 15% 넓고(서로 거들어 덜 서두른다)
//     팀 보너스 10% 를 더 받아 나눠 가진다.
import { ErrorCode } from './protocol.js';
import { capacity, chooseOrder, cookQuality, stepMinMs, menuOf, pantryOf, payFor, ratingOf, starsFor, tasteMatch, tierOf, updateRegular } from './restaurant.js';
import { countWhere, removeWhere } from './inventory.js';
import { earn } from './economy.js';
import { bump } from './progress.js';

export { stepMinMs };

/** 판정 창을 넓힌 동작 표 (같이 만들 때). */
export function lenientSteps(steps, factor) {
  if (factor === 1) return steps;
  const out = {};
  for (const [id, s] of Object.entries(steps)) out[id] = s.window_ms ? { ...s, window_ms: s.window_ms * factor } : { ...s, taps: s.taps ? Math.ceil(s.taps / factor) : s.taps };
  return out;
}

export const TEAM = { patience: 1.25, spawn: 0.8, window: 1.15, bonus: 0.1 };

export function createKitchen(deps) {
  const { data, cfg, random, now, send, sendTo, sendProfile, sendInventory } = deps;
  /** 지금 계절·시각 (v0.12 제철·시간 메뉴). */
  const when = () => deps.when?.() ?? {};
  const rest = data.restaurant;
  const steps = data.cookSteps;

  const ratingOfRoom = (room) => ratingOf(rest, room.restaurant.history);
  const staffOf = (room) => (room.shift ? [...room.shift.staff].map((id) => room.players.get(id)).filter((p) => p && p.online) : []);
  const nearCounter = (player) => Math.hypot(player.x - rest.counter.x, player.z - rest.counter.z) <= rest.open_range + 0.5;

  /** 식당 창고(v13) + 직원 모두의 가방 재료 − 이미 주문에 떼어 둔 재료. */
  function available(room) {
    const avail = { ...(room.restaurant.storage ?? {}) };
    for (const p of staffOf(room)) for (const [id, n] of Object.entries(pantryOf(p.slots))) avail[id] = (avail[id] ?? 0) + n;
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
      staff: shift ? [...shift.staff] : [],
      team: shift ? staffOf(room).length >= 2 : false,
      rating,
      tier,
      served: room.restaurant.served,
      revenue: room.restaurant.revenue,
      regulars,
      capacity: shift ? capacity(menuOf(data.recipes, tier, when()), available(room), data) : 0,
      store: { ...(room.restaurant.storage ?? {}) },
      shift: shift ? { served: shift.served, revenue: shift.revenue } : null,
      orders: shift
        ? [...shift.orders.values()].map((o) => ({
            id: o.id,
            customer: o.customer,
            dish: o.dish,
            seat: o.seat,
            left: Math.max(0, o.at + o.patience - t),
            patience: o.patience,
            cooking: o.steps.some((s) => s.by),
            regular: o.regular,
            steps: o.steps.map((s) => [s.by, s.taps ? 1 : 0]),
            used: o.used,
          }))
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
    for (const s of order.steps) if (s.by && !s.taps) room.broadcast({ t: 'act', id: s.by, kind: 'cook_end' });
    broadcastRest(room);
    room.saveDirty = true;
  }

  /** 떼어 둔 재료를 꺼낸다: 식당 창고(v13)부터, 그다음 직원 가방 (만든 사람부터). 모자라면 null (아무것도 꺼내지 않는다). */
  function takeIngredients(room, order, contributors) {
    const staff = staffOf(room);
    const ordered = [...contributors.map((id) => room.players.get(id)).filter(Boolean), ...staff.filter((p) => !contributors.includes(p.id))];
    const storage = room.restaurant.storage ?? {};
    for (const [id, n] of Object.entries(order.used)) {
      const have = (storage[id] ?? 0) + ordered.reduce((a, p) => a + countWhere(p.slots, (x) => x === id), 0);
      if (have < n) return null;
    }
    const touched = new Set();
    for (const [id, n] of Object.entries(order.used)) {
      let need = n;
      const fromStore = Math.min(need, storage[id] ?? 0);
      if (fromStore > 0) {
        storage[id] -= fromStore;
        if (storage[id] <= 0) delete storage[id];
        need -= fromStore;
      }
      for (const p of ordered) {
        if (need <= 0) break;
        const take = Math.min(need, countWhere(p.slots, (x) => x === id));
        if (take > 0) {
          removeWhere(p.slots, (x) => x === id, take);
          need -= take;
          touched.add(p);
        }
      }
    }
    return [...touched];
  }

  /** 동작이 다 들어온 주문을 판정한다. */
  function finishOrder(room, order, t, lastRid, lastBy) {
    const shift = room.shift;
    const recipe = data.recipeById.get(order.dish);
    const contributors = [...new Set(order.steps.map((s) => s.by))];
    const touched = takeIngredients(room, order, contributors);
    if (!touched) {
      dropOrder(room, order, 'missing');
      return;
    }
    release(shift, order);
    shift.orders.delete(order.id);
    const customer = data.customers.get(order.customer);
    const team = contributors.length >= 2;
    const quality = cookQuality(recipe, lenientSteps(steps, team ? TEAM.window : 1), order.steps.map((s) => s.taps));
    const taste = tasteMatch(customer, recipe);
    const timeLeft = (order.at + order.patience - t) / order.patience;
    const stars = starsFor(rest, { quality, taste, timeLeft, mbti: customer.mbti });
    const pay = Math.round((payFor(rest, recipe, stars, order.regular) * (team ? 1 + TEAM.bonus : 1)) / 100) * 100;
    // 같이 만든 사람들이 나눠 갖는다 (혼인한 세대면 어차피 한 지갑).
    const share = Math.floor(pay / contributors.length / 10) * 10;
    for (const id of contributors) {
      const p = room.players.get(id);
      if (!p) continue;
      p.profile.sol += share;
      earn(p.profile, share);
      bump(p.profile, 'serve');
    }
    room.restaurant.history.push(stars);
    if (room.restaurant.history.length > 100) room.restaurant.history.shift();
    room.restaurant.served += 1;
    room.restaurant.revenue += pay;
    shift.served += 1;
    shift.revenue += pay;
    shift.lastActivity = t;
    const reg = updateRegular(rest, room.restaurant.regulars[order.customer], order.dish, stars);
    room.restaurant.regulars[order.customer] = reg.rec;
    for (const id of contributors) {
      const p = room.players.get(id);
      if (!p) continue;
      sendTo(p, { t: 'rest_result', rid: id === lastBy ? lastRid : null, order: order.id, stars, pay, share, team, quality: Math.round(quality * 100) / 100, taste: Math.round(taste * 100) / 100, sol: p.profile.sol });
      sendProfile(p);
    }
    for (const p of touched) sendInventory(p);
    room.broadcast({ t: 'rest_served', order: order.id, customer: order.customer, dish: order.dish, stars, pay, team: contributors.length, regular: reg.rec.regular, became: reg.became, lost: reg.lost, by: lastBy });
    broadcastRest(room);
    room.saveDirty = true;
  }

  function handleRestaurant(ctx, msg, fail) {
    const { player, room } = ctx;
    const t = now();
    const shift = room.shift;
    if (msg.t === 'rest_open') {
      if (!player.acceptRid(msg.rid)) return;
      if (!nearCounter(player)) return fail(ErrorCode.notAtRestaurant);
      if (shift && !shift.staff.has(player.id)) return fail(ErrorCode.restBusy);
      if (!shift) {
        room.shift = { owner: player.id, staff: new Set([player.id]), openedAt: t, nextSpawnAt: t + rest.first_customer_s * 1000 * cfg.restSpawnScale, lastActivity: t, orders: new Map(), seq: 0, reserved: {}, served: 0, revenue: 0 };
      }
      send(ctx.ws, { t: 'rest_opened', rid: msg.rid });
      broadcastRest(room);
      return;
    }
    if (!shift) return fail(ErrorCode.restClosed);
    if (msg.t === 'rest_join') {
      if (!player.acceptRid(msg.rid)) return;
      if (!nearCounter(player)) return fail(ErrorCode.notAtRestaurant);
      shift.staff.add(player.id);
      shift.lastActivity = t;
      send(ctx.ws, { t: 'rest_joined', rid: msg.rid });
      room.broadcast({ t: 'rest_staff', id: player.id, joined: true });
      broadcastRest(room);
      return;
    }
    if (!shift.staff.has(player.id)) return fail(ErrorCode.notStaff);
    if (msg.t === 'rest_close') {
      // 주인이 닫으면 문을 닫고, 직원은 그만두기만 한다.
      if (player.id === shift.owner) closeShift(room, 'closed');
      else leaveStaff(room, player);
      return;
    }
    const order = typeof msg.order === 'string' ? shift.orders.get(msg.order) : null;
    if (!order) return fail(ErrorCode.orderGone);
    const recipe = data.recipeById.get(order.dish);
    const index = msg.step;
    if (!Number.isInteger(index) || index < 0 || index >= order.steps.length) return fail(ErrorCode.badMessage);
    const st = order.steps[index];
    const def = steps[recipe.steps[index]];
    if (msg.t === 'rest_cook') {
      // 동작 하나 맡기: 아무도 안 맡았거나 내가 맡은 것만.
      if (!player.acceptRid(msg.rid)) return;
      if (st.taps || (st.by && st.by !== player.id)) return fail(ErrorCode.stepTaken);
      st.by = player.id;
      st.start = t;
      shift.lastActivity = t;
      send(ctx.ws, { t: 'rest_claim', rid: msg.rid, order: order.id, step: index });
      room.broadcast({ t: 'act', id: player.id, kind: 'cook', e: def.anim, tool: def.tool ?? '' }, player.id);
      broadcastRest(room);
      return;
    }
    // rest_step: 맡은 동작을 다 했다.
    if (!player.acceptRid(msg.rid)) return;
    if (st.by !== player.id || st.taps) return fail(ErrorCode.stepTaken);
    if (t - st.start < stepMinMs(def) * 0.9) return fail(ErrorCode.cookTooFast);
    st.taps = Array.isArray(msg.taps) ? msg.taps.slice(0, 64) : [];
    shift.lastActivity = t;
    room.broadcast({ t: 'act', id: player.id, kind: 'cook_end' }, player.id);
    if (order.steps.every((s) => s.taps)) finishOrder(room, order, t, msg.rid, player.id);
    else {
      send(ctx.ws, { t: 'rest_stepped', rid: msg.rid, order: order.id, step: index });
      broadcastRest(room);
    }
  }

  function leaveStaff(room, player) {
    const shift = room.shift;
    if (!shift) return;
    shift.staff.delete(player.id);
    // 맡았다가 못 끝낸 동작은 놓는다 (다른 사람이 맡을 수 있게).
    for (const o of shift.orders.values()) for (const s of o.steps) if (s.by === player.id && !s.taps) s.by = 0;
    room.broadcast({ t: 'rest_staff', id: player.id, joined: false });
    broadcastRest(room);
  }

  /** 1초마다: 주인이 떠났으면 다른 직원에게 넘기거나 닫기, 지친 손님 보내기, 새 손님 받기 (재료로 만들 수 있는 요리만). */
  function tickRestaurant(room) {
    const shift = room.shift;
    if (!shift) return;
    const t = now();
    for (const id of [...shift.staff]) {
      const p = room.players.get(id);
      if (!p || !p.online) leaveStaff(room, { id });
    }
    if (shift.staff.size === 0) return closeShift(room, 'owner_left');
    if (!shift.staff.has(shift.owner)) {
      shift.owner = [...shift.staff][0];
      broadcastRest(room);
    }
    for (const o of [...shift.orders.values()]) if (t > o.at + o.patience) dropOrder(room, o, 'late');
    if (shift.orders.size === 0 && t - shift.lastActivity > rest.idle_close_s * 1000) return closeShift(room, 'idle');
    if (t < shift.nextSpawnAt || shift.orders.size >= rest.max_customers) return;
    const team = staffOf(room).length >= 2;
    const [lo, hi] = rest.spawn_every_s;
    shift.nextSpawnAt = t + (lo + random() * (hi - lo)) * 1000 * cfg.restSpawnScale * (team ? TEAM.spawn : 1);
    const seated = new Set([...shift.orders.values()].map((o) => o.customer));
    const freeSeats = rest.seats.map((_, i) => i).filter((i) => ![...shift.orders.values()].some((o) => o.seat === i));
    if (freeSeats.length === 0) return;
    const menu = menuOf(data.recipes, tierOf(rest, ratingOfRoom(room)), when());
    const avail = available(room);
    const pool = [...data.customers.values()].filter((c) => !seated.has(c.id));
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [pool[i], pool[j]] = [pool[j], pool[i]];
    }
    for (const c of pool) {
      const rec = room.restaurant.regulars[c.id];
      const pick = chooseOrder({ menu, avail, data, taste: c, regularDish: rec?.regular ? rec.dish : null, random, seasonWeight: data.recipeSeasonWeight ?? 1 });
      if (!pick) continue;
      shift.seq += 1;
      const seat = freeSeats[Math.floor(random() * freeSeats.length)];
      const patience = rest.patience_s[pick.recipe.tier] * 1000 * (team ? TEAM.patience : 1);
      const order = { id: `o${shift.seq}`, customer: c.id, dish: pick.recipe.id, seat, at: t, patience, used: pick.used, regular: pick.regular, steps: pick.recipe.steps.map(() => ({ by: 0, start: 0, taps: null })) };
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

  return { restWire, broadcastRest, handleRestaurant, tickRestaurant, seedRestaurant, closeShift, leaveStaff };
}
