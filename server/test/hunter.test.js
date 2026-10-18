// v0.28 헌터: 처치 점수 · 마석 · 협회 창구 매각 · 등급 재심사 · 현상금 의뢰 · 길드.
import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { PROTOCOL_VERSION } from '../src/protocol.js';
import { loadGameData } from '../src/gamedata.js';
import { Room } from '../src/rooms.js';
import { defaultConfig } from '../src/config.js';
import { Client, sleep, uid } from './helpers.js';

const data = loadGameData(defaultConfig.dataDir, defaultConfig);
const H = data.hunter;
const S = data.survival;
const office = { x: H.office.x, z: H.office.z + 1.2 };
const offsetTo = (hour) => {
  const d = new Date();
  const kst = (d.getUTCHours() * 60 + d.getUTCMinutes() + 540) % 1440;
  return (hour * 60 - kst + 1440) % 1440;
};

describe('v0.28 헌터', () => {
  const dirs = [];
  const servers = [];
  const clients = [];
  let n = 0;
  after(async () => {
    for (const c of clients) c.kill();
    for (const s of servers) await s.close();
    for (const d of dirs) rmSync(d, { recursive: true, force: true });
  });
  function start(hour, extra = {}) {
    const saveDir = mkdtempSync(path.join(tmpdir(), 'solbaram-hunter-'));
    dirs.push(saveDir);
    const server = createServer({
      port: 0, saveDir, saveIntervalMs: 60000, weatherForce: 'clear', moveSlackMeters: 3000, worldTimeScale: 1, clockOffsetMin: offsetTo(hour),
      creatureSpawnScale: 10000, creatureFreeze: true, random: () => 0.5, ...extra,
    });
    servers.push(server);
    return server;
  }
  async function join(server, code = '') {
    const c = new Client(server.port);
    clients.push(c);
    await c.opened;
    c.send(code ? { t: 'join', v: PROTOCOL_VERSION, uid: uid(), code } : { t: 'create', v: PROTOCOL_VERSION, uid: uid() });
    const w = await c.type('welcome');
    return { c, w };
  }
  const ask = async (c, msg, ms = 3000) => {
    const rid = `hu-${++n}`;
    c.send({ ...msg, rid });
    return c.next((m) => m.rid === rid, ms);
  };
  const moveTo = async (c, p) => {
    c.send({ t: 'move', x: p.x, y: 0.1, z: p.z, yaw: 0, vx: 0, vz: 0 });
    await sleep(120);
  };
  const roomOf = (server) => [...server.rooms.rooms.values()][0];
  const put = (room, id, p, k = 'shambler', hp = 1) => {
    room.creatures ??= new Map();
    room.creatures.set(id, { id, k, x: p.x, z: p.z, yaw: 0, hp, target: 0, nextAttack: 0, attackAt: 0, trapAt: {} });
  };
  const spot = { x: -150, z: 140 };

  it('처치하면 점수 · 마석, 협회 창구에서만 마석을 판다, 점수가 차면 등급 재심사', async () => {
    const server = start(23, { startItems: 'pipe_spear:1,mana_stone_e:5,mana_stone_d:2' });
    const { c, w } = await join(server);
    assert.equal(w.hunter.rank, 'E');
    assert.equal(w.hunter.next, 150);
    assert.equal(w.hunter.bounties.length, H.bounty.per_day);
    await moveTo(c, spot);
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    me.profile.held = me.slots.findIndex((x) => x?.id === 'pipe_spear');
    put(room, 'zh1', { x: spot.x + 1, z: spot.z });
    const swing = await ask(c, { t: 'attack' });
    assert.equal(swing.hit, 'zh1');
    const res = await c.next((m) => m.t === 'hunter_result' && m.kind === 'kill', 2000);
    assert.equal(res.pts, H.kill.points.shambler);
    assert.deepEqual(res.mana, [{ id: 'mana_stone_e', n: 1 }]);
    const hu = await c.next((m) => m.t === 'hunter' && m.kills === 1, 2000);
    assert.equal(hu.pts, H.kill.points.shambler);
    await c.next((m) => m.t === 'drop' && m.d.item === 'mana_stone_e', 2000);

    // 창구에서만.
    assert.equal((await ask(c, { t: 'hunter_sell', all: true })).code, 'not_at_office');
    await moveTo(c, office);
    const sol0 = me.profile.sol;
    const sold = await ask(c, { t: 'hunter_sell', all: true });
    assert.equal(sold.t, 'hunter_result');
    assert.equal(sold.amount, 5 * 3000 + 2 * 9000);
    assert.equal(sold.pts, 2);
    assert.equal(me.profile.sol, sol0 + sold.amount);
    assert.ok(!me.slots.some((s) => s?.id?.startsWith('mana_stone')));

    // 재심사.
    assert.equal((await ask(c, { t: 'hunter_rank' })).code, 'rank_not_ready');
    me.profile.hunter.pts = 700;
    const up = await ask(c, { t: 'hunter_rank' });
    assert.deepEqual({ from: up.from, rank: up.rank }, { from: 'E', rank: 'C' }, '여러 등급을 한꺼번에');
    assert.equal((await ask(c, { t: 'hunter_rank' })).code, 'rank_not_ready');
    // C급은 마석을 10% 더 받는다.
    me.slots[10] = { id: 'mana_stone_c', n: 1 };
    const more = await ask(c, { t: 'hunter_sell', slot: 10 });
    assert.equal(more.amount, Math.round(28000 * 1.1));
  });

  it('v0.28.15 헌터 마일리지: 점수를 받으면 쌓이고, 협회 상점에서 쓴다 (등급 · 직업 조건), 아공간 주머니 · 상자로 칸이 늘어난다 (저장된다)', async () => {
    const server = start(12, { startItems: 'pipe_spear:1' });
    const { c, w } = await join(server);
    assert.equal(w.hunter.mi, 0);
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    const kit = H.store.items.find((x) => x.id === 'first_aid_kit');
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'first_aid_kit' })).code, 'not_at_office');
    await moveTo(c, office);
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'first_aid_kit' })).code, 'not_enough_mileage');
    // 점수를 받으면 같은 만큼 마일리지 (마석 D 2개 = 점수 2).
    me.slots[10] = { id: 'mana_stone_d', n: 2 };
    await ask(c, { t: 'hunter_sell', slot: 10 });
    assert.equal(me.profile.hunter.mi, 2 * H.mileage.per_point);
    me.profile.hunter.mi = 5000;
    const got = await ask(c, { t: 'hunter_buy', i: 'first_aid_kit' });
    assert.equal(got.kind, 'buy');
    assert.equal(got.mi, 5000 - kit.cost);
    assert.ok(me.slots.some((x) => x?.id === 'first_aid_kit'));
    const hu = await c.next((m) => m.t === 'hunter' && m.mi === 5000 - kit.cost, 2000);
    assert.equal(hu.pts, 2, '등급 심사 점수는 그대로');
    // 등급이 모자라면 (D급 물건) · 직업 전용은 그 직업만.
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'armor_plate' })).code, 'rank_too_low');
    // 아공간 주머니: 차례대로 — 소 (+5) 를 사야 중을 산다. 가방 칸이 늘어난다.
    const before = me.slots.length;
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'subspace_pouch_m' })).code, 'rank_too_low');
    me.profile.hunter.rank = 'C';
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'subspace_pouch_m' })).code, 'bad_item', '소를 먼저');
    const small = await ask(c, { t: 'hunter_buy', i: 'subspace_pouch_s' });
    assert.deepEqual({ up: small.up, add: small.add }, { up: 'bag', add: 5 });
    assert.equal(me.slots.length, before + 5);
    assert.equal(me.profile.bagExtra, 5);
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'subspace_pouch_s' })).code, 'bad_item', '두 번은 못 산다');
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'subspace_pouch_m' })).kind, 'buy');
    assert.equal(me.slots.length, before + 10);
    // 늘어난 칸에도 들어간다.
    me.slots[me.slots.length - 1] = { id: 'bandage', n: 1 };
    // 아공간 상자: 방 전체 거점 상자 칸.
    const cap0 = data.survival.base.slots;
    const crate = await ask(c, { t: 'hunter_buy', i: 'subspace_crate' });
    assert.equal(crate.up, 'stash');
    assert.equal(room.stashExtra, 6);
    await c.next((m) => m.t === 'hunter' && m.stashCap === cap0 + 6, 2000);
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'greatsword' })).code, 'job_only');
    me.profile.hunter.job = 'warrior';
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'greatsword' })).kind, 'buy');
    assert.equal((await ask(c, { t: 'hunter_buy', i: 'nope' })).code, 'bad_item');
    // 저장했다 다시 읽어도 늘어난 칸 · 그 안의 물건 · 상자 칸이 그대로.
    const saved = room.toSave();
    assert.equal(saved.world.stashExtra, 6);
    const prof = Object.values(saved.profiles)[0];
    assert.equal(prof.bagExtra, 10);
    assert.equal(prof.slots.length, before + 10);
    assert.equal(prof.slots[prof.slots.length - 1].id, 'bandage');
    const back = Room.fromSave(structuredClone(saved), 2, server.config, data);
    const again = [...back.profiles.values()][0];
    assert.equal(again.bagExtra, 10);
    assert.equal(again.slots.length, before + 10);
    assert.equal(again.slots[again.slots.length - 1]?.id, 'bandage');
    assert.equal(back.stashExtra, 6);
  });

  it('현상금 의뢰: 다 채워야 보고, 한 번만 받는다 · 뒤지기도 센다', async () => {
    const server = start(12, { startSol: 0 });
    const { c, w } = await join(server);
    const room = roomOf(server);
    const me = [...room.players.values()][0];
    const b = w.hunter.bounties[0];
    assert.equal((await ask(c, { t: 'hunter_claim', b: b.id })).code, 'bounty_not_done');
    me.profile.hunter.bprog[b.id] = b.n;
    const ok = await ask(c, { t: 'hunter_claim', b: b.id });
    assert.deepEqual({ reward: ok.reward, pts: ok.pts }, { reward: b.reward, pts: b.pts });
    assert.equal(me.profile.sol, b.reward);
    assert.equal((await ask(c, { t: 'hunter_claim', b: b.id })).code, 'already_looted');
    // 빈집 냉장고 뒤지기 → loot 의뢰가 있으면 1 오른다.
    // 위에서 보고한 의뢰가 마침 '빈집 수색'이면 (방 코드에 따라) 더는 세지 않는다 — 다른 것만 본다.
    const loot = w.hunter.bounties.find((x) => x.kind === 'loot' && x.id !== b.id);
    const fridge = S.containers.get('h01_2');
    await moveTo(c, { x: fridge.x, z: fridge.z + 0.8 });
    c.send({ t: 'loot', c: 'h01_2', rid: 'lt-1' });
    await c.next((m) => m.t === 'looted', 2000);
    if (loot) await c.next((m) => m.t === 'hunter' && m.bounties.find((x) => x.id === loot.id)?.got === 1, 5000);
  });

  it('길드: 하나가 만들고 다른 하나가 가입, 함께 있으면 처치 점수가 늘고 길드 점수가 쌓인다 (저장된다)', async () => {
    const server = start(23, { startItems: 'pipe_spear:1' });
    const { c: a, w } = await join(server);
    const { c: b } = await join(server, w.code);
    assert.equal((await ask(a, { t: 'guild_create', name: 'x' })).code, 'bad_guild_name');
    const made = await ask(a, { t: 'guild_create', name: '새벽길드' });
    assert.equal(made.name, '새벽길드');
    const g1 = await b.next((m) => m.t === 'guild' && m.op === 'create', 2000);
    assert.equal(g1.g.members.length, 1);
    assert.equal((await ask(b, { t: 'guild_create', name: '다른길드' })).code, 'guild_exists');
    await ask(b, { t: 'guild_join' });
    const g2 = await a.next((m) => m.t === 'guild' && m.op === 'join', 2000);
    assert.equal(g2.g.members.length, 2);
    // 함께 사냥.
    await moveTo(a, spot);
    await moveTo(b, { x: spot.x + 3, z: spot.z });
    const room = roomOf(server);
    const pa = [...room.players.values()][0];
    pa.profile.held = pa.slots.findIndex((x) => x?.id === 'pipe_spear');
    put(room, 'zh2', { x: spot.x + 1, z: spot.z }, 'bloated');
    await ask(a, { t: 'attack' });
    const res = await a.next((m) => m.t === 'hunter_result' && m.kind === 'kill', 2000);
    assert.equal(res.pts, Math.round(H.kill.points.bloated * H.kill.party_mult));
    assert.equal(room.guild.pts, res.pts);
    assert.equal(room.toSave().world.guild.name, '새벽길드');
    await ask(b, { t: 'guild_leave' });
    assert.equal(room.guild.members.length, 1);
  });
});
