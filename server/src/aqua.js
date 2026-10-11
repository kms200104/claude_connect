// 물놀이 체험 (v21, 서버 권위): 성성호수 선착장의 바나나 보트 · 유람선. 데이터는 data/aqua/aqua.json (tools/art/gen_aqua.py).
// aqua_join { ride } → 선착장 곁(board_range)에서 요금을 내고 탄다. 그 놀이배가 손님을 받는 중(board_ms 동안)이면 같이 타고,
//   쉬고 있으면 새로 띄운다 (방마다 놀이배 하나씩 — 돌고 있는 동안은 aqua_busy). 출발 · 도착 시각은 서버가 정한다.
// aqua_leave → 출발 전에만 내린다 (요금을 돌려준다). aqua_hold { trip, turn, ms } → 바나나 보트 급회전 "꽉 잡아!":
//   클라이언트가 잰 경과 시간 ms(그 급회전 신호가 뜬 뒤 누를 때까지, 못 누르면 -1)가 window_ms 안이면 버틴다 (지연 불이익 없음).
//   그 급회전 무렵(서버 시각)에만 받고, 급회전마다 한 번. 결과는 방 전체에 aqua_fx { trip, id, turn, fell }.
// 방 전체에 aqua_trips { list: [{ id, ride, depart, riders: [{ id, seat }] }] } (welcome.aqua 도 같은 모양).
// 타는 동안 이동 요청은 받지 않고 자리는 서버가 노선에서 계산한다. 끝나면 land 로 내려 주고 aqua_end { trip, ride, held, turns }.
// 길 · 시간 계산은 클라이언트 core/rules/aqua_rules.gd 와 같다.
import { ErrorCode } from './protocol.js';

/** aqua.json 검사 + 찾기 Map. */
export function loadAqua(raw) {
  if (!raw) return null;
  const rides = new Map();
  for (const r of raw.rides) {
    if (!(r.fee > 0) || !(r.seats > 0) || !(r.speed > 0) || !(r.path?.length >= 2)) throw new Error(`aqua: ${r.id} 값`);
    rides.set(r.id, { ...r, duration: duration(r) });
  }
  return { ...raw, rides };
}

/** 한 바퀴 걸리는 시간 (초): 처음 · 끝 ease_s 초는 천천히. */
export function duration(ride) {
  return ride.length / ride.speed + (ride.ease_s ?? 0);
}

/** 출발 뒤 tau 초에 간 거리 (m). 처음 ease_s 초는 고르게 빨라지고, 마지막 ease_s 초는 고르게 느려진다. */
export function distanceAt(ride, tau) {
  const a = ride.ease_s ?? 0;
  const v = ride.speed;
  const total = duration(ride);
  if (tau <= 0) return 0;
  if (tau >= total) return ride.length;
  if (a > 0 && tau < a) return (v * tau * tau) / (2 * a);
  if (a > 0 && tau > total - a) return ride.length - (v * (total - tau) ** 2) / (2 * a);
  return v * (tau - a / 2);
}

/** 그 거리에 닿는 시각 (출발 뒤 초). distanceAt 의 역. */
export function timeAt(ride, s) {
  const a = ride.ease_s ?? 0;
  const v = ride.speed;
  const total = duration(ride);
  if (s <= 0) return 0;
  if (s >= ride.length) return total;
  if (a > 0 && s < (v * a) / 2) return Math.sqrt((2 * a * s) / v);
  if (a > 0 && s > ride.length - (v * a) / 2) return total - Math.sqrt((2 * a * (ride.length - s)) / v);
  return s / v + a / 2;
}

/** 노선 위 s m 자리 { x, z } (닫힌 고리라 길이를 넘으면 처음부터). */
export function pointAt(ride, s) {
  const path = ride.path;
  const n = path.length - 1;
  const step = ride.length / n;
  let d = s % ride.length;
  if (d < 0) d += ride.length;
  const i = Math.min(Math.floor(d / step), n - 1);
  const t = d / step - i;
  const a = path[i];
  const b = path[i + 1];
  return { x: a[0] + (b[0] - a[0]) * t, z: a[1] + (b[1] - a[1]) * t };
}

