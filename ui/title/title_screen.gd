class_name TitleScreen
extends Node
## 첫 화면: 비행기를 타고 섬 위를 천천히 도는 듯한 시점(조금 높이서 비스듬히 내려다보며, 구름이 스쳐 가고 기체가 살짝 기운다) 위에 로고와 시작 버튼. 서버 주소와 마지막 방 코드는 기억해 두었다가
## "시작하기" 한 번으로 바로 들어간다 (저장된 세션 → 이어하기, 없으면 마지막 방 코드로 참가, 그것도 없으면 새 마을).
## 접속이 실패하면 마을 화면의 방 패널(RoomPanel)이 오류와 입력 칸을 보여 준다.
## 실행 인자(--server, --create, --join, --resume)가 있으면 첫 화면을 건너뛴다 (테스트·개발용).

## 에디터 실행 때 class_name 이 모두 등록됐는지 확인하는 게임 스크립트 폴더 (broken_scripts).
const SCRIPT_DIRS: PackedStringArray = ["res://autoload", "res://core", "res://game", "res://ui"]

@export var village_scene: PackedScene
@export_group("Camera")
## 비행기 시점: 섬 바깥 물가를 크게 돌며 낮게 날아 섬과 하늘이 같이 보이게 비스듬히 본다.
@export var orbit_center: Vector3 = Vector3(10.0, 0.0, 6.0)
@export_range(4.0, 200.0, 0.5, "suffix:m") var orbit_radius: float = 104.0
@export_range(1.0, 120.0, 0.5, "suffix:m") var orbit_height: float = 24.0
@export_range(0.0, 1.0, 0.005, "suffix:rad/s") var orbit_speed: float = 0.022
## 기체가 좌우로 살짝 기우는 정도 (rad).
@export_range(0.0, 0.3, 0.005) var bank_amount: float = 0.045
@export_range(0, 40) var cloud_count: int = 14

@onready var _overlay: CanvasLayer = %Overlay
@onready var _logo: TextureRect = %Logo
@onready var _start_button: Button = %StartButton
@onready var _start_detail: Label = %StartDetail
@onready var _create_button: Button = %CreateButton
@onready var _join_toggle: Button = %JoinToggle
@onready var _code_row: HBoxContainer = %CodeRow
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _code_go: Button = %CodeGo
@onready var _server_edit: LineEdit = %ServerEdit
@onready var _subtitle: Label = $Overlay/Root/Subtitle
@onready var _card: PanelContainer = $Overlay/Root/Card

var _village: Node = null
var _hud: CanvasLayer = null
var _camera: Camera3D = null
var _angle: float = 0.6
var _started: bool = false
var _time: float = 0.0
var _clouds: Array[Node3D] = []
## 글자판 때문에 카드를 올린 만큼 (방 코드 · 서버 주소 칸).
var _lift: float = 0.0


func _ready() -> void:
	_village = village_scene.instantiate()
	add_child(_village)
	move_child(_village, 0)
	_hud = _village.get_node("HUD")
	if _has_launch_args():
		_hud.visible = true
		_overlay.queue_free()
		_started = true
		return
	_hud.visible = false
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.far = 900.0
	_village.add_child(_camera)
	_camera.current = true
	_build_clouds()
	_server_edit.text = Net.last_server_url()
	_code_edit.max_length = NetProtocol.ROOM_CODE_LENGTH
	_code_edit.text = Net.last_room_code()
	_code_edit.text_changed.connect(func(text: String) -> void:
		var column: int = _code_edit.caret_column
		_code_edit.text = text.to_upper()
		_code_edit.caret_column = column
		_refresh_start_label())
	_start_button.pressed.connect(_on_start)
	_create_button.pressed.connect(func() -> void: _enter(func() -> void: Net.create_room(_server_url())))
	_join_toggle.pressed.connect(func() -> void:
		_code_row.visible = not _code_row.visible
		if _code_row.visible:
			_code_edit.grab_focus())
	_code_go.pressed.connect(func() -> void:
		if _code_edit.text.strip_edges().length() == NetProtocol.ROOM_CODE_LENGTH:
			_enter(func() -> void: Net.join_room(_server_url(), _code_edit.text)))
	_refresh_start_label()
	# 설정: 닉네임 · 화질 고르기 (절약 · 고화질).
	var quality: QualityWindow = QualityWindow.attach(_overlay)
	var quality_button: Button = QualityWindow.make_button(quality, 32)
	_start_button.get_parent().add_child(quality_button)
	# 서버 없이 해 보기 (v0.10): 앱 안 테스트 서버로 들어간다 (안드로이드 기기 하나로 테스트할 때).
	var test_button: Button = Button.new()
	test_button.name = "TestServerButton"
	test_button.text = "서버 없이 테스트하기"
	test_button.focus_mode = Control.FOCUS_NONE
	test_button.add_theme_font_size_override("font_size", 28)
	test_button.pressed.connect(func() -> void: _enter(Net.play_on_test_server))
	_start_button.get_parent().add_child(test_button)
	_place_camera()
	_warn_if_broken()
	# 가로 화면 (v0.13.4): 로고는 왼쪽, 카드는 오른쪽.
	ScreenFit.changed.connect(func(_wide: bool) -> void: _fit())
	_fit()
	Audio.play_music(Audio.MUSIC_TITLE)


