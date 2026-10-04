# 네트워크 프로토콜 v7

WebSocket 텍스트 프레임, 메시지 하나가 JSON 객체 하나. `t`가 종류. 서버가 권위이고 클라이언트가 보내는 건 전부 **요청**이다.
상수는 `server/src/protocol.js` 와 `core/protocol/net_protocol.gd` 에 같은 값으로 둔다. 바꾸면 `VERSION`을 올린다.

v2 → v3: 칸 인벤토리(퀵슬롯 + 가방)와 손에 든 도구, 나무 베기, 주민 대화·부탁, 마을 시계·날씨·번개.
v3 → v4: 상점(드나들기·사고팔기·상점 포인트와 단계), 가구 설치·줍기, 옷 입기·벗기, 소지품 부탁, 달리기 속도(최대 7.2m/s 허용).
v4 → v5: 마을 이벤트(`ev`), 바닥의 선물·별 조각(`drop` `drop_gone` `collect`), 떠돌이 상인과 거래(`shop_sell`/`shop_buy` 의 `at: "merchant"`), 낚시 대회 상금(`fish_result.bonus`), 나무꾼의 날(`chop_result.n`).
v5 → v6: 섬 생활 — 씨앗 심기(`plant`)·심은 나무(`tree` 의 `k x z`)·꽃(`flower`, `pick`), 나무가 게임 시간으로 자람(`sprout`·`young` 단계), 감정표현(`emote` `emote_quick`, `act` 의 `kind: emote`)과 주민 반응(`npc_emote`), 주민 기분(`npcs` 의 `m`, `talk_open.m`), 대화 주제(`talk_topic`), 감정표현 배우기·주민 선물(`talk_open.teach` `gift`), 박물관 기증(`donate`, `museum`), 공항 기념품(`shop_buy` 의 `at: "airport"`). 저장 파일 schema 4.
v6 → v7: 얼굴 꾸미기 — 거울 앞에서 얼굴 바꾸기(`set_face` → `face`), 프로필·플레이어 정보의 `face`, 에러 `not_near_mirror` `bad_face`. 저장 파일은 schema 4 그대로 (프로필에 `face` 가 없으면 자리 기본 얼굴).

