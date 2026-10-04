import { randomBytes, randomInt } from 'node:crypto';
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH } from './protocol.js';
import { spawnPoints } from './config.js';
import { SAVE_SCHEMA_VERSION } from './persistence.js';
import { sanitize } from './inventory.js';

const finite = (v, fallback) => (typeof v === 'number' && Number.isFinite(v) ? v : fallback);

/** 한 사람(uid)의 저장되는 상태. 접속이 끊겨도 방 파일에 남는다. */
function newProfile(uid, slot) {
  const spawn = spawnPoints[(slot - 1) % spawnPoints.length];
  return { uid, slot, items: [], catches: 0, x: spawn.x, y: spawn.y, z: spawn.z, yaw: 0 };
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
    this.graceTimer = null;
    this.fishing = null; // 낚시 세션 (fishing.js)
    this.handledRids = new Set(); // 이미 처리한 요청 ID (중복 방지)
  }

  get uid() {
    return this.profile.uid;
  }

  get items() {
    return this.profile.items;
  }

  get online() {
    return this.ws !== null;
  }

  syncProfile() {
    Object.assign(this.profile, { x: this.x, y: this.y, z: this.z, yaw: this.yaw });
  }

  toWire() {
    return {
      id: this.id,
      online: this.online,
      fishing: this.fishing !== null,
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
  constructor(code, maxPlayers, createdAt = Date.now()) {
    this.code = code;
    this.maxPlayers = maxPlayers;
    this.players = new Map(); // slot -> Player (메모리에 있는 사람)
    this.profiles = new Map(); // uid -> profile (저장되는 사람 전체)
    this.createdAt = createdAt;
    this.stats = { totalCatches: 0, species: {} }; // 월드(마을) 공용 상태
    this.dirty = false; // 위치 스냅샷 방송 필요
    this.saveDirty = false; // 파일 저장 필요
  }

  static fromSave(data, maxPlayers, cfg) {
    const room = new Room(data.code, maxPlayers, finite(data.createdAt, Date.now()));
    const world = data.world ?? {};
    room.stats.totalCatches = Math.max(0, Math.trunc(finite(world.totalCatches, 0)));
    for (const [id, n] of Object.entries(world.species ?? {})) {
      if (Number.isInteger(n) && n > 0) room.stats.species[id] = n;
    }
    for (const [uid, p] of Object.entries(data.profiles ?? {})) {
      const slot = Number.isInteger(p?.slot) ? p.slot : 0;
      if (slot < 1 || slot > maxPlayers || [...room.profiles.values()].some((q) => q.slot === slot)) continue;
      const base = newProfile(uid, slot);
      room.profiles.set(uid, {
        ...base,
        items: sanitize(p.items, cfg),
        catches: Math.max(0, Math.trunc(finite(p.catches, 0))),
        x: finite(p.x, base.x),
        y: finite(p.y, base.y),
        z: finite(p.z, base.z),
        yaw: finite(p.yaw, 0),
      });
    }
    return room;
  }

  toSave() {
    const profiles = {};
    for (const [uid, profile] of this.profiles) {
      const live = this.players.get(profile.slot);
      if (live && live.uid === uid) live.syncProfile();
      profiles[uid] = { ...profile };
    }
    return {
      schema: SAVE_SCHEMA_VERSION,
      code: this.code,
      createdAt: this.createdAt,
      savedAt: Date.now(),
      world: { totalCatches: this.stats.totalCatches, species: { ...this.stats.species } },
      profiles,
    };
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
  constructor(cfg, store) {
    this.cfg = cfg;
    this.store = store;
    this.rooms = new Map(); // code -> Room (메모리에 올라온 방)
    this.tokens = new Map(); // token -> { room, player }
  }

  createRoom() {
    let code;
    do {
      code = Array.from({ length: ROOM_CODE_LENGTH }, () => ROOM_CODE_ALPHABET[randomInt(ROOM_CODE_ALPHABET.length)]).join('');
    } while (this.rooms.has(code) || this.store.exists(code));
    const room = new Room(code, this.cfg.maxPlayers);
    this.rooms.set(code, room);
    return room;
  }

  /** 메모리에 없으면 저장된 파일에서 불러온다. */
  getRoom(rawCode) {
    const code = String(rawCode).toUpperCase();
    const live = this.rooms.get(code);
    if (live) return live;
    const data = this.store.load(code);
    if (!data) return null;
    const room = Room.fromSave(data, this.cfg.maxPlayers, this.cfg);
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
      profile = newProfile(uid, slot);
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
