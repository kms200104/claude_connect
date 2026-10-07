# 네트워크 프로토콜 v16

WebSocket 텍스트 프레임, 메시지 하나가 JSON 객체 하나. `t`가 종류. 서버가 권위이고 클라이언트가 보내는 건 전부 **요청**이다.
상수는 `server/src/protocol.js` 와 `core/protocol/net_protocol.gd` 에 같은 값으로 둔다. 바꾸면 `VERSION`을 올린다.

v2 → v3: 칸 인벤토리(퀵슬롯 + 가방)와 손에 든 도구, 나무 베기, 주민 대화·부탁, 마을 시계·날씨·번개.
v3 → v4: 상점(드나들기·사고팔기·상점 포인트와 단계), 가구 설치·줍기, 옷 입기·벗기, 소지품 부탁, 달리기 속도(최대 7.2m/s 허용).
v4 → v5: 마을 이벤트(`ev`), 바닥의 선물·별 조각(`drop` `drop_gone` `collect`), 떠돌이 상인과 거래(`shop_sell`/`shop_buy` 의 `at: "merchant"`), 낚시 대회 상금(`fish_result.bonus`), 나무꾼의 날(`chop_result.n`).
v5 → v6: 섬 생활 — 씨앗 심기(`plant`)·심은 나무(`tree` 의 `k x z`)·꽃(`flower`, `pick`), 나무가 게임 시간으로 자람(`sprout`·`young` 단계), 감정표현(`emote` `emote_quick`, `act` 의 `kind: emote`)과 주민 반응(`npc_emote`), 주민 기분(`npcs` 의 `m`, `talk_open.m`), 대화 주제(`talk_topic`), 감정표현 배우기·주민 선물(`talk_open.teach` `gift`), 박물관 기증(`donate`, `museum`), 공항 기념품(`shop_buy` 의 `at: "airport"`). 저장 파일 schema 4.
v6 → v7: 얼굴 꾸미기 — 거울 앞에서 얼굴 바꾸기(`set_face` → `face`), 프로필·플레이어 정보의 `face`, 에러 `not_near_mirror` `bad_face`. 저장 파일은 schema 4 그대로 (프로필에 `face` 가 없으면 자리 기본 얼굴).
v7 → v8: 마을 경제 — 화폐를 현실 단위로(1솔 ≈ 1원, 모든 값 ×100), 증권(`stock_order`, `market_tick`), 아파트(`apt_buy` `apt_sell`, `homes`), 은행(`bank_quote` `loan_take` `loan_repay`, `bank`, 주간 정산 `week`), 식당(`rest_open` `rest_close` `rest_cook` `rest_serve`, `rest` `rest_order` `rest_served` `rest_left` `rest_closed` `rest_result`), 들판 채집물(`drop.kind: "forage"`), 성성호수 낚시터(`fish_cast.spot: "seongseong"`), 대화 주제 `worry` `mbti`. `profile` 에 `stocks trades loans credit income worth`, `welcome` 에 `market homes rest`. 저장 파일 schema 5 (schema 4 이하의 솔·상점 포인트·부탁 보상은 읽을 때 ×100).
v8 → v9: 같이 하기 · 동사무소 · 여울 · 삽 — 식당 직원(`rest_join`, 직원의 `rest_close` = 그만두기, `rest_staff`)·동작 나눠 맡기(`rest_cook{order, step}` → `rest_claim`, `rest_step` → `rest_stepped`, 마지막 동작에 서버가 `rest_result` — `rest_serve` 없어짐), `rest` 의 `staff team orders[].steps`, 같이 베기(`chop_result.coop`, `coop_bonus`), 같이 낚시·얕은/깊은 물(`fish_started.zone coop`), 동사무소(`civic_info` `civic_civil` `civic_apply` `marry_propose` `marry_answer`, `civic` `civic_result` `marry_proposal` `marry_declined` `household`), 정책대출(`apt_buy.policy: "didimdol"`, `loan_take.product: "sunshine_youth"`, 대출의 `product fixed`), 카드 캐시백(`shop_result.back`), 주간 지원금(`week.grant`), 여울 뜰채(`net` → `net_result`, `shoal`), 삽(`dig` → `dig_result`, `tile` `digspot` `digspot_gone`). `profile` 에 `civ`, `welcome` 에 `civic tiles digspots shoals`. 저장 파일은 schema 5 그대로 (world 에 `tiles households householdSeq`, 프로필에 `household civic age` — 없으면 기본값).
v10 → v11: 낚시 끌어올리기 — `fish_started.shadow`(물고기 그림자 크기), 챔질 뒤 `fish_reel{taps, ms}` → 클라이언트 `fish_reel{rid, taps[]}`, 실패 사유 `snapped`. 요리 동작 `grill`(면마다 뒤집기) · `steam`(재료 담기 → 물 붓기 → 뚜껑 열기). 주민이 먼저 다가와 말 걸기(`npcs` 의 `ap`, `npc_greet`). 마을톡(`msg_send` `msg_read` → `msg`, `welcome.chats`). 저장 파일은 schema 5 그대로 (프로필에 `chats`, 주민 관계에 `msgReplyDay` — 없으면 빈 값).
v11 → v12: 말풍선(`say`) · 다른 사람 몸짓(`act`) · 배달 일거리(`job_*`) · 예적금(`dep_open` `dep_close` `park_move`) · 주간 경제 소식. 버전이 다르면 `error{code: "bad_version", server_v}` 로 서버 버전을 알려 준다.
v12 → v13: 가방 30칸(퀵 5 + 가방 30, 옛 저장의 칸 자리는 그대로) · 버린 물건이 바닥에 남음(`inv_discard` → `drop{kind: "item", n}` · 일부만 줍기 `collect_result.n left`, 에러 `cant_drop_here` `ground_full`) · 10개씩 사기와 식당 창고(`shop_result.stored`, `rest.store`, 에러 `storage_full`) · 식재료 배달(`deliv_order` → `deliv_ok`, 마을톡 `sys:shop`, `couriers`, `deliv_done`, 에러 `delivery_busy`) · 물 밑 물고기 그림자와 겨눠 던지기(`fishes`, `fish_cast.x z`, `fish_started.fid size ms bx bz`, `fish_found`, 에러 `bad_cast`). 저장 파일은 schema 6 그대로 (world 에 `ground groundSeq deliveries delivSeq`, `restaurant.storage`).
v13 → v14: 닉네임 — `set_name{rid name}` → `name{rid? id name}`(방 전체), `create`/`join` 의 `name?`(처음 화면 설정에 적어 둔 이름), 플레이어 정보·프로필의 `name`(빈 문자열 = 자리 기본 이름), 에러 `bad_name`. 저장 파일은 schema 6 그대로 (프로필에 `name` 이 없으면 빈 이름).
v14 → v15: 휴대폰 연출 — `phone{on}`(꺼내 듦/넣음 → 플레이어 정보 · 스냅샷의 `phone`), `phone_tap`(들고 있을 때만, 120ms에 한 번 → 다른 사람에게 `act{kind: "phone_tap"}`). 끊기면 `phone` 은 false. 저장 파일은 그대로.
v15 → v16: 휴대폰 앱 · 놀거리 — 도감 · 업적 · 칭호(`profile` 의 `stats dex ach title birthday`, 새로 이루면 `ach{ids}`, `set_title` → `title{id title}` 방 전체, 플레이어 정보의 `title`), 생일(`set_birthday`, 그날 주민 축하 마을톡 · 선물, 주민 생일은 `npcs.json` 의 `birthday` · `talk_open.bday`), 날씨 · 달력(`cal_info` → `cal`), 친구 집 놀러 가기(`home_visit` → `home` · 주인에게 `visit`), 방명록(`home.gb`, `gb_write` → `gb`), 마을톡 사진(`photo_up` → `photo_sent` · 메시지의 `ph`(글은 한마디, 없으면 "📷 사진"), `photo_get` → `photo`, 사진만 큰 메시지 허용). 에러 `bad_title bad_birthday not_visitable bad_photo no_photo`. 저장 파일은 schema 6 그대로 (프로필에 `stats dex ach title birthday bdayYear visitDay`, world 에 `guestbooks photos photoSeq notedDay` — 없으면 빈 값).
v9 → v10: 아파트 집 안 — 공동 현관에서 들어가기·현관문으로 나가기(`home_enter` `home_exit` → `home`), 집 가구 놓기·옮기기·회수(`home_place` `home_move` `home_pickup` → `home_f`), 에러 `not_at_lobby` `not_home` `not_editable` `home_full`. 평형이 26·27·34·35평으로 바뀌었다(호수 id 는 그대로). 저장 파일은 schema 5 그대로 (world 에 `homeItems homeItemSeq`).

