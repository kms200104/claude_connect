import { randomBytes, randomInt } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH } from './protocol.js';
import { spawnPoints } from './config.js';
import { SAVE_SCHEMA_VERSION } from './persistence.js';
import { addItem, emptySlots, hasItem, sanitize } from './inventory.js';
import { sanitizePlanted, sanitizeTrees } from './trees.js';
import { sanitizeFlowers } from './plants.js';
import { defaultFace, sanitizeFace } from './face.js';
import { sanitizeHoldings } from './market.js';
import { sanitizeHomes } from './realestate.js';
import { newCredit, sanitizeLoans } from './bank.js';
import { sanitizeRestaurant } from './restaurant.js';
import { createNpcRuntime } from './npcs.js';
import { relationOf, sanitizeQuests, sanitizeRelations } from './quests.js';
import { sanitizePlaced } from './furniture.js';

const finite = (v, fallback) => (typeof v === 'number' && Number.isFinite(v) ? v : fallback);
const intOr = (v, fallback) => (Number.isInteger(v) ? v : fallback);

// 처음 들어온 사람은 퀵슬롯 1번에 낚싯대, 2번에 도끼를 들고 시작한다(1번을 손에 든 상태).
const STARTER_TOOLS = [
  ['rod', 0],
  ['axe', 1],
];

/** 도구가 없으면 원하는 칸(비어 있으면) 또는 빈 칸에 넣는다. 도구는 버릴 수 없으므로 옛 저장 파일에만 해당. */
function ensureStarterTools(slots, cfg) {
  for (const [id, preferred] of STARTER_TOOLS) {
    if (hasItem(slots, id)) continue;
    let index = preferred < cfg.quickSlots && slots[preferred] === null ? preferred : slots.findIndex((s) => s === null);
    if (index < 0) index = slots.length - 1; // 꽉 찬 옛 가방: 마지막 칸을 비워서라도 도구는 준다
    slots[index] = { id, n: 1 };
  }
  return slots;
}

/** schema 4 → 5 화폐 단위 배율. */
export const MONEY_SCALE_V5 = 100;

/** 한 사람(uid)의 저장되는 상태. 접속이 끊겨도 방 파일에 남는다. */
function newProfile(uid, slot, cfg, data) {
  const spawn = spawnPoints[(slot - 1) % spawnPoints.length];
  return {
    uid,
    slot,
    slots: ensureStarterTools(emptySlots(cfg), cfg),
    held: 0,
    sol: cfg.startSol ?? 0,
    catches: 0,
    x: spawn.x,
    y: spawn.y,
    z: spawn.z,
    yaw: 0,
    npcs: {},
    quests: [],
    questSeq: 0,
    lastQuestDay: null,
    outfit: { hat: '', top: '' }, // 입은 옷 (아이템 id). 입은 옷은 인벤토리 칸을 차지하지 않는다
    emotes: { known: ['hello'], quick: ['hello'] }, // 배운 감정표현과 감정표현 퀵슬롯
    face: data ? defaultFace(data.face, slot) : {}, // 거울에서 고른 얼굴 (눈·코·입·피부·머리)
    stocks: {}, // 가진 주식 { 종목: { q, cost } }
    trades: [], // 최근 거래 (보기용)
    loans: [], // 대출 [{ id, kind, principal, rate, unit, since }]
    loanSeq: 0,
    credit: { paid: 0, missed: 0, weeks: 0 }, // 이자 낸 기록 (신용점수)
    income: { amount: 0, history: [] }, // 이번 주 번 돈과 지난 주들 (대출 한도·신용)
  };
}

/** 배운 감정표현 (모르는 id 는 버리고, 기본 감정표현은 항상 안다) 과 퀵슬롯. */
function sanitizeEmotes(raw, data, cfg) {
  const base = data.emotes.default ?? ['hello'];
  const known = [...new Set([...base, ...(Array.isArray(raw?.known) ? raw.known : [])])].filter((e) => data.emoteIds.has(e));
  const quick = (Array.isArray(raw?.quick) ? raw.quick : base).filter((e) => known.includes(e)).slice(0, data.emotes.quick_slots ?? 4);
  return { known, quick: quick.length > 0 || Array.isArray(raw?.quick) ? quick : [...base] };
}

