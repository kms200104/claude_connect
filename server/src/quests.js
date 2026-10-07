// 주민 부탁(퀘스트). 말을 걸 때 서버가 확률로 부탁을 만들고, 받은 부탁은 아이템을 가져가면 완료된다.
// 부탁 내용은 지금 시각·날씨에 실제로 구할 수 있는 것만 고른다 (불가능한 부탁 방지).
//
// profile.npcs[npcId] = { f: 친밀도 0~100, talkDay: 마지막으로 처음 말 건 날, offerDay: 마지막으로 부탁을 받은 날,
//                       giftDay: 마지막으로 선물 받은 날, emoteDay: 감정표현으로 친밀도가 오른 날, chatDay/chatCount: 오늘 수다로 오른 횟수 }
// profile.quests = [{ id, npc, kind, item?, n, reward, exp }]   exp: 이 날짜까지 유효
import { availableFish, pickWeighted } from './gamedata.js';
import { countWhere } from './inventory.js';

export const QuestKind = Object.freeze({ deliver: 'deliver', deliverFish: 'deliver_fish', anyFish: 'any_fish' });

const FRIEND_MAX = 100;

export function friendStage(f) {
  return Math.min(4, Math.floor(f / 20));
}

export function relationOf(profile, npcId) {
  profile.npcs[npcId] ??= { f: 0, talkDay: null, offerDay: null, giftDay: null, emoteDay: null, chatDay: null, chatCount: 0 };
  return profile.npcs[npcId];
}

export function addFriendship(rel, amount) {
  rel.f = Math.min(FRIEND_MAX, rel.f + amount);
}

/** 오늘 수다(대화 주제·두 번째 대화)로 친밀도를 더 올릴 수 있으면 올린다. 오른 양을 돌려준다. */
export function addChatFriendship(rel, today, amount, perDay) {
  if (rel.chatDay !== today) {
    rel.chatDay = today;
    rel.chatCount = 0;
  }
  if (rel.chatCount >= perDay) return 0;
  rel.chatCount += 1;
  addFriendship(rel, amount);
  return amount;
}

/** 이번 대화에서 부탁을 할지. chance 가 null 이면 데이터의 확률(+친밀도 보너스)을 쓴다. */
export function shouldOffer({ rules, profile, npcId, today, random, chance = null }) {
  const rel = relationOf(profile, npcId);
  if (profile.quests.some((q) => q.npc === npcId)) return false;
  if (profile.quests.length >= rules.max_active) return false;
  if (rel.offerDay === today) return false;
  // 한동안 부탁을 못 받았으면 확실히 하나 준다.
  if (profile.lastQuestDay !== null && today - profile.lastQuestDay >= rules.pity_days) return true;
  const p = chance ?? Math.min(rules.chance + friendStage(rel.f) * rules.chance_per_friend_stage, rules.chance_max);
  return random() < p;
}

const between = (random, min, max) => min + Math.floor(random() * (max - min + 1));

/**
 * 부탁 하나를 만든다. 지금 낚을 수 있는 물고기가 없으면 물고기 부탁은 고르지 않는다.
 * goodsPool: 지금 구할 수 있는 소지품 id (상점 진열품 + 나무에서 나오는 것). 비어 있으면 소지품 부탁은 고르지 않는다.
 */
export function makeQuest({ rules, data, npcDef, random, hour, weather, season = null, today, seq, goodsPool = [] }) {
  const fishNow = [];
  for (const spot of data.allSpots?.() ?? data.spots.values()) {
    for (const f of availableFish(spot, data.fish, hour, weather, season)) if (!fishNow.includes(f)) fishNow.push(f);
  }
  const likes = npcDef.likes ?? [];
  const templates = rules.templates.filter(
    (t) => (t.kind !== QuestKind.deliverFish || fishNow.length > 0) && (t.pool !== 'goods' || goodsPool.length > 0),
  );
  const t = pickWeighted(templates, (x) => x.weight + (likes.includes(x.id) ? rules.like_weight_bonus : 0), random);
  const n = between(random, t.min, t.max);
  const quest = { id: `q${seq}`, npc: npcDef.id, kind: t.kind, n, reward: t.reward_base + t.reward_per * n, exp: today + 1 };
  if (t.kind === QuestKind.deliver && t.pool === 'goods') {
    // 소지품: 사 오거나 주워 와야 해서 그 값만큼 더 쳐준다.
    quest.item = goodsPool[Math.floor(random() * goodsPool.length)];
    const info = data.items.get(quest.item);
    quest.reward = t.reward_base + (info.buy ?? info.price * 2) * n;
  } else if (t.kind === QuestKind.deliver) quest.item = t.item;
  if (t.kind === QuestKind.deliverFish) {
    const fish = pickWeighted(fishNow, (f) => f.weight, random);
    quest.item = fish.id;
    quest.reward = t.reward_by_rarity[fish.rarity] ?? 20000;
  }
  return quest;
}

/** 이 부탁에 쓸 수 있는 아이템인지. */
export function questAccepts(q, data) {
  return q.kind === QuestKind.anyFish ? (id) => data.isFish(id) : (id) => id === q.item;
}

export function questProgress(slots, q, data) {
  return Math.min(countWhere(slots, questAccepts(q, data)), q.n);
}

export function questReady(slots, q, data) {
  return questProgress(slots, q, data) >= q.n;
}

export function pruneExpired(quests, today) {
  return quests.filter((q) => q.exp >= today);
}

export function questWire(q, slots, data) {
  return { ...q, have: questProgress(slots, q, data) };
}

/** 저장 파일 → 모양이 맞는 부탁만. */
export function sanitizeQuests(raw, data) {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (q) =>
      q &&
      typeof q.id === 'string' &&
      data.npcs.has(q.npc) &&
      Object.values(QuestKind).includes(q.kind) &&
      Number.isInteger(q.n) &&
      q.n > 0 &&
      Number.isInteger(q.reward) &&
      Number.isInteger(q.exp) &&
      (q.kind === QuestKind.anyFish || data.isKnown(q.item)),
  );
}

export function sanitizeRelations(raw, data) {
  const out = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [id, r] of Object.entries(raw)) {
    if (!data.npcs.has(id) || !r) continue;
    out[id] = {
      f: Number.isInteger(r.f) ? Math.max(0, Math.min(FRIEND_MAX, r.f)) : 0,
      talkDay: Number.isInteger(r.talkDay) ? r.talkDay : null,
      offerDay: Number.isInteger(r.offerDay) ? r.offerDay : null,
      giftDay: Number.isInteger(r.giftDay) ? r.giftDay : null,
      emoteDay: Number.isInteger(r.emoteDay) ? r.emoteDay : null,
      chatDay: Number.isInteger(r.chatDay) ? r.chatDay : null,
      chatCount: Number.isInteger(r.chatCount) ? r.chatCount : 0,
      msgReplyDay: Number.isInteger(r.msgReplyDay) ? r.msgReplyDay : null, // 마을톡 답장으로 친밀도를 올린 날 (v0.11)
    };
  }
  return out;
}