## 클라이언트 → 서버
| t | 필드 | 설명 |
|---|---|---|
| `create` | `v uid` | 방 생성 + 입장. `uid`는 기기에 저장된 영구 ID(8~64자 `[A-Za-z0-9_-]`) |
| `join` | `v uid code` | 방 코드(대소문자 무관)로 입장. 같은 `uid`는 쓰던 자리·인벤토리를 되찾는다 |
| `resume` | `v`, `token` | 끊긴 자리로 복귀 (유예 시간 안에서만) |
| `move` | `x y z yaw vx vz` | 내 위치 요청 (m, rad). 서버가 속도·경계 검사 |
| `ping` | `c` | 클라이언트 시각. `pong`으로 RTT·서버 시계 추정 |
| `fish_cast` | `rid spot` | 낚시터에 던지기 요청. **낚싯대를 손에 들고** 수역 `cast_range` 안에 있어야 한다 |
| `fish_hook` | `rid reaction` | 챔질 요청. `reaction` = 입질 연출이 보인 뒤 버튼을 누르기까지 걸린 ms (입질 전이면 0) |
| `fish_cancel` | | 낚시 취소 |
| `equip` | `slot` | 손에 들 퀵슬롯 번호(0~4, `-1` = 빈손). 거절되면 `inventory`로 서버 값을 다시 보낸다 |
| `inv_move` | `rid from to` | 칸 옮기기. 같은 아이템이면 쌓을 수 있는 만큼 합치고, 아니면 맞바꾼다 |
| `inv_discard` | `rid slot n` | 칸에서 n개 버리기(물고기는 놓아주기). 도구는 `cant_discard` |
| `chop` | `rid tree` | 도끼질 요청. **도끼를 손에 들고** 다 자란 나무에서 `chop_range` 안 |
| `talk` | `rid npc` | 주민에게 말 걸기. `talk_range` 안, 다른 사람과 이야기 중이 아니어야 한다 |
| `talk_end` | | 대화 끝 (주민이 다시 걷는다) |
| `quest_accept` | `rid` | 이번 대화에서 받은 부탁 제안 수락 |
| `quest_decline` | | 제안 거절 |
| `quest_turnin` | `rid quest` | 부탁 완료. 그 부탁을 한 주민과 대화 중이고 아이템이 다 있어야 한다 |
| `shop_enter` | `rid` | 상점 문(`door`)에서 `enter_range` 안이면 서버가 실내로 옮긴다 → `shop_door` |
| `shop_exit` | `rid` | 실내 출구(`exit`)에서 `exit_range` 안이면 밖으로 옮긴다 → `shop_door` |
| `shop_sell` | `rid slot n` | 칸의 물건 n개 팔기 (실내에서만, 도구는 `cant_sell`) |
| `shop_buy` | `rid item n` | 지금 단계까지 열린 진열품 n개 사기 (실내에서만) |
| `place` | `rid slot x z rot` | 가구 설치. 서버가 0.5m 격자로 맞추고, 3m 안·물/나무/다른 가구/상점 앞이 아닌 곳만 |
| `pickup` | `rid id` | 내가 놓은 가구를 2.5m 안에서 줍기 |
| `wear` | `rid slot` | 칸의 옷 입기 (입던 옷은 그 칸으로) |
| `unwear` | `rid part` | `hat` / `top` 벗기 (가방에 빈자리가 있어야) |
| `collect` | `rid id` | 바닥의 선물 풍선·별 조각 줍기 (`collect_range` 2m 안, 가방에 빈자리) |
| `shop_sell`/`shop_buy` + `at: "merchant"` | | 떠돌이 상인과 거래: 상인 곁(대화 거리 +1m)에서만. 상인이 찾는 물건만 2배 값에 사고(그 밖은 `not_wanted`), 보따리 물건(`stock`)을 판다. 상점 포인트는 쌓이지 않는다 |
| `shop_buy` + `at: "airport"` | | 공항 기념품 사기 (v6): 조종사 곁(`shop_range` 3.2m +0.5)에서만, `airport.json` 의 `stock` 만. 팔기는 `cant_sell`. 상점 포인트는 쌓이지 않는다 |
| `plant` | `rid x z` | 손에 든 씨앗 심기 (v6). 서버가 0.5m 격자로 맞추고, `plant_range` 안·섬 풀밭·길/물/건물/집 아님·나무 2.2m(꽃은 1m)·꽃 0.85m·가구 0.9m 떨어진 곳만. 나무 씨앗 → `tree`, 꽃씨 → `flower` |
| `pick` | `rid id` | 활짝 핀 꽃 따기 (v6, `plant_range` 안). 꽃 아이템 1개, 꽃은 봉오리로 돌아간다 |
| `emote` | `e` | 감정표현·몸짓 (v6). 배운 감정표현만(`unknown_emote`), 몸짓 `brake` 는 언제나. 0.7초 간격(몸짓은 0.2초). 결과 메시지 없음 — 상대에게 `act`, 근처 주민 반응은 `npc_emote` |
| `emote_quick` | `quick[]` | 감정표현 퀵슬롯 순서 저장 (v6, 배운 것만, 4칸까지) → `profile` |
| `talk_topic` | `topic` | 대화 중인 주민과 주제 수다 (v6): `mood hobby gossip fish past dream food you`. 하루 3번까지 친밀도 +1 → `talk_topic` |
| `donate` | `rid slot` | 박물관 관장 곁(`donate_range`)에서 칸의 물고기 기증 (v6). 한 종에 한 마리(`already_donated`), 물고기만(`not_fish`) |
| `set_face` | `rid face{}` | 얼굴 바꾸기 (v7). 마을 거울(`village_layout.json` 의 `mirrors`)이나 놓인 거울 가구(`items.json` 의 `mirror: true`) 2.2m(+0.5) 안에서만, 상점 안은 안 됨(`not_near_mirror`). `face` 는 바꿀 항목만: `eyes eye_color nose mouth skin hair hair_color` → `face_parts.json` 의 id. 모르는 항목·id·빈 요청은 `bad_face` |

