import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createClock, dayIndex, hourOf, inHours, timeBand, weatherAt, DAY_MS, HOUR_MS } from '../src/clock.js';
import { chopTree, newTreeState, refreshTree, sanitizeTrees } from '../src/trees.js';
import { createNpcRuntime, stepNpcs } from '../src/npcs.js';
import { makeQuest, pruneExpired, questProgress, questReady, shouldOffer } from '../src/quests.js';
import { availableFish, loadGameData, pickFish } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);

describe('마을 시계', () => {
  it('하루는 새벽 5시에 바뀌고, 시간대 구간은 아침·낮·저녁·밤', () => {
    const at = (h) => 1000 * DAY_MS + h * HOUR_MS;
    assert.equal(hourOf(at(13.5)), 13.5);
    assert.equal(dayIndex(at(4.99)), dayIndex(at(0)));
    assert.equal(dayIndex(at(5)), dayIndex(at(4.99)) + 1);
    assert.deepEqual([6, 12, 18, 22, 2].map(timeBand), ['morning', 'day', 'evening', 'night', 'night']);
    assert.equal(inHours([17, 5], 23), true);
    assert.equal(inHours([17, 5], 12), false);
    assert.equal(inHours([9, 17], 9), true);
    assert.equal(inHours(undefined, 3), true);
  });

  it('배율만큼 빨리 흐르고, 시간대·오프셋을 반영한다', () => {
    let real = 0;
    const clock = createClock({ clockScale: 60, utcOffsetMin: 540, clockOffsetMin: 0 }, () => real);
    const h0 = clock.hour();
    assert.equal(h0, 9, 'epoch 0 의 한국 시간은 오전 9시');
    real = 60 * 1000; // 실제 1분 = 게임 1시간
    assert.equal(clock.hour(), 10);
  });
});

describe('날씨', () => {
  it('같은 시드·날짜·시각이면 항상 같은 날씨, 3시간 블록 안에서는 바뀌지 않는다', () => {
    for (let day = 0; day < 30; day++) {
      assert.equal(weatherAt(42, day, 13), weatherAt(42, day, 13));
      assert.equal(weatherAt(42, day, 12), weatherAt(42, day, 14.9));
    }
  });

  it('4가지 날씨가 모두 나오고 맑음이 가장 많다', () => {
    const count = { clear: 0, cloudy: 0, rain: 0, thunder: 0 };
    for (let seed = 1; seed < 60; seed++) for (let day = 0; day < 40; day++) count[weatherAt(seed, day, (day % 8) * 3)] += 1;
    assert.ok(Object.values(count).every((n) => n > 0), JSON.stringify(count));
    assert.ok(count.clear > count.cloudy && count.cloudy > count.thunder, JSON.stringify(count));
  });

  it('시각·날씨에 따라 낚이는 물고기가 다르다', () => {
    const lake = data.spots.get('lake');
    const ids = (hour, weather) => availableFish(lake, data.fish, hour, weather).map((f) => f.id);
    assert.ok(ids(12, 'clear').includes('goldfish'));
    assert.ok(!ids(12, 'clear').includes('sturgeon'));
    assert.ok(ids(12, 'rain').includes('sturgeon'));
    assert.ok(ids(22, 'clear').includes('catfish'));
    assert.ok(!ids(22, 'clear').includes('minnow'));
    // 조건에 맞는 것만 뽑힌다
    for (let i = 0; i < 50; i++) assert.notEqual(pickFish(lake, data.fish, Math.random, 12, 'clear').id, 'sturgeon');
  });
});

describe('나무', () => {
  it('세 번 찍으면 쓰러지고, 다음 날 묘목·그다음 날 다 자란다', () => {
    const t = newTreeState();
    assert.deepEqual(chopTree(t, 10, 3), { felled: false });
    assert.deepEqual(chopTree(t, 10, 3), { felled: false });
    assert.deepEqual(chopTree(t, 10, 3), { felled: true });
    assert.equal(t.s, 'stump');
    assert.equal(chopTree(t, 10, 3), null, '그루터기는 찍을 수 없다');
    refreshTree(t, 11);
    assert.equal(t.s, 'sapling');
    assert.equal(chopTree(t, 11, 3), null);
    refreshTree(t, 12);
    assert.deepEqual({ s: t.s, c: t.c }, { s: 'grown', c: 0 });
  });

  it('덜 찍힌 나무는 날이 바뀌면 회복된다', () => {
    const t = newTreeState();
    chopTree(t, 3, 3);
    chopTree(t, 3, 3);
    assert.equal(refreshTree(t, 4), true);
    assert.equal(t.c, 0);
    assert.deepEqual(chopTree(t, 4, 3), { felled: false });
  });

  it('저장 파일 정리: 모르는 나무는 버리고 없는 나무는 기본값', () => {
    const out = sanitizeTrees({ t01: { s: 'stump', c: 0, d: 1, f: 1 }, zz: { s: 'stump' }, t02: { s: 'weird' } }, data.trees);
    assert.equal(out.size, data.trees.size);
    assert.equal(out.get('t01').s, 'stump');
    assert.equal(out.get('t02').s, 'grown');
    assert.equal(out.has('zz'), false);
  });
});

