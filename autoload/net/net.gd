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

enum State { DISCONNECTED, CONNECTING, JOINING, ONLINE, RECONNECTING }

enum Intent { NONE, CREATE, JOIN, RESUME }

const SETTINGS_PATH: String = "user://net.cfg"

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


func _ready() -> void:
	server_url = last_server_url()
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
			_send({"t": "create", "v": NetProtocol.VERSION})
		Intent.JOIN:
			_send({"t": "join", "v": NetProtocol.VERSION, "code": room_code})
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
		"error":
			_on_server_error(str(msg.get("code", "")))


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
	_save_session()
	_set_state(State.ONLINE)
	if me != null:
		welcomed.emit(me, others, resumed)


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


func _on_server_error(code: String) -> void:
	if code == NetProtocol.ERR_RATE_LIMITED:
		push_warning("Net: 서버가 요청 속도 제한을 알림")
		return
	if _intent == Intent.RESUME:
		_give_up(code)
		return
	if state == State.ONLINE:
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


func _load_settings() -> ConfigFile:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return cfg


func _save_server_url(url: String) -> void:
	var cfg: ConfigFile = _load_settings()
	cfg.set_value("settings", "server_url", url)
	cfg.save(SETTINGS_PATH)


func _save_session() -> void:
	var cfg: ConfigFile = _load_settings()
	cfg.set_value("session", "url", server_url)
	cfg.set_value("session", "code", room_code)
	cfg.set_value("session", "token", _token)
	cfg.save(SETTINGS_PATH)


func _forget_session() -> void:
	_token = ""
	_intent = Intent.NONE
	my_id = 0
	partner_present = false
	partner_online = false
	var cfg: ConfigFile = _load_settings()
	if cfg.has_section("session"):
		cfg.erase_section("session")
		cfg.save(SETTINGS_PATH)
