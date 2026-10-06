class_name FollowCamera
extends Node3D
## 대상을 부드럽게 따라오는 3인칭 카메라 리그. 고정 각도(yaw/pitch)로 내려다본다.
## 모든 값은 매 틱 다시 적용되므로 실행 중 인스펙터에서 바꿔도 즉시 반영된다.

@export_group("References")
@export var target: Node3D
@export var camera: Camera3D

@export_group("Framing")
@export_range(1.0, 30.0, 0.1, "suffix:m") var distance: float = 7.5
@export_range(0.0, 85.0, 0.5, "suffix:°") var pitch_degrees: float = 48.0
@export_range(-180.0, 180.0, 0.5, "suffix:°") var yaw_degrees: float = 0.0
@export_range(30.0, 110.0, 0.5, "suffix:°") var fov: float = 55.0
## 캐릭터 발 기준으로 카메라가 바라볼 지점의 오프셋.
@export var target_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

@export_group("Focus")
## 클로즈업(focus = 1)일 때의 거리·각도·바라보는 높이 (낚은 물고기를 자랑할 때).
@export_range(1.0, 30.0, 0.1, "suffix:m") var focus_distance: float = 3.4
@export_range(0.0, 85.0, 0.5, "suffix:°") var focus_pitch_degrees: float = 20.0
@export_range(0.0, 3.0, 0.05, "suffix:m") var focus_height: float = 1.55

## 0 = 평소, 1 = 클로즈업. set_focus 로 부드럽게 바꾼다.
var focus: float = 0.0
var _focus_tween: Tween = null

@export_group("Bag")
## 가방 창을 열었을 때 (v0.12): 캐릭터에 조금 다가가면서 바라보는 점을 머리 위로 올린다
## → 캐릭터는 화면 아래쪽에 서고, 머리 위 빈 하늘에 가방 창이 뜬다.
@export_range(1.0, 30.0, 0.1, "suffix:m") var bag_distance: float = 6.2
@export_range(0.0, 85.0, 0.5, "suffix:°") var bag_pitch_degrees: float = 30.0
@export_range(0.0, 6.0, 0.05, "suffix:m") var bag_height: float = 3.6

## 0 = 평소, 1 = 가방 창 구도. set_bag_view 로 부드럽게 바꾼다.
var bag_view: float = 0.0
var _bag_tween: Tween = null

@export_group("Point focus")
## 낚시 찌처럼 캐릭터 밖의 한 점을 같이 비출 때 (v13): 캐릭터와 그 점 사이로 바라보는 점을 옮기고, 가까우면 조금 다가가고
## 세로 화면에 둘이 다 안 들어가면(옆으로 멀면) 그만큼 물러난다.
@export_range(0.0, 1.0, 0.05) var point_share: float = 0.5
@export_range(0.3, 1.0, 0.01) var point_zoom: float = 0.85
## 화면 가장자리에 남길 여유 (m).
@export_range(0.0, 3.0, 0.1, "suffix:m") var point_margin: float = 1.1

## 같이 비출 점과 그 세기 (0 = 안 비춤). set_point_focus 로 부드럽게 바꾼다.
var point: Vector3 = Vector3.ZERO
var point_weight: float = 0.0
var _point_tween: Tween = null

@export_group("Smoothing")
## 클수록 캐릭터에 딱 붙는다 (지수 감쇠 계수, 프레임레이트와 무관).
@export_range(0.5, 30.0, 0.1) var follow_smoothing: float = 5.0
## 이동 방향으로 미리 보는 시간. 0이면 끈다.
@export_range(0.0, 1.0, 0.01, "suffix:s") var look_ahead_time: float = 0.25


func _ready() -> void:
	# 대상(Player)이 먼저 움직인 다음 카메라가 따라가도록 뒤에 처리한다.
	process_physics_priority = 10
	_apply_framing()
	if target != null:
		global_position = _goal_position()


func _physics_process(delta: float) -> void:
	_apply_framing()
	if target == null:
		return
	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(_goal_position(), weight)


## 순간이동(상점 문 등) 뒤에 마을을 가로질러 미끄러지지 않도록 바로 따라붙는다.
func snap_to_target() -> void:
	if target != null:
		_apply_framing()
		global_position = _goal_position()


## 클로즈업으로 다가가거나(1) 평소로 물러난다(0).
func set_focus(amount: float, duration: float = 0.6) -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.tween_property(self, "focus", clampf(amount, 0.0, 1.0), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 가방 창 구도로 옮겨 가거나(on) 평소로 돌아온다. 카메라가 미끄러지듯 움직인다.
func set_bag_view(on: bool, duration: float = 0.55) -> void:
	if _bag_tween != null and _bag_tween.is_valid():
		_bag_tween.kill()
	_bag_tween = create_tween()
	_bag_tween.tween_property(self, "bag_view", 1.0 if on else 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN_OUT)


## 한 점(낚시 찌)을 같이 비춘다. amount 0 이면 풀린다.
func set_point_focus(at: Vector3, amount: float = 1.0, duration: float = 0.9) -> void:
	point = at
	if _point_tween != null and _point_tween.is_valid():
		_point_tween.kill()
	_point_tween = create_tween()
	_point_tween.tween_property(self, "point_weight", clampf(amount, 0.0, 1.0), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func clear_point_focus(duration: float = 0.6) -> void:
	set_point_focus(point, 0.0, duration)


func _apply_framing() -> void:
	var pitch: float = lerpf(lerpf(pitch_degrees, focus_pitch_degrees, focus), bag_pitch_degrees, bag_view)
	rotation_degrees = Vector3(-pitch, yaw_degrees, 0.0)
	if camera != null:
		var dist: float = lerpf(lerpf(distance, focus_distance, focus), bag_distance, bag_view)
		var w: float = point_weight * (1.0 - focus)
		if w > 0.0 and target != null:
			dist = lerpf(dist, maxf(dist * point_zoom, _distance_to_fit_point()), w)
		camera.position = Vector3(0.0, 0.0, dist)
		camera.fov = fov


## 캐릭터와 찌가 가로로 다 들어오는 거리 (세로 화면은 가로 화각이 좁다).
func _distance_to_fit_point() -> float:
	var vp: Viewport = get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(9, 16)
	var aspect: float = size.x / maxf(size.y, 1.0)
	var half_h: float = atan(tan(deg_to_rad(fov) * 0.5) * aspect)
	var right: Vector3 = Vector3(cos(deg_to_rad(yaw_degrees)), 0.0, -sin(deg_to_rad(yaw_degrees)))
	var sep: float = absf((point - target.global_position).dot(right))
	return (sep * 0.5 + point_margin) / maxf(tan(half_h), 0.05)


func _goal_position() -> Vector3:
	var offset: Vector3 = target_offset.lerp(Vector3(0.0, focus_height, 0.0), focus).lerp(Vector3(0.0, bag_height, 0.0), bag_view)
	var goal: Vector3 = target.global_position + offset
	if point_weight > 0.0:
		goal = goal.lerp(point + Vector3(0.0, 0.4, 0.0), point_share * point_weight * (1.0 - focus))
	if look_ahead_time > 0.0 and target is CharacterBody3D:
		var body: CharacterBody3D = target
		goal += Vector3(body.velocity.x, 0.0, body.velocity.z) * look_ahead_time
	return goal
