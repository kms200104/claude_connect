import { performance } from 'node:perf_hooks';
import { WebSocketServer } from 'ws';
import { defaultConfig } from './config.js';
import { CloseCode, ErrorCode, PROTOCOL_VERSION } from './protocol.js';
import { RoomManager } from './rooms.js';
import { RoomStore } from './persistence.js';
import { loadGameData } from './gamedata.js';
import { createFishing } from './fishing.js';
import { removeItem, toWire as inventoryToWire } from './inventory.js';

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const UID_RE = /^[A-Za-z0-9_-]{8,64}$/;

/**
 * 서버 권위 원칙: 클라이언트가 보내는 건 항상 "요청"이다.
 * 위치는 속도 상한·경계 검사를 통과한 값만 반영하고, 어긋나면 서버 값으로 되돌리라고(correct) 알려 준다.
 */
export function createServer(overrides = {}) {
  const cfg = { ...defaultConfig, ...overrides };
  const store = overrides.store ?? new RoomStore(cfg.saveDir);
  const rooms = new RoomManager(cfg, store);
  const data = loadGameData(cfg.dataDir);
  const wss = new WebSocketServer({ port: cfg.port, maxPayload: cfg.maxMessageBytes });
  const now = () => performance.now();

  const send = (ws, message) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
  };
  const sendError = (ws, code, msg = '') => send(ws, { t: 'error', code, msg });
  const sendTo = (player, message) => player.ws && send(player.ws, message);
  const roomOf = (player) => [...rooms.rooms.values()].find((r) => r.players.get(player.id) === player);

  const fishing = createFishing({
    cfg,
    data,
    random: overrides.random,
    notify: sendTo,
    onFishingChanged: (player) => {
      const room = roomOf(player);
      if (room) room.dirty = true; // 스냅샷에 fishing 플래그를 실어 보낸다
    },
    onInventoryChanged: (player, fishId) => {
      const room = roomOf(player);
      sendTo(player, { t: 'inventory', ...inventoryToWire(player.items, cfg) });
      if (!room) return;
      room.stats.totalCatches += 1;
      room.stats.species[fishId] = (room.stats.species[fishId] ?? 0) + 1;
      rooms.save(room); // 인벤토리 변경은 바로 저장
    },
  });

  function detach(ctx, { startGrace }) {
    const { room, player } = ctx;
    if (!room || !player || player.ws !== ctx.ws) return;
    player.ws = null;
    fishing.drop(player);
    room.broadcast({ t: 'peer_status', id: player.id, online: false });
    room.saveDirty = true;
    if (!startGrace) return;
    player.graceTimer = setTimeout(() => {
      rooms.removePlayer(room, player);
      room.broadcast({ t: 'peer_left', id: player.id });
    }, cfg.reconnectGraceMs);
    player.graceTimer.unref?.();
  }

  function bind(ctx, room, player, resumed) {
    clearTimeout(player.graceTimer);
    if (player.ws && player.ws !== ctx.ws) {
      // 서버가 아직 끊김을 모르는 낡은 연결을 새 연결로 교체.
      const old = player.ws;
      player.ws = null;
      fishing.drop(player);
      old.close(CloseCode.replaced, 'replaced');
    }
    ctx.room = room;
    ctx.player = player;
    player.ws = ctx.ws;
    player.lastMoveAt = now();
    send(ctx.ws, {
      t: 'welcome',
      v: PROTOCOL_VERSION,
      id: player.id,
      token: player.token,
      code: room.code,
      resumed,
      st: now(),
      players: [...room.players.values()].map((p) => p.toWire()),
      inv: inventoryToWire(player.items, cfg),
    });
    room.broadcast(resumed ? { t: 'peer_status', id: player.id, online: true } : { t: 'peer_joined', p: player.toWire() }, player.id);
    room.dirty = true;
    rooms.save(room);
  }

  function checkVersion(ctx, msg) {
    if (msg.v !== PROTOCOL_VERSION) {
      sendError(ctx.ws, ErrorCode.badVersion, `server protocol ${PROTOCOL_VERSION}`);
      return false;
    }
    return true;
  }

  function validUid(ctx, msg) {
    if (typeof msg.uid === 'string' && UID_RE.test(msg.uid)) return true;
    sendError(ctx.ws, ErrorCode.badMessage, 'uid');
    return false;
  }

  /** 낚시·인벤토리 요청. 결과는 항상 서버가 확정해서 알린다. */
  function handleAction(ctx, msg) {
    const { player, room } = ctx;
    if (!player) return sendError(ctx.ws, ErrorCode.notInRoom);
    const fail = (code) => send(ctx.ws, { t: 'error', code, rid: msg.rid ?? null });
    switch (msg.t) {
      case 'fish_cast': {
        if (!player.acceptRid(msg.rid)) return; // 중복 요청 무시
        const err = fishing.cast(player, msg.rid, msg.spot);
        if (err) fail(err);
        return;
      }
      case 'fish_hook': {
        const err = fishing.hook(player, msg.rid, msg.reaction);
        if (err) fail(err);
        return;
      }
      case 'fish_cancel':
        return fishing.cancel(player);
      case 'inv_discard': {
        if (!player.acceptRid(msg.rid)) return;
        if (typeof msg.id !== 'string' || !data.fish.has(msg.id)) return fail(ErrorCode.badItem);
        const n = msg.n === undefined ? 1 : msg.n;
        if (!removeItem(player.items, msg.id, n)) return fail(ErrorCode.badItem);
        send(ctx.ws, { t: 'inventory', ...inventoryToWire(player.items, cfg) });
        rooms.save(room);
        return;
      }
    }
  }

  function handleMove(ctx, msg) {
    const { player, room } = ctx;
    if (!player) return sendError(ctx.ws, ErrorCode.notInRoom);
    if (![msg.x, msg.y, msg.z, msg.yaw].every(isNum)) return sendError(ctx.ws, ErrorCode.badMessage, 'move');

    const t = now();
    const dt = Math.min(Math.max((t - player.lastMoveAt) / 1000, 0.01), 1.0);
    player.lastMoveAt = t;

    let tx = Math.min(Math.max(msg.x, -cfg.worldHalfExtent), cfg.worldHalfExtent);
    let tz = Math.min(Math.max(msg.z, -cfg.worldHalfExtent), cfg.worldHalfExtent);
    const ty = Math.min(Math.max(msg.y, cfg.minY), cfg.maxY);

    const dx = tx - player.x;
    const dz = tz - player.z;
    const dist = Math.hypot(dx, dz);
    const allowed = cfg.maxSpeed * cfg.speedTolerance * dt + cfg.moveSlackMeters;
    let corrected = tx !== msg.x || tz !== msg.z || ty !== msg.y;
    if (dist > allowed) {
      const k = allowed / dist;
      tx = player.x + dx * k;
      tz = player.z + dz * k;
      corrected = true;
    }

    player.x = tx;
    player.y = ty;
    player.z = tz;
    player.yaw = msg.yaw;
    const vx = isNum(msg.vx) ? msg.vx : 0;
    const vz = isNum(msg.vz) ? msg.vz : 0;
    const speed = Math.hypot(vx, vz);
    const cap = cfg.maxSpeed * cfg.speedTolerance;
    const vk = speed > cap ? cap / speed : 1;
    player.vx = vx * vk;
    player.vz = vz * vk;
    room.dirty = true;
    room.saveDirty = true;
    fishing.onMove(player);

    if (corrected) send(ctx.ws, { t: 'correct', x: player.x, y: player.y, z: player.z });
  }

  function handleMessage(ctx, msg) {
    switch (msg.t) {
      case 'ping':
        return send(ctx.ws, { t: 'pong', c: msg.c, s: now() });
      case 'create': {
        if (!checkVersion(ctx, msg)) return;
        if (ctx.player) return sendError(ctx.ws, ErrorCode.alreadyInRoom);
        if (!validUid(ctx, msg)) return;
        const room = rooms.createRoom();
        const { player } = rooms.addPlayer(room, msg.uid);
        return bind(ctx, room, player, false);
      }
      case 'join': {
        if (!checkVersion(ctx, msg)) return;
        if (ctx.player) return sendError(ctx.ws, ErrorCode.alreadyInRoom);
        if (!validUid(ctx, msg)) return;
        if (typeof msg.code !== 'string') return sendError(ctx.ws, ErrorCode.badMessage, 'code');
        const room = rooms.getRoom(msg.code);
        if (!room) return sendError(ctx.ws, ErrorCode.roomNotFound);
        const added = rooms.addPlayer(room, msg.uid);
        if (!added) return sendError(ctx.ws, ErrorCode.roomFull);
        // 같은 uid가 이미 방에 있으면(다른 기기/재접속) 그 자리를 이어받는다.
        return bind(ctx, room, added.player, added.existing);
      }
      case 'resume': {
        if (!checkVersion(ctx, msg)) return;
        if (ctx.player) return sendError(ctx.ws, ErrorCode.alreadyInRoom);
        const found = typeof msg.token === 'string' ? rooms.findByToken(msg.token) : null;
        if (!found) return sendError(ctx.ws, ErrorCode.resumeFailed);
        return bind(ctx, found.room, found.player, true);
      }
      case 'move':
        return handleMove(ctx, msg);
      case 'fish_cast':
      case 'fish_hook':
      case 'fish_cancel':
      case 'inv_discard':
        return handleAction(ctx, msg);
      default:
        return sendError(ctx.ws, ErrorCode.badMessage, 'unknown type');
    }
  }

  wss.on('connection', (ws) => {
    const ctx = { ws, room: null, player: null, alive: true, tokens: cfg.rateLimitBurst, refilledAt: now(), overLimit: 0, lastRateErrorAt: -Infinity };
    ws.on('pong', () => {
      ctx.alive = true;
    });
    ws.on('message', (data, isBinary) => {
      // 초당 요청 제한 (토큰 버킷)
      const t = now();
      ctx.tokens = Math.min(cfg.rateLimitBurst, ctx.tokens + ((t - ctx.refilledAt) / 1000) * cfg.rateLimitPerSec);
      ctx.refilledAt = t;
      if (ctx.tokens < 1) {
        ctx.overLimit += 1;
        if (t - ctx.lastRateErrorAt > 1000) {
          ctx.lastRateErrorAt = t;
          sendError(ws, ErrorCode.rateLimited);
        }
        if (ctx.overLimit > cfg.rateLimitKickAfter) ws.close(CloseCode.rateLimited, 'rate limited');
        return;
      }
      ctx.tokens -= 1;

      let msg;
      try {
        if (isBinary) throw new Error('binary');
        msg = JSON.parse(data.toString());
      } catch {
        return sendError(ws, ErrorCode.badMessage, 'json');
      }
      if (typeof msg !== 'object' || msg === null || typeof msg.t !== 'string') return sendError(ws, ErrorCode.badMessage, 'shape');
      handleMessage(ctx, msg);
    });
    ws.on('close', () => detach(ctx, { startGrace: true }));
    ws.on('error', () => {});
    ws.ctx = ctx;
  });

  // 위치 스냅샷: 바뀐 방만 방송한다.
  const tick = setInterval(() => {
    for (const room of rooms.rooms.values()) {
      if (!room.dirty) continue;
      room.dirty = false;
      room.broadcast({
        t: 'snap',
        st: now(),
        p: [...room.players.values()].map((p) => ({ id: p.id, fishing: p.fishing !== null, x: p.x, y: p.y, z: p.z, yaw: p.yaw, vx: p.vx, vz: p.vz })),
      });
    }
  }, 1000 / cfg.tickRate);

  // 죽은 연결 정리 (모바일은 FIN 없이 끊기는 일이 흔하다).
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.ctx && !ws.ctx.alive) {
        ws.terminate();
        continue;
      }
      if (ws.ctx) ws.ctx.alive = false;
      ws.ping();
    }
  }, cfg.heartbeatMs);

  const autosave = setInterval(() => rooms.saveDirtyRooms(), cfg.saveIntervalMs);
  autosave.unref?.();

  return {
    wss,
    rooms,
    store,
    data,
    config: cfg,
    get port() {
      return wss.address().port;
    },
    /** 종료: 타이머를 멈추고, 메모리의 방을 전부 저장한 뒤 닫는다. */
    async close() {
      clearInterval(tick);
      clearInterval(heartbeat);
      clearInterval(autosave);
      for (const room of rooms.rooms.values()) {
        for (const p of room.players.values()) {
          clearTimeout(p.graceTimer);
          fishing.drop(p);
        }
      }
      await rooms.flushAll();
      for (const ws of wss.clients) ws.terminate();
      await new Promise((resolve) => wss.close(resolve));
    },
  };
}
