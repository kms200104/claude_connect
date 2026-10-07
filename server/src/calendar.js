// v16 날씨 · 달력 앱: 오늘부터 이레 동안의 날씨 예보와 마을 이벤트 · 생일 (서버 권위).
// 날씨(weatherAt)와 하루 이벤트(planDay)는 마을 시드와 날짜로 정해지는 값이라 앞날도 그대로 계산할 수 있다.
import { DAY_MS, DAY_START_HOUR, weatherAt } from './clock.js';
import { planDay } from './events.js';
import { dateOfDay, parseMonthDay, sameDay } from './progress.js';

export const CAL_DAYS = 7;
/** 하루를 3시간씩 여덟 칸 (0시 · 3시 · … · 21시). */
const BLOCKS = [0, 3, 6, 9, 12, 15, 18, 21];

/**
 * 그날 하루 [{ day, y, m, d, wd, w: [칸마다 날씨 8개], ev: 하루 이벤트 id | '', meteor: bool, npc: [생일 주민 id], pl: [생일 친구 자리] }].
 * weatherForce 가 있으면(시험) 날씨는 그 값.
 */
export function calendarWire({ seed, today, data, profiles, weatherForce = null, seasonOf, eventForce = '', eventWanted = '' }) {
  const out = [];
  for (let i = 0; i < CAL_DAYS; i++) {
    const day = today + i;
    const date = dateOfDay(day, DAY_MS, DAY_START_HOUR);
    const season = seasonOf(day * DAY_MS + (DAY_START_HOUR + 7) * 3600000);
    const plan = planDay({ seed, day, events: data.events, data, force: eventForce, forcedWanted: eventWanted, season });
    out.push({
      day,
      ...date,
      season,
      w: BLOCKS.map((h) => weatherForce ?? weatherAt(seed, day, h + 1)),
      ev: plan.daily?.id ?? '',
      meteor: !!plan.meteor,
      npc: [...data.npcs.values()].filter((n) => sameDay(parseMonthDay(n.birthday), date)).map((n) => n.id),
      pl: profiles.filter((p) => sameDay(p.birthday, date)).map((p) => p.slot),
    });
  }
  return out;
}
