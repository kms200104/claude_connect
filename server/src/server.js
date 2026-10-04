import { performance } from 'node:perf_hooks';
import { WebSocketServer } from 'ws';
import { defaultConfig } from './config.js';
import { CloseCode, ErrorCode, PROTOCOL_VERSION } from './protocol.js';
import { RoomManager } from './rooms.js';

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

/**
 * 서버 권위 원칙: 클라이언트가 보내는 건 항상 "요청"이다.
 * 위치는 속도 상한·경계 검사를 통과한 값만 반영하고, 어긋나면 서버 값으로 되돌리라고(correct) 알려 준다.
 */
export function createServer(overrides = {}) {
  const cfg = { ...defaultConfig, ...overrides };
  const rooms = new RoomManager(cfg.maxPlayers);
  const wss = new WebSocketServer({ port: cfg.port, maxPayload: cfg.maxMessageBytes });
  const now = () => performance.now();

  const send = (ws, message) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
  };
  const sendError = (ws, code, msg = '') => send(ws, { t: 'error', code, msg });

  function detach(ctx, { startGrace }) {
    const { room, player } = ctx;
    if (!room || !player || player.ws !== ctx.ws) return;
    player.ws = null;
    room.broadcast({ t: 'peer_status', id: player.id, online: false });
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
    });
    room.broadcast(resumed ? { t: 'peer_status', id: player.id, online: true } : { t: 'peer_joined', p: player.toWire() }, player.id);
    room.dirty = true;
  }

  function checkVersion(ctx, msg) {
    if (msg.v !== PROTOCOL_VERSION) {
      sendError(ctx.ws, ErrorCode.badVersion, `server protocol ${PROTOCOL_VERSION}`);
      return false;
    }
    return true;
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

    if (corrected) send(ctx.ws, { t: 'correct', x: player.x, y: player.y, z: player.z });
  }

  function handleMessage(ctx, msg) {
    switch (msg.t) {
      case 'ping':
        return send(ctx.ws, { t: 'pong', c: msg.c, s: now() });
      case 'create': {
        if (!checkVersion(ctx, msg)) return;
        if (ctx.player) return sendError(ctx.ws, ErrorCode.alreadyInRoom);
        const room = rooms.createRoom();
        return bind(ctx, room, rooms.addPlayer(room), false);
      }
      case 'join': {
        if (!checkVersion(ctx, msg)) return;
        if (ctx.player) return sendError(ctx.ws, ErrorCode.alreadyInRoom);
        if (typeof msg.code !== 'string') return sendError(ctx.ws, ErrorCode.badMessage, 'code');
        const room = rooms.getRoom(msg.code);
        if (!room) return sendError(ctx.ws, ErrorCode.roomNotFound);
        const player = rooms.addPlayer(room);
        if (!player) return sendError(ctx.ws, ErrorCode.roomFull);
        return bind(ctx, room, player, false);
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
        p: [...room.players.values()].map((p) => ({ id: p.id, x: p.x, y: p.y, z: p.z, yaw: p.yaw, vx: p.vx, vz: p.vz })),
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

  return {
    wss,
    rooms,
    config: cfg,
    get port() {
      return wss.address().port;
    },
    close() {
      clearInterval(tick);
      clearInterval(heartbeat);
      for (const room of rooms.rooms.values()) for (const p of room.players.values()) clearTimeout(p.graceTimer);
      for (const ws of wss.clients) ws.terminate();
      return new Promise((resolve) => wss.close(resolve));
    },
  };
}
