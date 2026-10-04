import { performance } from 'node:perf_hooks';
import { WebSocketServer } from 'ws';
import { defaultConfig } from './config.js';
import { CloseCode, ErrorCode, MOTIONS, PROTOCOL_VERSION, TOPICS } from './protocol.js';
import { RoomManager } from './rooms.js';
import { RoomStore } from './persistence.js';
import { loadGameData, pickWeighted } from './gamedata.js';
import { createFishing } from './fishing.js';
import { addItem, canAdd, moveSlot, removeAt, removeWhere, toWire as inventoryToWire } from './inventory.js';
import { createClock, isWeather, timeBand, weatherAt } from './clock.js';
import { chopTree, newTreeState, refreshTree, treeWire, TreeStage } from './trees.js';
import { beginTalk, endTalk, npcWire, pauseFor, stepNpcs } from './npcs.js';
import { addChatFriendship, addFriendship, makeQuest, pruneExpired, questAccepts, questReady, questWire, relationOf, shouldOffer } from './quests.js';
import { flowerWire, pickFlower, plantProblem, refreshFlower, snapPlant } from './plants.js';
import { baseMood, chooseReaction, currentMood, emoteToTeach, giftToGive, moodAfterEmote, setMood } from './social.js';
import { inInterior, levelFor, nearPoint, sellValue, shopWire, stockFor } from './shop.js';
import { PICKUP_RANGE, placedWire, placementProblem, snap } from './furniture.js';
import { activeEvents, dropPosition, eventsWire, findEvent, planDay, sellMultiplier } from './events.js';

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
    return {
      sol: player.profile.sol,
      quests: player.profile.quests.map((q) => questWire(q, player.slots, data)),
      friends,
      outfit: { ...player.profile.outfit },
      emotes: { known: [...player.profile.emotes.known], quick: [...player.profile.emotes.quick] },
    };
  };
  const sendProfile = (player) => sendTo(player, { t: 'profile', ...profileWire(player) });
  const clockWire = () => ({ g: clock.gameMs(), s: cfg.clockScale, st: now() });
  const shopLevels = data.shop.levels;
  const roomShopWire = (room) => shopWire(room.shopPoints, shopLevels);
  const inShop = (player) => inInterior(data.shop, player.x, player.z);
  /** 지금 구할 수 있는 소지품: 상점 진열품 + 나무에서 나오는 것. */
  const goodsPool = (room) => {
    const pool = new Set(stockFor(room.shopPoints, shopLevels).filter((id) => data.kindOf(id) === 'goods'));
    for (const drops of Object.values(data.chopDrops)) for (const d of drops) if (data.kindOf(d.id) === 'goods') pool.add(d.id);
    return [...pool];
  };

  // ---- 나무 · 꽃 성장 ----

  /** 나무가 단계마다 머무는 시간 (심은 나무는 새싹부터, 베인 나무는 그루터기부터). */
  const treeMinutes = (def) => (def?.planted ? { ...data.treeRules.regrowMinutes, ...data.plants.tree_minutes } : { ...data.plants.tree_minutes, ...data.treeRules.regrowMinutes });
  const treeWireOf = (room, id) => treeWire(id, room.trees.get(id), room.treeDef(id, data));
  const refreshOne = (room, id) => refreshTree(room.trees.get(id), clock.day(), clock.gameMs(), treeMinutes(room.treeDef(id, data)), cfg.growthScale);

  /** 자란 나무·꽃을 알린다 (worldTick 에서). */
  function tickGrowth(room) {
    for (const id of room.trees.keys()) {
      if (refreshOne(room, id)) {
        room.broadcast({ t: 'tree', ...treeWireOf(room, id) });
        room.saveDirty = true;
      }
    }
    const rainy = ['rain', 'thunder'].includes(weatherOf(room));
    for (const f of room.flowers.values()) {
      if (refreshFlower(f, data.flowerDefs.get(f.sp), clock.gameMs(), cfg.growthScale, rainy)) {
        room.broadcast({ t: 'flower', f: flowerWire(f) });
        room.saveDirty = true;
      }
    }
  }

  /** 주민 기분: 바탕 기분(3시간마다 바뀜)과 덮어쓴 기분. 바뀌면 주민 방송에 실린다. */
  function tickMoods(room, weather, eventDay, t) {
    let index = 0;
    for (const npc of room.npcs.values()) {
      npc.baseMood = baseMood({ seed: room.weatherSeed, day: clock.day(), hour: clock.hour(), index: index++, def: npc.def, weather, eventDay });
      const mood = currentMood(npc, t);
      if (mood !== npc.mood) {
        npc.mood = mood;
        room.npcsDirty = true;
      }
    }
  }

  // ---- 이벤트 ----

  /** 오늘의 이벤트 계획 (날짜가 바뀌면 다시 뽑는다). */
  const planOf = (room) => {
    const day = clock.day();
    if (!room.plan || room.plan.day !== day) {
      room.plan = planDay({ seed: room.weatherSeed, day, events: data.events, data, force: cfg.eventForce, forcedWanted: cfg.eventWanted });
    }
    return room.plan;
  };
  const activeOf = (room) => (room ? activeEvents(planOf(room), clock.hour(), weatherOf(room)) : []);
  const eventsMessage = (room) => ({ t: 'ev', ...eventsWire(activeOf(room), clock.day()) });
  const dropWire = (d) => (d.kind === 'gift' ? { id: d.id, kind: d.kind, x: d.x, z: d.z } : { id: d.id, kind: d.kind, item: d.item, x: d.x, z: d.z });

  /** 선물 풍선·별 조각 떨어뜨리기와 끝난 이벤트의 것 치우기 (worldTick 에서). */
  function tickDrops(room, active, t) {
    const kinds = { gift: findEvent(active, 'gift_day'), star: findEvent(active, 'meteor_shower') };
    for (const d of [...room.drops.values()]) {
      if (kinds[d.kind]) continue;
      room.drops.delete(d.id);
      room.broadcast({ t: 'drop_gone', id: d.id, by: 0 });
    }
    for (const [kind, ev] of Object.entries(kinds)) {
      if (!ev) {
        room.nextDropAt[kind] = 0;
        continue;
      }
      const count = [...room.drops.values()].filter((d) => d.kind === kind).length;
      if (count >= ev.def.max || t < room.nextDropAt[kind]) continue;
      room.nextDropAt[kind] = t + ev.def.spawn_every_s * 1000 * cfg.eventSpawnScale;
      const at = dropPosition({ random, data, layout: data.layout });
      if (!at) continue;
      const item = kind === 'gift' ? pickWeighted(ev.def.pool, (p) => p.weight, random).id : ev.def.item;
      room.dropSeq += 1;
      const d = { id: `d${room.dropSeq}`, kind, item, x: at.x, z: at.z };
      room.drops.set(d.id, d);
      room.broadcast({ t: 'drop', d: dropWire(d) });
    }
  }

  /** 선물·별 조각 줍기. */
  function handleCollect(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const d = typeof msg.id === 'string' ? room.drops.get(msg.id) : null;
    if (!d || Math.hypot(player.x - d.x, player.z - d.z) > data.events.collect_range + 0.5) return fail(ErrorCode.noDrop);
    if (!addItem(player.slots, d.item, 1, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
    room.drops.delete(d.id);
    send(ctx.ws, { t: 'collect_result', rid: msg.rid, id: d.id, kind: d.kind, item: d.item });
    sendInventory(player);
    sendProfile(player);
    room.broadcast({ t: 'drop_gone', id: d.id, by: player.id });
    rooms.save(room);
  }

  const fishing = createFishing({
    cfg,
    data,
    random: overrides.random,
    notify: sendTo,
    heldItem: (player) => player.heldItem,
    environment: (player) => environment(roomOf(player)),
    derby: (player) => findEvent(activeOf(roomOf(player)), 'fishing_derby'),
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
    // 들어오자마자 주민 기분이 보이도록 (worldTick 을 기다리지 않는다).
    tickMoods(room, weatherOf(room), activeOf(room).length > 0, now());
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
      trees: [...room.trees.keys()].map((id) => treeWireOf(room, id)),
      flowers: [...room.flowers.values()].map(flowerWire),
      museum: museumWire(room),
      npcs: [...room.npcs.values()].map(npcWire),
      shop: roomShopWire(room),
      placed: [...room.placed.values()].map((f) => placedWire(f, (uid) => room.slotOfUid(uid))),
      ev: eventsWire(activeOf(room), clock.day()),
      drops: [...room.drops.values()].map(dropWire),
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
    for (const id of room.trees.keys()) {
      if (refreshOne(room, id)) room.broadcast({ t: 'tree', ...treeWireOf(room, id) });
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
        const invalid = !Number.isInteger(slot) || slot < -1 || slot >= cfg.quickSlots;
        if (invalid || player.fishing) {
          fail(invalid ? ErrorCode.badItem : ErrorCode.alreadyFishing);
          // 클라이언트는 손에 든 칸을 먼저 바꿔 보여 주므로, 거절할 때는 서버 값을 다시 보낸다.
          return sendInventory(player);
        }
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
    const def = typeof msg.tree === 'string' ? room.treeDef(msg.tree, data) : null;
    if (!def || Math.hypot(player.x - def.x, player.z - def.z) > data.treeRules.chopRange) return fail(ErrorCode.notNearTree);
    const t = now();
    if (t - player.lastChopAt < cfg.chopCooldownMs) return fail(ErrorCode.tooFast);
    const state = room.trees.get(def.id);
    const today = clock.day();
    refreshOne(room, def.id);
    if (state.s !== TreeStage.grown) return fail(ErrorCode.treeNotReady);
    const drop = pickWeighted(data.chopDrops[def.kind], (d) => d.weight, random).id;
    // 나무꾼의 날에는 두 개씩.
    const lumber = findEvent(activeOf(room), 'lumber_day');
    const count = lumber ? lumber.def.drop_multiplier : 1;
    // 가방이 가득 차면 나무를 찍지 않는다(찍힌 횟수도 그대로).
    if (!canAdd(player.slots, drop, count, data.limitOf)) return fail(ErrorCode.inventoryFull);
    player.lastChopAt = t;
    const result = chopTree(state, today, clock.gameMs(), data.treeRules.chopsToFell);
    addItem(player.slots, drop, count, cfg, data.limitOf);
    send(ctx.ws, { t: 'chop_result', rid: msg.rid, ok: true, item: drop, n: count, tree: def.id, felled: result.felled });
    sendInventory(player);
    sendProfile(player);
    room.broadcast({ t: 'tree', ...treeWireOf(room, def.id) });
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
        } else {
          // 같은 날 또 말을 걸어도 조금씩 친해진다 (수다와 합쳐 하루 상한).
          addChatFriendship(rel, today, data.npcRules.talkExtraFriend, data.npcRules.topicFriendPerDay);
        }
        const reply = { t: 'talk_open', rid: msg.rid, npc: npc.id, f: rel.f, first, m: currentMood(npc, now()) };
        // 친해진 만큼 감정표현을 하나씩 가르쳐 준다.
        const teach = emoteToTeach(npc.def, rel.f, profile.emotes.known);
        if (teach) {
          profile.emotes.known.push(teach);
          if (profile.emotes.quick.length < data.emotes.quick_slots) profile.emotes.quick.push(teach);
          reply.teach = teach;
        }
        // 친한 주민은 가끔 선물을 챙겨 준다 (가방이 꽉 차 있으면 다음에).
        const gift = giftToGive({ def: npc.def, rel, rules: data.npcRules.gift, today, random });
        if (gift && addItem(player.slots, gift, 1, cfg, data.limitOf)) {
          rel.giftDay = today;
          reply.gift = gift;
          sendInventory(player);
        }
        const active = profile.quests.find((q) => q.npc === npc.id);
        if (active) {
          reply.quest = questWire(active, player.slots, data);
          reply.ready = questReady(player.slots, active, data);
        } else if (shouldOffer({ rules: data.quests, profile, npcId: npc.id, today, random, chance: cfg.questChance })) {
          const { hour, weather } = environment(room);
          const only = data.quests.templates.filter((t) => t.id === cfg.questTemplate);
          const rules = only.length > 0 ? { ...data.quests, templates: only } : data.quests;
          profile.questSeq += 1;
          player.offer = makeQuest({ rules, data, npcDef: npc.def, random, hour, weather, today, seq: profile.questSeq, goodsPool: goodsPool(room) });
          rel.offerDay = today;
          profile.lastQuestDay = today;
          reply.offer = player.offer;
        }
        if (profile.lastQuestDay === null) profile.lastQuestDay = today; // 첫 만남부터 "며칠째 부탁 없음"을 센다
        send(ctx.ws, reply);
        if (reply.teach || reply.gift) sendProfile(player);
        rooms.save(room);
        return;
      }
      case 'talk_topic': {
        // 대화 주제 하나를 골라 수다를 떨었다: 하루 몇 번까지 친밀도가 오르고, 주민 기분이 조금 풀린다.
        const npc = touch();
        if (!npc || npc.talkingWith !== player.id) return fail(ErrorCode.notTalking);
        if (!TOPICS.includes(msg.topic)) return fail(ErrorCode.badTopic);
        const rel = relationOf(player.profile, npc.id);
        const gain = addChatFriendship(rel, clock.day(), 1, data.npcRules.topicFriendPerDay);
        const t = now();
        const mood = currentMood(npc, t);
        if (gain > 0 && (mood === 'sad' || mood === 'grumpy') && random() < 0.5) {
          setMood(npc, 'calm', t);
          npc.mood = 'calm';
          room.npcsDirty = true;
        }
        send(ctx.ws, { t: 'talk_topic', npc: npc.id, topic: msg.topic, f: rel.f, gain, m: npc.mood });
        if (gain > 0) sendProfile(player);
        room.saveDirty = true;
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
        setMood(npc, 'happy', now());
        npc.mood = 'happy';
        room.npcsDirty = true;
        player.profile.quests = player.profile.quests.filter((q) => q !== quest);
        send(ctx.ws, { t: 'quest_done', rid: msg.rid, quest: quest.id, npc: npc.id, reward: quest.reward, sol: player.profile.sol });
        sendInventory(player);
        sendProfile(player);
        rooms.save(room);
        return;
      }
    }
  }

  // ---- 상점 ----

  /** 상점 문으로 드나들기: 서버가 위치를 옮기고 알려 준다 (이동 검사를 거치지 않는 순간 이동). */
  function moveThroughDoor(ctx, inside) {
    const { player, room } = ctx;
    const spot = inside ? data.shop.inside_spawn : data.shop.outside_spawn;
    player.x = spot.x;
    player.z = spot.z;
    player.y = 0.1;
    player.vx = 0;
    player.vz = 0;
    player.lastMoveAt = now();
    player.doorAt = now();
    fishing.drop(player);
    closeTalk(room, player, false);
    room.dirty = true;
    room.saveDirty = true;
    send(ctx.ws, { t: 'shop_door', inside, x: player.x, y: player.y, z: player.z, shop: roomShopWire(room) });
  }

  function handleShop(ctx, msg, fail) {
    const { player, room } = ctx;
    switch (msg.t) {
      case 'shop_enter': {
        if (!nearPoint(data.shop.door, player.x, player.z, data.shop.enter_range + 0.5)) return fail(ErrorCode.notNearDoor);
        return moveThroughDoor(ctx, true);
      }
      case 'shop_exit': {
        if (!inShop(player) || !nearPoint(data.shop.exit, player.x, player.z, data.shop.exit_range + 0.5)) return fail(ErrorCode.notNearDoor);
        return moveThroughDoor(ctx, false);
      }
      case 'shop_sell':
      case 'shop_buy': {
        if (!player.acceptRid(msg.rid)) return;
        const n = msg.n === undefined ? 1 : msg.n;
        if (!Number.isInteger(n) || n < 1 || n > 99) return fail(ErrorCode.badItem);
        if (msg.at === 'merchant') return handleMerchant(ctx, msg, n, fail);
        if (msg.at === 'airport') return handleAirport(ctx, msg, n, fail);
        if (!inShop(player)) return fail(ErrorCode.notInShop);
        const before = levelFor(room.shopPoints, shopLevels).level;
        let item;
        let amount;
        if (msg.t === 'shop_sell') {
          const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
          if (!slot) return fail(ErrorCode.badItem);
          const base = data.priceOf(slot.id);
          if (base <= 0) return fail(ErrorCode.cantSell);
          item = slot.id;
          // 특가 매입의 날에는 고른 물건을 2배로.
          amount = Math.floor(sellValue(base, n, room.shopPoints, shopLevels) * sellMultiplier(activeOf(room), item, 'shop'));
          if (!removeAt(player.slots, msg.slot, n)) return fail(ErrorCode.badItem);
          player.profile.sol += amount;
        } else {
          item = msg.item;
          if (typeof item !== 'string' || !stockFor(room.shopPoints, shopLevels).includes(item)) return fail(ErrorCode.notForSale);
          amount = data.items.get(item).buy * n;
          if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
          if (!addItem(player.slots, item, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
          player.profile.sol -= amount;
        }
        // 사고판 솔만큼 상점 포인트가 쌓인다 (마을 공용).
        room.shopPoints += Math.round(amount * data.shop.points_per_sol * cfg.shopPointsScale);
        const shop = roomShopWire(room);
        send(ctx.ws, { t: 'shop_result', rid: msg.rid, kind: msg.t === 'shop_sell' ? 'sell' : 'buy', item, n, sol: player.profile.sol, amount });
        sendInventory(player);
        sendProfile(player);
        room.broadcast({ t: 'shop', ...shop, up: shop.level > before });
        rooms.save(room);
        return;
      }
    }
  }

  /** 떠돌이 상인과 사고팔기: 상인 곁에서만, 찾는 물건만 2배 값에 사 가고, 귀한 물건을 판다. 상점 포인트는 쌓이지 않는다. */
  function handleMerchant(ctx, msg, n, fail) {
    const { player } = ctx;
    const room = ctx.room;
    const active = activeOf(room);
    const merchant = findEvent(active, 'merchant');
    const spot = merchant?.def.spot;
    if (!merchant || Math.hypot(player.x - spot.x, player.z - spot.z) > data.npcRules.talkRange + 1) return fail(ErrorCode.merchantAway);
    let item;
    let amount;
    if (msg.t === 'shop_sell') {
      const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
      if (!slot) return fail(ErrorCode.badItem);
      const mult = sellMultiplier(active, slot.id, 'merchant');
      if (mult <= 0) return fail(ErrorCode.notWanted);
      item = slot.id;
      amount = Math.floor(data.priceOf(item) * n * mult);
      if (!removeAt(player.slots, msg.slot, n)) return fail(ErrorCode.badItem);
      player.profile.sol += amount;
    } else {
      item = msg.item;
      if (typeof item !== 'string' || !merchant.def.stock.includes(item)) return fail(ErrorCode.notForSale);
      amount = data.items.get(item).buy * n;
      if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
      if (!addItem(player.slots, item, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
      player.profile.sol -= amount;
    }
    send(ctx.ws, { t: 'shop_result', rid: msg.rid, kind: msg.t === 'shop_sell' ? 'sell' : 'buy', item, n, sol: player.profile.sol, amount, at: 'merchant' });
    sendInventory(player);
    sendProfile(player);
    rooms.save(room);
  }

  // ---- 씨앗 심기 · 꽃 따기 ----

  function handlePlant(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (msg.t === 'pick') {
      const f = typeof msg.id === 'string' ? room.flowers.get(msg.id) : null;
      if (!f || f.s !== 'bloom' || Math.hypot(player.x - f.x, player.z - f.z) > data.plants.plant_range + 0.5) return fail(ErrorCode.noFlower);
      const def = data.flowerDefs.get(f.sp);
      if (!addItem(player.slots, def.item, 1, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
      pickFlower(f, def, clock.gameMs(), cfg.growthScale);
      send(ctx.ws, { t: 'pick_result', rid: msg.rid, id: f.id, item: def.item });
      sendInventory(player);
      sendProfile(player);
      room.broadcast({ t: 'flower', f: flowerWire(f), by: player.id });
      rooms.save(room);
      return;
    }
    // plant: 손에 든 씨앗을 (x, z) 에 심는다.
    if (player.fishing) return fail(ErrorCode.alreadyFishing);
    const held = player.profile.held;
    const seedId = player.heldItem;
    const seed = data.seedOf(seedId);
    if (!seed) return fail(ErrorCode.notSeed);
    const x = snapPlant(Number(msg.x));
    const z = snapPlant(Number(msg.z));
    const kind = seed.tree ? 'tree' : 'flower';
    if (kind === 'tree' && room.plantedTrees.size >= data.plants.max_planted_trees) return fail(ErrorCode.plantLimit);
    if (kind === 'flower' && room.flowers.size >= data.plants.max_flowers) return fail(ErrorCode.plantLimit);
    const problem = plantProblem({ kind, x, z, player, data, trees: room.allTreeSpots(data), flowers: room.flowers, placed: room.placed });
    if (problem) return fail(ErrorCode.badPlant);
    removeAt(player.slots, held, 1);
    let id;
    if (kind === 'tree') {
      room.plantSeq += 1;
      id = `p${room.plantSeq}`;
      room.plantedTrees.set(id, { id, kind: seed.tree, x, z, by: player.id, planted: true });
      room.trees.set(id, newTreeState(TreeStage.sprout, clock.gameMs()));
      room.broadcast({ t: 'tree', ...treeWireOf(room, id), by: player.id });
    } else {
      room.flowerSeq += 1;
      id = `g${room.flowerSeq}`;
      const def = data.flowerDefs.get(seed.flower);
      const f = { id, sp: seed.flower, c: Math.floor(random() * def.colors.length), x, z, s: 'sprout', t: clock.gameMs(), by: player.id };
      room.flowers.set(id, f);
      room.broadcast({ t: 'flower', f: flowerWire(f), by: player.id });
    }
    send(ctx.ws, { t: 'plant_result', rid: msg.rid, id, kind, x, z });
    sendInventory(player);
    sendProfile(player);
    rooms.save(room);
  }

  // ---- 감정표현 · 주민 반응 ----

  function handleEmote(ctx, msg, fail) {
    const { player, room } = ctx;
    const t = now();
    if (msg.t === 'emote_quick') {
      if (!Array.isArray(msg.quick)) return fail(ErrorCode.badMessage);
      const known = player.profile.emotes.known;
      player.profile.emotes.quick = [...new Set(msg.quick.filter((e) => typeof e === 'string' && known.includes(e)))].slice(0, data.emotes.quick_slots);
      sendProfile(player);
      room.saveDirty = true;
      return;
    }
    const e = msg.e;
    const motion = MOTIONS.includes(e);
    if (typeof e !== 'string' || (!motion && !player.profile.emotes.known.includes(e))) return fail(ErrorCode.unknownEmote);
    // 몸짓(브레이크)과 감정표현은 따로 센다 (달리다 멈추며 인사해도 둘 다 보인다).
    const key = motion ? 'lastMotionAt' : 'lastEmoteAt';
    if (t - (player[key] ?? -Infinity) < (motion ? 200 : data.emotes.cooldown_ms)) return fail(ErrorCode.tooFast);
    player[key] = t;
    room.broadcast({ t: 'act', id: player.id, kind: 'emote', e }, player.id);
    if (motion) return;
    // 근처 주민이 성격·기분대로 반응한다. 하루 한 번은 친밀도도 조금 오른다.
    const today = clock.day();
    for (const npc of room.npcs.values()) {
      if (npc.talkingWith !== null && npc.talkingWith !== player.id) continue;
      if (Math.hypot(player.x - npc.x, player.z - npc.z) > data.emotes.react_range) continue;
      if (t - npc.reactAt < data.emotes.npc_react_cooldown_ms) continue;
      npc.reactAt = t;
      const def = npc.def;
      const reaction = chooseReaction({ emotes: data.emotes, personality: def.personality, mood: currentMood(npc, t), emote: e, random });
      const after = moodAfterEmote(data.emotes, def.personality, e);
      if (after) setMood(npc, after, t);
      npc.mood = currentMood(npc, t);
      pauseFor(npc, player.x, player.z, t, 2600);
      const rel = relationOf(player.profile, npc.id);
      let gain = 0;
      if (rel.emoteDay !== today && e !== 'angry') {
        rel.emoteDay = today;
        addFriendship(rel, data.emotes.friend_per_reaction);
        gain = data.emotes.friend_per_reaction;
      }
      room.npcsDirty = true;
      room.broadcast({ t: 'npc_emote', npc: npc.id, e: reaction, to: player.id, m: npc.mood, from: e });
      if (gain > 0) sendProfile(player);
    }
    room.saveDirty = true;
  }

  // ---- 박물관 ----

  function museumWire(room) {
    return { fish: { ...room.museum.fish } };
  }

  function handleDonate(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const curator = data.museum.curator;
    if (Math.hypot(player.x - curator.x, player.z - curator.z) > data.museum.donate_range + 0.5) return fail(ErrorCode.notNearKeeper);
    const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
    if (!slot) return fail(ErrorCode.badItem);
    if (!data.isFish(slot.id)) return fail(ErrorCode.notFish);
    if (room.museum.fish[slot.id] !== undefined) return fail(ErrorCode.alreadyDonated);
    removeAt(player.slots, msg.slot, 1);
    room.museum.fish[slot.id] = player.id;
    player.profile.sol += data.museum.reward_sol;
    // 기증 수가 문턱을 넘으면 기념품 (가방이 차 있으면 다음 기증 때 다시 준다).
    const count = Object.keys(room.museum.fish).length;
    const gifts = [];
    for (const m of data.museum.milestones) {
      if (count < m.count || room.museum.claimed.includes(m.count)) continue;
      if (!addItem(player.slots, m.item, 1, cfg, data.limitOf)) break;
      room.museum.claimed.push(m.count);
      gifts.push(m.item);
    }
    send(ctx.ws, { t: 'donate_result', rid: msg.rid, fish: slot.id, reward: data.museum.reward_sol, sol: player.profile.sol, count, gifts });
    sendInventory(player);
    sendProfile(player);
    room.broadcast({ t: 'museum', ...museumWire(room), id: slot.id, by: player.id });
    rooms.save(room);
  }

  /** 공항 기념품 가게: 조종사 곁에서만, 공항 물건만. 상점 포인트는 쌓이지 않는다. */
  function handleAirport(ctx, msg, n, fail) {
    const { player, room } = ctx;
    const pilot = data.airport.pilot;
    if (Math.hypot(player.x - pilot.x, player.z - pilot.z) > data.airport.shop_range + 0.5) return fail(ErrorCode.notNearKeeper);
    if (msg.t !== 'shop_buy') return fail(ErrorCode.cantSell);
    const item = msg.item;
    if (typeof item !== 'string' || !data.airport.stock.includes(item)) return fail(ErrorCode.notForSale);
    const amount = data.items.get(item).buy * n;
    if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
    if (!addItem(player.slots, item, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
    player.profile.sol -= amount;
    send(ctx.ws, { t: 'shop_result', rid: msg.rid, kind: 'buy', item, n, sol: player.profile.sol, amount, at: 'airport' });
    sendInventory(player);
    sendProfile(player);
    rooms.save(room);
  }

  // ---- 가구 설치 · 옷 ----

  function handleFurniture(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    switch (msg.t) {
      case 'place': {
        const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
        if (!slot || data.kindOf(slot.id) !== 'furniture') return fail(ErrorCode.badItem);
        const mine = [...room.placed.values()].filter((f) => f.owner === player.uid).length;
        if (mine >= cfg.maxPlacedPerPlayer) return fail(ErrorCode.placeLimit);
        const x = snap(Number(msg.x));
        const z = snap(Number(msg.z));
        if (placementProblem({ x, z, player, placed: room.placed, data, trees: room.allTreeSpots(data), flowers: room.flowers })) return fail(ErrorCode.badPlace);
        removeAt(player.slots, msg.slot, 1);
        room.placedSeq += 1;
        const rot = Number.isInteger(msg.rot) ? ((msg.rot % 4) + 4) % 4 : 0;
        const f = { id: `f${room.placedSeq}`, item: slot.id, x, z, rot, owner: player.uid };
        room.placed.set(f.id, f);
        sendInventory(player);
        sendProfile(player);
        room.broadcast({ t: 'placed', rid: msg.rid, by: player.id, f: placedWire(f, (uid) => room.slotOfUid(uid)) });
        rooms.save(room);
        return;
      }
      case 'pickup': {
        const f = typeof msg.id === 'string' ? room.placed.get(msg.id) : null;
        if (!f || Math.hypot(player.x - f.x, player.z - f.z) > PICKUP_RANGE) return fail(ErrorCode.badPlace);
        if (f.owner !== player.uid) return fail(ErrorCode.notOwner);
        if (!addItem(player.slots, f.item, 1, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
        room.placed.delete(f.id);
        sendInventory(player);
        sendProfile(player);
        room.broadcast({ t: 'unplaced', rid: msg.rid, id: f.id });
        rooms.save(room);
        return;
      }
      case 'wear': {
        const index = msg.slot;
        const slot = Number.isInteger(index) ? player.slots[index] : null;
        const info = slot ? data.items.get(slot.id) : null;
        if (!info || info.kind !== 'clothing') return fail(ErrorCode.notWearable);
        // 입던 옷은 방금 비운 그 칸으로 돌아간다 (가방이 꽉 차 있어도 갈아입을 수 있다).
        const previous = player.profile.outfit[info.wear];
        removeAt(player.slots, index, 1);
        if (previous) player.slots[index] = { id: previous, n: 1 };
        player.profile.outfit[info.wear] = info.id;
        break;
      }
      case 'unwear': {
        const part = msg.part;
        if (part !== 'hat' && part !== 'top') return fail(ErrorCode.notWearable);
        const worn = player.profile.outfit[part];
        if (!worn) return fail(ErrorCode.notWearable);
        if (!addItem(player.slots, worn, 1, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
        player.profile.outfit[part] = '';
        break;
      }
    }
    // 옷을 입거나 벗었다.
    sendInventory(player);
    sendProfile(player);
    room.dirty = true; // 스냅샷으로 상대에게 옷을 보여 준다
    rooms.save(room);
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
      case 'shop_enter':
      case 'shop_exit':
      case 'shop_sell':
      case 'shop_buy':
        return handleShop(ctx, msg, fail);
      case 'place':
      case 'pickup':
      case 'wear':
      case 'unwear':
        return handleFurniture(ctx, msg, fail);
      case 'collect':
        return handleCollect(ctx, msg, fail);
      case 'plant':
      case 'pick':
        return handlePlant(ctx, msg, fail);
      case 'emote':
      case 'emote_quick':
        return handleEmote(ctx, msg, fail);
      case 'donate':
        return handleDonate(ctx, msg, fail);
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
    // 문을 지난 직후 도착한, 문 반대편의 낡은 위치 요청은 버린다 (되돌리지 않는다).
    if (t - player.doorAt < cfg.doorGraceMs && dist > 10) return;
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
      case 'shop_enter':
      case 'shop_exit':
      case 'shop_sell':
      case 'shop_buy':
      case 'place':
      case 'pickup':
      case 'wear':
      case 'unwear':
      case 'collect':
      case 'plant':
      case 'pick':
      case 'emote':
      case 'emote_quick':
      case 'donate':
      case 'talk_topic':
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
        p: [...room.players.values()].map((p) => ({
          id: p.id,
          fishing: p.fishing !== null,
          held: p.heldItem,
          hat: p.profile.outfit.hat,
          top: p.profile.outfit.top,
          x: p.x,
          y: p.y,
          z: p.z,
          yaw: p.yaw,
          vx: p.vx,
          vz: p.vz,
        })),
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
      // 이벤트가 열리고 닫히면 알린다. 선물·별 조각도 여기서 떨어뜨린다.
      const active = activeOf(room);
      const wire = eventsMessage(room);
      const sig = JSON.stringify(wire);
      if (sig !== room.eventSig) {
        room.eventSig = sig;
        room.broadcast(wire);
      }
      tickDrops(room, active, t);
      tickGrowth(room);
      tickMoods(room, weather, active.length > 0, t);
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
