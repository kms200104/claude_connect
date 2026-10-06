import { performance } from 'node:perf_hooks';
import { WebSocketServer } from 'ws';
import { defaultConfig } from './config.js';
import { CloseCode, ErrorCode, MOTIONS, PROTOCOL_VERSION, SAY_GAP_MS, SAY_MAX_CHARS, TOPICS } from './protocol.js';
import { RoomManager } from './rooms.js';
import { RoomStore } from './persistence.js';
import { loadGameData, pickWeighted } from './gamedata.js';
import { createFishing } from './fishing.js';
import { addItem, canAdd, moveSlot, removeAt, removeWhere, toWire as inventoryToWire } from './inventory.js';
import { createClock, isWeather, seasonOf, timeBand, weatherAt } from './clock.js';
import { chopTree, newTreeState, refreshTree, treeWire, TreeStage } from './trees.js';
import { beginTalk, endTalk, npcWire, pauseFor, stepNpcs, updateApproaches } from './npcs.js';
import { createMessenger } from './messenger.js';
import { addChatFriendship, addFriendship, makeQuest, pruneExpired, questAccepts, questReady, questWire, relationOf, shouldOffer } from './quests.js';
import { flowerWire, onPath, pickFlower, plantProblem, refreshFlower, snapPlant } from './plants.js';
import { groundProblem } from './world.js';
import { baseMood, chooseReaction, currentMood, emoteToTeach, giftToGive, mbtiLetter, moodAfterEmote, setMood } from './social.js';
import { inInterior, levelFor, nearPoint, sellValue, shopWire, stockFor } from './shop.js';
import { defaultFurniture, furnitureWire, interiorOrigin, lobbyOf, normRot, onFloor, snapGrid } from './homes.js';
import { PICKUP_RANGE, placedWire, placementProblem, snap } from './furniture.js';
import { activeEvents, buyMultiplier, dropPosition, eventsWire, findKind, planDay, sellMultiplier } from './events.js';
import { weekOf } from './bank.js';
import { applyFaceRequest, nearMirror } from './face.js';
import { cleanName } from './nickname.js';
import { createMarket } from './market.js';
import { createEconomy, earn } from './economy.js';
import { createKitchen } from './kitchen.js';
import { inZone, netCatch, refillShoal, shoalWire, stepShoal } from './shoal.js';
import { TileKind, beachSpot, digSpotWire, diggers, hitSpot, lakeShoreSpot, onBeach, snapTile, tileKey } from './dig.js';
import { distanceToSpot } from './gamedata.js';
import { createJobs } from './jobs.js';
import { createDelivery, storeIngredients } from './delivery.js';
import { SWIM, createSwimmers } from './swimmers.js';
import { zoneWeight } from './fishing.js';

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
/** 같이 베기: 이 시간 안에 다른 사람이 같은 나무를 찍었으면 함께 찍는 것으로 본다. */
const COOP_CHOP_MS = 4000;
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
  const environment = (room) => ({ hour: clock.hour(), weather: room ? weatherOf(room) : 'clear', season: cfg.seasonForce || seasonOf(clock.gameMs()) });

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
      face: { ...player.profile.face },
      name: player.profile.name ?? '',
      ...economy.profileWire(roomOf(player), player.profile),
    };
  };
  /** 프로필 보내기. 혼인한 세대면 지갑이 하나라 세대원에게도 함께 보낸다. */
  const sendProfile = (player) => {
    sendTo(player, { t: 'profile', ...profileWire(player) });
    const room = player.profile.household ? roomOf(player) : null;
    if (!room) return;
    for (const m of room.householdOf(player.profile)) {
      const live = m.uid !== player.uid ? room.players.get(m.slot) : null;
      if (live && live.uid === m.uid) sendTo(live, { t: 'profile', ...profileWire(live) });
    }
  };
  const clockWire = () => ({ g: clock.gameMs(), s: cfg.clockScale, st: now(), se: cfg.seasonForce || '' });

  // ---- 경제: 증권 · 아파트 · 은행 · 식당 (economy.js) ----
  const market = overrides.market ?? createMarket(data.market, { saveDir: cfg.saveDir, feedUrl: cfg.marketFeedUrl, random, gameMs: clock.gameMs, day: clock.day, forceHours: cfg.marketHours === 'krx' });
  /** 동사무소 그 창구(직원) 곁인지. */
  const nearDesk = (player, desk, extra = 0) => {
    const staff = data.civic.staff.find((s) => s.desk === desk);
    return !!staff && Math.hypot(player.x - staff.x, player.z - staff.z) <= data.civic.service_range + 0.5 + extra;
  };
  const messenger = createMessenger({ data, cfg, random, sendTo, clock });
  const economy = createEconomy({ data, cfg, clock, random, now, market, send, sendTo, sendProfile, sendInventory, rooms, nearDesk, onWeekReport: messenger.weekly });
  const jobs = createJobs({ data, random, now, clock, send, sendTo, sendProfile, act: (...a) => act(...a) });
  const kitchen = createKitchen({ data, cfg, random, now, send, sendTo, sendProfile, sendInventory, when: () => ({ season: environment(null).season, hour: clock.hour() }) });
  const shopLevels = data.shop.levels;
  const roomShopWire = (room) => shopWire(room.shopPoints, shopLevels);
  const inShop = (player) => inInterior(data.shop, player.x, player.z);
  /** 상점에서 사는 값 (장바구니 물가가 오른 주에는 비싸다). */
  const buyPrice = (room, item, n) => Math.round(data.items.get(item).buy * n * buyMultiplier(activeOf(room), item, data.kindOf));
  const delivery = createDelivery({
    data, cfg, random, now, send, sendTo, sendInventory, sendProfile, messenger, buyPrice,
    stockFor: (room) => stockFor(room.shopPoints, shopLevels),
    isIndoor: (p) => !!p.home || inShop(p),
    onPaid: (room, player, amount) => {
      room.shopPoints += Math.round(amount * data.shop.points_per_sol * cfg.shopPointsScale);
      room.broadcast({ t: 'shop', ...roomShopWire(room), up: false });
    },
    onStored: (room) => kitchen.broadcastRest(room),
  });
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
      room.plan = planDay({ seed: room.weatherSeed, day, events: data.events, data, force: cfg.eventForce, forcedWanted: cfg.eventWanted, season: environment(null).season });
    }
    return room.plan;
  };
  /** 이번 주 경제 소식 (v0.12, economy.js 가 주간 정산 때 정한다). 지난 주 것이면 없다. */
  const econOf = (room) => {
    const e = room.econ;
    if (!e || e.week !== weekOf(clock.day())) return null;
    const def = data.events.economy?.find((x) => x.id === e.id);
    return def ? { id: e.id, def } : null;
  };
  const activeOf = (room) => (room ? activeEvents(planOf(room), clock.hour(), weatherOf(room), econOf(room)) : []);
  const eventsMessage = (room) => ({ t: 'ev', ...eventsWire(activeOf(room), clock.day()) });
  const dropWire = (d) => {
    if (d.kind === 'gift') return { id: d.id, kind: d.kind, x: d.x, z: d.z };
    if (d.kind === 'item') return { id: d.id, kind: d.kind, item: d.item, n: d.n, x: d.x, z: d.z };
    return { id: d.id, kind: d.kind, item: d.item, x: d.x, z: d.z };
  };

  /** 선물 풍선·별 조각 떨어뜨리기와 끝난 이벤트의 것 치우기 (worldTick 에서). */
  function tickDrops(room, active, t) {
    const kinds = { gift: findKind(active, 'gift'), star: findKind(active, 'meteor') };
    for (const d of [...room.drops.values()]) {
      if (kinds[d.kind] || d.kind === 'forage' || d.kind === 'item') continue;
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
    tickForage(room, t);
  }

  /** 들판의 먹거리(나물·버섯·산딸기)는 이벤트와 상관없이 늘 조금씩 돋아난다 — 식당 재료를 채집으로 모을 수 있다. */
  function tickForage(room, t) {
    const rules = data.restaurant.forage;
    const count = [...room.drops.values()].filter((d) => d.kind === 'forage').length;
    if (count >= rules.max || t < room.nextDropAt.forage) return;
    // 처음엔 한꺼번에 반쯤 채워 두고, 그다음부터 천천히.
    room.nextDropAt.forage = count < rules.max / 2 ? t : t + rules.spawn_every_s * 1000 * cfg.eventSpawnScale;
    const at = forageSpot();
    if (!at) return;
    room.dropSeq += 1;
    const d = { id: `d${room.dropSeq}`, kind: 'forage', item: pickWeighted(rules.items, (p) => p.weight, random).id, x: at.x, z: at.z };
    room.drops.set(d.id, d);
    room.broadcast({ t: 'drop', d: dropWire(d) });
  }

  /** 채집물 자리: 섬 안쪽의 빈 풀밭 (건물·아파트·식당·물가는 피한다). */
  function forageSpot() {
    const rules = data.restaurant.forage;
    const avoid = [
      { x: data.restaurant.building.x, z: data.restaurant.building.z + 4, r: 12 },
      { x: data.museum.building.x, z: data.museum.building.z, r: 11 },
      { x: data.airport.building.x, z: data.airport.building.z, r: 11 },
      ...data.realestate.buildings.map((b) => ({ x: b.x, z: b.z, r: 9 })),
      { x: data.realestate.office.x, z: data.realestate.office.z, r: 4 },
      // 동사무소 건물(앞면 기준 뒤로 depth) + 앞 창구·광장.
      ...(data.civic?.building ? [{ x: data.civic.building.x, z: data.civic.building.z - (data.civic.building.depth ?? 8) * 0.5, r: 10 }] : []),
      { x: 0, z: 0, r: 8 },
    ];
    for (let i = 0; i < 10; i++) {
      const at = dropPosition({ random, data, layout: data.layout, near: { x: 0, z: 0 }, radius: rules.radius });
      if (!at) continue;
      const half = data.layout?.island?.half ?? 100;
      const beach = data.layout?.island?.beach ?? 9;
      if (Math.abs(at.x) > half - beach - 6 || Math.abs(at.z) > half - beach - 6) continue;
      if (avoid.some((a) => Math.hypot(at.x - a.x, at.z - a.z) < a.r)) continue;
      return at;
    }
    return null;
  }

  /**
   * v13: 내려놓을 자리. 발밑에서 시작해, 이미 놓인 물건과 겹치지 않게 해바라기 씨 배치로 조금씩 벌려 놓는다
   * (줍기 거리 안을 벗어나지 않는다).
   */
  function groundSpot(ground, x, z) {
    const near = ground.filter((d) => Math.hypot(d.x - x, d.z - z) < 1.6);
    for (let k = 0; k < 24; k++) {
      const r = k === 0 ? 0.25 : 0.25 + 0.2 * Math.sqrt(k);
      const a = k * 2.39996 + 0.6;
      const at = { x: x + Math.cos(a) * r, z: z + Math.sin(a) * r };
      if (near.every((d) => Math.hypot(d.x - at.x, d.z - at.z) >= 0.42)) return at;
    }
    return { x, z };
  }

  /** 선물·별 조각·먹거리, 그리고 사람이 내려놓은 물건(v13) 줍기. 내려놓은 묶음은 가방에 들어가는 만큼만 줍고 나머지는 남는다. */
  function handleCollect(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const d = typeof msg.id === 'string' ? room.drops.get(msg.id) : null;
    if (!d || Math.hypot(player.x - d.x, player.z - d.z) > data.events.collect_range + 0.5) return fail(ErrorCode.noDrop);
    let n = 1;
    if (d.kind === 'item') {
      n = d.n;
      while (n > 0 && !canAdd(player.slots, d.item, n, data.limitOf)) n -= 1;
    }
    if (n < 1 || !addItem(player.slots, d.item, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
    const left = d.kind === 'item' ? d.n - n : 0;
    send(ctx.ws, { t: 'collect_result', rid: msg.rid, id: d.id, kind: d.kind, item: d.item, n, left });
    sendInventory(player);
    sendProfile(player);
    if (left > 0) {
      d.n = left;
      room.broadcast({ t: 'drop', d: dropWire(d) });
    } else {
      room.drops.delete(d.id);
      room.broadcast({ t: 'drop_gone', id: d.id, by: player.id });
    }
    act(room, player, 'pick');
    rooms.save(room);
  }

  /** v0.12: 다른 사람 화면에 보일 몸짓 (줍기·심기·놓기·건네기 등). 판정과 상관없는 연출용 알림. */
  function act(room, player, kind, e = '') {
    room.broadcast({ t: 'act', id: player.id, kind, e }, player.id);
  }

  /**
   * v0.12: 말풍선. 대화하는 사람의 화면에 뜬 대사(주민 말 · 내가 고른 말)를 둘레 사람에게도 머리 위 말풍선으로 보여 준다.
   * 대사는 클라이언트가 고른 꾸밈 글자라 판정에 쓰지 않는다. 대화 중인 주민 것만, 길이·간격을 제한한다.
   */
  // 클라이언트에서만 대화가 이어지는 가게 사람들 (상점 주인 · 박물관 관장 · 조종사 · 떠돌이 상인) — 서버는 대화 중인지 모른다.
  const SAY_KEEPERS = new Set(
    [data.shop?.keeper?.id, data.museum?.curator?.id, data.airport?.pilot?.id, ...(data.events?.daily ?? []).map((e) => e?.npc?.id)].filter(Boolean),
  );

  function handleSay(ctx, msg, fail) {
    const { player, room } = ctx;
    const who = msg.who === 'npc' ? 'npc' : 'me';
    const keeper = who === 'npc' && SAY_KEEPERS.has(msg.npc);
    if (!keeper && (player.talkingTo === null || (who === 'npc' && msg.npc !== player.talkingTo))) return fail(ErrorCode.notTalking);
    const t = now();
    if (t - (player.lastSayAt ?? -Infinity) < SAY_GAP_MS) return fail(ErrorCode.tooFast);
    const text = typeof msg.tx === 'string' ? msg.tx.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, SAY_MAX_CHARS) : '';
    if (!text) return fail(ErrorCode.badMessage);
    player.lastSayAt = t;
    room.broadcast({ t: 'say', id: player.id, npc: who === 'npc' ? msg.npc : '', tx: text }, player.id);
  }

  // v13: 낚시터에 보이는 물고기 (swimmers.js). 낚시 대회가 열리면 희귀한 물고기가 더 자주 나타난다.
  const swimSpots = [...data.spots.keys(), ...(data.fishingSpot?.('sea') ? ['sea'] : [])];
  const swimmers = createSwimmers({
    data,
    random: overrides.random ?? Math.random,
    now,
    environment: (spot) => environment(null),
    weightFor: (room, spot, zone) => {
      const d = findKind(activeOf(room), 'derby');
      const boost = d && (!Array.isArray(d.def.spots) || d.def.spots.includes(spot.id)) ? d.def.rare_boost ?? 1 : 1;
      return (f) => f.weight * (f.rarity === 'rare' ? boost : 1) * zoneWeight(zone, f);
    },
    spotIds: () => swimSpots,
  });
  const fishing = createFishing({
    cfg,
    data,
    random: overrides.random,
    swim: {
      inWater: (spot, x, z) => swimmers.inWater(spot, x, z, 0.3),
      engage: (player, spot, x, z, waited = 0) => {
        const room = roomOf(player);
        return room ? swimmers.engage(room, spot.id, x, z, player.id, now(), SWIM.notice + SWIM.noticeGrowth * waited) : null;
      },
      release: (player, id, caught) => {
        const room = roomOf(player);
        if (room) swimmers.release(room, id, caught, now());
      },
    },
    notify: sendTo,
    heldItem: (player) => player.heldItem,
    environment: (player) => environment(roomOf(player)),
    // 낚시 대회: 대회가 열린 낚시터에서만 (spots 가 없으면 어디서나).
    derby: (player, spot) => {
      const d = findKind(activeOf(roomOf(player)), 'derby');
      return d && (!Array.isArray(d.def.spots) || d.def.spots.includes(spot?.id)) ? d : null;
    },
    // 같이 낚시: 같은 낚시터에서 9m 안에 다른 사람이 낚고 있으면.
    companions: (player, spot) => {
      const room = roomOf(player);
      if (!room) return 0;
      return [...room.players.values()].filter((p) => p !== player && p.fishing && p.fishing.spot === spot && Math.hypot(p.x - player.x, p.z - player.z) <= 9).length;
    },
    onFishingChanged: (player) => {
      const room = roomOf(player);
      if (room) room.dirty = true; // 스냅샷에 fishing 플래그를 실어 보낸다
    },
    publish: (player, ev) => roomOf(player)?.broadcast({ t: 'act', id: player.id, kind: 'fish', ...ev }, player.id),
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
    if (npc) room.broadcast({ t: 'act', id: player.id, kind: 'talk_end', e: npc.id }, player.id);
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
    kitchen.seedRestaurant(room);
    economy.tickWeek(room);
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
      market: market.wire(),
      homes: economy.homesWire(room),
      rest: kitchen.restWire(room),
      civic: economy.civicWire(room, player.profile),
      tiles: [...room.tiles.values()].map((t) => [t.x, t.z, t.s]),
      digspots: [...room.digSpots.values()].map(digSpotWire),
      shoals: [...room.shoals.values()].map(shoalWire),
      chats: messenger.wire(room, player.profile),
      couriers: delivery.wire(room),
      deliv: delivery.mine(room, player.uid),
    });
    room.broadcast(resumed ? { t: 'peer_status', id: player.id, online: true } : { t: 'peer_joined', p: player.toWire() }, player.id);
    // 집 안에서 끊겼다 돌아오면 그 집 안 그대로 (위치로 어느 집인지 찾는다).
    player.home = homeAtPosition(player.x, player.z);
    if (player.home) send(ctx.ws, homeMessage(room, player, null));
    room.dirty = true;
    rooms.save(room);
  }

  function checkVersion(ctx, msg) {
    if (msg.v !== PROTOCOL_VERSION) {
      // 앱이 어느 쪽이 옛날 것인지 알려 줄 수 있게 서버 버전을 같이 보낸다.
      send(ctx.ws, { t: 'error', code: ErrorCode.badVersion, msg: `server protocol ${PROTOCOL_VERSION}`, server_v: PROTOCOL_VERSION });
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
        // v13: 버린 물건은 사라지지 않고 발밑에 남는다 (누구나 다시 주울 수 있다).
        if (!player.acceptRid(msg.rid)) return;
        const slot = player.slots[msg.slot];
        if (!Number.isInteger(msg.slot) || !slot) return fail(ErrorCode.badItem);
        if (data.isTool(slot.id)) return fail(ErrorCode.cantDiscard);
        if (player.home || inShop(player)) return fail(ErrorCode.cantDropHere);
        const n = msg.n === undefined ? 1 : msg.n;
        const ground = [...room.drops.values()].filter((d) => d.kind === 'item');
        if (ground.length >= cfg.groundItemMax) return fail(ErrorCode.groundFull);
        const item = slot.id;
        if (!removeAt(player.slots, msg.slot, n)) return fail(ErrorCode.badItem);
        const at = groundSpot(ground, player.x, player.z);
        room.groundSeq += 1;
        const d = { id: `g${room.groundSeq}`, kind: 'item', item, n, x: at.x, z: at.z };
        room.drops.set(d.id, d);
        room.broadcast({ t: 'drop', d: dropWire(d), by: player.id });
        act(room, player, 'drop', item);
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
    const lumber = findKind(activeOf(room), 'lumber');
    const count = lumber ? lumber.def.drop_multiplier : 1;
    // 가방이 가득 차면 나무를 찍지 않는다(찍힌 횟수도 그대로).
    if (!canAdd(player.slots, drop, count, data.limitOf)) return fail(ErrorCode.inventoryFull);
    player.lastChopAt = t;
    // 같이 베기 (v0.9): 다른 사람이 4초 안에 같은 나무를 찍었으면 이번 도끼질은 두 번 찍은 셈.
    const last = room.treeHits.get(def.id);
    const partner = last && last.by !== player.id && t - last.at <= COOP_CHOP_MS ? room.players.get(last.by) : null;
    room.treeHits.set(def.id, { by: player.id, at: t });
    const result = chopTree(state, today, clock.gameMs(), data.treeRules.chopsToFell, partner ? 2 : 1);
    addItem(player.slots, drop, count, cfg, data.limitOf);
    // 같이 쓰러뜨리면 두 사람 모두 하나씩 더.
    let bonus = 0;
    if (result.felled && partner) {
      room.treeHits.delete(def.id);
      if (addItem(player.slots, drop, 1, cfg, data.limitOf)) bonus = 1;
      if (partner.online && addItem(partner.slots, drop, 1, cfg, data.limitOf)) {
        sendTo(partner, { t: 'coop_bonus', kind: 'chop', item: drop, n: 1, with: player.id });
        sendInventory(partner);
      }
    }
    send(ctx.ws, { t: 'chop_result', rid: msg.rid, ok: true, item: drop, n: count + bonus, tree: def.id, felled: result.felled, coop: !!partner });
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
        room.broadcast({ t: 'act', id: player.id, kind: 'talk', e: npc.id }, player.id);

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
          const { hour, weather, season } = environment(room);
          const only = data.quests.templates.filter((t) => t.id === cfg.questTemplate);
          const rules = only.length > 0 ? { ...data.quests, templates: only } : data.quests;
          profile.questSeq += 1;
          player.offer = makeQuest({ rules, data, npcDef: npc.def, random, hour, weather, season, today, seq: profile.questSeq, goodsPool: goodsPool(room) });
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
        // 고민 상담: 공감을 잘하는 F 주민과는 더 가까워진다.
        const bonus = msg.topic === 'worry' ? (data.mbti.worry_friend_bonus?.[mbtiLetter(npc.def.mbti, 2)] ?? 0) : 0;
        const gain = addChatFriendship(rel, clock.day(), 1 + bonus, data.npcRules.topicFriendPerDay);
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
        earn(player.profile, quest.reward);
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
        let back = 0;
        let stored = false;
        if (msg.t === 'shop_sell') {
          const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
          if (!slot) return fail(ErrorCode.badItem);
          const base = data.priceOf(slot.id);
          if (base <= 0) return fail(ErrorCode.cantSell);
          item = slot.id;
          // 특가 매입의 날에는 고른 물건을 2배로.
          amount = Math.floor(sellValue(base, n, room.shopPoints, shopLevels) * sellMultiplier(activeOf(room), item, 'shop', data.kindOf));
          if (!removeAt(player.slots, msg.slot, n)) return fail(ErrorCode.badItem);
          player.profile.sol += amount;
          earn(player.profile, amount);
        } else {
          item = msg.item;
          if (typeof item !== 'string' || !stockFor(room.shopPoints, shopLevels).includes(item)) return fail(ErrorCode.notForSale);
          // 장바구니 물가가 오른 주(v0.12 경제 소식)에는 그 종류가 비싸다.
          amount = buyPrice(room, item, n);
          if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
          // v13: 식재료는 가방 대신 식당 창고로 바로 간다 (식당은 창고 재료부터 쓴다).
          stored = data.kindOf(item) === 'ingredient';
          if (stored) {
            const max = data.shop.storage?.max_per_item ?? 999;
            if ((room.restaurant.storage?.[item] ?? 0) + n > max) return fail(ErrorCode.storageFull);
            storeIngredients(room.restaurant, item, n, max);
          } else if (!addItem(player.slots, item, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
          player.profile.sol -= amount;
          back = economy.cashback(room, player, amount);
        }
        // 사고판 솔만큼 상점 포인트가 쌓인다 (마을 공용).
        room.shopPoints += Math.round(amount * data.shop.points_per_sol * cfg.shopPointsScale);
        const shop = roomShopWire(room);
        send(ctx.ws, { t: 'shop_result', rid: msg.rid, kind: msg.t === 'shop_sell' ? 'sell' : 'buy', item, n, sol: player.profile.sol, amount, back, stored });
        sendInventory(player);
        sendProfile(player);
        room.broadcast({ t: 'shop', ...shop, up: shop.level > before });
        if (stored) kitchen.broadcastRest(room);
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
    const merchant = findKind(active, 'visitor');
    const spot = merchant?.def.spot;
    let back = 0;
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
      earn(player.profile, amount);
    } else {
      item = msg.item;
      if (typeof item !== 'string' || !merchant.def.stock.includes(item)) return fail(ErrorCode.notForSale);
      // 손님마다 파는 값 배율 (v0.12: 중고 가구상은 70%).
      amount = Math.round(data.items.get(item).buy * n * (merchant.def.buy_mult ?? 1));
      if (player.profile.sol < amount) return fail(ErrorCode.notEnoughSol);
      if (!addItem(player.slots, item, n, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
      player.profile.sol -= amount;
      back = economy.cashback(room, player, amount);
    }
    send(ctx.ws, { t: 'shop_result', rid: msg.rid, kind: msg.t === 'shop_sell' ? 'sell' : 'buy', item, n, sol: player.profile.sol, amount, back, at: 'merchant' });
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
      // 봄꽃 축제(v0.12)에는 꽃이 두 송이씩.
      const fest = findKind(activeOf(room), 'flowers');
      if (!addItem(player.slots, def.item, fest ? fest.def.drop_multiplier ?? 2 : 1, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
      pickFlower(f, def, clock.gameMs(), cfg.growthScale);
      send(ctx.ws, { t: 'pick_result', rid: msg.rid, id: f.id, item: def.item });
      sendInventory(player);
      sendProfile(player);
      room.broadcast({ t: 'flower', f: flowerWire(f), by: player.id });
      act(room, player, 'pick');
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
    act(room, player, 'plant');
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
      // E 는 멀리서도 늘 반응하고, I 는 가까이에서만 가끔 반응한다.
      const def = npc.def;
      const ei = mbtiLetter(def.mbti, 0);
      if (Math.hypot(player.x - npc.x, player.z - npc.z) > (data.mbti.react_range?.[ei] ?? data.emotes.react_range)) continue;
      if (t - npc.reactAt < data.emotes.npc_react_cooldown_ms) continue;
      if (random() >= (data.mbti.react_chance?.[ei] ?? 1)) continue;
      npc.reactAt = t;
      const reaction = chooseReaction({ emotes: data.emotes, personality: def.personality, mood: currentMood(npc, t), emote: e, random, mbti: data.mbti, type: def.mbti });
      const after = moodAfterEmote(data.emotes, def.personality, e, data.mbti, def.mbti);
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
    earn(player.profile, data.museum.reward_sol);
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
    act(room, player, 'give', slot.id);
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
    const back = economy.cashback(room, player, amount);
    send(ctx.ws, { t: 'shop_result', rid: msg.rid, kind: 'buy', item, n, sol: player.profile.sol, amount, back, at: 'airport' });
    sendInventory(player);
    sendProfile(player);
    rooms.save(room);
  }

  // ---- 거울: 얼굴 꾸미기 ----

  /** 거울 앞에서 얼굴(눈·코·입·피부·머리)을 바꾼다. 바꾼 얼굴은 방 모두에게 알린다 (요청한 사람에게는 rid 와 함께). */
  function handleFace(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (inShop(player) || !nearMirror(data, room.placed, player.x, player.z)) return fail(ErrorCode.notNearMirror);
    const next = applyFaceRequest(player.profile.face, msg.face, data.face);
    if (!next) return fail(ErrorCode.badFace);
    player.profile.face = next;
    sendTo(player, { t: 'face', rid: msg.rid, id: player.id, face: { ...next } });
    room.broadcast({ t: 'face', id: player.id, face: { ...next } }, player.id);
    rooms.save(room);
  }

  /** 닉네임 (v14): 어디서나 바꿀 수 있다 (거울 창 · 처음 화면 설정). 빈 이름이면 기본 이름으로 돌아간다. */
  function handleName(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const name = cleanName(msg.name);
    if (name === null) return fail(ErrorCode.badName);
    player.profile.name = name;
    sendTo(player, { t: 'name', rid: msg.rid, id: player.id, name });
    room.broadcast({ t: 'name', id: player.id, name }, player.id);
    rooms.save(room);
  }

  /** 입장할 때 같이 보낸 닉네임 (처음 화면 설정). 쓸 수 없거나 비었으면 그대로 둔다. */
  function applyJoinName(player, raw) {
    const name = cleanName(raw);
    if (!name || name === player.profile.name) return false;
    player.profile.name = name;
    return true;
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
        act(room, player, 'place');
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
        act(room, player, 'place');
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

  // ---- 여울 몰이 (뜰채) ----

  /** 뜰채질: 여울 안에서 앞쪽 둘레의 물고기를 떠 올린다. 같은 여울에 두 사람 이상이면 넓게 뜬다. */
  function handleNet(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const rules = data.dig.net;
    if (player.heldItem !== 'fishing_net') return fail(ErrorCode.noTool);
    const t = now();
    if (t - (player.lastNetAt ?? -Infinity) < rules.cooldown_ms) return fail(ErrorCode.tooFast);
    const shoal = [...room.shoals.values()].find((s) => inZone(s.zone, player.x, player.z, 0.6));
    if (!shoal) return fail(ErrorCode.notInShallow);
    player.lastNetAt = t;
    const wading = [...room.players.values()].filter((p) => p.online && inZone(shoal.zone, p.x, p.z, 0.3)).length;
    const coop = wading >= 2;
    // 캐릭터 정면 = -Z 를 yaw 만큼 돌린 방향.
    const cx = player.x - Math.sin(player.yaw) * rules.range;
    const cz = player.z - Math.cos(player.yaw) * rules.range;
    const caught = netCatch(shoal, cx, cz, coop ? rules.coop_radius : rules.radius, rules.max_catch);
    const got = [];
    for (const f of caught) if (addItem(player.slots, f.sp, 1, cfg, data.limitOf)) got.push(f.sp);
    if (got.length) {
      player.profile.catches += got.length;
      room.stats.totalCatches += got.length;
      for (const id of got) room.stats.species[id] = (room.stats.species[id] ?? 0) + 1;
    }
    send(ctx.ws, { t: 'net_result', rid: msg.rid, fish: got, coop, lost: caught.length - got.length });
    room.broadcast({ t: 'act', id: player.id, kind: 'net', e: got.length ? 'catch' : 'miss' }, player.id);
    room.broadcast({ t: 'shoal', ...shoalWire(shoal) });
    if (got.length) {
      sendInventory(player);
      sendProfile(player);
      rooms.save(room);
    }
  }

  // ---- 집 안 (v0.10): 아파트 호수마다 평면도대로 지은 집 안, 가구 놓기·옮기기·회수 ----

  const homeRules = data.floorplans;
  const HOME_MAX_FURNITURE = 60;
  /** 그 호수 집 안의 월드 원점 (평면도 왼쪽 위). */
  const homeOrigin = (unitId) => (homeRules ? interiorOrigin(homeRules, data.units, unitId) : null);
  const unitById = (unitId) => data.units.find((u) => u.id === unitId) ?? null;
  /** 이 위치가 어느 집 안인지 (끊겼다 돌아왔을 때). */
  function homeAtPosition(x, z) {
    if (!homeRules || x > -100) return null;
    for (const u of data.units) {
      const o = homeOrigin(u.id);
      const plan = data.planOf(u);
      if (o && plan && x >= o.x - 1 && x <= o.x + plan.size.x + 1 && z >= o.z - 1 && z <= o.z + plan.size.z + 1) return u.id;
    }
    return null;
  }
  /** 그 집 가구 목록 (아직 아무도 손대지 않은 집은 평면도의 기본 가구). */
  const homeList = (room, unitId) => room.homeItems[unitId] ?? defaultFurniture(data.planOf(unitById(unitId)));
  /** 내 집이거나 우리 세대(혼인신고한 배우자) 집이면 가구를 옮길 수 있다. */
  function canEditHome(room, player, unitId) {
    const owner = room.homes[unitId]?.owner;
    if (!owner) return false;
    return room.householdOf(player.profile).some((p) => p.uid === owner);
  }
  function homeMessage(room, player, rid) {
    const unit = unitById(player.home);
    const o = homeOrigin(player.home);
    const owner = room.homes[player.home]?.owner;
    return {
      t: 'home', rid, unit: player.home, plan: data.planOf(unit)?.id ?? '', ox: o.x, oz: o.z,
      owner: owner ? room.slotOfUid(owner) ?? 0 : 0, edit: canEditHome(room, player, player.home),
      x: player.x, y: player.y, z: player.z, f: furnitureWire(homeList(room, player.home)),
    };
  }
  /** 그 집 안에 있는 사람 모두에게 가구 목록을 다시 보낸다 (요청한 사람에게는 rid 와 함께). */
  function broadcastHomeFurniture(room, unitId, requester, rid) {
    const wire = furnitureWire(homeList(room, unitId));
    for (const p of room.players.values()) {
      if (!p.online || p.home !== unitId) continue;
      sendTo(p, { t: 'home_f', rid: p === requester ? rid : null, unit: unitId, f: wire });
    }
  }
  function teleport(ctx, x, z) {
    const { player, room } = ctx;
    player.x = x;
    player.z = z;
    player.y = 0.1;
    player.vx = 0;
    player.vz = 0;
    player.lastMoveAt = now();
    player.doorAt = now();
    fishing.drop(player);
    closeTalk(room, player, false);
    room.dirty = true;
    room.saveDirty = true;
  }

  function handleHomeInside(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    if (!homeRules) return fail(ErrorCode.notHome);
    if (msg.t === 'home_enter') {
      const unit = typeof msg.unit === 'string' ? unitById(msg.unit) : null;
      if (!unit) return fail(ErrorCode.badUnit);
      if (player.home) return fail(ErrorCode.notAtLobby);
      const lobby = lobbyOf(data.realestate, homeRules, unit.building);
      if (!lobby || Math.hypot(player.x - lobby.x, player.z - lobby.z) > homeRules.lobby.range + 0.5) return fail(ErrorCode.notAtLobby);
      const plan = data.planOf(unit);
      const o = homeOrigin(unit.id);
      player.home = unit.id;
      teleport(ctx, o.x + plan.spawn[0], o.z + plan.spawn[1]);
      return send(ctx.ws, homeMessage(room, player, msg.rid));
    }
    if (!player.home) return fail(ErrorCode.notHome);
    const unitId = player.home;
    const plan = data.planOf(unitById(unitId));
    const o = homeOrigin(unitId);
    if (msg.t === 'home_exit') {
      if (Math.hypot(player.x - (o.x + plan.front[0]), player.z - (o.z + plan.front[1])) > 2.2) return fail(ErrorCode.notHome);
      const lobby = lobbyOf(data.realestate, homeRules, unitById(unitId).building);
      player.home = null;
      teleport(ctx, lobby.x, lobby.z + 0.6);
      return send(ctx.ws, { t: 'home', rid: msg.rid, unit: '', x: player.x, y: player.y, z: player.z });
    }
    if (!canEditHome(room, player, unitId)) return fail(ErrorCode.notEditable);
    const grid = homeRules.grid ?? 0.25;
    const spot = () => {
      if (![msg.x, msg.z].every(isNum)) return null;
      const x = snapGrid(msg.x, grid);
      const z = snapGrid(msg.z, grid);
      return onFloor(plan, x, z, 0.05) ? { x, z } : null;
    };
    // 처음 손대는 집: 기본 가구를 그 집 것으로 만든다.
    const list = (room.homeItems[unitId] ??= defaultFurniture(plan));
    switch (msg.t) {
      case 'home_place': {
        const slot = Number.isInteger(msg.slot) ? player.slots[msg.slot] : null;
        if (!slot || data.kindOf(slot.id) !== 'furniture') return fail(ErrorCode.badItem);
        if (list.length >= HOME_MAX_FURNITURE) return fail(ErrorCode.homeFull);
        const at = spot();
        if (!at) return fail(ErrorCode.badPlace);
        removeAt(player.slots, msg.slot, 1);
        room.homeItemSeq += 1;
        list.push({ id: `h${room.homeItemSeq}`, item: slot.id, x: at.x, z: at.z, rot: normRot(msg.rot) });
        sendInventory(player);
        break;
      }
      case 'home_move': {
        const f = list.find((x) => x.id === msg.id);
        if (!f) return fail(ErrorCode.badPlace);
        const at = spot();
        if (!at) return fail(ErrorCode.badPlace);
        f.x = at.x;
        f.z = at.z;
        f.rot = normRot(msg.rot);
        break;
      }
      case 'home_pickup': {
        const i = list.findIndex((x) => x.id === msg.id);
        if (i < 0) return fail(ErrorCode.badPlace);
        if (!addItem(player.slots, list[i].item, 1, cfg, data.limitOf)) return fail(ErrorCode.inventoryFull);
        list.splice(i, 1);
        sendInventory(player);
        break;
      }
      default:
        return fail(ErrorCode.badMessage);
    }
    broadcastHomeFurniture(room, unitId, player, msg.rid);
    act(room, player, 'place');
    rooms.save(room);
  }

  // ---- 삽: 조개 캐기 · 땅 고치기 ----

  /** 바닷가·호숫가에 조개 숨구멍을 돋운다 (worldTick). */
  function tickDigSpots(room, t) {
    const rules = data.dig;
    const count = (kind) => [...room.digSpots.values()].filter((d) => d.kind === kind).length;
    const add = (kind, at, hp, spot = '') => {
      room.digSeq += 1;
      const d = { id: `s${room.digSeq}`, kind, spot, x: at.x, z: at.z, hp, hits: [] };
      room.digSpots.set(d.id, d);
      room.broadcast({ t: 'digspot', d: digSpotWire(d) });
    };
    if (count('beach') < rules.beach.max && t >= room.nextDigAt.beach) {
      // 처음엔 반쯤 한꺼번에, 그다음은 천천히.
      room.nextDigAt.beach = count('beach') < rules.beach.max / 2 ? t : t + rules.beach.spawn_every_s * 1000 * cfg.eventSpawnScale;
      const at = beachSpot(data.layout?.island, random);
      if (at && !data.blocked.rects.some((r) => at.x >= r.x0 && at.x <= r.x1 && at.z >= r.z0 && at.z <= r.z1)) add('beach', at, rules.beach.hp);
    }
    if (t >= room.nextDigAt.lake) {
      room.nextDigAt.lake = t + rules.lake.spawn_every_s * 1000 * cfg.eventSpawnScale;
      for (const spot of data.spots.values()) {
        const here = [...room.digSpots.values()].filter((d) => d.kind === 'lake' && d.spot === spot.id).length;
        if (here >= rules.lake.max_per_spot) continue;
        const at = lakeShoreSpot(spot, data.layout?.lake_shore ?? 1.6, random);
        if (distanceToSpot(spot, at.x, at.z) > 0.3) add('lake', at, rules.lake.hp, spot.id);
      }
    }
  }

  /**
   * 삽질: (x, z) 를 판다. 숨구멍 곁이면 조개 캐기(hp 번, 같이 파면 두 배로 줄고 판 사람 모두 하나씩),
   * 아니면 땅 고치기 — mode: dig(풀밭 → 구덩이, 가끔 조약돌·옛날 동전·화석) / fill(구덩이 메우기) / path(흙길 깔기·걷기).
   */
  function handleDig(ctx, msg, fail) {
    const { player, room } = ctx;
    if (!player.acceptRid(msg.rid)) return;
    const rules = data.dig;
    if (player.heldItem !== 'shovel') return fail(ErrorCode.noTool);
    if (![msg.x, msg.z].every(isNum)) return fail(ErrorCode.badDig);
    if (Math.hypot(msg.x - player.x, msg.z - player.z) > rules.dig_range + 0.5) return fail(ErrorCode.badDig);
    const t = now();
    if (t - (player.lastDigAt ?? -Infinity) < rules.cooldown_ms) return fail(ErrorCode.tooFast);
    player.lastDigAt = t;
    // 조개 숨구멍
    const spot = [...room.digSpots.values()].find((d) => Math.hypot(d.x - msg.x, d.z - msg.z) <= rules.spot_range);
    if (spot) {
      const res = hitSpot(spot, player.id, t, rules.coop_window_ms);
      room.broadcast({ t: 'act', id: player.id, kind: 'dig', e: spot.kind }, player.id);
      if (!res.done) {
        room.broadcast({ t: 'digspot', d: digSpotWire(spot) });
        send(ctx.ws, { t: 'dig_result', rid: msg.rid, kind: 'spot', spot: spot.id, hp: spot.hp, coop: res.coop });
        return;
      }
      room.digSpots.delete(spot.id);
      room.broadcast({ t: 'digspot_gone', id: spot.id, by: player.id });
      const table = spot.kind === 'beach' ? rules.beach.items : rules.lake.items;
      const people = diggers(spot);
      for (const id of people) {
        const p = room.players.get(id);
        if (!p || !p.online) continue;
        const item = pickWeighted(table, (e) => e.weight, random).id;
        const ok = addItem(p.slots, item, 1, cfg, data.limitOf);
        const reply = { t: 'dig_result', kind: 'clam', spot: spot.id, item: ok ? item : '', full: !ok, coop: people.length >= 2 };
        if (p === player) reply.rid = msg.rid;
        sendTo(p, reply);
        if (ok) {
          sendInventory(p);
          sendProfile(p);
        }
      }
      rooms.save(room);
      return;
    }
    // 땅 고치기
    const x = snapTile(msg.x);
    const z = snapTile(msg.z);
    const key = tileKey(x, z);
    const tile = room.tiles.get(key);
    const mode = msg.mode;
    const problem = groundProblem(data, x, z) || onBeach(data.layout?.island, x, z) || (mode !== 'fill' && onPath(data.layout, x, z));
    if (problem) return fail(ErrorCode.badDig);
    if (room.allTreeSpots(data).some((tr) => Math.hypot(tr.x - x, tr.z - z) < 1.2)) return fail(ErrorCode.badDig);
    if ([...room.flowers.values()].some((f) => Math.hypot(f.x - x, f.z - z) < 0.8)) return fail(ErrorCode.badDig);
    if ([...room.placed.values()].some((f) => Math.hypot(f.x - x, f.z - z) < 1.0)) return fail(ErrorCode.badDig);
    let found = '';
    if (mode === 'dig') {
      if (tile) return fail(ErrorCode.badDig);
      if (room.tiles.size >= rules.max_tiles) return fail(ErrorCode.plantLimit);
      room.tiles.set(key, { x, z, s: TileKind.hole });
      if (random() < rules.hole_finds.chance) {
        const item = pickWeighted(rules.hole_finds.items, (e) => e.weight, random).id;
        if (addItem(player.slots, item, 1, cfg, data.limitOf)) found = item;
      }
    } else if (mode === 'fill') {
      if (tile?.s !== TileKind.hole) return fail(ErrorCode.badDig);
      room.tiles.delete(key);
    } else if (mode === 'path') {
      if (tile?.s === TileKind.hole) return fail(ErrorCode.badDig);
      if (tile?.s === TileKind.path) room.tiles.delete(key);
      else {
        if (room.tiles.size >= rules.max_tiles) return fail(ErrorCode.plantLimit);
        room.tiles.set(key, { x, z, s: TileKind.path });
      }
    } else return fail(ErrorCode.badDig);
    const now_ = room.tiles.get(key);
    room.broadcast({ t: 'tile', x, z, s: now_?.s ?? '' });
    room.broadcast({ t: 'act', id: player.id, kind: 'dig', e: mode }, player.id);
    send(ctx.ws, { t: 'dig_result', rid: msg.rid, kind: mode, x, z, s: now_?.s ?? '', item: found });
    if (found) {
      sendInventory(player);
      sendProfile(player);
    }
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
        // 상점 · 집 안에서는 낚시를 못 한다 (실내는 바다 건너에 있어서 바다 낚시터로 잘못 잡히던 버그).
        if (player.home || inShop(player)) return fail(ErrorCode.notAtSpot);
        const target = Number.isFinite(msg.x) && Number.isFinite(msg.z) ? { x: msg.x, z: msg.z } : null;
        const err = fishing.cast(player, msg.rid, msg.spot, target);
        if (err) fail(err);
        return;
      }
      case 'fish_hook': {
        const err = fishing.hook(player, msg.rid, msg.reaction);
        if (err) fail(err);
        return;
      }
      case 'msg_send':
      case 'msg_read':
        return messenger.handle(ctx, msg, fail);
      case 'fish_reel': {
        const err = fishing.reel(player, msg.rid, msg.taps);
        if (err) fail(err);
        return;
      }
      case 'fish_cancel':
        return fishing.cancel(player);
      case 'say':
        return handleSay(ctx, msg, fail);
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
      case 'deliv_order':
        return delivery.order(ctx, msg, fail);
      case 'plant':
      case 'pick':
        return handlePlant(ctx, msg, fail);
      case 'emote':
      case 'emote_quick':
        return handleEmote(ctx, msg, fail);
      case 'donate':
        return handleDonate(ctx, msg, fail);
      case 'set_face':
        return handleFace(ctx, msg, fail);
      case 'set_name':
        return handleName(ctx, msg, fail);
      case 'stock_order':
        return economy.handleStock(ctx, msg, fail);
      case 'apt_buy':
      case 'apt_sell':
      case 'apt_lease':
        return economy.handleHome(ctx, msg, fail);
      case 'dep_open':
      case 'dep_close':
      case 'park_move':
        return economy.handleSavings(ctx, msg, fail);
      case 'job_info':
      case 'job_take':
      case 'job_pick':
      case 'job_drop':
      case 'job_quit':
        return jobs.handle(ctx, msg, fail);
      case 'bank_quote':
      case 'loan_take':
      case 'loan_repay':
        return economy.handleBank(ctx, msg, fail);
      case 'rest_open':
      case 'rest_join':
      case 'rest_close':
      case 'rest_cook':
      case 'rest_step':
        return kitchen.handleRestaurant(ctx, msg, fail);
      case 'civic_info':
      case 'civic_civil':
      case 'civic_apply':
      case 'marry_propose':
      case 'marry_answer':
        return economy.handleCivic(ctx, msg, fail);
      case 'net':
        return handleNet(ctx, msg, fail);
      case 'dig':
        return handleDig(ctx, msg, fail);
      case 'home_enter':
      case 'home_exit':
      case 'home_place':
      case 'home_move':
      case 'home_pickup':
        return handleHomeInside(ctx, msg, fail);
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
        applyJoinName(player, msg.name);
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
        const renamed = applyJoinName(added.player, msg.name);
        // 같은 uid가 이미 방에 있으면(다른 기기/재접속) 그 자리를 이어받는다.
        bind(ctx, room, added.player, added.existing);
        // 이어받은 자리는 다른 사람이 이미 알고 있으니 바뀐 이름만 따로 알린다.
        if (renamed && added.existing) room.broadcast({ t: 'name', id: added.player.id, name: added.player.profile.name }, added.player.id);
        return;
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
      case 'fish_reel':
      case 'msg_send':
      case 'msg_read':
      case 'fish_cancel':
      case 'say':
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
      case 'deliv_order':
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
      case 'set_face':
      case 'set_name':
      case 'talk_topic':
      case 'stock_order':
      case 'apt_buy':
      case 'apt_sell':
      case 'apt_lease':
      case 'dep_open':
      case 'dep_close':
      case 'park_move':
      case 'job_info':
      case 'job_take':
      case 'job_pick':
      case 'job_drop':
      case 'job_quit':
      case 'bank_quote':
      case 'loan_take':
      case 'loan_repay':
      case 'rest_open':
      case 'rest_join':
      case 'rest_close':
      case 'rest_cook':
      case 'rest_step':
      case 'civic_info':
      case 'civic_civil':
      case 'civic_apply':
      case 'marry_propose':
      case 'marry_answer':
      case 'net':
      case 'dig':
      case 'home_enter':
      case 'home_exit':
      case 'home_place':
      case 'home_move':
      case 'home_pickup':
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
          held: jobs.carried(p) ?? p.heldItem,
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
      const online = [...room.players.values()].filter((p) => p.online);
      const approached = updateApproaches(room.npcs, online, {
        rules: data.npcRules.approach && { ...data.npcRules.approach, chance_per_s: data.npcRules.approach.chance_per_s * cfg.npcApproachScale },
        now: t,
        dtMs,
        random,
        mode: stayHome ? 'home' : 'roam',
        friendOf: (p, npcId) => p.profile.npcs?.[npcId]?.f ?? 0,
        lastApproached: (p, npcId) => p.approachedAt?.[npcId] ?? -Infinity,
        canBeApproached: (p) => p.talkingTo === null && !p.fishing && !p.home && !inShop(p),
        onGreet: (npc, p) => {
          p.approachedAt ??= {};
          p.approachedAt[npc.id] = t;
          sendTo(p, { t: 'npc_greet', npc: npc.id });
          // 둘레 사람에게도 이 주민이 그 사람에게 손을 흔들며 말을 거는 모습이 보인다 (인사받은 사람은 npc_greet 로 따로 그린다).
          room.broadcast({ t: 'npc_emote', npc: npc.id, e: 'hello', to: p.id, m: npc.mood, from: '' }, p.id);
        },
      });
      if (approached) room.npcsDirty = true;
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
      tickShoals(room, dtMs / 1000, t);
      if (delivery.tick(room, dtMs, t)) room.broadcast({ t: 'couriers', c: delivery.wire(room) });
      for (const spotId of swimmers.tick(room, dtMs, t, online)) room.broadcast({ t: 'fishes', spot: spotId, f: swimmers.wire(room, spotId) });
    }
  }, 1000 / cfg.npcTickRate);

  // 마을톡: 친한 주민이 가끔 먼저 연락한다.
  const messengerTimer = setInterval(() => {
    for (const room of rooms.rooms.values()) messenger.tick(room, { weather: weatherOf(room), restaurantOpen: !!room.shift });
  }, cfg.messengerCheckMs || data.messenger.check_ms);
  messengerTimer.unref?.();

  /** 여울 물고기: 사람이 가까이 있는 여울만 움직이고 알린다. */
  function tickShoals(room, dt, t) {
    const rules = data.dig.net;
    const people = [...room.players.values()].filter((p) => p.online);
    for (const shoal of room.shoals.values()) {
      const z = shoal.zone;
      let changed = refillShoal(shoal, data, rules, t, random);
      const near = people.filter((p) => inZone(z, p.x, p.z, 14));
      if (near.length === 0 && !changed) continue;
      changed = stepShoal(shoal, near.filter((p) => inZone(z, p.x, p.z, rules.flee_radius)), rules, dt, t, random) || changed;
      if (changed) room.broadcast({ t: 'shoal', ...shoalWire(shoal) });
    }
  }

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
      economy.tickWeek(room);
      kitchen.tickRestaurant(room);
      tickDigSpots(room, t);
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

  // 증권시장: 1분마다 시세가 움직이고 모든 방에 알린다.
  let marketBusy = false;
  const marketTick = setInterval(async () => {
    if (marketBusy) return;
    marketBusy = true;
    try {
      const changed = await market.tick();
      if (changed) economy.broadcastMarket(changed);
    } finally {
      marketBusy = false;
    }
  }, cfg.marketTickMs);

  return {
    wss,
    rooms,
    store,
    data,
    clock,
    market,
    economy,
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
      clearInterval(marketTick);
      clearInterval(messengerTimer);
      market.save();
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
