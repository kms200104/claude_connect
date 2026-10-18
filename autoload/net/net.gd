extends Node
## 세션 서버(WebSocket) 접속, 방 코드 입장, 끊김 감지와 자동 재접속, 서버 시계 추정.
## 게임플레이 코드는 이 싱글턴의 시그널만 구독한다. 서버가 권위이고 클라이언트는 요청만 보낸다.

signal state_changed(new_state: int)
## 방에 들어왔다(또는 재접속으로 돌아왔다). `self_state`는 서버가 알고 있는 내 위치.
signal welcomed(self_state: NetPlayerState, others: Array[NetPlayerState], resumed: bool)
signal peer_joined(state: NetPlayerState)
signal peer_left(id: int)
signal peer_status_changed(id: int, online: bool)
signal snapshot_received(server_time_ms: float, states: Array[NetPlayerState])
## 서버가 내 이동을 거부하고 되돌린 위치.
signal position_corrected(position: Vector3)
signal connection_lost
signal session_lost(reason: String)
signal error_received(code: String)
signal latency_updated(rtt_ms: float)
## 내 인벤토리 전체. `slots`는 퀵슬롯(앞 quick_slot_count 칸) + 가방 칸, 빈 칸은 null. `held_slot`은 손에 든 퀵슬롯(-1 = 빈손).
signal inventory_updated(slots: Array[InventoryItem], held_slot: int)
## 솔(화폐)·부탁 목록·친밀도가 바뀜.
signal profile_updated
## v19 차고: 차고(vehicles)가 바뀜 · 사기/꾸미기/팔기 결과 (veh_result: kind, v, model, part, slot, cost, sol) · 내가 차고 탈것에 타고 내림 (mount: { v, m, f }, 빈 사전 = 내림).
signal vehicles_changed
signal vehicle_done(result: Dictionary)
## v0.26 타는 탈것 내구도가 바뀜 { v, hp, max, why, broken } · 들이받기 결과 { c, hard, u, dmg, slow }.
signal vehicle_hp(info: Dictionary)
## v0.27 동승: 누가 친구 차에 탔다 · 내렸다 (Net.seats).
signal seat_changed(player_id: int)
## v0.27 탈것 배터리가 바뀜 { v, charge, max, empty }.
signal vehicle_charge(info: Dictionary)
signal rammed(info: Dictionary)
## v0.20 폰다운 기능: 솔걸음 보상 결과 (steps_ok: today, got, reward, sol) · 재난문자 (alert: id, level, sender, text, at, late) ·
## 민방위 훈련 (drill: on, shelter{name,x,z,r}, until, done) · 대피 보상 (drill_done: reward, sol).
signal steps_updated(info: Dictionary)
## v0.22 제작: 만들었다 { recipe, item, n, tier }.
signal crafted(info: Dictionary)
## v0.23 생존: 가구를 뒤졌다 { c, items[{id,n}], got } · 누가 뒤져 비었다(c, 다시 차는 세상 ms) · 체력 · 다쳤다 · 기절 ·
## 크리처 목록 · 맞았다 · 쓰러졌다(사라졌다) · 내가 휘둘렀다 { hit }.
signal looted(info: Dictionary)
signal container_changed(container_id: String, until: float)
signal hp_changed(hp: int, max_hp: int)
## v0.28.7 배고픔 · 목마름.
signal needs_changed(food: int, water: int)
## v0.28.7 회피 구르기 허락 (서버 dodge_ok): ms 동안 dist m 를 구른다.
signal dodged(ms: int, dist: float)
signal hurt(info: Dictionary)
signal knocked_out(info: Dictionary)
signal creatures_updated
signal creature_hit(info: Dictionary)
signal creature_dead(info: Dictionary)
signal swung(info: Dictionary)
## v0.24 거점 · 같이 하기: 판자 hp 가 바뀜 (key "집:자리", hp, 소식 {by, c}) · 내가 댔다 · 누가 쓰러짐 · 일으키기 시작/멈춤 · 일어남(기절 포함).
signal board_changed(key: String, hp: int, info: Dictionary)
signal boarded(info: Dictionary)
signal downed_changed(player_id: int)
## v0.25: 판자 대는 중 (key, 끝났거나 그만두면 Net.board_jobs 에서 빠진다) · 거점 상자 · 자는 사람 · 내가 낸 소리 { k, r, n }.
signal board_job_changed(key: String)
signal stash_changed(house_id: String)
signal sleep_changed(player_id: int)
signal noise_made(info: Dictionary)
## v0.26 피 냄새: 누가 피를 흘리기 시작 · 멈춤 · 핏자국 하나 { id, x, z, ms }.
signal bleed_changed(player_id: int)
signal scent_dropped(info: Dictionary)
## v0.27 보급 상자: 새 상자 · 땅에 닿음 · 누가 열어 사라짐 (id), 내가 연 결과 { s, items, got }.
signal supply_changed(crate_id: String)
## 누가 열어 갔다 (by = 0 이면 해가 떠서 회수).
signal supply_taken(crate_id: String, by: int)
signal supply_got(info: Dictionary)
## v0.28 헌터: 내 헌터 기록이 바뀜 (Net.hunter) · 길드가 바뀜 (Net.guild, info = 서버 guild 메시지) · 요청 결과 { kind, … }.
signal hunter_changed
signal guild_changed(info: Dictionary)
signal hunter_done(info: Dictionary)
## v0.28.5 각성 효과 (누가 · 무엇을 · 얼마 동안 ms) · 마력 방패가 막았다 (누가 · 남은 횟수).
signal awaken_fx(player_id: int, awaken_id: String, ms: int)
signal shield_blocked(player_id: int, left: int)
## v0.28.8 전사 '버티기' 로 막았다 · 직업 액티브 기술을 썼다 (나 · 남, 그림용) · 내 액티브가 허락됐다.
signal guard_blocked(player_id: int, sanctuary: bool)
## v0.28.9 누군가의 직업 · 2차 전직이 바뀌었다 (겉모습).
signal hunter_job_changed(player_id: int)
signal skill_fx(info: Dictionary)
signal skill_used(active_id: String, cooldown_ms: int)
## v0.28 게이트: 열림 · 상태가 바뀜 · 닫힘 (id, Net.gates 에 없으면 닫힘) · 내가 들어감 · 공략 보상 { g, rank, name, items, got, sol, pts }.
signal gate_changed(gate_id: String)
signal gate_entered(gate_id: String)
## v0.28.2 던전에서 나왔다 (나가는 균열).
signal gate_left(gate_id: String)
signal gate_cleared(info: Dictionary)
## v0.28.2 가디언: 상태가 바뀜 (id) · 총을 쐈다 { g, c, hp, x, z } · 주민이 맞음 { id, hp } · 쓰러짐 · 일어남.
signal guard_changed(guard_id: String)
signal guard_shot(info: Dictionary)
signal npc_hurt(info: Dictionary)
signal alert_received(alert: Dictionary)
signal drill_changed(info: Dictionary)
signal drill_finished(info: Dictionary)
signal mount_changed(mount: Dictionary)
## v19.1 세워 둔 · 주민이 가져오는 중인 차고 탈것 목록이 바뀜 (Net.parked).
signal parked_changed
## v21 물놀이: 놀이배 목록(Net.aqua_trips)이 바뀜 · 타기/내리기 결과 (aqua_result: kind, trip, ride, seat, depart, cost, sol) ·
## 누군가 급회전에서 버팀/빠짐 · 내가 탄 놀이배가 한 바퀴 돌고 선착장에 닿음 (aqua_end: trip, ride, held, turns).
signal aqua_changed
signal aqua_done(result: Dictionary)
signal aqua_fx(trip: String, player_id: int, turn: int, fell: bool)
signal aqua_ended(result: Dictionary)
signal weather_changed(weather: String)
## 번개 (뇌우일 때 서버가 방 전체에 같은 순간 보낸다). power 0.6~1.
signal lightning_struck(power: float)
## 번쩍임 없이 멀리서 우르릉 (번개 사이사이).
signal thunder_rumbled
## 방금 친 번개가 '우르르 쾅쾅' 길게 구르는 천둥인지 (lightning_struck 직전에 정해진다).
var lightning_roll: bool = false
signal tree_changed(tree_id: String, stage: String, chops: int)
signal npcs_received(server_time_ms: float, states: Array[NetNpcState])
## 내 도끼질 결과 (서버가 확정). 나무에서 얻은 아이템과 나무가 쓰러졌는지.
signal chop_succeeded(tree_id: String, item_id: String, felled: bool)
## 상대가 한 동작 (지금은 도끼질만). target = 나무 id.
signal peer_action(id: int, kind: String, target: String)
## v12: 상대의 동작 알림 전체 (낚시 장면처럼 추가 값이 있는 것: kind = fish 면 e = cast|nibble|bite|reel|land|end, spot, fish).
signal peer_act(id: int, kind: String, msg: Dictionary)
## v12: 상대가 대화 중에 화면에 띄운 대사 (npc 가 비면 상대 자신의 말).
signal peer_said(id: int, npc_id: String, text: String)
signal talk_opened(reply: TalkReply)
## 서버가 대화를 끝냄 (멀어졌거나 시간 초과).
signal talk_closed(npc_id: String)
signal quest_accepted(quest: QuestInfo)
signal quest_completed(quest_id: String, npc_id: String, reward: int)
## 상점 단계·포인트가 바뀜 (방 전체). leveled_up = 방금 커졌다.
signal shop_updated(leveled_up: bool)
## 서버가 상점 문으로 나를 옮겼다 (inside = 들어감).
signal shop_door_passed(inside: bool, position: Vector3)
## 사고팔기 성공. kind = "buy" / "sell", amount = 오간 솔.
signal shop_traded(kind: String, item_id: String, count: int, amount: int)
signal furniture_placed(info: PlacedInfo, by_player: int)
signal furniture_removed(id: String)
## 요청이 거부됨. kind = 요청 종류(chop, talk, quest_accept, quest_turnin, inv_move, inv_discard …), code = NetProtocol.ERR_*
signal request_failed(kind: String, code: String)
## 찌를 던졌다. shadow = 물 밑에 다가올 물고기 그림자 크기 (희귀하고 클수록 크다, 0.6~1.7).
signal fish_started(shadow: float)
## v13: 겨눠 던진 찌를 알아챈 물고기 (처음엔 없다가 지나가던 물고기가 찾아왔을 때). last_fish 에 fid · 크기 · 다가오는 시간.
signal fish_found(shadow: float)
## v13: 낚시터 물고기 그림자들 [{id, x, z, yaw, s(S·M·L), r(희귀도), st(roam·engaged·flee), o(낚는 사람)}].
signal fishes_updated(spot_id: String, list: Array[Dictionary])
## 챔질 성공 → 끌어올리기: ms 안에 taps 번 연타해야 한다 (v0.11).
signal fish_reel(taps: int, ms: int)
signal fish_nibble
## 진짜 입질. 이 순간부터 `window_ms` 안에 챔질해야 한다.
signal fish_bite(window_ms: int)
## 서버가 확정한 낚시 결과. 성공이면 `fish_id`가 물고기 종류, 실패면 `reason`(NetProtocol.FISH_*).
signal fish_result(success: bool, fish_id: String, reason: String)
## 낚시·인벤토리 요청이 거부됨 (NetProtocol.ERR_*).
signal action_rejected(code: String)
## 열린 이벤트 목록이 바뀌었다 (started: 새로 열린 이벤트 id 들).
signal events_changed(started: PackedStringArray)
## 바닥에 선물 풍선·별 조각이 생겼다 / 없어졌다 (by: 주운 사람 id, 0 = 이벤트가 끝나 사라짐).
signal drop_added(drop: DropInfo)
signal drop_removed(id: String, by: int)
## 내가 선물·별 조각을 주웠다.
signal collected(kind: String, item_id: String)
## 바닥 묶음의 개수가 바뀌었다 (v13: 가방에 다 안 들어가 일부만 주웠을 때).
signal drop_changed(drop: DropInfo)
## 식재료 배달 (v13): 주문이 받아졌다(merged = 아직 떠나지 않은 상자에 같이 담김, 배달비 없음) /
## 상자를 받았다(items = [{item, n, where: "bag" | "storage"}]) / 길 위의 배달 알바들이 바뀌었다.
signal delivery_ordered(item_id: String, count: int, eta_s: int, amount: int, merged: bool)
signal delivery_done(items: Array[Dictionary])
signal couriers_updated(list: Array[Dictionary])
## 낚시 대회 상금을 받았다.
signal fish_bonus(amount: int)
## 누군가 씨앗을 심어 새 나무가 생겼다 (상태는 tree_changed 로도 온다).
signal tree_planted(info: TreeInfo)
## 심은 꽃이 생기거나 자라거나 따였다 (by: 그렇게 한 사람, 0 = 저절로 자람).
signal flower_changed(flower: FlowerState, by: int)
## 내가 심었다 (kind = "tree" / "flower").
signal planted(kind: String, id: String)
## 내가 꽃을 땄다.
signal flower_picked(item_id: String)
## 다른 사람의 감정표현·몸짓(브레이크).
signal peer_emoted(player_id: int, emote_id: String)
## 누군가(나 포함) 거울에서 얼굴을 바꿨다.
signal face_changed(player_id: int, face: Dictionary)
## 누군가(나 포함) 닉네임을 바꿨다 (v14). 빈 이름이면 기본 이름.
signal name_changed(player_id: int, display_name: String)
## 주민이 누군가의 감정표현에 반응했다 (to: 감정표현을 한 사람).
## from = 그 사람이 한 감정표현 (주민 반응은 그에 대한 것).
## 친한 주민이 먼저 다가와 나에게 말을 걸었다 (v0.11).
signal npc_greeted(npc_id: String)
signal npc_emoted(npc_id: String, emote_id: String, to_player: int, mood: String, from: String)
## 대화 주제로 수다를 떨었다 (gain: 오른 친밀도).
signal topic_answered(npc_id: String, topic: String, gain: int)
## 박물관에 기증된 물고기가 늘었다 (마을 공용).
signal museum_changed(fish_id: String, by: int)
## 내가 기증했다 (reward: 감사 솔, gifts: 기념품 아이템).
signal donated(fish_id: String, reward: int, count: int, gifts: PackedStringArray)
## 받은 메시지 전부 (Net 이 따로 다루지 않는 경제 메시지는 Economy 가 여기서 받는다).
signal message_received(msg: Dictionary)

