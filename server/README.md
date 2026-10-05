# 솔바람 마을 세션 서버

Node.js ≥ 20, WebSocket(`ws`). 방 코드 입장 · 위치 동기화 · 끊김 후 재접속(30초 자리 유지) · 낚시 판정 · 퀵슬롯+가방 인벤토리 ·
나무 베기 · 주민 이동·대화·부탁 · 마을 시계·날씨·번개 · 상점(사고팔기·상점 포인트·3단계 성장) · 가구 설치 · 옷 ·
마을 이벤트(특가 매입·떠돌이 상인·낚시 대회·나무꾼의 날·선물 풍선·유성우) · 섬 생활(씨앗 심기·꽃·나무 다시 자라기,
감정표현과 주민 반응, 주민 기분·대화 주제·감정표현 가르치기·선물, 박물관 기증, 공항 기념품) · 주민 MBTI(T/F 공감) ·
마을 경제(v0.8: 현실 화폐 단위, 분 단위 모의 증권, 성성호수 아파트 사고팔기·월세, 신용점수·변동금리 대출·주간 이자, 식당 영업·요리 판정·단골, 들판 채집) · 같이 하기·동사무소·여울·삽(v0.9: 식당 직원·재료 합치기·동작 나눠 맡기·팀 보너스, 같이 베기·같이 낚시, 동사무소 민원·혼인신고 세대 지갑·천안시 기준 지원금·디딤돌/햇살론유스 고정금리, 얕은 물·여울 물고기 떼·뜰채 몰이, 삽으로 조개·구덩이·흙길) · 아파트 집 안(v0.10: 평면도 26·27·34·35평, 공동 현관 엘리베이터, 집 가구 놓기·옮기기·회수) · JSON 저장.

**항상 켜 두기**(서울 VM + systemd + Caddy wss / 도커 / Fly.io)와 안드로이드 테스트(앱 안 테스트 서버, Internet 권한): [`docs/deploy.md`](../docs/deploy.md). 파일은 `server/Dockerfile`, `server/deploy/`.
프로토콜: [`docs/protocol.md`](../docs/protocol.md)

```bash
cd server
npm install
npm start                 # ws://0.0.0.0:8080  (PORT=9000 npm start 로 포트 변경)
npm test                  # 서버 단위·통합 테스트
```

Windows 에서는 저장소 맨 위의 `server.bat` 을 더블클릭하면 코드 받기 · 패키지 설치 · (전에 켠 서버가 8080 을 잡고 있으면 끄고) 서버 켜기 · 폰에 적을 주소 안내까지 한다.

저장 파일: `server/saves/<방코드>.json` (`SAVE_DIR`로 변경, git 무시). 정적 데이터는 저장소의 `data/` 아래 JSON(물고기·아이템·나무·주민·부탁)을 클라이언트와 함께 읽는다(`DATA_DIR`).

환경변수(`src/config.js`): `SAVE_DIR` `FISH_TIME_SCALE` `QUICK_SLOTS` `INVENTORY_CAPACITY` `PORT` `TICK_RATE` `RECONNECT_GRACE_MS` `HEARTBEAT_MS` `MAX_SPEED` `WORLD_HALF_EXTENT` `RATE_LIMIT_PER_SEC` `CHOP_COOLDOWN_MS` `NPC_TICK_RATE` `TALK_TIMEOUT_MS` …

