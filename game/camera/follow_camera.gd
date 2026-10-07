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
## 클로즈업 때 바라보는 점을 화면 오른쪽으로 옮길 만큼 (m). 가로 화면 거울처럼 창이 오른쪽에 있을 때 캐릭터를 왼쪽에 둔다.
var focus_side: float = 0.0

## 0 = 평소, 1 = 클로즈업. set_focus 로 부드럽게 바꾼다.
var focus: float = 0.0
var _focus_tween: Tween = null

@export_group("Bag")
## 가방 창을 열었을 때 (v0.12): 캐릭터에 조금 다가가면서 바라보는 점을 머리 위로 올린다
## → 캐릭터는 화면 아래쪽에 서고, 머리 위 빈 하늘에 가방 창이 뜬다.
@export_range(1.0, 30.0, 0.1, "suffix:m") var bag_distance: float = 6.2
@export_range(0.0, 85.0, 0.5, "suffix:°") var bag_pitch_degrees: float = 30.0
@export_range(0.0, 6.0, 0.05, "suffix:m") var bag_height: float = 3.6
## 가로 화면 (v0.13.4): 가방 창이 머리 오른쪽에 뜨므로 위로 올리는 대신 오른쪽으로 비켜 캐릭터를 왼쪽에 둔다.
@export_range(0.0, 6.0, 0.05, "suffix:m") var bag_side: float = 3.0
@export_range(0.0, 6.0, 0.05, "suffix:m") var bag_side_height: float = 1.2

## 0 = 평소, 1 = 가방 창 구도. set_bag_view 로 부드럽게 바꾼다.
var bag_view: float = 0.0
var _bag_tween: Tween = null

@export_group("Water lean")
## 물가를 걸을 때 (v0.13.4): 바라보는 점을 물 쪽으로 살짝 옮겨 물 밑 물고기 그림자가 화면에 들어오게 한다.
## 바다는 해안선에서 water_lean_range 안이면 바다 쪽으로(가까울수록 더), 호수는 물가에서 그 절반 거리 안이면 호수 쪽으로.
@export_range(0.0, 6.0, 0.1, "suffix:m") var water_lean: float = 2.4
@export_range(1.0, 20.0, 0.5, "suffix:m") var water_lean_range: float = 9.0
@export_range(0.1, 10.0, 0.1) var water_lean_smoothing: float = 1.5

## 지금 물 쪽으로 옮긴 만큼 (부드럽게 따라간다).
var lean: Vector3 = Vector3.ZERO

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

@export_group("See through")
## 높은 건물·나무가 캐릭터를 가리면 (v0.13.5): 그 건물의 캐릭터 둘레를 점점이 비워 캐릭터가 비쳐 보이게 한다
## (toon_world_see 셰이더를 쓰는 건물·나무 머티리얼만). 집 안·1인칭에서는 끈다.
@export var see_through: bool = true
## 캐릭터 자리에서 비우는 원의 반지름 (m). 화면에서 캐릭터 키(1.6m)보다 조금 크게.
@export_range(0.5, 4.0, 0.05, "suffix:m") var see_through_radius: float = 1.6
## 비우는 원의 가운데 높이 (캐릭터 발 기준).
@export_range(0.0, 3.0, 0.05, "suffix:m") var see_through_height: float = 0.9
## 켜고 끌 때 몇 초에 걸쳐 바뀌는지.
@export_range(0.0, 2.0, 0.05, "suffix:s") var see_through_fade: float = 0.35

## 지금 비우는 세기 (0~1, 부드럽게 따라간다). 1인칭 같은 다른 카메라가 끄려면 see_through_blocked 를 켠다.
var see_through_weight: float = 0.0
var see_through_blocked: bool = false
var _see_through_radius_sent: float = -1.0

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
	lean = lean.lerp(water_lean_target(target.global_position), 1.0 - exp(-water_lean_smoothing * delta))
	global_position = global_position.lerp(_goal_position(), weight)
	_update_see_through(delta)


