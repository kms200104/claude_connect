// v16 기록 · 도감 · 업적 · 칭호 · 생일 (서버 권위). 데이터는 data/achievements/achievements.json.
//   profile.stats  — 한 일을 센다 (낚시 · 도끼질 · 배달 …). bump 로만 올린다.
//   profile.dex    — 도감: fish { id: 낚은 수 }, items [가구 · 옷 id] (가방 · 입은 옷 · 내가 놓은 가구에 한 번이라도 있었던 것).
//   profile.ach    — 이룬 업적 [{ id, at(마을 날짜) }], profile.title — 고른 칭호(업적 id, '' = 없음).
//   profile.birthday — { m, d } (없으면 null), profile.bdayYear — 축하를 받은 마을 해 (한 해에 한 번).
// 판정은 프로필을 보낼 때마다(sendProfile) 한 번 돈다 — 무엇이 바뀌든 그 뒤에 확인된다.

export const STAT_KEYS = Object.freeze(['fish', 'chop', 'plant', 'clam', 'deliver', 'serve', 'quest', 'visit', 'guestbook', 'photo']);
/** 아주 친한 주민 기준 친밀도. */
export const BEST_FRIEND = 30;
const DEX_ITEM_KINDS = new Set(['furniture', 'clothing']);

/** 데이터 검사 + id 맵. */
export function loadAchievements(raw) {
  if (!raw) return { list: [], byId: new Map() };
  const known = new Set(Object.keys(raw.stats ?? {}));
  const ids = new Set();
  for (const a of raw.list) {
    if (ids.has(a.id)) throw new Error(`achievement ${a.id}: 같은 id`);
    ids.add(a.id);
    if (!known.has(a.stat)) throw new Error(`achievement ${a.id}: unknown stat ${a.stat}`);
    if (!Number.isInteger(a.goal) || a.goal < 1) throw new Error(`achievement ${a.id}: goal`);
    if (typeof a.title !== 'string' || !a.title) throw new Error(`achievement ${a.id}: title`);
  }
  return { list: raw.list, byId: new Map(raw.list.map((a) => [a.id, a])) };
}

export function sanitizeStats(raw) {
  const out = {};
  for (const k of STAT_KEYS) out[k] = Number.isInteger(raw?.[k]) && raw[k] > 0 ? raw[k] : 0;
  return out;
}

export function sanitizeDex(raw, data) {
  const out = { fish: {}, items: [] };
  if (!raw || typeof raw !== 'object') return out;
  for (const [id, n] of Object.entries(raw.fish ?? {})) if (data.isFish(id) && Number.isInteger(n) && n > 0) out.fish[id] = n;
  if (Array.isArray(raw.items)) out.items = [...new Set(raw.items.filter((id) => DEX_ITEM_KINDS.has(data.kindOf(id))))];
  return out;
}

export function sanitizeAch(raw, achievements) {
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  const out = [];
  for (const a of raw) {
    if (!a || !achievements.byId.has(a.id) || seen.has(a.id)) continue;
    seen.add(a.id);
    out.push({ id: a.id, at: Number.isInteger(a.at) ? a.at : 0 });
  }
  return out;
}

/** 생일 { m: 1~12, d: 1~31 } (그 달에 없는 날은 버린다). */
export function cleanBirthday(raw) {
  if (!raw || !Number.isInteger(raw.m) || !Number.isInteger(raw.d)) return null;
  if (raw.m < 1 || raw.m > 12 || raw.d < 1) return null;
  const days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][raw.m - 1];
  return raw.d <= days ? { m: raw.m, d: raw.d } : null;
}

export function bump(profile, key, n = 1) {
  profile.stats ??= sanitizeStats(null);
  profile.stats[key] = (profile.stats[key] ?? 0) + n;
}

/** 낚은 물고기를 도감에 (수를 센다). */
export function noteFish(profile, id, n = 1) {
  profile.dex ??= { fish: {}, items: [] };
  profile.dex.fish[id] = (profile.dex.fish[id] ?? 0) + n;
}

/** 가방 · 입은 옷 · 내가 놓은 가구에 있는 가구 · 옷을 도감에 올린다. 새로 오른 게 있으면 true. */
export function noteItems(profile, data, extra = []) {
  profile.dex ??= { fish: {}, items: [] };
  const have = new Set(profile.dex.items);
  const before = have.size;
  const add = (id) => {
    if (id && DEX_ITEM_KINDS.has(data.kindOf(id))) have.add(id);
  };
  for (const s of profile.slots) if (s) add(s.id);
  add(profile.outfit?.hat);
  add(profile.outfit?.top);
  for (const id of extra) add(id);
  if (have.size === before) return false;
  profile.dex.items = [...have];
  return true;
}

/** 업적 판정에 쓰는 값 (stats + 도감 · 친밀도 · 지갑 · 집 · 기증). */
export function statValues(profile, { donated = 0, homes = 0 } = {}) {
  const s = profile.stats ?? {};
  const friends = Object.values(profile.npcs ?? {}).filter((r) => (r?.f ?? 0) >= BEST_FRIEND).length;
  return {
    ...Object.fromEntries(STAT_KEYS.map((k) => [k, s[k] ?? 0])),
    fish_kinds: Object.keys(profile.dex?.fish ?? {}).length,
    items: profile.dex?.items?.length ?? 0,
    best_friend: friends,
    donate: donated,
    sol: profile.sol ?? 0,
    homes,
  };
}

/** 새로 이룬 업적 id 목록 (프로필에 적는다). */
export function checkAchievements(profile, achievements, values, day) {
  profile.ach ??= [];
  const got = new Set(profile.ach.map((a) => a.id));
  const fresh = [];
  for (const a of achievements.list) {
    if (got.has(a.id) || (values[a.stat] ?? 0) < a.goal) continue;
    profile.ach.push({ id: a.id, at: day });
    fresh.push(a.id);
  }
  return fresh;
}

/** 칭호로 쓸 수 있는지 (이룬 업적만, '' 는 칭호 없음). */
export function canWearTitle(profile, id) {
  return id === '' || (profile.ach ?? []).some((a) => a.id === id);
}

/** 프로필에 실어 보내는 부분. */
export function progressWire(profile, values) {
  return {
    stats: values,
    dex: { fish: { ...(profile.dex?.fish ?? {}) }, items: [...(profile.dex?.items ?? [])] },
    ach: (profile.ach ?? []).map((a) => ({ id: a.id, at: a.at })),
    title: profile.title ?? '',
    birthday: profile.birthday ? { ...profile.birthday } : null,
  };
}

// ---- 마을 달력 ----

/** 마을 날짜 번호 → { y, m, d, wd(0=일) } (dayIndex 의 그날 정오 기준). */
export function dateOfDay(day, dayMs = 86400000, dayStartHour = 5) {
  const t = new Date(day * dayMs + (dayStartHour + 7) * 3600000);
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate(), wd: t.getUTCDay() };
}

/** "MM-DD" → { m, d }. */
export function parseMonthDay(text) {
  const m = /^(\d{2})-(\d{2})$/.exec(String(text ?? ''));
  return m ? cleanBirthday({ m: Number(m[1]), d: Number(m[2]) }) : null;
}

export function sameDay(md, date) {
  return !!md && md.m === date.m && md.d === date.d;
}