## 클라이언트 → 서버
| t | 필드 | 설명 |
|---|---|---|
| `create` | `v uid name?` | 방 생성 + 입장. `uid`는 기기에 저장된 영구 ID(8~64자 `[A-Za-z0-9_-]`). v14 `name` = 쓸 닉네임 (비었거나 쓸 수 없으면 무시) |
| `join` | `v uid code name?` | 방 코드(대소문자 무관)로 입장. 같은 `uid`는 쓰던 자리·인벤토리를 되찾는다. `name` 은 `create` 와 같다 |
| `resume` | `v`, `token` | 끊긴 자리로 복귀 (유예 시간 안에서만) |
| `move` | `x y z yaw vx vz` | 내 위치 요청 (m, rad). 서버가 속도·경계 검사 |
| `ping` | `c` | 클라이언트 시각. `pong`으로 RTT·서버 시계 추정 |
| `fish_cast` | `rid spot x? z?` | 낚시터에 던지기 요청. **낚싯대를 손에 들고** 수역 `cast_range` 안에 있어야 한다. v13: `x z` = 찌를 떨어뜨릴 자리(물 안, 캐릭터에서 7m 안 — 아니면 `bad_cast`). 주면 그 둘레의 보이는 물고기가 알아채고 다가온다 |
| `fish_hook` | `rid reaction` | 챔질 요청. `reaction` = 입질 연출이 보인 뒤 버튼을 누르기까지 걸린 ms (입질 전이면 0) |
| `fish_reel` | `rid taps[]` | 끌어올리기 연타 (v11). `taps` = 서버 `fish_reel` 을 받아 연타 화면이 뜬 뒤 누른 시각들(ms). 필요한 수를 채우면 바로, 못 채우면 시간이 다 됐을 때 보낸다 |
| `fish_cancel` | | 낚시 취소 |
| `msg_send` | `rid th tx` | 마을톡 보내기 (v11). `th` = `npc:<주민>` 또는 `pl:<자리>`(같은 마을 친구), `tx` 1~200자. 시스템 방(`sys:*`)·나 자신·없는 방은 `bad_message` |
| `msg_read` | `th` | 그 대화방을 다 읽었다 (답 없음) |
| `equip` | `slot` | 손에 들 퀵슬롯 번호(0~4, `-1` = 빈손). 거절되면 `inventory`로 서버 값을 다시 보낸다 |
| `inv_move` | `rid from to` | 칸 옮기기. 같은 아이템이면 쌓을 수 있는 만큼 합치고, 아니면 맞바꾼다 |
| `inv_discard` | `rid slot n` | 칸에서 n개 내려놓기. v13: 사라지지 않고 발밑에 `drop{kind: "item"}` 으로 남는다 (집·상점 안은 `cant_drop_here`, 마을 바닥에 150묶음이 넘으면 `ground_full`). 도구는 `cant_discard` |
| `chop` | `rid tree` | 도끼질 요청. **도끼를 손에 들고** 다 자란 나무에서 `chop_range` 안 |
| `talk` | `rid npc` | 주민에게 말 걸기. `talk_range` 안, 다른 사람과 이야기 중이 아니어야 한다 |
| `talk_end` | | 대화 끝 (주민이 다시 걷는다) |
| `quest_accept` | `rid` | 이번 대화에서 받은 부탁 제안 수락 |
| `quest_decline` | | 제안 거절 |
| `quest_turnin` | `rid quest` | 부탁 완료. 그 부탁을 한 주민과 대화 중이고 아이템이 다 있어야 한다 |
| `shop_enter` | `rid` | 상점 문(`door`)에서 `enter_range` 안이면 서버가 실내로 옮긴다 → `shop_door` |
| `shop_exit` | `rid` | 실내 출구(`exit`)에서 `exit_range` 안이면 밖으로 옮긴다 → `shop_door` |
| `shop_sell` | `rid slot n` | 칸의 물건 n개 팔기 (실내에서만, 도구는 `cant_sell`) |
| `shop_buy` | `rid item n` | 지금 단계까지 열린 진열품 n개(1~99) 사기 (실내에서만). v13: 식재료는 가방 대신 식당 창고로 (`shop_result.stored`, 재료마다 999개까지 — 넘으면 `storage_full`) |
| `deliv_order` | `rid item n` | v13 식재료 배달 주문 (어디서나). 지금 상점에서 파는 식재료만(`not_for_sale`), n 1~99, 한 사람이 동시에 3건까지(`delivery_busy`). 값 + 배달비(3,000솔)를 바로 낸다. 아직 상점을 떠나지 않은 내 상자가 있으면 거기에 같이 담고 배달비는 받지 않는다(묶음 배달) |
| `place` | `rid slot x z rot` | 가구 설치. 서버가 0.5m 격자로 맞추고, 3m 안·물/나무/다른 가구/상점 앞이 아닌 곳만 |
| `pickup` | `rid id` | 내가 놓은 가구를 2.5m 안에서 줍기 |
| `wear` | `rid slot` | 칸의 옷 입기 (입던 옷은 그 칸으로) |
| `unwear` | `rid part` | `hat` / `top` 벗기 (가방에 빈자리가 있어야) |
| `collect` | `rid id` | 바닥의 선물 풍선·별 조각·채집물·내려놓은 물건 줍기 (`collect_range` 2m 안, 가방에 빈자리). v13: 내려놓은 묶음은 들어가는 만큼만 줍고 나머지는 남는다 |
| `shop_sell`/`shop_buy` + `at: "merchant"` | | 떠돌이 상인과 거래: 상인 곁(대화 거리 +1m)에서만. 상인이 찾는 물건만 2배 값에 사고(그 밖은 `not_wanted`), 보따리 물건(`stock`)을 판다. 상점 포인트는 쌓이지 않는다 |
| `shop_buy` + `at: "airport"` | | 공항 기념품 사기 (v6): 조종사 곁(`shop_range` 3.2m +0.5)에서만, `airport.json` 의 `stock` 만. 팔기는 `cant_sell`. 상점 포인트는 쌓이지 않는다 |
| `plant` | `rid x z` | 손에 든 씨앗 심기 (v6). 서버가 0.5m 격자로 맞추고, `plant_range` 안·섬 풀밭·길/물/건물/집 아님·나무 2.2m(꽃은 1m)·꽃 0.85m·가구 0.9m 떨어진 곳만. 나무 씨앗 → `tree`, 꽃씨 → `flower` |
| `pick` | `rid id` | 활짝 핀 꽃 따기 (v6, `plant_range` 안). 꽃 아이템 1개, 꽃은 봉오리로 돌아간다 |
| `emote` | `e` | 감정표현·몸짓 (v6). 배운 감정표현만(`unknown_emote`), 몸짓 `brake` 는 언제나. 0.7초 간격(몸짓은 0.2초). 결과 메시지 없음 — 상대에게 `act`, 근처 주민 반응은 `npc_emote` |
| `emote_quick` | `quick[]` | 감정표현 퀵슬롯 순서 저장 (v6, 배운 것만, 4칸까지) → `profile` |
| `talk_topic` | `topic` | 대화 중인 주민과 주제 수다 (v6): `mood hobby gossip fish past dream food you` + v8 `worry`(고민 상담 — F 주민은 공감해 주고 친밀도 +1 더) `mbti`. 하루 3번까지 친밀도 +1 → `talk_topic` |
| `donate` | `rid slot` | 박물관 관장 곁(`donate_range`)에서 칸의 물고기 기증 (v6). 한 종에 한 마리(`already_donated`), 물고기만(`not_fish`) |
| `stock_order` | `rid id side qty` | 주식 시장가 주문 (v8). `side` = `buy`/`sell`, `qty` 1~`max_order_qty`. 지금 가격으로 바로 체결, 수수료 0.015%, 매도는 증권거래세 0.18%. 모르는 종목·수량은 `bad_order`, 장이 닫히면(`MARKET_HOURS=krx`) `market_closed`, 보유보다 많이 팔면 `not_enough_shares` → `stock_result` |
| `apt_buy` | `rid unit loan` | 아파트 사기 (v8). `unit` = `"101-803"`(동-층호). 시세 + 취득세 1.1% + 중개보수 0.4% 를 솔 + 주택담보대출(`loan`, 시세 × LTV 70% 이하, DSR 40% 이하, 대출 6건까지)로 낸다. 이미 누가 가졌으면 `unit_taken`, 한도 초과 `loan_limit` → `apt_result`, 방 전체에 `homes`. v9: `policy: "didimdol"` 이면 동사무소에서 받은 승인(2주)으로 디딤돌대출 — 승인 금리 **고정**, 승인 한도·집값 상한·LTV(생애최초 80%), 승인이 없거나 지났으면 `not_eligible`. 세대(부부) 가 이미 집이 있으면 받을 수 없다 |
| `apt_sell` | `rid unit` | 내 집 팔기 (v8). 시세 − 중개보수, 그 집 담보대출부터 갚고(모자라면 남은 빚은 신용대출로) 나머지가 솔로 → `apt_result`, `homes` |
| `bank_quote` | | 은행 창구 정보 요청 (v8) → `bank` |
| `loan_take` | `rid amount product` | 신용대출 (v8). 10만 솔 이상(`bad_loan`), 남은 신용 한도·DSR·건수(`loan_limit`) 안에서 → `loan_result`, `bank`. v9: `product: "sunshine_youth"` 는 서민금융 창구 곁에서만(`not_at_civic`), 만 34세 이하·연 소득 3,500만 이하(`not_eligible`), 1,200만까지, 소득 없으면 4.0% · 있으면 4.5% **고정** |
| `loan_repay` | `rid id amount` | 대출 갚기 (v8, 원금에서 빠진다. 다 갚으면 목록에서 사라짐) → `loan_result`, `bank` |
| `rest_open` | `rid` | 식당 문 열기 (v8). 카운터(`restaurant.json` 의 `counter`) `open_range` 2.6m(+0.5) 안(`not_at_restaurant`), 다른 사람이 열었으면 `rest_busy`. 문을 연 사람 가방의 재료로 장사한다 → `rest_opened`, `rest` |
| `rest_close` | `rid` | 문 닫기 (연 사람만) → `rest_closed{reason: "closed"}`. v9: 직원이 보내면 일을 그만둔다 → 방 전체에 `rest_staff{joined: false}` |
| `rest_join` | `rid` | 열린 식당에 직원으로 들어가기 (v9). 카운터 곁(`not_at_restaurant`), 이미 직원이면 무시 → `rest_joined`, 방 전체에 `rest_staff{joined: true}`, `rest`. 직원들 가방 재료를 합쳐 주문을 받는다 |
| `rest_cook` | `rid order step` | 이 주문의 `step` 번째 동작을 맡는다 (v9, 직원만). 서버가 그 동작 시작 시각을 잰다. 다른 사람이 맡았으면 `step_taken` → `rest_claim`, `rest` 의 `orders[].steps` |
| `rest_step` | `rid order step taps[]` | 맡은 동작 끝 (v9). `taps` = 동작을 시작하고 누른 시각들(ms). 동작의 가장 짧은 시간 90% 보다 빠르면 `cook_too_fast`, 떠난 손님 `order_gone` → `rest_stepped`. 마지막 동작이 들어오면 서버가 판정해 함께 만든 사람 모두에게 `rest_result`, 방 전체에 `rest_served` (떼어 둔 재료가 없으면 `missing_ingredient`) |
| `civic_info` | | 동사무소 창구 정보 요청 (v9) → `civic` |
| `civic_civil` | `rid service` | 민원 (v9, 민원 창구 `service_range` 2.6m(+0.5) 안, `not_at_civic`). `move_in`(무료, 이미 전입이면 `not_eligible`) · `resident_copy`(400솔) · `family_cert`(1,000솔, 혼인한 사람만) → `civic_result{service, fee, doc}` |
| `civic_apply` | `rid program` | 정책 신청 (v9, 그 정책 창구 곁). `youth_rent` · `emergency_living` · `local_card` · `didimdol`(승인). 자격이 안 되면 `not_eligible`, 모르는 정책 `bad_program` → `civic_result{program, weekly weeks / amount / approval}`, `civic` |
| `marry_propose` | `rid to` | 혼인신고 제안 (v9). 두 사람 모두 민원 창구 곁(+2.5m), 상대가 접속 중(`no_partner`), 둘 다 미혼(`already_married`) → `civic_result{service: "marriage_asked"}`, 상대에게 `marry_proposal` |
| `marry_answer` | `rid accept` | 제안에 답하기 (2분 안). 수락하면 두 지갑을 합쳐 한 세대 → 방 전체에 `household`, 둘에게 `profile`·`civic`. 거절하면 제안한 사람에게 `marry_declined` |
| `net` | `rid` | 뜰채질 (v9). **뜰채를 들고**(`no_tool`) 여울 안(+0.6m, `not_in_shallow`), 650ms 마다(`too_fast`). 캐릭터 앞 0.9m 둘레 1.1m(여울에 두 사람이면 1.45m) 안 물고기를 3마리까지 → `net_result`, 방 전체에 `shoal` |
| `dig` | `rid x z mode` | 삽질 (v9). **삽을 들고**(`no_tool`), (x, z) 가 2.2m(+0.5) 안(`bad_dig`), 420ms 마다(`too_fast`). 조개 숨구멍 1.4m 안이면 조개 캐기, 아니면 `mode` = `dig`(풀밭 → 구덩이) / `fill`(구덩이 메우기) / `path`(흙길 깔기·걷기). 길·건물·물·모래밭·나무 곁은 `bad_dig` → `dig_result`, 방 전체에 `tile` 또는 `digspot`·`digspot_gone` |
| `home_enter` | `rid unit` | 아파트 집 안으로 (v10). 그 동 공동 현관 앞(동 앞 4.2m, 2.4m+0.5 안, `not_at_lobby`), 이미 집 안이면 `not_at_lobby`, 모르는 호수 `bad_unit`. 누구 집이든 들어갈 수 있다(구경) → `home`, 서버가 그 집 현관으로 옮긴다 |
| `home_exit` | `rid` | 현관문 곁(2.2m)에서 나가기 → `home{unit: ""}`, 동 앞으로 |
| `home_place` | `rid slot x z rot` | 가방의 가구를 집에 놓기 (v10). 집 안(`not_home`), 내 집·우리 세대 집(`not_editable`), 가구(`bad_item`), (x, z) 는 평면도 기준 미터 → 0.25m 격자, 바닥 위(`bad_place`), 60개까지(`home_full`). `rot` = 45° 단위 0~7 → `home_f` |
| `home_move` | `rid id x z rot` | 집 가구 옮기기·돌리기 (같은 검사) → `home_f` |
| `home_pickup` | `rid id` | 집 가구를 가방에 넣기 (`inventory_full`) → `home_f`, `inventory` |
| `set_face` | `rid face{}` | 얼굴 바꾸기 (v7). 마을 거울(`village_layout.json` 의 `mirrors`)이나 놓인 거울 가구(`items.json` 의 `mirror: true`) 2.2m(+0.5) 안에서만, 상점 안은 안 됨(`not_near_mirror`). `face` 는 바꿀 항목만: `eyes eye_color nose mouth skin hair hair_color` → `face_parts.json` 의 id. 모르는 항목·id·빈 요청은 `bad_face` |
| `set_name` | `rid name` | 닉네임 바꾸기 (v14, 어디서나). 앞뒤 공백을 지우고 띄어쓰기는 한 칸으로, 글자·숫자·띄어쓰기·`_ - .` 만 10자까지 — 아니면 `bad_name`. 빈 문자열 = 자리 기본 이름으로 |
| `phone` | `on` | 휴대폰을 꺼내 들었다(true) · 넣었다(false) (v15, 연출용 — 답 없음). 다른 사람 화면에서 `players[]`/`snap.p[]` 의 `phone` 으로 들고 보는 모습 |
| `phone_tap` | | 휴대폰 화면을 눌렀다 (v15, 들고 있을 때만, 120ms에 한 번). 다른 사람에게 `act{id, kind: "phone_tap"}` |
| `set_title` | `rid id` | 칭호 달기 (v16): 이룬 업적 id 만, `""` = 떼기. 아니면 `bad_title`. 결과 `title{rid, id, title}` · 다른 사람에게 `title{id, title}` |
| `set_birthday` | `rid birthday{m, d}` | 생일 정하기 (v16). 없는 날짜는 `bad_birthday`. 오늘로 정하면 바로 축하 (한 해에 한 번) |
| `cal_info` | | 날씨 · 달력 (v16, 답 `cal`) |
| `home_visit` | `rid unit` | 친구 집에 바로 놀러 가기 (v16): 주인이 있는 집만(`not_visitable`), 낚시 · 배달 중엔 안 됨. 답 `home`, 주인에게 `visit{id, unit}` + 마을톡 |
| `gb_write` | `rid tx` | 방명록 쓰기 (v16): 주인이 있는 집 안에서만(`not_home`), 100자, 8초에 한 번(`too_fast`). 그 집 안 사람 모두에게 `gb` |
| `photo_up` | `rid th img tx?` | 사진 보내기 (v16): `th` = `pl:<자리>`, `img` = base64 JPEG (96KB 이하, `bad_photo`), 4초에 한 번. 두 사람 대화방에 `msg{m: {…, ph}}`, 보낸 사람에게 `photo_sent{rid, id, th}`. 이 메시지만 `maxMessageBytes` 를 넘어도 된다 |
| `photo_get` | `id` | 마을톡 사진 받기 (v16): 답 `photo{id, img}` (없으면 `no_photo`) |

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
| `market_tick` | `minute open source q{id: 가격}` | 1분마다 바뀐 시세 (v8, 모든 방에 같은 값). `source` = `sim`(내장 모의 거래소) / `feed`(외부 시세 서버) |
| `stock_result` | `rid id side qty price amount fee tax sol holding{q, cost}` | 주문 체결 (v8) |
| `homes` | `index owners{unit: 자리} bought{unit: 산 값}` | 아파트 주인 목록과 집값 지수 (v8) |
| `apt_result` | `rid kind unit price tax? fee loan? repaid? sol` | 아파트 사기(`kind: buy`)·팔기(`sell`) 결과 (v8) |
| `bank` | `base score grade rate_credit rate_mortgage credit_limit ltv dsr income_year income_week week loans[]` | 은행 창구 정보 (v8) |
| `loan_result` | `rid kind(take/repay) loan? id? paid? left? sol` | 대출·상환 결과 (v8) |
| `week` | `week rent interest capitalized missed base index sol` | 한 주 정산 (v8): 월세 수입, 낸 이자, 못 내서 원금에 붙은 이자, 연체 여부, 새 기준금리·집값 지수 |
| `rest` | `open owner rating tier served revenue regulars{손님: 요리} capacity shift{served, revenue} orders[]` | 식당 상태 (v8). `orders[]` = `{id, customer, dish, seat, left(ms), patience(ms), cooking, regular}`, `capacity` = 남은 재료로 더 만들 수 있는 그릇 수(예상) |
| `rest_opened` / `rest_closed` | `rid` / `reason` | 문 열림 / 닫힘 (`closed` `owner_left` `idle` `no_ingredients`) |
| `rest_order` | `order customer dish seat regular` | 손님이 앉아 주문 (v8) |
| `rest_result` | `rid order stars pay share team quality taste sol` | 함께 만든 요리의 판정 (v8, v9 에서 만든 사람 모두에게). `share` = 내 몫(팀이면 값 +10% 를 나눔), `rid` 는 마지막 동작을 낸 사람에게만 |
| `rest_served` | `order customer dish stars pay regular became lost by` | 누가 요리를 냈다 — 단골이 됐는지(`became`)·풀렸는지(`lost`) |
| `rest_left` | `order customer dish reason lost` | 손님이 떠났다 (`late` 기다리다 지침 / `missing` 재료가 사라짐) — 별 1개 |
| `rest_joined` / `rest_staff` | `rid` / `id joined` | 직원으로 들어감 (v9) / 누가 들어오거나 나감 |
| `rest_claim` | `rid order step` | 그 동작을 맡음 (v9, 지금부터 시간을 잰다) |
| `rest_stepped` | `rid order step` | 그 동작을 받음 (v9) |
| `civic` | `resident movedIn age married partner income_year homes card approvals programs[{id, ok, reasons[], terms, got}]` | 동사무소 창구 정보 (v9). `reasons` 는 안 되는 이유("만 34세 이하" 등), 디딤돌·햇살론은 `terms`(금리·한도·집값 상한·LTV) |
| `civic_result` | `rid service fee doc sol` / `rid program …` | 민원·정책 결과 (v9). `doc` = 등본·증명서 내용(`{kind, title, self, spouse, since, …}`) |
| `marry_proposal` / `marry_declined` | `from` / `by` | 혼인신고 제안 받음 / 거절됨 (v9) |
| `household` | `id members[] since sol` | 한 세대가 됐다 (v9, 방 전체). 이제부터 두 사람의 `profile.sol` 은 같은 지갑 |
| `net_result` | `rid fish[] coop lost` | 뜰채질 결과 (v9). `fish` = 가방에 들어간 물고기, `lost` = 가방이 차서 놓친 수, `coop` = 여울에 둘 이상 |
| `shoal` | `id panic f[[id, x, z, size]]` | 여울 물고기 떼 (v9, 움직일 때마다 방 전체). `panic` = 둘 이상이 들어와 허둥댐 |
| `dig_result` | `rid kind …` | 삽질 결과 (v9). `kind: "spot"`(숨구멍 hp 줄어듦, `coop`) / `"clam"`(다 팠다 — 판 사람 모두에게, `item full coop`) / `"dig" "fill" "path"`(`x z s item`, 구덩이에서 나온 것) |
| `tile` | `x z s` | 땅 칸이 바뀜 (v9, 방 전체). `s` = `hole` / `path` / `""`(원래대로) |
| `digspot` / `digspot_gone` | `d{id, kind, x, z, hp}` / `id by` | 조개 숨구멍이 돋았거나 hp 가 줄었다 / 다 파서 사라졌다 (v9) |
| `coop_bonus` | `kind item n with` | 같이 해서 받은 덤 (v9, 지금은 같이 쓰러뜨린 나무 — 상대가 마지막에 찍었을 때) |
| `home` | `rid unit plan ox oz owner edit x y z f[]` | 집에 들어감 (v10) — `plan` = 평면도 id(`26a` `26b` `27` `34` `35`), `ox oz` = 집 안 월드 원점(평면도 왼쪽 위), `owner` = 주인 자리(0 = 아직 아무도 안 삼), `edit` = 꾸밀 수 있는지, `x y z` = 옮겨진 자리, `f` = 가구 `[[id, item, x, z, rot]]`. 나오면 `unit: ""` 와 `x y z` 만. 집 안에서 끊겼다 돌아오면 `welcome` 뒤에 다시 온다 |
| `home_f` | `rid unit f[]` | 그 집 가구 목록 (v10, 요청한 사람에게는 `rid` 와 함께, 같은 집 안의 다른 사람에게도) |
| `inventory` | `slots[] quick cap held` | 내 인벤토리 전체. `slots` 길이 = `quick + cap`, 앞 `quick` 칸이 퀵슬롯, 빈 칸은 `null`. `held` = 손에 든 퀵슬롯(-1 = 빈손) |
| `profile` | `sol quests[] friends{} outfit emotes face` | 내 솔(화폐)·받은 부탁·주민 친밀도·입은 옷·감정표현(`{known[], quick[]}`, v6)·얼굴(v7). 바뀔 때마다 나에게만 |
| `fish_started` | `rid spot zone coop shadow fid? size? ms? bx? bz?` | 던지기 수락. v13 겨눠 던지기: `fid` = 찌를 알아챈 물고기(`fishes` 의 id, 없으면 "" 그리고 `shadow` 0 → 나중에 `fish_found`), `ms` = 그 물고기가 찌 앞까지 오는 시간, `bx bz` = 찌 자리. v11: `shadow` = 물 밑에서 다가오는 그림자 크기 (희귀도 흔함 0.75 · 보통 1.0 · 희귀 1.35 × 몸 S 0.85 · M 1 · L 1.2 — 어떤 물고기인지는 모른다). v9: `zone` = `shallow`/`deep`(찌가 떨어진 물, 얕으면 작은 물고기만·깊으면 큰 물고기 1.6배), `coop` = 9m 안에서 같이 낚시 중(기다림 ×0.7 · 희귀 ×1.35) |
| `fish_nibble` | `rid` | 가짜 입질 (0~3번). 아직 당기면 안 된다 |
| `fish_bite` | `rid windowMs` | 진짜 입질. 물고기 종류는 알리지 않는다 |
| `fish_reel` | `rid taps ms` | 챔질 성공 → 끌어올리기 (v11): `ms` 안에 `taps` 번 연타해야 한다 |
| `fish_result` | `rid ok fish? reason? bonus?` | 서버가 확정한 결과. 실패 사유: `early late escaped moved cancelled inventory_full snapped`(v11: 연타가 모자라 놓침). 낚시 대회 중이면 `bonus` 솔을 더 받았다 |
| `chop_result` | `rid ok item n tree felled coop` | 도끼질 성공. `item` `n`개(나무꾼의 날 2개)가 인벤토리에 들어갔고, `felled`면 나무가 쓰러졌다. v9: `coop` = 4초 안에 다른 사람이 찍은 나무라 두 번 찍은 셈 (같이 쓰러뜨리면 둘 다 +1) |
| `tree` | `id s c k? x? z? by?` | 나무 상태 변화 (방 전체). `s` = `grown` / `stump` / `sprout` / `sapling` / `young` (v6: 게임 시간으로 자람), `c` = 오늘 찍힌 횟수. 씨앗을 심은 나무(`id` = `p…`)는 `k`(종류) `x z`도 실린다 |
| `act` | `id kind tree? e?` | 상대의 동작: `kind: chop`(도끼질, `tree`), `kind: emote`(감정표현·몸짓 `e`, v6) |
| `npcs` | `st n[]` | 주민 위치 (방 전체, 움직이거나 기분이 바뀔 때 10Hz). `n[]`: `{id, x, z, yaw, talk, m}` (`talk` = 대화 중인 플레이어 id, 0 = 없음, `m` = 기분 `happy calm sad grumpy sleepy excited`, v6, `ap` = 먼저 말을 걸러 다가가는 플레이어 id, v11) |
| `npc_greet` | `npc` | 친한 주민이 내 곁까지 걸어와 먼저 말을 걸었다 (그 사람에게만, v11). 클라이언트는 인사·한마디(`dialogue.json` 의 `approach`)를 보이고, 가만히 있으면 대화를 연다 |
| `msg` | `th m{f, tx, at}` | 마을톡 새 메시지 (v11). `f` = `me` · 주민 id · `bank` · `town` · `p<자리>`, `at` = 유닉스 ms. `{player}` 는 받는 화면에서 그 사람 이름으로 채운다 |
| `talk_open` | `rid npc f first m quest? ready? offer? teach? gift?` | 말 걸기 수락. `f` 친밀도, `first` 오늘 첫 대화, `m` 지금 기분, `quest` 이 주민의 진행 중 부탁(`ready` = 지금 완료 가능), `offer` 새 부탁 제안, `teach` 이번에 가르쳐 준 감정표현, `gift` 친해져서 준 선물(이미 가방에) |
| `talk_topic` | `npc topic f gain m` | 주제 수다 결과 (v6): `gain` = 오른 친밀도(하루 상한이면 0), `m` = 수다 뒤 기분 |
| `npc_emote` | `npc e to m from` | 주민이 감정표현에 반응했다 (방 전체, v6): `e` 주민의 몸짓, `to` 감정표현을 한 사람, `m` 바뀐 기분, `from` 그 사람의 감정표현 |
| `flower` | `f by?` | 꽃이 생기거나 자라거나 따였다 (방 전체, v6). `f` = `{id, sp, c, x, z, s}` (`sp` 종류, `c` 색 번호, `s` = `sprout`/`bud`/`bloom`), `by` = 그렇게 한 사람(저절로 자라면 없음) |
| `plant_result` | `rid id kind x z` | 내가 심었다 (`kind` = `tree`/`flower`) |
| `pick_result` | `rid id item` | 내가 꽃을 땄다 |
| `face` | `rid? id face{}` | 누군가 얼굴을 바꿨다 (v7, 방 전체 — 바꾼 사람에게는 `rid` 와 함께). `face` = 일곱 항목 전부 |
| `name` | `rid? id name` | 누군가 닉네임을 바꿨다 (v14, 방 전체 — 바꾼 사람에게는 `rid` 와 함께). 이어받은 자리로 `join` 하며 이름이 바뀌어도 다른 사람에게 온다 |
| `museum` | `fish{} id by` | 박물관 기증 목록이 바뀌었다 (방 전체, v6). `fish` = 물고기 id → 기증한 사람 자리 번호 |
| `donate_result` | `rid fish reward sol count gifts[]` | 내가 기증했다: 감사 `reward`솔, 지금까지 `count`종, 문턱을 넘어 받은 기념품 `gifts` |
| `talk_closed` | `npc` | 서버가 대화를 끝냄 (멀어짐·시간 초과) |
| `quest_accepted` | `rid quest` | 부탁 수락 확정 |
| `quest_done` | `rid quest npc reward sol` | 부탁 완료. 아이템을 가져가고 `reward`솔을 줬다 |
| `weather` | `w` | 날씨 변화: `clear` / `cloudy` / `rain` / `thunder` |
| `shop_door` | `inside x y z shop` | 서버가 나를 상점 안/밖으로 옮겼다 (클라이언트는 그 자리로 순간이동) |
| `shop_result` | `rid kind item n sol amount back` | 사고팔기 성공 (`kind` = `buy`/`sell`, `amount` = 오간 솔, v9 `back` = 천안사랑카드 캐시백) |
| `shop` | `level points next up` | 상점 단계·포인트 (방 전체). `next` = 다음 단계 문턱(마지막이면 null), `up` = 방금 커졌다 |
| `placed` | `rid by f` | 가구가 놓였다 (방 전체). `f` = `{id, item, x, z, rot, owner}` (`owner` = 놓은 사람 자리 번호) |
| `unplaced` | `rid id` | 가구가 치워졌다 (방 전체) |
| `lightning` | `st power` | 번개 (뇌우일 때, 방의 모두에게 같은 순간). `power` 0.6~1 |
| `ev` | `day list[]` | 지금 열린 이벤트가 바뀌었다 (방 전체). `list[]`: `{id, wanted?, mult?, stock?}` — `wanted` 오늘 2배로 사 주는 물건, `stock` 떠돌이 상인의 보따리 |
| `drop` | `d by?` | 바닥에 선물·별 조각이 떨어졌다 (방 전체). `d` = `{id, kind, x, z, item?, n?}` (`kind` = `gift`/`star`/`forage`/`item`, 선물 속 `item`은 주울 때까지 비밀). v13 `item` = 사람이 내려놓은 묶음(`n`개, id `g…`) — 같은 id 가 다시 오면 개수가 바뀐 것 |
| `deliv_ok` | `rid id item n amount fee eta sol merged items orders` | v13 배달 주문 수락. `eta` = 상자가 출발할 때까지 초 (20~30), `merged` = 기존 상자에 같이 담김(`fee` 0), `items` = 상자 안 `[{item, n}]`(같은 재료는 합침), `orders` = 상자에 담긴 건수 |
| `couriers` | `c[]` | v13 길 위의 배달 알바들 `{id, x, z, yaw, ph, to, item, k}` (`item` = 상자의 첫 재료, `k` = 재료 가짓수) (`ph` = `walk` 뛰어가는 중 · `hand` 건네는 중 · `back` 돌아가는 중, `to` = 받는 사람 자리). 움직이는 동안 주민 틱마다 |
| `deliv_done` | `id items[]` | v13 배달 상자를 받았다. `items` = `[{item, n, where}]`, `where` = `bag` / `storage`(가방이 가득 · 집이나 상점 안에 90초 넘게 · 접속 안 함) |
| `fishes` | `spot f[]` | v13 그 낚시터 물 밑 물고기 그림자들 `{id, x, z, yaw, s, r, st, o}` (`s` = 몸 크기 S·M·L, `r` = 희귀도 — 어떤 물고기인지는 모른다, `st` = `roam`/`engaged`/`flee`, `o` = 낚는 사람 자리). 사람이 28m 안에 있는 호수 · 바닷가에 선 사람 앞바다만 |
| `fish_found` | `rid fid shadow size ms` | v13 겨눈 찌 둘레에 없던 물고기가 지나가다 알아챘다 (그 물고기가 다가와 문다) |
| `drop_gone` | `id by` | 주웠거나(`by` = 주운 사람) 이벤트가 끝나 사라졌다(`by` = 0) |
| `collect_result` | `rid id kind item` | 내가 주웠다. `item` 1개가 인벤토리에 들어갔다 |
| `error` | `code msg rid?` | 아래 에러 코드 |