## 셰이더(toon_world_see)에 캐릭터 자리와 세기를 넣는다.
func _update_see_through(delta: float) -> void:
	var want: float = 1.0 if see_through and not see_through_blocked and target != null and not Home.is_inside() else 0.0
	var step: float = delta / see_through_fade if see_through_fade > 0.0 else 1.0
	see_through_weight = move_toward(see_through_weight, want, step)
	var at: Vector3 = target.global_position + Vector3(0.0, see_through_height, 0.0) if target != null else Vector3.ZERO
	RenderingServer.global_shader_parameter_set(&"see_through_target", Vector4(at.x, at.y, at.z, see_through_weight))
	if see_through_radius != _see_through_radius_sent:
		_see_through_radius_sent = see_through_radius
		RenderingServer.global_shader_parameter_set(&"see_through_radius", see_through_radius)


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


## 이 자리에서 물 쪽으로 옮길 만큼 (물에서 멀거나 실내면 0).
func water_lean_target(at: Vector3) -> Vector3:
	var layout: VillageLayout = GameData.layout
	if water_lean <= 0.0 or layout == null or layout.island_half <= 0.0 or Home.is_inside():
		return Vector3.ZERO
	var p: Vector2 = Vector2(at.x, at.z)
	var shape: float = layout.island_shape(p)
	if shape > SpotInfo.SEA_STAND_MAX or (GameData.shop != null and GameData.shop.is_inside(at)):
		return Vector3.ZERO
	var best: Vector3 = Vector3.ZERO
	# 바다: 섬 모양이 커지는 쪽(바깥)이 바다.
	var to_coast: float = (1.0 - shape) * layout.island_half
	if to_coast < water_lean_range:
		var e: float = 0.5
		var grad: Vector2 = Vector2(layout.island_shape(p + Vector2(e, 0)) - layout.island_shape(p - Vector2(e, 0)),
			layout.island_shape(p + Vector2(0, e)) - layout.island_shape(p - Vector2(0, e)))
		if grad.length() > 0.000001:
			var k: float = clampf((water_lean_range - to_coast) / (water_lean_range * 0.6), 0.0, 1.0)
			var dir: Vector2 = grad.normalized()
			best = Vector3(dir.x, 0.0, dir.y) * water_lean * k
	# 호수: 물가에서 가까우면 호수 가운데 쪽으로 (조금 약하게).
	for spot: SpotInfo in GameData.spots.values():
		if spot.is_sea:
			continue
		var d: float = spot.distance_to(at)
		var reach: float = water_lean_range * 0.5
		if d < reach:
			# 윤곽 호수(크고 굽은 호수)는 가운데가 아니라 가장 가까운 물 쪽으로.
			var to: Vector2 = (spot.nearest_in_water(p) if spot.has_outline() else spot.center) - p
			if to.length() > 0.01:
				var k: float = clampf((reach - d) / (reach * 0.6), 0.0, 1.0) * 0.7
				var v: Vector3 = Vector3(to.normalized().x, 0.0, to.normalized().y) * water_lean * k
				if v.length() > best.length():
					best = v
	return best


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
	var bag_offset: Vector3 = Vector3(0.0, bag_height, 0.0)
	var right: Vector3 = Vector3(cos(deg_to_rad(yaw_degrees)), 0.0, -sin(deg_to_rad(yaw_degrees)))
	if ScreenFit.landscape:
		bag_offset = right * bag_side + Vector3(0.0, bag_side_height, 0.0)
	var offset: Vector3 = target_offset.lerp(Vector3(0.0, focus_height, 0.0) + right * focus_side, focus).lerp(bag_offset, bag_view)
	var goal: Vector3 = target.global_position + offset + lean * (1.0 - bag_view) * (1.0 - focus)
	if point_weight > 0.0:
		goal = goal.lerp(point + Vector3(0.0, 0.4, 0.0), point_share * point_weight * (1.0 - focus))
	if look_ahead_time > 0.0 and target is CharacterBody3D:
		var body: CharacterBody3D = target
		goal += Vector3(body.velocity.x, 0.0, body.velocity.z) * look_ahead_time
	return goal
