# 솔바람 마을 세션 서버

Node.js ≥ 20, WebSocket(`ws`). 방 코드 입장 · 위치 동기화 · 끊김 후 재접속(30초 자리 유지) · 낚시 판정 · 퀵슬롯+가방 인벤토리 ·
나무 베기 · 주민 이동·대화·부탁 · 마을 시계·날씨·번개 · 상점(사고팔기·상점 포인트·3단계 성장) · 가구 설치 · 옷 ·
마을 이벤트(특가 매입·떠돌이 상인·낚시 대회·나무꾼의 날·선물 풍선·유성우) · 섬 생활(씨앗 심기·꽃·나무 다시 자라기,
감정표현과 주민 반응, 주민 기분·대화 주제·감정표현 가르치기·선물, 박물관 기증, 공항 기념품) · JSON 저장.
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
- `GROWTH_SCALE=0.01` — 나무·꽃이 100배 빨리 자란다. `START_FRIENDSHIP=30` — 처음 들어온 사람의 주민 친밀도 (감정표현 배우기·선물을 바로 보려고). `START_ITEMS=acorn:3,seed_tulip:2,crucian:1` — 처음 들어온 사람에게 줄 물건.
- `EVENT_FORCE=merchant` — 오늘의 이벤트 고정 (`bargain` `merchant` `fishing_derby` `lumber_day` `gift_day` `meteor_shower`, 쉼표로 여럿). `EVENT_WANTED=wood,crucian` — 특가 매입·떠돌이 상인이 찾는 물건 고정. `EVENT_SPAWN_SCALE=0.02` — 선물·별 조각을 빨리 떨어뜨림.

종단 테스트 (서버 + 헤드리스 Godot, `GODOT=/path/to/godot`):
- `tests/run_net_e2e.sh` — 두 클라이언트 동기화·보간·재접속
- `tests/run_fishing_e2e.sh` — 낚시 → 인벤토리 → 서버 재시작 후 복구
- `tests/run_village_e2e.sh` — 비 · 퀵슬롯으로 도끼 들기 · 나무 베기 → 인벤토리 · 가방 창(캐릭터가 고른 칸을 바라봄) · 주민 대화 → 부탁 → 완료
- `tests/run_shop_e2e.sh` — 달리기 · 상점 들어가기 · 주인과 대화 → 팔기 → 상점 성장 → 사기 · 나가기 · 옷 입기 · 가구 설치·줍기
- `tests/run_events_e2e.sh` — 떠돌이 상인(이벤트 칩·알림판·노점·찾는 물건 2배로 팔기·보따리 사기) · 선물 풍선 줍기 · 나무 넘어지는 연출 · 상점 문으로 걸어 드나들기
- `tests/run_island_e2e.sh` — 섬·박물관·공항 · 달리다 반대로 꺾으면 브레이크 · 감정표현과 주민 반응 · 대화(기분 이름표·감정표현 배우기·주제 수다) · 도토리 심기 → 나무로 자람 · 튤립 심기 → 피면 따기 · 박물관 기증(수조) · 공항 기념품
- `tests/run_mirror_e2e.sh` — 광장 거울 앞 "거울 보기" · 얼굴 클로즈업 · 눈·코·입·피부·머리 고르기(미리 보기) · 닫으면 되돌림 · 완료하면 저장 · 거울에서 멀면 거절 · 거울 가구를 놓고 그 앞에서도 · 가방에 넣기
- 렌더러 없이 도는 검사: `godot --headless --path . res://tests/face_check.tscn` (얼굴 부품이 머리 겉면 밖인지 · 캐릭터 삼각형 4,000 이하, 절약·고화질 둘 다), `res://tests/quality_check.tscn` (화질 두 단계 · S24/폴드7 3D 해상도 · 리소스팩), `res://tests/audio_check.tscn` (발소리 재질 · 비 오는 날 물웅덩이 · 낮/밤/비/이벤트 음악 고르기 · 음악 연달아 바꾸기 · 소리 파일)
- `tests/run_title_e2e.sh` — 첫 화면: 새 마을 만들기 → 다시 켜면 서버 주소·마지막 방이 채워져 있고 "시작하기"로 같은 방에 들어감
- `godot --headless --path . res://tests/anim_check.tscn` — AnimationTree 블렌딩 (걷기·달리기 팔다리·낚시·도끼질·브레이크·감정표현·자랑)

화면 확인(테스트 아님, 실제 렌더러 필요): 서버를 `WEATHER_FORCE=clear QUEST_CHANCE=1 MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0` 으로 띄우고
`godot --path . res://tools/capture_screens.tscn -- --server=ws://127.0.0.1:8080 --out=/tmp/shots` — 아침·도끼질·비·뇌우·노을·밤·대화·부탁 목록·가방 창을 PNG로 찍는다.
섬 생활 화면은 `tools/capture_island.sh /tmp/island_shots` (섬 하늘·박물관·수조·공항·이륙·바닷가, 브레이크·감정표현·대화·감정표현 창·정원·도감, 낚시 자랑, 거울·얼굴 꾸미기·화질 창).
`MODES="mirror"` 처럼 일부만, `RES=984x1092`(갤럭시 Z 폴드7 펼친 화면 비율) · `RES=540x1170`(갤럭시 S24 비율)로 화면 비율을 바꿔 찍을 수 있다.
얼굴·머리 모양 모음은 `godot --path . res://tools/art_preview.tscn -- --what=faces|faces_side|hairs --out=…` (가로 화면 `--resolution 2200x1300` 권장).
이벤트 화면은 `tools/capture_events.sh /tmp/event_shots` (서버를 이벤트별로 띄워 떠돌이 상인·특가 매입·선물 풍선·넘어지는 나무·찌 던지기·유성우를 찍는다).
상점·옷·가구는 서버를 `WEATHER_FORCE=clear START_SOL=40000 MOVE_SLACK_M=200 DOOR_GRACE_MS=0` 으로 띄우고 `res://tools/capture_shop.tscn` (구멍가게 → 잡화점 → 백화점, 옷·가구).

아트·소리 도구 (DESIGN.md 11.4, 3.17):
- `python3 tools/art/extract_reference.py` — 참고 이미지(`art_source/reference/`)에서 로고·아이콘을 투명 PNG로 오림
- `python3 tools/art/gen_ground.py` — `data/world/village_layout.json` 으로 바닥 텍스처를 만듦
- `python3 tools/audio/gen_audio.py` — 효과음·배경음악 합성 (numpy, scipy, ffmpeg). `python3 tools/audio/gen_audio.py v06_sounds` 처럼 묶음 이름을 주면 그 묶음만 (v0.6 소리는 따로 고정한 난수라 기존 소리가 바뀌지 않는다)
- `python3 tools/art/gen_emote_icons.py` — 감정표현 말풍선 아이콘 11장
- `python3 tools/art/gen_character_rig.py` — 캐릭터 리그 씬(애니메이션 키 표: 걷기·달리기·낚시·도끼질·던지기·브레이크·자랑·심기·감정표현 11종)
- `godot --path . res://tools/render_icons.tscn` — 아이템 모형을 찍어 아이콘 PNG 로 (실제 렌더러 필요)
- `godot --path . res://tools/art_preview.tscn -- --what=characters --out=/tmp/p.png` — 모형 확인 (trees / characters / outfits / furniture / shop / village)