## 서버 → 클라이언트
| t | 필드 | 설명 |
|---|---|---|
| `welcome` | `id token code resumed st players[] inv prof clock w trees[] npcs[] shop placed[] ev drops[] flowers[] museum` | 입장/복귀 성공. 아래 "입장 정보" 참고 (v6: 심은 나무는 `trees[]` 에 `k x z` 와 함께, `flowers[]`, `museum {fish}`) |
| `peer_joined` | `p` | 상대 입장 |
| `peer_status` | `id online` | 상대 연결 끊김/복귀 (자리는 유지) |
| `peer_left` | `id` | 유예 시간이 지나 자리가 비워짐 |
| `snap` | `st p[]` | 위치 스냅샷 (방 단위, 변화가 있을 때만, 기본 20Hz) |
| `correct` | `x y z` | 요청한 이동이 거부됨 → 이 위치로 되돌리기 |
| `pong` | `c s` | `s` = 서버 시각(ms) |
| `inventory` | `slots[] quick cap held` | 내 인벤토리 전체. `slots` 길이 = `quick + cap`, 앞 `quick` 칸이 퀵슬롯, 빈 칸은 `null`. `held` = 손에 든 퀵슬롯(-1 = 빈손) |
| `profile` | `sol quests[] friends{} outfit emotes face` | 내 솔(화폐)·받은 부탁·주민 친밀도·입은 옷·감정표현(`{known[], quick[]}`, v6)·얼굴(v7). 바뀔 때마다 나에게만 |
| `fish_started` | `rid spot` | 던지기 수락 |
| `fish_nibble` | `rid` | 가짜 입질 (0~3번). 아직 당기면 안 된다 |
| `fish_bite` | `rid windowMs` | 진짜 입질. 물고기 종류는 알리지 않는다 |
| `fish_result` | `rid ok fish? reason? bonus?` | 서버가 확정한 결과. 실패 사유: `early late escaped moved cancelled inventory_full`. 낚시 대회 중이면 `bonus` 솔을 더 받았다 |
| `chop_result` | `rid ok item n tree felled` | 도끼질 성공. `item` `n`개(나무꾼의 날 2개)가 인벤토리에 들어갔고, `felled`면 나무가 쓰러졌다 |
| `tree` | `id s c k? x? z? by?` | 나무 상태 변화 (방 전체). `s` = `grown` / `stump` / `sprout` / `sapling` / `young` (v6: 게임 시간으로 자람), `c` = 오늘 찍힌 횟수. 씨앗을 심은 나무(`id` = `p…`)는 `k`(종류) `x z`도 실린다 |
| `act` | `id kind tree? e?` | 상대의 동작: `kind: chop`(도끼질, `tree`), `kind: emote`(감정표현·몸짓 `e`, v6) |
| `npcs` | `st n[]` | 주민 위치 (방 전체, 움직이거나 기분이 바뀔 때 10Hz). `n[]`: `{id, x, z, yaw, talk, m}` (`talk` = 대화 중인 플레이어 id, 0 = 없음, `m` = 기분 `happy calm sad grumpy sleepy excited`, v6) |
| `talk_open` | `rid npc f first m quest? ready? offer? teach? gift?` | 말 걸기 수락. `f` 친밀도, `first` 오늘 첫 대화, `m` 지금 기분, `quest` 이 주민의 진행 중 부탁(`ready` = 지금 완료 가능), `offer` 새 부탁 제안, `teach` 이번에 가르쳐 준 감정표현, `gift` 친해져서 준 선물(이미 가방에) |
| `talk_topic` | `npc topic f gain m` | 주제 수다 결과 (v6): `gain` = 오른 친밀도(하루 상한이면 0), `m` = 수다 뒤 기분 |
| `npc_emote` | `npc e to m from` | 주민이 감정표현에 반응했다 (방 전체, v6): `e` 주민의 몸짓, `to` 감정표현을 한 사람, `m` 바뀐 기분, `from` 그 사람의 감정표현 |
| `flower` | `f by?` | 꽃이 생기거나 자라거나 따였다 (방 전체, v6). `f` = `{id, sp, c, x, z, s}` (`sp` 종류, `c` 색 번호, `s` = `sprout`/`bud`/`bloom`), `by` = 그렇게 한 사람(저절로 자라면 없음) |
| `plant_result` | `rid id kind x z` | 내가 심었다 (`kind` = `tree`/`flower`) |
| `pick_result` | `rid id item` | 내가 꽃을 땄다 |
| `face` | `rid? id face{}` | 누군가 얼굴을 바꿨다 (v7, 방 전체 — 바꾼 사람에게는 `rid` 와 함께). `face` = 일곱 항목 전부 |
| `museum` | `fish{} id by` | 박물관 기증 목록이 바뀌었다 (방 전체, v6). `fish` = 물고기 id → 기증한 사람 자리 번호 |
| `donate_result` | `rid fish reward sol count gifts[]` | 내가 기증했다: 감사 `reward`솔, 지금까지 `count`종, 문턱을 넘어 받은 기념품 `gifts` |
| `talk_closed` | `npc` | 서버가 대화를 끝냄 (멀어짐·시간 초과) |
| `quest_accepted` | `rid quest` | 부탁 수락 확정 |
| `quest_done` | `rid quest npc reward sol` | 부탁 완료. 아이템을 가져가고 `reward`솔을 줬다 |
| `weather` | `w` | 날씨 변화: `clear` / `cloudy` / `rain` / `thunder` |
| `shop_door` | `inside x y z shop` | 서버가 나를 상점 안/밖으로 옮겼다 (클라이언트는 그 자리로 순간이동) |
| `shop_result` | `rid kind item n sol amount` | 사고팔기 성공 (`kind` = `buy`/`sell`, `amount` = 오간 솔) |
| `shop` | `level points next up` | 상점 단계·포인트 (방 전체). `next` = 다음 단계 문턱(마지막이면 null), `up` = 방금 커졌다 |
| `placed` | `rid by f` | 가구가 놓였다 (방 전체). `f` = `{id, item, x, z, rot, owner}` (`owner` = 놓은 사람 자리 번호) |
| `unplaced` | `rid id` | 가구가 치워졌다 (방 전체) |
| `lightning` | `st power` | 번개 (뇌우일 때, 방의 모두에게 같은 순간). `power` 0.6~1 |
| `ev` | `day list[]` | 지금 열린 이벤트가 바뀌었다 (방 전체). `list[]`: `{id, wanted?, mult?, stock?}` — `wanted` 오늘 2배로 사 주는 물건, `stock` 떠돌이 상인의 보따리 |
| `drop` | `d` | 바닥에 선물·별 조각이 떨어졌다 (방 전체). `d` = `{id, kind, x, z, item?}` (`kind` = `gift`/`star`, 선물 속 `item`은 주울 때까지 비밀) |
| `drop_gone` | `id by` | 주웠거나(`by` = 주운 사람) 이벤트가 끝나 사라졌다(`by` = 0) |
| `collect_result` | `rid id kind item` | 내가 주웠다. `item` 1개가 인벤토리에 들어갔다 |
| `error` | `code msg rid?` | 아래 에러 코드 |

