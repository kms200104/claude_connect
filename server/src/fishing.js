import { performance } from 'node:perf_hooks';
import { ErrorCode, FishFail } from './protocol.js';
import { distanceToSpot, pickFish } from './gamedata.js';
import { addItem, canAdd, hasFreeSpace } from './inventory.js';
import { earn } from './economy.js';
import { shallowAt } from './shoal.js';

/** 같이 낚시 (v0.9): 같은 낚시터에서 친구가 함께 낚고 있으면 입질이 빨라지고(×0.7) 귀한 물고기가 1.35배 잘 문다. */
export const COOP_FISHING = { wait: 0.7, rare: 1.35, range: 9 };

/**
 * 얕은 곳·깊은 곳 (v0.9): 가장 가까운 물이 여울이면 작은 물고기(S·M)만, 깊은 물이면 큰 물고기(L)가 1.6배 잘 문다.
 * 돌려주는 값: 물고기 → 가중치 배율.
 */
export function zoneWeight(zone, f) {
  if (zone === 'shallow') return f.size === 'L' ? 0 : f.size === 'S' ? 1.4 : 1;
  return f.size === 'L' ? 1.6 : 1;
}

/**
 * 낚시 판정(서버 권위).
 *
 * 흐름: fish_cast → fish_started{shadow} → (가짜 fish_nibble × 0~3) → fish_bite{windowMs} → fish_hook{reaction}
 *       → fish_reel{taps, ms} (v0.11: 끌어올리기 연타) → 클라이언트 fish_reel{taps:[ms…]} → fish_result
 * shadow 는 물 밑 그림자의 크기(희귀하고 클수록 크다)라서 어떤 물고기인지는 알려 주지 않는다.
 * 클라이언트는 "입질 연출이 화면에 뜬 뒤 버튼을 누르기까지 걸린 시간(reaction)"만 보낸다.
 * 서버는 reaction이 허용 창 안인지, 서버가 잰 경과 시간과 모순되지 않는지만 본다 → 네트워크 지연은 불리하게 작용하지 않는다.
 * 물고기 종류는 결과가 확정될 때에만 알려 준다. 낚싯대를 손에 들고 있어야 하고, 시각·날씨에 따라 낚이는 물고기가 다르다.
 */
/** 물 밑 그림자 크기: 희귀도 × 몸 크기. 흔함·S 가 가장 작고 희귀·L 이 가장 크다. */
export function shadowSize(f) {
  const r = { common: 0.75, uncommon: 1.0, rare: 1.35 }[f.rarity] ?? 0.75;
  const s = { S: 0.85, M: 1.0, L: 1.2 }[f.size] ?? 1.0;
  return Math.round(r * s * 100) / 100;
}

/** 끌어올리기 연타: 몇 번을 몇 ms 안에. 희귀하고 클수록 많이, 시간은 조금 더 준다. */
export function reelNeed(f, cfg) {
  const base = { common: [6, 2600], uncommon: [9, 3000], rare: [13, 3400] }[f.rarity] ?? [6, 2600];
  const extra = f.size === 'L' ? 2 : f.size === 'S' ? -1 : 0;
  const taps = Math.max(1, Math.round((base[0] + extra) * cfg.fishReelScale));
  return { taps, ms: base[1] + (f.size === 'L' ? 300 : 0) };
}

