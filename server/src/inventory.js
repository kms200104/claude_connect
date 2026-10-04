// 인벤토리: 물고기 "종류" 하나가 한 칸. 칸 수(capacity)와 칸당 최대 개수(stackSize)로 제한한다.
// items: [{ id: string, n: number }]  (순서 = 획득 순서)

export function canAdd(items, id, cfg) {
  const slot = items.find((it) => it.id === id);
  if (slot) return slot.n < cfg.inventoryStackSize;
  return items.length < cfg.inventoryCapacity;
}

export function hasFreeSpace(items, cfg) {
  return items.length < cfg.inventoryCapacity || items.some((it) => it.n < cfg.inventoryStackSize);
}

/** 성공하면 true. 공간이 없으면 아무것도 바꾸지 않고 false. */
export function addItem(items, id, cfg, n = 1) {
  if (!canAdd(items, id, cfg)) return false;
  const slot = items.find((it) => it.id === id);
  if (slot) slot.n = Math.min(cfg.inventoryStackSize, slot.n + n);
  else items.push({ id, n: Math.min(cfg.inventoryStackSize, n) });
  return true;
}

/** 가진 개수보다 많이 버릴 수는 없다. 성공하면 true. */
export function removeItem(items, id, n = 1) {
  const i = items.findIndex((it) => it.id === id);
  if (i < 0 || !Number.isInteger(n) || n < 1 || items[i].n < n) return false;
  items[i].n -= n;
  if (items[i].n === 0) items.splice(i, 1);
  return true;
}

/** 저장 파일에서 읽은 값을 안전하게 정리한다. */
export function sanitize(raw, cfg) {
  const out = [];
  if (!Array.isArray(raw)) return out;
  for (const it of raw) {
    if (out.length >= cfg.inventoryCapacity) break;
    if (!it || typeof it.id !== 'string' || !Number.isInteger(it.n) || it.n < 1) continue;
    if (out.some((o) => o.id === it.id)) continue;
    out.push({ id: it.id, n: Math.min(it.n, cfg.inventoryStackSize) });
  }
  return out;
}

export function toWire(items, cfg) {
  return { items: items.map((it) => ({ id: it.id, n: it.n })), cap: cfg.inventoryCapacity };
}