## 세로: 로고 위 · 카드 아래 (장면 그대로). 가로: 로고 왼쪽 가운데 · 카드 오른쪽 가운데.
func _fit() -> void:
	if _logo == null or _card == null:
		return
	if ScreenFit.landscape:
		for c: Control in [_logo, _subtitle]:
			c.anchor_left = 0.27
			c.anchor_right = 0.27
		_logo.offset_left = -420.0
		_logo.offset_right = 420.0
		_logo.offset_top = 170.0
		_logo.offset_bottom = 170.0 + 476.0
		_subtitle.offset_top = 660.0
		_subtitle.offset_bottom = 724.0
		_card.anchor_left = 0.5
		_card.anchor_top = 0.5
		_card.anchor_right = 1.0
		_card.anchor_bottom = 0.5
		_card.offset_left = 40.0
		_card.offset_right = -70.0
		_card.offset_top = -330.0 - _lift
		_card.offset_bottom = 330.0 - _lift
		_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		for c: Control in [_logo, _subtitle]:
			c.anchor_left = 0.5
			c.anchor_right = 0.5
		_logo.offset_left = -450.0
		_logo.offset_right = 450.0
		_logo.offset_top = 150.0
		_logo.offset_bottom = 659.0
		_subtitle.offset_top = 676.0
		_subtitle.offset_bottom = 740.0
		_card.anchor_left = 0.0
		_card.anchor_top = 1.0
		_card.anchor_right = 1.0
		_card.anchor_bottom = 1.0
		_card.offset_left = 70.0
		_card.offset_right = -70.0
		_card.offset_top = -760.0 - _lift
		_card.offset_bottom = -120.0 - _lift
		_card.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _process(delta: float) -> void:
	if _started:
		return
	_time += delta
	_angle += orbit_speed * delta
	_place_camera()
	var want: float = KeyboardLift.lift_for(_card, _lift)
	if absf(want - _lift) > 1.0:
		_lift = want
		_fit()
	if _logo != null:
		# 로고가 둥실둥실.
		_logo.pivot_offset = _logo.size * 0.5
		_logo.rotation = sin(_time * 1.3) * 0.015
		_logo.scale = Vector2.ONE * (1.0 + sin(_time * 2.0) * 0.012)


func _place_camera() -> void:
	if _camera == null:
		return
	# 높이가 천천히 오르내리고, 도는 쪽으로 살짝 기운다 (비행기 창밖처럼).
	var height: float = orbit_height + sin(_time * 0.21) * 3.0
	var at: Vector3 = orbit_center + Vector3(cos(_angle), 0.0, sin(_angle)) * orbit_radius + Vector3(0.0, height, 0.0)
	var ahead: Vector3 = orbit_center + Vector3(cos(_angle + 0.35), 0.0, sin(_angle + 0.35)) * orbit_radius * 0.22
	_camera.look_at_from_position(at, ahead)
	_camera.rotate_object_local(Vector3.FORWARD, -bank_amount + sin(_time * 0.37) * bank_amount * 0.4)
	for i: int in _clouds.size():
		var c: Node3D = _clouds[i]
		# 구름은 바람 따라 천천히 흘러가다 섬 반대편에서 다시 나온다.
		c.position.x += (0.9 + 0.25 * float(i % 3)) * get_process_delta_time()
		if c.position.x > orbit_center.x + 130.0:
			c.position.x -= 260.0


## 카메라 높이 아래위로 흩어진 뭉게구름 (흰 공 몇 개를 겹쳐 만든 반투명 덩어리).
func _build_clouds() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in cloud_count:
		var st: SurfaceTool = ClayMesh.begin()
		var puffs: int = rng.randi_range(4, 7)
		for k: int in puffs:
			var r: float = rng.randf_range(3.0, 6.0)
			ClayMesh.add_ellipsoid(st, Vector3(rng.randf_range(-7.0, 7.0), rng.randf_range(-0.5, 1.5), rng.randf_range(-4.0, 4.0)), Vector3(r, r * 0.55, r * 0.8), Color.WHITE, 10, 6)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = ClayMesh.commit(st)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "TitleCloud%d" % i
		_village.add_child(mi)
		var a: float = rng.randf() * TAU
		var dist: float = rng.randf_range(40.0, 125.0)
		mi.position = orbit_center + Vector3(cos(a) * dist, rng.randf_range(24.0, 40.0), sin(a) * dist)
		_clouds.append(mi)


## 시작하기: 이어할 세션 → 마지막 방 → 새 마을 순서.
func _on_start() -> void:
	var url: String = _server_url()
	var saved: String = Net.saved_session_code()
	if Net.has_saved_session() and Net.saved_session_url() == url:
		_enter(func() -> void: Net.resume_saved_session())
	elif not _code_edit.text.strip_edges().is_empty() and _code_edit.text.strip_edges().length() == NetProtocol.ROOM_CODE_LENGTH:
		_enter(func() -> void: Net.join_room(url, _code_edit.text))
	elif not saved.is_empty():
		_enter(func() -> void: Net.join_room(url, saved))
	else:
		_enter(func() -> void: Net.create_room(url))