export function createFishing({
  cfg,
  data,
  random = Math.random,
  now = () => performance.now(),
  notify,
  onInventoryChanged,
  onFishingChanged,
  heldItem = () => 'rod',
  environment = () => ({ hour: 12, weather: 'clear', season: null }),
  // 낚시 대회가 열려 있으면 그 이벤트 ({ def }) — 희귀한 물고기가 더 잘 잡히고, 낚을 때마다 상금.
  derby = () => null,
  // 같은 낚시터에서 함께 낚고 있는 다른 사람 수 (같이 낚시 보너스).
  companions = () => 0,
  // v0.12: 다른 사람 화면에 보일 낚시 장면 (던지기 · 톡 · 입질 · 끌어올리기 · 낚음/놓침). 판정과는 상관없는 연출용.
  publish = () => {},
}) {
  const scaled = (ms) => ms * cfg.fishTimeScale;
  const rand = (min, max) => min + random() * (max - min);

  function clearTimers(session) {
    for (const t of session.timers) clearTimeout(t);
    session.timers.length = 0;
  }

  function schedule(session, ms, fn) {
    const t = setTimeout(fn, scaled(ms));
    t.unref?.();
    session.timers.push(t);
  }

  function end(player, result) {
    const session = player.fishing;
    if (!session) return;
    clearTimers(session);
    player.fishing = null;
    notify(player, { t: 'fish_result', rid: session.rid, ...result });
    publish(player, result.ok ? { e: 'land', fish: result.fish } : { e: 'end', reason: result.reason });
    onFishingChanged(player);
  }

  /** 에러 코드를 돌려주거나(실패), null(성공) */
  function cast(player, rid, spotId) {
    if (player.fishing) return ErrorCode.alreadyFishing;
    if (heldItem(player) !== 'rod') return ErrorCode.noTool;
    const spot = typeof spotId === 'string' ? (data.fishingSpot?.(spotId) ?? data.spots.get(spotId)) : null;
    if (!spot) return ErrorCode.notAtSpot;
    if (distanceToSpot(spot, player.x, player.z) > spot.cast_range) return ErrorCode.notAtSpot;
    if (!hasFreeSpace(player.slots, data.isFish, data.limitOf)) return ErrorCode.inventoryFull;

    const { hour, weather, season = null } = environment(player);
    const contest = derby(player, spot);
    const coop = companions(player, spot) > 0;
    const boost = (contest ? contest.def.rare_boost ?? 1 : 1) * (coop ? COOP_FISHING.rare : 1);
    const zone = shallowAt(spot, player.x, player.z) ? 'shallow' : 'deep';
    const weight = (f) => f.weight * (f.rarity === 'rare' ? boost : 1) * zoneWeight(zone, f);
    let fish = pickFish(spot, data.fish, random, hour, weather, weight, season);
    if (weight(fish) <= 0) fish = pickFish(spot, data.fish, random, hour, weather, (f) => f.weight * (f.size === 'L' ? 0.0001 : 1), season);
    const pace = coop ? COOP_FISHING.wait : 1;
    const session = {
      rid,
      spot,
      fish,
      phase: 'waiting', // waiting → bite
      timers: [],
      startX: player.x,
      startZ: player.z,
      biteAt: 0,
    };
    player.fishing = session;
    notify(player, { t: 'fish_started', rid, spot: spot.id, zone, coop, shadow: shadowSize(fish) });
    publish(player, { e: 'cast', spot: spot.id });
    onFishingChanged(player);

    // 입질 일정: 가짜 입질 0~N번 뒤에 진짜 입질.
    const fakes = Math.floor(random() * (cfg.fishMaxFakeNibbles + 1));
    let at = rand(cfg.fishFirstNibbleMinMs, cfg.fishFirstNibbleMaxMs) * pace;
    for (let i = 0; i < fakes; i++) {
      schedule(session, at, () => {
        if (player.fishing !== session) return;
        notify(player, { t: 'fish_nibble', rid });
        publish(player, { e: 'nibble' });
      });
      at += rand(cfg.fishGapMinMs, cfg.fishGapMaxMs) * pace;
    }
    schedule(session, at, () => {
      if (player.fishing !== session) return;
      session.phase = 'bite';
      session.biteAt = now();
      notify(player, { t: 'fish_bite', rid, windowMs: fish.hook_window_ms });
      publish(player, { e: 'bite' });
      // 허용 창 + 네트워크 여유 안에 아무 응답이 없으면 도망간다.
      session.timers.push(
        setTimeout(() => player.fishing === session && end(player, { ok: false, reason: FishFail.escaped }), fish.hook_window_ms + cfg.fishHookGraceMs),
      );
    });
    return null;
  }

  function hook(player, rid, reaction) {
    const session = player.fishing;
    if (!session || session.rid !== rid) return ErrorCode.notFishing;
    if (session.phase !== 'bite') {
      end(player, { ok: false, reason: FishFail.early });
      return null;
    }
    if (typeof reaction !== 'number' || !Number.isFinite(reaction) || reaction < 0) return ErrorCode.badMessage;

    const window = session.fish.hook_window_ms;
    const elapsedOnServer = now() - session.biteAt;
    // 서버가 잰 경과 시간보다 더 오래 걸렸다고 주장할 수는 없다. (+여유)
    const plausible = reaction <= elapsedOnServer + cfg.fishReactionSlackMs;
    if (reaction < cfg.fishMinReactionMs || !plausible) {
      // 매크로이거나 값이 모순됨 → 실패로 처리
      end(player, { ok: false, reason: FishFail.early });
      return null;
    }
    if (reaction > window) {
      end(player, { ok: false, reason: FishFail.late });
      return null;
    }
    if (!canAdd(player.slots, session.fish.id, 1, data.limitOf)) {
      end(player, { ok: false, reason: FishFail.inventoryFull });
      return null;
    }
    if (cfg.fishReelScale <= 0) {
      land(player, session);
      return null;
    }
    // 챔질 성공 → 끌어올리기: 정해진 시간 안에 연타를 채워야 한다.
    clearTimers(session);
    const need = reelNeed(session.fish, cfg);
    session.phase = 'reel';
    session.reel = { ...need, at: now() };
    notify(player, { t: 'fish_reel', rid, taps: need.taps, ms: need.ms });
    publish(player, { e: 'reel' });
    session.timers.push(
      setTimeout(() => player.fishing === session && end(player, { ok: false, reason: FishFail.snapped }), need.ms + cfg.fishHookGraceMs),
    );
    return null;
  }

  /** 끌어올리기 결과: taps = 연타 화면이 뜬 뒤 누른 시각들(ms). 수와 간격, 서버가 잰 시간과의 모순을 본다. */
  function reel(player, rid, taps) {
    const session = player.fishing;
    if (!session || session.rid !== rid) return ErrorCode.notFishing;
    if (session.phase !== 'reel') return ErrorCode.notFishing;
    if (!Array.isArray(taps) || taps.length > 200 || !taps.every((t) => typeof t === 'number' && Number.isFinite(t) && t >= 0)) {
      return ErrorCode.badMessage;
    }
    const { taps: need, ms, at } = session.reel;
    const elapsedOnServer = now() - at;
    let prev = -Infinity;
    let counted = 0;
    let honest = true;
    for (const t of taps) {
      if (t < prev) honest = false;
      else if (t - prev >= cfg.fishMinTapGapMs && t <= ms) counted += 1;
      prev = Math.max(prev, t);
    }
    if (taps.length > 0 && taps[taps.length - 1] > elapsedOnServer + cfg.fishReactionSlackMs) honest = false;
    if (!honest || counted < need) {
      end(player, { ok: false, reason: FishFail.snapped });
      return null;
    }
    if (!canAdd(player.slots, session.fish.id, 1, data.limitOf)) {
      end(player, { ok: false, reason: FishFail.inventoryFull });
      return null;
    }
    land(player, session);
    return null;
  }

  // 성공: 인벤토리 지급 + 대회 상금 + 통계 갱신을 한 번에 기록한다.
  function land(player, session) {
    addItem(player.slots, session.fish.id, 1, cfg, data.limitOf);
    player.profile.catches += 1;
    const contest = derby(player, session.spot);
    const bonus = contest ? contest.def.bonus?.[session.fish.rarity] ?? 0 : 0;
    player.profile.sol += bonus;
    earn(player.profile, bonus);
    onInventoryChanged(player, session.fish.id);
    end(player, bonus > 0 ? { ok: true, fish: session.fish.id, bonus } : { ok: true, fish: session.fish.id });
  }

  function cancel(player, reason = FishFail.cancelled) {
    if (player.fishing) end(player, { ok: false, reason });
  }

  /** 접속 끊김 등으로 세션만 조용히 정리 (알림 없음). */
  function drop(player) {
    if (!player.fishing) return;
    clearTimers(player.fishing);
    player.fishing = null;
  }

  function onMove(player) {
    const s = player.fishing;
    if (s && Math.hypot(player.x - s.startX, player.z - s.startZ) > cfg.fishMaxMoveMeters) cancel(player, FishFail.moved);
  }

  return { cast, hook, reel, cancel, drop, onMove };
}