시연·테스트용:
- `CLOCK_SCALE=60` — 마을 시계를 60배로 (실제 1분 = 마을 1시간). `CLOCK_OFFSET_MIN=600` — 마을 시각을 10시간 뒤로.
- `WEATHER_FORCE=rain` — 날씨 고정 (`clear` `cloudy` `rain` `thunder`).
- `QUEST_CHANCE=1` — 말 걸 때마다 부탁 제안. `QUEST_TEMPLATE=wood` — 부탁 종류 고정 (`data/quests/quests.json` 의 id).
- `START_SOL=2000000` — 처음 들어온 사람의 솔 (v0.8 부터 1솔 ≈ 1원). `SHOP_POINTS_SCALE=20` — 상점 포인트를 20배로 쌓아 상점이 빨리 커진다.
- `GROWTH_SCALE=0.01` — 나무·꽃이 100배 빨리 자란다. `START_FRIENDSHIP=30` — 처음 들어온 사람의 주민 친밀도 (감정표현 배우기·선물을 바로 보려고). `START_ITEMS=acorn:3,seed_tulip:2,crucian:1` — 처음 들어온 사람에게 줄 물건.
- `node tools/make_test_snapshot.js` — 앱 안 테스트 서버가 쓸 입장 정보(`data/testserver/welcome.json`)를 다시 찍는다 (데이터·프로토콜이 바뀌면).
- `MARKET_TICK_MS=1000` — 시세가 움직이는 간격 (기본 60000 = 1분). `MARKET_HOURS=krx` — 평일 9:00~15:30 (마을 시계)에만 장이 열림 (기본 언제나).
- `REST_SPAWN_SCALE=0.05` — 식당 손님이 20배 빨리 온다. `REST_START_HISTORY=5,5,4` — 처음 식당 별점 기록 (높은 단계 요리를 바로 보려고).
- `EVENT_FORCE=merchant` — 오늘의 이벤트 고정 (`bargain` `merchant` `fishing_derby` `lumber_day` `gift_day` `meteor_shower`, 쉼표로 여럿). `EVENT_WANTED=wood,crucian` — 특가 매입·떠돌이 상인이 찾는 물건 고정. `EVENT_SPAWN_SCALE=0.02` — 선물·별 조각을 빨리 떨어뜨림.

### 증권 시세 서버 연동 (`MARKET_FEED_URL`)
기본은 서버에 들어 있는 모의 거래소(종목마다 변동성·추세·평균 회귀·가끔 뉴스)로 1분마다 움직인다. 실제·외부 시세를 쓰려면
`MARKET_FEED_URL=http://시세서버/quotes` 를 주면 1분마다 `GET` 해서 다음 형식을 읽는다:

```json
{ "ts": 1767000000000, "quotes": { "SBE": 71200, "HSB": 18450, "CAM": 214500 } }
```

(`quotes` 는 `[{ "id": "SBE", "price": 71200 }]` 배열이어도 된다.) 키는 `data/market/stocks.json` 의 종목 `id`. 실제 종목 코드는 각 종목의 `feed_symbol`
(예: `005930.KS`)에 적어 두었으니, 시세 서버가 그 코드로 실제 시세를 가져와 게임 종목 id 로 바꿔 주면 된다. 값은 호가 단위·하루 ±30% 제한으로 다듬는다.
읽지 못한 분(타임아웃 5초, HTTP 오류)은 모의 거래소로 대신 움직이고 로그에 한 번만 알린다.
연습용 시세 서버: `node tools/market_server.js --port 8090 --tick-ms 60000` → `MARKET_FEED_URL=http://127.0.0.1:8090/quotes`.
(클라우드 개발 환경처럼 외부 금융 사이트가 막힌 곳에서는 실제 시세를 가져올 수 없다 — 네트워크 허용 목록에 시세 사이트를 넣어야 한다.)

