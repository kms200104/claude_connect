class_name CharacterPreview
extends SubViewportContainer
## 가방 창 오른쪽의 내 캐릭터. 왼쪽에서 아이템 칸을 고르면 캐릭터가 몸·고개·눈을 돌려 그 칸을 바라본다.
##
## 고른 칸의 화면 위치를 미리보기 카메라의 광선으로 바꿔 캐릭터 앞 평면과 만나는 점을 찾는다. 칸이 미리보기 밖(왼쪽)에
## 있어도 같은 식이 통해서, 실제로 그 칸을 쳐다보는 각도가 나온다. 몸은 천천히, 눈은 먼저 움직인다.
## 창이 닫혀 있으면 SubViewport 를 그리지 않는다 (UPDATE_DISABLED).

@export_group("References")
@export var viewport: SubViewport
@export var camera: Camera3D
## 캐릭터를 돌리는 축 (기본 yaw = PI 로 카메라를 바라본다).
@export var pivot: Node3D
@export var rig: CharacterRig
@export var bubble: Label3D
## 메인 월드의 월드 커브 기준점(플레이어). 미리보기 무대를 그 자리에 두어야 셰이더가 캐릭터를 가라앉히지 않는다.
@export var follow: Node3D

@export_group("Look")
## 몸이 돌아가는 최대 각도.
@export_range(0.0, 90.0, 1.0, "suffix:°") var max_turn_degrees: float = 60.0
@export_range(0.0, 30.0, 1.0, "suffix:°") var max_tilt_degrees: float = 10.0
## 바라볼 각도 중 몸이 맡는 몫. 나머지는 눈동자가 채워서 "눈이 먼저, 몸이 따라" 보인다.
@export_range(0.1, 1.0, 0.05) var body_turn_share: float = 0.65
@export_range(0.5, 30.0, 0.5) var body_smoothing: float = 7.0
@export_range(0.5, 40.0, 0.5) var eye_smoothing: float = 18.0
## 시선 목표를 놓을 평면: 캐릭터 머리에서 카메라 쪽으로 이만큼 앞.
@export_range(0.1, 3.0, 0.05, "suffix:m") var look_plane_distance: float = 0.9
## 아무것도 고르지 않은 채 이 시간이 지나면 가끔 두리번거린다.
@export_range(0.5, 10.0, 0.5, "suffix:s") var idle_glance_after: float = 3.0

const HEAD_HEIGHT: float = 1.4
## 화면에 꼭 들어와야 하는 크기 (캐릭터 + 받침 + 머리 위 표시). 세로로 긴 칸이면 가로 폭에 맞춘다.
const FRAME_SIZE: Vector2 = Vector2(1.7, 2.5)
const FACING_YAW: float = PI

var look_active: bool = false
## 시선 목표 (무대 원점 기준. 무대는 플레이어를 따라 움직이므로 월드 좌표로 들고 있으면 어긋난다).
var look_target: Vector3 = Vector3.ZERO

var _target_yaw: float = FACING_YAW
var _target_tilt: float = 0.0
var _idle_time: float = 0.0
var _next_glance: float = 0.0
var _glance_yaw: float = 0.0
var _stage: Node3D = null


func _ready() -> void:
	stretch = true
	_stage = camera.get_parent() as Node3D
	set_open(false)
	if bubble != null:
		bubble.visible = false


## 창이 열려 있을 때만 그린다.
func set_open(open: bool) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	set_process(open)
	if open:
		clear_look()
		pivot.rotation = Vector3(0.0, FACING_YAW, 0.0)
		if rig != null and Net.state == Net.State.ONLINE:
			rig.set_held(Net.held_item_id())


## 이 컨트롤(아이템 칸)의 가운데를 바라본다. kind 에 따라 머리 위에 반응 표시를 띄운다.
func look_at_control(control: Control, item: ItemInfo = null) -> void:
	look_at_canvas_point(control.get_global_rect().get_center())
	if item != null:
		react(item)


func look_at_canvas_point(point: Vector2) -> void:
	_sync_stage()
	_fit_camera()
	var local: Vector2 = point - get_global_rect().position
	var to_vp: Vector2 = Vector2(viewport.size) / size if size.x > 0.0 and size.y > 0.0 else Vector2.ONE
	var vp_point: Vector2 = local * to_vp
	var origin: Vector3 = camera.project_ray_origin(vp_point)
	var dir: Vector3 = camera.project_ray_normal(vp_point)
	var head: Vector3 = _stage.global_position + Vector3(0.0, HEAD_HEIGHT, 0.0)
	var plane: Plane = Plane(Vector3.BACK, head + Vector3.BACK * look_plane_distance)
	var hit: Variant = plane.intersects_ray(origin, dir)
	var world_target: Vector3 = (hit as Vector3) if hit != null else head + Vector3.BACK
	look_target = world_target - _stage.global_position
	look_active = true
	_idle_time = 0.0
	_aim_at(look_target)