describe('주민 이동', () => {
  const opts = (mode) => ({ dtMs: 100, now: 0, random: () => 0, mode, speed: 1.4, idleMinMs: 0, idleMaxMs: 0 });

  it('길목 사이를 걷고, 비·밤에는 집 앞에 머문다', () => {
    const npcs = createNpcRuntime(data.npcs, 0, () => 0);
    const morak = npcs.get('morak');
    const [hx, hz] = morak.def.waypoints[0];
    assert.equal(stepNpcs(npcs, opts('home')), false, '집 앞에 있으면 움직이지 않는다');
    assert.equal(stepNpcs(npcs, opts('roam')), true);
    assert.ok(Math.hypot(morak.x - hx, morak.z - hz) > 0.1);
    for (let i = 0; i < 400; i++) stepNpcs(npcs, opts('home'));
    assert.deepEqual([morak.x, morak.z], [hx, hz], '비가 오면 집 앞으로 돌아간다');
  });

  it('대화 중인 주민은 움직이지 않는다', () => {
    const npcs = createNpcRuntime(data.npcs, 0, () => 0);
    for (const n of npcs.values()) n.talkingWith = 1;
    assert.equal(stepNpcs(npcs, opts('roam')), false);
  });
});

describe('부탁', () => {
  const rules = data.quests;
  const profile = () => ({ npcs: {}, quests: [], lastQuestDay: 5 });

  it('확률·하루 한 번·동시 부탁 수 제한', () => {
    const p = profile();
    assert.equal(shouldOffer({ rules, profile: p, npcId: 'morak', today: 5, random: () => 0.99 }), false);
    assert.equal(shouldOffer({ rules, profile: p, npcId: 'morak', today: 5, random: () => 0 }), true);
    p.npcs.morak.offerDay = 5;
    assert.equal(shouldOffer({ rules, profile: p, npcId: 'morak', today: 5, random: () => 0 }), false, '같은 날 같은 주민은 한 번만');
    p.quests = [{ npc: 'a' }, { npc: 'b' }, { npc: 'c' }];
    assert.equal(shouldOffer({ rules, profile: p, npcId: 'mujin', today: 5, random: () => 0 }), false, '최대 3개');
  });

  it('며칠 동안 부탁이 없으면 확실히 하나 준다', () => {
    const p = profile();
    assert.equal(shouldOffer({ rules, profile: p, npcId: 'mujin', today: 7, random: () => 0.99 }), true);
  });

  it('지금 낚을 수 있는 물고기만 부탁하고, 진행도를 인벤토리로 센다', () => {
    const npcDef = data.npcs.get('haerang');
    for (let i = 0; i < 40; i++) {
      const q = makeQuest({ rules, data, npcDef, random: Math.random, hour: 12, weather: 'clear', today: 3, seq: i });
      assert.equal(q.exp, 4);
      assert.ok(q.reward > 0);
      if (q.kind === 'deliver_fish') assert.notEqual(q.item, 'sturgeon', '맑은 낮에는 철갑상어를 부탁하지 않는다');
    }
    const wood = makeQuest({ rules, data, npcDef: data.npcs.get('mujin'), random: () => 0, hour: 12, weather: 'clear', today: 3, seq: 1 });
    assert.deepEqual({ kind: wood.kind, item: wood.item, n: wood.n }, { kind: 'deliver', item: 'wood', n: 3 });
    const slots = [{ id: 'rod', n: 1 }, { id: 'wood', n: 2 }, null];
    assert.equal(questProgress(slots, wood, data), 2);
    assert.equal(questReady(slots, wood, data), false);
    slots[2] = { id: 'wood', n: 5 };
    assert.equal(questProgress(slots, wood, data), 3);
    assert.equal(questReady(slots, wood, data), true);
    const anyFish = { kind: 'any_fish', n: 2 };
    assert.equal(questReady([{ id: 'carp', n: 1 }, { id: 'loach', n: 1 }], anyFish, data), true);
  });

  it('소지품 부탁: 지금 구할 수 있는 소지품만, 산 값보다 넉넉한 보상', () => {
    const only = { ...rules, templates: rules.templates.filter((t) => t.id === 'goods') };
    const npcDef = data.npcs.get('morak');
    const q = makeQuest({ rules: only, data, npcDef, random: () => 0.5, hour: 12, weather: 'clear', today: 1, seq: 1, goodsPool: ['honey_jar', 'tea_leaves'] });
    assert.equal(q.kind, 'deliver');
    assert.ok(['honey_jar', 'tea_leaves'].includes(q.item));
    assert.ok(q.reward > data.items.get(q.item).buy * q.n);
    for (let i = 0; i < 60; i++) {
      const other = makeQuest({ rules, data, npcDef, random: Math.random, hour: 12, weather: 'clear', today: 1, seq: i, goodsPool: [] });
      assert.notEqual(data.kindOf(other.item ?? ''), 'goods', '구할 수 있는 소지품이 없으면 소지품 부탁은 나오지 않는다');
    }
  });

  it('기한이 지난 부탁은 사라진다', () => {
    assert.deepEqual(pruneExpired([{ id: 'a', exp: 4 }, { id: 'b', exp: 5 }], 5), [{ id: 'b', exp: 5 }]);
  });
});