`players[]`/`p[]` 항목: `{id, online, fishing, held, hat, top, x, y, z, yaw, vx, vz}` (`fishing`은 낚시 자세, `held`는 손에 든 아이템 id, `hat`·`top`은 입은 옷 — 상대 캐릭터 표시용). `welcome.players[]`·`peer_joined.p` 에는 `face` 도 실린다 (v7, 스냅샷 `snap.p[]` 에는 없다 — 바뀌면 `face` 메시지).
`profile`에는 `outfit {hat, top}`도 실린다. `st`/`s`는 서버 단조 시계(ms).

부탁(`quest`/`offer`/`quests[]`): `{id, npc, kind, item?, n, reward, exp, have}` — `kind` = `deliver`(재료 n개) / `deliver_fish`(그 물고기 n마리) / `any_fish`(아무 물고기 n마리), `exp` = 이 마을 날짜까지 유효, `have` = 지금 인벤토리로 채운 개수.

에러 코드: `bad_version bad_message not_in_room already_in_room room_not_found room_full resume_failed rate_limited not_at_spot already_fishing not_fishing inventory_full bad_item cant_discard no_tool not_near_tree tree_not_ready too_fast not_near_npc npc_busy not_talking no_offer bad_quest quest_not_ready not_near_door not_in_shop not_for_sale not_enough_sol cant_sell bad_place place_limit not_owner not_wearable no_drop merchant_away not_wanted not_seed bad_plant plant_limit no_flower unknown_emote not_near_keeper already_donated not_fish bad_topic not_near_mirror bad_face`