enum State { DISCONNECTED, CONNECTING, JOINING, ONLINE, RECONNECTING }

enum Intent { NONE, CREATE, JOIN, RESUME }

const SETTINGS_BASE: String = "user://net"
## 앱 안 테스트 서버 주소 (v0.10). 서버 주소 칸에 이걸 쓰거나 "테스트 서버로 하기"를 누르면 LocalTestServer 를 띄워 거기로 접속한다.
const TEST_SERVER_URL: String = "test://local"
const MAX_LOCAL_INSTANCES: int = 8

@export_group("Connection")
@export var default_server_url: String = TEST_SERVER_URL
@export_range(1.0, 30.0, 0.5, "suffix:s") var connect_timeout: float = 5.0
## ONLINE인데 이 시간 동안 서버에서 아무것도 안 오면 끊긴 것으로 본다.
@export_range(1.0, 30.0, 0.5, "suffix:s") var idle_timeout: float = 6.0
@export_range(0.5, 10.0, 0.5, "suffix:s") var ping_interval: float = 2.0

@export_group("Reconnect")
## 서버의 유예 시간(기본 30초)보다 약간 길게.
@export_range(1.0, 120.0, 1.0, "suffix:s") var reconnect_window: float = 35.0
@export var reconnect_backoff: PackedFloat32Array = PackedFloat32Array([0.3, 0.6, 1.2, 2.0, 3.0])

var state: State = State.DISCONNECTED
var server_url: String = ""
var room_code: String = ""
var my_id: int = 0
var partner_present: bool = false
## v17: 테스트 도구가 켜진 서버 (설정의 "테스트: 솔 받기" 단추를 보인다).
var dev_tools: bool = false
var partner_online: bool = false
var rtt_ms: float = 0.0
var uid: String = ""
## 같은 PC에서 여러 인스턴스를 띄울 때 서로 다른 저장 슬롯(1, 2, …)을 쓴다. 폰에서는 항상 1.
var profile_slot: int = 1
## 퀵슬롯 + 가방 칸. 빈 칸은 null.
var inventory: Array[InventoryItem] = []
var quick_slot_count: int = 5
## 가방 칸 수 (퀵슬롯 제외).
var inventory_capacity: int = 20
## 손에 든 퀵슬롯 번호 (-1 = 빈손).
var held_slot: int = -1
var sol: int = 0
var quests: Array[QuestInfo] = []
## 주민 id → 친밀도
var friends: Dictionary[String, int] = {}
var weather: String = NetProtocol.WEATHER_CLEAR
## 나무 id → 상태(NetProtocol.TREE_*)
var tree_stages: Dictionary[String, String] = {}
## 마지막으로 받은 주민 위치.
var npc_states: Array[NetNpcState] = []
## 상점 (마을 공용): 단계, 포인트, 다음 단계 문턱(-1 = 마지막 단계).
var shop_level: int = 1
var shop_points: int = 0
var shop_next: int = -1
## 마을에 설치된 가구 (id → 정보).
var placed: Dictionary[String, PlacedInfo] = {}
## 내가 입은 옷 (아이템 id).
var outfit_hat: String = ""
var outfit_top: String = ""
## 지금 열려 있는 이벤트 (서버가 정한다).
var events: Array[ActiveEvent] = []
## 바닥에 떨어진 선물·별 조각 (id → 정보).
var drops: Dictionary[String, DropInfo] = {}
## 마지막으로 주운 개수와 바닥에 남은 개수 (v13 내려놓은 묶음).
var last_collect_count: int = 1
var last_collect_left: int = 0
## 마지막으로 산 것이 식당 창고로 갔는지 (v13: 식재료).
var last_trade_stored: bool = false
## v13: 지금 낚시를 알아챈 물고기 {fid, size, ms, bx, bz} (fish_started · fish_found 때 채운다). fid 가 비면 아직 없음.
var last_fish: Dictionary = {}
## 낚시터 id → 물고기 그림자 목록 (fishes_updated 와 같은 것).
var fishes: Dictionary[String, Array] = {}
## 길 위의 배달 알바 [{id, x, z, yaw, ph, to, item, k}] 와 내 배달 상자 [{id, items: [{item, n}], ph}] (v13, 묶음 배달).
var couriers: Array[Dictionary] = []
var my_deliveries: Array[Dictionary] = []
## 마지막 도끼질로 얻은 개수 (나무꾼의 날에는 2).
var last_chop_count: int = 1
## 씨앗을 심어 생긴 나무 (id → 정보). 데이터 나무는 GameData.trees.
var planted_trees: Dictionary[String, TreeInfo] = {}
## 마을에 심은 꽃 (id → 상태).
var flowers: Dictionary[String, FlowerState] = {}
## 박물관에 기증된 물고기 (물고기 id → 기증한 사람 자리 번호).
var museum_fish: Dictionary[String, int] = {}
## 배운 감정표현과 감정표현 퀵슬롯.
var emotes_known: PackedStringArray = ["hello"]
var emotes_quick: PackedStringArray = ["hello"]
## 주민 id → 지금 기분.
var npc_moods: Dictionary[String, String] = {}
## 버전이 맞지 않을 때 서버가 알려 준 서버의 프로토콜 버전 (0 = 모름).
var server_version: int = 0
## 자리 번호 → 거울에서 고른 얼굴 (FaceCatalog id 사전). 없으면 자리 기본 얼굴.
var faces: Dictionary[int, Dictionary] = {}
## 자리 번호 → 닉네임 (v14). 없거나 빈 이름이면 GameData.player_name 의 기본 이름.
var names: Dictionary[int, String] = {}
## v19 내 차고: [{ id, model, owned: [부품], fit: { 칸: 부품 } }] (프로필).
var vehicles: Array[Dictionary] = []
## v0.20 솔걸음: 오늘 서버가 인정한 걸음 · 받은 목표 번호.
var steps_today: int = 0
var steps_got: Array[int] = []
## 지금 민방위 훈련 중인지 (drill 메시지, 빈 사전 = 아님).
var drill: Dictionary = {}
## v19.1 방에 세워 둔(또는 오는 중인) 차고 탈것: [{ v, o(주인 자리), m, f, x, z, yaw, t(도착 서버 시각, 0 = 이미 있음), npc }].
var parked: Array[Dictionary] = []
## v0.27 동승한 사람 (id → {d: 운전자, s: 자리 번호, seat?: [x, y, z] (나만)}).
var seats: Dictionary[int, Dictionary] = {}
## v21 물놀이 배 [{ id, ride, depart(서버 시각 ms), riders: [{ id, seat }] }].
var aqua_trips: Array[Dictionary] = []

var _ws: WebSocketPeer = null
## 앱 안 테스트 서버 (TEST_SERVER_URL 로 접속할 때만 만든다).
var test_server: LocalTestServer = null
var _intent: Intent = Intent.NONE
var _token: String = ""
var _open_handled: bool = false
var _connect_started_ms: float = 0.0
var _last_rx_ms: float = 0.0
var _next_ping_ms: float = 0.0
var _next_retry_ms: float = 0.0
var _reconnect_deadline_ms: float = 0.0
var _attempt: int = 0
var _clock_offset_ms: float = 0.0
var _clock_samples: Array[Vector2] = []  # (rtt, offset)
var _user_closed: bool = false
var _join_fallback_tried: bool = false
var _rid_counter: int = 0
var _fishing_rid: String = ""
## 마지막으로 보낸 말풍선 대사 시각 (SAY_GAP_MS 거르기).
var _last_say_ms: int = -100000
var _pending: Dictionary[String, String] = {}  # rid → 요청 종류 (거부됐을 때 어떤 요청인지 알리려고)
var _clock_game_ms: float = 0.0
var _clock_scale: float = 1.0
var _clock_server_ms: float = 0.0
## v0.22 세상 시각(낮 · 밤): 서버가 보낸 기준값과 배율 (기본 60배 — 현실 1분이 마을 1시간).
var _clock_world_ms: float = 0.0
## v0.23 생존 상태: 체력 · 뒤진 가구(id → 다시 차는 세상 ms) · 크리처(id → {k, x, z, yaw, hp, a}).
var hp: int = 10
var max_hp: int = 10
var food: int = 100
var water: int = 100
var looted_until: Dictionary[String, float] = {}
var creatures: Dictionary[String, Dictionary] = {}
var night: bool = false
## v0.24 판자 ("집:자리" → 남은 hp, 없으면 뚫림) · 쓰러진 사람 (id → {until: 이 기기 ms, by: 일으키는 사람, done: 다 되는 이 기기 ms}).
var boards: Dictionary[String, int] = {}
var downed: Dictionary[int, Dictionary] = {}
## v0.25 판자 대는 중 ("집:자리" → {progress, need, helpers: Array[int], at: 받은 이 기기 ms}) · 거점 상자 (집 → [{id, n}]) · 자는 사람.
var board_jobs: Dictionary[String, Dictionary] = {}
var stash: Dictionary[String, Array] = {}
var sleeping: Dictionary[int, bool] = {}
## v0.26 피 흘리는 사람 · 남은 핏자국 [{id, x, z, until: 이 기기 ms}].
var bleeding: Dictionary[int, bool] = {}
var scent: Array[Dictionary] = []
## v0.27 보급 상자 (id → {x, z, land: 땅에 닿는 이 기기 ms}).
var supply: Dictionary[String, Dictionary] = {}
## v0.28 내 헌터 기록 { rank, pts, next, nextRank, kills, gates, bounties: [{id, kind, k, n, got, done, reward, pts, name, desc}] } ·
## 이 마을 길드 { name, pts, level, title, next, members: [{id, rank, name}] } (없으면 빈 것) · 사람마다 헌터 등급.
var hunter: Dictionary = {}
var guild: Dictionary = {}
var hunter_ranks: Dictionary[int, String] = {}
## v0.28 열린 게이트 (id → {rank, spot, name, x, z, st: open|raid|break, until: 이 기기 ms, wave, waves, alive, boss, raiders: [id]}).
var gates: Dictionary[String, Dictionary] = {}
## v0.28.2 가디언 (id → {x, z, yaw, hp, max, until: 부활하는 이 기기 ms, 0 = 서 있음}).
var guards: Dictionary[String, Dictionary] = {}
var _world_scale: float = 1.0
## 서버가 계절을 고정했으면 그 계절 (SEASON_FORCE, 테스트·시연용). 비어 있으면 마을 날짜로.
var _season_force: String = ""


func _ready() -> void:
	profile_slot = _claim_profile_slot()
	server_url = last_server_url()
	uid = _load_or_create_uid()
	process_mode = Node.PROCESS_MODE_ALWAYS


