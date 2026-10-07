class_name HomeFirstPerson
extends Node
## 집 안 1인칭 (v0.13.5): "1인칭" 버튼 → 캐릭터 눈높이에서 화면을 끌어 둘러보고, 조이스틱으로 걷는다. "돌아가기"로 평소 카메라로.
## 1인칭인 동안 창유리는 찍어 둔 사진 대신 실시간 창밖 풍경을 보여 준다: 마을의 그 집 자리(아파트 동 · 층 · 호)에
## 메인 카메라와 같은 방향 · 화각의 카메라를 하나 더 두고 (같은 월드를 함께 쓰는 SubViewport), 유리가 그 화면을 화면 좌표 그대로 읽는다.
## 집 안 좌표 → 마을 좌표: 평면도 남쪽 가운데(발코니) ↔ 그 집 발코니 앞, 평면도 방향 ↔ 동 방향. 집 안이 실제 동보다 커서
## 가로 거리는 view_depth_scale 만큼 줄여 옮긴다 (창 너머 시차만 맞으면 되고, 카메라가 이웃 동 안으로 들어가지 않게).
## 마을 쪽 카메라에는 자기 동이 보이지 않게 그 동 그림을 hidden_layer 에만 둔다 (마을 메인 카메라는 모든 층을 본다).

signal changed(on: bool)

## 눈 높이 (발 기준, m).
const EYE_HEIGHT: float = 1.45
## 위아래로 볼 수 있는 각도.
const PITCH_LIMIT: float = deg_to_rad(65.0)
## 자기 동을 감출 때 쓰는 렌더 층 (1~20 중 20번).
const HIDDEN_LAYER: int = 1 << 19

var player: Player = null
var camera_rig: FollowCamera = null
var interior: HomeInterior = null
var apartments: ApartmentSite = null
var joystick: TouchJoystick = null

## 끌기 감도 (화면 1px 당 rad).
var drag_turn: float = 0.0052
## 1인칭 화각.
var fov: float = 70.0
## 창밖 화면 해상도 (메인 화면 대비). 창은 화면의 일부라 조금 낮춰도 티가 나지 않는다.
var live_scale: float = 0.6
var view_depth_scale: float = 0.3

var active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _saved_fov: float = 55.0
var _saved_camera: Transform3D = Transform3D.IDENTITY
var _vp: SubViewport = null
var _live_cam: Camera3D = null
var _hidden: Array[VisualInstance3D] = []
var _hidden_layers: Array[int] = []
var _unit: String = ""
## 창 · 버튼 위에서 시작한 터치 (둘러보기에 쓰지 않는다).
var _ui_touches: Dictionary[int, bool] = {}


## 1인칭으로 (집 안에서만).
func enter() -> void:
	if active or player == null or camera_rig == null or not Home.is_inside():
		return
	active = true
	_unit = Home.unit
	var cam: Camera3D = camera_rig.camera
	_saved_fov = cam.fov
	_saved_camera = cam.transform
	camera_rig.set_physics_process(false)
	camera_rig.see_through_blocked = true
	_yaw = player.body.rotation.y if player.body != null else 0.0
	_pitch = deg_to_rad(-6.0)
	if player.body != null:
		player.body.visible = false
	_start_live_view()
	if interior != null:
		interior.set_first_person(true)
	_place_camera()
	changed.emit(true)


## 평소 카메라로.
func exit() -> void:
	if not active:
		return
	active = false
	_stop_live_view()
	if interior != null:
		interior.set_first_person(false)
	if player != null and player.body != null:
		player.body.visible = true
	if camera_rig != null:
		var cam: Camera3D = camera_rig.camera
		cam.transform = _saved_camera
		cam.fov = _saved_fov
		camera_rig.set_physics_process(true)
		camera_rig.see_through_blocked = false
		camera_rig.snap_to_target()
	changed.emit(false)


func toggle() -> void:
	if active:
		exit()
	else:
		enter()