## 입장 정보 (`welcome`)
- `inv` = `inventory`, `prof` = `profile` 과 같은 모양.
- `clock` = `{g, s, st}`: 서버 시각 `st`(ms)일 때 마을 시각이 `g`(마을 시간대 벽시계를 epoch ms로 나타낸 값)이고 `s`배로 흐른다. 클라이언트는 `g + (서버시각 − st) × s` 로 지금 마을 시각을 계산한다. 하루는 **새벽 5시**에 바뀐다.
- `w` = 지금 날씨, `trees[]` = `{id, s, c}` 전체, `npcs[]` = 주민 위치 전체, `shop` = `shop` 메시지와 같은 모양, `placed[]` = 설치된 가구 전체.
- `ev` = `ev` 메시지와 같은 모양(지금 열린 이벤트), `drops[]` = 바닥의 선물·별 조각 전체.

## 마을 이벤트 (서버 판정, `data/events/events.json`)
- 날마다(새벽 5시 기준) 마을 시드와 날짜로 하루 이벤트를 뽑는다: 75% 확률로 아래 다섯 중 하나(가중치), 나머지는 이벤트 없는 날. 저장하지 않아도 언제 계산해도 같다(날씨와 같은 방식).
  | id | 이름 | 시간 | 규칙 |
  |---|---|---|---|
  | `bargain` | 특가 매입의 날 | 하루 종일 | 상점이 고른 물건(물고기 2 + 재료 1)을 2배 값에 사 준다 |
  | `merchant` | 떠돌이 상인 누리 | 9~21시 | 광장(`spot`)에 노점. 찾는 물건(물고기·소지품·재료 하나씩)을 2배 값에 사고, 보따리 물건 4가지를 판다 |
  | `fishing_derby` | 호수 낚시 대회 | 9~18시 | 낚을 때마다 상금(흔한 40 · 조금 귀한 150 · 귀한 500솔), 귀한 물고기가 2.5배 잘 잡힌다 |
  | `lumber_day` | 나무꾼의 날 | 하루 종일 | 도끼질 한 번에 2개 |
  | `gift_day` | 선물 풍선의 날 | 8~19시 | 40초마다 선물 풍선이 마을에 내려앉는다(최대 4개). 주우면 클로버·꽃다발·바람개비 등 |
- 밤 이벤트 `meteor_shower`(유성우)는 따로 35% 확률, 20~4시의 맑음·흐림에만. 30초마다 별 조각이 떨어진다(최대 5개).
- 선물·별 조각 자리는 호수·상점·집·나무·바위를 피해 광장 둘레 28m 안에서 고른다. 메모리에만 두고, 이벤트가 끝나면 치운다.
- 시연·테스트: `EVENT_FORCE=merchant,meteor_shower`(고정), `EVENT_WANTED=wood,crucian`(찾는 물건 고정), `EVENT_SPAWN_SCALE=0.02`(빨리 떨어뜨리기).

## 흐름
- **입장**: `create`/`join` → `welcome`(+상대에게 `peer_joined`). 클라이언트는 `welcome`의 내 위치로 캐릭터를 맞춘다.
- **동기화**: 클라이언트는 20Hz로 `move`(바뀐 게 있을 때 + 1초 하트비트). 서버는 `snap`을 방송하고, 클라이언트는 서버 시계 기준 120ms 과거를 보간해서 그린다.
- **끊김**: 서버가 소켓 close 또는 ws ping 무응답으로 감지 → `peer_status(online:false)`, 자리를 30초 유지. 클라이언트는 close 또는 6초 무응답을 감지하면 백오프(0.3→3초)로 `resume`을 반복하고, 서버 유예보다 약간 긴 35초 뒤 포기한다. 끊기면 낚시·대화는 취소된다.
- **복귀**: `resume` → `welcome(resumed:true)`. 서버가 알고 있는 마지막 위치로 되돌아간다(오프라인 중 이동은 인정하지 않음).
- **대체**: 같은 `token`으로 새 연결이 오면 낡은 연결을 close code `4000`으로 끊는다(클라이언트는 이 코드에서 재접속하지 않는다).

## 서버 검증
이동은 `max_speed × 1.6 × dt + 0.6m` 이내만 인정하고 초과분은 잘라낸 뒤 `correct`를 보낸다. 경계(±200m — 섬 ±100m 와 바다 너머 상점 실내까지)·높이(−5~30m) 밖은 안으로 되돌린다. 설치·심기는 섬 경계(`village_layout.json` 의 `island`, 모래사장 안쪽)로 따로 막는다.
연결당 초당 60개(버스트 120) 초과 시 `rate_limited`, 계속 넘으면 close `4008`. 메시지는 1KB 이하.