/** 박물관 (마을 공용): 기증한 물고기 id → 기증한 사람 자리 번호, 받은 기념품 단계. */
function sanitizeMuseum(raw, data) {
  const out = { fish: {}, claimed: [] };
  if (!raw || typeof raw !== 'object') return out;
  for (const [id, by] of Object.entries(raw.fish ?? {})) if (data.isFish(id)) out.fish[id] = Number.isInteger(by) ? by : 0;
  if (Array.isArray(raw.claimed)) out.claimed = raw.claimed.filter((n) => data.museum.milestones.some((m) => m.count === n));
  return out;
}

function sanitizeOutfit(raw, data) {
  const out = { hat: '', top: '' };
  if (!raw || typeof raw !== 'object') return out;
  for (const part of ['hat', 'top']) {
    const id = raw[part];
    if (typeof id === 'string' && data.items.get(id)?.kind === 'clothing' && data.items.get(id).wear === part) out[part] = id;
  }
  return out;
}

/** 접속 중(또는 재접속 유예 중)인 플레이어. 영속 데이터는 profile 에 있다. */
export class Player {
  constructor(profile, token) {
    this.profile = profile;
    this.id = profile.slot;
    this.token = token;
    this.ws = null; // 오프라인이면 null
    this.x = profile.x;
    this.y = profile.y;
    this.z = profile.z;
    this.yaw = profile.yaw;
    this.vx = 0;
    this.vz = 0;
    this.lastMoveAt = 0; // performance.now() 기준 ms
    this.lastChopAt = -Infinity;
    this.doorAt = -Infinity; // 상점 문을 지난 시각
    this.lastEmoteAt = -Infinity; // 감정표현 간격
    this.lastMotionAt = -Infinity; // 몸짓(브레이크) 간격
    this.graceTimer = null;
    this.fishing = null; // 낚시 세션 (fishing.js)
    this.talkingTo = null; // 대화 중인 NPC id
    this.offer = null; // 대화 중 받은(아직 수락 안 한) 부탁
    this.handledRids = new Set(); // 이미 처리한 요청 ID (중복 방지)
  }

  get uid() {
    return this.profile.uid;
  }

  get slots() {
    return this.profile.slots;
  }

  get online() {
    return this.ws !== null;
  }

  /** 손에 든 아이템 id (퀵슬롯이 비었거나 아무것도 안 들었으면 ''). */
  get heldItem() {
    const s = this.profile.held >= 0 ? this.profile.slots[this.profile.held] : null;
    return s ? s.id : '';
  }

  syncProfile() {
    Object.assign(this.profile, { x: this.x, y: this.y, z: this.z, yaw: this.yaw });
  }

  toWire() {
    return {
      id: this.id,
      online: this.online,
      fishing: this.fishing !== null,
      held: this.heldItem,
      hat: this.profile.outfit.hat,
      top: this.profile.outfit.top,
      face: { ...this.profile.face },
      x: this.x,
      y: this.y,
      z: this.z,
      yaw: this.yaw,
      vx: this.vx,
      vz: this.vz,
    };
  }

  /** 같은 요청 ID를 두 번 처리하지 않기 위한 기록. 새 ID면 true. */
  acceptRid(rid) {
    if (typeof rid !== 'string' && !Number.isInteger(rid)) return false;
    const key = String(rid).slice(0, 40);
    if (this.handledRids.has(key)) return false;
    this.handledRids.add(key);
    if (this.handledRids.size > 64) this.handledRids.delete(this.handledRids.values().next().value);
    return true;
  }
}