func create_room(url: String) -> void:
	_start(url, Intent.CREATE, "")


func join_room(url: String, code: String) -> void:
	_start(url, Intent.JOIN, code.strip_edges().to_upper())


## 앱을 껐다 켠 뒤 저장된 세션으로 이어하기. 저장된 세션이 없으면 false.
func resume_saved_session() -> bool:
	var cfg: ConfigFile = _load_settings()
	var token: String = str(cfg.get_value("session", "token", ""))
	if token.is_empty():
		return false
	_token = token
	_start(str(cfg.get_value("session", "url", default_server_url)), Intent.RESUME, str(cfg.get_value("session", "code", "")))
	return true


func has_saved_session() -> bool:
	return not str(_load_settings().get_value("session", "token", "")).is_empty()


func leave() -> void:
	_user_closed = true
	drill = {}
	_forget_session()
	_close_socket(1000, "leave")
	_set_state(State.DISCONNECTED)


func last_server_url() -> String:
	return str(_load_settings().get_value("settings", "server_url", default_server_url))


## 마지막으로 들어갔던 방 코드 (나가기를 눌러도 기억한다). 없으면 빈 문자열.
func last_room_code() -> String:
	return str(_load_settings().get_value("settings", "room_code", ""))


## 저장된 세션의 방 코드 (이어하기로 돌아갈 방).
func saved_session_code() -> String:
	return str(_load_settings().get_value("session", "code", ""))


## 저장된 세션의 서버 주소.
func saved_session_url() -> String:
	return str(_load_settings().get_value("session", "url", ""))


func send_move(position: Vector3, yaw: float, velocity: Vector3) -> void:
	if state != State.ONLINE:
		return
	_send({
		"t": "move",
		"x": snappedf(position.x, 0.001), "y": snappedf(position.y, 0.001), "z": snappedf(position.z, 0.001),
		"yaw": snappedf(yaw, 0.001),
		"vx": snappedf(velocity.x, 0.001), "vz": snappedf(velocity.z, 0.001),
	})


## 낚시터에 던지기 요청. 결과는 fish_started / action_rejected 로 온다.
## aim (v13): 찌를 떨어뜨릴 자리 (물고기 머리 앞). 주면 그 둘레의 물고기가 알아채고 다가온다.
func cast_fishing(spot_id: String, aim: Variant = null) -> void:
	_fishing_rid = _next_rid()
	last_fish = {}
	var msg: Dictionary = {"t": "fish_cast", "rid": _fishing_rid, "spot": spot_id}
	if aim is Vector3:
		msg["x"] = snappedf((aim as Vector3).x, 0.001)
		msg["z"] = snappedf((aim as Vector3).z, 0.001)
	_send(msg)


## 챔질 요청. `reaction_ms`는 입질 연출이 보인 뒤 버튼을 누르기까지 걸린 시간(없으면 0).
func hook_fishing(reaction_ms: float) -> void:
	if _fishing_rid.is_empty():
		return
	_send({"t": "fish_hook", "rid": _fishing_rid, "reaction": snappedf(reaction_ms, 0.1)})


## 끌어올리기 연타 결과: 연타 화면이 뜬 뒤 누른 시각(ms)들. 서버가 수·간격을 보고 낚았는지 정한다.
func reel_fishing(tap_times_ms: PackedFloat32Array) -> void:
	if _fishing_rid.is_empty():
		return
	var taps: Array[float] = []
	for t: float in tap_times_ms:
		taps.append(snappedf(t, 0.1))
	_send({"t": "fish_reel", "rid": _fishing_rid, "taps": taps})


func cancel_fishing() -> void:
	_send({"t": "fish_cancel"})


## 칸에 든 아이템 버리기(물고기는 놓아주기). 도구는 서버가 거부한다.
## 식재료 배달 주문 (v13). 값 + 배달비를 바로 낸다. 아직 상점을 떠나지 않은 내 상자가 있으면 거기에 같이 담기고 배달비는 없다.
func order_delivery(item_id: String, count: int) -> void:
	_request("deliv_order", {"item": item_id, "n": count})


## 아직 상점을 떠나지 않은 (같이 담을 수 있는) 내 배달 상자가 있는지 — 있으면 다음 주문은 배달비 없이 같이 온다.
func has_waiting_delivery() -> bool:
	for d: Dictionary in my_deliveries:
		if str(d.get("ph", "wait")) == "wait":
			return true
	return false


func _apply_couriers(list: Variant) -> void:
	couriers.clear()
	if list is Array:
		for entry: Variant in list:
			if entry is Dictionary:
				couriers.append(entry)
	# 내 주문 중 길에 나선 것은 'walk' 로 (휴대폰에 "오는 중" 표시).
	for d: Dictionary in my_deliveries:
		for c: Dictionary in couriers:
			if str(c.get("id", "")) == str(d.get("id", "")):
				d["ph"] = str(c.get("ph", "walk"))
	couriers_updated.emit(couriers)


func discard_item(slot: int, count: int = 1) -> void:
	_request("inv_discard", {"slot": slot, "n": count})


## 손에 들 퀵슬롯 (-1 = 빈손). 서버가 확인하기 전에 화면에는 바로 반영한다.
func equip(slot: int) -> void:
	held_slot = slot
	inventory_updated.emit(inventory, held_slot)
	_send({"t": "equip", "slot": slot})


## 칸 옮기기 (다른 아이템이면 맞바꾸고 같은 아이템이면 합친다).
func move_item(from_slot: int, to_slot: int) -> void:
	_request("inv_move", {"from": from_slot, "to": to_slot})


func chop_tree(tree_id: String) -> void:
	_request("chop", {"tree": tree_id})


func talk_to(npc_id: String) -> void:
	_request("talk", {"npc": npc_id})


func end_talk() -> void:
	_send({"t": "talk_end"})


func accept_quest() -> void:
	_request("quest_accept", {})


func decline_quest() -> void:
	_send({"t": "quest_decline"})


func turn_in_quest(quest_id: String) -> void:
	_request("quest_turnin", {"quest": quest_id})


func enter_shop() -> void:
	_request("shop_enter", {})


func exit_shop() -> void:
	_request("shop_exit", {})


## at = "merchant" 이면 떠돌이 상인과 거래한다 (상인 곁에서만).
func sell_item(slot: int, count: int = 1, at: String = "") -> void:
	var fields: Dictionary = {"slot": slot, "n": count}
	if not at.is_empty():
		fields["at"] = at
	_request("shop_sell", fields)


func buy_item(item_id: String, count: int = 1, at: String = "") -> void:
	var fields: Dictionary = {"item": item_id, "n": count}
	if not at.is_empty():
		fields["at"] = at
	_request("shop_buy", fields)


## 바닥의 선물·별 조각 줍기.
func collect(drop_id: String) -> void:
	_request("collect", {"id": drop_id})


## 지금 열린 이벤트 (없으면 null).
func event_active(event_id: String) -> ActiveEvent:
	for e: ActiveEvent in events:
		if e.id == event_id:
			return e
	return null


## 이 종류의 열린 이벤트 (v0.12: visitor · bargain · derby · economy …). 없으면 null.
func event_of_kind(kind: String) -> ActiveEvent:
	for e: ActiveEvent in events:
		var info: EventInfo = e.info()
		if info != null and info.kind == kind:
			return e
	return null


## 이 물건을 팔 때의 배율 (서버 sellMultiplier 와 같다). 상점: 특가 매입 × 이번 주 경제 소식. 광장 손님: 찾는 물건만, 그 밖은 0(안 산다).
func sell_multiplier(item_id: String, at: String = "") -> float:
	if at == "merchant":
		var m: ActiveEvent = event_of_kind(EventInfo.KIND_VISITOR)
		return m.multiplier if m != null and item_id in m.wanted else 0.0
	var b: ActiveEvent = event_of_kind(EventInfo.KIND_BARGAIN)
	var mult: float = b.multiplier if b != null and item_id in b.wanted else 1.0
	var fx: Dictionary = _econ_effect()
	if str(fx.get("type", "")) == "sell" and _item_kind(item_id) == str(fx.get("item_kind", "")):
		mult *= float(fx.get("mult", 1.0))
	return mult


## 살 때의 배율 (서버 buyMultiplier · 광장 손님의 buy_mult 와 같다).
func buy_multiplier(item_id: String, at: String = "") -> float:
	if at == "merchant":
		var m: ActiveEvent = event_of_kind(EventInfo.KIND_VISITOR)
		return m.info().buy_mult if m != null and m.info() != null else 1.0
	if at != "":
		return 1.0
	var fx: Dictionary = _econ_effect()
	if str(fx.get("type", "")) == "buy" and _item_kind(item_id) == str(fx.get("item_kind", "")):
		return float(fx.get("mult", 1.0))
	return 1.0


func _econ_effect() -> Dictionary:
	var e: ActiveEvent = event_of_kind(EventInfo.KIND_ECONOMY)
	return e.info().effect if e != null and e.info() != null else {}


static func _item_kind(item_id: String) -> String:
	if GameData.fish.has(item_id):
		return "fish"
	var info: ItemInfo = GameData.item(item_id)
	return info.kind if info != null else ""


## 손에 든 씨앗을 (x, z) 에 심는다 (서버가 0.5m 격자로 맞춘다).
func plant(position: Vector3) -> void:
	_request("plant", {"x": snappedf(position.x, 0.01), "z": snappedf(position.z, 0.01)})


func pick_flower(flower_id: String) -> void:
	_request("pick", {"id": flower_id})


## 감정표현·몸짓을 한다 (근처 주민이 반응한다). 결과를 기다리지 않는다.
func send_emote(emote_id: String) -> void:
	_send({"t": "emote", "e": emote_id})


## 대화 중 화면에 띄운 대사를 둘레 사람에게 말풍선으로 (npc_id = 주민의 말, 빈 문자열 = 내 말). 결과를 기다리지 않는다.
## 서버는 SAY_GAP_MS 보다 잦은 대사를 버리니, 잇달아 오면 버리지 않고 간격(+여유)을 두고 차례로 보낸다.
func send_say(npc_id: String, text: String) -> void:
	var line: String = text.strip_edges().left(NetProtocol.SAY_MAX_CHARS)
	if line.is_empty() or state != State.ONLINE:
		return
	var now: int = Time.get_ticks_msec()
	var at: int = maxi(now, _last_say_ms + NetProtocol.SAY_GAP_MS + 60)
	_last_say_ms = at
	if at > now:
		await get_tree().create_timer(float(at - now) / 1000.0).timeout
		if state != State.ONLINE:
			return
	_send({"t": "say", "who": "npc" if not npc_id.is_empty() else "me", "npc": npc_id, "tx": line})


## 감정표현 퀵슬롯 (배운 것만, 최대 GameData.emote_quick_slots 개).
func set_emote_quick(ids: PackedStringArray) -> void:
	emotes_quick = ids
	profile_updated.emit()
	_send({"t": "emote_quick", "quick": Array(ids)})


## 대화 중인 주민과 이 주제로 수다를 떤다.
func talk_topic(topic: String) -> void:
	_send({"t": "talk_topic", "topic": topic})


## 닉네임을 바꾼다 (v14, 어디서나). 빈 이름이면 기본 이름으로. 결과는 name_changed. 처음 화면 설정에도 같이 기억한다.
func set_nickname(display_name: String) -> void:
	var clean: String = NetProtocol.clean_name(display_name)
	save_nickname(clean)
	if state == State.ONLINE:
		_request("set_name", {"name": clean})


## 들어온 뒤: 처음 화면 설정에서 바꾼 이름이 서버와 다르면(이어하기는 이름을 안 보낸다) 보내고,
## 설정에 이름이 없으면 서버 이름을 기억해 둔다.
func _sync_nickname() -> void:
	var local: String = nickname()
	var remote: String = str(names.get(my_id, ""))
	if local == remote:
		return
	if local.is_empty():
		save_nickname(remote)
	else:
		_request("set_name", {"name": local})


## 처음 화면 설정에 적어 둔 닉네임 (입장할 때 같이 보낸다). 없으면 빈 문자열.
func nickname() -> String:
	return str(_load_settings().get_value("settings", "nickname", ""))


func save_nickname(display_name: String) -> void:
	var cfg: ConfigFile = _load_settings()
	cfg.set_value("settings", "nickname", NetProtocol.clean_name(display_name))
	cfg.save(_settings_path())


## 휴대폰을 꺼냈다 · 넣었다 (v15, 다른 사람 화면에서도 들고 보는 모습이 보이게).
func set_phone(on: bool) -> void:
	_send({"t": "phone", "on": on})