## 낚시 (서버 판정)
`fish_cast` → `fish_started` → 가짜 `fish_nibble` × 0~3 → `fish_bite{windowMs}` → `fish_hook{reaction}` → `fish_result`.
- 물고기는 던질 때 서버가 **지금 시각·날씨에 낚이는 물고기 중에서** 가중치로 정하고(`fish.json`의 `hours`·`weather`), 결과가 확정될 때에만 `fish_result.fish`로 알린다.
- 서버는 `reaction`이 허용 창(`hook_window_ms`, 450~700ms) 안인지, 사람이 낼 수 있는 값(≥80ms)인지, 서버가 잰 경과 시간과 모순되지 않는지만 본다. 네트워크 지연은 판정에 들어가지 않는다.
- 입질 전에 당기면 `early`, 창을 넘기면 `late`, 아예 반응이 없으면 `escaped`, 캐스팅 지점에서 1.5m 넘게 움직이면 `moved`.
- 같은 `rid`는 한 번만 처리한다.

## 나무 (서버 판정)
- 다 자란 나무(`grown`)를 도끼로 찍을 때마다 `chop_drops` 가중치로 목재 1개(목재 / 부드러운 목재 / 단단한 목재). 3번째에 쓰러져 그루터기(`stump`).
- (v6) 그루터기는 게임 시간으로 `regrow_minutes`(8분) 뒤 묘목(`sapling`) → 10분 뒤 어린 나무(`young`, 아직 못 벰) → 10분 뒤 다 자란 나무. 씨앗을 심은 나무는 새싹(`sprout`, `plants.json` 의 `tree_minutes`)부터. 1초마다 확인해서 바뀌면 `tree` 로 알린다. `GROWTH_SCALE` 로 빠르게(테스트). 덜 찍힌 나무는 날이 바뀌면 회복된다.
- 가방이 가득 차면 `inventory_full`로 거절하고 나무는 그대로다. 도끼질 사이 최소 간격 `CHOP_COOLDOWN_MS`(기본 400ms).

## 주민 · 부탁 (서버 판정)
- 주민은 데이터의 길목(`waypoints`) 사이를 걷는다. 비·뇌우·밤(20~5시)에는 집 앞(첫 길목)에 머문다. 위치는 저장하지 않는다.
- 한 주민은 한 번에 한 사람과만 이야기한다(`npc_busy`). 60초 동안 요청이 없거나 6m 넘게 멀어지면 `talk_closed`.
- 오늘 처음 말을 걸면 친밀도 +2, 부탁을 완료하면 +5 (최대 100). (v6) 같은 날 다시 말 걸기·`talk_topic` 은 합쳐서 하루 3번까지 +1, 감정표현에 반응한 주민은 하루 한 번 +1 (`흥!` 은 빼고).
- (v6) **기분**: 서버가 1초마다 정한다. 마을 시드·날짜·3시간 구간·주민 순서로 바탕 기분을 뽑고(주민의 `mood_bias` 가중치, 날씨별 `weather` 기분 +4, 22~6시 졸림 +6, 이벤트 날 활발·몽상가 신남 +2), 감정표현·수다·부탁 완료가 8분 동안 덮어쓴다. 바뀌면 `npcs` 에 실린다.
- (v6) **감정표현 반응**: 7m 안, 다른 사람과 이야기 중이 아닌 주민이 3.5초에 한 번까지 반응한다. 반응은 `emotes.json` 의 성격별 표, 기분이 졸림·뾰로통·시무룩·신남이면 35% 확률로 기분대로. 2.6초 멈춰 서서 그 사람을 본다.
- (v6) **감정표현 가르치기**: 말을 걸 때 친밀도가 `teaches` 문턱을 넘은, 아직 모르는 감정표현 하나를 가르쳐 준다(빈 퀵슬롯에 넣는다).
- (v6) **선물**: 친밀도 12 이상이면 말을 걸 때 하루 한 번 45% 확률로 `gifts` 중 하나를 가방에 넣어 준다 (`gift_rules`).
- 부탁 제안은 말을 걸 때 서버가 정한다: 그 주민의 진행 중 부탁이 없고, 받은 부탁이 3개 미만이고, 오늘 그 주민에게 제안받지 않았을 때 확률 30%(+친밀도 단계마다 5%, 최대 60%). 이틀 넘게 제안이 없었으면 반드시 하나. 지금 낚을 수 없는 물고기는 부탁하지 않는다.
- 부탁은 다음 날까지 유효하고, 지나면 조용히 사라진다(벌칙 없음).

