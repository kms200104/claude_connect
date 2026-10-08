// 일거리 (v0.12, 서버 권위): 배달 알바. 데이터는 data/jobs/jobs.json.
// job_take → 서버가 받을 곳과 갖다줄 주민 집을 골라 job 으로 알린다. job_pick(받을 곳 곁) → 물건을 든다 (모두에게 들고 있는 모습).
// job_drop(주민 집 곁) → 삯 + (시간 안이면) 팁 + (친구가 곁에 있으면) 두 사람 모두 같이 보너스. 시간이 지나도 실패는 없다.
// 하던 배달은 접속 동안만 기억한다 (나갔다 오면 다시 받는다). 하루 건수만 프로필에 남긴다.
// 연속 팁 (v0.13.7): 시간 안에 갖다줄 때마다 연속 횟수(profile.tipStreak)가 오르고, 2번째부터 삯 × streak.per × (연속 - 1)
// (최대 streak.max)을 더 받는다. 늦게 갖다주거나 들고 있던 배달을 그만두면 0 으로.
import { ErrorCode } from './protocol.js';
import { earn } from './economy.js';
import { addFriendship, relationOf } from './quests.js';
import { pickWeighted } from './gamedata.js';
import { bump } from './progress.js';
import { lobbyOf } from './homes.js';

/** jobs.json 검사 + 받을 곳 Map. 집이 없는 주민은 homes(주민 → 아파트 동)의 공동 현관 앞으로 배달한다. */
export function loadJobs(raw, npcs, realestate = null, floorplans = null) {
  if (!raw) return null;
  const pickups = new Map(raw.pickups.map((p) => [p.id, p]));
  for (const k of raw.kinds) {
    for (const id of k.pickups) if (!pickups.has(id)) throw new Error(`jobs: ${k.id} 의 받을 곳 ${id} 이(가) 없음`);
  }
  const houses = [];
  for (const n of npcs.values()) {
    if (n.house) {
      houses.push({ npc: n.id, name: n.name, x: n.house.x, z: n.house.z });
      continue;
    }
    const building = raw.homes?.[n.id];
    if (!building) continue;
    const lobby = realestate && floorplans ? lobbyOf(realestate, floorplans, building) : null;
    if (!lobby) throw new Error(`jobs: ${n.id} 의 아파트 ${building}동 이(가) 없음`);
    houses.push({ npc: n.id, name: n.name, x: lobby.x, z: lobby.z });
  }
  if (houses.length === 0) throw new Error('jobs: 집이 있는 주민이 없음');
  return { ...raw, pickups, kindById: new Map(raw.kinds.map((k) => [k.id, k])), houses };
}

/** 연속 팁 보너스: 2번째 연속부터 삯 × per × (연속 - 1), 최대 삯 × max. 100 솔 단위. */
export function streakBonusOf(rules, pay, streak) {
  const s = rules.streak;
  if (!s || streak < 2) return 0;
  return Math.round((pay * Math.min(s.per * (streak - 1), s.max)) / 100) * 100;
}

/** 받을 곳 → 집 거리로 삯과 넉넉한 시간(초)을 매긴다. */
export function quoteJob(rules, kind, from, to) {
  const dist = Math.hypot(to.x - from.x, to.z - from.z);
  const pay = Math.round((kind.base + kind.per_m * dist) / 100) * 100;
  const limitS = Math.round((rules.grace_s + dist / rules.pace_mps) * (kind.time_scale ?? 1));
  return { dist: Math.round(dist), pay, tip: Math.round((pay * kind.tip) / 100) * 100, limitS };
}

