// v0.22 세상 시각: 낮 · 밤은 60배 (현실 1분 = 마을 1시간), 날짜 · 주 · 계절 · 날씨는 달력 그대로.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createClock, HOUR_MS } from '../src/clock.js';

describe('v0.22 세상 시각 60배', () => {
  it('현실 1분이 지나면 세상 시각은 1시간, 달력 시각은 1분 흐른다', () => {
    let real = Date.UTC(2026, 9, 13, 3, 0, 0); // 한국 12:00
    const clock = createClock({ clockScale: 1, utcOffsetMin: 540, clockOffsetMin: 0, worldTimeScale: 60 }, () => real);
    assert.equal(clock.hour(), 12, '켠 순간은 달력과 같다');
    assert.equal(clock.calHour(), 12);
    const day = clock.day();
    real += 60000;
    assert.ok(Math.abs(clock.hour() - 13) < 1e-9, `세상 ${clock.hour()}`);
    assert.ok(Math.abs(clock.calHour() - (12 + 1 / 60)) < 1e-9, '달력은 1분');
    // 현실 24분이면 세상은 하루가 돈다 (같은 시각으로 돌아온다). 달력 날짜는 그대로.
    real += 23 * 60000;
    assert.ok(Math.abs(clock.hour() - 12) < 1e-6);
    assert.equal(clock.day(), day, '날짜 · 주 · 경제는 달력');
    assert.equal(clock.worldScale, 60);
  });

  it('배율 1 이면 예전과 같다 (테스트 · 시연)', () => {
    let real = Date.UTC(2026, 9, 13, 3, 0, 0);
    const clock = createClock({ clockScale: 1, utcOffsetMin: 540, clockOffsetMin: 0, worldTimeScale: 1 }, () => real);
    real += 3 * HOUR_MS;
    assert.equal(clock.hour(), clock.calHour());
  });
});
