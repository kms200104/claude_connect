// v0.28 헌터 (서버 권위): 게이트가 열리는 도시에서 크리처를 사냥하는 헌터 — 협회 등급 · 마석 · 현상금 의뢰 · 길드.
// data/hunter/hunter.json. 클라이언트는 요청만:
//   hunter_sell { slot, n? } | { all: true }  협회 출장소 창구에서 마석 팔기 (등급 · 길드만큼 더 받는다)
//   hunter_rank {}                            창구에서 등급 재심사 (점수가 다음 등급 기준을 넘었을 때)
//   hunter_claim { b }                        현상금 의뢰 완료 보고 (헌터넷 앱, 다 채운 것만)
//   guild_create { name } · guild_join {} · guild_leave {}   길드 (같은 방 둘)
//   stat_up { s }                             v0.28.1 스탯 포인트 하나를 힘 · 체력 · 민첩 · 행운에 쓴다
//   awaken { a }                              v0.28.5 각성 고르기 (level.awaken.slots 레벨마다 하나, 바꿀 수 없다)
//   hunter_buy { i }                          v0.28.14 협회 상점 (창구): v0.28.15 헌터 마일리지로 산다 (store.items 의 id)
//                                             up: bag (아공간 주머니 — 내 가방 칸) · stash (아공간 상자 — 방 전체 거점 상자 칸) 은 산 즉시 늘어난다
//   awaken_use { a }                          v0.28.5 쓰는 각성 (그림자 걸음 · 마력 방패) → 방 전체 awaken_fx { id, a, ms }
// v0.28.1 레벨: 경험치(처치 · 게이트 · 의뢰 · 뒤지기 · 보급 상자)가 차면 레벨이 오르고 스탯 포인트를 받는다, 레벨이 되면 기술을 배운다.
// 서버 → hunter { rank, pts, next, kills, bounties, guild } (나) · guild { … } (방 전체) · hunter_result { kind, … }.
// 처치 · 뒤지기 · 보급 상자 · 게이트는 survival.js 가 onKill · onLoot · onSupply · onGate 로 알린다.
import { ErrorCode } from './protocol.js';
import { addItem, removeAt } from './inventory.js';
import { earn } from './economy.js';

const hashString = (s) => {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
};

/** 파일을 읽어 검사한다 (모르는 아이템 · 크리처면 켜지 않는다). */
export function loadHunter(raw, isKnown) {
  if (!raw) return null;
  const ranks = raw.ranks.list.map((r, i) => ({ ...r, index: i }));
  for (const list of Object.values(raw.kill?.mana ?? {})) for (const e of list) if (!isKnown(e.id)) throw new Error(`hunter mana: unknown item ${e.id}`);
  for (const id of raw.office?.sell_items ?? []) if (!isKnown(id)) throw new Error(`hunter office: unknown item ${id}`);
  for (const [rank, a] of Object.entries(raw.gates?.assoc?.by_gate ?? {})) for (const it of a.items ?? []) if (!isKnown(it.id)) throw new Error(`hunter assoc ${rank}: unknown item ${it.id}`);
  for (const it of raw.store?.items ?? []) {
    if (!isKnown(it.id)) throw new Error(`hunter store: unknown item ${it.id}`);
    if (it.up && !['bag', 'stash'].includes(it.up)) throw new Error(`hunter store ${it.id}: unknown upgrade ${it.up}`);
    if (!ranks.some((r) => r.id === it.rank)) throw new Error(`hunter store ${it.id}: unknown rank ${it.rank}`);
    if (!Number.isInteger(it.cost) || it.cost <= 0) throw new Error(`hunter store ${it.id}: bad cost`);
  }
  // v0.28.8 전직 · 기술 나무: 앞선 기술 · 액티브가 있어야 한다.
  const J = raw.level?.jobs;
  const jobById = new Map();
  for (const job of J?.list ?? []) {
    const ids = new Set(job.tree.map((n) => n.id));
    for (const n of job.tree) {
      for (const r of n.req ?? []) if (!ids.has(r)) throw new Error(`hunter job ${job.id}: ${n.id} needs unknown ${r}`);
      if (n.active && !J.actives?.[n.active]) throw new Error(`hunter job ${job.id}: unknown active ${n.active}`);
    }
    jobById.set(job.id, { ...job, nodeById: new Map(job.tree.map((n) => [n.id, n])) });
  }
  return { ...raw, ranks, rankById: new Map(ranks.map((r) => [r.id, r])), bountyById: new Map(raw.bounty.pool.map((b) => [b.id, b])), jobById };
}