`players[]`/`p[]` 항목: `{id, online, fishing, phone, held, hat, top, x, y, z, yaw, vx, vz}` (`fishing`은 낚시 자세, `held`는 손에 든 아이템 id, `hat`·`top`은 입은 옷 — 상대 캐릭터 표시용). `welcome.players[]`·`peer_joined.p` 에는 `face` 도 실린다 (v7, 스냅샷 `snap.p[]` 에는 없다 — 바뀌면 `face` 메시지) · `name` 도 (v14, 빈 문자열 = 자리 기본 이름, 바뀌면 `name` 메시지). `prof.name` = 내 닉네임.
`profile`에는 `outfit {hat, top}`도 실린다. `st`/`s`는 서버 단조 시계(ms).

부탁(`quest`/`offer`/`quests[]`): `{id, npc, kind, item?, n, reward, exp, have}` — `kind` = `deliver`(재료 n개) / `deliver_fish`(그 물고기 n마리) / `any_fish`(아무 물고기 n마리), `exp` = 이 마을 날짜까지 유효, `have` = 지금 인벤토리로 채운 개수.

v16 서버 → 클라이언트: `ach{ids}`(새로 이룬 업적) · `title{rid?, id, title}` · `cal{today, days[{day, y, m, d, wd, season, w[8], ev, meteor, npc[], pl[]}], econ}`(오늘부터 이레, `w` = 0 · 3 · … · 21시 칸 날씨) · `gb{rid?, unit, list[{by, tx, at}]}` · `visit{id, unit}` · `photo_sent{rid, id, th}` · `photo{id, img}`. `profile` 의 v16 값: `stats`(업적 판정 값 — `data/achievements/achievements.json` 의 `stats`), `dex{fish{id: 낚은 수}, items[]}`, `ach[{id, at}]`, `title`, `birthday{m, d}|null`.

