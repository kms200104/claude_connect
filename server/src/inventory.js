// 인벤토리: 고정 칸 배열. 앞쪽 quickSlots 칸이 화면 아래 퀵슬롯, 나머지 inventoryCapacity 칸이 가방이다.
// slots: Array<{ id: string, n: number } | null>
// 한 칸에 쌓을 수 있는 개수는 아이템마다 다르다(limitOf). 도구는 1개, 목재는 30개, 물고기는 cfg.inventoryStackSize.

export function slotCount(cfg) {
  return cfg.quickSlots + cfg.inventoryCapacity;
}

export function emptySlots(cfg) {
  return Array.from({ length: slotCount(cfg) }, () => null);
}

/** 새 아이템을 넣을 칸 순서: 가방 칸 → 퀵슬롯. (같은 아이템이 쌓인 칸은 이 순서로 먼저 채운다.) */
/** 퀵슬롯에 먼저 넣는 아이템 (v0.16: 탈것 — 퀵슬롯을 눌러 바로 탄다). gamedata 가 채운다. */
export const QUICK_FIRST = new Set();

function placementOrder(slots, cfg, id = '') {
  const order = [];
  if (QUICK_FIRST.has(id)) {
    for (let i = 0; i < Math.min(cfg.quickSlots, slots.length); i++) order.push(i);
    for (let i = cfg.quickSlots; i < slots.length; i++) order.push(i);
    return order;
  }
  for (let i = cfg.quickSlots; i < slots.length; i++) order.push(i);
  for (let i = 0; i < Math.min(cfg.quickSlots, slots.length); i++) order.push(i);
  return order;
}

/** n개를 모두 넣을 수 있는지. */
export function canAdd(slots, id, n, limitOf) {
  const limit = limitOf(id);
  let room = 0;
  for (const s of slots) {
    if (s === null) room += limit;
    else if (s.id === id) room += Math.max(limit - s.n, 0);
    if (room >= n) return true;
  }
  return false;
}

/** 아무 물고기나 한 마리 더 받을 공간이 있는지 (던지기 전 검사: 무엇이 낚일지 아직 모른다). */
export function hasFreeSpace(slots, isFish, limitOf) {
  return slots.some((s) => s === null || (isFish(s.id) && s.n < limitOf(s.id)));
}

/** 전부 넣거나 아무것도 안 넣는다. 성공하면 true. */
export function addItem(slots, id, n, cfg, limitOf) {
  if (!Number.isInteger(n) || n < 1 || !canAdd(slots, id, n, limitOf)) return false;
  const limit = limitOf(id);
  let left = n;
  const order = placementOrder(slots, cfg, id);
  for (const i of order) {
    const s = slots[i];
    if (s !== null && s.id === id && s.n < limit) {
      const put = Math.min(limit - s.n, left);
      s.n += put;
      left -= put;
      if (left === 0) return true;
    }
  }
  for (const i of order) {
    if (slots[i] === null) {
      const put = Math.min(limit, left);
      slots[i] = { id, n: put };
      left -= put;
      if (left === 0) return true;
    }
  }
  return left === 0;
}

/** 조건에 맞는 아이템 개수 합. */
export function countWhere(slots, pred) {
  return slots.reduce((sum, s) => sum + (s !== null && pred(s.id) ? s.n : 0), 0);
}

export function hasItem(slots, id) {
  return slots.some((s) => s !== null && s.id === id);
}

/** 조건에 맞는 아이템을 n개 뺀다(뒤쪽 칸부터). 모자라면 아무것도 안 빼고 null, 성공하면 뺀 내역 {id: 개수}. */
export function removeWhere(slots, pred, n) {
  if (!Number.isInteger(n) || n < 1 || countWhere(slots, pred) < n) return null;
  const taken = {};
  let left = n;
  for (let i = slots.length - 1; i >= 0 && left > 0; i--) {
    const s = slots[i];
    if (s === null || !pred(s.id)) continue;
    const take = Math.min(s.n, left);
    s.n -= take;
    left -= take;
    taken[s.id] = (taken[s.id] ?? 0) + take;
    if (s.n === 0) slots[i] = null;
  }
  return taken;
}

/** 한 칸에서 n개 버리기. 가진 것보다 많이는 못 버린다. */
export function removeAt(slots, index, n) {
  if (!Number.isInteger(index) || index < 0 || index >= slots.length) return false;
  const s = slots[index];
  if (s === null || !Number.isInteger(n) || n < 1 || s.n < n) return false;
  s.n -= n;
  if (s.n === 0) slots[index] = null;
  return true;
}

/** from 칸을 to 칸으로: 같은 아이템이면 쌓을 수 있는 만큼 합치고, 아니면 맞바꾼다. */
export function moveSlot(slots, from, to, limitOf) {
  const valid = (i) => Number.isInteger(i) && i >= 0 && i < slots.length;
  if (!valid(from) || !valid(to) || from === to || slots[from] === null) return false;
  const a = slots[from];
  const b = slots[to];
  if (b !== null && b.id === a.id) {
    const put = Math.min(limitOf(a.id) - b.n, a.n);
    if (put > 0) {
      b.n += put;
      a.n -= put;
      if (a.n === 0) slots[from] = null;
      return true;
    }
  }
  slots[from] = b;
  slots[to] = a;
  return true;
}

/**
 * 저장 파일에서 읽은 값을 정리한다.
 * - 새 형식: 칸 배열. positional 이면 칸 자리를 그대로 지킨다. 가방 칸 수가 바뀌었으면(v0.12: 20 → 30)
 *   있는 칸은 같은 자리에 두고, 줄어서 넘친 아이템만 빈 칸에 다시 넣는다.
 * - 옛 형식(schema 1): 물고기 목록 [{id, n}] → 차례로 넣는다
 */
export function sanitize(raw, cfg, isKnown, limitOf, positional = Array.isArray(raw) && raw.length === slotCount(cfg)) {
  const slots = emptySlots(cfg);
  if (!Array.isArray(raw)) return slots;
  const clean = (it) => (it && typeof it.id === 'string' && isKnown(it.id) && Number.isInteger(it.n) && it.n >= 1 ? { id: it.id, n: Math.min(it.n, limitOf(it.id)) } : null);
  if (positional) {
    const overflow = [];
    for (let i = 0; i < raw.length; i++) {
      const c = clean(raw[i]);
      if (i < slots.length) slots[i] = c;
      else if (c) overflow.push(c);
    }
    for (const c of overflow) addItem(slots, c.id, c.n, cfg, limitOf);
    return slots;
  }
  for (const it of raw) {
    const c = clean(it);
    if (c) addItem(slots, c.id, c.n, cfg, limitOf);
  }
  return slots;
}

/** held: 손에 든 퀵슬롯 번호(없으면 -1). */
export function toWire(slots, cfg, held = -1) {
  return { slots: slots.map((s) => (s === null ? null : { id: s.id, n: s.n })), quick: cfg.quickSlots, cap: cfg.inventoryCapacity, held };
}