func _process(_delta: float) -> void:
	if not active:
		return
	# 집을 나가거나 다른 집으로 옮겨지면 (현관 · 순간이동) 평소로.
	if not Home.is_inside() or Home.unit != _unit:
		exit()
		return
	# 집 안에 들어갈 때 창밖 사진을 찍는 HomeView 가 끝나며 땅 휘기를 다시 켜도, 1인칭 동안은 꺼 둔다.
	WorldStyle.curve_paused = true
	_place_camera()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_ui_touches[touch.index] = _over_ui(touch.position)
		else:
			_ui_touches.erase(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _ui_touches.get(drag.index, false) or (joystick != null and joystick.owns_touch(drag.index)):
			return
		_yaw -= drag.relative.x * drag_turn
		_pitch = clampf(_pitch - drag.relative.y * drag_turn, -PITCH_LIMIT, PITCH_LIMIT)
		# 같이 있는 친구에게도 캐릭터가 그쪽을 바라보는 것으로 보인다.
		player.look_toward(Vector3(-sin(_yaw), 0.0, -cos(_yaw)))


## 버튼 · 휴대폰 · 창 위인지 (조이스틱이 피하는 컨트롤들과 같다).
func _over_ui(pos: Vector2) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"blocks_joystick"):
		var control: Control = node as Control
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return true
	return false


func _place_camera() -> void:
	var cam: Camera3D = camera_rig.camera
	var eye: Vector3 = player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), eye)
	cam.fov = fov
	if _live_cam != null:
		# 자리만 줄여 옮기고(view_depth_scale), 보는 방향은 동 방향만큼 돌리기만 한다. 줄인 변환을 카메라 방향에까지 곱하면
		# 시야가 가로로 찌그러지고 위아래로 볼 때 기울어져 창밖이 "사진을 우겨넣은" 것처럼 보인다.
		var to_village: Transform3D = _to_village()
		_live_cam.global_transform = Transform3D(to_village.basis.orthonormalized() * cam.global_transform.basis, to_village * cam.global_transform.origin)
		_live_cam.fov = cam.fov
		var want: Vector2i = Vector2i((Vector2(get_viewport().get_visible_rect().size) * live_scale).round())
		if _vp.size != want:
			_vp.size = want


## 집 안 좌표 → 마을의 그 집 자리.
func _to_village() -> Transform3D:
	if Home.plan == null or apartments == null:
		return Transform3D.IDENTITY
	var anchor_in: Vector3 = Home.to_world(Vector2(Home.plan.size.x * 0.5, Home.plan.size.y))
	var basis: Basis = apartments.unit_basis(_unit)
	# unit_position 은 발코니 앞 (층 바닥 + 1m) — 바닥 높이로 맞춘다.
	var anchor_out: Vector3 = apartments.unit_position(_unit) - Vector3(0.0, 1.0, 0.0)
	var squash: Basis = Basis.from_scale(Vector3(view_depth_scale, 1.0, view_depth_scale))
	return Transform3D(basis, anchor_out) * Transform3D(squash, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -anchor_in)


func _start_live_view() -> void:
	if interior == null or apartments == null:
		return
	_vp = SubViewport.new()
	_vp.name = "WindowLiveView"
	_vp.world_3d = get_viewport().world_3d
	_vp.size = Vector2i((Vector2(get_viewport().get_visible_rect().size) * live_scale).round())
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_live_cam = Camera3D.new()
	_live_cam.near = 0.3
	# 섬(±100m) 너머 남쪽 바다 위에 있는 집 안들은 보이지 않게.
	_live_cam.far = 160.0
	_live_cam.cull_mask = 0xFFFFF & ~HIDDEN_LAYER
	_vp.add_child(_live_cam)
	add_child(_vp)
	_live_cam.current = true
	# 마을이 집 안 기준으로 휘면 멀리 있는 마을이 가라앉으므로 1인칭 동안은 땅 휘기를 끈다 (집 안은 작아 차이가 없다).
	WorldStyle.curve_paused = true
	_hidden = apartments.unit_tower_visuals(_unit)
	_hidden_layers.clear()
	for v: VisualInstance3D in _hidden:
		_hidden_layers.append(v.layers)
		v.layers = HIDDEN_LAYER
	interior.set_live_view(_vp.get_texture())


func _stop_live_view() -> void:
	if interior != null:
		interior.set_live_view(null)
	for i: int in _hidden.size():
		if is_instance_valid(_hidden[i]):
			_hidden[i].layers = _hidden_layers[i]
	_hidden.clear()
	_hidden_layers.clear()
	WorldStyle.curve_paused = false
	if _vp != null:
		_vp.queue_free()
	_vp = null
	_live_cam = null
