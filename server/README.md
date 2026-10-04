# 솔바람 마을 세션 서버

Node.js ≥ 20, WebSocket(`ws`). 방 코드 입장 · 위치 동기화 · 끊김 후 재접속(30초 자리 유지).
프로토콜: [`docs/protocol.md`](../docs/protocol.md)

```bash
cd server
npm install
npm start                 # ws://0.0.0.0:8080  (PORT=9000 npm start 로 포트 변경)
npm test                  # 서버 단위 테스트
```

환경변수(`src/config.js`): `PORT` `TICK_RATE` `RECONNECT_GRACE_MS` `HEARTBEAT_MS` `MAX_SPEED` `WORLD_HALF_EXTENT` `RATE_LIMIT_PER_SEC` …

종단 테스트(서버 + 헤드리스 Godot 2개): `GODOT=/path/to/godot tests/run_net_e2e.sh`