## 탈것 타기 · 내리기 (v18, 연출용: 친구 화면에 타고 있는 모습). 가방에 그 아이템이 있어야 서버가 받아 준다.
func set_ride(item_id: String, on: bool) -> void:
	_send({"t": "ride", "on": on, "item": item_id})


## 휴대폰 화면을 눌렀다 (다른 사람 화면에서도 톡 누르는 손짓).
func phone_tap() -> void:
	_send({"t": "phone_tap"})


## 거울 앞에서 얼굴을 바꾼다 (바꿀 항목만 보내도 된다). 결과는 face_changed.
func set_face(face: Dictionary) -> void:
	_request("set_face", {"face": face})


## 이 자리 사람의 겉모습 (옷 색 + 얼굴).
func look_of(player_id: int) -> CharacterLook:
	return GameData.player_look(player_id, faces.get(player_id, {}))


## 박물관 관장에게 칸의 물고기를 기증한다.
func donate(slot: int) -> void:
	_request("donate", {"slot": slot})


## 가구 설치 (x, z 는 서버가 0.5m 격자로 맞춘다, rot 은 90° 단위).
func place_furniture(slot: int, position: Vector3, rot: int) -> void:
	_request("place", {"slot": slot, "x": snappedf(position.x, 0.01), "z": snappedf(position.z, 0.01), "rot": rot})


func pickup_furniture(id: String) -> void:
	_request("pickup", {"id": id})


## 칸에 든 옷을 입는다 (입던 옷은 그 칸으로 돌아온다).
func wear(slot: int) -> void:
	_request("wear", {"slot": slot})


## part = "hat" / "top"
func unwear(part: String) -> void:
	_request("unwear", {"part": part})


## 손에 든 아이템 id (빈손이면 빈 문자열).
func held_item_id() -> String:
	if held_slot < 0 or held_slot >= inventory.size() or inventory[held_slot] == null:
		return ""
	return inventory[held_slot].id


## 마을 시계 (게임 시각 ms). 서버가 보낸 기준값에서 서버 시계 추정치로 흘려 쓴다.
func game_ms() -> float:
	return _clock_game_ms + (server_time_ms() - _clock_server_ms) * _clock_scale


## 지금 계절 (v0.12): spring / summer / autumn / winter.
func season() -> String:
	return _season_force if not _season_force.is_empty() else VillageClock.season_of(game_ms())


## v0.22 세상 시각 (ms): 낮과 밤은 달력보다 빨리 흐른다.
func world_ms() -> float:
	return _clock_world_ms + (server_time_ms() - _clock_server_ms) * _world_scale


## 지금 마을 시각 (낮 · 밤 · 하늘 · 주민 일정 · 물고기 시간대) — 세상 시각.
func game_hour() -> float:
	return VillageClock.hour_of(world_ms())


## 달력 시각 (날씨 예보 칸 · 훈련 일정처럼 실제 날짜를 따르는 것).
func calendar_hour() -> float:
	return VillageClock.hour_of(game_ms())


func game_day() -> int:
	return VillageClock.day_index(game_ms())


func quest_from(npc_id: String) -> QuestInfo:
	for q: QuestInfo in quests:
		if q.npc == npc_id:
			return q
	return null


## 서버 기준 현재 시각(ms). 원격 플레이어 보간의 시간축.
func server_time_ms() -> float:
	return Time.get_ticks_usec() / 1000.0 + _clock_offset_ms


## 테스트용: 서버에 알리지 않고 소켓을 갑자기 끊는다(와이파이 단절과 비슷).
func debug_drop_connection() -> void:
	if _ws != null:
		_ws.close(1001, "debug drop")
		_ws = null
		_on_socket_closed(1006)


func _start(url: String, intent: Intent, code: String) -> void:
	_close_socket(1000, "restart")
	_user_closed = false
	server_url = url.strip_edges()
	_save_server_url(server_url)
	_intent = intent
	if intent != Intent.RESUME:
		_token = ""
	room_code = code
	_attempt = 0
	_open_socket()
	_set_state(State.CONNECTING)


func _open_socket() -> void:
	_ws = WebSocketPeer.new()
	# v16: 사진(photo_up · photo)은 수십 KB 라 기본 버퍼(64KB)보다 넉넉히.
	_ws.outbound_buffer_size = 1 << 18
	_ws.inbound_buffer_size = 1 << 18
	_open_handled = false
	_connect_started_ms = Time.get_ticks_msec()
	var err: Error = _ws.connect_to_url(_socket_url())
	if err != OK:
		_ws = null
		_on_socket_closed(-1)


## 실제로 여는 WebSocket 주소. 테스트 서버 주소면 앱 안 서버를 (없으면) 띄우고 그 포트로.
func _socket_url() -> String:
	if server_url != TEST_SERVER_URL:
		return server_url
	if test_server == null:
		test_server = LocalTestServer.new()
		test_server.name = "LocalTestServer"
		add_child(test_server)
	if not test_server.start():
		return "ws://127.0.0.1:1"
	return test_server.url()


## 지금 앱 안 테스트 서버에 붙어 있는지.
func is_test_server() -> bool:
	return server_url == TEST_SERVER_URL


## 진짜 서버에 연결하지 못했을 때: 앱 안 테스트 서버로 새로 들어간다 (그 전 세션이 테스트 서버 것이면 이어한다).
func play_on_test_server() -> void:
	var cfg: ConfigFile = _load_settings()
	if str(cfg.get_value("session", "url", "")) == TEST_SERVER_URL and has_saved_session():
		resume_saved_session()
	else:
		create_room(TEST_SERVER_URL)


func _close_socket(code: int, reason: String) -> void:
	if _ws != null:
		_ws.close(code, reason)
		_ws = null
	_open_handled = false


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec()
	if _ws == null:
		if state == State.RECONNECTING and now >= _next_retry_ms:
			_open_socket()
		return

	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now - _connect_started_ms > connect_timeout * 1000.0:
				_ws.close()
				_ws = null
				_on_socket_closed(-1)
		WebSocketPeer.STATE_OPEN:
			if not _open_handled:
				_open_handled = true
				_last_rx_ms = now
				_next_ping_ms = now
				_on_socket_open()
			while _ws != null and _ws.get_available_packet_count() > 0:
				_last_rx_ms = now
				_handle_text(_ws.get_packet().get_string_from_utf8())
			if _ws == null:
				return
			if now >= _next_ping_ms:
				_next_ping_ms = now + ping_interval * 1000.0
				_send({"t": "ping", "c": Time.get_ticks_usec() / 1000.0})
			if state == State.ONLINE and now - _last_rx_ms > idle_timeout * 1000.0:
				push_warning("Net: 서버 응답 없음 — 재접속 시도")
				_ws.close(1006, "idle")
				_ws = null
				_on_socket_closed(1006)
		WebSocketPeer.STATE_CLOSED:
			var code: int = _ws.get_close_code()
			_ws = null
			_on_socket_closed(code)


func _on_socket_open() -> void:
	_set_state(State.JOINING if state != State.RECONNECTING else State.RECONNECTING)
	match _intent:
		Intent.CREATE:
			_send({"t": "create", "v": NetProtocol.VERSION, "uid": uid, "name": nickname()})
		Intent.JOIN:
			_send({"t": "join", "v": NetProtocol.VERSION, "uid": uid, "code": room_code, "name": nickname()})
		Intent.RESUME:
			_send({"t": "resume", "v": NetProtocol.VERSION, "token": _token})


func _on_socket_closed(code: int) -> void:
	_open_handled = false
	if _user_closed or state == State.DISCONNECTED:
		return
	if code == NetProtocol.CLOSE_REPLACED:
		# 같은 세션이 다른 연결로 이어졌다(다른 기기/인스턴스). 재접속하면 서로 뺏고 뺏기게 된다.
		_forget_session()
		_set_state(State.DISCONNECTED)
		session_lost.emit("replaced")
		return
	if _token.is_empty():
		# 방에 들어가기 전의 접속 실패.
		_set_state(State.DISCONNECTED)
		error_received.emit(NetProtocol.ERR_CONNECT_FAILED)
		return
	# 세션이 있으니 재접속을 시도한다.
	var now: float = Time.get_ticks_msec()
	if state != State.RECONNECTING:
		_reconnect_deadline_ms = now + reconnect_window * 1000.0
		_attempt = 0
		_intent = Intent.RESUME
		_set_state(State.RECONNECTING)
		connection_lost.emit()
	if now > _reconnect_deadline_ms:
		_give_up(NetProtocol.ERR_RECONNECT_TIMEOUT)
		return
	var step: int = mini(_attempt, reconnect_backoff.size() - 1)
	_next_retry_ms = now + reconnect_backoff[step] * 1000.0
	_attempt += 1


func _give_up(reason: String) -> void:
	_forget_session()
	_close_socket(1000, "give up")
	_set_state(State.DISCONNECTED)
	session_lost.emit(reason)


func _send(message: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(message))


