class_name Player
extends CharacterBody3D
## 조이스틱(없으면 방향키)으로 움직이는 캐릭터. 이동 방향은 카메라 기준.
## 입력 방향으로 가속하고, 입력이 없으면 감속한다. 모델(Body)만 부드럽게 회전한다.

@export_group("References")
@export var joystick: TouchJoystick
@export var camera: Camera3D
## 회전시킬 시각용 노드 (충돌체는 회전하지 않는다).
@export var body: Node3D
## idle / walk / 낚시 애니메이션을 재생하는 리그 (보통 body와 같은 노드).
@export var rig: CharacterRig

@export_group("Movement")
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var max_speed: float = 4.5
@export_range(1.0, 100.0, 0.5, "suffix:m/s²") var acceleration: float = 16.0
@export_range(1.0, 100.0, 0.5, "suffix:m/s²") var deceleration: float = 22.0
@export_range(0.0, 60.0, 0.5, "suffix:m/s²") var gravity: float = 24.0

@export_group("Turning")
## 클수록 빨리 돌아선다 (지수 감쇠 계수, 프레임레이트와 무관).
@export_range(1.0, 40.0, 0.5) var turn_smoothing: float = 10.0
## 이 크기 이하의 입력으로는 방향을 바꾸지 않는다 (떨림 방지).
@export_range(0.0, 0.5, 0.01) var min_input_to_turn: float = 0.05

@export_group("Animation")
## 이 속도(m/s)로 걸을 때 walk 애니메이션이 100% 재생된다. 0이면 max_speed를 쓴다.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var walk_speed_reference: float = 0.0

var _input_locks: Dictionary[StringName, bool] = {}
var _look_yaw: float = 0.0
var _look_active: bool = false


func _physics_process(delta: float) -> void:
	var input: Vector2 = _read_input()
	var move_dir: Vector3 = _input_to_world(input)
	var target_velocity: Vector3 = move_dir * max_speed * minf(input.length(), 1.0)

	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = acceleration if input.length() > 0.0 else deceleration
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()
	_turn_body(move_dir, input.length(), delta)
	if rig != null:
		var reference: float = walk_speed_reference if walk_speed_reference > 0.0 else max_speed
		rig.set_move_speed(Vector3(velocity.x, 0.0, velocity.z).length() / reference)


## 이동 입력을 막거나 푼다. 사유별로 따로 기록해서 여러 곳(낚시, 가방 창)이 서로 간섭하지 않는다.
func set_input_lock(reason: StringName, locked: bool) -> void:
	if locked:
		_input_locks[reason] = true
	else:
		_input_locks.erase(reason)


func is_input_locked() -> bool:
	return not _input_locks.is_empty()


## 입력이 막혀 있는 동안 이 방향(월드 XZ)을 바라보게 한다. 풀려면 clear_look_direction().
func look_toward(direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return
	_look_yaw = atan2(-flat.x, -flat.z)
	_look_active = true


func clear_look_direction() -> void:
	_look_active = false


func set_fishing_pose(active: bool) -> void:
	if rig != null:
		rig.set_fishing(active)


func _read_input() -> Vector2:
	if is_input_locked():
		return Vector2.ZERO
	if joystick != null and joystick.output != Vector2.ZERO:
		return joystick.output
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


func _input_to_world(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var basis_ref: Basis = camera.global_basis if camera != null else Basis.IDENTITY
	var forward: Vector3 = Vector3(-basis_ref.z.x, 0.0, -basis_ref.z.z).normalized()
	var right: Vector3 = Vector3(basis_ref.x.x, 0.0, basis_ref.x.z).normalized()
	return (right * input.x - forward * input.y).normalized()


func _turn_body(move_dir: Vector3, input_amount: float, delta: float) -> void:
	if body == null:
		return
	var target_yaw: float
	if _look_active and move_dir == Vector3.ZERO:
		target_yaw = _look_yaw
	elif input_amount > min_input_to_turn and move_dir != Vector3.ZERO:
		# 모델의 정면은 -Z.
		target_yaw = atan2(-move_dir.x, -move_dir.z)
	else:
		return
	var weight: float = 1.0 - exp(-turn_smoothing * delta)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, weight)
