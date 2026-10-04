import { randomBytes, randomInt } from 'node:crypto';
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH } from './protocol.js';
import { spawnPoints } from './config.js';

export class Player {
  constructor(id, token, spawn) {
    this.id = id;
    this.token = token;
    this.ws = null; // 오프라인이면 null
    this.x = spawn.x;
    this.y = spawn.y;
    this.z = spawn.z;
    this.yaw = 0;
    this.vx = 0;
    this.vz = 0;
    this.lastMoveAt = 0; // performance.now() 기준 ms
    this.graceTimer = null;
  }

  get online() {
    return this.ws !== null;
  }

  toWire() {
    return {
      id: this.id,
      online: this.online,
      x: this.x,
      y: this.y,
      z: this.z,
      yaw: this.yaw,
      vx: this.vx,
      vz: this.vz,
    };
  }
}

export class Room {
  constructor(code, maxPlayers) {
    this.code = code;
    this.maxPlayers = maxPlayers;
    this.players = new Map(); // id -> Player
    this.dirty = false;
  }

  freeSlot() {
    for (let id = 1; id <= this.maxPlayers; id++) {
      if (!this.players.has(id)) return id;
    }
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
  constructor(maxPlayers) {
    this.maxPlayers = maxPlayers;
    this.rooms = new Map(); // code -> Room
    this.tokens = new Map(); // token -> { room, player }
  }

  createRoom() {
    let code;
    do {
      code = Array.from({ length: ROOM_CODE_LENGTH }, () => ROOM_CODE_ALPHABET[randomInt(ROOM_CODE_ALPHABET.length)]).join('');
    } while (this.rooms.has(code));
    const room = new Room(code, this.maxPlayers);
    this.rooms.set(code, room);
    return room;
  }

  getRoom(code) {
    return this.rooms.get(String(code).toUpperCase()) ?? null;
  }

  addPlayer(room) {
    const id = room.freeSlot();
    if (id === null) return null;
    const token = randomBytes(16).toString('hex');
    const spawn = spawnPoints[(id - 1) % spawnPoints.length];
    const player = new Player(id, token, spawn);
    room.players.set(id, player);
    this.tokens.set(token, { room, player });
    return player;
  }

  findByToken(token) {
    return this.tokens.get(token) ?? null;
  }

  removePlayer(room, player) {
    clearTimeout(player.graceTimer);
    room.players.delete(player.id);
    this.tokens.delete(player.token);
    if (room.players.size === 0) this.rooms.delete(room.code);
  }
}