func _handle_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var msg: Dictionary = parsed
	# 경제 상태(Economy)가 먼저 바뀌어야 welcomed · profile_updated 를 받은 화면이 새 값을 본다.
	message_received.emit(msg)
	match str(msg.get("t", "")):
		"welcome":
			_on_welcome(msg)
		"snap":
			snapshot_received.emit(float(msg.get("st", 0.0)), _parse_states(msg.get("p", [])))
		"peer_joined":
			var joined_data: Variant = msg.get("p", {})
			if joined_data is Dictionary:
				partner_present = true
				partner_online = true
				var joined: NetPlayerState = NetPlayerState.from_dict(joined_data)
				faces[joined.id] = joined.face
				names[joined.id] = joined.display_name
				hunter_ranks[joined.id] = str((joined_data as Dictionary).get("hr", "E"))
				_set_hunter_job(joined.id, str((joined_data as Dictionary).get("hj", "")), bool((joined_data as Dictionary).get("ha", false)))
				peer_joined.emit(joined)
		"peer_status":
			var pid: int = int(msg.get("id", 0))
			partner_online = bool(msg.get("online", false))
			peer_status_changed.emit(pid, partner_online)
		"peer_left":
			partner_present = false
			partner_online = false
			peer_left.emit(int(msg.get("id", 0)))
		"correct":
			position_corrected.emit(Vector3(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)), float(msg.get("z", 0.0))))
		"pong":
			_on_pong(msg)
		"inventory":
			_apply_inventory(msg)
		"profile":
			_apply_profile(msg)
		"veh_result":
			sol = int(msg.get("sol", sol))
			if msg.has("hp"):
				_set_vehicle_hp(msg)
			if str(msg.get("kind", "")) == "cargo":
				var cv2: Dictionary = vehicle(str(msg.get("v", "")))
				if not cv2.is_empty():
					cv2["cargo"] = msg.get("items", [])
			vehicle_done.emit(msg)
		"veh_hp":
			_set_vehicle_hp(msg)
			vehicle_hp.emit(msg)
		"veh_charge":
			var cv: Dictionary = vehicle(str(msg.get("v", "")))
			if not cv.is_empty():
				cv["charge"] = int(msg.get("charge", 0))
				cv["cmax"] = int(msg.get("max", 0))
			vehicle_charge.emit(msg)
		"rammed":
			rammed.emit(msg)
		"seat", "veh_seat":
			var sid: int = int(msg.get("id", my_id))
			if int(msg.get("d", 0)) != 0:
				var entry: Dictionary = {"d": int(msg.get("d", 0)), "s": int(msg.get("s", 0))}
				if msg.has("seat"):
					entry["seat"] = msg.get("seat")
				elif seats.has(sid) and seats[sid].has("seat"):
					entry["seat"] = seats[sid]["seat"]
				seats[sid] = entry
			else:
				seats.erase(sid)
			seat_changed.emit(sid)
		"steps_ok":
			sol = int(msg.get("sol", sol))
			_apply_steps(msg)
			steps_updated.emit(msg)
		"alert":
			alert_received.emit(msg)
		"drill":
			drill = msg if bool(msg.get("on", false)) else {}
			drill_changed.emit(msg)
		"crafted":
			crafted.emit(msg)
		"looted":
			looted.emit(msg)
		"container":
			looted_until[str(msg.get("c", ""))] = float(msg.get("until", 0.0))
			container_changed.emit(str(msg.get("c", "")), float(msg.get("until", 0.0)))
		"hp":
			_set_hp(msg)
		"dodge_ok":
			dodge_ready_at = Time.get_ticks_msec() + int(float(GameData.survival.dodge_cooldown_ms) * dodge_cool_mult())
			dodged.emit(int(msg.get("ms", 380)), float(msg.get("dist", 3.4)))
		"needs":
			food = int(msg.get("food", food))
			water = int(msg.get("water", water))
			needs_changed.emit(food, water)
		"hurt":
			_set_hp(msg)
			hurt.emit(msg)
		"ko":
			_set_hp(msg)
			knocked_out.emit(msg)
		"creatures":
			_apply_creatures(msg.get("c", []))
		"creature_hit":
			var hit_id: String = str(msg.get("id", ""))
			if creatures.has(hit_id):
				creatures[hit_id]["hp"] = int(msg.get("hp", 0))
			creature_hit.emit(msg)
		"creature_dead":
			creatures.erase(str(msg.get("id", "")))
			creature_dead.emit(msg)
		"swing":
			swung.emit(msg)
		"board":
			var key: String = "%s:%s" % [str(msg.get("h", "")), str(msg.get("o", ""))]
			var bhp: int = int(msg.get("hp", 0))
			if bhp > 0:
				boards[key] = bhp
			else:
				boards.erase(key)
			board_changed.emit(key, bhp, msg)
		"boarded":
			boarded.emit(msg)
		"boarding", "board_job":
			_apply_board_job(msg)
		"stash":
			var sh: String = str(msg.get("h", ""))
			stash[sh] = (msg.get("items", []) as Array).duplicate(true) if msg.get("items") is Array else []
			stash_changed.emit(sh)
		"sleep":
			var sid: int = int(msg.get("id", 0))
			if bool(msg.get("on", false)):
				sleeping[sid] = true
			else:
				sleeping.erase(sid)
			sleep_changed.emit(sid)
		"noise":
			noise_made.emit(msg)
		"bleed":
			var bid: int = int(msg.get("id", 0))
			if bool(msg.get("on", false)):
				bleeding[bid] = true
			else:
				bleeding.erase(bid)
			bleed_changed.emit(bid)
		"scent":
			var drop: Dictionary = {"id": int(msg.get("id", 0)), "x": float(msg.get("x", 0.0)), "z": float(msg.get("z", 0.0)), "until": Time.get_ticks_msec() + int(msg.get("ms", 40000))}
			scent.append(drop)
			scent_dropped.emit(drop)
		"supply":
			var crate: Dictionary = msg.get("s", {}) if msg.get("s") is Dictionary else {}
			var cid: String = str(crate.get("id", ""))
			if not cid.is_empty():
				supply[cid] = {"x": float(crate.get("x", 0.0)), "z": float(crate.get("z", 0.0)), "land": Time.get_ticks_msec() + int(crate.get("left", 0))}
				supply_changed.emit(cid)
		"supply_land":
			var lid: String = str(msg.get("s", ""))
			if supply.has(lid):
				supply[lid]["land"] = mini(int(supply[lid]["land"]), Time.get_ticks_msec())
				supply_changed.emit(lid)
		"supply_gone":
			var gid: String = str(msg.get("s", ""))
			if supply.has(gid):
				supply.erase(gid)
				supply_changed.emit(gid)
				supply_taken.emit(gid, int(msg.get("by", 0)))
		"supply_got":
			supply_got.emit(msg)
		"hunter":
			hunter = msg
			var ready: Dictionary = msg.get("awReady", {}) if msg.get("awReady") is Dictionary else {}
			for aid: Variant in ready:
				awaken_ready_at[str(aid)] = Time.get_ticks_msec() + int(ready[aid])
			var jready: Dictionary = msg.get("jReady", {}) if msg.get("jReady") is Dictionary else {}
			for jid: Variant in jready:
				skill_ready_at[str(jid)] = Time.get_ticks_msec() + int(jready[jid])
			hunter_ranks[my_id] = str(msg.get("rank", "E"))
			_set_hunter_job(my_id, str(msg.get("job", "")), bool(msg.get("adv", false)))
			var hg: Variant = msg.get("guild", null)
			guild = hg if hg is Dictionary else {}
			hunter_changed.emit()
		"guild":
			var gg: Variant = msg.get("g", null)
			guild = gg if gg is Dictionary else {}
			guild_changed.emit(msg)
		"hunter_job":
			_set_hunter_job(int(msg.get("id", 0)), str(msg.get("j", "")), bool(msg.get("a", false)))
		"hunter_level":
			hunter_done.emit({"kind": "remote_level", "id": int(msg.get("id", 0)), "lv": int(msg.get("lv", 1))})
		"hunter_rank":
			hunter_ranks[int(msg.get("id", 0))] = str(msg.get("rank", "E"))
			hunter_done.emit({"kind": "remote_rank", "id": int(msg.get("id", 0)), "rank": str(msg.get("rank", "E"))})
		"hunter_result":
			if str(msg.get("kind", "")) == "awaken_use":
				awaken_ready_at[str(msg.get("a", ""))] = Time.get_ticks_msec() + int(msg.get("cd", 0))
			hunter_done.emit(msg)
		"awaken_fx":
			awaken_fx.emit(int(msg.get("id", 0)), str(msg.get("a", "")), int(msg.get("ms", 0)))
		"shield_block":
			shield_blocked.emit(int(msg.get("id", 0)), int(msg.get("left", 0)))
		"guard_block":
			guard_blocked.emit(int(msg.get("id", 0)), int(msg.get("sanct", 0)) == 1)
		"skill_ok":
			skill_ready_at[str(msg.get("a", ""))] = Time.get_ticks_msec() + int(msg.get("cd", 0))
			skill_used.emit(str(msg.get("a", "")), int(msg.get("cd", 0)))
		"skill_fx":
			skill_fx.emit(msg)
		"gate":
			var gw: Dictionary = msg.get("g", {}) if msg.get("g") is Dictionary else {}
			var gid: String = str(gw.get("id", ""))
			if not gid.is_empty():
				gates[gid] = _gate_entry(gw)
				gate_changed.emit(gid)
		"gate_gone":
			var gone_id: String = str(msg.get("g", ""))
			if gates.erase(gone_id):
				gate_changed.emit(gone_id)
		"gate_entered":
			gate_entered.emit(str(msg.get("g", "")))
		"gate_left":
			gate_left.emit(str(msg.get("g", "")))
		"gate_clear":
			gate_cleared.emit(msg)
		"guard_shot":
			var sg: String = str(msg.get("g", ""))
			if guards.has(sg):
				guards[sg]["yaw"] = atan2(float(msg.get("x", 0.0)) - float(guards[sg]["x"]), float(msg.get("z", 0.0)) - float(guards[sg]["z"]))
			guard_shot.emit(msg)
		"guard_hit":
			var hg: String = str(msg.get("g", ""))
			if guards.has(hg):
				guards[hg]["hp"] = int(msg.get("hp", 0))
				guard_changed.emit(hg)
		"guard_down":
			var dg: String = str(msg.get("g", ""))
			if guards.has(dg):
				guards[dg]["hp"] = 0
				guards[dg]["until"] = Time.get_ticks_msec() + int(float(msg.get("left", 0)) / maxf(_world_scale, 1.0))
				guard_changed.emit(dg)
		"guard_up":
			var ug: String = str(msg.get("g", ""))
			if guards.has(ug):
				guards[ug]["hp"] = int(guards[ug]["max"])
				guards[ug]["until"] = 0
				guard_changed.emit(ug)
		"npc_hit", "npc_down", "npc_up":
			npc_hurt.emit(msg)
		"downed":
			downed[int(msg.get("id", 0))] = {"until": Time.get_ticks_msec() + int(msg.get("left", 0)), "by": 0, "done": 0}
			downed_changed.emit(int(msg.get("id", 0)))
		"revive":
			var who: int = int(msg.get("id", 0))
			if downed.has(who):
				downed[who]["by"] = int(msg.get("by", 0))
				downed[who]["done"] = Time.get_ticks_msec() + int(msg.get("ms", 0)) if int(msg.get("by", 0)) != 0 else 0
				downed_changed.emit(who)
		"up":
			downed.erase(int(msg.get("id", 0)))
			downed_changed.emit(int(msg.get("id", 0)))
		"drill_done":
			sol = int(msg.get("sol", sol))
			if not drill.is_empty():
				drill["done"] = true
			drill_finished.emit(msg)
		"veh_parked":
			_apply_parked(msg.get("list", []))
		"aqua_trips":
			_apply_aqua(msg.get("list", []))
		"aqua_result":
			sol = int(msg.get("sol", sol))
			aqua_done.emit(msg)
		"aqua_fx":
			aqua_fx.emit(str(msg.get("trip", "")), int(msg.get("id", 0)), int(msg.get("turn", 0)), bool(msg.get("fell", false)))
		"aqua_end":
			aqua_ended.emit(msg)
		"veh_ride":
			var mount: Variant = msg.get("mount", null)
			mount_changed.emit(mount if mount is Dictionary else {})
		"face":
			var face_id: int = int(msg.get("id", 0))
			_pending.erase(str(msg.get("rid", "")))
			var face_data: Variant = msg.get("face", {})
			if face_data is Dictionary:
				faces[face_id] = face_data
				face_changed.emit(face_id, face_data)
		"name":
			var name_id: int = int(msg.get("id", 0))
			_pending.erase(str(msg.get("rid", "")))
			names[name_id] = str(msg.get("name", ""))
			if name_id == my_id:
				save_nickname(names[name_id])
			name_changed.emit(name_id, names[name_id])
		"weather":
			weather = str(msg.get("w", weather))
			weather_changed.emit(weather)
		"lightning":
			lightning_roll = bool(msg.get("roll", false))
			lightning_struck.emit(float(msg.get("power", 1.0)))
		"thunder":
			thunder_rumbled.emit()
		"tree":
			var tree_id: String = str(msg.get("id", ""))
			if msg.has("k") and not planted_trees.has(tree_id):
				var info: TreeInfo = TreeInfo.planted_from_dict(msg)
				planted_trees[tree_id] = info
				tree_stages[tree_id] = str(msg.get("s", NetProtocol.TREE_SPROUT))
				tree_planted.emit(info)
			tree_stages[tree_id] = str(msg.get("s", NetProtocol.TREE_GROWN))
			tree_changed.emit(tree_id, tree_stages[tree_id], int(msg.get("c", 0)))
		"flower":
			var fd: Variant = msg.get("f", {})
			if fd is Dictionary:
				var flower: FlowerState = FlowerState.from_dict(fd)
				flowers[flower.id] = flower
				flower_changed.emit(flower, int(msg.get("by", 0)))
		"plant_result":
			_pending.erase(str(msg.get("rid", "")))
			planted.emit(str(msg.get("kind", "")), str(msg.get("id", "")))
		"pick_result":
			_pending.erase(str(msg.get("rid", "")))
			flower_picked.emit(str(msg.get("item", "")))
		"npc_greet":
			npc_greeted.emit(str(msg.get("npc", "")))
		"npc_emote":
			var npc_id: String = str(msg.get("npc", ""))
			npc_moods[npc_id] = str(msg.get("m", npc_moods.get(npc_id, "calm")))
			npc_emoted.emit(npc_id, str(msg.get("e", "")), int(msg.get("to", 0)), npc_moods[npc_id], str(msg.get("from", "")))
		"talk_topic":
			var talked: String = str(msg.get("npc", ""))
			npc_moods[talked] = str(msg.get("m", npc_moods.get(talked, "calm")))
			topic_answered.emit(talked, str(msg.get("topic", "")), int(msg.get("gain", 0)))
		"museum":
			_apply_museum(msg)
			museum_changed.emit(str(msg.get("id", "")), int(msg.get("by", 0)))
		"donate_result":
			_pending.erase(str(msg.get("rid", "")))
			sol = int(msg.get("sol", sol))
			var gifts: PackedStringArray = []
			for g: Variant in msg.get("gifts", []):
				gifts.append(str(g))
			donated.emit(str(msg.get("fish", "")), int(msg.get("reward", 0)), int(msg.get("count", 0)), gifts)
		"npcs":
			npc_states = _parse_npcs(msg.get("n", []))
			npcs_received.emit(float(msg.get("st", 0.0)), npc_states)
		"act":
			if str(msg.get("kind", "")) == "emote":
				peer_emoted.emit(int(msg.get("id", 0)), str(msg.get("e", "")))
			peer_action.emit(int(msg.get("id", 0)), str(msg.get("kind", "")), str(msg.get("tree", msg.get("e", ""))))
			peer_act.emit(int(msg.get("id", 0)), str(msg.get("kind", "")), msg)
		"say":
			peer_said.emit(int(msg.get("id", 0)), str(msg.get("npc", "")), str(msg.get("tx", "")))
		"chop_result":
			_pending.erase(str(msg.get("rid", "")))
			last_chop_count = int(msg.get("n", 1))
			chop_succeeded.emit(str(msg.get("tree", "")), str(msg.get("item", "")), bool(msg.get("felled", false)))
		"talk_open":
			_pending.erase(str(msg.get("rid", "")))
			talk_opened.emit(TalkReply.from_dict(msg))
		"talk_closed":
			talk_closed.emit(str(msg.get("npc", "")))
		"quest_accepted":
			_pending.erase(str(msg.get("rid", "")))
			var accepted: Variant = msg.get("quest", {})
			if accepted is Dictionary:
				quest_accepted.emit(QuestInfo.from_dict(accepted))
		"shop":
			_apply_shop(msg)
			shop_updated.emit(bool(msg.get("up", false)))
		"shop_door":
			_pending.erase(str(msg.get("rid", "")))
			_apply_shop(msg.get("shop", {}))
			shop_door_passed.emit(bool(msg.get("inside", false)), Vector3(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)), float(msg.get("z", 0.0))))
		"shop_result":
			_pending.erase(str(msg.get("rid", "")))
			sol = int(msg.get("sol", sol))
			last_trade_stored = bool(msg.get("stored", false))
			shop_traded.emit(str(msg.get("kind", "")), str(msg.get("item", "")), int(msg.get("n", 1)), int(msg.get("amount", 0)))
		"placed":
			_pending.erase(str(msg.get("rid", "")))
			var f: Variant = msg.get("f", {})
			if f is Dictionary:
				var info: PlacedInfo = PlacedInfo.from_dict(f)
				placed[info.id] = info
				furniture_placed.emit(info, int(msg.get("by", 0)))
		"unplaced":
			_pending.erase(str(msg.get("rid", "")))
			var removed_id: String = str(msg.get("id", ""))
			placed.erase(removed_id)
			furniture_removed.emit(removed_id)
		"quest_done":
			_pending.erase(str(msg.get("rid", "")))
			sol = int(msg.get("sol", sol))
			quest_completed.emit(str(msg.get("quest", "")), str(msg.get("npc", "")), int(msg.get("reward", 0)))
		"fish_started":
			last_fish = {"fid": str(msg.get("fid", "")), "size": str(msg.get("size", "")), "ms": int(msg.get("ms", 0)),
				"bx": msg.get("bx"), "bz": msg.get("bz")}
			fish_started.emit(float(msg.get("shadow", 1.0)))
		"fish_found":
			last_fish.merge({"fid": str(msg.get("fid", "")), "size": str(msg.get("size", "")), "ms": int(msg.get("ms", 0))}, true)
			fish_found.emit(float(msg.get("shadow", 1.0)))
		"fishes":
			var school: Array[Dictionary] = []
			for entry: Variant in msg.get("f", []):
				if entry is Dictionary:
					school.append(entry)
			fishes[str(msg.get("spot", ""))] = school
			fishes_updated.emit(str(msg.get("spot", "")), school)
		"fish_reel":
			fish_reel.emit(int(msg.get("taps", 6)), int(msg.get("ms", 2600)))
		"fish_nibble":
			fish_nibble.emit()
		"fish_bite":
			fish_bite.emit(int(msg.get("windowMs", 600)))
		"fish_result":
			_fishing_rid = ""
			fish_result.emit(bool(msg.get("ok", false)), str(msg.get("fish", "")), str(msg.get("reason", "")))
			if int(msg.get("bonus", 0)) > 0:
				fish_bonus.emit(int(msg.get("bonus", 0)))
		"ev":
			_apply_events(msg)
		"drop":
			var dropped: Variant = msg.get("d", {})
			if dropped is Dictionary:
				var d: DropInfo = DropInfo.from_dict(dropped)
				d.dropped_by = int(msg.get("by", d.dropped_by))
				var known: bool = drops.has(d.id)
				drops[d.id] = d
				if known:
					drop_changed.emit(d)
				else:
					drop_added.emit(d)
		"drop_gone":
			var gone: String = str(msg.get("id", ""))
			drops.erase(gone)
			drop_removed.emit(gone, int(msg.get("by", 0)))
		"deliv_ok":
			_pending.erase(str(msg.get("rid", "")))
			sol = int(msg.get("sol", sol))
			# 같은 상자(id)에 담겼으면 그 상자의 물건 목록만 바꾼다.
			var box_id: String = str(msg.get("id", ""))
			var box_items: Array = msg.get("items", [{"item": msg.get("item", ""), "n": msg.get("n", 1)}])
			var found: bool = false
			for d: Dictionary in my_deliveries:
				if str(d.get("id", "")) == box_id:
					d["items"] = box_items
					d["orders"] = int(msg.get("orders", 1))
					found = true
			if not found:
				my_deliveries.append({"id": box_id, "items": box_items, "orders": int(msg.get("orders", 1)), "ph": "wait"})
			delivery_ordered.emit(str(msg.get("item", "")), int(msg.get("n", 1)), int(msg.get("eta", 0)), int(msg.get("amount", 0)), bool(msg.get("merged", false)))
		"deliv_done":
			var done_id: String = str(msg.get("id", ""))
			my_deliveries = my_deliveries.filter(func(d: Dictionary) -> bool: return str(d.get("id", "")) != done_id)
			var got: Array[Dictionary] = []
			for entry: Variant in msg.get("items", []):
				if entry is Dictionary:
					got.append(entry)
			delivery_done.emit(got)
		"couriers":
			_apply_couriers(msg.get("c", []))
		"collect_result":
			_pending.erase(str(msg.get("rid", "")))
			last_collect_count = int(msg.get("n", 1))
			last_collect_left = int(msg.get("left", 0))
			collected.emit(str(msg.get("kind", "")), str(msg.get("item", "")))
		"error":
			_on_server_error(str(msg.get("code", "")), msg)
	if msg.get("t") != "error" and msg.get("rid") != null:
		_pending.erase(str(msg.get("rid")))


