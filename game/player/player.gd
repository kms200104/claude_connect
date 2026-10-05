class_name Player
extends CharacterBody3D
## 조이스틱(없으면 방향키)으로 움직이는 캐릭터. 이동 방향은 카메라 기준.
## 입력 방향으로 가속하고, 입력이 없으면 감속한다. 모델(Body)만 부드럽게 회전한다.
## 달리다가 반대쪽으로 확 틀면 몸을 젖혀 버티며 끼이익 미끄러져 멈춘 뒤 돌아선다 (braked 신호).

## 달리다 브레이크를 잡았다 (미끄러지기 시작).
signal braked

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

@export_group("Braking")
## 달리는 중(이 속도 이상)에 진행 방향과 이 각도 이상 어긋나게 밀면 브레이크를 잡는다.
@export_range(1.0, 20.0, 0.1, "suffix:m/s") var brake_min_speed: float = 5.2
@export_range(90.0, 180.0, 1.0, "suffix:°") var brake_angle: float = 125.0
## 미끄러지는 동안의 감속 (작을수록 멀리 미끄러진다).
@export_range(1.0, 60.0, 0.5, "suffix:m/s²") var brake_deceleration: float = 13.0
## 이 속도 아래로 떨어지면 미끄러짐이 끝나고 돌아선다.
@export_range(0.0, 3.0, 0.05, "suffix:m/s") var brake_stop_speed: float = 0.7
## 흙먼지를 일으키는 간격.
@export_range(0.02, 0.5, 0.01, "suffix:s") var brake_dust_interval: float = 0.07

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
## 이번 프레임에 가려고 한 방향 × 입력 세기 (월드 XZ). 벽에 막혀 멈춰 있어도 미는 방향을 알 수 있다 (상점 문).
var move_intent: Vector3 = Vector3.ZERO
## 브레이크를 잡고 미끄러지는 중.
var braking: bool = false
## 여울(얕은 물)에 들어가 있는지 (v9): 걸음이 느려지고 물을 첨벙인다.
var wading: bool = false
## 몸(Body)의 원래 높이 — 여울에서는 여기서 WADE_SINK 만큼 내려간다.
var _body_rest_y: float = NAN
## 물속에서 걷는 빠르기 배율.
const WADE_SPEED: float = 0.55
## 여울에 들어가면 몸이 이만큼 물에 잠긴다 (바닥 아래로 내려 발목·정강이가 물에 들어간 것처럼).
const WADE_SINK: float = 0.09
var _splash_left: float = 0.0

var _input_locks: Dictionary[StringName, bool] = {}
var _look_yaw: float = 0.0
var _look_active: bool = false
var _full_push_time: float = 0.0
var _footsteps: Footsteps = Footsteps.new()
var _brake_dust_left: float = 0.0


func _ready() -> void:
	# 주민들이 돌아보는 대상 (NpcCrowd).
	add_to_group(&"player")


func _physics_process(delta: float) -> void:
	var input: Vector2 = _read_input()
	_update_running(input.length(), delta)
	var move_dir: Vector3 = _input_to_world(input)
	move_intent = move_dir * minf(input.length(), 1.0)
	var top_speed: float = run_speed if running else max_speed
	wading = not Field.zone_at(global_position, 0.1).is_empty()
	if wading:
		top_speed *= WADE_SPEED
	var target_velocity: Vector3 = move_dir * top_speed * minf(input.length(), 1.0)

	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if not braking and _should_brake(horizontal, move_dir, input.length()):
		_start_brake()
	if braking:
		# 미끄러지는 동안은 입력을 받지 않고 진행 방향으로 쭉 밀려 가다 선다.
		horizontal = horizontal.move_toward(Vector3.ZERO, brake_deceleration * delta)
		_brake_dust_left -= delta
		if _brake_dust_left <= 0.0 and is_inside_tree():
			_brake_dust_left = brake_dust_interval
			Puff.burst(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Puff.dust_color(global_position), 2, 0.45, 0.25, 0.08, 0.45)
		if horizontal.length() <= brake_stop_speed:
			_end_brake()
	else:
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
	if not braking:
		var step: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
		_footsteps.advance(step, running, global_position, false)
		_turn_body(move_dir, input.length(), delta)
		if wading and step > 0.0:
			_splash_left -= delta
			if _splash_left <= 0.0 and is_inside_tree():
				_splash_left = 0.28
				Puff.burst(get_parent(), global_position + Vector3(0.0, 0.25, 0.0), Color(0.85, 0.95, 1.0, 0.8), 3, 0.35, 0.3, 0.06, 0.4)
	if body != null:
		if is_nan(_body_rest_y):
			_body_rest_y = body.position.y
		body.position.y = move_toward(body.position.y, _body_rest_y - (WADE_SINK if wading else 0.0), delta * 1.2)
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


func play_cast() -> void:
	if rig != null:
		rig.play_cast()


## 낚싯대 끝 (월드 좌표). 찌가 여기서 날아간다.
func rod_tip() -> Vector3:
	if rig != null and rig.rod != null:
		return rig.rod.global_transform * Vector3(0.0, 1.5, 0.0)
	return global_position + Vector3(0.0, 1.6, 0.0)


func play_chop() -> void:
	if rig != null:
		rig.play_chop()


## 삽질 한 번.
func play_dig() -> void:
	if rig != null:
		rig.play_dig()


## 쪼그려 앉아 흙을 토닥이는 동작 (씨앗 심기·꽃 따기).
func play_plant() -> void:
	if rig != null:
		rig.play_plant()


## 감정표현 (몸짓 + 머리 위 말풍선 + 소리). 서버에 알리는 건 EmoteController.
func play_emote(emote_id: String) -> void:
	if rig != null:
		rig.play_emote(emote_id)
	EmoteBubble.pop(self, emote_id)
	var info: EmoteInfo = GameData.emote(emote_id)
	Audio.play_sfx(info.sound if info != null else "emote_pop", -3.0)


## 빠르게 달리는 중에 거의 반대쪽으로 밀었는가.
func _should_brake(horizontal: Vector3, move_dir: Vector3, input_amount: float) -> bool:
	var speed: float = horizontal.length()
	if speed < brake_min_speed or input_amount < 0.5 or move_dir == Vector3.ZERO:
		return false
	return (horizontal / speed).dot(move_dir) <= cos(deg_to_rad(brake_angle))


func _start_brake() -> void:
	braking = true
	running = false
	_full_push_time = 0.0
	_brake_dust_left = 0.0
	if rig != null:
		rig.set_braking(true)
	Audio.play_sfx("skid", -1.0, 1.0, 0.06)
	braked.emit()


func _end_brake() -> void:
	braking = false
	if rig != null:
		rig.set_braking(false)


## 끝까지 민 채로 run_delay 가 지나면 달리기 시작, 덜 밀거나 놓으면 걷기.
func _update_running(amount: float, delta: float) -> void:
	if braking:
		return
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
