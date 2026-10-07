// 식재료 배달 (v13). 휴대폰 '배달' 앱에서 식재료를 주문하면(값 + 배달비를 바로 낸다) 20~30초 뒤
// 상점에서 "배달 가고 있습니다~" 마을톡이 오고, 상점 배달 알바가 상점 문 앞에서 출발해 주문한 사람에게 뛰어간다.
// 곁(hand_range)에 닿으면 물건을 건네고(가방, 가득 차 있으면 식당 창고) 다시 상점으로 돌아간다.
// 주문한 사람이 집 안·상점 안에 있거나 접속이 끊겨 있으면 그 자리에서 기다리다(wait_s) 식당 창고에 넣어 두고 돌아간다.
// 묶음 배달 (v0.13.2): 아직 상점을 떠나지 않은 내 배달이 있으면 새 주문은 그 상자에 같이 담는다 (최대 max_active 건,
// 배달비는 상자당 한 번). 그래서 3건을 주문해도 알바 한 명이 한 번에 가져오고 마을톡도 한 번만 온다.
// 상자 = { id, uid, pid, items: [{item, n}], orders, ph, … }.
// 배달 알바의 위치는 서버가 정하고(주민처럼 곧장 걷는다) 'couriers' 로 방송한다.
import { ErrorCode } from './protocol.js';
import { addItem, canAdd } from './inventory.js';
import { yawToward } from './npcs.js';

const round = (v) => Math.round(v * 1000) / 1000;

/** 식당 창고에 넣는다 (아이템마다 max 까지). 넣은 개수. */
export function storeIngredients(restaurant, id, n, max = 999) {
  restaurant.storage ??= {};
  const have = restaurant.storage[id] ?? 0;
  const put = Math.max(0, Math.min(n, max - have));
  if (put > 0) restaurant.storage[id] = have + put;
  return put;
}

