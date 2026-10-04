import { randomBytes, randomInt } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH } from './protocol.js';
import { spawnPoints } from './config.js';
import { SAVE_SCHEMA_VERSION } from './persistence.js';
import { emptySlots, hasItem, sanitize } from './inventory.js';
import { sanitizeTrees } from './trees.js';
import { createNpcRuntime } from './npcs.js';
import { sanitizeQuests, sanitizeRelations } from './quests.js';
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

/** 한 사람(uid)의 저장되는 상태. 접속이 끊겨도 방 파일에 남는다. */
function newProfile(uid, slot, cfg) {
  const spawn = spawnPoints[(slot - 1) % spawnPoints.length];
  return {
    uid,
    slot,
    slots: ensureStarterTools(emptySlots(cfg), cfg),
    held: 0,
    sol: 0,
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
  };
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
    this.shopPoints = 0; // 상점 포인트 (마을 공용, 단계는 포인트로 정해진다)
    this.placed = new Map(); // 설치된 가구 (furniture.js)
    this.placedSeq = 0;
    // NPC 위치는 저장하지 않는다 (방을 다시 열면 집 앞에서 시작).
    this.npcs = createNpcRuntime(data.npcs, performance.now(), Math.random);
    this.npcsDirty = true;
    this.weather = null; // 마지막으로 알린 날씨
    this.day = null; // 마지막으로 처리한 날짜
    this.nextLightningAt = 0;
    this.dirty = false; // 위치 스냅샷 방송 필요
    this.saveDirty = false; // 파일 저장 필요
  }

  static fromSave(saved, maxPlayers, cfg, data) {
    const room = new Room(saved.code, maxPlayers, data, finite(saved.createdAt, Date.now()));
    const world = saved.world ?? {};
    room.stats.totalCatches = Math.max(0, Math.trunc(finite(world.totalCatches, 0)));
    for (const [id, n] of Object.entries(world.species ?? {})) {
      if (Number.isInteger(n) && n > 0) room.stats.species[id] = n;
    }
    if (Number.isInteger(world.weatherSeed)) room.weatherSeed = world.weatherSeed;
    room.trees = sanitizeTrees(world.trees, data.trees);
    room.shopPoints = Math.max(0, Math.trunc(finite(world.shopPoints, 0)));
    room.placed = sanitizePlaced(world.placed, data);
    room.placedSeq = Math.max(0, intOr(world.placedSeq, 0));
    for (const [uid, p] of Object.entries(saved.profiles ?? {})) {
      const slot = Number.isInteger(p?.slot) ? p.slot : 0;
      if (slot < 1 || slot > maxPlayers || [...room.profiles.values()].some((q) => q.slot === slot)) continue;
      const base = newProfile(uid, slot, cfg);
      // schema 1 은 물고기 목록(items), schema 2 부터는 칸 배열(slots).
      const slots = ensureStarterTools(sanitize(p.slots ?? p.items, cfg, data.isKnown, data.limitOf), cfg);
      const held = intOr(p.held, base.held);
      room.profiles.set(uid, {
        ...base,
        slots,
        held: held >= -1 && held < cfg.quickSlots ? held : base.held,
        sol: Math.max(0, Math.trunc(finite(p.sol, 0))),
        catches: Math.max(0, Math.trunc(finite(p.catches, 0))),
        x: finite(p.x, base.x),
        y: finite(p.y, base.y),
        z: finite(p.z, base.z),
        yaw: finite(p.yaw, 0),
        npcs: sanitizeRelations(p.npcs, data),
        quests: sanitizeQuests(p.quests, data),
        questSeq: Math.max(0, intOr(p.questSeq, 0)),
        lastQuestDay: intOr(p.lastQuestDay, null),
        outfit: sanitizeOutfit(p.outfit, data),
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
    for (const [id, st] of this.trees) trees[id] = { ...st };
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
      },
      profiles,
    };
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
      profile = newProfile(uid, slot, this.cfg);
      room.profiles.set(uid, profile);
    }
    const token = randomBytes(16).toString('hex');
    const player = new Player(profile, token);
    room.players.set(player.id, player);
    this.tokens.set(token, { room, player });
    room.saveDirty = true;
    return { player, existing: false };
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