/** 테스트용: 놀이배를 k 배 빠르게 (시간 값은 1/k). */
function scaled(rules, k) {
  if (!rules || !(k > 0) || k === 1) return rules;
  const rides = new Map();
  for (const [id, r] of rules.rides) {
    const s = { ...r, speed: r.speed * k, ease_s: (r.ease_s ?? 0) / k, prompt_s: (r.prompt_s ?? 1.3) / k };
    rides.set(id, { ...s, duration: duration(s) });
  }
  return { ...rules, rides };
}

export function createAqua({ data, send, sendProfile, now = () => performance.now(), boardMs = NaN, speedScale = 1 }) {
  const rules = scaled(data.aqua, speedScale);
  // 테스트는 손님을 짧게 기다린다 (config.aquaBoardMs).
  const board = Number.isFinite(boardMs) ? boardMs : (rules?.board_ms ?? 8000);
  const PROMPT_SLACK_MS = 2500;
  const LATE_MS = 4000;
  let seq = 0;

  const tripsOf = (room) => {
    if (!room.aquaTrips) room.aquaTrips = new Map();
    return room.aquaTrips;
  };
  const tripsWire = (room) =>
    [...tripsOf(room).values()].map((t) => ({ id: t.id, ride: t.ride.id, depart: t.depart, riders: [...t.riders.entries()].map(([id, r]) => ({ id, seat: r.seat })) }));
  const broadcastTrips = (room) => room.broadcast({ t: 'aqua_trips', list: tripsWire(room) });

  /** 지금 이 사람이 타고 있는 자리 (안 타면 null). 이동 요청 대신 쓴다. */
  function seatPos(player, room) {
    const trip = player.aqua ? tripsOf(room).get(player.aqua) : null;
    if (!trip) return null;
    return pointAt(trip.ride, distanceAt(trip.ride, (now() - trip.depart) / 1000));
  }

  function land(player) {
    const [x, z] = rules.dock.land;
    player.x = x;
    player.z = z;
  }

  /** 놀이배에서 내린다 (끝 · 끊김 · 출발 전 내리기). 선착장 땅에 선다. */
  function leave(player, room, { refund = false } = {}) {
    const trip = player.aqua ? tripsOf(room).get(player.aqua) : null;
    player.aqua = null;
    if (!trip) return false;
    trip.riders.delete(player.id);
    if (refund) {
      player.profile.sol += trip.ride.fee;
      room.saveDirty = true;
    }
    land(player);
    room.dirty = true;
    if (trip.riders.size === 0) tripsOf(room).delete(trip.id);
    broadcastTrips(room);
    return true;
  }

  function finish(room, trip) {
    tripsOf(room).delete(trip.id);
    for (const [id, r] of trip.riders) {
      const player = room.players.get(id);
      if (!player || player.aqua !== trip.id) continue;
      player.aqua = null;
      land(player);
      const turns = trip.ride.turns?.length ?? 0;
      const held = Object.values(r.held).filter(Boolean).length;
      if (player.ws) {
        send(player.ws, { t: 'aqua_end', trip: trip.id, ride: trip.ride.id, held, turns });
        send(player.ws, { t: 'correct', x: player.x, y: player.y, z: player.z });
      }
    }
    room.dirty = true;
    broadcastTrips(room);
  }

  /** 다 돈 놀이배를 선착장에 대고 손님을 내린다. */
  function tick(room) {
    if (!room.aquaTrips?.size) return;
    const t = now();
    for (const trip of [...room.aquaTrips.values()]) {
      if (t >= trip.depart + trip.ride.duration * 1000) finish(room, trip);
    }
  }

  function handle(ctx, msg, fail, { blocked }) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!rules) return fail(ErrorCode.badMessage);
    const p = player.profile;
    switch (msg.t) {
      case 'aqua_join': {
        const ride = typeof msg.ride === 'string' ? rules.rides.get(msg.ride) : null;
        if (!ride) return fail(ErrorCode.badMessage);
        if (player.aqua) return fail(ErrorCode.aquaBusy);
        const why = blocked(player);
        if (why) return fail(why);
        if (player.mount || player.ride) return fail(ErrorCode.cantRide);
        if (Math.hypot(player.x - rules.dock.x, player.z - rules.dock.z) > rules.dock.board_range) return fail(ErrorCode.notNearDock);
        const t = now();
        let trip = [...tripsOf(room).values()].find((x) => x.ride.id === ride.id);
        if (trip && (t >= trip.depart || trip.riders.size >= ride.seats)) return fail(ErrorCode.aquaBusy);
        if (p.sol < ride.fee) return fail(ErrorCode.notEnoughSol);
        if (!trip) {
          seq += 1;
          trip = { id: `A${seq}`, ride, depart: t + board, riders: new Map() };
          tripsOf(room).set(trip.id, trip);
        }
        const taken = new Set([...trip.riders.values()].map((r) => r.seat));
        let seat = 0;
        while (taken.has(seat)) seat += 1;
        trip.riders.set(player.id, { seat, held: {} });
        p.sol -= ride.fee;
        player.aqua = trip.id;
        const at = pointAt(ride, 0);
        player.x = at.x;
        player.z = at.z;
        room.dirty = true;
        room.saveDirty = true;
        send(ctx.ws, { t: 'aqua_result', rid: msg.rid, kind: 'join', trip: trip.id, ride: ride.id, seat, depart: trip.depart, cost: ride.fee, sol: p.sol });
        sendProfile(player);
        broadcastTrips(room);
        return;
      }
      case 'aqua_leave': {
        const trip = player.aqua ? tripsOf(room).get(player.aqua) : null;
        if (!trip) return fail(ErrorCode.badMessage);
        if (now() >= trip.depart) return fail(ErrorCode.aquaBusy);
        leave(player, room, { refund: true });
        send(ctx.ws, { t: 'aqua_result', rid: msg.rid, kind: 'leave', trip: trip.id, ride: trip.ride.id, cost: -trip.ride.fee, sol: p.sol });
        send(ctx.ws, { t: 'correct', x: player.x, y: player.y, z: player.z });
        sendProfile(player);
        return;
      }
      case 'aqua_hold': {
        const trip = player.aqua ? tripsOf(room).get(player.aqua) : null;
        if (!trip || trip.id !== msg.trip) return fail(ErrorCode.badMessage);
        const turns = trip.ride.turns ?? [];
        const k = Number.isInteger(msg.turn) ? msg.turn : -1;
        if (k < 0 || k >= turns.length) return fail(ErrorCode.badMessage);
        const rider = trip.riders.get(player.id);
        if (k in rider.held) return;
        // 그 급회전 신호가 뜰 무렵부터 지난 뒤 조금까지만 (서버 시각 — 미리 보내 두기 막기).
        const turnAt = trip.depart + timeAt(trip.ride, turns[k].s) * 1000;
        const promptAt = turnAt - (trip.ride.prompt_s ?? 1.3) * 1000;
        const t = now();
        if (t < promptAt - PROMPT_SLACK_MS || t > turnAt + LATE_MS) return fail(ErrorCode.badMessage);
        const ms = Number(msg.ms);
        const held = Number.isFinite(ms) && ms >= 0 && ms <= (trip.ride.window_ms ?? 1500);
        rider.held[k] = held;
        room.broadcast({ t: 'aqua_fx', trip: trip.id, id: player.id, turn: k, fell: !held });
        return;
      }
      default:
    }
  }

  return { handle, tick, leave, seatPos, tripsWire };
}