## 시계 · 날씨
- 마을 시각은 서버 시계 기준(기본 한국 시간, 실제 시간과 같은 속도). `CLOCK_SCALE`·`CLOCK_OFFSET_MIN`으로 시연용으로 빠르게/옮길 수 있다.
- 날씨는 방마다 저장된 시드로 하루를 3시간 블록 8개로 나눠 정한다(맑음 50 · 흐림 25 · 비 18 · 뇌우 7, 직전 블록과 같을 확률 50%). 같은 시드·날짜·시각이면 언제 계산해도 같다. 바뀌면 `weather`로 알린다.
- 뇌우일 때는 6~18초마다 `lightning`을 방 전체에 보낸다.

## 상점 (서버 판정)
- 실내는 섬 밖 바다 너머 멀리 떨어진 공간(`interior`, z≈190, v6 에서 옮김)이다. 문을 지나면 서버가 위치를 바꾸고 `shop_door`로 알린다(이동 속도 검사를 거치지 않는 유일한 순간이동). 문을 지난 직후 1.5초(`DOOR_GRACE_MS`) 동안은 문 반대편(10m 넘게 떨어진 곳)에서 늦게 도착한 `move`를 무시한다.
- 사고팔기는 실내(`interior` 사각형 안)에서만. 파는 값 = 기본 가격(`price`) × 개수 × (1 + 단계 보너스 0 / 5% / 10%), 사는 값 = `buy` × 개수.
- **사고판 솔만큼 상점 포인트가 쌓인다**(마을 공용, `SHOP_POINTS_SCALE` 배). 1500포인트 → 2단계 잡화점, 6000포인트 → 3단계 백화점. 단계가 오르면 진열품이 늘고(이전 단계 물건도 계속 판다) 방 전체에 `shop{up: true}`.
- 상점 주인(달보)과의 대화는 클라이언트만의 연출이다(서버 대화 잠금 없음, 두 사람이 같이 거래할 수 있다).

## 가구 · 옷 (서버 판정)
- 설치: 가구 아이템 1개를 칸에서 빼서 마을에 놓는다. 위치 0.5m 격자, 방향 90° 단위. 다른 가구·나무(심은 나무 포함)와 1m, 꽃과 0.8m, 물과 0.6m 떨어져야 하고, 섬 모래사장·바다, 상점·박물관·공항·주민 집 자리에는 못 놓는다. 한 사람당 30개(`MAX_PLACED_PER_PLAYER`).
- 가구는 마을 공용으로 보이고, 놓은 사람만 주울 수 있다(`not_owner`).
- 옷: 모자(`hat`)·상의(`top`) 한 벌씩. 입은 옷은 인벤토리 칸을 차지하지 않는다. 갈아입으면 입던 옷이 방금 비운 칸으로 돌아오므로 가방이 꽉 차도 갈아입을 수 있다.

## 심기 · 꽃 · 박물관 · 공항 (서버 판정, v6)
- 심기: 손에 든 씨앗(`items.json` 의 `plant.tree` / `plant.flower`)을 하나 써서 심는다. 나무는 마을에 40그루, 꽃은 160송이까지(`plant_limit`). 자리 규칙은 `plant` 메시지 설명과 같다 (`badPlant`). 심은 나무는 다 자라면 데이터 나무처럼 베고 다시 자란다.
- 꽃: 새싹 → 봉오리 → 활짝(`plants.json` 의 `minutes`, 수국은 비 오면 `rain_bonus` 배 빨리). 따면 꽃 아이템 1개, 봉오리로 돌아가 `rebloom_minutes` 뒤 다시 핀다.
- 박물관: 관장 곁에서 한 종에 한 마리 기증, 마을 공용(`museum.fish`). 기증마다 `reward_sol`(50솔). 기증 수가 `milestones`(5·15·31)를 넘으면 그 기증을 한 사람에게 기념품 (가방이 차 있으면 다음 기증 때).
- 공항: 조종사 곁에서 `stock` 의 기념품만 산다. 비행기 이착륙은 서버 메시지 없이 마을 시계(`flight.cycle_minutes`)로 클라이언트가 계산한다.

