// 마을톡 (v0.11): 휴대폰 메신저. 대화방(thread)마다 메시지를 프로필에 저장한다 (끊겨 있어도 쌓였다가 들어오면 보인다).
//   npc:<주민>  — 친한 주민이 하루 한두 번 먼저 연락한다 (안부 · "식당 언제 열어?" · 비 오는 날). 내가 보내면 잠시 뒤 답장.
//   sys:bank    — 은행·동사무소 알림 (매주 이자 · 연체 · 월세 수입 · 지원금).
//   sys:town    — 마을 공지 (처음 들어오면 환영 인사).
//   pl:<자리>   — 같은 마을 친구(플레이어)와 주고받는 대화.
// 메시지 = { f: 보낸 쪽('me' | 주민 id | 'bank' | 'town' | 'p<자리>'), tx: 글, at: 보낸 시각(유닉스 ms) }.
import { ErrorCode } from './protocol.js';
import { addFriendship, relationOf } from './quests.js';

const THREAD = /^(npc:[a-z_]+|sys:(bank|town)|pl:[1-9][0-9]?)$/;

export function sanitizeChats(raw, rules) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [th, t] of Object.entries(raw)) {
    if (!THREAD.test(th) || !t || !Array.isArray(t.m)) continue;
    const m = t.m
      .filter((x) => x && typeof x.f === 'string' && typeof x.tx === 'string' && Number.isFinite(x.at))
      .slice(-rules.max_messages)
      .map((x) => ({ f: x.f, tx: x.tx.slice(0, rules.max_text), at: x.at }));
    out[th] = { m, read: Math.max(0, Math.min(m.length, Number.isInteger(t.read) ? t.read : m.length)) };
  }
  return out;
}

/** 대사 채우기: {sol} 등. {player} 는 받는 사람 화면에서 그 사람 이름으로 채운다 (이름은 클라이언트에 있다). */
export function fillLine(line, values) {
  return line.replace(/\{(\w+)\}/g, (all, k) => (values[k] !== undefined ? String(values[k]) : all));
}

const sol = (n) => `${Math.round(n).toLocaleString('ko-KR')}솔`;

