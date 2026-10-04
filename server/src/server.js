import { performance } from 'node:perf_hooks';
import { WebSocketServer } from 'ws';
import { defaultConfig } from './config.js';
import { CloseCode, ErrorCode, PROTOCOL_VERSION } from './protocol.js';
import { RoomManager } from './rooms.js';
import { RoomStore } from './persistence.js';
import { loadGameData, pickWeighted } from './gamedata.js';
import { createFishing } from './fishing.js';
import { addItem, canAdd, moveSlot, removeAt, removeWhere, toWire as inventoryToWire } from './inventory.js';
import { createClock, isWeather, timeBand, weatherAt } from './clock.js';
import { chopTree, refreshTree, treeWire, TreeStage } from './trees.js';
import { beginTalk, endTalk, npcWire, stepNpcs } from './npcs.js';
import { addFriendship, makeQuest, pruneExpired, questAccepts, questReady, questWire, relationOf, shouldOffer } from './quests.js';

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const UID_RE = /^[A-Za-z0-9_-]{8,64}$/;

/**
 * 서버 권위 원칙: 클라이언트가 보내는 건 항상 "요청"이다.
 * 위치는 속도 상한·경계 검사를 통과한 값만 반영하고, 어긋나면 서버 값으로 되돌리라고(correct) 알려 준다.
 * 시각·날씨·나무·주민·부탁은 전부 서버가 정하고 방 안의 모두에게 같은 값을 보낸다.
 */