## 게임 데이터(GameData)를 못 읽었으면 (git pull 로 새 스크립트가 생겼는데 Godot 에디터가 아직 등록하지 않은 경우가 대부분)
## 들어가 봐야 땅만 있고 움직이지 못하므로, 카드에 고치는 법을 띄우고 들어가기 단추를 막는다.
func _warn_if_broken() -> void:
	var broken: PackedStringArray = broken_scripts()
	if scripts_broken():
		broken.insert(0, "res://autoload/game_data/game_data.gd")
	if broken.is_empty():
		return
	push_error("스크립트를 불러오지 못했어요 (%s). Godot 에디터에서 프로젝트 → 현재 프로젝트 새로고침 뒤 다시 실행하세요." % ", ".join(broken))
	var warn: Label = Label.new()
	warn.name = "ScriptsBroken"
	warn.text = "게임 스크립트를 불러오지 못했어요 (%s).\n새로 받은 파일이 Godot 에디터에 아직 등록되지 않았어요.\n에디터 메뉴 [프로젝트 → 현재 프로젝트 새로고침] 뒤 다시 실행해 주세요." % broken[0].get_file()
	warn.add_theme_font_size_override("font_size", 26)
	warn.add_theme_color_override("font_color", Color("#D9483B"))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_button.get_parent().add_child(warn)
	_start_button.get_parent().move_child(warn, 0)
	for b: Button in [_start_button, _create_button, _join_toggle, _code_go]:
		b.disabled = true
	var test_button: Button = _start_button.get_parent().get_node_or_null("TestServerButton") as Button
	if test_button != null:
		test_button.disabled = true


## 게임 데이터 자동 로드가 스크립트 없이 떠 있는지 (스크립트 컴파일 실패).
func scripts_broken() -> bool:
	var data: Node = get_node_or_null(^"/root/GameData")
	return data == null or data.get_script() == null or not ("items" in data)


## 에디터에 아직 등록되지 않은 class_name 스크립트 경로들. GameData 가 멀쩡해도 새 class_name 이 등록되지 않으면
## 그 이름을 쓰는 스크립트만 조용히 빠진다 (탈것이 안 오고 선착장이 안 보이는 식). 컴파일은 느리므로 파일 머리의
## class_name 만 읽어 전역 클래스 목록과 견준다. 내보낸 게임은 등록이 빌드에 굳어 있어 건너뛴다.
static func broken_scripts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not OS.has_feature("editor"):
		return out
	var known: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		known[str(entry.get("class", ""))] = true
	var todo: PackedStringArray = PackedStringArray(SCRIPT_DIRS)
	while not todo.is_empty():
		var dir: String = todo[todo.size() - 1]
		todo.remove_at(todo.size() - 1)
		for sub: String in DirAccess.get_directories_at(dir):
			todo.append(dir.path_join(sub))
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var path: String = dir.path_join(file)
			var declared: String = _declared_class(path)
			if not declared.is_empty() and not known.has(declared):
				out.append(path)
	return out


## 스크립트 머리(첫 몇 줄)에 적힌 class_name. 없으면 빈 문자열.
static func _declared_class(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	for i: int in 4:
		if f.eof_reached():
			break
		var line: String = f.get_line().strip_edges()
		if line.begins_with("class_name "):
			return line.substr(11).get_slice(" ", 0).strip_edges()
	return ""


func _refresh_start_label() -> void:
	var code: String = Net.saved_session_code() if Net.has_saved_session() else _code_edit.text.strip_edges()
	if Net.has_saved_session():
		_start_detail.text = "방 %s 이어하기" % code
	elif code.length() == NetProtocol.ROOM_CODE_LENGTH:
		_start_detail.text = "방 %s 들어가기" % code
	else:
		_start_detail.text = "새 마을 만들기"


func _server_url() -> String:
	var url: String = _server_edit.text.strip_edges()
	return url if not url.is_empty() else Net.default_server_url


## 마을 화면으로: 첫 화면을 흐리게 지우고, 게임 카메라와 HUD 를 켠 뒤 접속을 시작한다.
func _enter(connect_action: Callable) -> void:
	if _started:
		return
	_started = true
	Audio.play_ui(Audio.SFX_CONFIRM)
	# 마을 음악(낮·밤·비·이벤트)은 들어가면 SoundDirector 가 고른다.
	var game_camera: Camera3D = _village.get_node("CameraRig/Camera3D")
	game_camera.current = true
	if _camera != null:
		_camera.queue_free()
		_camera = null
	for c: Node3D in _clouds:
		c.queue_free()
	_clouds.clear()
	_hud.visible = true
	connect_action.call()
	var fade: Tween = create_tween()
	fade.tween_property(_overlay.get_node("Root"), "modulate:a", 0.0, 0.45)
	fade.tween_callback(_overlay.queue_free)


static func _has_launch_args() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server=") or arg == "--create" or arg.begins_with("--join=") or arg == "--resume":
			return true
	return false