에러 코드: `bad_version bad_message not_in_room already_in_room room_not_found room_full resume_failed rate_limited not_at_spot already_fishing not_fishing inventory_full bad_item cant_discard no_tool not_near_tree tree_not_ready too_fast not_near_npc npc_busy not_talking no_offer bad_quest quest_not_ready not_near_door not_in_shop not_for_sale not_enough_sol cant_sell bad_place place_limit not_owner not_wearable no_drop merchant_away not_wanted not_seed bad_plant plant_limit no_flower unknown_emote not_near_keeper already_donated not_fish bad_topic not_near_mirror bad_face bad_name market_closed bad_order not_enough_shares bad_unit unit_taken not_your_unit loan_limit bad_loan rest_closed rest_busy not_at_restaurant order_gone missing_ingredient cook_too_fast not_staff step_taken not_at_civic not_eligible bad_program no_partner already_married not_in_shallow bad_dig not_at_lobby not_home not_editable home_full cant_drop_here ground_full delivery_busy storage_full bad_cast` (앱 안 테스트 서버는 지원하지 않는 요청에 `test_server`)

## 입장 정보 (`welcome`)
- `inv` = `inventory`, `prof` = `profile` 과 같은 모양.
- `clock` = `{g, s, st}`: 서버 시각 `st`(ms)일 때 마을 시각이 `g`(마을 시간대 벽시계를 epoch ms로 나타낸 값)이고 `s`배로 흐른다. 클라이언트는 `g + (서버시각 − st) × s` 로 지금 마을 시각을 계산한다. 하루는 **새벽 5시**에 바뀐다.
- `w` = 지금 날씨, `trees[]` = `{id, s, c}` 전체, `npcs[]` = 주민 위치 전체, `shop` = `shop` 메시지와 같은 모양, `placed[]` = 설치된 가구 전체.
- `ev` = `ev` 메시지와 같은 모양(지금 열린 이벤트), `drops[]` = 바닥의 선물·별 조각·채집물 전체.
- `market` (v8) = `{minute, open, source, fee, tax, stocks[{id, name, sector, about, price, ref, hist[]}]}` — `ref` 는 오늘 기준가(어제 마지막 가격), `hist` 는 최근 120분 가격. `homes` = `homes` 메시지, `rest` = `rest` 메시지와 같은 모양.
- v9: `civic` = `civic` 메시지, `tiles[[x, z, s]]` = 고친 땅 칸 전체, `digspots[]` = 조개 숨구멍 전체, `shoals[]` = 여울 물고기 떼 전체. `prof.civ` = `{age, resident, card, partner, household, since, approvals}`, `prof.loans[]` 에 `product fixed`.
- v11: `chats` = `{th: {m: [{f, tx, at}], read}}` 마을톡 대화방 전체 (처음이면 `sys:town` 환영 인사).
- `prof` 의 경제 정보 (v8): `stocks{id: {q, cost}}`, `trades[]`(최근 10건), `loans[{id, kind, principal, rate, unit, since, weekly}]`, `credit{score, grade}`, `income{week, year}`, `worth{assets, debt, net}`.

