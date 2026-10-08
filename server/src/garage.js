// 차고 (v19, 서버 권위): 자전거 · 전기오토바이 사기 · 꾸미기(부품 사서 끼우기) · 타기. 데이터는 data/vehicles/garage.json.
// (가방에서 꺼내 타는 킥보드는 아이템 · ride 메시지로 따로 — server.js handleRide.)
// veh_buy → 값을 치르고 차고(profile.vehicles)에 넣는다. veh_part → 처음 끼우는 부품은 값을 치르고(그 탈것에 남는다), 산 적 있는 부품은 공짜로 바꿔 끼운다.
// veh_unfit → 그 칸을 기본 부품으로. veh_sell → 탈것과 산 부품 값의 resale 만큼 돌려받는다.
// veh_call (v19.1) → 동네 주민이 그 탈것을 타고 와서 내 곁(x, z)에 세워 두고 간다 (delivery.eta_ms 뒤 도착). 오는 중 · 세워 둔 탈것은
// 방 전체에 veh_parked { list: [{ v, o(주인 자리), m, f, x, z, yaw, t(도착 서버 시각, 0 = 이미 있음), npc }] } 로 보인다 (저장된다).
// veh_ride → 세워 둔 내 탈것 곁(ride_range)에서 올라탄다 (빈 v = 내려서 그 자리에 세워 둠, 킥보드에서는 내린다).
// 타는 동안은 스냅샷에 모양(mount)을 싣고, 이동 속도 검사를 그 탈것의 최고 속도로 한다 (내린 뒤 speed_grace_ms 동안도).
// 집 · 상점 안, 문을 지날 때, 낚싯대를 던질 때는 내린다.
import { ErrorCode } from './protocol.js';

/** garage.json 검사 + 찾기 Map. */
export function loadGarage(raw) {
  if (!raw) return null;
  const models = new Map(raw.models.map((m) => [m.id, m]));
  const parts = new Map(raw.parts.map((p) => [p.id, p]));
  const slots = new Set(raw.slots.map((s) => s.id));
  for (const m of raw.models) {
    if (!raw.kinds[m.kind]) throw new Error(`vehicles: ${m.id} 의 종류 ${m.kind} 이(가) 없음`);
    if (!(m.price > 0) || !(m.top > 0)) throw new Error(`vehicles: ${m.id} 값 · 최고 속도`);
  }
  for (const p of raw.parts) {
    if (!slots.has(p.slot)) throw new Error(`vehicles: ${p.id} 의 칸 ${p.slot} 이(가) 없음`);
    for (const k of p.kinds) if (!(p.price?.[k] > 0)) throw new Error(`vehicles: ${p.id} 의 ${k} 값이 없음`);
  }
  return { ...raw, models, parts, slotIds: [...slots] };
}

/** 끼운 부품의 성능 배율을 곱한 탈것 성능 { top, accel, brake, turn, wade }. 클라이언트 VehicleCatalog.stats 와 같다. */
export function vehicleStats(rules, vehicle) {
  const m = rules.models.get(vehicle.model);
  const out = { top: m.top, accel: m.accel, brake: m.brake, turn: m.turn, wade: m.wade ?? 0.55 };
  for (const id of Object.values(vehicle.fit ?? {})) {
    const s = rules.parts.get(id)?.stats;
    if (!s) continue;
    for (const k of Object.keys(out)) if (Number.isFinite(s[k])) out[k] *= s[k];
  }
  out.wade = Math.min(out.wade, 1);
  return out;
}

/** 부품 값 (그 종류 탈것에 맞지 않으면 0). */
export function partPrice(rules, partId, kind) {
  const p = rules.parts.get(partId);
  return p && p.kinds.includes(kind) ? p.price[kind] : 0;
}

/** 팔 때 돌려받는 돈: (탈것 값 + 산 부품 값) × resale, 100 솔 단위. */
export function resaleValue(rules, vehicle) {
  const m = rules.models.get(vehicle.model);
  const spent = m.price + (vehicle.owned ?? []).reduce((sum, id) => sum + partPrice(rules, id, m.kind), 0);
  return Math.round((spent * (rules.resale ?? 0.5)) / 100) * 100;
}

