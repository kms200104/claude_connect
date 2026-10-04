import { performance } from 'node:perf_hooks';
import { ErrorCode, FishFail } from './protocol.js';
import { distanceToSpot, pickFish } from './gamedata.js';
import { addItem, canAdd, hasFreeSpace } from './inventory.js';

/**
 * 낚시 판정(서버 권위).
 *
 * 흐름: fish_cast → fish_started → (가짜 fish_nibble × 0~3) → fish_bite{windowMs} → fish_hook{reaction}
 * 클라이언트는 "입질 연출이 화면에 뜬 뒤 버튼을 누르기까지 걸린 시간(reaction)"만 보낸다.
 * 서버는 reaction이 허용 창 안인지, 서버가 잰 경과 시간과 모순되지 않는지만 본다 → 네트워크 지연은 불리하게 작용하지 않는다.
 * 물고기 종류는 결과가 확정될 때에만 알려 준다. 낚싯대를 손에 들고 있어야 하고, 시각·날씨에 따라 낚이는 물고기가 다르다.
 */
export function createFishing({
  cfg,
  data,
  random = Math.random,
  now = () => performance.now(),
  notify,
  onInventoryChanged,
  onFishingChanged,
  heldItem = () => 'rod',
  environment = () => ({ hour: 12, weather: 'clear' }),
  // 낚시 대회가 열려 있으면 그 이벤트 ({ def }) — 희귀한 물고기가 더 잘 잡히고, 낚을 때마다 상금.
  derby = () => null,
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
    onFishingChanged(player);
  }

  /** 에러 코드를 돌려주거나(실패), null(성공) */
  function cast(player, rid, spotId) {
    if (player.fishing) return ErrorCode.alreadyFishing;
    if (heldItem(player) !== 'rod') return ErrorCode.noTool;
    const spot = typeof spotId === 'string' ? data.spots.get(spotId) : null;
    if (!spot) return ErrorCode.notAtSpot;
    if (distanceToSpot(spot, player.x, player.z) > spot.cast_range) return ErrorCode.notAtSpot;
    if (!hasFreeSpace(player.slots, data.isFish, data.limitOf)) return ErrorCode.inventoryFull;

    const { hour, weather } = environment(player);
    const contest = derby(player);
    const boost = contest ? contest.def.rare_boost ?? 1 : 1;
    const fish = pickFish(spot, data.fish, random, hour, weather, (f) => f.weight * (f.rarity === 'rare' ? boost : 1));
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
    notify(player, { t: 'fish_started', rid, spot: spot.id });
    onFishingChanged(player);

    // 입질 일정: 가짜 입질 0~N번 뒤에 진짜 입질.
    const fakes = Math.floor(random() * (cfg.fishMaxFakeNibbles + 1));
    let at = rand(cfg.fishFirstNibbleMinMs, cfg.fishFirstNibbleMaxMs);
    for (let i = 0; i < fakes; i++) {
      schedule(session, at, () => player.fishing === session && notify(player, { t: 'fish_nibble', rid }));
      at += rand(cfg.fishGapMinMs, cfg.fishGapMaxMs);
    }
    schedule(session, at, () => {
      if (player.fishing !== session) return;
      session.phase = 'bite';
      session.biteAt = now();
      notify(player, { t: 'fish_bite', rid, windowMs: fish.hook_window_ms });
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
    // 성공: 인벤토리 지급 + 대회 상금 + 통계 갱신을 한 번에 기록한다.
    addItem(player.slots, session.fish.id, 1, cfg, data.limitOf);
    player.profile.catches += 1;
    const contest = derby(player);
    const bonus = contest ? contest.def.bonus?.[session.fish.rarity] ?? 0 : 0;
    player.profile.sol += bonus;
    onInventoryChanged(player, session.fish.id);
    end(player, bonus > 0 ? { ok: true, fish: session.fish.id, bonus } : { ok: true, fish: session.fish.id });
    return null;
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

  return { cast, hook, cancel, drop, onMove };
}