종단 테스트 (서버 + 헤드리스 Godot, `GODOT=/path/to/godot`):
- `tests/run_net_e2e.sh` — 두 클라이언트 동기화·보간·재접속
- `tests/run_fishing_e2e.sh` — 낚시 → 인벤토리 → 서버 재시작 후 복구
- `tests/run_village_e2e.sh` — 비 · 퀵슬롯으로 도끼 들기 · 나무 베기 → 인벤토리 · 가방 창(캐릭터가 고른 칸을 바라봄) · 주민 대화 → 부탁 → 완료
- `tests/run_shop_e2e.sh` — 달리기 · 상점 들어가기 · 주인과 대화 → 팔기 → 상점 성장 → 사기 · 나가기 · 옷 입기 · 가구 설치·줍기
- `tests/run_events_e2e.sh` — 떠돌이 상인(이벤트 칩·알림판·노점·찾는 물건 2배로 팔기·보따리 사기) · 선물 풍선 줍기 · 나무 넘어지는 연출 · 상점 문으로 걸어 드나들기
- `tests/run_island_e2e.sh` — 섬·박물관·공항 · 달리다 반대로 꺾으면 브레이크 · 감정표현과 주민 반응 · 대화(기분 이름표·감정표현 배우기·주제 수다) · 도토리 심기 → 나무로 자람 · 튤립 심기 → 피면 따기 · 박물관 기증(수조) · 공항 기념품
- `tests/run_mirror_e2e.sh` — 광장 거울 앞 "거울 보기" · 얼굴 클로즈업 · 눈·코·입·피부·머리 고르기(미리 보기) · 닫으면 되돌림 · 완료하면 저장 · 거울에서 멀면 거절 · 거울 가구를 놓고 그 앞에서도 · 가방에 넣기
- 렌더러 없이 도는 검사: `godot --headless --path . res://tests/face_check.tscn` (얼굴 부품이 머리 겉면 밖인지 · 캐릭터 삼각형 4,000 이하, 절약·고화질 둘 다), `res://tests/quality_check.tscn` (화질 두 단계 · S24/폴드7 3D 해상도 · 리소스팩), `res://tests/audio_check.tscn` (발소리 재질 · 비 오는 날 물웅덩이 · 낮/밤/비/이벤트 음악 고르기 · 음악 연달아 바꾸기 · 소리 파일)
- `tests/run_economy_e2e.sh` — 증권(시세 받기·휴대폰·매수·매도·거래세) · 은행(신용등급·금리·대출·상환) · 부동산(부스 '부동산' · 아파트 사기 · 발코니 깃발) · 식당(식당 열기 · 재료만큼만 주문 · 요리 미니게임 → 별점 · 앉은 손님) · 들판 채집 · 성성호수 낚시터
- `tests/run_coop_e2e.sh` — 두 사람 (v0.9): 동사무소 창구 상황 버튼 · 전입신고 · 천안사랑카드 · 혼인신고 제안/수락 → 솔이 한 지갑으로 · 햇살론유스(고정) 가 배우자 지갑에도 · 식당 같이 일하기(재료 합치기 · 한 그릇의 동작을 나눠 맡기 · 팀 보너스) · 여울에 들어가 걷기 · 둘이 몰아 뜰채질 · 바닷가 조개 같이 캐기 · 삽으로 구덩이·메우기·흙길
- `tests/run_test_server_e2e.sh` — 앱 안 테스트 서버 (Node 서버 없이): 주민 대화 · 나무 베기 → 그루터기 · 낚시 · 들판 채집 · 거울 · 다시 접속해도 가방 그대로
- `tests/run_home_e2e.sh` — 집 안 (v0.10): 서버가 없을 때 접속 실패 → "테스트 서버로 하기" → 앱 안 테스트 서버 → 집 구경 · 꾸미기 / 진짜 서버에서 집 사기 → 공동 현관 '집 구경' → 엘리베이터 → 평면도대로 지은 벽 · 기본 가구 → 위에서 본 꾸미기(끌어 옮기기 · 보이지 않는 격자 · 벽 밖 거절 · 좌우 돌리기 · 가방에 넣기 · 가방에서 놓기) → 현관문 나가기
- `godot --headless --path . res://tests/script_check.tscn` — 모든 GDScript 를 오토로드가 있는 상태에서 불러 문법·타입 오류 검사
- `tests/run_title_e2e.sh` — 첫 화면: 높은 곳에서 비스듬히 내려다보며 나는 항공뷰 · 구름 · 새 마을 만들기 → 다시 켜면 서버 주소·마지막 방이 채워져 있고 "시작하기"로 같은 방에 들어감
- `godot --headless --path . res://tests/anim_check.tscn` — AnimationTree 블렌딩 (걷기·달리기 팔다리·낚시·도끼질·브레이크·감정표현·자랑)