export function createDelivery({ data, cfg, random, now, send, sendTo, sendInventory, sendProfile, messenger, stockFor, buyPrice, isIndoor, onPaid, onStored }) {
  const rules = data.shop.delivery;
  const door = data.shop.door;
  const nameOf = (id) => data.items.get(id)?.name ?? id;
  const itemsText = (items) => items.map((it) => `${nameOf(it.item)} ${it.n}개`).join(', ');
  const line = (key, items) => rules.lines[key].replace('{items}', itemsText(items));
  /** 아직 받지 않은 주문 건수 (상자마다 담긴 건수의 합). */
  const activeOf = (room, uid) => [...room.deliveries.values()].filter((d) => d.uid === uid && d.ph !== 'back' && d.ph !== 'hand').reduce((sum, d) => sum + d.orders, 0);
  const itemsWire = (d) => d.items.map((it) => ({ item: it.item, n: it.n }));

  /** 주문 받기: 지금 상점에서 파는 식재료만. 값 + 배달비를 바로 받는다. */
  function order(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const item = msg.item;
    const n = msg.n === undefined ? 1 : msg.n;
    if (!Number.isInteger(n) || n < 1 || n > rules.max_n) return fail(ErrorCode.badItem);
    if (typeof item !== 'string' || data.kindOf(item) !== 'ingredient' || !stockFor(room).includes(item)) return fail(ErrorCode.notForSale);
    if (activeOf(room, player.uid) >= rules.max_active) return fail(ErrorCode.deliveryBusy);
    const t = now();
    // 아직 상점에 있는 내 상자가 있으면 거기에 같이 담는다 (배달비 없음).
    const box = [...room.deliveries.values()].find((d) => d.uid === player.uid && d.ph === 'wait' && d.orders < rules.max_active);
    const goods = buyPrice(room, item, n);
    const fee = box ? 0 : rules.fee;
    const amount = goods + fee;
    if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
    player.profile.sol -= amount;
    onPaid?.(room, player, goods);
    const scale = cfg.deliveryTimeScale ?? 1;
    let d = box;
    if (d) {
      const same = d.items.find((it) => it.item === item);
      if (same) same.n += n;
      else d.items.push({ item, n });
      d.orders += 1;
      d.pid = player.id;
      // 막 떠나려던 참이면 담을 틈을 조금 준다.
      d.dueAt = Math.max(d.dueAt, t + 3000 * scale);
    } else {
      const delay = (rules.min_delay_s + random() * (rules.max_delay_s - rules.min_delay_s)) * 1000 * scale;
      room.delivSeq += 1;
      d = { id: `v${room.delivSeq}`, uid: player.uid, pid: player.id, items: [{ item, n }], orders: 1, ph: 'wait', dueAt: t + delay, x: door.x, z: door.z, yaw: 0, waited: 0, handAt: 0 };
      room.deliveries.set(d.id, d);
    }
    send(ctx.ws, { t: 'deliv_ok', rid: msg.rid, id: d.id, item, n, amount, fee, merged: !!box, items: itemsWire(d), orders: d.orders, eta: Math.max(0, Math.round((d.dueAt - t) / 1000)), sol: player.profile.sol });
    sendProfile(player);
    room.saveDirty = true;
  }

  const ownerOf = (room, d) => {
    const p = room.players.get(d.pid);
    return p && p.uid === d.uid ? p : null;
  };

  const putAway = (room, items) => {
    for (const it of items) storeIngredients(room.restaurant, it.item, it.n, data.shop.storage?.max_per_item ?? 999);
    if (items.length > 0) onStored?.(room);
  };

  /** 상자를 통째로 식당 창고에 넣고 한 번 알린다 (주문한 사람이 없음). */
  function store(room, d) {
    putAway(room, d.items);
    const profile = room.profiles.get(d.uid);
    if (profile) messenger.push(room, profile, 'sys:shop', 'courier', line('stored', d.items));
    const p = ownerOf(room, d);
    if (p?.ws) sendTo(p, { t: 'deliv_done', id: d.id, items: d.items.map((it) => ({ ...it, where: 'storage' })) });
  }

  /** 다가가 상자를 건넨다: 가방에 들어가는 것은 가방, 넘치는 것은 식당 창고. 마을톡은 한 번만. */
  function handOver(room, d, p) {
    const bag = [];
    const stored = [];
    for (const it of d.items) {
      if (canAdd(p.slots, it.item, it.n, data.limitOf) && addItem(p.slots, it.item, it.n, cfg, data.limitOf)) bag.push(it);
      else stored.push(it);
    }
    putAway(room, stored);
    const text = [bag.length > 0 ? line('done', bag) : '', stored.length > 0 ? line('full', stored) : ''].filter(Boolean).join(' ');
    messenger.push(room, p.profile, 'sys:shop', 'courier', text);
    sendTo(p, { t: 'deliv_done', id: d.id, items: [...bag.map((it) => ({ ...it, where: 'bag' })), ...stored.map((it) => ({ ...it, where: 'storage' }))] });
    if (bag.length > 0) {
      sendInventory(p);
      sendProfile(p);
    }
    room.saveDirty = true;
  }

  /** 한 걸음: 목표 쪽으로 speed 만큼. 닿았으면 true. */
  function stepToward(d, tx, tz, dt, stopAt) {
    const dx = tx - d.x;
    const dz = tz - d.z;
    const dist = Math.hypot(dx, dz);
    if (dist <= stopAt) return true;
    const step = Math.min(rules.speed * dt, dist - stopAt);
    d.x = round(d.x + (dx / dist) * step);
    d.z = round(d.z + (dz / dist) * step);
    d.yaw = round(yawToward(dx, dz));
    return dist - step <= stopAt + 1e-6;
  }

  /** npcTick 마다. 바뀐 게 있으면 true (couriers 방송). */
  function tick(room, dtMs, t) {
    if (room.deliveries.size === 0) return false;
    const dt = dtMs / 1000;
    let changed = false;
    for (const d of [...room.deliveries.values()]) {
      const p = ownerOf(room, d);
      switch (d.ph) {
        case 'wait': {
          if (t < d.dueAt) break;
          const profile = room.profiles.get(d.uid);
          if (!p || !p.online) {
            // 주문한 사람이 없다: 바로 식당 창고로.
            store(room, d);
            room.deliveries.delete(d.id);
          } else {
            if (profile) messenger.push(room, profile, 'sys:shop', 'courier', line('start', d.items));
            d.ph = 'walk';
          }
          changed = true;
          break;
        }
        case 'walk': {
          if (!p || !p.online || isIndoor(p)) {
            d.waited += dtMs;
            if (d.waited >= rules.wait_s * 1000) {
              store(room, d);
              d.ph = 'back';
              changed = true;
            }
            break;
          }
          if (stepToward(d, p.x, p.z, dt, rules.hand_range * 0.8)) {
            d.yaw = round(yawToward(p.x - d.x, p.z - d.z));
            d.ph = 'hand';
            d.handAt = t;
            handOver(room, d, p);
          }
          changed = true;
          break;
        }
        case 'hand':
          if (t - d.handAt >= 1600) {
            d.ph = 'back';
            changed = true;
          }
          break;
        case 'back':
          if (stepToward(d, door.x, door.z, dt, 0.3)) room.deliveries.delete(d.id);
          changed = true;
          break;
      }
    }
    return changed;
  }

  /** 방송용: 길 위에 나와 있는 배달 알바만 (기다리는 주문은 안 보인다). */
  function wire(room) {
    return [...room.deliveries.values()].filter((d) => d.ph !== 'wait').map((d) => ({ id: d.id, x: d.x, z: d.z, yaw: d.yaw, ph: d.ph, to: d.pid, item: d.items[0]?.item ?? '', k: d.items.length }));
  }

  /** 들어올 때 보내는 내 주문들 (기다리는 것 포함). */
  function mine(room, uid) {
    return [...room.deliveries.values()].filter((d) => d.uid === uid).map((d) => ({ id: d.id, items: itemsWire(d), orders: d.orders, ph: d.ph }));
  }

  return { order, tick, wire, mine };
}