/** 저장된 차고를 데이터에 맞게 다듬는다 (모르는 모델 · 부품은 버림). */
export function sanitizeVehicles(raw, rules) {
  if (!rules || !Array.isArray(raw)) return [];
  const out = [];
  for (const v of raw) {
    const m = v && typeof v.id === 'string' ? rules.models.get(v.model) : null;
    if (!m || out.some((o) => o.id === v.id)) continue;
    const owned = Array.isArray(v.owned) ? [...new Set(v.owned.filter((id) => partPrice(rules, id, m.kind) > 0))] : [];
    const fit = {};
    for (const [slot, id] of Object.entries(v.fit ?? {})) {
      const p = rules.parts.get(id);
      if (p && p.slot === slot && owned.includes(id)) fit[slot] = id;
    }
    // 세워 둔 자리 (다시 켜면 이미 도착한 것으로).
    const at = v.at && [v.at.x, v.at.z].every(Number.isFinite) ? { x: v.at.x, z: v.at.z, yaw: Number.isFinite(v.at.yaw) ? v.at.yaw : 0, t: 0, npc: '' } : null;
    out.push({ id: v.id, model: m.id, owned, fit, at });
    if (out.length >= rules.max_owned) break;
  }
  return out;
}

/** 스냅샷 · 입장 정보에 싣는 타는 모양 { v, m, f } (안 타면 null). */
export function mountWire(player) {
  const v = player.mount ? player.profile.vehicles.find((x) => x.id === player.mount) : null;
  return v ? { v: v.id, m: v.model, f: { ...v.fit } } : null;
}

/** 방에 세워 둔(또는 오는 중인) 탈것 전부 (veh_parked · welcome.parked). */
export function parkedWire(room) {
  const out = [];
  for (const p of room.profiles.values()) {
    for (const v of p.vehicles ?? []) {
      if (v.at) out.push({ v: v.id, o: p.slot, m: v.model, f: { ...v.fit }, x: v.at.x, z: v.at.z, yaw: v.at.yaw, t: v.at.t ?? 0, npc: v.at.npc ?? '' });
    }
  }
  return out;
}

