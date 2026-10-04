import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// 모든 수치는 환경변수로 덮어쓸 수 있다 (테스트에서는 짧은 값을 쓴다).
const num = (name, fallback) => {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && process.env[name] !== undefined && process.env[name] !== '' ? v : fallback;
};

export const defaultConfig = {
  port: num('PORT', 8080),
  // 방 하나에 들어올 수 있는 인원 (MVP: 2인 협동).
  maxPlayers: num('MAX_PLAYERS', 2),
  // 위치 스냅샷 방송 주기.
  tickRate: num('TICK_RATE', 20),
  // 접속이 끊긴 플레이어의 자리를 지켜 주는 시간(ms). 이 안에 resume 하면 이어서 플레이.
  reconnectGraceMs: num('RECONNECT_GRACE_MS', 30000),
  // ws ping 주기(ms). 응답 없는 소켓은 다음 주기에 끊는다.
  heartbeatMs: num('HEARTBEAT_MS', 10000),
  // 이동 검증: 클라이언트 최대 속도(m/s)에 여유를 곱한 값 + 고정 여유 거리(m).
  // 달리기 속도(7m/s)까지 받는다. 걷기는 4.5m/s.
  maxSpeed: num('MAX_SPEED', 7.2),
  speedTolerance: num('SPEED_TOLERANCE', 1.6),
  moveSlackMeters: num('MOVE_SLACK_M', 0.6),
  // 이동 가능 경계 (원점 중심 정사각형 반경)와 높이 범위.
  worldHalfExtent: num('WORLD_HALF_EXTENT', 78),
  minY: num('MIN_Y', -5),
  maxY: num('MAX_Y', 30),
  // 연결당 초당 메시지 상한 (토큰 버킷).
  rateLimitPerSec: num('RATE_LIMIT_PER_SEC', 60),
  rateLimitBurst: num('RATE_LIMIT_BURST', 120),
  // 이 횟수만큼 상한을 초과하면 연결을 끊는다.
  rateLimitKickAfter: num('RATE_LIMIT_KICK_AFTER', 300),
  maxMessageBytes: num('MAX_MESSAGE_BYTES', 1024),

  // 저장·데이터 위치. 저장은 방 코드별 JSON 파일(<saveDir>/<CODE>.json).
  saveDir: process.env.SAVE_DIR || path.resolve(here, '../saves'),
  dataDir: process.env.DATA_DIR || path.resolve(here, '../../data'),
  // 변경이 있는 방을 이 주기로 저장한다. 인벤토리 변경은 즉시 저장.
  saveIntervalMs: num('SAVE_INTERVAL_MS', 5000),

  // 인벤토리: 퀵슬롯 칸 수 + 가방 칸 수. 물고기 한 칸에 쌓을 수 있는 개수(도구·목재는 items.json 의 stack).
  quickSlots: num('QUICK_SLOTS', 5),
  inventoryCapacity: num('INVENTORY_CAPACITY', 20),
  inventoryStackSize: num('INVENTORY_STACK_SIZE', 99),

  // 낚시. 입질까지 기다리는 시간은 fishTimeScale 배로 줄이거나 늘릴 수 있다(테스트는 0.01).
  fishTimeScale: num('FISH_TIME_SCALE', 1),
  fishFirstNibbleMinMs: num('FISH_FIRST_NIBBLE_MIN_MS', 2000),
  fishFirstNibbleMaxMs: num('FISH_FIRST_NIBBLE_MAX_MS', 4000),
  fishGapMinMs: num('FISH_GAP_MIN_MS', 1500),
  fishGapMaxMs: num('FISH_GAP_MAX_MS', 3000),
  fishMaxFakeNibbles: num('FISH_MAX_FAKE_NIBBLES', 3),
  // 입질 후 챔질 허용 창에 더해 주는 네트워크 여유. 지연이 판정에 불리하게 작용하지 않도록.
  fishHookGraceMs: num('FISH_HOOK_GRACE_MS', 1500),
  // 사람이 낼 수 있는 가장 빠른 반응 시간 (이보다 빠르면 매크로로 보고 거부).
  fishMinReactionMs: num('FISH_MIN_REACTION_MS', 80),
  // 클라이언트가 보고한 반응 시간이 서버가 측정한 경과 시간을 이만큼까지 넘는 건 허용.
  fishReactionSlackMs: num('FISH_REACTION_SLACK_MS', 100),
  // 낚시 중 캐스팅 지점에서 이 이상 움직이면 낚시가 취소된다.
  fishMaxMoveMeters: num('FISH_MAX_MOVE_M', 1.5),

  // 마을 시계. 기본은 실제 시간(배율 1, 한국 시간). 테스트·시연은 배율을 키우거나 시각을 옮긴다.
  clockScale: num('CLOCK_SCALE', 1),
  utcOffsetMin: num('UTC_OFFSET_MIN', 540),
  clockOffsetMin: num('CLOCK_OFFSET_MIN', 0),
  // 날씨를 고정한다 (clear | cloudy | rain | thunder). 비우면 마을 시드로 정한다.
  weatherForce: process.env.WEATHER_FORCE || '',
  // 뇌우일 때 번개 간격(ms).
  lightningMinMs: num('LIGHTNING_MIN_MS', 6000),
  lightningMaxMs: num('LIGHTNING_MAX_MS', 18000),

  // 나무 베기: 한 번 찍은 뒤 다음 도끼질까지 최소 간격(도끼 휘두르는 시간).
  chopCooldownMs: num('CHOP_COOLDOWN_MS', 400),

  // 주민 NPC: 이동 계산·방송 주기, 걷다 멈춰 서 있는 시간.
  npcTickRate: num('NPC_TICK_RATE', 10),
  npcIdleMinMs: num('NPC_IDLE_MIN_MS', 2500),
  npcIdleMaxMs: num('NPC_IDLE_MAX_MS', 7000),
  // 대화: 이 시간 동안 아무 요청이 없거나, 이만큼 멀어지면 대화를 끝낸다.
  talkTimeoutMs: num('TALK_TIMEOUT_MS', 60000),
  talkLeaveMeters: num('TALK_LEAVE_M', 6),
  // 부탁(퀘스트) 확률. 비우면 data/quests/quests.json 의 값.
  questChance: process.env.QUEST_CHANCE !== undefined && process.env.QUEST_CHANCE !== '' ? Number(process.env.QUEST_CHANCE) : null,
  // 상점 문을 지난 직후 이 시간 동안은 문 반대편(10m 넘게 떨어진 곳)에서 온 낡은 이동 요청을 버린다.
  doorGraceMs: num('DOOR_GRACE_MS', 1500),
  // 상점 포인트 배율 (시연·테스트용. 1이면 거래한 솔만큼 포인트).
  shopPointsScale: num('SHOP_POINTS_SCALE', 1),
  // 한 사람이 마을에 설치할 수 있는 가구 수.
  maxPlacedPerPlayer: num('MAX_PLACED_PER_PLAYER', 30),
  // 부탁 종류를 하나로 고정한다 (quests.json 의 템플릿 id, 시연·테스트용). 비우면 전부.
  questTemplate: process.env.QUEST_TEMPLATE || '',
};

// 슬롯(1부터)별 스폰 위치.
export const spawnPoints = [
  { x: 0, y: 0.1, z: 0 },
  { x: 2.5, y: 0.1, z: 0 },
  { x: -2.5, y: 0.1, z: 0 },
  { x: 0, y: 0.1, z: 2.5 },
];