export function createServer(overrides = {}) {
  const cfg = { ...defaultConfig, ...overrides };
  const data = loadGameData(cfg.dataDir, cfg);
  const store = overrides.store ?? new RoomStore(cfg.saveDir);
  const rooms = new RoomManager(cfg, store, data);
  const wss = new WebSocketServer({ port: cfg.port, maxPayload: cfg.maxMessageBytes });
  const now = () => performance.now();
  const random = overrides.random ?? Math.random;
  const clock = overrides.clock ?? createClock(cfg);

  const send = (ws, message) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
  };
  const sendError = (ws, code, msg = '') => send(ws, { t: 'error', code, msg });
  const sendTo = (player, message) => player.ws && send(player.ws, message);
  const roomOf = (player) => [...rooms.rooms.values()].find((r) => r.players.get(player.id) === player);

  const weatherOf = (room) => (isWeather(cfg.weatherForce) ? cfg.weatherForce : weatherAt(room.weatherSeed, clock.day(), clock.hour()));
  const environment = (room) => ({ hour: clock.hour(), weather: room ? weatherOf(room) : 'clear' });

  const sendInventory = (player) => sendTo(player, { t: 'inventory', ...inventoryToWire(player.slots, cfg, player.profile.held) });
  const profileWire = (player) => {
    const friends = {};
    for (const [id, rel] of Object.entries(player.profile.npcs)) friends[id] = rel.f;
    return { sol: player.profile.sol, quests: player.profile.quests.map((q) => questWire(q, player.slots, data)), friends };
  };
  const sendProfile = (player) => sendTo(player, { t: 'profile', ...profileWire(player) });
  const clockWire = () => ({ g: clock.gameMs(), s: cfg.clockScale, st: now() });

  const fishing = createFishing({
    cfg,
    data,
    random: overrides.random,
    notify: sendTo,
    heldItem: (player) => player.heldItem,
    environment: (player) => environment(roomOf(player)),
    onFishingChanged: (player) => {
      const room = roomOf(player);
      if (room) room.dirty = true; // 스냅샷에 fishing 플래그를 실어 보낸다
    },
    onInventoryChanged: (player, fishId) => {
      const room = roomOf(player);
      sendInventory(player);
      sendProfile(player); // 부탁 진행도(have)가 바뀐다
      if (!room) return;
      room.stats.totalCatches += 1;
      room.stats.species[fishId] = (room.stats.species[fishId] ?? 0) + 1;
      rooms.save(room); // 인벤토리 변경은 바로 저장
    },
  });

  // ---- 대화 ----

  function closeTalk(room, player, notify) {
    const npc = player.talkingTo !== null ? room.npcs.get(player.talkingTo) : null;
    if (npc && npc.talkingWith === player.id) endTalk(npc, now());
    if (npc && notify) sendTo(player, { t: 'talk_closed', npc: npc.id });
    player.talkingTo = null;
    player.offer = null;
    room.npcsDirty = true;
  }

  function detach(ctx, { startGrace }) {
    const { room, player } = ctx;
    if (!room || !player || player.ws !== ctx.ws) return;
    player.ws = null;
    fishing.drop(player);
    closeTalk(room, player, false);
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
      closeTalk(room, player, false);
      old.close(CloseCode.replaced, 'replaced');
    }
    ctx.room = room;
    ctx.player = player;
    player.ws = ctx.ws;
    player.lastMoveAt = now();
    advanceDay(room);
    send(ctx.ws, {
      t: 'welcome',
      v: PROTOCOL_VERSION,
      id: player.id,
      token: player.token,
      code: room.code,
      resumed,
      st: now(),
      players: [...room.players.values()].map((p) => p.toWire()),
      inv: inventoryToWire(player.slots, cfg, player.profile.held),
      prof: profileWire(player),
      clock: clockWire(),
      w: weatherOf(room),
      trees: [...room.trees].map(([id, st]) => treeWire(id, st)),
      npcs: [...room.npcs.values()].map(npcWire),
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

  /** 날짜가 바뀌었으면 나무를 자라게 하고 지난 부탁을 지운다. */
  function advanceDay(room) {
    const today = clock.day();
    if (room.day === today) return;
    room.day = today;
    for (const [id, st] of room.trees) {
      if (refreshTree(st, today)) room.broadcast({ t: 'tree', ...treeWire(id, st) });
    }
    for (const profile of room.profiles.values()) {
      const kept = pruneExpired(profile.quests, today);
      if (kept.length === profile.quests.length) continue;
      profile.quests = kept;
      const live = room.players.get(profile.slot);
      if (live && live.uid === profile.uid) sendProfile(live);
    }
    room.saveDirty = true;
  }

  // ---- 인벤토리 ----

  function handleInventory(ctx, msg, fail) {
    const { player, room } = ctx;
    switch (msg.t) {
      case 'equip': {
        const slot = msg.slot;
        if (!Number.isInteger(slot) || slot < -1 || slot >= cfg.quickSlots) return fail(ErrorCode.badItem);
        if (player.fishing) return fail(ErrorCode.alreadyFishing);
        player.profile.held = slot;
        sendInventory(player);
        room.dirty = true; // 손에 든 도구를 상대에게
        room.saveDirty = true;
        return;
      }
      case 'inv_move': {
        if (!player.acceptRid(msg.rid)) return;
        if (player.fishing) return fail(ErrorCode.alreadyFishing);
        if (!moveSlot(player.slots, msg.from, msg.to, data.limitOf)) return fail(ErrorCode.badItem);
        sendInventory(player);
        room.dirty = true;
        room.saveDirty = true; // 자리 바꾸기는 개수가 안 바뀌니 주기 저장으로 충분하다
        return;
      }
      case 'inv_discard': {
        if (!player.acceptRid(msg.rid)) return;
        const slot = player.slots[msg.slot];
        if (!Number.isInteger(msg.slot) || !slot) return fail(ErrorCode.badItem);
        if (data.isTool(slot.id)) return fail(ErrorCode.cantDiscard);
        const n = msg.n === undefined ? 1 : msg.n;
        if (!removeAt(player.slots, msg.slot, n)) return fail(ErrorCode.badItem);
        sendInventory(player);
        sendProfile(player);
        rooms.save(room);
        return;
      }
    }
  }

  // ---- 나무 베기 ----

  function handleChop(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (player.heldItem !== 'axe') return fail(ErrorCode.noTool);
    if (player.fishing) return fail(ErrorCode.alreadyFishing);
    const def = typeof msg.tree === 'string' ? data.trees.get(msg.tree) : null;
    if (!def || Math.hypot(player.x - def.x, player.z - def.z) > data.treeRules.chopRange) return fail(ErrorCode.notNearTree);
    const t = now();
    if (t - player.lastChopAt < cfg.chopCooldownMs) return fail(ErrorCode.tooFast);
    const state = room.trees.get(def.id);
    const today = clock.day();
    refreshTree(state, today);
    if (state.s !== TreeStage.grown) return fail(ErrorCode.treeNotReady);
    const drop = pickWeighted(data.chopDrops, (d) => d.weight, random).id;
    // 가방이 가득 차면 나무를 찍지 않는다(찍힌 횟수도 그대로).
    if (!canAdd(player.slots, drop, 1, data.limitOf)) return fail(ErrorCode.inventoryFull);
    player.lastChopAt = t;
    const result = chopTree(state, today, data.treeRules.chopsToFell);
    addItem(player.slots, drop, 1, cfg, data.limitOf);
    send(ctx.ws, { t: 'chop_result', rid: msg.rid, ok: true, item: drop, tree: def.id, felled: result.felled });
    sendInventory(player);
    sendProfile(player);
    room.broadcast({ t: 'tree', ...treeWire(def.id, state) });
    room.broadcast({ t: 'act', id: player.id, kind: 'chop', tree: def.id }, player.id);
    rooms.save(room);
  }

  // ---- 주민 대화 · 부탁 ----

  function handleTalk(ctx, msg, fail) {
    const { player, room } = ctx;
    const touch = () => {
      const npc = player.talkingTo !== null ? room.npcs.get(player.talkingTo) : null;
      if (npc) npc.talkTouchedAt = now();
      return npc;
    };
    switch (msg.t) {
      case 'talk': {
        if (!player.acceptRid(msg.rid)) return;
        const npc = typeof msg.npc === 'string' ? room.npcs.get(msg.npc) : null;
        if (!npc) return fail(ErrorCode.notNearNpc);
        if (player.fishing) return fail(ErrorCode.alreadyFishing);
        if (npc.talkingWith !== null && npc.talkingWith !== player.id) return fail(ErrorCode.npcBusy);
        if (Math.hypot(player.x - npc.x, player.z - npc.z) > data.npcRules.talkRange + 0.5) return fail(ErrorCode.notNearNpc);
        if (player.talkingTo !== null && player.talkingTo !== npc.id) closeTalk(room, player, false);
        beginTalk(npc, player, now());
        player.talkingTo = npc.id;
        room.npcsDirty = true;

        const today = clock.day();
        const profile = player.profile;
        const rel = relationOf(profile, npc.id);
        const first = rel.talkDay !== today;
        if (first) {
          rel.talkDay = today;
          addFriendship(rel, data.quests.friend_per_talk);
        }
        const reply = { t: 'talk_open', rid: msg.rid, npc: npc.id, f: rel.f, first };
        const active = profile.quests.find((q) => q.npc === npc.id);
        if (active) {
          reply.quest = questWire(active, player.slots, data);
          reply.ready = questReady(player.slots, active, data);
        } else if (shouldOffer({ rules: data.quests, profile, npcId: npc.id, today, random, chance: cfg.questChance })) {
          const { hour, weather } = environment(room);
          profile.questSeq += 1;
          player.offer = makeQuest({ rules: data.quests, data, npcDef: npc.def, random, hour, weather, today, seq: profile.questSeq });
          rel.offerDay = today;
          profile.lastQuestDay = today;
          reply.offer = player.offer;
        }
        if (profile.lastQuestDay === null) profile.lastQuestDay = today; // 첫 만남부터 "며칠째 부탁 없음"을 센다
        send(ctx.ws, reply);
        rooms.save(room);
        return;
      }
      case 'talk_end': {
        if (player.talkingTo !== null) closeTalk(room, player, false);
        return;
      }
      case 'quest_accept': {
        if (!player.acceptRid(msg.rid)) return;
        const npc = touch();
        if (!npc || !player.offer || player.offer.npc !== npc.id) return fail(ErrorCode.noOffer);
        const quest = player.offer;
        player.offer = null;
        player.profile.quests.push(quest);
        send(ctx.ws, { t: 'quest_accepted', rid: msg.rid, quest: questWire(quest, player.slots, data) });
        sendProfile(player);
        rooms.save(room);
        return;
      }
      case 'quest_decline': {
        touch();
        player.offer = null;
        return;
      }
      case 'quest_turnin': {
        if (!player.acceptRid(msg.rid)) return;
        const npc = touch();
        const quest = player.profile.quests.find((q) => q.id === msg.quest);
        if (!quest) return fail(ErrorCode.badQuest);
        if (!npc || npc.id !== quest.npc) return fail(ErrorCode.notTalking);
        if (!questReady(player.slots, quest, data)) return fail(ErrorCode.questNotReady);
        // 아이템 차감 · 보상 · 친밀도를 한 번에 반영하고 바로 저장한다.
        removeWhere(player.slots, questAccepts(quest, data), quest.n);
        player.profile.sol += quest.reward;
        addFriendship(relationOf(player.profile, npc.id), data.quests.friend_per_quest);
        player.profile.quests = player.profile.quests.filter((q) => q !== quest);
        send(ctx.ws, { t: 'quest_done', rid: msg.rid, quest: quest.id, npc: npc.id, reward: quest.reward, sol: player.profile.sol });
        sendInventory(player);
        sendProfile(player);
        rooms.save(room);
        return;
      }
    }
  }

  /** 낚시·인벤토리·나무·대화 요청. 결과는 항상 서버가 확정해서 알린다. */
  function handleAction(ctx, msg) {
    const { player } = ctx;
    if (!player) return sendError(ctx.ws, ErrorCode.notInRoom);
    const fail = (code) => send(ctx.ws, { t: 'error', code, rid: msg.rid ?? null });
    switch (msg.t) {
      case 'fish_cast': {
        if (!player.acceptRid(msg.rid)) return; // 중복 요청 무시
        if (player.talkingTo !== null) return fail(ErrorCode.alreadyFishing);
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
      case 'equip':
      case 'inv_move':
      case 'inv_discard':
        return handleInventory(ctx, msg, fail);
      case 'chop':
        return handleChop(ctx, msg, fail);
      default:
        return handleTalk(ctx, msg, fail);
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
    if (player.talkingTo !== null) {
      const npc = room.npcs.get(player.talkingTo);
      if (!npc || Math.hypot(player.x - npc.x, player.z - npc.z) > cfg.talkLeaveMeters) closeTalk(room, player, true);
    }

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
      case 'equip':
      case 'inv_move':
      case 'inv_discard':
      case 'chop':
      case 'talk':
      case 'talk_end':
      case 'quest_accept':
      case 'quest_decline':
      case 'quest_turnin':
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
    ws.on('message', (raw, isBinary) => {
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
        msg = JSON.parse(raw.toString());
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
        p: [...room.players.values()].map((p) => ({ id: p.id, fishing: p.fishing !== null, held: p.heldItem, x: p.x, y: p.y, z: p.z, yaw: p.yaw, vx: p.vx, vz: p.vz })),
      });
    }
  }, 1000 / cfg.tickRate);

  // 주민 이동과 대화 시간 초과. 비·뇌우·밤에는 집 앞으로 돌아간다.
  let lastNpcTick = now();
  const npcTick = setInterval(() => {
    const t = now();
    const dtMs = Math.min(t - lastNpcTick, 500);
    lastNpcTick = t;
    for (const room of rooms.rooms.values()) {
      const weather = weatherOf(room);
      const stayHome = weather === 'rain' || weather === 'thunder' || timeBand(clock.hour()) === 'night';
      for (const npc of room.npcs.values()) {
        if (npc.talkingWith !== null && t - npc.talkTouchedAt > cfg.talkTimeoutMs) {
          const player = room.players.get(npc.talkingWith);
          if (player && player.talkingTo === npc.id) closeTalk(room, player, true);
          else endTalk(npc, t);
          room.npcsDirty = true;
        }
      }
      const moved = stepNpcs(room.npcs, {
        dtMs,
        now: t,
        random,
        mode: stayHome ? 'home' : 'roam',
        speed: data.npcRules.walkSpeed,
        idleMinMs: cfg.npcIdleMinMs,
        idleMaxMs: cfg.npcIdleMaxMs,
      });
      if (moved || room.npcsDirty) {
        room.npcsDirty = false;
        room.broadcast({ t: 'npcs', st: t, n: [...room.npcs.values()].map(npcWire) });
      }
    }
  }, 1000 / cfg.npcTickRate);

  // 날씨 변화 · 번개 · 날짜 변경 (1초마다면 충분하다).
  const worldTick = setInterval(() => {
    const t = now();
    for (const room of rooms.rooms.values()) {
      advanceDay(room);
      const weather = weatherOf(room);
      if (weather !== room.weather) {
        room.weather = weather;
        room.broadcast({ t: 'weather', w: weather });
      }
      if (weather === 'thunder' && t >= room.nextLightningAt) {
        if (room.nextLightningAt > 0) room.broadcast({ t: 'lightning', st: t, power: Math.round((0.6 + random() * 0.4) * 100) / 100 });
        room.nextLightningAt = t + cfg.lightningMinMs + random() * (cfg.lightningMaxMs - cfg.lightningMinMs);
      }
    }
  }, 1000);

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
    clock,
    config: cfg,
    get port() {
      return wss.address().port;
    },
    /** 종료: 타이머를 멈추고, 메모리의 방을 전부 저장한 뒤 닫는다. */
    async close() {
      clearInterval(tick);
      clearInterval(npcTick);
      clearInterval(worldTick);
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