## 마을 이벤트 (서버 판정, `data/events/events.json`)
- 날마다(새벽 5시 기준) 마을 시드와 날짜로 하루 이벤트를 뽑는다: 75% 확률로 아래 다섯 중 하나(가중치), 나머지는 이벤트 없는 날. 저장하지 않아도 언제 계산해도 같다(날씨와 같은 방식).
  | id | 이름 | 시간 | 규칙 |
  |---|---|---|---|
  | `bargain` | 특가 매입의 날 | 하루 종일 | 상점이 고른 물건(물고기 2 + 재료 1)을 2배 값에 사 준다 |
  | `merchant` | 떠돌이 상인 누리 | 9~21시 | 광장(`spot`)에 노점. 찾는 물건(물고기·소지품·재료 하나씩)을 2배 값에 사고, 보따리 물건 4가지를 판다 |
  | `fishing_derby` | 호수 낚시 대회 | 9~18시 | 낚을 때마다 상금(흔한 4,000 · 조금 귀한 15,000 · 귀한 50,000솔), 귀한 물고기가 2.5배 잘 잡힌다 |
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
`fish_cast` → `fish_started{shadow}` → 가짜 `fish_nibble` × 0~3 → `fish_bite{windowMs}` → `fish_hook{reaction}` → `fish_reel{taps, ms}` → `fish_reel{taps[]}` → `fish_result`.
- (v11) 끌어올리기: 흔함 6번/2.6초 · 보통 9번/3.0초 · 희귀 13번/3.4초, L 은 +2번 +0.3초, S 는 −1번. 40ms 보다 촘촘한 누름은 세지 않고, 시각이 거꾸로 가거나 서버가 잰 시간보다 늦은 기록은 실패. `ms + FISH_HOOK_GRACE_MS` 안에 아무것도 안 오면 `snapped`. `FISH_REEL_SCALE` = 횟수 배율 (0 이면 챔질만으로 낚는다 — 옛 테스트용).
- (v11 클라이언트) 찌가 물에 닿으면 그림자가 멀리서 맴돌며 다가오고, 가짜 입질 = 그림자가 쏙 와서 찌를 건드림 + 약한 진동, 진짜 입질 = 그림자가 달려들어 물고 들어감 + 강한 진동 + 찌가 쑥 잠김. 반응 시간은 찌가 잠긴 순간부터 잰다.
- 물고기는 던질 때 서버가 **지금 시각·날씨에 낚이는 물고기 중에서** 가중치로 정하고(`fish.json`의 `hours`·`weather`), 결과가 확정될 때에만 `fish_result.fish`로 알린다.
- 서버는 `reaction`이 허용 창(`hook_window_ms`, 450~700ms) 안인지, 사람이 낼 수 있는 값(≥80ms)인지, 서버가 잰 경과 시간과 모순되지 않는지만 본다. 네트워크 지연은 판정에 들어가지 않는다.
- 입질 전에 당기면 `early`, 창을 넘기면 `late`, 아예 반응이 없으면 `escaped`, 캐스팅 지점에서 1.5m 넘게 움직이면 `moved`.
- 같은 `rid`는 한 번만 처리한다.
- (v13 `server/src/swimmers.js`) 호수마다 물고기 6마리가 늘 헤엄치고(0.25~0.55m/s, 물가 0.9m 안쪽), 바다는 바닷가에 선 사람마다 앞바다(해안선 1.5~4.5m 바깥)에 4마리. 2.5~4분마다 지금 시각·날씨·계절에 맞는 물고기로 바뀐다(얕은 물에 생기면 작은 물고기, 낚시 대회면 희귀 가중치).
- 겨눠 던지기: 찌 둘레 2.6m 안의 물고기 가운데 **찌가 머리 앞쪽에 떨어진** 것이 먼저 알아챈다 (옆이면 +0.8m, 뒤면 +2.5m 만큼 멀게 친다). 알아챈 물고기는 몸을 돌려 찌 앞(머리가 찌를 향하게)까지 헤엄쳐 오고(0.8m/s, 멀면 3.5초 안에 오도록 빠르게), 잠깐 살핀 뒤 톡 2~3번 → 진짜 입질. 그 물고기가 곧 낚일 물고기다. 아무도 없으면 기다리는 1초마다 알아채는 거리가 1.5m 넓어진다. 낚으면 사라지고 20초 뒤 다시 채워진다. 놓치면 휙 달아나 8초 동안 찌를 무시한다.
- (v13 클라이언트) `FishSchool` 이 그림자를 그린다: 모양은 같고 크기 S 0.75 · M 1 · L 1.35, 아우라는 보통 하늘빛 · 희귀 금빛 + 반짝임. 낚시 어시스트: 던지면 5.5m 안의 물고기 가운데 앞쪽 · 가까운 것을 골라 캐릭터를 그쪽으로 돌리고 그 머리 앞 0.85m 에 찌를 던진다. 찌가 떨어지면 카메라가 캐릭터와 찌를 함께 비춘다(세로 화면에 둘 다 들어오게 물러남).

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
- 박물관: 관장 곁에서 한 종에 한 마리 기증, 마을 공용(`museum.fish`). 기증마다 `reward_sol`(5,000솔). 기증 수가 `milestones`(5·15·31)를 넘으면 그 기증을 한 사람에게 기념품 (가방이 차 있으면 다음 기증 때).
- 공항: 조종사 곁에서 `stock` 의 기념품만 산다. 비행기 이착륙은 서버 메시지 없이 마을 시계(`flight.cycle_minutes`)로 클라이언트가 계산한다.

