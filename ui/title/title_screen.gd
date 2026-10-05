class_name TitleScreen
extends Node
## 첫 화면: 비행기를 타고 섬 위를 천천히 도는 듯한 시점(조금 높이서 비스듬히 내려다보며, 구름이 스쳐 가고 기체가 살짝 기운다) 위에 로고와 시작 버튼. 서버 주소와 마지막 방 코드는 기억해 두었다가
## "시작하기" 한 번으로 바로 들어간다 (저장된 세션 → 이어하기, 없으면 마지막 방 코드로 참가, 그것도 없으면 새 마을).
## 접속이 실패하면 마을 화면의 방 패널(RoomPanel)이 오류와 입력 칸을 보여 준다.
## 실행 인자(--server, --create, --join, --resume)가 있으면 첫 화면을 건너뛴다 (테스트·개발용).

@export var village_scene: PackedScene
@export_group("Camera")
## 비행기 시점: 섬 가운데를 크게 돌며 조금 높이서 비스듬히 내려다본다.
@export var orbit_center: Vector3 = Vector3(10.0, 0.0, 6.0)
@export_range(4.0, 200.0, 0.5, "suffix:m") var orbit_radius: float = 82.0
@export_range(1.0, 120.0, 0.5, "suffix:m") var orbit_height: float = 44.0
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

var _village: Node = null
var _hud: CanvasLayer = null
var _camera: Camera3D = null
var _angle: float = 0.6
var _started: bool = false
var _time: float = 0.0
var _clouds: Array[Node3D] = []


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
	# 화질 고르기 (절약 · 고화질).
	var quality: QualityWindow = QualityWindow.attach(_overlay)
	var quality_button: Button = QualityWindow.make_button(quality, 32)
	_start_button.get_parent().add_child(quality_button)
	_place_camera()
	Audio.play_music(Audio.MUSIC_TITLE)


func _process(delta: float) -> void:
	if _started:
		return
	_time += delta
	_angle += orbit_speed * delta
	_place_camera()
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