export function createMessenger({ data, cfg, random, sendTo, clock, wallNow = () => Date.now() }) {
  const rules = data.messenger;

  function threadOf(profile, th) {
    profile.chats ??= {};
    profile.chats[th] ??= { m: [], read: 0 };
    return profile.chats[th];
  }

  /** 메시지 하나를 넣고, 그 사람이 접속 중이면 바로 보낸다. */
  function push(room, profile, th, from, text, mine = false) {
    const t = threadOf(profile, th);
    const m = { f: from, tx: String(text).slice(0, rules.max_text), at: wallNow() };
    t.m.push(m);
    if (mine) t.read = t.m.length;
    if (t.m.length > rules.max_messages) {
      const cut = t.m.length - rules.max_messages;
      t.m.splice(0, cut);
      t.read = Math.max(0, t.read - cut);
    }
    const player = room ? [...room.players.values()].find((p) => p.profile === profile) : null;
    if (player?.ws) sendTo(player, { t: 'msg', th, m });
    if (room) room.saveDirty = true;
    return m;
  }

  /** 들어올 때 보내는 대화방 전체. 처음이면 환영 인사를 넣어 둔다. */
  function wire(room, profile) {
    if (!profile.chats || Object.keys(profile.chats).length === 0) {
      threadOf(profile, 'sys:town').m.push({ f: 'town', tx: rules.welcome, at: wallNow() });
    }
    return profile.chats;
  }

  const linesOf = (npcDef, key) => rules.lines[npcDef.personality]?.[key] ?? [];
  const pick = (list) => list[Math.floor(random() * list.length)];

  /** 친한 주민의 먼저 연락: check_ms 마다 접속한 사람마다 한 번 굴린다. */
  function tick(room, { weather, restaurantOpen }) {
    const day = clock.day();
    for (const player of room.players.values()) {
      if (!player.online) continue;
      const p = player.profile;
      p.msgDay ??= { day: null, n: 0, from: [] };
      if (p.msgDay.day !== day) p.msgDay = { day, n: 0, from: [] };
      if (p.msgDay.n >= rules.daily_max || random() > rules.chance_per_check) continue;
      const friends = [...room.npcs.values()]
        .map((n) => n.def)
        .filter((d) => rules.lines[d.personality] && !p.msgDay.from.includes(d.id) && (p.npcs?.[d.id]?.f ?? 0) >= rules.min_friendship);
      if (friends.length === 0) continue;
      const def = pick(friends);
      const kinds = ['daily'];
      if (!restaurantOpen) kinds.push('shop');
      if (weather === 'rain' || weather === 'thunder') kinds.push('rain', 'rain');
      const lines = linesOf(def, pick(kinds));
      if (lines.length === 0) continue;
      p.msgDay.n += 1;
      p.msgDay.from.push(def.id);
      push(room, p, `npc:${def.id}`, def.id, pick(lines));
    }
  }

  /** 은행·동사무소 알림 (매주). report = { interest, capitalized, missed, rent, grant }. */
  function weekly(room, profile, report) {
    if (report.interest > 0) push(room, profile, 'sys:bank', 'bank', fillLine(rules.bank.paid, { sol: sol(report.interest) }));
    if (report.missed && report.capitalized > 0) push(room, profile, 'sys:bank', 'bank', fillLine(rules.bank.missed, { sol: sol(report.capitalized) }));
    if (report.rent > 0) push(room, profile, 'sys:bank', 'bank', fillLine(rules.bank.rent, { sol: sol(report.rent) }));
    if (report.grant > 0) push(room, profile, 'sys:bank', 'bank', fillLine(rules.bank.grant, { sol: sol(report.grant) }));
  }

  function handle(ctx, msg, fail) {
    const { player, room } = ctx;
    const th = msg.th;
    if (typeof th !== 'string' || !THREAD.test(th)) return fail(ErrorCode.badMessage);
    if (msg.t === 'msg_read') {
      const t = player.profile.chats?.[th];
      if (t) t.read = t.m.length;
      return;
    }
    // msg_send
    if (!player.acceptRid(msg.rid)) return;
    const text = typeof msg.tx === 'string' ? msg.tx.trim().slice(0, rules.max_text) : '';
    if (!text) return fail(ErrorCode.badMessage);
    if (th.startsWith('sys:')) return fail(ErrorCode.badMessage);
    if (th.startsWith('npc:')) {
      const id = th.slice(4);
      const npc = room.npcs.get(id);
      if (!npc || !rules.lines[npc.def.personality]) return fail(ErrorCode.badMessage);
      push(room, player.profile, th, 'me', text, true);
      const delay = rules.reply_min_ms + random() * (rules.reply_max_ms - rules.reply_min_ms);
      const timer = setTimeout(() => {
        const rel = relationOf(player.profile, id);
        const day = clock.day();
        if (rel.msgReplyDay !== day) {
          rel.msgReplyDay = day;
          addFriendship(rel, rules.friend_per_reply_day);
        }
        push(room, player.profile, th, id, pick(linesOf(npc.def, 'reply')));
      }, delay * cfg.messengerReplyScale);
      timer.unref?.();
      return;
    }
    // pl:<자리> — 같은 마을 친구에게.
    const slot = Number(th.slice(3));
    const target = [...room.profiles.values()].find((p) => p.slot === slot);
    if (!target || target === player.profile) return fail(ErrorCode.badMessage);
    push(room, player.profile, th, 'me', text, true);
    push(room, target, `pl:${player.profile.slot}`, `p${player.profile.slot}`, text);
  }

  return { push, wire, tick, weekly, handle, sanitize: (raw) => sanitizeChats(raw, rules) };
}