## 증권 (서버 판정, v8)
- 종목 10개 (`data/market/stocks.json`), 서버 전체에 시장 하나 — 모든 방이 같은 시세를 본다. `MARKET_TICK_MS`(기본 60000)마다 한 번 움직인다.
- 시세 출처: 내장 모의 거래소(종목마다 변동성 `vol`·추세 `drift`·평균 회귀·가끔 뉴스 급등락) 또는 외부 시세 서버 `MARKET_FEED_URL` — 1분마다 `GET` 해서 `{"quotes": {"SBE": 71200, …}}`(또는 `[{id, price}]`)를 받는다. 읽지 못하면 그 분은 모의 거래소로 움직이고 게임은 멈추지 않는다. 같은 형식의 연습용 서버: `node server/tools/market_server.js`.
- 호가 단위(KRX), 하루 ±30% 가격 제한(어제 마지막 가격 기준), 시장가 즉시 체결. 장 시간은 기본 언제나 열림, `MARKET_HOURS=krx` 면 평일 9:00~15:30(마을 시계).
- 시세는 `<SAVE_DIR>/market.json` 에 저장해 서버를 다시 켜도 이어진다.

## 아파트 · 은행 (서버 판정, v8)
- 솔바람 성성호수 푸르지오 (`data/realestate/apartments.json`): 3개 동 × 10층 × 2호 = 60호. 1~9층은 59㎡ / 84㎡, 꼭대기 층은 114㎡. 시세 = 평형 기준가 × (1 + 층 할증 + 동 할증) × 마을 집값 지수 (만 원 단위). 한 집은 한 사람만, 마을(방) 단위로 저장.
- 한 주 = 마을 날짜 7일 (`floor(day / 7)`). 주가 바뀌면 방마다: 집마다 월세(시세 × 3.5% / 52)가 들어오고, 대출마다 이자(원금 × 금리 / 52, 올림)가 솔에서 빠진다. 솔이 모자라면 낸 만큼 내고 나머지는 원금에 붙고 연체 1회. 그 뒤 기준금리(12% 확률로 ±0.25%p, 1.5~4.5%)와 집값 지수(로그 정규, 주 +0.15% 추세 · 0.6% 변동)가 한 걸음 움직인다. 오래 비운 마을은 4주까지만 몰아서 계산한다.
- 신용점수 0~1000 (`data/bank/bank.json`): 720 에서 시작, 꼬박꼬박 낸 주 +6, 연체 −45, 연 소득 1천만 솔마다 +12(최대 90), 거래 주 +4(최대 40), 빚/자산이 50% 를 넘은 만큼 × 220 감점. 점수 → 1~10등급(KCB 식 구간). 금리 = 기준금리 + 등급 가산금리(신용 / 주택담보), 최대 19.9%. 매주 새 점수로 다시 매긴다(변동금리).
- 소득 = 번 돈(팔기·부탁 보상·박물관·낚시 대회·월세·식당) 기록, 연 소득 = 최근 4주 평균 × 52. 신용대출 한도 = max(300만, 연 소득 × 1.5) × 등급 배수 (최대 1.5억) − 이미 빌린 신용대출. DSR: (원금 × 금리 + 원금/30) 합 / 연 소득 ≤ 40%. 소득이 없으면 300만 솔까지 신용대출만.

## 식당 (서버 판정, v8)
- 솔바람 식당 (`data/restaurant/restaurant.json`, 요리는 `recipes.json`). 한 마을에 한 사람이 문을 연다(v9: 다른 사람은 직원으로 같이 일한다 — 아래 "같이 하기") — 손님은 **문을 연 사람(v9: 직원 모두) 가방의 재료로 만들 수 있는 요리만** 주문하고, 주문이 들어오는 순간 그 재료를 떼어 둔다(다른 주문이 같은 재료를 겹쳐 쓰지 않는다). 그래서 재료가 모자란 주문은 들어오지 않는다. 시킬 게 없고 앉은 손님도 없으면 `no_ingredients` 로 닫는다.
- 재료: 상점 식재료(1단계 13종, 2단계 감자·버터·레몬), 들판 채집물(산나물·쑥·표고·산딸기·달래, 75초마다 섬 곳곳에 돋아남, 최대 14개), 물고기. `fish: common` 은 그 희귀도 이하 아무 물고기(싼 것부터), `item_any` 는 목록 중 하나.
- 별점 = 최근 20명의 별점 평균(처음엔 2.0 으로 기운다, 가중치 3). 별점이 2.5 · 3.3 · 4.0 · 4.6 을 넘으면 2~5단계 요리가 열린다 — 높은 단계일수록 비싸지만 동작이 많고 판정 창이 좁다. 1단계는 물고기 한 마리 구이처럼 쉽고 마진이 적다.
- 요리 동작: `beats`(박자마다 가장 가까운 누름과의 차이), `timing`(한 번 누른 시각과 딱 좋은 때의 차이), `mash`(시간 안에 누른 횟수, 50ms 보다 촘촘한 누름은 세지 않음). 솜씨 = 동작 평균.
  - (v11) `grill`: `sides` 면을 차례로 굽는다. `taps[k]` = k번째 면을 뒤집은(마지막은 꺼낸) 시각 — 면마다 구운 시간(`taps[k] − taps[k−1]`)과 `side_ms` 의 차이를 `window_ms` 로 본다. 더 누르면 한 번에 0.1 깎는다.
  - (v11) `steam`: `taps` = 재료 `items` 개 넣은 시각 → 물 붓기 시작 → 멈춤 → 뚜껑 연 시각. 솜씨 = (담은 재료 비율 + 물 높이 `(멈춤 − 시작) / fill_ms` 가 1 에 가까운 정도(`water_window`) + 찐 시간과 `steam_ms` 의 차이(`window_ms`)) / 3.