func _on_welcome(msg: Dictionary) -> void:
	var resumed: bool = bool(msg.get("resumed", false))
	my_id = int(msg.get("id", 0))
	_token = str(msg.get("token", ""))
	room_code = str(msg.get("code", room_code))
	dev_tools = bool(msg.get("dev", false))
	_save_last_room(room_code)
	_intent = Intent.NONE
	_attempt = 0
	var me: NetPlayerState = null
	var others: Array[NetPlayerState] = []
	faces.clear()
	names.clear()
	for player_state: NetPlayerState in _parse_states(msg.get("players", [])):
		faces[player_state.id] = player_state.face
		names[player_state.id] = player_state.display_name
		if player_state.id == my_id:
			me = player_state
		else:
			others.append(player_state)
	partner_present = not others.is_empty()
	partner_online = partner_present and others[0].online
	_join_fallback_tried = false
	_fishing_rid = ""
	_pending.clear()
	_apply_inventory(msg.get("inv", {}))
	_apply_profile(msg.get("prof", {}))
	_sync_nickname()
	_apply_clock(msg.get("clock", {}))
	# v0.23 생존.
	var surv: Dictionary = msg.get("surv", {}) if msg.get("surv") is Dictionary else {}
	looted_until.clear()
	var looted_map: Variant = surv.get("looted", {})
	if looted_map is Dictionary:
		for id: Variant in looted_map:
			looted_until[str(id)] = float(looted_map[id])
	night = bool(surv.get("night", false))
	_set_hp({"hp": surv.get("hp", max_hp), "max": surv.get("max", max_hp)})
	var nd: Dictionary = surv.get("needs", {}) if surv.get("needs") is Dictionary else {}
	food = int(nd.get("food", 100))
	water = int(nd.get("water", 100))
	needs_changed.emit(food, water)
	creatures.clear()
	_apply_creatures(surv.get("creatures", []))
	boards.clear()
	var board_map: Variant = surv.get("boards", {})
	if board_map is Dictionary:
		for key: Variant in board_map:
			boards[str(key)] = int(board_map[key])
	board_jobs.clear()
	for j: Variant in surv.get("jobs", []):
		if j is Dictionary:
			_apply_board_job(j)
	stash.clear()
	var stash_map: Variant = surv.get("stash", {})
	if stash_map is Dictionary:
		for h: Variant in stash_map:
			stash[str(h)] = (stash_map[h] as Array).duplicate(true) if stash_map[h] is Array else []
	sleeping.clear()
	for sid: Variant in surv.get("sleeping", []):
		sleeping[int(sid)] = true
	bleeding.clear()
	for bid: Variant in surv.get("bleeding", []):
		bleeding[int(bid)] = true
	scent.clear()
	for d: Variant in surv.get("scent", []):
		if d is Dictionary:
			scent.append({"id": int(d.get("id", 0)), "x": float(d.get("x", 0.0)), "z": float(d.get("z", 0.0)), "until": Time.get_ticks_msec() + int(d.get("left", 0))})
	var hw: Variant = msg.get("hunter", {})
	hunter = hw if hw is Dictionary else {}
	var hgw: Variant = hunter.get("guild", null)
	guild = hgw if hgw is Dictionary else {}
	hunter_ranks.clear()
	for pv: Variant in msg.get("players", []):
		if pv is Dictionary:
			hunter_ranks[int(pv.get("id", 0))] = str(pv.get("hr", "E"))
			_set_hunter_job(int(pv.get("id", 0)), str(pv.get("hj", "")), bool(pv.get("ha", false)))
	guards.clear()
	for gd: Variant in surv.get("guards", []):
		if gd is Dictionary:
			var left_ms: int = int(float(gd.get("left", 0)) / maxf(_world_scale, 1.0))
			guards[str(gd.get("id", ""))] = {"x": float(gd.get("x", 0.0)), "z": float(gd.get("z", 0.0)), "yaw": float(gd.get("yaw", 0.0)), "hp": int(gd.get("hp", 1)), "max": int(gd.get("max", 1)), "until": Time.get_ticks_msec() + left_ms if left_ms > 0 else 0}
	gates.clear()
	for gv: Variant in surv.get("gates", []):
		if gv is Dictionary:
			gates[str(gv.get("id", ""))] = _gate_entry(gv)
	supply.clear()
	for d: Variant in surv.get("supply", []):
		if d is Dictionary:
			supply[str(d.get("id", ""))] = {"x": float(d.get("x", 0.0)), "z": float(d.get("z", 0.0)), "land": Time.get_ticks_msec() + int(d.get("left", 0))}
	downed.clear()
	for d: Variant in surv.get("downed", []):
		if d is Dictionary:
			downed[int(d.get("id", 0))] = {"until": Time.get_ticks_msec() + int(d.get("left", 0)), "by": int(d.get("by", 0)), "done": 0}
	weather = str(msg.get("w", NetProtocol.WEATHER_CLEAR))
	tree_stages.clear()
	planted_trees.clear()
	var tree_list: Variant = msg.get("trees", [])
	if tree_list is Array:
		for entry: Variant in tree_list:
			if entry is Dictionary:
				tree_stages[str(entry.get("id", ""))] = str(entry.get("s", NetProtocol.TREE_GROWN))
				if entry.has("k"):
					var planted_info: TreeInfo = TreeInfo.planted_from_dict(entry)
					planted_trees[planted_info.id] = planted_info
	flowers.clear()
	var flower_list: Variant = msg.get("flowers", [])
	if flower_list is Array:
		for entry: Variant in flower_list:
			if entry is Dictionary:
				var fl: FlowerState = FlowerState.from_dict(entry)
				flowers[fl.id] = fl
	museum_fish.clear()
	_apply_museum(msg.get("museum", {}))
	npc_states = _parse_npcs(msg.get("npcs", []))
	_apply_shop(msg.get("shop", {}))
	placed.clear()
	var placed_list: Variant = msg.get("placed", [])
	if placed_list is Array:
		for entry: Variant in placed_list:
			if entry is Dictionary:
				var p: PlacedInfo = PlacedInfo.from_dict(entry)
				placed[p.id] = p
	drops.clear()
	_apply_couriers(msg.get("couriers", []))
	_apply_parked(msg.get("parked", []))
	seats.clear()
	for st: Variant in msg.get("seats", []):
		if st is Dictionary:
			seats[int(st.get("id", 0))] = {"d": int(st.get("d", 0)), "s": int(st.get("s", 0))}
	_apply_aqua(msg.get("aqua", []))
	my_deliveries.clear()
	for entry: Variant in msg.get("deliv", []):
		if entry is Dictionary:
			my_deliveries.append(entry)
	var drop_list: Variant = msg.get("drops", [])
	if drop_list is Array:
		for entry: Variant in drop_list:
			if entry is Dictionary:
				var dd: DropInfo = DropInfo.from_dict(entry)
				drops[dd.id] = dd
	events.clear()
	_apply_events(msg.get("ev", {}), false)
	_save_session()
	_set_state(State.ONLINE)
	if me != null:
		welcomed.emit(me, others, resumed)
	weather_changed.emit(weather)
	npcs_received.emit(float(msg.get("st", 0.0)), npc_states)


