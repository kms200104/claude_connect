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


func _apply_framing() -> void:
	rotation_degrees = Vector3(-lerpf(pitch_degrees, focus_pitch_degrees, focus), yaw_degrees, 0.0)
	if camera != null:
		camera.position = Vector3(0.0, 0.0, lerpf(distance, focus_distance, focus))
		camera.fov = fov


func _goal_position() -> Vector3:
	var goal: Vector3 = target.global_position + target_offset.lerp(Vector3(0.0, focus_height, 0.0), focus)
	if look_ahead_time > 0.0 and target is CharacterBody3D:
		var body: CharacterBody3D = target
		goal += Vector3(body.velocity.x, 0.0, body.velocity.z) * look_ahead_time
	return goal