화면 확인(테스트 아님, 실제 렌더러 필요): 서버를 `WEATHER_FORCE=clear QUEST_CHANCE=1 MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0` 으로 띄우고
`godot --path . res://tools/capture_screens.tscn -- --server=ws://127.0.0.1:8080 --out=/tmp/shots` — 아침·도끼질·비·뇌우·노을·밤·대화·부탁 목록·가방 창을 PNG로 찍는다.
섬 생활 화면은 `tools/capture_island.sh /tmp/island_shots` (섬 하늘·박물관·수조·공항·이륙·바닷가, 브레이크·감정표현·대화·감정표현 창·정원·도감, 낚시 자랑, 거울·얼굴 꾸미기·화질 창).
`MODES="mirror"` 처럼 일부만, `RES=984x1092`(갤럭시 Z 폴드7 펼친 화면 비율) · `RES=540x1170`(갤럭시 S24 비율)로 화면 비율을 바꿔 찍을 수 있다.
얼굴·머리 모양 모음은 `godot --path . res://tools/art_preview.tscn -- --what=faces|faces_side|hairs --out=…` (가로 화면 `--resolution 2200x1300` 권장).
이벤트 화면은 `tools/capture_events.sh /tmp/event_shots` (서버를 이벤트별로 띄워 떠돌이 상인·특가 매입·선물 풍선·넘어지는 나무·찌 던지기·유성우를 찍는다).
마을 경제 화면은 `tools/capture_town.sh /tmp/town_shots` (식당·아파트·성성호수 하늘에서, 아파트 단지, 부동산 부스, 손님이 앉은 식당, 주방 창·요리 동작·상차림, 휴대폰 네 앱, 채집물, 성성호수).
집 안(v0.10) 화면은 `tools/capture_home.sh /tmp/home_shots [34]` (공동 현관 · 엘리베이터 · 평면도마다 집 안과 위에서 본 꾸미기).
v0.9 화면은 `tools/capture_coop.sh /tmp/coop_shots` (첫 화면 항공뷰, 동사무소 · 창구 · 민원/복지/서민금융 창, 갈대 여울 · 물에 들어간 모습 · 뜰채질, 바닷가 조개 숨구멍 · 삽질, 구덩이·흙길).
상점·옷·가구는 서버를 `WEATHER_FORCE=clear START_SOL=40000 MOVE_SLACK_M=200 DOOR_GRACE_MS=0` 으로 띄우고 `res://tools/capture_shop.tscn` (구멍가게 → 잡화점 → 백화점, 옷·가구).

아트·소리 도구 (DESIGN.md 11.4, 3.17):
- `python3 tools/art/extract_reference.py` — 참고 이미지(`art_source/reference/`)에서 로고·아이콘을 투명 PNG로 오림
- `python3 tools/art/gen_ground.py` — `data/world/village_layout.json` 으로 바닥 텍스처를 만듦
- `python3 tools/audio/gen_audio.py` — 효과음·배경음악 합성 (numpy, scipy, ffmpeg). `python3 tools/audio/gen_audio.py v06_sounds` 처럼 묶음 이름을 주면 그 묶음만 (v0.6 소리는 따로 고정한 난수라 기존 소리가 바뀌지 않는다)
- `python3 tools/art/gen_emote_icons.py` — 감정표현 말풍선 아이콘 11장
- `python3 tools/audio/gen_cook_sfx.py` — 식당 효과음 (칼질·지글지글·보글보글·접시·주문 벨·계산)
- `python3 tools/art/gen_character_rig.py` — 캐릭터 리그 씬(애니메이션 키 표: 걷기·달리기·낚시·도끼질·던지기·브레이크·자랑·심기·감정표현 11종·요리 5종·앉기)
- `godot --path . res://tools/render_icons.tscn` — 아이템·요리 모형을 찍어 아이콘 PNG 로 (실제 렌더러 필요, `-- --only=dishes` 는 요리만)
- `godot --path . res://tools/art_preview.tscn -- --what=characters --out=/tmp/p.png` — 모형 확인 (trees / characters / outfits / furniture / shop / village)
