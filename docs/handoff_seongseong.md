# 성성호수공원 재현 — 작업 인수인계 (체크포인트)

기준 브랜치: `claude/seongseong-lake` (커밋 bca34cf: 1/30 실제 윤곽 호수 + 둘레길·방문자센터·정자·벤치).
dev 브랜치·main 은 건드리지 않는다. 단계마다 커밋·푸시.

## 목표 (사용자 요청)
- 성성호수공원 **지도 사진 그대로의 재현**. 호수가 섬(지도) 중심에 크게.
- 주변 **입주 예정 아파트** 도면·동별 평수·집 구조를 따와서 "성성호수공원에 사는 느낌".
- 주민집은 없앤다(주민은 아파트에 사는 것처럼). 상점·식당은 나중에 현대식으로 재탄생 예정.
- 기존 건축물은 **우선 위치만 빈 공간에 몰아넣고**, 공원 재현에 집중.

## 확정된 결정 (사용자 답변)
| 항목 | 결정 |
|---|---|
| 섬 크기 | 그대로 (±100m, 바닷가 9m → 풀밭 약 ±91m) |
| 호수 크기 | 실제의 **1/10** (약 86×90m), 섬 정중앙 (바깥 사각형 가운데 = (0, 0)) |
| 재현 단지 | e편한세상 성성호수공원(DL이앤씨) · 엘리프 성성호수공원(계룡건설, 1,165가구) · 업성 푸르지오 레이크시티(대우건설) · 기존 입주 단지(천안 푸르지오 레이크사이드·레이크타운 등) |
| 집 내부 | 단지별 대표 평형 2~3개 (예: 59·84㎡) — 실제 평면도처럼 방 구조 |
| 평면도 출처 | 사용자가 평면도 이미지를 첨부 (아직 안 옴) |

## 입력 대기
- **네이버 지도 캡처 2장** (이전 세션에서 받았지만 대화 정리로 사라짐 — 다시 받아야 함). 아파트 동 배치가 보이게 확대본이면 좋다.
- **단지별 평면도 이미지**.

## 원본 데이터
- `tools/art/data/lake_outline_real_m.json`: 지도 캡처에서 딴 윤곽. 미터, 중심 = 큰 호수 무게중심, +x 동, +z 남.
  `polygons[0]` = 성성호수(111점), `polygons[1]` = 서쪽 작은 연못(18점). 축척 막대 200m = 135px (1.4815 m/px).
- 1/10 변환 결과 (재현용 메모): `polygons/10` 후 바깥 사각형 가운데로 옮기면 큰 호수 x −43.1~43.1, z −45.0~45.0 (면적 약 3,190㎡),
  연못 x −60.3~−42.8, z 30.4~41.0. 단순화: cv2.approxPolyDP(eps 0.35m, 연못 0.2m) → Chaikin 1회 → 반시계 → 약 200점 / 36점.
- 윤곽 안에 들어가는 여울 사각형 후보 (가장자리에서 0.6m 안쪽):
  - 서남쪽 꼬리 `seongseong_ford`: 가운데 (−25.5, 23.0), 반 4.0×3.0
  - 남쪽 물굽이 `seongseong_bay`(새로): 가운데 (8.0, 24.0), 반 3.0×4.0
  - 연못 `lake_reeds`: 가운데 (−50.5, 33.75), 반 2.5×2.5

## 1단계 계획 (다음에 할 일)
1. **호수**: `data/fish/spots.json`
   - `seongseong` = 1/10 윤곽 + 여울 둘. x/z/half_* = 윤곽의 바깥 사각형.
   - `lake` 스팟 id 는 유지하고 **서쪽 연못**으로 바꾼다 (이름 "서쪽 연못", 예전 마을 호수 물고기 31종·갈대 여울 그대로 — 박물관·저장 데이터 호환).
   - `tools/art/gen_lake_sdf.py`: 큰 호수용으로 해상도를 0.25m/칸(최대 384²)으로 키운 뒤 재생성. `village.tscn` 연잎 수 조정(연못 작게, 큰 호수 많게).