## 얼굴 · 거울 (서버 판정, v7)
- 얼굴은 프로필의 `face` (`eyes eye_color nose mouth skin hair hair_color`, `data/looks/face_parts.json` 의 id). 새 프로필·모르는 id 는 자리 기본 얼굴(`defaults[slot-1]`).
- 거울: 마을 거울 자리(`mirrors`)와 `mirror: true` 가구(전신 거울·거울 화장대)를 누가 놓았든 그 앞(`mirror.range` 2.2m + 0.5m)에서만 바꾼다. 거울 자리 1.3m 안에는 심거나 가구를 놓을 수 없다.
- 비용 없음. 바꾸면 저장하고 방 전체에 `face` 로 알린다.

## 인벤토리
퀵슬롯 5칸 + 가방 20칸. 새 아이템은 같은 아이템 칸 → 빈 가방 칸 → 빈 퀵슬롯 순으로 들어간다. 칸당 개수: 물고기 99, 목재 30, 도구 1.
처음 들어오면 퀵슬롯 1번에 낚싯대, 2번에 도끼가 있고 1번을 손에 들고 있다(솔은 `START_SOL`, 기본 0). 도구는 버릴 수 없다.
아이템 종류: 도구, 재료(목재 6종), 소지품(부탁·선물용 19종 + v6 씨앗 4 · 자작나무 씨앗 · 꽃 4 · 엽서), 가구(20종 + v6 지구본·비행기 모형·여행 가방·어항·월척 트로피·황금 물고기상), 옷(모자 8·상의 7, v6 조종사 모자), 물고기(31종). 나무 종류(둥근·소나무·자작나무)마다 나오는 목재·소지품이 다르다.
물고기 칸이 가득 차면 던지기 전에 `inventory_full`로 거절하고, 던진 뒤 칸이 찼다면 `fish_result(inventory_full)`로 놓친다.

## 저장
방(마을) 하나 = JSON 파일 하나: `<SAVE_DIR>/<방코드>.json`
(`schema: 4`, `createdAt`, `world{totalCatches, species, weatherSeed, trees{<id>: {s, c, d, t}}, shopPoints, placed[], placedSeq, planted[{id, kind, x, z, by, st}], plantSeq, flowers[{id, sp, c, x, z, s, t, by}], flowerSeq, museum{fish{}, claimed[]}}`,
`profiles{<uid>: {slot, slots, held, sol, catches, x, y, z, yaw, npcs{<id>: {f, talkDay, offerDay, giftDay, emoteDay, chatDay, chatCount}}, quests[], questSeq, lastQuestDay, outfit{hat, top}, emotes{known[], quick[]}}}`).
- schema 3 파일도 그대로 읽는다: 나무 상태의 `t`(단계 시작 게임 시각)가 없으면 0 으로 보고 다음 틱에 다 자란다, 감정표현은 '안녕'부터.
- 사람은 `uid`로 구분한다. 서버가 재시작되어 `token`이 사라져도, 클라이언트가 방 코드 + `uid`로 `join`하면 같은 자리·인벤토리·위치로 돌아온다(클라이언트가 `resume_failed` 뒤 자동으로 시도).
- 아이템 수가 바뀌는 일(낚시·도끼질·버리기·부탁 완료·사고팔기·가구 설치/줍기·옷 입기/벗기)과 부탁·친밀도·상점 포인트 변화, 입퇴장은 즉시 저장한다. 칸 옮기기·손에 든 칸·위치는 5초 주기로 저장한다. 쓰기는 임시 파일 → rename 으로 원자적이다. 종료 시에는 메모리의 방을 전부 저장한다.
- `schema: 1` 파일(물고기 목록 `items`)은 읽을 때 칸 인벤토리로 옮기고 도구를 챙겨 준다.
- 방 코드는 파일 이름이라 형식(`[A-HJ-KM-NP-Z2-9]{6}`)을 검사한 뒤에만 쓴다. 깨진 파일은 `.corrupt-<시각>`으로 옮겨 두고 방이 없는 것으로 처리한다.
