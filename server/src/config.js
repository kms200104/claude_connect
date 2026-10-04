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
  maxSpeed: num('MAX_SPEED', 4.5),
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
};

// 슬롯(1부터)별 스폰 위치.
export const spawnPoints = [
  { x: 0, y: 0.1, z: 0 },
  { x: 2.5, y: 0.1, z: 0 },
  { x: -2.5, y: 0.1, z: 0 },
  { x: 0, y: 0.1, z: 2.5 },
];
