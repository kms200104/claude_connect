// v0.28 헌터 (서버 권위): 게이트가 열리는 도시에서 크리처를 사냥하는 헌터 — 협회 등급 · 마석 · 현상금 의뢰 · 길드.
// data/hunter/hunter.json. 클라이언트는 요청만:
//   hunter_sell { slot, n? } | { all: true }  협회 출장소 창구에서 마석 팔기 (등급 · 길드만큼 더 받는다)
//   hunter_rank {}                            창구에서 등급 재심사 (점수가 다음 등급 기준을 넘었을 때)
//   hunter_claim { b }                        현상금 의뢰 완료 보고 (헌터넷 앱, 다 채운 것만)
//   guild_create { name } · guild_join {} · guild_leave {}   길드 (같은 방 둘)
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
  return { ...raw, ranks, rankById: new Map(ranks.map((r) => [r.id, r])), bountyById: new Map(raw.bounty.pool.map((b) => [b.id, b])) };
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
  };
}

/** 저장된 길드 { name, members: [uid], pts, since } (같은 방 둘). */
export function sanitizeGuild(raw, profiles) {
  if (!raw || typeof raw.name !== 'string' || !raw.name.trim()) return null;
  const members = Array.isArray(raw.members) ? raw.members.filter((uid) => typeof uid === 'string' && profiles.has(uid)).slice(0, 2) : [];
  if (members.length === 0) return null;
  return { name: raw.name.trim().slice(0, 16), members, pts: Math.max(0, Math.trunc(Number(raw.pts) || 0)), since: Number.isFinite(raw.since) ? raw.since : 0 };
}

export function createHunter({ data, cfg, clock, random, now, send, sendTo, sendInventory, sendProfile, saveRoom, dropAt, inShop }) {
  const H = data.hunter;
  const ranks = H?.ranks ?? [];

  const rec = (player) => {
    player.profile.hunter = sanitizeHunter(player.profile.hunter, H);
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
      rank: r.id, pts: h.pts, next: nx?.points ?? 0, nextRank: nx?.id ?? '', kills: h.kills, gates: h.gates,
      bounties: todayBounties(room).map((b) => ({ id: b.id, kind: b.kind, k: b.k ?? '', n: b.n, got: Math.min(b.n, h.bprog[b.id] ?? 0), done: h.bdone.includes(b.id), reward: b.reward, pts: b.pts, name: b.name, desc: b.desc })),
      guild: guildWire(room),
    };
  }

  const sendHunter = (room, player) => sendTo(player, { t: 'hunter', ...wire(room, player) });
  const sendGuild = (room) => room.broadcast({ t: 'guild', g: guildWire(room) });

  /** 점수를 더한다 (길드원이면 길드 점수도). */
  function addPoints(room, player, pts) {
    if (pts <= 0) return;
    rec(player).pts += pts;
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
    for (const e of H.kill.mana[c.k] ?? []) {
      if (random() >= e.chance) continue;
      const [lo, hi] = e.n ?? [1, 1];
      const n = lo + Math.floor(random() * (hi - lo + 1));
      dropAt(room, e.id, n, c.x + (random() - 0.5) * 0.8, c.z + (random() - 0.5) * 0.8);
      got.push({ id: e.id, n });
    }
    progress(room, player, 'kill', c.k);
    sendTo(player, { t: 'hunter_result', kind: 'kill', k: c.k, pts, mana: got });
    sendHunter(room, player);
  }

  function onLoot(room, player) {
    if (H && player && progress(room, player, 'loot')) sendHunter(room, player);
  }

  function onSupply(room, player) {
    if (H && player && progress(room, player, 'supply')) sendHunter(room, player);
  }

  /** 게이트를 공략했다 (게이트 점수 · 의뢰). */
  function onGate(room, player, pts) {
    if (!H || !player) return;
    rec(player).gates++;
    addPoints(room, player, pts);
    progress(room, player, 'gate');
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
        send(ctx.ws, { t: 'hunter_result', rid: msg.rid, kind: 'claim', b: b.id, reward: b.reward, pts: b.pts });
        sendHunter(room, player);
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

  return { handle, wire, sendHunter, guildWire, onKill, onLoot, onSupply, onGate, rankWire, sellBonus };
}