## 이벤트 목록 받기. announce 면 새로 열린 이벤트를 알린다 (접속할 때는 이미 열려 있던 것도 한 번 알린다).
func _apply_events(data: Variant, announce: bool = true) -> void:
	if not data is Dictionary:
		return
	var before: PackedStringArray = []
	for e: ActiveEvent in events:
		before.append(e.id)
	events.clear()
	var started: PackedStringArray = []
	for entry: Variant in (data as Dictionary).get("list", []):
		if entry is Dictionary:
			var e: ActiveEvent = ActiveEvent.from_dict(entry)
			events.append(e)
			if not e.id in before:
				started.append(e.id)
	if announce or not started.is_empty():
		events_changed.emit(started)


func _next_rid() -> String:
	_rid_counter += 1
	return "%s-%d" % [uid.left(6), _rid_counter]


## v0.23 빈집 가구 뒤지기 · 크리처 공격 · 회복 아이템 쓰기 (모두 서버가 판정).
func loot(container_id: String) -> void:
	if state == State.ONLINE:
		_request("loot", {"c": container_id})


## v0.28 헌터: 협회 창구에서 마석 팔기 (slot < 0 이면 모두) · 등급 재심사 · 의뢰 완료 보고 · 길드.
func hunter_sell(slot: int, n: int = 0) -> void:
	if state == State.ONLINE:
		_request("hunter_sell", {"all": true} if slot < 0 else {"slot": slot, "n": n})


func hunter_rank_up() -> void:
	if state == State.ONLINE:
		_request("hunter_rank", {})


func hunter_claim(bounty_id: String) -> void:
	if state == State.ONLINE:
		_request("hunter_claim", {"b": bounty_id})


func guild_create(guild_name: String) -> void:
	if state == State.ONLINE:
		_request("guild_create", {"name": guild_name})


func guild_join() -> void:
	if state == State.ONLINE:
		_request("guild_join", {})


func guild_leave() -> void:
	if state == State.ONLINE:
		_request("guild_leave", {})


## v0.28 게이트 진입 (곁에서, 헌터 등급 확인은 서버).
func gate_enter(gate_id: String) -> void:
	if state == State.ONLINE:
		_request("gate_enter", {"g": gate_id})


## v0.28.2 던전에서 나가기 (나가는 균열 곁에서).
func gate_leave(gate_id: String) -> void:
	if state == State.ONLINE:
		_request("gate_leave", {"g": gate_id})


func _gate_entry(gw: Dictionary) -> Dictionary:
	var raiders: Array[int] = []
	for r: Variant in gw.get("raiders", []):
		raiders.append(int(r))
	return {"rank": str(gw.get("rank", "E")), "spot": str(gw.get("spot", "")), "name": str(gw.get("name", "")), "x": float(gw.get("x", 0.0)), "z": float(gw.get("z", 0.0)),
		"st": str(gw.get("st", "open")), "until": Time.get_ticks_msec() + int(gw.get("left", 0)), "wave": int(gw.get("wave", 0)), "waves": int(gw.get("waves", 1)),
		"alive": int(gw.get("alive", 0)), "boss": int(gw.get("boss", 0)) == 1, "raiders": raiders, "map": str(gw.get("map", ""))}


## 내가 길드원인지.
func in_guild() -> bool:
	for m: Variant in guild.get("members", []):
		if m is Dictionary and int(m.get("id", 0)) == my_id:
			return true
	return false


## v0.27 보급 상자 열기 (먼저 연 사람이 갖는다).
func open_supply(crate_id: String) -> void:
	if state == State.ONLINE:
		_request("supply_open", {"s": crate_id})


## run: 달리며 휘두름 (v0.28.1 "달리며 공격" 기술이 있으면 서버가 사거리를 늘린다).
func attack(run: bool = false) -> void:
	if state == State.ONLINE:
		_request("attack", {"run": true} if run else {})


## v0.28.1 스탯 포인트 쓰기 (str · vit · agi · luk).
func stat_up(stat: String) -> void:
	if state == State.ONLINE:
		_request("stat_up", {"s": stat})


## 배운 기술인지 (서버 hunter.skills).
func has_skill(skill_id: String) -> bool:
	return (hunter.get("skills", []) as Array).has(skill_id)


## v0.28.5 고른 각성인지 · 각성 고르기 · 쓰기 (판정은 서버). 다시 쓸 수 있는 때 (ticks ms).
var awaken_ready_at: Dictionary[String, int] = {}


func has_awaken(awaken_id: String) -> bool:
	return (hunter.get("aw", []) as Array).has(awaken_id)


func awaken_pick(awaken_id: String) -> void:
	if state == State.ONLINE:
		_request("awaken", {"a": awaken_id})


func awaken_use(awaken_id: String) -> void:
	if state == State.ONLINE:
		_request("awaken_use", {"a": awaken_id})


## v0.28.8 전직 · 기술 나무 (판정은 서버). 액티브 기술을 다시 쓸 수 있는 때 (ticks ms).
var skill_ready_at: Dictionary[String, int] = {}
## v0.28.9 내 '피의 광란' 이 끝나는 때 (ticks ms, 공격 간격 표시용 — 판정은 서버).
var frenzy_until: int = 0


## v0.28.9 다른 사람 (나 포함) 의 직업 · 2차 전직 (이름표 · 휘장): id → [job, adv].
var hunter_jobs: Dictionary[int, Array] = {}


func job_of(player_id: int) -> String:
	return str((hunter_jobs.get(player_id, ["", false]) as Array)[0])


func advanced_of(player_id: int) -> bool:
	return bool((hunter_jobs.get(player_id, ["", false]) as Array)[1])


func _set_hunter_job(player_id: int, job: String, adv: bool) -> void:
	var before: Array = hunter_jobs.get(player_id, ["", false])
	hunter_jobs[player_id] = [job, adv]
	if str(before[0]) != job or bool(before[1]) != adv:
		hunter_job_changed.emit(player_id)


func class_advance() -> void:
	if state == State.ONLINE:
		_request("class_advance", {})


func is_advanced() -> bool:
	return bool(hunter.get("adv", false))


func class_pick(job_id: String) -> void:
	if state == State.ONLINE:
		_request("class_pick", {"j": job_id})


func skill_up(node_id: String) -> void:
	if state == State.ONLINE:
		_request("skill_up", {"n": node_id})


func skill_reset() -> void:
	if state == State.ONLINE:
		_request("skill_reset", {})


func skill_use(active_id: String) -> void:
	if state == State.ONLINE:
		_request("skill_use", {"a": active_id})


## 내 직업 ("" = 아직) · 배운 기술 (id → 단계) · 남은 기술 포인트.
func job_id() -> String:
	return str(hunter.get("job", ""))


func job_learned() -> Dictionary:
	return hunter.get("jt", {}) if hunter.get("jt") is Dictionary else {}


func job_fx(key: String) -> float:
	return GameData.hunter.job_fx(job_id(), job_learned(), key) if GameData.hunter != null else 0.0


## 배운 액티브 기술 id 들 (나무 순서).
func job_actives() -> PackedStringArray:
	var out: PackedStringArray = []
	if GameData.hunter == null:
		return out
	for n: Variant in GameData.hunter.job(job_id()).get("tree", []):
		var a: String = str((n as Dictionary).get("active", ""))
		if not a.is_empty() and int(job_learned().get(str((n as Dictionary).get("id", "")), 0)) > 0:
			out.append(a)
	return out


## v0.28.7 회피 구르기 요청 (서버가 dodge_ok 로 허락해야 구른다). 이 시각 (ms) 전에는 다시 못 한다 (단추 표시용).
var dodge_ready_at: int = 0


func dodge() -> void:
	if state == State.ONLINE:
		_request("dodge", {})


## 민첩만큼 짧아지는 재사용 배율 (서버 hunter.bonus.cooldown 과 같은 셈).
func dodge_cool_mult() -> float:
	var st: Dictionary = hunter.get("st", {}) if hunter.get("st") is Dictionary else {}
	var per: float = float((GameData.hunter.level_stats.get("agi", {}) as Dictionary).get("cooldown", 0.0)) if GameData.hunter != null else 0.0
	return maxf(0.3, 1.0 - float(st.get("agi", 0)) * per) * maxf(0.4, 1.0 - job_fx("cd")) * maxf(0.4, 1.0 - job_fx("dodge_cd"))


func use_item(slot: int) -> void:
	if state == State.ONLINE:
		_request("use", {"slot": slot})


## v0.24 빈집 현관 · 깨진 창에 판자 대기 (보수도 같다) · 쓰러진 동료 일으키기 · 쓰러진 채 포기 (대피소에서 깨어난다).
func board(house_id: String, opening_id: String) -> void:
	if state == State.ONLINE:
		_request("board", {"h": house_id, "o": opening_id})


func revive(player_id: int) -> void:
	if state == State.ONLINE:
		_request("revive", {"p": player_id})


func give_up() -> void:
	if state == State.ONLINE:
		_request("give_up", {})


## v0.25 거점 상자에 넣기 (가방 칸, n = 0 이면 그 칸 다) · 꺼내기 · 침대에서 자기 / 일어나기.
func stash_put(house_id: String, slot: int, n: int = 0) -> void:
	if state == State.ONLINE:
		_request("stash", {"h": house_id, "op": "put", "slot": slot, "n": n})


func stash_take(house_id: String, item_id: String, n: int = 0) -> void:
	if state == State.ONLINE:
		_request("stash", {"h": house_id, "op": "take", "id": item_id, "n": n})


func sleep_in_bed(on: bool) -> void:
	if state == State.ONLINE:
		_request("sleep", {"on": on})


func _apply_board_job(msg: Dictionary) -> void:
	var key: String = "%s:%s" % [str(msg.get("h", "")), str(msg.get("o", ""))]
	if bool(msg.get("cancel", false)) or bool(msg.get("done", false)):
		board_jobs.erase(key)
	else:
		var helpers: Array[int] = []
		for id: Variant in msg.get("helpers", []):
			helpers.append(int(id))
		board_jobs[key] = {"progress": float(msg.get("progress", 0.0)), "need": float(msg.get("need", 1.0)), "helpers": helpers, "at": Time.get_ticks_msec()}
	board_job_changed.emit(key)


func is_downed(player_id: int) -> bool:
	return downed.has(player_id)


## 이 가구를 지금 뒤질 수 있는지 (다시 찰 때가 지났는지).
func can_loot(container_id: String) -> bool:
	return float(looted_until.get(container_id, 0.0)) <= world_ms()


func _set_hp(msg: Dictionary) -> void:
	hp = int(msg.get("hp", hp))
	max_hp = int(msg.get("max", max_hp))
	hp_changed.emit(hp, max_hp)


func _apply_creatures(list: Variant) -> void:
	var seen: Dictionary = {}
	for c: Variant in list if list is Array else []:
		if c is Dictionary:
			var id: String = str(c.get("id", ""))
			seen[id] = true
			creatures[id] = c
	for id: String in creatures.keys():
		if not seen.has(id):
			creatures.erase(id)
	creatures_updated.emit()


## v0.22 제작대에서 만들기 (서버가 작업대 거리 · 재료 · 가방을 보고 crafted 또는 request_failed("craft", …)).
func craft(recipe_id: String, n: int = 1) -> void:
	if state == State.ONLINE:
		_request("craft", {"recipe": recipe_id, "n": n})


## 다른 오토로드(Economy)가 쓰는 요청 (rid 를 붙이고, 거부되면 request_failed 로 알린다).
func request(kind: String, fields: Dictionary = {}) -> void:
	_request(kind, fields)


## rid 없이 보내는 메시지 (bank_quote · rest_cook 처럼 중복돼도 괜찮은 것).
func send_message(message: Dictionary) -> void:
	if state == State.ONLINE:
		_send(message)


## 요청 ID를 붙여 보내고, 거부되면 어떤 요청이었는지 알 수 있게 기록해 둔다.
func _request(kind: String, fields: Dictionary) -> void:
	var rid: String = _next_rid()
	if _pending.size() > 32:
		_pending.clear()
	_pending[rid] = kind
	var message: Dictionary = {"t": kind, "rid": rid}
	message.merge(fields)
	_send(message)