export class Room {
  constructor(code, maxPlayers, data, createdAt = Date.now()) {
    this.code = code;
    this.maxPlayers = maxPlayers;
    this.players = new Map(); // slot -> Player (메모리에 있는 사람)
    this.profiles = new Map(); // uid -> profile (저장되는 사람 전체)
    this.createdAt = createdAt;
    this.stats = { totalCatches: 0, species: {} }; // 월드(마을) 공용 상태
    this.weatherSeed = randomInt(0x7fffffff);
    this.trees = sanitizeTrees(null, data.trees);
    // 씨앗을 심어 생긴 나무 (id → { id, kind, x, z, by, planted }). 상태는 this.trees 에 같은 id 로.
    this.plantedTrees = new Map();
    this.plantSeq = 0;
    // 심은 꽃 (plants.js).
    this.flowers = new Map();
    this.flowerSeq = 0;
    this.museum = { fish: {}, claimed: [] };
    this.shopPoints = 0; // 상점 포인트 (마을 공용, 단계는 포인트로 정해진다)
    this.placed = new Map(); // 설치된 가구 (furniture.js)
    this.placedSeq = 0;
    // NPC 위치는 저장하지 않는다 (방을 다시 열면 집 앞에서 시작).
    this.npcs = createNpcRuntime(data.npcs, performance.now(), Math.random);
    this.npcsDirty = true;
    this.weather = null; // 마지막으로 알린 날씨
    this.day = null; // 마지막으로 처리한 날짜
    this.nextLightningAt = 0;
    // 이벤트 (events.js): 오늘의 계획, 마지막으로 알린 목록, 바닥에 떨어진 선물·별 조각 (저장하지 않음).
    this.plan = null;
    this.eventSig = '';
    this.drops = new Map();
    this.dropSeq = 0;
    this.nextDropAt = { gift: 0, star: 0, forage: 0 };
    // 경제 (마을 공용): 아파트 소유 · 집값 지수 · 기준금리 · 마지막으로 이자를 매긴 주
    this.homes = {}; // 호수 → { owner: uid, price, day }
    this.aptIndex = data.realestate?.index?.start ?? 1;
    this.baseRate = data.bank?.base_rate ?? 0.03;
    this.week = null;
    // 식당: 별점 기록 · 단골 (저장) / 지금 영업 (저장 안 함)
    this.restaurant = sanitizeRestaurant(null, data.recipes ?? []);
    this.shift = null;
    this.dirty = false; // 위치 스냅샷 방송 필요
    this.saveDirty = false; // 파일 저장 필요
  }