export function createJobs({ data, random, now, clock, send, sendTo, sendProfile, act }) {
  const rules = data.jobs;

  function todayCount(p) {
    const today = clock.day();
    if (p.jobDay?.day !== today) p.jobDay = { day: today, done: 0 };
    return p.jobDay.done;
  }

  function wire(player) {
    const j = player.job;
    const p = player.profile;
    return {
      t: 'job',
      done: todayCount(p),
      max: rules.daily_max,
      job: j
        ? { kind: j.kind, name: j.name, item: j.item, stage: j.stage, from: j.from, to: j.to, pay: j.pay, tip: j.tip, dist: j.dist, limit_s: j.limitS, left_ms: Math.max(0, j.dueAt - now()) }
        : null,
      streak: p.tipStreak ?? 0,
      kinds: rules.kinds.map((k) => ({ id: k.id, name: k.name, about: k.about })),
    };
  }

  /** 휴대폰 일거리 앱이 열릴 때 · 상태가 바뀔 때. */
  function sendJob(player) {
    sendTo(player, wire(player));
  }

  function take(ctx, msg, fail) {
    const { player } = ctx;
    if (player.job) return fail(ErrorCode.jobBusy);
    if (todayCount(player.profile) >= rules.daily_max) return fail(ErrorCode.jobLimit);
    const kind = rules.kindById.get(msg.kind) ?? pickWeighted(rules.kinds, (k) => k.weight ?? 1, random);
    const from = rules.pickups.get(kind.pickups[Math.floor(random() * kind.pickups.length)]);
    // 같은 집이 연달아 나오지 않게, 받을 곳에서 너무 가까운 집(15m 안)도 뺀다.
    const houses = rules.houses.filter((h) => h.npc !== player.lastJobNpc && Math.hypot(h.x - from.x, h.z - from.z) > 15);
    const pool = houses.length > 0 ? houses : rules.houses;
    const to = pool[Math.floor(random() * pool.length)];
    const q = quoteJob(rules, kind, from, to);
    player.job = {
      kind: kind.id,
      name: kind.name,
      item: kind.item,
      stage: 'pickup',
      from: { id: from.id, name: from.name, x: from.x, z: from.z },
      to: { npc: to.npc, name: to.name, x: to.x, z: to.z },
      pay: q.pay,
      tip: q.tip,
      dist: q.dist,
      limitS: q.limitS,
      dueAt: 0,
    };
    // 친구 화면에 헬멧 · 가방이 바로 보이도록 (스냅샷의 job).
    if (ctx.room) ctx.room.dirty = true;
    sendJob(player);
  }

  function pick(ctx, msg, fail) {
    const { player, room } = ctx;
    const j = player.job;
    if (!j || j.stage !== 'pickup') return fail(ErrorCode.noJob);
    if (Math.hypot(player.x - j.from.x, player.z - j.from.z) > rules.range + 0.5) return fail(ErrorCode.notAtJob);
    j.stage = 'carry';
    // 시간은 물건을 받은 때부터 잰다.
    j.dueAt = now() + j.limitS * 1000;
    room.dirty = true;
    act(room, player, 'carry', j.item);
    sendJob(player);
  }

  function drop(ctx, msg, fail) {
    const { player, room } = ctx;
    const j = player.job;
    if (!j || j.stage !== 'carry') return fail(ErrorCode.noJob);
    if (Math.hypot(player.x - j.to.x, player.z - j.to.z) > rules.house_range + 0.5) return fail(ErrorCode.notAtJob);
    const p = player.profile;
    const onTime = now() <= j.dueAt;
    const tip = onTime ? j.tip : 0;
    p.tipStreak = onTime ? (p.tipStreak ?? 0) + 1 : 0;
    const streakBonus = streakBonusOf(rules, j.pay, p.tipStreak);
    // 같이 배달: 같은 방의 다른 사람이 곁에 있으면 두 사람 모두 보너스 (빼앗지 않고 더한다).
    const friends = [...room.players.values()].filter(
      (o) => o !== player && o.online && Math.hypot(o.x - player.x, o.z - player.z) <= rules.together_m,
    );
    const bonus = friends.length > 0 ? Math.round((j.pay * rules.together) / 100) * 100 : 0;
    const total = j.pay + tip + bonus + streakBonus;
    p.sol += total;
    earn(p, total);
    p.jobDay.done += 1;
    bump(p, 'deliver');
    addFriendship(relationOf(p, j.to.npc), rules.friend);
    for (const o of friends) {
      o.profile.sol += bonus;
      earn(o.profile, bonus);
      sendTo(o, { t: 'job_result', by: player.id, kind: j.kind, npc: j.to.npc, pay: 0, tip: 0, bonus, total: bonus, helper: true, sol: o.profile.sol });
      sendProfile(o);
    }
    player.lastJobNpc = j.to.npc;
    player.job = null;
    room.dirty = true;
    room.saveDirty = true;
    send(ctx.ws, { t: 'job_result', rid: msg.rid, by: player.id, kind: j.kind, npc: j.to.npc, pay: j.pay, tip, bonus, streak: p.tipStreak, streakBonus, total, onTime, with: friends.map((o) => o.id), sol: p.sol });
    act(room, player, 'deliver', j.to.npc);
    sendProfile(player);
    sendJob(player);
  }

  function quit(ctx) {
    const { player, room } = ctx;
    if (player.job?.stage === 'carry') {
      act(room, player, 'carry', '');
      room.dirty = true;
      // 들고 있던 배달을 그만두면 연속 팁도 끊긴다.
      player.profile.tipStreak = 0;
    }
    player.job = null;
    room.dirty = true;
    sendJob(player);
  }

  /** job_info · job_take · job_pick · job_drop · job_quit */
  function handle(ctx, msg, fail) {
    if (!rules) return fail(ErrorCode.noJob);
    if (msg.t === 'job_info') return sendJob(ctx.player);
    if (msg.t === 'job_quit') return quit(ctx);
    if (!ctx.player.acceptRid(msg.rid)) return;
    if (msg.t === 'job_take') return take(ctx, msg, fail);
    if (msg.t === 'job_pick') return pick(ctx, msg, fail);
    return drop(ctx, msg, fail);
  }

  /** 다른 사람에게 보이는 손에 든 것 (배달 중이면 그 물건). */
  const carried = (player) => (player.job?.stage === 'carry' ? player.job.item : null);

  return { handle, sendJob, carried };
}