func _apply_inventory(data: Variant) -> void:
	if not data is Dictionary:
		return
	var parsed: Array[InventoryItem] = []
	var entries: Variant = data.get("slots", [])
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				parsed.append(InventoryItem.new(str(entry.get("id", "")), int(entry.get("n", 0))))
			else:
				parsed.append(null)
	inventory = parsed
	quick_slot_count = int(data.get("quick", quick_slot_count))
	inventory_capacity = int(data.get("cap", inventory_capacity))
	held_slot = int(data.get("held", held_slot))
	inventory_updated.emit(inventory, held_slot)


func _apply_steps(info: Dictionary) -> void:
	steps_today = int(info.get("today", steps_today))
	var got: Array[int] = []
	for g: Variant in info.get("got", []):
		got.append(int(g))
	steps_got = got


func _apply_profile(data: Variant) -> void:
	if not data is Dictionary:
		return
	sol = int(data.get("sol", sol))
	if data.get("steps") is Dictionary:
		_apply_steps(data["steps"])
	var parsed: Array[QuestInfo] = []
	var list: Variant = data.get("quests", [])
	if list is Array:
		for entry: Variant in list:
			if entry is Dictionary:
				parsed.append(QuestInfo.from_dict(entry))
	quests = parsed
	friends.clear()
	var f: Variant = data.get("friends", {})
	if f is Dictionary:
		for npc_id: Variant in f:
			friends[str(npc_id)] = int(f[npc_id])
	var o: Variant = data.get("outfit", {})
	if o is Dictionary:
		outfit_hat = str(o.get("hat", ""))
		outfit_top = str(o.get("top", ""))
	var e: Variant = data.get("emotes", {})
	if e is Dictionary:
		emotes_known = PackedStringArray(Array(e.get("known", ["hello"])).map(func(x: Variant) -> String: return str(x)))
		emotes_quick = PackedStringArray(Array(e.get("quick", ["hello"])).map(func(x: Variant) -> String: return str(x)))
	var my_face: Variant = data.get("face", null)
	if my_face is Dictionary and my_id > 0:
		faces[my_id] = my_face
	if data.has("name") and my_id > 0:
		names[my_id] = str(data.get("name", ""))
	var garage: Variant = data.get("vehicles", null)
	if garage is Array:
		vehicles.clear()
		for v: Variant in garage:
			if v is Dictionary:
				vehicles.append(v)
		vehicles_changed.emit()
	profile_updated.emit()


func _apply_museum(data: Variant) -> void:
	if not data is Dictionary:
		return
	var fish_map: Variant = (data as Dictionary).get("fish", {})
	if fish_map is Dictionary:
		museum_fish.clear()
		for fish_id: Variant in fish_map:
			museum_fish[str(fish_id)] = int(fish_map[fish_id])


func _apply_shop(data: Variant) -> void:
	if not data is Dictionary or not data.has("level"):
		return
	shop_level = int(data.get("level", shop_level))
	shop_points = int(data.get("points", shop_points))
	var next: Variant = data.get("next")
	shop_next = int(next) if next != null else -1


func _apply_clock(data: Variant) -> void:
	if not data is Dictionary:
		return
	_clock_game_ms = float(data.get("g", 0.0))
	_clock_scale = float(data.get("s", 1.0))
	_clock_server_ms = float(data.get("st", 0.0))
	_clock_world_ms = float(data.get("w", _clock_game_ms))
	_world_scale = float(data.get("ws", _clock_scale))
	_season_force = str(data.get("se", ""))


func _parse_npcs(entries: Variant) -> Array[NetNpcState]:
	var states: Array[NetNpcState] = []
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				var npc_state: NetNpcState = NetNpcState.from_dict(entry)
				npc_moods[npc_state.id] = npc_state.mood
				states.append(npc_state)
	return states


func _load_or_create_uid() -> String:
	var cfg: ConfigFile = _load_settings()
	var saved: String = str(cfg.get_value("settings", "uid", ""))
	if saved.length() >= 8:
		return saved
	var created: String = Crypto.new().generate_random_bytes(12).hex_encode()
	cfg.set_value("settings", "uid", created)
	cfg.save(_settings_path())
	return created


func _parse_states(entries: Variant) -> Array[NetPlayerState]:
	var states: Array[NetPlayerState] = []
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				states.append(NetPlayerState.from_dict(entry))
	return states


func _on_pong(msg: Dictionary) -> void:
	var now: float = Time.get_ticks_usec() / 1000.0
	var rtt: float = maxf(now - float(msg.get("c", now)), 0.0)
	var offset: float = float(msg.get("s", 0.0)) + rtt * 0.5 - now
	_clock_samples.append(Vector2(rtt, offset))
	if _clock_samples.size() > 8:
		_clock_samples.pop_front()
	# RTT가 가장 작은 표본이 가장 믿을 만하다.
	var best: Vector2 = _clock_samples[0]
	for sample: Vector2 in _clock_samples:
		if sample.x < best.x:
			best = sample
	_clock_offset_ms = best.y
	rtt_ms = rtt
	latency_updated.emit(rtt)


func _on_server_error(code: String, msg: Dictionary = {}) -> void:
	if code == NetProtocol.ERR_BAD_VERSION:
		# 서버가 알려 준 프로토콜 버전 (옛 서버는 msg 글에만 "server protocol N").
		server_version = int(msg.get("server_v", str(msg.get("msg", "")).get_slice("protocol ", 1).to_int()))
	if code == NetProtocol.ERR_RATE_LIMITED:
		push_warning("Net: 서버가 요청 속도 제한을 알림")
		return
	if _intent == Intent.RESUME:
		# 서버가 재시작되어 세션이 사라졌어도 방 코드와 내 uid로 자리를 되찾을 수 있다(방은 파일에 저장되어 있다).
		if code == NetProtocol.ERR_RESUME_FAILED and not room_code.is_empty() and not _join_fallback_tried:
			_join_fallback_tried = true
			_intent = Intent.JOIN
			_token = ""
			_send({"t": "join", "v": NetProtocol.VERSION, "uid": uid, "code": room_code})
			return
		_give_up(code)
		return
	if state == State.ONLINE:
		# 방에 들어온 뒤의 에러는 낚시·인벤토리·나무·대화 요청 거부다.
		var rid: String = str(msg.get("rid")) if msg.get("rid") != null else ""
		var kind: String = _pending.get(rid, "")
		_pending.erase(rid)
		if not kind.is_empty():
			request_failed.emit(kind, code)
		if (not rid.is_empty() and kind in ["", "fish_cast"]) or code in [NetProtocol.ERR_NOT_AT_SPOT, NetProtocol.ERR_INVENTORY_FULL, NetProtocol.ERR_ALREADY_FISHING, NetProtocol.ERR_NOT_FISHING, NetProtocol.ERR_BAD_ITEM, NetProtocol.ERR_NO_TOOL, NetProtocol.ERR_BAD_CAST]:
			action_rejected.emit(code)
		return
	_close_socket(1000, "error")
	_forget_session()
	_set_state(State.DISCONNECTED)
	error_received.emit(code)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(int(new_state))


func _settings_path() -> String:
	return "%s.cfg" % SETTINGS_BASE if profile_slot == 1 else "%s_%d.cfg" % [SETTINGS_BASE, profile_slot]


## 실행 인자 `--profile=N`이 있으면 그 슬롯, 없으면 다른 인스턴스가 쓰고 있지 않은 가장 작은 슬롯을 잡는다.
## (슬롯마다 uid가 달라서, 한 PC의 두 인스턴스가 같은 사람으로 취급되어 서로 쫓아내는 일을 막는다.)
func _claim_profile_slot() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			return clampi(int(arg.trim_prefix("--profile=")), 1, 99)
	var me: int = OS.get_process_id()
	for slot: int in range(1, MAX_LOCAL_INSTANCES + 1):
		var lock_path: String = "%s_slot_%d.pid" % [SETTINGS_BASE, slot]
		var owner: int = int(FileAccess.get_file_as_string(lock_path)) if FileAccess.file_exists(lock_path) else 0
		if owner == 0 or owner == me or not OS.is_process_running(owner):
			var f: FileAccess = FileAccess.open(lock_path, FileAccess.WRITE)
			if f != null:
				f.store_string(str(me))
			return slot
	return 1


func _load_settings() -> ConfigFile:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(_settings_path())
	return cfg


func _save_server_url(url: String) -> void:
	var cfg: ConfigFile = _load_settings()
	cfg.set_value("settings", "server_url", url)
	cfg.save(_settings_path())


func _save_last_room(code: String) -> void:
	if code.is_empty():
		return
	var cfg: ConfigFile = _load_settings()
	cfg.set_value("settings", "room_code", code)
	cfg.save(_settings_path())


func _save_session() -> void:
	var cfg: ConfigFile = _load_settings()
	cfg.set_value("session", "url", server_url)
	cfg.set_value("session", "code", room_code)
	cfg.set_value("session", "token", _token)
	cfg.save(_settings_path())


func _forget_session() -> void:
	_token = ""
	_intent = Intent.NONE
	my_id = 0
	partner_present = false
	partner_online = false
	var cfg: ConfigFile = _load_settings()
	if cfg.has_section("session"):
		cfg.erase_section("session")
		cfg.save(_settings_path())


func _set_vehicle_hp(msg: Dictionary) -> void:
	var v: Dictionary = vehicle(str(msg.get("v", "")))
	if not v.is_empty():
		v["hp"] = int(msg.get("hp", 0))
		v["max"] = int(msg.get("max", 1))


## v0.26 탈것으로 크리처를 들이받았다 (빠르기 m/s · 진행 방향) · 벽에 세게 부딪쳤다 (갑자기 줄어든 빠르기 m/s).
func ram(creature_id: String, speed: float, heading: Vector3) -> void:
	if state == State.ONLINE:
		_request("ram", {"c": creature_id, "s": snappedf(speed, 0.01), "dx": snappedf(heading.x, 0.01), "dz": snappedf(heading.z, 0.01)})


func vehicle_crash(drop: float) -> void:
	if state == State.ONLINE:
		_request("veh_crash", {"s": snappedf(drop, 0.01)})


## 탈것 배터리 (0~1, 배터리가 없는 탈것이면 -1).
func vehicle_battery(id: String) -> float:
	var v: Dictionary = vehicle(id)
	var cmax: float = float(v.get("cmax", 0))
	if cmax <= 0.0:
		var m: VehicleCatalog.Model = GameData.garage.model(str(v.get("model", "")))
		cmax = m.range if m != null else 0.0
	if cmax <= 0.0:
		return -1.0
	return clampf(float(v.get("charge", cmax)) / cmax, 0.0, 1.0)


## 탈것 내구도 (없으면 가득 = 1.0).
func vehicle_health(id: String) -> float:
	var v: Dictionary = vehicle(id)
	return float(v.get("hp", 1)) / maxf(1.0, float(v.get("max", 1))) if v.has("hp") else 1.0


## v19 내 차고 탈것 하나 (차고에 없으면 빈 사전).
func vehicle(id: String) -> Dictionary:
	for v: Dictionary in vehicles:
		if str(v.get("id", "")) == id:
			return v
	return {}


func _apply_aqua(list: Variant) -> void:
	aqua_trips.clear()
	if list is Array:
		for e: Variant in list:
			if e is Dictionary:
				aqua_trips.append(e)
	aqua_changed.emit()


## 내가 탄 물놀이 배 (없으면 빈 사전).
func my_aqua_trip() -> Dictionary:
	return aqua_trip_of(my_id)


## 그 사람이 탄 물놀이 배 (없으면 빈 사전).
func aqua_trip_of(player_id: int) -> Dictionary:
	for trip: Dictionary in aqua_trips:
		for r: Variant in trip.get("riders", []):
			if r is Dictionary and int(r.get("id", -1)) == player_id:
				return trip
	return {}


func _apply_parked(list: Variant) -> void:
	parked.clear()
	if list is Array:
		for e: Variant in list:
			if e is Dictionary:
				parked.append(e)
	parked_changed.emit()


## v19.1 세워 둔 그 탈것 (없으면 빈 사전).
func parked_of(vehicle_id: String, owner: int = -1) -> Dictionary:
	for e: Dictionary in parked:
		if str(e.get("v", "")) == vehicle_id and int(e.get("o", 0)) == (my_id if owner < 0 else owner):
			return e
	return {}
