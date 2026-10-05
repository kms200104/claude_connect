class_name RoomPanel
extends Control
## 방 코드로 접속하는 작은 패널. 접속하면 한 줄 상태 표시로 접힌다.
## 테스트용 실행 인자: `-- --server=ws://host:8080 --create` 또는 `-- --join=ABC123 [--resume]`

@export var top_margin: float = 60.0

@onready var _card: PanelContainer = %Card
@onready var _form: VBoxContainer = %Form
@onready var _server_edit: LineEdit = %ServerEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _create_button: Button = %CreateButton
@onready var _join_button: Button = %JoinButton
@onready var _resume_button: Button = %ResumeButton
@onready var _leave_button: Button = %LeaveButton
@onready var _status: Label = %StatusLabel

var _last_error: String = ""
## 진짜 서버에 연결하지 못하면 보이는 "테스트 서버로 하기" (v0.10).
var _test_button: Button = null
var _reconnect_started_ms: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.offset_top = top_margin
	_server_edit.text = Net.last_server_url()
	_code_edit.max_length = NetProtocol.ROOM_CODE_LENGTH
	_code_edit.text_changed.connect(_on_code_changed)
	_create_button.pressed.connect(_on_create_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	_leave_button.pressed.connect(Net.leave)
	_test_button = Button.new()
	_test_button.name = "TestServerButton"
	_test_button.text = "연결이 안 되면: 테스트 서버로 하기"
	_test_button.focus_mode = Control.FOCUS_NONE
	_test_button.custom_minimum_size = _resume_button.custom_minimum_size
	_test_button.add_theme_font_size_override("font_size", _resume_button.get_theme_font_size("font_size"))
	_test_button.pressed.connect(func() -> void:
		_last_error = ""
		_server_edit.text = Net.TEST_SERVER_URL
		Net.play_on_test_server())
	_form.add_child(_test_button)
	# 방 정보 줄에 화질 단추 (창은 HUD 맨 위에 붙인다).
	var quality: QualityWindow = QualityWindow.attach(get_parent() if get_parent() != null else self)
	var quality_button: Button = QualityWindow.make_button(quality, 26)
	quality_button.name = "QualityButton"
	_leave_button.get_parent().add_child(quality_button)
	_leave_button.get_parent().move_child(quality_button, _leave_button.get_index())
	Net.state_changed.connect(_on_state_changed)
	Net.error_received.connect(_on_error)
	Net.session_lost.connect(_on_session_lost)
	Net.connection_lost.connect(func() -> void: _reconnect_started_ms = Time.get_ticks_msec())
	_resume_button.visible = Net.has_saved_session()
	_refresh()
	_apply_command_line()


func _process(_delta: float) -> void:
	if Net.state == Net.State.ONLINE or Net.state == Net.State.RECONNECTING:
		_refresh_status()


func _apply_command_line() -> void:
	var url: String = ""
	var create: bool = false
	var join: String = ""
	var resume: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			url = arg.trim_prefix("--server=")
		elif arg == "--create":
			create = true
		elif arg.begins_with("--join="):
			join = arg.trim_prefix("--join=")
		elif arg == "--resume":
			resume = true
	if not url.is_empty():
		_server_edit.text = url
	if resume:
		Net.resume_saved_session()
	elif create:
		Net.create_room(_server_edit.text)
	elif not join.is_empty():
		Net.join_room(_server_edit.text, join)


func _on_code_changed(text: String) -> void:
	var column: int = _code_edit.caret_column
	_code_edit.text = text.to_upper()
	_code_edit.caret_column = column


func _on_create_pressed() -> void:
	_last_error = ""
	Net.create_room(_server_edit.text)


func _on_join_pressed() -> void:
	_last_error = ""
	Net.join_room(_server_edit.text, _code_edit.text)


func _on_resume_pressed() -> void:
	_last_error = ""
	Net.resume_saved_session()


func _on_state_changed(_new_state: int) -> void:
	_refresh()


func _on_error(code: String) -> void:
	_last_error = _describe_error(code)
	_resume_button.visible = Net.has_saved_session()
	_refresh()


func _on_session_lost(reason: String) -> void:
	_last_error = "세션이 끝났어요 (%s)" % _describe_error(reason)
	_resume_button.visible = false
	_refresh()


func _describe_error(code: String) -> String:
	match code:
		NetProtocol.ERR_ROOM_NOT_FOUND:
			return "그 코드의 방이 없어요"
		NetProtocol.ERR_ROOM_FULL:
			return "방이 가득 찼어요"
		NetProtocol.ERR_BAD_VERSION:
			# 어느 쪽이 옛날 것인지까지 알려 준다: 앱이 낮으면 앱을 새로 설치, 서버가 낮으면 서버 폴더에서 git pull 뒤 다시 켜기.
			var server_v: int = Net.server_version
			if server_v <= 0:
				return "앱 버전(v%d)이 서버와 달라요" % NetProtocol.VERSION
			if server_v > NetProtocol.VERSION:
				return "앱이 옛날 버전이에요 (앱 v%d · 서버 v%d) — 최신 코드로 앱을 다시 설치하세요" % [NetProtocol.VERSION, server_v]
			return "서버가 옛날 버전이에요 (앱 v%d · 서버 v%d) — 서버 폴더에서 git pull 뒤 다시 켜세요" % [NetProtocol.VERSION, server_v]
		NetProtocol.ERR_CONNECT_FAILED:
			return "서버에 연결하지 못했어요 — 아래 '테스트 서버로 하기'로 서버 없이 해 볼 수 있어요"
		NetProtocol.ERR_RESUME_FAILED, NetProtocol.ERR_RECONNECT_TIMEOUT:
			return "자리를 되찾지 못했어요"
		"replaced":
			return "다른 곳에서 같은 자리로 접속했어요"
		_:
			return code


func _refresh() -> void:
	var offline: bool = Net.state == Net.State.DISCONNECTED
	var busy: bool = Net.state == Net.State.CONNECTING or Net.state == Net.State.JOINING
	_form.visible = offline or busy
	_create_button.disabled = busy
	_join_button.disabled = busy
	_leave_button.visible = Net.state == Net.State.ONLINE or Net.state == Net.State.RECONNECTING
	if _test_button != null:
		_test_button.visible = offline and not _last_error.is_empty()
		_test_button.disabled = busy
	_refresh_status()


func _refresh_status() -> void:
	match Net.state:
		Net.State.DISCONNECTED:
			_status.text = _last_error if not _last_error.is_empty() else "방을 만들거나 코드로 참가하세요"
		Net.State.CONNECTING, Net.State.JOINING:
			_status.text = "접속 중…"
		Net.State.ONLINE:
			var partner: String = "상대 대기 중"
			if Net.partner_present:
				partner = "상대 접속 중" if Net.partner_online else "상대 연결 끊김"
			_status.text = "방 코드 %s · %s · %d ms" % [Net.room_code, partner, int(Net.rtt_ms)]
			if Net.is_test_server():
				_status.text = "테스트 서버 (앱 안, 혼자) · 방 %s" % Net.room_code
		Net.State.RECONNECTING:
			var secs: int = int((Time.get_ticks_msec() - _reconnect_started_ms) / 1000.0)
			_status.text = "연결이 끊겼어요 — 다시 연결하는 중… %d초" % secs
