import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { chooseReaction, mbtiLetter, moodAfterEmote } from '../src/social.js';

describe('주민 MBTI: T 는 공감이 서툴고 F 는 감정적으로 공감한다', () => {
  const data = loadGameData(defaultConfig.dataDir, defaultConfig);
  const npc = (id) => data.npcs.get(id);
  const always = () => 0;

  it('여섯 주민 모두 MBTI 가 있고 F 셋 · T 셋', () => {
    const types = [...data.npcs.values()].map((n) => n.mbti);
    assert.ok(types.every((t) => data.mbti.types[t]), JSON.stringify(types));
    assert.equal(types.filter((t) => mbtiLetter(t, 2) === 'F').length, 3);
    assert.equal(types.filter((t) => mbtiLetter(t, 2) === 'T').length, 3);
  });

  it('슬퍼하면 F 는 안아 주며 같이 시무룩해지고, T 는 생각에 잠길 뿐 기분이 그대로', () => {
    const f = npc('morak');
    const t = npc('mujin');
    const fr = chooseReaction({ emotes: data.emotes, personality: f.personality, mood: 'calm', emote: 'sad', random: always, mbti: data.mbti, type: f.mbti });
    const tr = chooseReaction({ emotes: data.emotes, personality: t.personality, mood: 'calm', emote: 'sad', random: always, mbti: data.mbti, type: t.mbti });
    assert.ok(['love', 'sad'].includes(fr), fr);
    assert.equal(tr, 'think');
    assert.equal(moodAfterEmote(data.emotes, f.personality, 'sad', data.mbti, f.mbti), 'sad');
    assert.notEqual(moodAfterEmote(data.emotes, t.personality, 'sad', data.mbti, t.mbti), 'sad');
    // 기뻐하면 F 는 같이 들뜨고 T 는 박수 한 번.
    assert.equal(moodAfterEmote(data.emotes, f.personality, 'happy', data.mbti, f.mbti), 'happy');
    assert.equal(chooseReaction({ emotes: data.emotes, personality: t.personality, mood: 'calm', emote: 'happy', random: always, mbti: data.mbti, type: t.mbti }), 'clap');
  });

  it('E 는 멀리서도 반응하고 I 는 가까이에서만, 고민 상담은 F 와 더 친해진다', () => {
    assert.ok(data.mbti.react_range.E > data.emotes.react_range && data.mbti.react_range.I < data.emotes.react_range);
    assert.equal(data.mbti.worry_friend_bonus.F, 1);
    assert.equal(data.mbti.worry_friend_bonus.T, 0);
    for (const key of ['worry_F', 'worry_T', 'worry_T_after', 'react_F_sad', 'react_T_sad']) assert.ok(data.mbti.lines[key].length >= 2, key);
  });
});
