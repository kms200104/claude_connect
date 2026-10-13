// 폰다운 기능 (v0.20, 서버 권위): 솔걸음(만보기) 보상 · 재난문자 · 민방위 훈련. 데이터는 data/safety/safety.json.
// steps { rid, n } — 휴대폰 가속도 센서로 센 오늘 걸음(클라 기준 누적). 서버는 늘어난 만큼을 사람이 걸을 수 있는 빠르기
//   (지난 보고 뒤 초 × max_rate + slack)와 하루 상한(daily_cap)으로 거르고, 목표(tiers)를 넘으면 하루 한 번 솔을 준다 → steps_ok.
// 재난문자: 날씨 · 계절 · 시각이 맞으면 방마다 하루 한 번 alert { id, level, sender, text, at } 를 보낸다 (늦게 들어온 사람에게도 오늘 것).
// 민방위 훈련: 매달 day 일 hour 시부터 minutes 분 동안 drill { on, shelter, until } — 대피소 반경 안에 들어오면 drill_done(보상, 한 번).
//   훈련 동안 주민은 제자리(집 앞 길목)로 돌아가 기다린다 (server.js npcTick 의 drillActive).

import { DAY_MS } from './clock.js';
import { earn } from './economy.js';

/** safety.json 검사. */
export function loadSafety(raw) {
  if (!raw) return null;
  const tiers = raw.steps?.tiers ?? [];
  for (let i = 0; i < tiers.length; i++) {
    const [steps, sol] = tiers[i];
    if (!(steps > 0) || !(sol > 0) || (i > 0 && steps <= tiers[i - 1][0])) throw new Error('safety: steps.tiers 는 늘어나는 [걸음, 솔]');
  }
  for (const a of raw.alerts?.list ?? []) {
    if (!a.id || !a.text || !['emergency', 'safety'].includes(a.level)) throw new Error(`safety: 재난문자 ${a.id}`);
  }
  return raw;
}

/** 마을 시각(게임 ms, 마을 벽시계를 UTC 로 적은 값)의 날짜 · 시각. */
export function wallClock(gameMs) {
  const d = new Date(gameMs);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), hour: d.getUTCHours() + d.getUTCMinutes() / 60 + d.getUTCSeconds() / 3600 };
}

/** 이번 달 훈련 { start, end, notice } (게임 ms). */
export function drillWindow(rules, gameMs) {
  const w = wallClock(gameMs);
  const start = Date.UTC(w.y, w.m - 1, rules.day, rules.hour, 0, 0);
  return { start, end: start + rules.minutes * 60000, notice: start - rules.notice_minutes * 60000 };
}

/** 걸음 보고 하나를 받아들인다 (늘어난 만큼 · 빠르기 · 상한). 돌려주는 값 = 새로 받은 보상들의 합. */
export function acceptSteps(rules, state, n, t, day) {
  if (state.day !== day) {
    state.day = day;
    state.today = 0;
    state.got = [];
  }
  const reported = Math.max(0, Math.trunc(n));
  // 클라가 날이 바뀌어 0부터 다시 세면(줄어들면) 그 값부터 늘어난 것으로 본다.
  const delta = reported >= state.last ? reported - state.last : reported;
  const allowed = Math.floor(rules.max_rate * Math.max(0, t - state.at) / 1000 + rules.slack);
  state.today = Math.min(rules.daily_cap, state.today + Math.min(delta, allowed));
  state.last = reported;
  state.at = t;
  let reward = 0;
  rules.tiers.forEach(([steps, sol], i) => {
    if (state.today >= steps && !state.got.includes(i)) {
      state.got.push(i);
      reward += sol;
    }
  });
  return reward;
}

