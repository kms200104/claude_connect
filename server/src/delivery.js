// 식재료 배달 (v13). 휴대폰 '배달' 앱에서 식재료를 주문하면(값 + 배달비를 바로 낸다) 20~30초 뒤
// 상점에서 "배달 가고 있습니다~" 마을톡이 오고, 상점 배달 알바가 상점 문 앞에서 출발해 주문한 사람에게 뛰어간다.
// 곁(hand_range)에 닿으면 물건을 건네고(가방, 가득 차 있으면 식당 창고) 다시 상점으로 돌아간다.
// 주문한 사람이 집 안·상점 안에 있거나 접속이 끊겨 있으면 그 자리에서 기다리다(wait_s) 식당 창고에 넣어 두고 돌아간다.
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
  const itemsText = (d) => `${nameOf(d.item)} ${d.n}개`;
  const line = (key, d) => rules.lines[key].replace('{items}', itemsText(d));
  const activeOf = (room, uid) => [...room.deliveries.values()].filter((d) => d.uid === uid && d.ph !== 'back').length;

  /** 주문 받기: 지금 상점에서 파는 식재료만. 값 + 배달비를 바로 받는다. */
  function order(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const item = msg.item;
    const n = msg.n === undefined ? 1 : msg.n;
    if (!Number.isInteger(n) || n < 1 || n > rules.max_n) return fail(ErrorCode.badItem);
    if (typeof item !== 'string' || data.kindOf(item) !== 'ingredient' || !stockFor(room).includes(item)) return fail(ErrorCode.notForSale);
    if (activeOf(room, player.uid) >= rules.max_active) return fail(ErrorCode.deliveryBusy);
    const goods = buyPrice(room, item, n);
    const amount = goods + rules.fee;
    if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
    player.profile.sol -= amount;
    onPaid?.(room, player, goods);
    const t = now();
    const delay = (rules.min_delay_s + random() * (rules.max_delay_s - rules.min_delay_s)) * 1000 * (cfg.deliveryTimeScale ?? 1);
    room.delivSeq += 1;
    const d = { id: `v${room.delivSeq}`, uid: player.uid, pid: player.id, item, n, ph: 'wait', dueAt: t + delay, x: door.x, z: door.z, yaw: 0, waited: 0, handAt: 0 };
    room.deliveries.set(d.id, d);
    send(ctx.ws, { t: 'deliv_ok', rid: msg.rid, id: d.id, item, n, amount, fee: rules.fee, eta: Math.round(delay / 1000), sol: player.profile.sol });
    sendProfile(player);
    room.saveDirty = true;
  }

  const ownerOf = (room, d) => {
    const p = room.players.get(d.pid);
    return p && p.uid === d.uid ? p : null;
  };

  /** 식당 창고에 넣고 알린다 (안 계심 / 가방이 가득 참). */
  function store(room, d, key) {
    storeIngredients(room.restaurant, d.item, d.n, data.shop.storage?.max_per_item ?? 999);
    const profile = room.profiles.get(d.uid);
    if (profile) messenger.push(room, profile, 'sys:shop', 'courier', line(key, d));
    const p = ownerOf(room, d);
    if (p?.ws) sendTo(p, { t: 'deliv_done', id: d.id, item: d.item, n: d.n, where: 'storage' });
    onStored?.(room);
  }

  /** 다가가 건네기: 가방에 다 들어가면 가방, 아니면 식당 창고. */
  function handOver(room, d, p) {
    if (canAdd(p.slots, d.item, d.n, data.limitOf) && addItem(p.slots, d.item, d.n, cfg, data.limitOf)) {
      messenger.push(room, p.profile, 'sys:shop', 'courier', line('done', d));
      sendTo(p, { t: 'deliv_done', id: d.id, item: d.item, n: d.n, where: 'bag' });
      sendInventory(p);
      sendProfile(p);
    } else {
      store(room, d, 'full');
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
            store(room, d, 'stored');
            room.deliveries.delete(d.id);
          } else {
            if (profile) messenger.push(room, profile, 'sys:shop', 'courier', line('start', d));
            d.ph = 'walk';
          }
          changed = true;
          break;
        }
        case 'walk': {
          if (!p || !p.online || isIndoor(p)) {
            d.waited += dtMs;
            if (d.waited >= rules.wait_s * 1000) {
              store(room, d, 'stored');
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
    return [...room.deliveries.values()].filter((d) => d.ph !== 'wait').map((d) => ({ id: d.id, x: d.x, z: d.z, yaw: d.yaw, ph: d.ph, to: d.pid, item: d.item }));
  }

  /** 들어올 때 보내는 내 주문들 (기다리는 것 포함). */
  function mine(room, uid) {
    return [...room.deliveries.values()].filter((d) => d.uid === uid).map((d) => ({ id: d.id, item: d.item, n: d.n, ph: d.ph }));
  }

  return { order, tick, wire, mine };
}