/** 저장된 헌터 기록 { rank, pts, kills, bday, bprog: { id: n }, bdone: [id] } (모양이 틀리면 새로). */
export function sanitizeHunter(raw, rules) {
  const intOr = (v, d) => (Number.isInteger(v) ? v : d);
  const h = raw && typeof raw === 'object' ? raw : {};
  return {
    rank: typeof h.rank === 'string' && rules?.rankById.has(h.rank) ? h.rank : 'E',
    pts: Math.max(0, intOr(h.pts, 0)),
    kills: Math.max(0, intOr(h.kills, 0)),
    gates: Math.max(0, intOr(h.gates, 0)),
    bday: intOr(h.bday, -1),
    bprog: Object.fromEntries(Object.entries(h.bprog ?? {}).filter(([id, n]) => rules?.bountyById.has(id) && Number.isInteger(n) && n >= 0)),
    bdone: Array.isArray(h.bdone) ? h.bdone.filter((id) => rules?.bountyById.has(id)) : [],
    // v0.28.1 레벨 · 경험치 · 남은 스탯 포인트 · 쓴 스탯.
    lv: Math.max(1, Math.min(rules?.level?.max ?? 50, intOr(h.lv, 1))),
    xp: Math.max(0, intOr(h.xp, 0)),
    sp: Math.max(0, intOr(h.sp, 0)),
    st: Object.fromEntries(Object.keys(rules?.level?.stats ?? {}).map((k) => [k, Math.max(0, Math.min(rules.level.stats[k].cap ?? 99, intOr(h.st?.[k], 0)))])),
    // v0.28.5 고른 각성 (순서대로, 자리 수까지).
    aw: Array.isArray(h.aw) ? [...new Set(h.aw.filter((a) => rules?.level?.awaken?.list?.some((x) => x.id === a)))].slice(0, rules?.level?.awaken?.slots?.length ?? 0) : [],
    // v0.28.8 직업 · 남은 기술 포인트 · 배운 기술 (id → 단계).
    ...sanitizeJob(h, rules, intOr),
    // v0.28.12 오늘 (UTC 날짜) 행동 경험치를 받은 수.
    actDay: intOr(h.actDay, -1),
    acts: Object.fromEntries(Object.entries(h.acts ?? {}).filter(([k, v]) => rules?.level?.xp?.acts?.[k] !== undefined && Number.isInteger(v) && v >= 0)),
    // v0.28.15 헌터 마일리지 (협회 상점에서 쓴다, 등급 심사 점수 pts 와 따로). 마일리지가 없던 기록은 모은 점수만큼 들고 시작한다.
    mi: Number.isInteger(h.mi) ? Math.max(0, h.mi) : Math.max(0, intOr(h.pts, 0) - Math.max(0, intOr(h.spent, 0))),
  };
}

function sanitizeJob(h, rules, intOr) {
  const job = typeof h.job === 'string' ? rules?.jobById?.get(h.job) : null;
  if (!job) return { job: '', adv: false, jp: 0, jt: {} };
  const jt = {};
  for (const [id, n] of Object.entries(h.jt ?? {})) {
    const node = job.nodeById.get(id);
    if (node && Number.isInteger(n) && n > 0) jt[id] = Math.min(n, node.max);
  }
  // v0.28.9 2차 전직 (advance 가 있는 직업만).
  return { job: job.id, adv: h.adv === true && Boolean(job.advance), jp: Math.max(0, intOr(h.jp, 0)), jt };
}

/** v0.28.8 그 레벨에서 전직하면 받는 기술 포인트 (전직 레벨부터 레벨마다). */
export function jobPointsAt(rules, lv) {
  const J = rules?.level?.jobs;
  return J ? Math.max(0, lv - J.level + 1) * J.per_level : 0;
}

/** 배운 기술이 주는 값의 합 (fx[key] × 단계). */
export function jobFx(rules, profile, key) {
  const h = profile?.hunter;
  const job = h?.job ? rules?.jobById?.get(h.job) : null;
  if (!job) return 0;
  let sum = 0;
  for (const [id, n] of Object.entries(h.jt ?? {})) sum += (job.nodeById.get(id)?.fx?.[key] ?? 0) * n;
  return sum;
}

/** 그 액티브 기술을 배웠는지. */
export function hasActive(rules, profile, active) {
  const h = profile?.hunter;
  const job = h?.job ? rules?.jobById?.get(h.job) : null;
  return Boolean(job) && job.tree.some((n) => n.active === active && (h.jt?.[n.id] ?? 0) > 0);
}