  static fromSave(saved, maxPlayers, cfg, data) {
    const room = new Room(saved.code, maxPlayers, data, finite(saved.createdAt, Date.now()));
    const world = saved.world ?? {};
    // schema 5: 화폐를 현실 단위로 (모든 값 ×100). 그 전 저장은 솔·상점 포인트·부탁 보상을 100배로 옮긴다.
    const money = Number.isInteger(saved.schema) && saved.schema < 5 ? MONEY_SCALE_V5 : 1;
    room.stats.totalCatches = Math.max(0, Math.trunc(finite(world.totalCatches, 0)));
    for (const [id, n] of Object.entries(world.species ?? {})) {
      if (Number.isInteger(n) && n > 0) room.stats.species[id] = n;
    }
    if (Number.isInteger(world.weatherSeed)) room.weatherSeed = world.weatherSeed;
    room.trees = sanitizeTrees(world.trees, data.trees);
    const planted = sanitizePlanted(world.planted, data.treeKinds, data.plants.max_planted_trees);
    room.plantedTrees = planted.defs;
    for (const [id, st] of planted.states) room.trees.set(id, st);
    room.plantSeq = Math.max(0, intOr(world.plantSeq, 0));
    room.flowers = sanitizeFlowers(world.flowers, data);
    room.flowerSeq = Math.max(0, intOr(world.flowerSeq, 0));
    room.museum = sanitizeMuseum(world.museum, data);
    room.shopPoints = Math.max(0, Math.trunc(finite(world.shopPoints, 0) * money));
    room.placed = sanitizePlaced(world.placed, data);
    room.placedSeq = Math.max(0, intOr(world.placedSeq, 0));
    room.homes = sanitizeHomes(world.homes, data.units);
    if (finite(world.aptIndex, 0) > 0) room.aptIndex = world.aptIndex;
    if (finite(world.baseRate, 0) > 0) room.baseRate = world.baseRate;
    room.week = intOr(world.week, null);
    room.restaurant = sanitizeRestaurant(world.restaurant, data.recipes);
    for (const [uid, p] of Object.entries(saved.profiles ?? {})) {
      const slot = Number.isInteger(p?.slot) ? p.slot : 0;
      if (slot < 1 || slot > maxPlayers || [...room.profiles.values()].some((q) => q.slot === slot)) continue;
      const base = newProfile(uid, slot, cfg, data);
      // schema 1 은 물고기 목록(items), schema 2 부터는 칸 배열(slots).
      const slots = ensureStarterTools(sanitize(p.slots ?? p.items, cfg, data.isKnown, data.limitOf), cfg);
      const held = intOr(p.held, base.held);
      room.profiles.set(uid, {
        ...base,
        slots,
        held: held >= -1 && held < cfg.quickSlots ? held : base.held,
        sol: Math.max(0, Math.trunc(finite(p.sol, 0) * money)),
        catches: Math.max(0, Math.trunc(finite(p.catches, 0))),
        x: finite(p.x, base.x),
        y: finite(p.y, base.y),
        z: finite(p.z, base.z),
        yaw: finite(p.yaw, 0),
        npcs: sanitizeRelations(p.npcs, data),
        quests: sanitizeQuests(p.quests, data).map((q) => ({ ...q, reward: q.reward * money })),
        questSeq: Math.max(0, intOr(p.questSeq, 0)),
        lastQuestDay: intOr(p.lastQuestDay, null),
        outfit: sanitizeOutfit(p.outfit, data),
        emotes: sanitizeEmotes(p.emotes, data, cfg),
        face: sanitizeFace(p.face, data.face, base.slot),
        stocks: sanitizeHoldings(p.stocks, data.market),
        trades: Array.isArray(p.trades) ? p.trades.slice(-20) : [],
        loans: sanitizeLoans(p.loans),
        loanSeq: Math.max(0, intOr(p.loanSeq, 0)),
        credit: { ...newCredit(data.bank), ...(p.credit && typeof p.credit === 'object' ? { paid: intOr(p.credit.paid, 0), missed: intOr(p.credit.missed, 0), weeks: intOr(p.credit.weeks, 0) } : {}) },
        income: { amount: Math.max(0, Math.trunc(finite(p.income?.amount, 0))), history: Array.isArray(p.income?.history) ? p.income.history.filter(Number.isFinite).slice(-8) : [] },
      });
    }
    return room;
  }

  toSave() {
    const profiles = {};
    for (const [uid, profile] of this.profiles) {
      const live = this.players.get(profile.slot);
      if (live && live.uid === uid) live.syncProfile();
      profiles[uid] = structuredClone(profile);
    }
    const trees = {};
    for (const [id, st] of this.trees) if (!this.plantedTrees.has(id)) trees[id] = { ...st };
    const planted = [...this.plantedTrees.values()].map((d) => ({ id: d.id, kind: d.kind, x: d.x, z: d.z, by: d.by, st: { ...this.trees.get(d.id) } }));
    return {
      schema: SAVE_SCHEMA_VERSION,
      code: this.code,
      createdAt: this.createdAt,
      savedAt: Date.now(),
      world: {
        totalCatches: this.stats.totalCatches,
        species: { ...this.stats.species },
        weatherSeed: this.weatherSeed,
        trees,
        shopPoints: this.shopPoints,
        placed: [...this.placed.values()].map((f) => ({ ...f })),
        placedSeq: this.placedSeq,
        planted,
        plantSeq: this.plantSeq,
        flowers: [...this.flowers.values()].map((f) => ({ ...f })),
        flowerSeq: this.flowerSeq,
        museum: structuredClone(this.museum),
        homes: structuredClone(this.homes),
        aptIndex: this.aptIndex,
        baseRate: this.baseRate,
        week: this.week,
        restaurant: structuredClone(this.restaurant),
      },
      profiles,
    };
  }

  /** 나무 정의 (데이터 나무 또는 심은 나무). */
  treeDef(id, data) {
    return data.trees.get(id) ?? this.plantedTrees.get(id) ?? null;
  }

  /** 모든 나무 자리 (설치·심기 간격 검사용). */
  allTreeSpots(data) {
    return [...data.trees.values(), ...this.plantedTrees.values()];
  }