- 손님 별점(1~5) = 1 + 4 × (0.6 × 솜씨 + 0.25 × 입맛 + 0.15 × 시간). 입맛 = 좋아하는 맛 태그 +0.25, 싫어하는 맛 −0.4. MBTI: F 손님은 늦어도 시간 점수가 0.5 아래로 안 떨어지고, T 손님은 솜씨를 1.25 제곱해서 본다. 받는 돈 = 값 × (0.8 · 0.95 · 1.05 · 1.2, 별 2~5) (+단골 10%).
- 단골: 같은 요리에 4점 이상을 3번 연속 주면 단골 — 그 손님은 그 요리만 시킨다(재료가 없으면 시키지 않는다). 3점 아래를 주면 풀린다. 기다리다 떠나면 별 1개.
- 손님 = 주민 6명(각자 입맛) + 섬 밖 손님 6명(등산객·학생·직장인·낚시꾼·미식가·여행객). 기다림은 단계마다 70~140초. 주인이 접속을 끊으면 닫는다, 3분 동안 손님이 없어도 닫는다.
- 시연·테스트: `REST_SPAWN_SCALE=0.05`(손님 빨리), `REST_START_HISTORY=5,5,4`(처음 별점 기록).

## 같이 하기 (서버 판정, v9)
- **식당**: 문을 연 사람이 주인, `rest_join` 한 사람이 직원. 주문은 직원 모두의 가방을 합친 재료로 받고, 떼어 둔 재료는 가진 사람 가방에서 빠진다. 한 주문의 동작은 아무 직원이나 하나씩 맡는다(동시에 가능) — 동작마다 서버가 맡은 시각을 재고, 그 동작의 최소 시간 90% 보다 빨리 끝내면 `cook_too_fast`. 직원이 둘 이상이면 팀(`TEAM`): 손님 인내 ×1.25, 손님이 오는 간격 ×0.8, 판정 창 ×1.15, 값 +10% 를 함께 만든 사람 수로 나눈다(`share`). 주인이 끊기거나 나가면 남은 직원이 주인이 되고, 아무도 없으면 닫는다.
- **나무**: 같은 나무를 다른 사람이 4초 안에 찍었으면 이번 도끼질은 2번으로 센다. 그렇게 쓰러뜨리면 둘 다 +1 (`coop_bonus`).
- **낚시**: 같은 낚시터에서 9m 안에 다른 사람이 낚시 중이면 입질까지 기다림 ×0.7, 희귀(rare) 가중치 ×1.35.
- **여울**: 여울 안에 둘 이상이면 `panic` — 물고기가 2.4m/s 로 느려지고 방향이 흔들리며, 뜰채 반지름이 1.45m.
- **조개**: 같은 숨구멍을 3초 안에 다른 사람이 팠으면 hp 를 2 줄인다. 다 파면 그 숨구멍을 판 사람 모두에게 하나씩.

## 동사무소 · 세대 (서버 판정, v9)
- `data/civic/civic.json`: 건물·창구 직원 3명(`civil` `welfare` `finance`)·민원·정책. 창구 곁 = 직원 자리에서 `service_range` 2.6m(+0.5).
- **세대**: 혼인신고하면 `room.households` 에 `{id, members[uid], wallet{sol}, since}` 가 생기고, 두 프로필의 `sol` 은 같은 `wallet` 을 읽고 쓴다(저장할 때는 세대 지갑만 한 번). 소득은 부부합산(주마다 더함), 자산·빚·집은 세대 전체로 본다. 신용점수는 각자.
- **정책** (한 주 = 한 달): `youth_rent` 주 20만 × 24주(만 19~34세 · 전입 · 무주택 · 연 소득 1,846만 이하, 주간 정산 `week.grant`) / `emergency_living` 78.3만 한 번(솔 10만 이하 · 이번 주 소득 0 · 유동 자산 100만 이하 · 무주택, 4주마다 최대 6번) / `local_card` 상점·상인·공항에서 산 값의 10% 캐시백, 주 4.6만까지(전입) / `didimdol` 승인 2주 — 금리는 세대 연 소득 구간(2천만 이하 2.85% · 4천만 3.15% · 6천만 3.45% · 7천만 3.75% · 8,500만 4.05%), 신혼 −0.2%p, 한도 2.5억(신혼 3.2억), 집값 5억(신혼 6억) 이하, 소득 6천만(신혼 8,500만) 이하, LTV 70%(첫 집 80%), 무주택 세대 / `sunshine_youth` 1,200만, 4.0~4.5% 고정.
- 대출의 `fixed: true` 는 주마다 금리를 다시 매기지 않는다.

## 여울 · 삽 (서버 판정, v9)
- 여울 = `data/fish/spots.json` 의 낚시터마다 `shallows[{id, x, z, half_x, half_z, max, fish[]}]`. 여울 안은 들어갈 수 있고(이동 검사가 물로 막지 않음), 낚시 찌가 여울에 떨어지면 `zone: shallow`.
- 물고기 떼(`server/src/shoal.js`, 규칙은 `data/world/dig.json` 의 `net`): 여울마다 최대 `max` 마리, 14초마다 한 마리씩 다시 참. 3.4m 안의 사람에게서 멀어지는 쪽으로 3.6m/s(허둥대면 2.4m/s), 여울 벽에 막히면 그 방향 속도를 잃고 1.5초 동안 지쳐서 ×0.35. 아무도 없으면 0.55m/s 로 어슬렁. 근처(14m)에 사람이 있을 때만 움직이고 그때마다 `shoal` 을 보낸다.
- 조개 숨구멍(`server/src/dig.js`): 바닷가(섬 가장자리 모래밭) 최대 8곳, 처음엔 반을 한꺼번에, 그 뒤 45초마다 하나. hp 3, 바지락·개조개·맛조개·키조개. 호숫가는 낚시터마다 2곳, 60초마다, hp 2, 재첩·다슬기.
- 땅 칸: 1m 격자(`round(x)`, `round(z)`), `hole`(30% 로 조약돌·옛날 동전·화석) / `path`. 최대 400칸, 방 저장 파일의 `world.tiles`.

## 아파트 집 안 (서버 판정, v10)
- 평면도 `data/realestate/floorplans.json`: 그림 픽셀 좌표 × `scale` → 미터, 평면도 왼쪽 위가 (0, 0) (`server/src/homes.js` 의 `planInMeters`, 클라이언트 `FloorPlan` 이 같은 식).
- 호수의 평면도 = 동의 `plans[평형]` 또는 평형의 `plan`. 집 안 원점 = `interiors` 격자에서 호수 순서 번째 (x0 −185 + (i mod 3)·26, z0 −190 + ⌊i/3⌋·19.5) — 섬 서쪽 바다 위, 서버 경계(±200) 안.
- 들어가면 현관 가운데(spawn)로, 나가면 동 공동 현관 앞으로 서버가 옮긴다 (이동 검사를 거치지 않는 순간 이동). `player.home` 은 위치로도 되찾는다 (재접속).
- 가구: 아직 아무도 손대지 않은 집은 평면도 `defaults`(TV · 에어컨 · 선풍기 · 침대)를 보여 주고, 처음 놓기·옮기기·회수할 때 그 집 것(`room.homeItems[호수]`)이 된다. 서버는 0.25m 격자에 맞추고 가구 가운데가 방 사각형 안(0.05m 안쪽)인지만 본다 — 벽·두 방에 걸치는지는 클라이언트(꾸미기 화면)가 귀퉁이로 거른다.
- 꾸밀 수 있는 사람 = 주인 또는 주인과 같은 세대(혼인신고). 집을 팔아도 가구는 집에 남는다.

## 주민이 먼저 다가오기 · 마을톡 (서버 판정, v11)
- 주민: 친밀도가 `approach.min_friendship`(6) 이상인 사람이 9m 안에 있고, 그 사람이 대화·낚시 중이 아니고 집·상점 안이 아니면, 초당 `chance_per_s`(0.12) 확률로 그쪽으로 걸어간다 (가장 친한 사람에게). 1.5m 앞에서 멈추고 `npc_greet`. 한 사람에게 5분에 한 번, 주민마다 45초에 한 번. 15초 안에 닿지 못하거나 멀어지면 그만둔다. `NPC_APPROACH_SCALE` = 확률 배율.
- 클라이언트: 멈춰 선 주민은 5m 안의 나를 돌아본다 (서버 방향과 별개, 화면에서만).
- 마을톡 (`data/messenger/messenger.json`, `server/src/messenger.js`): 대화방 `npc:<주민>` · `sys:bank`(은행·동사무소) · `sys:town`(환영 인사) · `pl:<자리>`(친구). 프로필에 방마다 최근 60개와 읽은 수를 저장해서 끊겨 있던 사람도 들어오면 `welcome.chats` 로 받는다.
  - 친밀도 4 이상인 주민이 `check_ms`(20초)마다 20% 확률로 먼저 연락 (주민마다 하루 한 번, 사람마다 하루 3통): 안부 · "식당 언제 열어?"(식당이 닫혀 있을 때) · 비 오는 날 이야기.
  - 주민에게 보내면 1.5~4초 뒤 답장, 하루 한 번 친밀도 +1. 친구에게 보내면 두 사람의 방에 같이 들어가고, 받는 사람이 접속 중이면 바로 `msg`.
  - 은행: 주간 정산 때 이자를 냈으면 · 못 내서 원금에 더했으면 · 월세 수입 · 청년 월세 지원금을 알린다.
  - `MESSENGER_CHECK_MS` · `MESSENGER_REPLY_SCALE` 은 테스트용.

