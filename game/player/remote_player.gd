class_name RemotePlayer
extends Node3D
## 다른 사람의 캐릭터. 서버 스냅샷을 버퍼에 쌓고, 서버 시계 기준으로 조금 과거(interpolation_delay)를
## 보간해서 그린다. 패킷이 늦거나 몇 개 빠져도 끊기지 않고, 너무 늦으면 짧게 외삽한 뒤 멈춘다.

@export_group("References")
@export var body: Node3D
@export var rig: CharacterRig
@export var name_label: Label3D

@export_group("Interpolation")
## 클수록 부드럽지만 상대 움직임이 늦게 보인다. 스냅샷 주기(50ms)의 2~3배가 적당.
@export_range(0.0, 500.0, 5.0, "suffix:ms") var interpolation_delay_ms: float = 120.0
## 최신 스냅샷보다 앞서야 할 때 속도로 추정해 이동하는 최대 시간.
@export_range(0.0, 500.0, 10.0, "suffix:ms") var max_extrapolation_ms: float = 200.0
## 이 거리 이상 한 번에 움직이면 보간하지 않고 순간이동으로 본다.
@export_range(0.5, 50.0, 0.5, "suffix:m") var teleport_distance: float = 6.0
## 보간 결과를 한 번 더 부드럽게 따라가는 정도 (클수록 딱 붙는다).
@export_range(1.0, 60.0, 0.5) var follow_smoothing: float = 30.0
@export_range(4, 100) var max_samples: int = 40

@export_group("Animation")
## 이 속도(m/s)로 움직이면 walk 애니메이션이 100% 재생된다 (플레이어 최대 속도와 같게).
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var walk_speed_reference: float = 4.5
## 화면에서 실제 움직인 속도를 이 정도로 부드럽게 따라가며 걷기 애니메이션에 쓴다.
@export_range(1.0, 40.0, 0.5) var speed_smoothing: float = 12.0

var player_id: int = 0
var online: bool = true
var fishing: bool = false
## 리그의 기본값(낚싯대)과 같게 시작해야 첫 상태가 빈손일 때도 반영된다.
var held_item: String = "rod"

var _samples: Array[Sample] = []
var _shown_speed: float = 0.0


class Sample:
	var time_ms: float
	var position: Vector3
	var yaw: float
	var velocity: Vector3
	var fishing: bool
	var held: String

	func _init(t: float, p: Vector3, y: float, v: Vector3, f: bool, h: String) -> void:
		time_ms = t
		position = p
		yaw = y
		velocity = v
		fishing = f
		held = h


func setup(state: NetPlayerState) -> void:
	player_id = state.id
	global_position = state.position
	if body != null:
		body.rotation.y = state.yaw
	set_online(state.online)
	_apply_held(state.held)


func set_online(value: bool) -> void:
	online = value
	if name_label != null:
		name_label.text = "플레이어 %d" % player_id if online else "플레이어 %d · 연결 끊김" % player_id
		name_label.modulate = Color.WHITE if online else Color(1.0, 1.0, 1.0, 0.55)


## 상대의 동작 이벤트 (지금은 도끼질만).
func play_action(kind: String) -> void:
	if kind == "chop" and rig != null:
		rig.play_chop()


func push_sample(server_time_ms: float, position: Vector3, yaw: float, velocity: Vector3, is_fishing: bool = false, held: String = "") -> void:
	if not _samples.is_empty():
		var last: Sample = _samples[-1]
		if server_time_ms <= last.time_ms:
			return  # 순서가 뒤바뀐 패킷
		if last.position.distance_to(position) > teleport_distance:
			_samples.clear()
			global_position = position
	_samples.append(Sample.new(server_time_ms, position, yaw, velocity, is_fishing, held))
	# 손에 든 도구는 보간할 값이 아니라서 받자마자 바꾼다.
	_apply_held(held)
	if _samples.size() > max_samples:
		_samples.pop_front()


func _apply_held(item_id: String) -> void:
	if item_id == held_item:
		return
	held_item = item_id
	if rig != null:
		rig.set_held(item_id)


func _process(delta: float) -> void:
	if _samples.is_empty():
		return
	var render_time: float = Net.server_time_ms() - interpolation_delay_ms
	var target_pos: Vector3
	var target_yaw: float
	var target_fishing: bool
	var last: Sample = _samples[-1]

	if render_time >= last.time_ms:
		var ahead: float = minf(render_time - last.time_ms, max_extrapolation_ms) / 1000.0
		target_pos = last.position + last.velocity * ahead
		target_yaw = last.yaw
		target_fishing = last.fishing
	elif render_time <= _samples[0].time_ms:
		target_pos = _samples[0].position
		target_yaw = _samples[0].yaw
		target_fishing = _samples[0].fishing
	else:
		var i: int = _samples.size() - 2
		while i > 0 and _samples[i].time_ms > render_time:
			i -= 1
		var a: Sample = _samples[i]
		var b: Sample = _samples[i + 1]
		var span: float = maxf(b.time_ms - a.time_ms, 0.001)
		var f: float = clampf((render_time - a.time_ms) / span, 0.0, 1.0)
		target_pos = a.position.lerp(b.position, f)
		target_yaw = lerp_angle(a.yaw, b.yaw, f)
		target_fishing = a.fishing

	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	var before: Vector3 = global_position
	global_position = global_position.lerp(target_pos, weight)
	if rig != null and delta > 0.0:
		# 실제로 화면에서 움직인 속도로 걷기 애니메이션을 정한다 (낚시 중에는 서 있는다).
		var moved: float = Vector3(global_position.x - before.x, 0.0, global_position.z - before.z).length() / delta
		_shown_speed = lerpf(_shown_speed, moved, 1.0 - exp(-speed_smoothing * delta))
		rig.set_move_speed(0.0 if target_fishing else _shown_speed / walk_speed_reference)
		rig.set_fishing(target_fishing)
	if body != null:
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, weight)
