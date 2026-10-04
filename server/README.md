# 솔바람 마을 세션 서버

Node.js ≥ 20, WebSocket(`ws`). 방 코드 입장 · 위치 동기화 · 끊김 후 재접속(30초 자리 유지) · 낚시 판정 · 인벤토리 · JSON 저장.
프로토콜: [`docs/protocol.md`](../docs/protocol.md)

```bash
cd server
npm install
npm start                 # ws://0.0.0.0:8080  (PORT=9000 npm start 로 포트 변경)
npm test                  # 서버 단위 테스트
```

저장 파일: `server/saves/<방코드>.json` (`SAVE_DIR`로 변경, git 무시). 정적 데이터는 저장소의 `data/fish/*.json`을 클라이언트와 함께 읽는다(`DATA_DIR`).

환경변수(`src/config.js`): `SAVE_DIR` `FISH_TIME_SCALE` `INVENTORY_CAPACITY` `PORT` `TICK_RATE` `RECONNECT_GRACE_MS` `HEARTBEAT_MS` `MAX_SPEED` `WORLD_HALF_EXTENT` `RATE_LIMIT_PER_SEC` …

종단 테스트 (서버 + 헤드리스 Godot, `GODOT=/path/to/godot`):
- `tests/run_net_e2e.sh` — 두 클라이언트 동기화·보간·재접속
- `tests/run_fishing_e2e.sh` — 낚시 → 인벤토리 → 서버 재시작 후 복구
- `godot --headless --path . res://tests/anim_check.tscn` — AnimationTree 블렌딩