export function createGarage({ data, send, sendProfile, rooms, now = () => performance.now(), random = Math.random, etaMs }) {
  const rules = data.garage;
  const delivery = { eta_ms: 6500, park_range: 4, ride_range: 3, speed_grace_ms: 1500, ...(rules?.delivery ?? {}) };
  // 테스트는 배달을 빨리 (config.vehicleEtaMs, VEHICLE_ETA_MS).
  if (Number.isFinite(etaMs)) delivery.eta_ms = etaMs;
  const couriers = data.npcs ? [...data.npcs.keys()] : [];

  const broadcastParked = (room) => room?.broadcast({ t: 'veh_parked', list: parkedWire(room) });

  /** 지금 타고 있는 탈것의 최고 속도 (안 타면 0). 이동 속도 검사가 쓴다. */
  function topSpeed(player) {
    const id = player.mount ?? (now() < (player.mountGraceUntil ?? 0) ? player.lastMount : null);
    const v = id ? player.profile.vehicles.find((x) => x.id === id) : null;
    return v && rules ? vehicleStats(rules, v).top : 0;
  }

  /** 내린다: 지금 자리(순간이동 전이면 떠나기 전 자리)에 세워 둔다. 탄 채였으면 스냅샷 · veh_parked 로 알린다. */
  function dismount(player, room) {
    if (!player.mount) return false;
    const v = player.profile.vehicles.find((x) => x.id === player.mount);
    player.lastMount = player.mount;
    player.mountGraceUntil = now() + delivery.speed_grace_ms;
    player.mount = null;
    if (v) v.at = { x: player.x, z: player.z, yaw: Number.isFinite(player.yaw) ? player.yaw : 0, t: 0, npc: '' };
    if (room) {
      room.dirty = true;
      room.saveDirty = true;
      broadcastParked(room);
    }
    return true;
  }

  function handle(ctx, msg, fail, { blocked }) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!rules) return fail(ErrorCode.badVehicle);
    const p = player.profile;
    const vehicle = typeof msg.v === 'string' ? p.vehicles.find((x) => x.id === msg.v) : null;
    switch (msg.t) {
      case 'veh_buy': {
        const m = typeof msg.model === 'string' ? rules.models.get(msg.model) : null;
        if (!m) return fail(ErrorCode.badVehicle);
        if (p.vehicles.length >= rules.max_owned) return fail(ErrorCode.garageFull);
        if (p.sol < m.price) return fail(ErrorCode.notEnoughSol);
        p.sol -= m.price;
        p.vehSeq = (p.vehSeq ?? 0) + 1;
        const v = { id: `V${p.vehSeq}`, model: m.id, owned: [], fit: {} };
        p.vehicles.push(v);
        send(ctx.ws, { t: 'veh_result', rid: msg.rid, kind: 'buy', v: v.id, model: m.id, cost: m.price, sol: p.sol });
        break;
      }
      case 'veh_part': {
        if (!vehicle) return fail(ErrorCode.badVehicle);
        const kind = rules.models.get(vehicle.model).kind;
        const part = typeof msg.part === 'string' ? rules.parts.get(msg.part) : null;
        const price = part ? partPrice(rules, part.id, kind) : 0;
        if (!part || price <= 0) return fail(ErrorCode.badPart);
        let cost = 0;
        if (!vehicle.owned.includes(part.id)) {
          if (p.sol < price) return fail(ErrorCode.notEnoughSol);
          p.sol -= price;
          cost = price;
          vehicle.owned.push(part.id);
        }
        vehicle.fit[part.slot] = part.id;
        send(ctx.ws, { t: 'veh_result', rid: msg.rid, kind: 'part', v: vehicle.id, part: part.id, cost, sol: p.sol });
        break;
      }
      case 'veh_unfit': {
        if (!vehicle) return fail(ErrorCode.badVehicle);
        if (typeof msg.slot !== 'string' || !vehicle.fit[msg.slot]) return fail(ErrorCode.badPart);
        delete vehicle.fit[msg.slot];
        send(ctx.ws, { t: 'veh_result', rid: msg.rid, kind: 'unfit', v: vehicle.id, slot: msg.slot, cost: 0, sol: p.sol });
        break;
      }
      case 'veh_sell': {
        if (!vehicle) return fail(ErrorCode.badVehicle);
        const back = resaleValue(rules, vehicle);
        if (player.mount === vehicle.id) dismount(player, room);
        const wasParked = !!vehicle.at;
        p.vehicles = p.vehicles.filter((x) => x !== vehicle);
        p.sol += back;
        if (wasParked) broadcastParked(room);
        send(ctx.ws, { t: 'veh_result', rid: msg.rid, kind: 'sell', v: vehicle.id, cost: -back, sol: p.sol });
        break;
      }
      case 'veh_ride': {
        if (msg.v === '' || msg.v === null || msg.v === undefined) {
          dismount(player, room);
        } else {
          if (!vehicle) return fail(ErrorCode.badVehicle);
          const why = blocked(player);
          if (why) return fail(why);
          if (player.mount === vehicle.id) return send(ctx.ws, { t: 'veh_ride', rid: msg.rid, id: player.id, mount: mountWire(player) });
          // 세워 둔(도착한) 그 탈것 곁에서만 탄다.
          const at = vehicle.at;
          if (!at || (at.t ?? 0) > now() || Math.hypot(player.x - at.x, player.z - at.z) > delivery.ride_range + 0.5) return fail(ErrorCode.notNearVehicle);
          if (player.mount) dismount(player, room);
          vehicle.at = null;
          broadcastParked(room);
          player.mount = vehicle.id;
          player.ride = ''; // 킥보드에서는 내린다
          room.dirty = true;
        }
        send(ctx.ws, { t: 'veh_ride', rid: msg.rid, id: player.id, mount: mountWire(player) });
        if (room) room.saveDirty = true;
        return;
      }
      case 'veh_call': {
        // 주민 배달: 내 곁 (park_range 안) 에 세워 둔다. 타고 있는 그 탈것은 부를 수 없다.
        if (!vehicle) return fail(ErrorCode.badVehicle);
        if (player.mount === vehicle.id) return fail(ErrorCode.badVehicle);
        const why = blocked(player);
        if (why) return fail(why);
        let x = Number(msg.x);
        let z = Number(msg.z);
        if (!Number.isFinite(x) || !Number.isFinite(z) || Math.hypot(x - player.x, z - player.z) > delivery.park_range) {
          x = player.x;
          z = player.z;
        }
        const npc = couriers.length ? couriers[Math.floor(random() * couriers.length)] : '';
        const arrive = now() + delivery.eta_ms;
        vehicle.at = { x, z, yaw: Number.isFinite(msg.yaw) ? msg.yaw : player.yaw, t: arrive, npc };
        send(ctx.ws, { t: 'veh_result', rid: msg.rid, kind: 'call', v: vehicle.id, npc, at: arrive, cost: 0, sol: p.sol });
        sendProfile(player);
        broadcastParked(room);
        rooms.save(room);
        return;
      }
      default:
        return;
    }
    // 차고 · 끼운 부품이 바뀌었다. 타고 있는 탈것이면 모양도 다시 알린다.
    if (player.mount && vehicle && player.mount === vehicle.id) room.dirty = true;
    // 세워 둔 탈것의 모양이 바뀌었다.
    if (vehicle?.at && msg.t !== 'veh_sell') broadcastParked(room);
    sendProfile(player);
    rooms.save(room);
  }

  /** 프로필에 싣는 차고. */
  function profileWire(profile) {
    return { vehicles: (profile.vehicles ?? []).map((v) => ({ id: v.id, model: v.model, owned: [...v.owned], fit: { ...v.fit }, at: v.at ? { x: v.at.x, z: v.at.z, t: v.at.t ?? 0 } : null })) };
  }

  return { handle, topSpeed, dismount, profileWire, parkedWire, broadcastParked };
}
