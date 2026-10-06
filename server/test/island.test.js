import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { groundProblem, onIsland } from '../src/world.js';
import { onPath } from '../src/plants.js';
import { baseMood, chooseReaction, emoteToTeach, giftToGive } from '../src/social.js';
import { loadGameData } from '../src/gamedata.js';
import { defaultConfig } from '../src/config.js';
import { Client, uid } from './helpers.js';

// 빈 풀밭 (박물관–동사무소 길 바로 남쪽: 길 가운데까지 약 4m, 둘레 3m 안에 나무·꽃밭·바위 없음).
const GRASS = { x: -43, z: 64 };

const MIN = 60000;
/** 테스트가 돌리는 시계 (gameMs 를 직접 옮긴다). */
const fakeClock = (hour = 12) => {
  const c = { hour: () => c.h, day: () => 100, gameMs: () => c.g, scale: 1, h: hour, g: 1_000_000 };
  return c;
};
// random=0: 반응은 첫 후보, 선물은 첫 물건, 꽃 색은 0번.
const BASE = { port: 0, moveSlackMeters: 200, random: () => 0, saveIntervalMs: 60000, chopCooldownMs: 0, weatherForce: 'rain', questChance: 0 };

describe('섬 생활: 심기 · 꽃 · 감정표현 · 주민 마음 · 박물관 · 공항', () => {
  const servers = [];
  const clients = [];
  const dirs = [];
  let rid = 0;
  const newRid = () => `i${++rid}`;

  async function start(overrides = {}, clock = fakeClock()) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-island-'));
    dirs.push(saveDir);
    const server = createServer({ ...BASE, saveDir, clock, ...overrides });
    servers.push(server);
    return { server, clock, saveDir };
  }
  async function join(server, code = null) {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    return { c, welcome: await c.type('welcome') };
  }
  async function moveTo(c, x, z) {
    c.send({ t: 'move', x, y: 0.1, z, yaw: 0, vx: 0, vz: 0 });
    await c.next((m) => m.t === 'snap' && m.p.some((p) => p.x === x && p.z === z));
  }
  const slotOf = (inv, id) => inv.slots.findIndex((s) => s?.id === id);

  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });

  it('섬 지형: 바다·길·건물 자리에는 심거나 놓을 수 없다', () => {
    const data = loadGameData(defaultConfig.dataDir, defaultConfig);
    const island = data.layout.island;
    assert.ok(onIsland(island, 0, 0) && onIsland(island, 60, 60));
    assert.ok(!onIsland(island, 99, 99), '모서리 바다');
    assert.equal(groundProblem(data, 0, 120), 'edge');
    assert.equal(groundProblem(data, 10, 0), 'water', '성성호수 가운데');
    assert.equal(groundProblem(data, data.museum.building.x, data.museum.building.z - 4), 'building', '박물관');
    assert.equal(groundProblem(data, 0, -80), 'building', '공항');
    assert.equal(groundProblem(data, -30.3, -7.9), 'building', 'e편한세상 112동');
    assert.equal(groundProblem(data, GRASS.x, GRASS.z), null);
    const plaza = data.layout.plaza;
    assert.ok(onPath(data.layout, plaza.x, plaza.z) && onPath(data.layout, 3, -56) && !onPath(data.layout, GRASS.x, GRASS.z));
  });

  it('씨앗을 심으면 새싹 → 묘목 → 어린 나무 → 다 자란 나무 (베면 다시 그루터기), 꽃은 피면 딸 수 있다', async () => {
    const { server, clock, saveDir } = await start({ startItems: 'acorn:2,seed_tulip:3' });
    const { c, welcome } = await join(server);
    const acorn = slotOf(welcome.inv, 'acorn');
    const seed = slotOf(welcome.inv, 'seed_tulip');
    await moveTo(c, GRASS.x, GRASS.z + 1);
    // 손에 든 게 씨앗이 아니면 못 심는다 (낚싯대).
    c.send({ t: 'plant', rid: newRid(), x: GRASS.x, z: GRASS.z });
    assert.equal((await c.type('error')).code, 'not_seed');
    // 퀵슬롯으로 옮겨 손에 든다.
    c.send({ t: 'inv_move', rid: newRid(), from: acorn, to: 2 });
    c.send({ t: 'inv_move', rid: newRid(), from: seed, to: 3 });
    c.send({ t: 'equip', slot: 2 });
    await c.next((m) => m.t === 'inventory' && m.held === 2 && m.slots[2]?.id === 'acorn');
    c.send({ t: 'plant', rid: newRid(), x: GRASS.x, z: GRASS.z + 3 });
    assert.equal((await c.type('error')).code, 'bad_plant', '길 위에는 안 된다');
    c.send({ t: 'plant', rid: newRid(), x: GRASS.x + 0.1, z: GRASS.z + 0.2 });
    const planted = await c.type('plant_result');
    assert.deepEqual({ kind: planted.kind, x: planted.x, z: planted.z }, { kind: 'tree', x: GRASS.x, z: GRASS.z }, '0.5m 격자에 맞춘다');
    const sprout = await c.next((m) => m.t === 'tree' && m.id === planted.id);
    assert.deepEqual({ s: sprout.s, k: sprout.k, x: sprout.x }, { s: 'sprout', k: 'round', x: GRASS.x });
    c.send({ t: 'plant', rid: newRid(), x: GRASS.x + 1, z: GRASS.z });
    assert.equal((await c.type('error')).code, 'bad_plant', '나무 곁에 바짝 붙여 심을 수 없다');

    const m = server.data.plants.tree_minutes;
    clock.g += m.sprout * MIN;
    assert.equal((await c.next((x) => x.t === 'tree' && x.id === planted.id, 2500)).s, 'sapling');
    clock.g += (m.sapling + m.young) * MIN;
    assert.equal((await c.next((x) => x.t === 'tree' && x.id === planted.id && x.s === 'grown', 2500)).s, 'grown');
    // 다 자란 심은 나무도 벨 수 있다.
    c.send({ t: 'equip', slot: 1 });
    for (let i = 0; i < 3; i++) {
      c.send({ t: 'chop', rid: newRid(), tree: planted.id });
      await c.type('chop_result');
    }
    assert.equal((await c.next((x) => x.t === 'tree' && x.id === planted.id && x.s === 'stump')).s, 'stump');

    // 꽃: 튤립 알뿌리
    c.send({ t: 'equip', slot: 3 });
    await c.next((x) => x.t === 'inventory' && x.held === 3);
    c.send({ t: 'plant', rid: newRid(), x: GRASS.x + 2, z: GRASS.z + 2 });
    const fp = await c.type('plant_result');
    assert.equal(fp.kind, 'flower');
    const f0 = await c.next((x) => x.t === 'flower' && x.f.id === fp.id);
    assert.deepEqual({ sp: f0.f.sp, s: f0.f.s, c: f0.f.c }, { sp: 'tulip', s: 'sprout', c: 0 });
    c.send({ t: 'pick', rid: newRid(), id: fp.id });
    assert.equal((await c.type('error')).code, 'no_flower', '아직 안 핀 꽃은 못 딴다');
    const tulip = server.data.flowerDefs.get('tulip');
    clock.g += (tulip.minutes.sprout + tulip.minutes.bud) * MIN;
    assert.equal((await c.next((x) => x.t === 'flower' && x.f.id === fp.id && x.f.s === 'bloom', 2500)).f.s, 'bloom');
    c.send({ t: 'pick', rid: newRid(), id: fp.id });
    const picked = await c.type('pick_result');
    assert.equal(picked.item, 'tulip');
    assert.equal((await c.next((x) => x.t === 'flower' && x.f.id === fp.id)).f.s, 'bud', '따면 봉오리로 돌아간다');
    await c.next((x) => x.t === 'inventory' && x.slots.some((s) => s?.id === 'tulip'));

    await server.rooms.flushAll();
    const saved = JSON.parse(readFileSync(path.join(saveDir, `${welcome.code}.json`), 'utf8'));
    assert.equal(saved.world.planted.length, 1);
    assert.equal(saved.world.planted[0].kind, 'round');
    assert.equal(saved.world.flowers.length, 1);
    assert.equal(saved.world.trees[planted.id], undefined, '심은 나무 상태는 planted 에 함께 저장된다');
  });

  it('감정표현: 배운 것만 할 수 있고, 상대에게 보이고, 근처 주민이 반응하며 하루 한 번 친해진다', async () => {
    const { server } = await start();
    const a = await join(server);
    const b = await join(server, a.welcome.code);
    const tong = a.welcome.npcs.find((n) => n.id === 'tongtong');
    await moveTo(a.c, tong.x + 2, tong.z);
    a.c.send({ t: 'emote', e: 'love' });
    assert.equal((await a.c.type('error')).code, 'unknown_emote', '아직 안 배운 감정표현');
    a.c.send({ t: 'emote', e: 'hello' });
    const seen = await b.c.next((m) => m.t === 'act' && m.kind === 'emote');
    assert.deepEqual({ id: seen.id, e: seen.e }, { id: 1, e: 'hello' });
    const react = await a.c.next((m) => m.t === 'npc_emote' && m.npc === 'tongtong');
    assert.equal(react.to, 1);
    assert.ok(server.data.emoteIds.has(react.e));
    const prof = await a.c.next((m) => m.t === 'profile' && m.friends.tongtong === 1);
    assert.ok(prof, '반응해 준 주민과 친해진다');
    // 브레이크 몸짓은 배우지 않아도 보낼 수 있다.
    a.c.send({ t: 'emote', e: 'brake' });
    assert.equal((await b.c.next((m) => m.t === 'act' && m.e === 'brake')).kind, 'emote');
    // 감정표현 퀵슬롯: 배운 것만.
    a.c.send({ t: 'emote_quick', quick: ['hello', 'love'] });
    assert.deepEqual((await a.c.next((m) => m.t === 'profile' && m.emotes)).emotes.quick, ['hello']);
  });

  it('대화: 오늘의 기분·주제 수다(하루 상한)·감정표현 배우기·친한 주민의 선물', async () => {
    const { server } = await start({ startFriendship: 30 });
    const { c, welcome } = await join(server);
    const morak = welcome.npcs.find((n) => n.id === 'morak');
    await moveTo(c, morak.x + 1.5, morak.z);
    c.send({ t: 'talk', rid: newRid(), npc: 'morak' });
    const open = await c.type('talk_open');
    assert.ok(['happy', 'calm', 'sad', 'grumpy', 'sleepy', 'excited'].includes(open.m));
    assert.equal(open.teach, 'love', '친밀도가 충분하면 감정표현을 가르쳐 준다');
    assert.equal(open.gift, 'tea_leaves', '친한 주민이 선물을 준다');
    const inv = await c.next((m) => m.t === 'inventory' && m.slots.some((s) => s?.id === 'tea_leaves'));
    assert.ok(inv);
    const gains = [];
    for (const topic of ['hobby', 'gossip', 'fish', 'dream']) {
      c.send({ t: 'talk_topic', topic });
      gains.push((await c.type('talk_topic')).gain);
    }
    assert.deepEqual(gains, [1, 1, 1, 0], '수다로 오르는 친밀도는 하루 세 번까지');
    c.send({ t: 'talk_topic', topic: 'weird' });
    assert.equal((await c.type('error')).code, 'bad_topic');
    c.send({ t: 'talk_end' });
    c.send({ t: 'talk_topic', topic: 'hobby' });
    assert.equal((await c.type('error')).code, 'not_talking');
    // 같은 날 다시 말 걸면 선물은 안 준다 (하루 한 번).
    c.send({ t: 'talk', rid: newRid(), npc: 'morak' });
    const again = await c.type('talk_open');
    assert.equal(again.gift, undefined);
  });

  it('박물관: 관장 곁에서 물고기를 한 종씩 기증하고, 다섯 종이면 어항을 받는다', async () => {
    const { server } = await start({ startItems: 'crucian:2,loach:1,minnow:1,pale_chub:1,korean_minnow:1,wood:1' });
    const a = await join(server);
    const b = await join(server, a.welcome.code);
    const inv = a.welcome.inv;
    a.c.send({ t: 'donate', rid: newRid(), slot: slotOf(inv, 'crucian') });
    assert.equal((await a.c.type('error')).code, 'not_near_keeper');
    const cur = server.data.museum.curator;
    await moveTo(a.c, cur.x + 1, cur.z + 1);
    a.c.send({ t: 'donate', rid: newRid(), slot: slotOf(inv, 'wood') });
    assert.equal((await a.c.type('error')).code, 'not_fish');
    let slots = inv.slots;
    const results = [];
    for (const fish of ['crucian', 'loach', 'minnow', 'pale_chub', 'korean_minnow']) {
      a.c.send({ t: 'donate', rid: newRid(), slot: slots.findIndex((s) => s?.id === fish) });
      results.push(await a.c.type('donate_result'));
      slots = (await a.c.type('inventory')).slots;
    }
    assert.deepEqual(results.map((r) => r.count), [1, 2, 3, 4, 5]);
    assert.deepEqual(results[4].gifts, ['fish_tank']);
    assert.equal(results[4].sol, 25000, '기증할 때마다 5,000솔');
    a.c.send({ t: 'donate', rid: newRid(), slot: slots.findIndex((s) => s?.id === 'crucian') });
    assert.equal((await a.c.type('error')).code, 'already_donated');
    const shared = await b.c.next((m) => m.t === 'museum' && Object.keys(m.fish).length === 5);
    assert.equal(shared.fish.crucian, 1, '마을 공용: 상대에게도 기증 목록이 보인다');
  });

  it('공항 기념품 가게: 조종사 곁에서 공항 물건만 산다', async () => {
    const { server } = await start({ startSol: 100000 });
    const { c } = await join(server);
    c.send({ t: 'shop_buy', rid: newRid(), item: 'seed_sunflower', n: 1, at: 'airport' });
    assert.equal((await c.type('error')).code, 'not_near_keeper');
    const pilot = server.data.airport.pilot;
    await moveTo(c, pilot.x + 1, pilot.z + 1);
    c.send({ t: 'shop_buy', rid: newRid(), item: 'sofa', n: 1, at: 'airport' });
    assert.equal((await c.type('error')).code, 'not_for_sale');
    c.send({ t: 'shop_buy', rid: newRid(), item: 'seed_sunflower', n: 2, at: 'airport' });
    const bought = await c.type('shop_result');
    assert.deepEqual({ item: bought.item, sol: bought.sol, at: bought.at }, { item: 'seed_sunflower', sol: 76000, at: 'airport' });
  });

  it('주민 마음: 같은 시각이면 같은 기분, 밤엔 졸리고, 성격대로 반응하고, 친해지면 가르쳐 주고 선물한다', () => {
    const data = loadGameData(defaultConfig.dataDir, defaultConfig);
    const haerang = data.npcs.get('haerang');
    const args = { seed: 42, day: 7, hour: 14, index: 2, def: haerang, weather: 'clear', eventDay: false };
    assert.equal(baseMood(args), baseMood(args));
    let sleepy = 0;
    for (let day = 0; day < 60; day++) if (baseMood({ ...args, day, hour: 23 }) === 'sleepy') sleepy += 1;
    assert.ok(sleepy > 30, `한밤중엔 대개 졸리다 (${sleepy}/60)`);
    assert.equal(chooseReaction({ emotes: data.emotes, personality: 'gruff', mood: 'calm', emote: 'angry', random: () => 0.9 }), 'angry');
    assert.equal(chooseReaction({ emotes: data.emotes, personality: 'kind', mood: 'sleepy', emote: 'hello', random: () => 0 }), 'sleepy', '졸린 주민은 졸린 반응');
    assert.equal(emoteToTeach(data.npcs.get('tongtong'), 1, ['hello']), null);
    assert.equal(emoteToTeach(data.npcs.get('tongtong'), 12, ['hello', 'happy']), 'surprise');
    const rel = { f: 20, giftDay: 99 };
    assert.equal(giftToGive({ def: haerang, rel, rules: data.npcRules.gift, today: 99, random: () => 0 }), null, '하루 한 번');
    assert.equal(giftToGive({ def: haerang, rel, rules: data.npcRules.gift, today: 100, random: () => 0 }), haerang.gifts[0]);
  });
});
