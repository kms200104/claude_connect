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

@export_group("Running")
## 조이스틱을 끝까지(이 비율 이상) 민 채로 run_delay 가 지나면 달린다.
@export_range(0.5, 1.0, 0.01) var run_threshold: float = 0.95
@export_range(0.0, 3.0, 0.05, "suffix:s") var run_delay: float = 0.7
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var run_speed: float = 7.0
## 달리다가 입력이 이 비율 아래로 떨어지면 걷기로 돌아간다 (조금 덜 밀어도 바로 멈추지 않게).
@export_range(0.0, 1.0, 0.01) var run_release_threshold: float = 0.7
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

## 손에 든 아이템 id (빈손이면 빈 문자열).
var held_item: String = "rod"
## 달리는 중인지 (조이스틱을 끝까지 0.7초 이상 밀고 있음).
var running: bool = false

var _input_locks: Dictionary[StringName, bool] = {}
var _look_yaw: float = 0.0
var _look_active: bool = false
var _full_push_time: float = 0.0
var _footsteps: Footsteps = Footsteps.new()


func _physics_process(delta: float) -> void:
	var input: Vector2 = _read_input()
	_update_running(input.length(), delta)
	var move_dir: Vector3 = _input_to_world(input)
	var top_speed: float = run_speed if running else max_speed
	var target_velocity: Vector3 = move_dir * top_speed * minf(input.length(), 1.0)

	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = acceleration if input.length() > 0.0 else deceleration
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	var before: Vector3 = global_position
	move_and_slide()
	_footsteps.advance(Vector2(global_position.x - before.x, global_position.z - before.z).length(), running, global_position, false)
	_turn_body(move_dir, input.length(), delta)
	if rig != null:
		var reference: float = walk_speed_reference if walk_speed_reference > 0.0 else max_speed
		rig.set_move_speed(CharacterRig.speed_to_blend(Vector3(velocity.x, 0.0, velocity.z).length(), reference, run_speed))
	if joystick != null:
		joystick.boost = running


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


## 손에 든 아이템 (퀵슬롯에서 고른 것). 낚싯대·도끼는 모델에 보인다.
func set_held_item(item_id: String) -> void:
	held_item = item_id
	if rig != null:
		rig.set_held(item_id)


func play_chop() -> void:
	if rig != null:
		rig.play_chop()


## 끝까지 민 채로 run_delay 가 지나면 달리기 시작, 덜 밀거나 놓으면 걷기.
func _update_running(amount: float, delta: float) -> void:
	if amount >= run_threshold:
		_full_push_time += delta
	else:
		_full_push_time = 0.0
	if running:
		running = amount >= run_release_threshold
	else:
		running = _full_push_time >= run_delay


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