  /** 저장된 사람 uid → 자리 번호 (없으면 0). */
  slotOfUid(uid) {
    return this.profiles.get(uid)?.slot ?? 0;
  }

  freeSlot() {
    const used = new Set([...this.profiles.values()].map((p) => p.slot));
    for (let id = 1; id <= this.maxPlayers; id++) if (!used.has(id)) return id;
    return null;
  }

  broadcast(message, exceptId = null) {
    const text = JSON.stringify(message);
    for (const p of this.players.values()) {
      if (p.id !== exceptId && p.ws) p.ws.send(text);
    }
  }
}

export class RoomManager {
  constructor(cfg, store, data) {
    this.cfg = cfg;
    this.store = store;
    this.data = data;
    this.rooms = new Map(); // code -> Room (메모리에 올라온 방)
    this.tokens = new Map(); // token -> { room, player }
  }

  createRoom() {
    let code;
    do {
      code = Array.from({ length: ROOM_CODE_LENGTH }, () => ROOM_CODE_ALPHABET[randomInt(ROOM_CODE_ALPHABET.length)]).join('');
    } while (this.rooms.has(code) || this.store.exists(code));
    const room = new Room(code, this.cfg.maxPlayers, this.data);
    this.rooms.set(code, room);
    return room;
  }

  /** 메모리에 없으면 저장된 파일에서 불러온다. */
  getRoom(rawCode) {
    const code = String(rawCode).toUpperCase();
    const live = this.rooms.get(code);
    if (live) return live;
    const saved = this.store.load(code);
    if (!saved) return null;
    const room = Room.fromSave(saved, this.cfg.maxPlayers, this.cfg, this.data);
    this.rooms.set(code, room);
    return room;
  }

  /** uid가 이 방에서 쓰던 자리가 있으면 그대로, 없으면 빈 자리를 새로 준다. 자리가 없으면 null. */
  addPlayer(room, uid) {
    let profile = room.profiles.get(uid);
    if (profile) {
      const existing = room.players.get(profile.slot);
      if (existing) return { player: existing, existing: true };
    } else {
      const slot = room.freeSlot();
      if (slot === null) return null;
      profile = newProfile(uid, slot, this.cfg, this.data);
      this.applyStarter(profile);
      room.profiles.set(uid, profile);
    }
    const token = randomBytes(16).toString('hex');
    const player = new Player(profile, token);
    room.players.set(player.id, player);
    this.tokens.set(token, { room, player });
    room.saveDirty = true;
    return { player, existing: false };
  }

  /** 시연·테스트용 시작 선물 (START_ITEMS) 과 주민 친밀도 (START_FRIENDSHIP). */
  applyStarter(profile) {
    for (const entry of String(this.cfg.startItems ?? '').split(',')) {
      const [id, n] = entry.trim().split(':');
      if (id && this.data.isKnown(id)) addItem(profile.slots, id, Math.max(1, parseInt(n ?? '1', 10) || 1), this.cfg, this.data.limitOf);
    }
    if (this.cfg.startFriendship > 0) {
      for (const id of this.data.npcs.keys()) relationOf(profile, id).f = Math.min(100, this.cfg.startFriendship);
    }
  }

  findByToken(token) {
    return this.tokens.get(token) ?? null;
  }

  /** 유예 시간이 지나 자리를 비운다. 영속 데이터(profile)는 방 파일에 그대로 남는다. */
  removePlayer(room, player) {
    clearTimeout(player.graceTimer);
    player.syncProfile();
    room.players.delete(player.id);
    this.tokens.delete(player.token);
    room.saveDirty = true;
    if (room.players.size === 0) this.unload(room);
  }

  unload(room) {
    this.save(room);
    room.saveDirty = false;
    this.rooms.delete(room.code);
  }

  save(room) {
    room.saveDirty = false;
    return this.store.save(room.code, room.toSave());
  }

  saveDirtyRooms() {
    for (const room of this.rooms.values()) if (room.saveDirty) this.save(room);
  }

  async flushAll() {
    for (const room of this.rooms.values()) this.save(room);
    await this.store.idle();
  }
}
