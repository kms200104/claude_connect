# 솔바람 마을 세션 서버

Node.js ≥ 20, WebSocket(`ws`). 방 코드 입장 · 위치 동기화 · 끊김 후 재접속(30초 자리 유지) · 낚시 판정 · 퀵슬롯+가방 인벤토리 ·
나무 베기 · 주민 이동·대화·부탁 · 마을 시계·날씨·번개 · 상점(사고팔기·상점 포인트·3단계 성장) · 가구 설치 · 옷 ·
마을 이벤트(특가 매입·떠돌이 상인·낚시 대회·나무꾼의 날·선물 풍선·유성우) · JSON 저장.
프로토콜: [`docs/protocol.md`](../docs/protocol.md)

```bash
cd server
npm install
npm start                 # ws://0.0.0.0:8080  (PORT=9000 npm start 로 포트 변경)
npm test                  # 서버 단위·통합 테스트
```

저장 파일: `server/saves/<방코드>.json` (`SAVE_DIR`로 변경, git 무시). 정적 데이터는 저장소의 `data/` 아래 JSON(물고기·아이템·나무·주민·부탁)을 클라이언트와 함께 읽는다(`DATA_DIR`).

환경변수(`src/config.js`): `SAVE_DIR` `FISH_TIME_SCALE` `QUICK_SLOTS` `INVENTORY_CAPACITY` `PORT` `TICK_RATE` `RECONNECT_GRACE_MS` `HEARTBEAT_MS` `MAX_SPEED` `WORLD_HALF_EXTENT` `RATE_LIMIT_PER_SEC` `CHOP_COOLDOWN_MS` `NPC_TICK_RATE` `TALK_TIMEOUT_MS` …

시연·테스트용:
- `CLOCK_SCALE=60` — 마을 시계를 60배로 (실제 1분 = 마을 1시간). `CLOCK_OFFSET_MIN=600` — 마을 시각을 10시간 뒤로.
- `WEATHER_FORCE=rain` — 날씨 고정 (`clear` `cloudy` `rain` `thunder`).
- `QUEST_CHANCE=1` — 말 걸 때마다 부탁 제안. `QUEST_TEMPLATE=wood` — 부탁 종류 고정 (`data/quests/quests.json` 의 id).
- `START_SOL=20000` — 처음 들어온 사람의 솔. `SHOP_POINTS_SCALE=20` — 상점 포인트를 20배로 쌓아 상점이 빨리 커진다.
- `EVENT_FORCE=merchant` — 오늘의 이벤트 고정 (`bargain` `merchant` `fishing_derby` `lumber_day` `gift_day` `meteor_shower`, 쉼표로 여럿). `EVENT_WANTED=wood,crucian` — 특가 매입·떠돌이 상인이 찾는 물건 고정. `EVENT_SPAWN_SCALE=0.02` — 선물·별 조각을 빨리 떨어뜨림.

종단 테스트 (서버 + 헤드리스 Godot, `GODOT=/path/to/godot`):
- `tests/run_net_e2e.sh` — 두 클라이언트 동기화·보간·재접속
- `tests/run_fishing_e2e.sh` — 낚시 → 인벤토리 → 서버 재시작 후 복구
- `tests/run_village_e2e.sh` — 비 · 퀵슬롯으로 도끼 들기 · 나무 베기 → 인벤토리 · 가방 창(캐릭터가 고른 칸을 바라봄) · 주민 대화 → 부탁 → 완료
- `tests/run_shop_e2e.sh` — 달리기 · 상점 들어가기 · 주인과 대화 → 팔기 → 상점 성장 → 사기 · 나가기 · 옷 입기 · 가구 설치·줍기
- `tests/run_events_e2e.sh` — 떠돌이 상인(이벤트 칩·알림판·노점·찾는 물건 2배로 팔기·보따리 사기) · 선물 풍선 줍기 · 나무 넘어지는 연출 · 상점 문으로 걸어 드나들기
- `tests/run_title_e2e.sh` — 첫 화면: 새 마을 만들기 → 다시 켜면 서버 주소·마지막 방이 채워져 있고 "시작하기"로 같은 방에 들어감
- `godot --headless --path . res://tests/anim_check.tscn` — AnimationTree 블렌딩 (걷기·달리기 팔다리·낚시·도끼질)

화면 확인(테스트 아님, 실제 렌더러 필요): 서버를 `WEATHER_FORCE=clear QUEST_CHANCE=1 MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0` 으로 띄우고
`godot --path . res://tools/capture_screens.tscn -- --server=ws://127.0.0.1:8080 --out=/tmp/shots` — 아침·도끼질·비·뇌우·노을·밤·대화·부탁 목록·가방 창을 PNG로 찍는다.
이벤트 화면은 `tools/capture_events.sh /tmp/event_shots` (서버를 이벤트별로 띄워 떠돌이 상인·특가 매입·선물 풍선·넘어지는 나무·찌 던지기·유성우를 찍는다).
상점·옷·가구는 서버를 `WEATHER_FORCE=clear START_SOL=40000 MOVE_SLACK_M=200 DOOR_GRACE_MS=0` 으로 띄우고 `res://tools/capture_shop.tscn` (구멍가게 → 잡화점 → 백화점, 옷·가구).

아트·소리 도구 (DESIGN.md 11.4, 3.17):
- `python3 tools/art/extract_reference.py` — 참고 이미지(`art_source/reference/`)에서 로고·아이콘을 투명 PNG로 오림
- `python3 tools/art/gen_ground.py` — `data/world/village_layout.json` 으로 바닥 텍스처를 만듦
- `python3 tools/audio/gen_audio.py` — 효과음·배경음악 합성 (numpy, scipy, ffmpeg)
- `godot --path . res://tools/render_icons.tscn` — 아이템 모형을 찍어 아이콘 PNG 로 (실제 렌더러 필요)
- `godot --path . res://tools/art_preview.tscn -- --what=characters --out=/tmp/p.png` — 모형 확인 (trees / characters / outfits / furniture / shop / village)