2. **건물 이전** (우선 북서쪽 생활권으로; 그룹마다 같은 dx,dz 로 옮겨 안쪽 배치 유지):
   - 새 중앙 광장 약 (−48, −48) r 6 → `village_layout.json` plaza, 서버 `config.js` spawnPoints(지금 (0,0) 둘레 — 호수 안이 됨).
   - 상점 door/outside_spawn (interior·room_origin 은 섬 밖이라 그대로), 박물관(building·curator·aquarium), 식당(building·counter·seats·tables), 동사무소(building + staff x/z), 이벤트 상인 spot(`events.json` daily[1].spot), 거울(`mirrors`).
   - 공항은 그대로 (0,−76), 활주로 x 12~46, z −78 — 호수와 겹치지 않음.
   - 기존 아파트 단지(`realestate/apartments.json` 101~103동 (53~75, 30), office)는 동쪽이라 일단 유지 → 2단계에서 실제 단지로 교체.
3. **주민집 제거**: `npcs.json` 의 `house` 를 없애고 `waypoints` 를 공원·광장 둘레로 옮긴다.
   house 가 없을 때 처리 필요: `server/src/events.js` blocked(`n.house.x` 바로 접근 — 터짐), `game/npc/npc_crowd.gd` `_build_house`, `core/types/npc_info.gd`(has_house 같은 표시 추가), `interaction_controller.gd`·`village_decor.gd` 의 house 거리 검사. `world.js` 는 이미 `if (n.house)`.
4. **나무·장식**: `world/trees.json` 50그루 중 호수·새 건물·길에 걸리는 것은 빈 풀밭으로 옮긴다(id 유지). `village_layout.json` 의 flower_beds·fences·rocks·dock(옛 호수 선착장 (−12.6, 2))·plazas·paths 를 새 배치에 맞게 정리.
5. **떨어지는 물건 자리**: `server/src/events.js` `dropPosition` 기본 near (−3, 2) 와 `server.js` forageSpot 의 near (0,0)·avoid 목록이 옛 마을 가운데 기준 → 새 광장/호수 둘레 기준으로.
6. **둘레길·공원**: 호수 둘레길(윤곽을 약 4~5m 바깥으로 민 고리, shapely buffer 로 만들었음), 광장 연결 도로, 연못 둘레, 방문자센터·정자·벤치(`village_layout.json` park) 재배치. 아파트 단지 4곳 부지를 비워 둔다(2단계에서 지도대로).
7. **바닥 텍스처** `python3 tools/art/gen_ground.py` 재생성 → Godot 은 `--headless --import` 로 캐시 갱신 후 렌더.

## 테스트에 박힌 옛 좌표 (데이터에서 읽도록 고칠 것)
- `tests/fishing_e2e.gd` 52행 `Vector3(-20, 0, 2)`(lake 위치), 67행 `(-9, 0.1, 2)` 물가
- `tests/test_server_e2e.gd` 110행 `(-9, 0.1, 2)`
- `tests/coop_e2e.gd` 285행 `Field.zone_at(Vector3(-26, 0, 2))`(갈대 여울), 391행 `(-40/-44, 0.1, 22)`
- `tests/audio_check.gd` 25~42행 (박물관 앞 광장 (48,−9), 흙길 (1.5, 9), 풀밭 (20, 30))
- `tests/island_e2e.gd` 83·135·150행, `tests/mirror_e2e.gd` 112·124행, `tests/shop_e2e.gd` 64·162·171행
- 서버 테스트(`server/test/*.test.js`)에도 좌표가 있을 수 있다 — `npm test` 로 확인.

## 검증 방법
- 서버: `cd server && npm ci && npm test`
- 클라: `GODOT=<godot 4.5> tests/run_<이름>_e2e.sh` (economy, fishing, coop, island, village, events, home, shop, mirror, net, social, test_server, title)
- 렌더: `xvfb-run -a -s "-screen 0 1280x960x24" $GODOT --path . --rendering-driver vulkan --rendering-method mobile res://tools/art_preview.tscn -- --what=village --cam=x,y,z --at=x,y,z --player=x,y,z --out=a.png`
  (월드 커브는 플레이어 기준이라 먼 곳은 `--player` 로 플레이어를 그쪽에 둔다). 렌더 뒤 `.import` 파일 변경은 되돌린다.
- 윤곽·여울을 바꾸면 `gen_lake_sdf.py` → `gen_ground.py` 순서로 다시 돌린다.

## 2·3단계
- 2단계 (지도 캡처 받은 뒤): 단지별 동 배치·도로·공원 시설을 지도 축척(1/10 기준)대로. 건물은 게임 스케일(동 하나 약 11×8m)로 키워 배치.
- 3단계 (평면도 받은 뒤): `data/realestate/floorplans.json`·`server/src/homes.js`(방 rects 미터 단위) 형식으로 단지별 대표 평형 2~3개.