/** 이 나무에 쓴 포인트. */
const spentOf = (h) => Object.values(h.jt ?? {}).reduce((a, b) => a + b, 0);

/** 다음 레벨까지 경험치. */
export function xpToNext(rules, lv) {
  const L = rules?.level;
  return L ? Math.round(L.base * lv ** L.power) : 0;
}

/** 스탯 하나 (프로필 기준, 없으면 0). */
export function statOf(rules, profile, key) {
  return Number.isInteger(profile?.hunter?.st?.[key]) ? profile.hunter.st[key] : 0;
}

/** 배운 기술인지 (레벨). */
export function hasSkill(rules, profile, id) {
  const sk = rules?.level?.skills?.find((x) => x.id === id);
  return Boolean(sk) && (profile?.hunter?.lv ?? 1) >= sk.level;
}

/** v0.28.5 그 레벨에서 고를 수 있는 각성 자리 수. */
export function awakenSlots(rules, lv) {
  return (rules?.level?.awaken?.slots ?? []).filter((l) => lv >= l).length;
}

/** 고른 각성인지. */
export function hasAwaken(profile, id) {
  return Array.isArray(profile?.hunter?.aw) && profile.hunter.aw.includes(id);
}

/** 저장된 길드 { name, members: [uid], pts, since } (같은 방 둘). */
export function sanitizeGuild(raw, profiles) {
  if (!raw || typeof raw.name !== 'string' || !raw.name.trim()) return null;
  const members = Array.isArray(raw.members) ? raw.members.filter((uid) => typeof uid === 'string' && profiles.has(uid)).slice(0, 2) : [];
  if (members.length === 0) return null;
  return { name: raw.name.trim().slice(0, 16), members, pts: Math.max(0, Math.trunc(Number(raw.pts) || 0)), since: Number.isFinite(raw.since) ? raw.since : 0 };
}

