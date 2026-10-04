// 마을 시계와 날씨. 둘 다 서버가 정하고, 클라이언트는 welcome/clock·weather 메시지로 받아 그린다.
import { Weather } from './protocol.js';

export const HOUR_MS = 3600000;
export const DAY_MS = 24 * HOUR_MS;
// 마을의 하루는 새벽 5시에 바뀐다 (나무가 다시 자라고, 부탁이 만료되는 기준).
export const DAY_START_HOUR = 5;

/**
 * 게임 시각(ms)은 "마을 시간대의 벽시계"를 epoch ms로 나타낸 값이다.
 * clockScale 배로 흐르고, clockOffsetMin 만큼 앞당기거나 늦출 수 있다(테스트·시연용).
 */
export function createClock(cfg, realNow = () => Date.now()) {
  const anchor = realNow();
  const shift = (cfg.utcOffsetMin + cfg.clockOffsetMin) * 60000;
  const gameMs = (real = realNow()) => anchor + (real - anchor) * cfg.clockScale + shift;
  return {
    scale: cfg.clockScale,
    gameMs,
    hour: () => hourOf(gameMs()),
    day: () => dayIndex(gameMs()),
  };
}

/** 0 이상 24 미만의 시(소수 포함). */
export function hourOf(gameMs) {
  return (((gameMs % DAY_MS) + DAY_MS) % DAY_MS) / HOUR_MS;
}

/** 새벽 5시 기준 날짜 번호. */
export function dayIndex(gameMs) {
  return Math.floor((gameMs - DAY_START_HOUR * HOUR_MS) / DAY_MS);
}

/** 시간대 구간: morning(5–10) day(10–17) evening(17–20) night(20–5). */
export function timeBand(hour) {
  if (hour >= 5 && hour < 10) return 'morning';
  if (hour >= 10 && hour < 17) return 'day';
  if (hour >= 17 && hour < 20) return 'evening';
  return 'night';
}

/** [start, end) 시간 범위. start > end 면 자정을 넘긴다 (예: [17, 5]). 범위가 없으면 언제나 참. */
export function inHours(range, hour) {
  if (!Array.isArray(range) || range.length !== 2) return true;
  const [start, end] = range;
  return start <= end ? hour >= start && hour < end : hour >= start || hour < end;
}

// ---- 날씨 ----

// 하루를 3시간 블록 8개로 나누고, 블록마다 날씨를 정한다. 직전 블록과 같을 확률을 높여 날씨가 자주 바뀌지 않게 한다.
const BLOCK_HOURS = 3;
const TABLE = [
  [Weather.clear, 50],
  [Weather.cloudy, 25],
  [Weather.rain, 18],
  [Weather.thunder, 7],
];
const STAY_CHANCE = 0.5;

/** 32비트 정수 해시 → [0, 1) 난수 생성기 (같은 시드면 항상 같은 수열). */
export function seededRandom(...parts) {
  let h = 0x811c9dc5;
  for (const p of parts) {
    h ^= p >>> 0;
    h = Math.imul(h, 0x01000193) >>> 0;
    h ^= h >>> 15;
  }
  let state = h || 0x9e3779b9;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function draw(random) {
  const total = TABLE.reduce((s, [, w]) => s + w, 0);
  let r = random() * total;
  for (const [w, weight] of TABLE) {
    r -= weight;
    if (r < 0) return w;
  }
  return Weather.clear;
}

/** 마을 시드와 날짜·시각으로 날씨를 정한다. 저장할 필요 없이 언제 계산해도 같은 값이 나온다. */
export function weatherAt(seed, day, hour) {
  const random = seededRandom(seed, day + 100000);
  const block = Math.min(Math.floor(hour / BLOCK_HOURS), 24 / BLOCK_HOURS - 1);
  let current = draw(random);
  for (let i = 1; i <= block; i++) {
    if (random() >= STAY_CHANCE) current = draw(random);
  }
  return current;
}

export function isWeather(value) {
  return Object.values(Weather).includes(value);
}
