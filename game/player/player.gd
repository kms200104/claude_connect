class_name Player
extends CharacterBody3D
## 조이스틱(없으면 방향키)으로 움직이는 캐릭터. 이동 방향은 카메라 기준.
## 입력 방향으로 가속하고, 입력이 없으면 감속한다. 모델(Body)만 부드럽게 회전한다.

@export_group("References")
@export var joystick: VirtualJoystick
@export var camera: Camera3D
## 회전시킬 시각용 노드 (충돌체는 회전하지 않는다).
@export var body: Node3D

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


func _read_input() -> Vector2:
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
	if body == null or input_amount <= min_input_to_turn or move_dir == Vector3.ZERO:
		return
	# 모델의 정면은 -Z.
	var target_yaw: float = atan2(-move_dir.x, -move_dir.z)
	var weight: float = 1.0 - exp(-turn_smoothing * delta)
	body.rotation.y = lerp_angle(body.rotation.y, target_yaw, weight)
