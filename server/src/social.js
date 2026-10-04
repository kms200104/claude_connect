// 주민의 마음 (서버 권위): 기분, 감정표현 반응, 감정표현 가르쳐 주기, 선물.
// 기분은 마을 시드·날짜·3시간 구간으로 뽑는 '오늘의 바탕 기분'에 날씨·밤·이벤트가 더해지고,
// 플레이어의 감정표현·부탁 완료 같은 일이 잠시 덮어쓴다 (moodOverride). 대사 말투는 클라이언트가 기분에 맞춰 바꾼다.
import { seededRandom } from './clock.js';
import { pickWeighted } from './gamedata.js';

export const MOODS = Object.freeze(['happy', 'calm', 'sad', 'grumpy', 'sleepy', 'excited']);
const MOOD_SALT = 0x6d00d;
// 감정표현·대화로 바뀐 기분이 유지되는 시간 (실제 ms).
export const MOOD_OVERRIDE_MS = 8 * 60 * 1000;

/** 성격별로 감정표현이 기분을 바꾸는 방식 (없으면 emotes.json 의 mood). */
const EMOTE_MOOD = {
  kind: { angry: 'sad', sad: 'calm' },
  lively: { angry: 'excited', sad: 'calm', surprise: 'excited' },
  lazy: { angry: 'sleepy', surprise: 'calm', sleepy: 'sleepy' },
  gruff: { hello: 'calm', happy: 'calm', love: 'grumpy', angry: 'grumpy', sleepy: 'grumpy', clap: 'happy' },
  snooty: { angry: 'grumpy', sleepy: 'grumpy', hello: 'calm' },
  dreamy: { angry: 'sad', sad: 'sad', think: 'calm' },
};

/** 오늘(3시간 구간)의 바탕 기분. 같은 마을·같은 시각이면 언제 계산해도 같다. */
export function baseMood({ seed, day, hour, index, def, weather, eventDay }) {
  const block = Math.floor(hour / 3);
  const random = seededRandom(seed, day * 8 + block + MOOD_SALT, index);
  const weights = { ...(def.mood_bias ?? {}) };
  for (const m of MOODS) weights[m] = weights[m] ?? 1;
  const byWeather = def.weather?.[weather];
  if (byWeather) weights[byWeather] += 4;
  if (hour >= 22 || hour < 6) weights.sleepy += 6;
  if (eventDay && (def.personality === 'lively' || def.personality === 'dreamy')) weights.excited += 2;
  return pickWeighted(MOODS, (m) => Math.max(weights[m], 0.01), random);
}

/** 지금 기분 (덮어쓴 기분이 살아 있으면 그것). */
export function currentMood(npc, now) {
  return npc.moodOverride && npc.moodOverride.until > now ? npc.moodOverride.m : npc.baseMood;
}

export function setMood(npc, mood, now, ms = MOOD_OVERRIDE_MS) {
  if (!MOODS.includes(mood)) return;
  npc.moodOverride = { m: mood, until: now + ms };
}

/** 플레이어의 감정표현에 이 주민이 보일 반응 (감정표현 id). 기분이 반응을 바꾸기도 한다. */
export function chooseReaction({ emotes, personality, mood, emote, random }) {
  const byMood = emotes.mood_reactions?.[mood];
  if (byMood && random() < 0.35) return byMood[Math.floor(random() * byMood.length)];
  const options = emotes.reactions?.[personality]?.[emote] ?? emotes.reactions?.kind?.[emote] ?? ['hello'];
  return options[Math.floor(random() * options.length)];
}

/** 감정표현을 받은 뒤의 기분 ('' 이면 그대로). */
export function moodAfterEmote(emotes, personality, emote) {
  const special = EMOTE_MOOD[personality]?.[emote];
  if (special) return special;
  return emotes.emotes.find((e) => e.id === emote)?.mood ?? '';
}

/** 친밀도에 맞춰 아직 안 가르쳐 준 감정표현 하나 (없으면 null). */
export function emoteToTeach(def, friendship, known) {
  for (const [emote, need] of def.teaches ?? []) {
    if (friendship >= need && !known.includes(emote)) return emote;
  }
  return null;
}

/** 친해진 주민이 오늘 선물을 줄지, 준다면 무엇을. */
export function giftToGive({ def, rel, rules, today, random }) {
  if (!def.gifts?.length || rel.f < rules.min_friendship) return null;
  if (rel.giftDay !== null && rel.giftDay !== undefined && today - rel.giftDay < rules.cooldown_days) return null;
  if (random() >= rules.chance) return null;
  return def.gifts[Math.floor(random() * def.gifts.length)];
}