## 바닥에 내려놓기 · 식당 창고 · 식재료 배달 (서버 판정, v13)
- 내려놓기: 발밑에서 시작해 이미 놓인 물건과 0.42m 이상 떨어지게 해바라기 씨 배치로 놓는다(줍기 거리 안). 누구나 주울 수 있고 저장된다(마을에 150묶음까지). 클라이언트는 아이템 모형을 손바닥만 하게(0.42m) 줄여 바닥에 두고, 가까이 가면 물건 위에 이름표("목재 ×3")를 띄운다.
- 식당 창고(`restaurant.storage`): 상점에서 산 식재료와 받지 못한 배달이 들어간다. 식당은 손님 주문을 받을 때 창고 + 직원 가방을 함께 세고, 요리를 낼 때 창고 재료부터 쓴다.
- 묶음 배달: 출발 전 상자(`wait`)에 다음 주문을 같이 담는다 — 최대 3건 · 배달비는 상자당 한 번 · 같은 재료는 합친다. 막 떠나려던 참이면 3초(`DELIVERY_TIME_SCALE` 배) 더 기다린다. 출발 · 완료 마을톡은 상자마다 한 번("주문하신 달걀 10개, 쌀 한 봉 2개, 두부 3개, 배달 가고 있습니다~"). 가방에 다 안 들어가면 들어가는 재료만 건네고 나머지는 식당 창고로, 마을톡 한 통에 함께 적는다.
- 배달 (`data/shop/shop.json` 의 `delivery`, `server/src/delivery.js`): 주문 → 20~30초(`DELIVERY_TIME_SCALE` 배) 뒤 마을톡 `sys:shop` 에 "주문하신 ○○ n개, 배달 가고 있습니다~" → 배달 알바(`courier`)가 상점 문 앞에서 3.4m/s 로 주문한 사람에게 곧장 뛰어가 1.5m 안에서 건넨다(가방, 안 들어가면 식당 창고) → "배달 완료!" → 상점으로 돌아간다. 주문한 사람이 집·상점 안이거나 접속을 끊었으면 그 자리에서 90초 기다리다 식당 창고에 넣고 알린다. 기다리는 주문은 저장된다(다시 켜면 바로 출발하거나 창고로).

## 도감 · 업적 · 칭호 · 생일 · 달력 · 방명록 · 사진 (서버 판정, v16)
- 도감: 낚은 물고기는 낚을 때(낚싯대 · 뜰채) 센다. 가구 · 옷은 프로필을 보낼 때마다 가방 · 입은 옷 · 내가 마을에 놓은 가구를 훑어 한 번이라도 있었던 것을 올린다.
- 업적(`server/src/progress.js`): 프로필을 보낼 때마다 판정 값(stats + 도감 크기 · 친밀도 30 이상 주민 수 · 지갑 · 가진 집 · 내가 기증한 물고기)이 목표를 넘은 업적을 적고 `ach` 로 알린다. 칭호는 이룬 업적의 것만 단다.
- 생일: 플레이어 생일이 되면(접속할 때 · 날짜가 바뀔 때) 친밀도 `birthday.min_friendship`(4) 이상인 주민이 축하 마을톡과 선물(주민 `gifts` 중 하나, 가방이 차면 못 받음)을 보내고, 같은 마을 친구들 마을 소식 방에 알린다. 한 해에 한 번(`bdayYear`) — 생일을 바꿔도 다시 받지 못한다. 주민 생일에는 모두의 마을 소식 방에 알리고(하루 한 번, `notedDay`), 그날 처음 말을 걸면 친밀도 +`npc_talk_bonus`(3).
- 달력: 날씨(`weatherAt`)와 하루 이벤트(`planDay`)는 마을 시드와 날짜로 정해지는 값이라 앞날을 그대로 계산해 보낸다 (예보가 틀리지 않는다). 유성우는 "그날 밤 맑으면".
- 놀러 가기 · 방명록: 같은 집은 하루 한 번만 업적에 센다(`visitDay`). 방명록은 집마다 최근 40개.
- 사진(`server/src/photos.js`): `<saveDir>/photos/<방 코드>/<id>.jpg`, 방마다 최근 80장(넘치면 오래된 것부터 지움). 앨범(찍은 사진)은 기기에만 있고 보낼 때 그 한 장만 올린다.

## 앱 안 테스트 서버 (v10)
- 서버 주소 `test://local` = 클라이언트 안의 `LocalTestServer` (127.0.0.1 의 빈 포트, 18680~). 같은 메시지 형식으로 답한다.
- 입장 정보는 `data/testserver/welcome.json` (`node server/tools/make_test_snapshot.js` 로 진짜 서버에서 찍음) + 저장된 가방·솔·위치.
- 처리: `ping` `create/join/resume` `move` `equip` `inv_move` `inv_discard` `talk` `talk_topic` `talk_end` `chop`(그루터기 → 다시 자람) `fish_cast` `fish_hook` `fish_reel` `fish_cancel` `collect`(나무 곁에 채집물이 돋음) `plant` `pick` `wear` `unwear` `set_face` `shop_enter/exit` `shop_buy/sell` `place` `pickup` `home_*` (어느 집이든 `edit: true`), v13: `inv_discard`(발밑에 남음, 다시 줍기) · 겨눠 던지기는 물고기 그림자가 없어 옛 방식 · `deliv_order` 는 `test_server`, v11: 주민 마을톡(`msg_send npc:*` 답장, 친한 주민이 30초마다 먼저 연락 — 친구 방은 `test_server`) · 가까이 서 있는 친한 주민의 `npc_greet`. 나무·꽃은 게임 1분 = 실제 6초로 자란다. v16: `cal_info`(늘 맑음 · 이벤트 없음 · 주민 생일만). 그 밖에 rid 가 있는 요청(식당·증권·은행·동사무소·혼인·뜰채·삽 · 칭호 · 생일 · 방명록 · 놀러 가기 · 사진 …)은 `error{code: "test_server"}`.

## 얼굴 · 거울 (서버 판정, v7)
- 얼굴은 프로필의 `face` (`eyes eye_color nose mouth skin hair hair_color`, `data/looks/face_parts.json` 의 id). 새 프로필·모르는 id 는 자리 기본 얼굴(`defaults[slot-1]`).
- 거울: 마을 거울 자리(`mirrors`)와 `mirror: true` 가구(전신 거울·거울 화장대)를 누가 놓았든 그 앞(`mirror.range` 2.2m + 0.5m)에서만 바꾼다. 거울 자리 1.3m 안에는 심거나 가구를 놓을 수 없다.
- 비용 없음. 바꾸면 저장하고 방 전체에 `face` 로 알린다.

## 인벤토리
퀵슬롯 5칸 + 가방 30칸 (v13, 이전 20칸 — 저장된 칸 자리는 그대로 두고 늘어난 칸은 빈다). 새 아이템은 같은 아이템 칸 → 빈 가방 칸 → 빈 퀵슬롯 순으로 들어간다. 칸당 개수: 물고기 99, 목재 30, 도구 1.
처음 들어오면 퀵슬롯 1번에 낚싯대, 2번에 도끼가 있고 1번을 손에 들고 있다(솔은 `START_SOL`, 기본 0). 도구는 버릴 수 없다.
아이템 종류: 도구, 재료(목재 6종), 소지품(부탁·선물용 19종 + v6 씨앗 4 · 자작나무 씨앗 · 꽃 4 · 엽서), 가구(20종 + v6 지구본·비행기 모형·여행 가방·어항·월척 트로피·황금 물고기상), 옷(모자 8·상의 7, v6 조종사 모자), 물고기(31종). 나무 종류(둥근·소나무·자작나무)마다 나오는 목재·소지품이 다르다.
물고기 칸이 가득 차면 던지기 전에 `inventory_full`로 거절하고, 던진 뒤 칸이 찼다면 `fish_result(inventory_full)`로 놓친다.

## 저장
방(마을) 하나 = JSON 파일 하나: `<SAVE_DIR>/<방코드>.json`
(`schema: 5`, `createdAt`, `world{totalCatches, species, weatherSeed, trees{<id>: {s, c, d, t}}, shopPoints, placed[], placedSeq, planted[{id, kind, x, z, by, st}], plantSeq, flowers[{id, sp, c, x, z, s, t, by}], flowerSeq, museum{fish{}, claimed[]}}`,
`profiles{<uid>: {slot, slots, held, sol, catches, x, y, z, yaw, npcs{<id>: {f, talkDay, offerDay, giftDay, emoteDay, chatDay, chatCount}}, quests[], questSeq, lastQuestDay, outfit{hat, top}, emotes{known[], quick[]}}}`).
- v8 (schema 5): `world` 에 `homes{unit: {owner, price, day}}`, `aptIndex`, `baseRate`, `week`, `restaurant{history[], regulars{}, served, revenue}`, 프로필에 `stocks{} trades[] loans[] loanSeq credit{paid, missed, weeks} income{amount, history[]}`. schema 4 이하는 읽을 때 솔·상점 포인트·부탁 보상을 ×100 (현실 화폐 단위).
- schema 3 파일도 그대로 읽는다: 나무 상태의 `t`(단계 시작 게임 시각)가 없으면 0 으로 보고 다음 틱에 다 자란다, 감정표현은 '안녕'부터.
- 사람은 `uid`로 구분한다. 서버가 재시작되어 `token`이 사라져도, 클라이언트가 방 코드 + `uid`로 `join`하면 같은 자리·인벤토리·위치로 돌아온다(클라이언트가 `resume_failed` 뒤 자동으로 시도).
- 아이템 수가 바뀌는 일(낚시·도끼질·버리기·부탁 완료·사고팔기·가구 설치/줍기·옷 입기/벗기)과 부탁·친밀도·상점 포인트 변화, 입퇴장은 즉시 저장한다. 칸 옮기기·손에 든 칸·위치는 5초 주기로 저장한다. 쓰기는 임시 파일 → rename 으로 원자적이다. 종료 시에는 메모리의 방을 전부 저장한다.
- `schema: 1` 파일(물고기 목록 `items`)은 읽을 때 칸 인벤토리로 옮기고 도구를 챙겨 준다.
- 방 코드는 파일 이름이라 형식(`[A-HJ-KM-NP-Z2-9]{6}`)을 검사한 뒤에만 쓴다. 깨진 파일은 `.corrupt-<시각>`으로 옮겨 두고 방이 없는 것으로 처리한다.