func clear_look() -> void:
	look_active = false
	_target_yaw = FACING_YAW
	_target_tilt = 0.0
	_idle_time = 0.0


## 몸이 정면에서 얼마나 돌아가 있는지 (라디안, 음수 = 화면 왼쪽을 봄).
func yaw_offset() -> float:
	return wrapf(pivot.rotation.y - FACING_YAW, -PI, PI)


## 아이템 종류별 짧은 반응: 살짝 뛰어오르고 머리 위에 표시.
func react(item: ItemInfo) -> void:
	var t: Tween = create_tween()
	t.tween_property(pivot, "position:y", 0.12, 0.1).set_ease(Tween.EASE_OUT)
	t.tween_property(pivot, "position:y", 0.0, 0.16).set_ease(Tween.EASE_IN)
	if bubble == null:
		return
	match item.kind:
		ItemInfo.KIND_FISH:
			bubble.text = "!" if item.rarity != "rare" else "!!"
		ItemInfo.KIND_TOOL:
			bubble.text = "✓"
		_:
			bubble.text = "♪"
	bubble.visible = true
	bubble.scale = Vector3.ONE * 0.6
	var b: Tween = create_tween()
	b.tween_property(bubble, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.tween_interval(1.0)
	b.tween_callback(func() -> void: bubble.visible = false)


func _process(delta: float) -> void:
	_sync_stage()
	_fit_camera()
	if not look_active:
		_idle_glance(delta)
	pivot.rotation.y = lerp_angle(pivot.rotation.y, _target_yaw + (0.0 if look_active else _glance_yaw), 1.0 - exp(-body_smoothing * delta))
	pivot.rotation.x = lerpf(pivot.rotation.x, _target_tilt, 1.0 - exp(-body_smoothing * delta))
	if rig != null:
		var goal: Vector2 = _eye_goal() if look_active else Vector2(_glance_yaw * -1.5, 0.0)
		rig.set_eye_offset(rig.get_eye_offset().lerp(goal, 1.0 - exp(-eye_smoothing * delta)))


## 미리보기 칸의 비율에 맞춰 카메라 화각을 정한다 (Camera3D 의 fov 는 세로 기준).
func _fit_camera() -> void:
	if size.y <= 0.0:
		return
	var aspect: float = size.x / size.y
	var vertical: float = maxf(FRAME_SIZE.y, FRAME_SIZE.x / maxf(aspect, 0.1))
	var distance: float = camera.position.z
	camera.fov = rad_to_deg(2.0 * atan(vertical * 0.5 / distance))


func _sync_stage() -> void:
	if follow != null and _stage != null:
		_stage.global_position = follow.global_position


## target: 무대 원점 기준.
func _aim_at(target: Vector3) -> void:
	var d: Vector3 = target - Vector3(0.0, HEAD_HEIGHT, 0.0)
	var yaw: float = atan2(-d.x, -d.z)
	var limit: float = deg_to_rad(max_turn_degrees)
	_target_yaw = FACING_YAW + clampf(wrapf(yaw - FACING_YAW, -PI, PI) * body_turn_share, -limit, limit)
	var flat: float = Vector2(d.x, d.z).length()
	var tilt_limit: float = deg_to_rad(max_tilt_degrees)
	# 아래를 보면 앞으로 숙인다 (-X 회전이 앞으로 숙이는 방향).
	_target_tilt = clampf(atan2(d.y, maxf(flat, 0.01)), -tilt_limit, tilt_limit)


## 몸이 다 못 돌아간 만큼을 눈이 채운다.
func _eye_goal() -> Vector2:
	if rig == null or rig.visual == null:
		return Vector2.ZERO
	var local: Vector3 = rig.visual.global_transform.affine_inverse() * (_stage.global_position + look_target)
	var eye: Vector3 = rig.eye_center
	return Vector2((local.x - eye.x) * 2.0, (local.y - eye.y) * 2.0)


func _idle_glance(delta: float) -> void:
	_idle_time += delta
	if _idle_time < idle_glance_after:
		_glance_yaw = 0.0
		return
	_next_glance -= delta
	if _next_glance <= 0.0:
		_next_glance = randf_range(1.5, 3.5)
		_glance_yaw = randf_range(-0.35, 0.35) if randf() < 0.7 else 0.0