export function createHunter({ data, cfg, clock, random, now, send, sendTo, sendInventory, sendProfile, saveRoom, dropAt, inShop }) {
  /** 체력 스탯이 오르면 survival 이 하트를 다시 보낸다 (createSurvival 뒤에 이어 준다). */
  let onVit = null;
  const H = data.hunter;
  const ranks = H?.ranks ?? [];

  const rec = (player) => {
    player.profile.hunter = sanitizeHunter(player.profile.hunter, H);
    if (cfg.startHunterLv > 1 && !player.startLvApplied) {
      player.startLvApplied = true;
      if (player.profile.hunter.lv < cfg.startHunterLv) player.profile.hunter.lv = Math.min(H.level?.max ?? 50, cfg.startHunterLv);
    }
    if (cfg.startMileage > 0 && !player.startMiApplied) {
      player.startMiApplied = true;
      player.profile.hunter.mi = Math.max(player.profile.hunter.mi, cfg.startMileage);
    }
    return player.profile.hunter;
  };
  const rankOf = (h) => H.rankById.get(h.rank) ?? ranks[0];
  const nextRank = (h) => ranks[rankOf(h).index + 1] ?? null;

  /** 오늘(마을 날짜)의 의뢰 — 방 시드로 per_day 개 (같은 방 · 같은 날은 늘 같다). */
  function todayBounties(room) {
    const day = clock.day();
    if (room.bountyDay === day && room.bountyList) return room.bountyList;
    const pool = [...H.bounty.pool];
    let seed = hashString(`${room.code}:${day}`);
    const out = [];
    while (out.length < Math.min(H.bounty.per_day, pool.length)) {
      seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
      out.push(pool.splice(seed % pool.length, 1)[0]);
    }
    room.bountyDay = day;
    room.bountyList = out;
    return out;
  }

  /** 날짜가 바뀌었으면 진행을 비운다. */
  function freshDay(h) {
    const day = clock.day();
    if (h.bday !== day) {
      h.bday = day;
      h.bprog = {};
      h.bdone = [];
    }
  }

  const guildLevel = (g) => {
    let lv = H.guild.levels[0];
    for (const l of H.guild.levels) if ((g?.pts ?? 0) >= l.points) lv = l;
    return lv;
  };
  const guildOf = (room, player) => (room.guild && room.guild.members.includes(player.uid) ? room.guild : null);

  function guildWire(room) {
    const g = room.guild;
    if (!g) return null;
    const lv = guildLevel(g);
    const next = H.guild.levels.find((l) => l.level === lv.level + 1) ?? null;
    const members = g.members.map((uid) => {
      const p = room.profiles.get(uid);
      return { id: p?.slot ?? 0, rank: sanitizeHunter(p?.hunter, H).rank, name: p?.name ?? '' };
    });
    return { name: g.name, pts: g.pts, level: lv.level, title: lv.name, next: next?.points ?? 0, members };
  }

  function wire(room, player) {
    const h = rec(player);
    freshDay(h);
    const r = rankOf(h);
    const nx = nextRank(h);
    return {
      rank: r.id, pts: h.pts, mi: h.mi, bag: player.profile.bagExtra ?? 0, stashCap: (data.survival?.base?.slots ?? 12) + (room.stashExtra ?? 0), next: nx?.points ?? 0, nextRank: nx?.id ?? '', kills: h.kills, gates: h.gates,
      bounties: todayBounties(room).map((b) => ({ id: b.id, kind: b.kind, k: b.k ?? '', n: b.n, got: Math.min(b.n, h.bprog[b.id] ?? 0), done: h.bdone.includes(b.id), reward: b.reward, pts: b.pts, name: b.name, desc: b.desc })),
      guild: guildWire(room),
      lv: h.lv, xp: h.xp, xpNext: h.lv >= (H.level?.max ?? 50) ? 0 : xpToNext(H, h.lv), sp: h.sp, st: { ...h.st },
      skills: (H.level?.skills ?? []).filter((sk) => h.lv >= sk.level).map((sk) => sk.id),
      aw: [...h.aw], awSlots: awakenSlots(H, h.lv),
      awReady: Object.fromEntries(h.aw.map((a) => [a, Math.max(0, (player.awReady?.[a] ?? 0) - now())])),
      job: h.job, adv: h.adv, jp: h.jp, jt: { ...h.jt },
      jReady: Object.fromEntries(Object.keys(H.level?.jobs?.actives ?? {}).filter((a) => hasActive(H, player.profile, a)).map((a) => [a, Math.max(0, (player.skReady?.[a] ?? 0) - now())])),
    };
  }

  /** 경험치를 더한다 (레벨이 오르면 스탯 포인트 · 기술). 오른 레벨 수. */
  function addXp(room, player, xp) {
    const L = H?.level;
    if (!L || !player || xp <= 0) return 0;
    const h = rec(player);
    h.xp += Math.round(xp);
    let ups = 0;
    while (h.lv < L.max && h.xp >= xpToNext(H, h.lv)) {
      h.xp -= xpToNext(H, h.lv);
      h.lv++;
      h.sp += L.points_per_level;
      if (h.job) h.jp += L.jobs?.per_level ?? 0;
      ups++;
    }
    if (h.lv >= L.max) h.xp = 0;
    if (ups > 0) {
      const learned = L.skills.filter((sk) => sk.level > h.lv - ups && sk.level <= h.lv).map((sk) => sk.id);
      sendTo(player, { t: 'hunter_result', kind: 'level', lv: h.lv, sp: h.sp, learned });
      room.broadcast({ t: 'hunter_level', id: player.id, lv: h.lv }, player.id);
    }
    return ups;
  }

  const sendHunter = (room, player) => sendTo(player, { t: 'hunter', ...wire(room, player) });
  const sendGuild = (room) => room.broadcast({ t: 'guild', g: guildWire(room) });

  /** 점수를 더한다 (길드원이면 길드 점수도). */
  function addPoints(room, player, pts) {
    if (pts <= 0) return;
    rec(player).pts += pts;
    // v0.28.15 헌터 마일리지: 점수만큼 (mileage.per_point 배).
    rec(player).mi += Math.round(pts * (H.mileage?.per_point ?? 1));
    const g = guildOf(room, player);
    if (g) {
      const before = guildLevel(g).level;
      g.pts += pts;
      if (guildLevel(g).level !== before) room.broadcast({ t: 'guild', g: guildWire(room), up: true });
    }
  }

  /** 의뢰 진행 (kind · 크리처 k). 바뀐 게 있으면 true. */
  function progress(room, player, kind, k = '', n = 1) {
    const h = rec(player);
    freshDay(h);
    let changed = false;
    for (const b of todayBounties(room)) {
      if (b.kind !== kind || (b.k && b.k !== k) || h.bdone.includes(b.id)) continue;
      const before = h.bprog[b.id] ?? 0;
      if (before >= b.n) continue;
      h.bprog[b.id] = Math.min(b.n, before + n);
      changed = true;
    }
    return changed;
  }

  // ---- survival.js 가 알린다 ----

  /** 크리처를 쓰러뜨렸다: 점수 (길드원이 곁이면 더) · 마석 · 의뢰. */
  function onKill(room, player, c) {
    if (!H || !player) return;
    const h = rec(player);
    h.kills++;
    let pts = H.kill.points[c.k] ?? 1;
    const g = guildOf(room, player);
    if (g) {
      const mate = [...room.players.values()].find((p) => p !== player && p.online && g.members.includes(p.uid));
      if (mate && Math.hypot(mate.x - player.x, mate.z - player.z) <= H.kill.party_range) pts = Math.round(pts * H.kill.party_mult);
    }
    addPoints(room, player, pts);
    const got = [];
    const luck = 1 + statOf(H, player.profile, 'luk') * (H.level?.stats?.luk?.mana ?? 0);
    for (const e of H.kill.mana[c.k] ?? []) {
      if (random() >= e.chance * luck) continue;
      const [lo, hi] = e.n ?? [1, 1];
      const n = lo + Math.floor(random() * (hi - lo + 1));
      dropAt(room, e.id, n, c.x + (random() - 0.5) * 0.8, c.z + (random() - 0.5) * 0.8);
      got.push({ id: e.id, n });
    }
    progress(room, player, 'kill', c.k);
    const xp = (H.level?.xp?.kill?.[c.k] ?? 8) * (c.boss ? (H.level?.xp?.boss_mult ?? 1) : 1);
    sendTo(player, { t: 'hunter_result', kind: 'kill', k: c.k, pts, mana: got, xp });
    addXp(room, player, xp);
    sendHunter(room, player);
    return { pts, xp, mana: got };
  }

  /** v0.28.12 행동 경험치 (level.xp.acts[kind], 하루 acts_cap 번까지). 받은 경험치 (0 = 없음 · 다 찼음). */
  function act(room, player, kind, n = 1) {
    const X = H?.level?.xp;
    const per = X?.acts?.[kind];
    if (!per || !player || !room) return 0;
    const h = rec(player);
    const day = Math.floor(Date.now() / 86400000);
    if (h.actDay !== day) {
      h.actDay = day;
      h.acts = {};
    }
    h.acts ??= {};
    const cap = X.acts_cap?.[kind] ?? Infinity;
    const take = Math.max(0, Math.min(n, cap - (h.acts[kind] ?? 0)));
    if (take <= 0) return 0;
    h.acts[kind] = (h.acts[kind] ?? 0) + take;
    const xp = per * take;
    sendTo(player, { t: 'hunter_result', kind: 'act', a: kind, xp });
    grant(room, player, { xp });
    return xp;
  }

  /** v0.28.12 협회 지급 · 여러 행동의 점수 · 경험치를 더한다 (레벨이 오르면 알린다). */
  function grant(room, player, { pts = 0, xp = 0 } = {}) {
    if (!H || !player) return;
    if (pts > 0) addPoints(room, player, pts);
    if (xp > 0) addXp(room, player, xp);
    sendHunter(room, player);
  }

  function onLoot(room, player) {
    if (!H || !player) return;
    progress(room, player, 'loot');
    addXp(room, player, H.level?.xp?.loot ?? 0);
    sendHunter(room, player);
  }

  function onSupply(room, player) {
    if (!H || !player) return;
    progress(room, player, 'supply');
    addXp(room, player, H.level?.xp?.supply ?? 0);
    sendHunter(room, player);
  }

  /** 게이트를 공략했다 (게이트 점수 · 의뢰). */
  function onGate(room, player, pts, rank = 'E') {
    if (!H || !player) return;
    rec(player).gates++;
    addPoints(room, player, pts);
    // v0.28.15 게이트를 깨면 등급만큼 마일리지 덤.
    rec(player).mi += H.mileage?.gate?.[rank] ?? 0;
    progress(room, player, 'gate');
    addXp(room, player, H.level?.xp?.gate?.[rank] ?? 0);
    sendHunter(room, player);
  }

  // ---- 요청 ----

  const nearOffice = (player) => !player.home && !inShop(player) && Math.hypot(player.x - H.office.x, player.z - H.office.z) <= H.office.range + 0.4;

  function sellBonus(room, player) {
    return rankOf(rec(player)).sell_bonus + (guildOf(room, player) ? H.guild.sell_bonus : 0);
  }

  function handle(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!H) return fail(ErrorCode.badMessage);
    switch (msg.t) {
      case 'hunter_sell': {
        if (!nearOffice(player)) return fail(ErrorCode.notAtOffice);
        const sellable = new Set(H.office.sell_items);
        const picks = [];
        if (msg.all === true) {
          player.slots.forEach((s, i) => {
            if (s && sellable.has(s.id)) picks.push({ slot: i, n: s.n });
          });
        } else {
          const s = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
          if (!s || !sellable.has(s.id)) return fail(ErrorCode.badItem);
          const n = Number.isInteger(msg.n) && msg.n > 0 ? Math.min(msg.n, s.n) : s.n;
          picks.push({ slot: msg.slot, n });
        }
        if (picks.length === 0) return fail(ErrorCode.notEnoughItems);
        const bonus = sellBonus(room, player);
        let amount = 0;
        let pts = 0;
        let count = 0;
        const sold = [];
        for (const p of picks) {
          const s = player.slots[p.slot];
          const id = s.id;
          amount += Math.round(data.items.get(id).price * p.n * (1 + bonus));
          pts += (H.office.sell_points[id] ?? 0) * p.n;
          count += p.n;
          removeAt(player.slots, p.slot, p.n);
          sold.push({ id, n: p.n });
        }
        player.profile.sol += amount;
        earn(player.profile, amount);
        addPoints(room, player, pts);
        progress(room, player, 'sell', '', count);
        sendInventory(player);
        sendProfile(player);
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'sell', sold, amount, pts, bonus });
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'hunter_buy': {
        if (!nearOffice(player)) return fail(ErrorCode.notAtOffice);
        const it = (H.store?.items ?? []).find((x) => x.id === msg.i);
        if (!it) return fail(ErrorCode.badItem);
        const h = rec(player);
        if (rankOf(h).index < (H.rankById.get(it.rank)?.index ?? 0)) return fail(ErrorCode.rankTooLow);
        if (it.job && h.job !== it.job) return fail(ErrorCode.jobOnly);
        if (h.mi < it.cost) return fail(ErrorCode.notEnoughMileage);
        const n = it.n ?? 1;
        if (it.up === 'bag') {
          // 아공간 주머니: 차례대로 (at = 지금까지 늘린 칸).
          if ((player.profile.bagExtra ?? 0) !== (it.at ?? 0)) return fail(ErrorCode.badItem);
          player.profile.bagExtra = (player.profile.bagExtra ?? 0) + it.add;
          for (let i = 0; i < it.add; i++) player.slots.push(null);
        } else if (it.up === 'stash') {
          if ((room.stashExtra ?? 0) !== (it.at ?? 0)) return fail(ErrorCode.badItem);
          room.stashExtra = (room.stashExtra ?? 0) + it.add;
        } else if (!addItem(player.slots, it.id, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
        h.mi -= it.cost;
        sendInventory(player);
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'buy', i: it.id, n, cost: it.cost, mi: h.mi, up: it.up ?? '', add: it.add ?? 0 });
        if (it.up === 'stash') for (const p of room.players.values()) sendHunter(room, p);
        else sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'hunter_rank': {
        if (!nearOffice(player)) return fail(ErrorCode.notAtOffice);
        const h = rec(player);
        const nx = nextRank(h);
        if (!nx || h.pts < nx.points) return fail(ErrorCode.rankNotReady);
        // 점수가 여러 등급을 넘었으면 한꺼번에.
        let to = nx;
        for (const r of ranks) if (r.index > to.index && h.pts >= r.points) to = r;
        const from = h.rank;
        h.rank = to.id;
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'rank', from, rank: to.id });
        room.broadcast({ t: 'hunter_rank', id: player.id, rank: to.id }, player.id);
        sendHunter(room, player);
        if (guildOf(room, player)) sendGuild(room);
        saveRoom(room);
        return;
      }
      case 'hunter_claim': {
        const h = rec(player);
        freshDay(h);
        const b = todayBounties(room).find((x) => x.id === msg.b);
        if (!b) return fail(ErrorCode.badItem);
        if (h.bdone.includes(b.id)) return fail(ErrorCode.alreadyLooted);
        if ((h.bprog[b.id] ?? 0) < b.n) return fail(ErrorCode.bountyNotDone);
        h.bdone.push(b.id);
        player.profile.sol += b.reward;
        earn(player.profile, b.reward);
        addPoints(room, player, b.pts);
        sendProfile(player);
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'claim', b: b.id, reward: b.reward, pts: b.pts, xp: b.pts * (H.level?.xp?.claim_mult ?? 0) });
        addXp(room, player, b.pts * (H.level?.xp?.claim_mult ?? 0));
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'stat_up': {
        const def = H.level?.stats?.[msg.s];
        const h = rec(player);
        if (!def) return fail(ErrorCode.badItem);
        if (h.sp <= 0) return fail(ErrorCode.noStatPoint);
        if ((h.st[msg.s] ?? 0) >= (def.cap ?? 99)) return fail(ErrorCode.statCapped);
        h.sp--;
        h.st[msg.s] = (h.st[msg.s] ?? 0) + 1;
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'stat', s: msg.s, v: h.st[msg.s], sp: h.sp });
        sendHunter(room, player);
        // 체력이 오르면 하트도 (survival hpWire).
        if (msg.s === 'vit') onVit?.(room, player);
        saveRoom(room);
        return;
      }
      case 'awaken': {
        const def = H.level?.awaken?.list?.find((x) => x.id === msg.a);
        const h = rec(player);
        if (!def) return fail(ErrorCode.badItem);
        if (h.aw.includes(def.id)) return fail(ErrorCode.alreadyLooted);
        if (h.aw.length >= awakenSlots(H, h.lv)) return fail(ErrorCode.noAwakenSlot);
        h.aw.push(def.id);
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'awaken', a: def.id });
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'awaken_use': {
        const def = H.level?.awaken?.list?.find((x) => x.id === msg.a);
        if (!def || !def.active || !hasAwaken(player.profile, def.id)) return fail(ErrorCode.notAwakened);
        if (player.downed) return fail(ErrorCode.downed);
        const t = now();
        player.awReady ??= {};
        if (t < (player.awReady[def.id] ?? 0)) return fail(ErrorCode.coolingDown);
        player.awReady[def.id] = t + def.cooldown_ms;
        if (def.id === 'shadow') {
          player.shadowUntil = t + def.ms;
        } else if (def.id === 'shield') {
          player.shieldUntil = t + def.ms;
          player.shieldHits = def.hits;
        }
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'awaken_use', a: def.id, ms: def.ms, cd: def.cooldown_ms });
        room.broadcast({ t: 'awaken_fx', id: player.id, a: def.id, ms: def.ms });
        return;
      }
      // ---- v0.28.8 전직 · 기술 나무 ----
      case 'class_pick': {
        const J = H.level?.jobs;
        const job = H.jobById?.get(msg.j);
        const h = rec(player);
        if (!J || !job) return fail(ErrorCode.badItem);
        if (h.job) return fail(ErrorCode.jobTaken);
        if (h.lv < J.level) return fail(ErrorCode.jobLevel);
        h.job = job.id;
        h.adv = false;
        h.jp = jobPointsAt(H, h.lv);
        h.jt = {};
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'job', j: job.id, jp: h.jp });
        room.broadcast({ t: 'hunter_job', id: player.id, j: job.id, a: false }, player.id);
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      // v0.28.9 2차 전직: advance_level 에, 직업의 advance 로 (바꿀 수 없다). 포인트를 더 받는다.
      case 'class_advance': {
        const J = H.level?.jobs;
        const h = rec(player);
        const job = h.job ? H.jobById?.get(h.job) : null;
        if (!J || !job) return fail(ErrorCode.noJobYet);
        if (!job.advance) return fail(ErrorCode.badItem);
        if (h.adv) return fail(ErrorCode.jobTaken);
        if (h.lv < (J.advance_level ?? 30)) return fail(ErrorCode.jobLevel);
        h.adv = true;
        h.jp += J.advance_points ?? 0;
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'advance', j: job.id, a: job.advance.id, jp: h.jp });
        room.broadcast({ t: 'hunter_job', id: player.id, j: job.id, a: true }, player.id);
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'skill_up': {
        const J = H.level?.jobs;
        const h = rec(player);
        const job = h.job ? H.jobById?.get(h.job) : null;
        const node = job?.nodeById.get(msg.n);
        if (!J || !node) return fail(ErrorCode.badItem);
        if (h.jp <= 0) return fail(ErrorCode.noSkillPoint);
        if ((h.jt[node.id] ?? 0) >= node.max) return fail(ErrorCode.skillMaxed);
        if ((node.adv && !h.adv) || spentOf(h) < (node.row - 1) * J.row_gate || (node.req ?? []).some((r) => (h.jt[r] ?? 0) <= 0)) return fail(ErrorCode.skillLocked);
        h.jp--;
        h.jt[node.id] = (h.jt[node.id] ?? 0) + 1;
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'skill', n: node.id, v: h.jt[node.id], jp: h.jp });
        sendHunter(room, player);
        if (node.fx?.hp) onVit?.(room, player);
        saveRoom(room);
        return;
      }
      case 'skill_reset': {
        const J = H.level?.jobs;
        const h = rec(player);
        if (!J || !h.job) return fail(ErrorCode.badItem);
        const spent = spentOf(h);
        if (spent <= 0) return fail(ErrorCode.badItem);
        if ((player.profile.sol ?? 0) < J.reset_sol) return fail(ErrorCode.notEnoughSol);
        player.profile.sol -= J.reset_sol;
        h.jp += spent;
        h.jt = {};
        sendProfile(player);
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'skill_reset', jp: h.jp, cost: J.reset_sol });
        sendHunter(room, player);
        onVit?.(room, player);
        saveRoom(room);
        return;
      }
      case 'guild_create': {
        const name = typeof msg.name === 'string' ? msg.name.replace(/[\u0000-\u001f\u007f]/g, '').trim() : '';
        if ([...name].length < H.guild.name_min || [...name].length > H.guild.name_max) return fail(ErrorCode.badGuildName);
        if (room.guild) return fail(ErrorCode.guildExists);
        room.guild = { name, members: [player.uid], pts: 0, since: Date.now() };
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'guild', op: 'create', name });
        room.broadcast({ t: 'guild', g: guildWire(room), by: player.id, op: 'create' });
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'guild_join': {
        if (!room.guild) return fail(ErrorCode.noGuild);
        if (room.guild.members.includes(player.uid)) return fail(ErrorCode.guildExists);
        if (room.guild.members.length >= 2) return fail(ErrorCode.guildFull);
        room.guild.members.push(player.uid);
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'guild', op: 'join', name: room.guild.name });
        room.broadcast({ t: 'guild', g: guildWire(room), by: player.id, op: 'join' });
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      case 'guild_leave': {
        if (!guildOf(room, player)) return fail(ErrorCode.noGuild);
        room.guild.members = room.guild.members.filter((uid) => uid !== player.uid);
        if (room.guild.members.length === 0) room.guild = null;
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'guild', op: 'leave' });
        room.broadcast({ t: 'guild', g: guildWire(room), by: player.id, op: 'leave' });
        sendHunter(room, player);
        saveRoom(room);
        return;
      }
      default:
        return fail(ErrorCode.badMessage);
    }
  }

  /** 다른 사람에게 보이는 등급 (머리 위 이름표). */
  const rankWire = (player) => (H ? rec(player).rank : '');

  /** 스탯이 주는 값 (survival · server 가 쓴다). */
  const fx = (player, key) => jobFx(H, player.profile, key);
  const bonus = {
    damage: (player) => 1 + statOf(H, player.profile, 'str') * (H?.level?.stats?.str?.damage ?? 0),
    // v0.28.8 기술 나무: 무기 갈래 (근접 · 원거리) 와 모든 피해 배율.
    weapon: (player, w) => 1 + fx(player, 'dmg') + (w?.ammo ? fx(player, 'ranged') : fx(player, 'melee')),
    hp: (player) => Math.floor(statOf(H, player.profile, 'vit') * (H?.level?.stats?.vit?.hp_per ?? 0)) + fx(player, 'hp'),
    speed: (player) => (1 + statOf(H, player.profile, 'agi') * (H?.level?.stats?.agi?.speed ?? 0)) * (1 + fx(player, 'speed')) * ((player.shadowUntil ?? 0) > now() ? 1 + (H?.level?.awaken?.list?.find((x) => x.id === 'shadow')?.speed ?? 0) : 1),
    fx,
    active: (player, a) => hasActive(H, player.profile, a),
    activeDef: (a) => H?.level?.jobs?.actives?.[a] ?? null,
    critBase: () => H?.level?.jobs?.crit_base ?? 2,
    // v0.28.5 각성: 그림자 걸음 중이면 크리처가 보지 못한다 · 마력 방패가 공격을 막는다 (막았으면 true).
    hidden: (player) => (player.shadowUntil ?? 0) > now(),
    block: (player) => {
      if ((player.shieldUntil ?? 0) <= now() || (player.shieldHits ?? 0) <= 0) return false;
      player.shieldHits--;
      return true;
    },
    cooldown: (player) => (1 - statOf(H, player.profile, 'agi') * (H?.level?.stats?.agi?.cooldown ?? 0)) * Math.max(0.4, 1 - fx(player, 'cd')),
    skill: (player, id) => hasSkill(H, player.profile, id),
    skillDef: (id) => H?.level?.skills?.find((x) => x.id === id) ?? null,
  };

  return { handle, wire, sendHunter, guildWire, onKill, onLoot, onSupply, onGate, grant, act, rankWire, sellBonus, bonus, setOnVit: (fn) => { onVit = fn; } };
}