export function createSafety({ data, cfg, clock, now, send, sendTo }) {
  const rules = data.safety;

  function stepsOf(player) {
    const p = player.profile;
    if (!p.steps || typeof p.steps !== 'object') p.steps = { day: -1, today: 0, got: [] };
    // 보고 사이 시각 · 마지막 값은 접속 동안만 (다시 들어오면 그때부터 잰다).
    if (!Number.isFinite(player.stepsAt)) {
      player.stepsAt = now();
      player.stepsLast = 0;
    }
    return p.steps;
  }

  function handleSteps(ctx, msg, fail) {
    const { player } = ctx;
    if (!rules) return fail('bad_message');
    if (!player.acceptRid(msg.rid)) return;
    if (!Number.isFinite(msg.n) || msg.n < 0) return fail('bad_message');
    const saved = stepsOf(player);
    const state = { day: saved.day, today: saved.today, got: [...saved.got], last: player.stepsLast, at: player.stepsAt };
    const reward = acceptSteps(rules.steps, state, msg.n, now(), clock.day());
    Object.assign(saved, { day: state.day, today: state.today, got: state.got });
    player.stepsLast = state.last;
    player.stepsAt = state.at;
    if (reward > 0) {
      player.profile.sol += reward;
      earn(player.profile, reward);
    }
    send(ctx.ws, { t: 'steps_ok', rid: msg.rid, today: saved.today, got: saved.got, reward, sol: player.profile.sol });
  }

  /** 오늘 보낼 재난문자 (지금 날씨 · 계절 · 시각에 맞는 것). */
  function dueAlerts(weather, season, hour) {
    return (rules?.alerts?.list ?? []).filter((a) => {
      if (a.weather && a.weather !== weather) return false;
      if (a.weather_not && a.weather_not.includes(weather)) return false;
      if (a.season && a.season !== season) return false;
      if (Array.isArray(a.hours) && !(hour >= a.hours[0] && hour < a.hours[1])) return false;
      return true;
    });
  }

  function alertWire(a, at) {
    return { t: 'alert', id: a.id, level: a.level, sender: a.sender ?? '', text: a.text, at };
  }

  function drillActive(room) {
    return !!room.drill?.on;
  }

  function shelterWire() {
    const s = rules.drill.shelter;
    return { name: s.name, x: s.x, z: s.z, r: s.radius };
  }

  /** 1초마다: 재난문자 · 민방위 훈련. */
  function tick(room, weather, season) {
    if (!rules) return;
    const g = clock.gameMs();
    const day = clock.day();
    if (room.alertDay !== day) {
      room.alertDay = day;
      room.alertsSent = [];
    }
    const hour = wallClock(g).hour;
    for (const a of dueAlerts(weather, season, hour)) {
      if (room.alertsSent.some((x) => x.id === a.id)) continue;
      const wire = alertWire(a, g);
      room.alertsSent.push(wire);
      room.broadcast(wire);
    }
    // 민방위 훈련.
    const d = rules.drill;
    const w = drillWindow(d, g);
    const forced = cfg.drillForce && !room.drillForcedDone;
    const active = forced || (g >= w.start && g < w.end);
    const key = forced ? 'forced' : `${w.start}`;
    if (!room.drill || room.drill.key !== key) room.drill = { key, on: false, noticed: false, done: [], until: forced ? g + d.minutes * 60000 : w.end };
    const dr = room.drill;
    if (!dr.noticed && !forced && g >= w.notice && g < w.start) {
      dr.noticed = true;
      const wire = alertWire({ id: 'drill_notice', level: 'safety', sender: '민방위', text: d.notice }, g);
      room.alertsSent.push(wire);
      room.broadcast(wire);
    }
    if (active && !dr.on) {
      dr.on = true;
      const wire = alertWire({ id: 'drill_start', level: 'emergency', sender: '민방위', text: d.start }, g);
      room.alertsSent.push(wire);
      room.broadcast(wire);
      room.broadcast({ t: 'drill', on: true, shelter: shelterWire(), until: dr.until });
    }
    if (dr.on && (forced ? g >= dr.until : !active)) {
      dr.on = false;
      if (forced) room.drillForcedDone = true;
      const wire = alertWire({ id: 'drill_end', level: 'safety', sender: '민방위', text: d.end }, g);
      room.alertsSent.push(wire);
      room.broadcast(wire);
      room.broadcast({ t: 'drill', on: false, shelter: shelterWire(), until: 0 });
    }
    if (dr.on) {
      const s = d.shelter;
      for (const p of room.players.values()) {
        if (!p.online || dr.done.includes(p.id)) continue;
        if (Math.hypot(p.x - s.x, p.z - s.z) > s.radius) continue;
        dr.done.push(p.id);
        p.profile.sol += d.reward;
        earn(p.profile, d.reward);
        sendTo(p, { t: 'drill_done', reward: d.reward, sol: p.profile.sol });
      }
    }
  }

  /** 들어온 사람에게 오늘 온 재난문자 · 진행 중인 훈련을 알린다. */
  function onJoin(room, player) {
    if (!rules) return;
    for (const wire of room.alertsSent ?? []) sendTo(player, { ...wire, late: true });
    if (room.drill?.on) sendTo(player, { t: 'drill', on: true, shelter: shelterWire(), until: room.drill.until, done: room.drill.done.includes(player.id) });
  }

  return { handleSteps, tick, onJoin, drillActive, DAY_MS };
}
