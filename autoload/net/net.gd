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
signal weather_changed(weather: String)
## 번개 (뇌우일 때 서버가 방 전체에 같은 순간 보낸다). power 0.6~1.
signal lightning_struck(power: float)
signal tree_changed(tree_id: String, stage: String, chops: int)
signal npcs_received(server_time_ms: float, states: Array[NetNpcState])
## 내 도끼질 결과 (서버가 확정). 나무에서 얻은 아이템과 나무가 쓰러졌는지.
signal chop_succeeded(tree_id: String, item_id: String, felled: bool)
## 상대가 한 동작 (지금은 도끼질만). target = 나무 id.
signal peer_action(id: int, kind: String, target: String)
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
signal fish_started
signal fish_nibble
## 진짜 입질. 이 순간부터 `window_ms` 안에 챔질해야 한다.
signal fish_bite(window_ms: int)
## 서버가 확정한 낚시 결과. 성공이면 `fish_id`가 물고기 종류, 실패면 `reason`(NetProtocol.FISH_*).
signal fish_result(success: bool, fish_id: String, reason: String)
## 낚시·인벤토리 요청이 거부됨 (NetProtocol.ERR_*).
signal action_rejected(code: String)

enum State { DISCONNECTED, CONNECTING, JOINING, ONLINE, RECONNECTING }

enum Intent { NONE, CREATE, JOIN, RESUME }

const SETTINGS_BASE: String = "user://net"
const MAX_LOCAL_INSTANCES: int = 8

@export_group("Connection")
@export var default_server_url: String = "ws://127.0.0.1:8080"
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

var _ws: WebSocketPeer = null
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
var _pending: Dictionary[String, String] = {}  # rid → 요청 종류 (거부됐을 때 어떤 요청인지 알리려고)
var _clock_game_ms: float = 0.0
var _clock_scale: float = 1.0
var _clock_server_ms: float = 0.0


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
	_forget_session()
	_close_socket(1000, "leave")
	_set_state(State.DISCONNECTED)


func last_server_url() -> String:
	return str(_load_settings().get_value("settings", "server_url", default_server_url))


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
func cast_fishing(spot_id: String) -> void:
	_fishing_rid = _next_rid()
	_send({"t": "fish_cast", "rid": _fishing_rid, "spot": spot_id})


## 챔질 요청. `reaction_ms`는 입질 연출이 보인 뒤 버튼을 누르기까지 걸린 시간(없으면 0).
func hook_fishing(reaction_ms: float) -> void:
	if _fishing_rid.is_empty():
		return
	_send({"t": "fish_hook", "rid": _fishing_rid, "reaction": snappedf(reaction_ms, 0.1)})


func cancel_fishing() -> void:
	_send({"t": "fish_cancel"})


## 칸에 든 아이템 버리기(물고기는 놓아주기). 도구는 서버가 거부한다.
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


func sell_item(slot: int, count: int = 1) -> void:
	_request("shop_sell", {"slot": slot, "n": count})


func buy_item(item_id: String, count: int = 1) -> void:
	_request("shop_buy", {"item": item_id, "n": count})


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


func game_hour() -> float:
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
	_open_handled = false
	_connect_started_ms = Time.get_ticks_msec()
	var err: Error = _ws.connect_to_url(server_url)
	if err != OK:
		_ws = null
		_on_socket_closed(-1)


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
			_send({"t": "create", "v": NetProtocol.VERSION, "uid": uid})
		Intent.JOIN:
			_send({"t": "join", "v": NetProtocol.VERSION, "uid": uid, "code": room_code})
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
				peer_joined.emit(NetPlayerState.from_dict(joined_data))
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
		"weather":
			weather = str(msg.get("w", weather))
			weather_changed.emit(weather)
		"lightning":
			lightning_struck.emit(float(msg.get("power", 1.0)))
		"tree":
			var tree_id: String = str(msg.get("id", ""))
			tree_stages[tree_id] = str(msg.get("s", NetProtocol.TREE_GROWN))
			tree_changed.emit(tree_id, tree_stages[tree_id], int(msg.get("c", 0)))
		"npcs":
			npc_states = _parse_npcs(msg.get("n", []))
			npcs_received.emit(float(msg.get("st", 0.0)), npc_states)
		"act":
			peer_action.emit(int(msg.get("id", 0)), str(msg.get("kind", "")), str(msg.get("tree", "")))
		"chop_result":
			_pending.erase(str(msg.get("rid", "")))
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
			fish_started.emit()
		"fish_nibble":
			fish_nibble.emit()
		"fish_bite":
			fish_bite.emit(int(msg.get("windowMs", 600)))
		"fish_result":
			_fishing_rid = ""
			fish_result.emit(bool(msg.get("ok", false)), str(msg.get("fish", "")), str(msg.get("reason", "")))
		"error":
			_on_server_error(str(msg.get("code", "")), msg)


func _on_welcome(msg: Dictionary) -> void:
	var resumed: bool = bool(msg.get("resumed", false))
	my_id = int(msg.get("id", 0))
	_token = str(msg.get("token", ""))
	room_code = str(msg.get("code", room_code))
	_intent = Intent.NONE
	_attempt = 0
	var me: NetPlayerState = null
	var others: Array[NetPlayerState] = []
	for player_state: NetPlayerState in _parse_states(msg.get("players", [])):
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
	_apply_clock(msg.get("clock", {}))
	weather = str(msg.get("w", NetProtocol.WEATHER_CLEAR))
	tree_stages.clear()
	var tree_list: Variant = msg.get("trees", [])
	if tree_list is Array:
		for entry: Variant in tree_list:
			if entry is Dictionary:
				tree_stages[str(entry.get("id", ""))] = str(entry.get("s", NetProtocol.TREE_GROWN))
	npc_states = _parse_npcs(msg.get("npcs", []))
	_apply_shop(msg.get("shop", {}))
	placed.clear()
	var placed_list: Variant = msg.get("placed", [])
	if placed_list is Array:
		for entry: Variant in placed_list:
			if entry is Dictionary:
				var p: PlacedInfo = PlacedInfo.from_dict(entry)
				placed[p.id] = p
	_save_session()
	_set_state(State.ONLINE)
	if me != null:
		welcomed.emit(me, others, resumed)
	weather_changed.emit(weather)
	npcs_received.emit(float(msg.get("st", 0.0)), npc_states)


func _next_rid() -> String:
	_rid_counter += 1
	return "%s-%d" % [uid.left(6), _rid_counter]


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


func _apply_profile(data: Variant) -> void:
	if not data is Dictionary:
		return
	sol = int(data.get("sol", sol))
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
	profile_updated.emit()


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


func _parse_npcs(entries: Variant) -> Array[NetNpcState]:
	var states: Array[NetNpcState] = []
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				states.append(NetNpcState.from_dict(entry))
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
		if (not rid.is_empty() and kind in ["", "fish_cast"]) or code in [NetProtocol.ERR_NOT_AT_SPOT, NetProtocol.ERR_INVENTORY_FULL, NetProtocol.ERR_ALREADY_FISHING, NetProtocol.ERR_NOT_FISHING, NetProtocol.ERR_BAD_ITEM, NetProtocol.ERR_NO_TOOL]:
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
