import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { addItem, canAdd, hasFreeSpace, removeItem, sanitize } from '../src/inventory.js';

const cfg = { inventoryCapacity: 3, inventoryStackSize: 2 };

describe('inventory', () => {
  it('같은 물고기는 한 칸에 쌓이고 칸당 상한이 있다', () => {
    const inv = [];
    assert.ok(addItem(inv, 'carp', cfg));
    assert.ok(addItem(inv, 'carp', cfg));
    assert.deepEqual(inv, [{ id: 'carp', n: 2 }]);
    assert.equal(addItem(inv, 'carp', cfg), false);
    assert.equal(canAdd(inv, 'carp', cfg), false);
  });

  it('칸이 가득 차면 새 종류는 못 넣지만 기존 종류는 넣을 수 있다', () => {
    const inv = [{ id: 'a', n: 1 }, { id: 'b', n: 1 }, { id: 'c', n: 2 }];
    assert.equal(canAdd(inv, 'd', cfg), false);
    assert.equal(canAdd(inv, 'a', cfg), true);
    assert.equal(hasFreeSpace(inv, cfg), true);
    assert.equal(hasFreeSpace([{ id: 'a', n: 2 }, { id: 'b', n: 2 }, { id: 'c', n: 2 }], cfg), false);
  });

  it('버리기: 가진 만큼만, 0이 되면 칸이 비워진다', () => {
    const inv = [{ id: 'carp', n: 2 }];
    assert.equal(removeItem(inv, 'carp', 3), false);
    assert.equal(removeItem(inv, 'nope', 1), false);
    assert.equal(removeItem(inv, 'carp', 0), false);
    assert.equal(removeItem(inv, 'carp', 1.5), false);
    assert.ok(removeItem(inv, 'carp', 1));
    assert.ok(removeItem(inv, 'carp', 1));
    assert.deepEqual(inv, []);
  });

  it('저장 파일의 이상한 값은 걸러낸다', () => {
    const raw = [{ id: 'a', n: 5 }, { id: 'a', n: 1 }, { id: 3, n: 1 }, { id: 'b', n: -1 }, null, { id: 'c', n: 1 }, { id: 'd', n: 1 }, { id: 'e', n: 1 }];
    assert.deepEqual(sanitize(raw, cfg), [{ id: 'a', n: 2 }, { id: 'c', n: 1 }, { id: 'd', n: 1 }]);
    assert.deepEqual(sanitize('x', cfg), []);
  });
});
