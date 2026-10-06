// v16 방명록: 집(호수)마다 다녀간 사람이 남긴 글. 마을 저장 파일(world.guestbooks)에 둔다.
// 글 = { by: 자리, tx: 글, at: 유닉스 ms }. 집마다 최근 GUESTBOOK.max 개.

export const GUESTBOOK = Object.freeze({ max: 40, maxText: 100, gapMs: 8000 });

export function cleanEntryText(raw) {
  if (typeof raw !== 'string') return '';
  return raw.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, GUESTBOOK.maxText);
}

export function sanitizeGuestbooks(raw, units) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  const known = new Set(units.map((u) => u.id));
  for (const [unit, list] of Object.entries(raw)) {
    if (!known.has(unit) || !Array.isArray(list)) continue;
    const clean = list
      .filter((e) => e && Number.isInteger(e.by) && typeof e.tx === 'string' && Number.isFinite(e.at))
      .slice(-GUESTBOOK.max)
      .map((e) => ({ by: e.by, tx: cleanEntryText(e.tx), at: e.at }))
      .filter((e) => e.tx);
    if (clean.length > 0) out[unit] = clean;
  }
  return out;
}

export function addEntry(books, unit, entry) {
  const list = (books[unit] ??= []);
  list.push(entry);
  if (list.length > GUESTBOOK.max) list.splice(0, list.length - GUESTBOOK.max);
  return list;
}

export function guestbookWire(books, unit) {
  return (books[unit] ?? []).map((e) => ({ ...e }));
}
