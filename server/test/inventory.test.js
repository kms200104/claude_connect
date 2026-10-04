import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { addItem, canAdd, countWhere, emptySlots, hasFreeSpace, moveSlot, removeAt, removeWhere, sanitize, toWire } from '../src/inventory.js';

// 퀵슬롯 2칸 + 가방 3칸. 물고기는 2마리, 목재는 3개, 도구는 1개씩 쌓인다.
const cfg = { quickSlots: 2, inventoryCapacity: 3, inventoryStackSize: 2 };
const limitOf = (id) => ({ rod: 1, wood: 3 })[id] ?? cfg.inventoryStackSize;
const isFish = (id) => !['rod', 'wood'].includes(id);
const isKnown = (id) => id !== 'dragon';

describe('inventory (퀵슬롯 + 가방 칸)', () => {
  it('새 아이템은 가방 칸부터 채우고, 같은 아이템은 칸당 상한까지 쌓인다', () => {
    const s = emptySlots(cfg);
    assert.equal(s.length, 5);
    assert.ok(addItem(s, 'carp', 1, cfg, limitOf));
    assert.ok(addItem(s, 'carp', 1, cfg, limitOf));
    assert.deepEqual(s, [null, null, { id: 'carp', n: 2 }, null, null]);
    assert.ok(addItem(s, 'carp', 1, cfg, limitOf));
    assert.deepEqual(s[3], { id: 'carp', n: 1 });
  });

  it('가방이 차면 빈 퀵슬롯에 넣고, 다 차면 아무것도 넣지 않는다', () => {
    const s = [null, null, { id: 'a', n: 2 }, { id: 'b', n: 2 }, { id: 'c', n: 2 }];
    assert.ok(addItem(s, 'wood', 3, cfg, limitOf));
    assert.deepEqual(s[0], { id: 'wood', n: 3 });
    assert.equal(canAdd(s, 'wood', 4, limitOf), false, '빈 칸 1개(3개)뿐이라 4개는 못 넣는다');
    assert.equal(addItem(s, 'wood', 4, cfg, limitOf), false);
    assert.equal(s[1], null, '실패하면 아무것도 바뀌지 않는다');
    assert.equal(hasFreeSpace(s, isFish, limitOf), true);
    s[1] = { id: 'rod', n: 1 };
    assert.equal(hasFreeSpace(s, isFish, limitOf), false, '물고기 칸이 전부 꽉 찼고 빈 칸도 없다');
  });

  it('칸 옮기기: 다른 아이템은 맞바꾸고, 같은 아이템은 합친다', () => {
    const s = [{ id: 'rod', n: 1 }, null, { id: 'wood', n: 2 }, { id: 'wood', n: 2 }, null];
    assert.ok(moveSlot(s, 0, 4, limitOf));
    assert.deepEqual([s[0], s[4]], [null, { id: 'rod', n: 1 }]);
    assert.ok(moveSlot(s, 2, 3, limitOf));
    assert.deepEqual([s[2], s[3]], [{ id: 'wood', n: 1 }, { id: 'wood', n: 3 }]);
    assert.equal(moveSlot(s, 1, 2, limitOf), false, '빈 칸에서 옮길 수는 없다');
    assert.equal(moveSlot(s, 2, 99, limitOf), false);
    assert.equal(moveSlot(s, 2, 2, limitOf), false);
  });

  it('버리기: 가진 만큼만, 0이 되면 칸이 비워진다', () => {
    const s = [null, null, { id: 'carp', n: 2 }, null, null];
    assert.equal(removeAt(s, 2, 3), false);
    assert.equal(removeAt(s, 0, 1), false);
    assert.equal(removeAt(s, 2, 0), false);
    assert.equal(removeAt(s, 2, 1.5), false);
    assert.equal(removeAt(s, 9, 1), false);
    assert.ok(removeAt(s, 2, 1));
    assert.ok(removeAt(s, 2, 1));
    assert.equal(s[2], null);
  });

  it('조건으로 개수 세기·빼기 (부탁 완료): 모자라면 하나도 안 뺀다', () => {
    const s = [{ id: 'rod', n: 1 }, { id: 'carp', n: 1 }, { id: 'crucian', n: 2 }, { id: 'wood', n: 3 }, null];
    assert.equal(countWhere(s, isFish), 3);
    assert.equal(removeWhere(s, isFish, 4), null);
    assert.equal(countWhere(s, isFish), 3);
    assert.deepEqual(removeWhere(s, isFish, 2), { crucian: 2 });
    assert.deepEqual(s, [{ id: 'rod', n: 1 }, { id: 'carp', n: 1 }, null, { id: 'wood', n: 3 }, null]);
  });

  it('저장 파일 정리: 새 형식은 칸 그대로, 옛 형식(물고기 목록)은 차례로 넣는다', () => {
    const slots = [{ id: 'rod', n: 1 }, { id: 'dragon', n: 1 }, { id: 'carp', n: 5 }, null, 'x'];
    assert.deepEqual(sanitize(slots, cfg, isKnown, limitOf), [{ id: 'rod', n: 1 }, null, { id: 'carp', n: 2 }, null, null]);
    const legacy = [{ id: 'carp', n: 1 }, { id: 'dragon', n: 1 }, { id: 3, n: 1 }, { id: 'b', n: -1 }, null, { id: 'c', n: 1 }];
    assert.deepEqual(sanitize(legacy, cfg, isKnown, limitOf), [null, null, { id: 'carp', n: 1 }, { id: 'c', n: 1 }, null]);
    assert.deepEqual(sanitize('x', cfg, isKnown, limitOf), emptySlots(cfg));
  });

  it('전송 형식에 칸 수와 손에 든 칸이 실린다', () => {
    const s = emptySlots(cfg);
    s[0] = { id: 'rod', n: 1 };
    assert.deepEqual(toWire(s, cfg, 0), { slots: [{ id: 'rod', n: 1 }, null, null, null, null], quick: 2, cap: 3, held: 0 });
  });
});
