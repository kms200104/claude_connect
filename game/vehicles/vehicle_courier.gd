class_name VehicleCourier
extends Node3D
## 탈것 배달 (v19.1): 동네 주민이 그 탈것을 타고 와서 정해진 자리(target)에 세워 두고, 손을 흔들고 걸어서 떠난다.
## 서버가 정한 도착 시각(arrive_ms, 서버 시계)에 딱 닿게 빠르기를 맞추고, 마지막 몇 m 는 천천히 들어와 세운다.
## 출발 자리는 화면 연출: 세울 자리에서 막힌 데(건물 · 호수 · 바닷가 벽) 없이 가장 멀리 트인 쪽 (최대 START_MAX m).
## 세우고 나면 arrived 로 탈것 모형을 넘긴다 (ParkedVehicles 가 받아 세워 둔다). 판정과 상관없는 그림이다.

signal arrived(model: VehicleModel)

enum Phase { RIDE, HOP_OFF, WAVE, LEAVE, DONE }

const RIG_SCENE: PackedScene = preload("res://game/player/character_rig.tscn")
const START_MAX: float = 20.0
const START_MIN: float = 5.0
## 손 흔들고 걸어 나가는 시간 · 거리.
const WAVE_S: float = 1.1
const LEAVE_S: float = 3.2
const LEAVE_M: float = 5.5

var npc_id: String = ""
var model: VehicleModel = null
var rig: CharacterRig = null
var phase: Phase = Phase.RIDE
var _info: VehicleCatalog.Model = null
var _target: Transform3D = Transform3D()
var _start: Vector3 = Vector3.ZERO
var _arrive_ms: float = 0.0
var _begin_ms: float = 0.0
var _t: float = 0.0
var _speed: float = 0.0
var _yaw: float = 0.0
var _leave_dir: Vector3 = Vector3.FORWARD


## model 은 이미 빚은 탈것 (이 노드 아래로 옮긴다). target = 세울 자리 (바닥 높이 · 방향).
func setup(npc: String, vehicle: VehicleModel, target: Transform3D, arrive_ms: float, exclude: Array[RID] = []) -> void:
	npc_id = npc
	model = vehicle
	_info = vehicle.info
	_target = target
	_arrive_ms = arrive_ms
	_begin_ms = Net.server_time_ms()
	name = "Courier_%s" % npc
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	add_child(model)
	model.transform = Transform3D()
	rig = RIG_SCENE.instantiate()
	add_child(rig)
	var info: NpcInfo = GameData.npcs.get(npc)
	if info != null:
		rig.set_look(info.look)
	# 배달하는 주민은 빈손으로 핸들을 잡는다 (리그 기본은 낚싯대).
	rig.set_held("")
	rig.set_riding(_info.kind if _info != null else "bike")
	model.lights_on = true
	rig.position = Vector3(0.0, 0.8 + (_info.lift if _info != null else 0.15), 0.0)
	_start = _pick_start(target.origin, exclude)
	var flat: Vector3 = (target.origin - _start) * Vector3(1, 0, 1)
	_yaw = atan2(-flat.x, -flat.z) if flat.length() > 0.01 else target.basis.get_euler().y
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _start)


## 세울 자리에서 막힌 데 없이 가장 멀리 트인 방향으로 물러난 자리 (거기서 출발한다).
func _pick_start(at: Vector3, exclude: Array[RID]) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	var best: Vector3 = at + Vector3(0.0, 0.0, START_MIN)
	var best_len: float = -1.0
	for i: int in 16:
		var a: float = TAU * float(i) / 16.0
		var dir: Vector3 = Vector3(sin(a), 0.0, cos(a))
		var clear: float = START_MAX
		if space != null:
			var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.6, 0), at + dir * START_MAX + Vector3(0, 0.6, 0))
			q.exclude = exclude
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				clear = (hit["position"] as Vector3 - at).length() - 1.0
		# 탈것이 바라볼 방향 뒤쪽에서 오면 자연스럽다 (같은 길이면 그쪽).
		var behind: float = dir.dot(_target.basis.z) * 0.5
		if clear + behind > best_len:
			best_len = clear + behind
			best = at + dir * clampf(clear, START_MIN, START_MAX)
	return Vector3(best.x, at.y, best.z)


func _process(delta: float) -> void:
	if rig == null or delta <= 0.0 or phase == Phase.RIDE and model == null:
		return
	match phase:
		Phase.RIDE:
			_ride(delta)
		Phase.HOP_OFF:
			_t += delta
			var k: float = clampf(_t / 0.35, 0.0, 1.0)
			# 왼쪽으로 폴짝 내린다.
			rig.position = Vector3(-0.55 * k, 0.8 + _info.lift * (1.0 - k) + sin(k * PI) * 0.12, 0.0)
			if k >= 1.0:
				_park()
		Phase.WAVE:
			_t += delta
			if _t >= WAVE_S:
				phase = Phase.LEAVE
				_t = 0.0
				rig.rotation.y = atan2(-_leave_dir.x, -_leave_dir.z) - global_rotation.y
				rig.set_move_speed(1.0)
		Phase.LEAVE:
			_t += delta
			rig.position += global_basis.inverse() * _leave_dir * (LEAVE_M / LEAVE_S) * delta
			if _t > LEAVE_S - 0.4:
				rig.scale = Vector3.ONE * clampf((LEAVE_S - _t) / 0.4, 0.01, 1.0)
			if _t >= LEAVE_S:
				phase = Phase.DONE
				queue_free()


## 도착 시각에 맞춰 달린다: 남은 거리 ÷ 남은 시간, 마지막 2.5m 는 천천히 들어와 세울 방향으로 돌린다.
func _ride(delta: float) -> void:
	var now: float = Net.server_time_ms()
	var left_s: float = maxf((_arrive_ms - now) / 1000.0, 0.0)
	var to: Vector3 = (_target.origin - global_position) * Vector3(1, 0, 1)
	var dist: float = to.length()
	if dist < 0.05 or left_s <= 0.0:
		global_position = _target.origin
		phase = Phase.HOP_OFF
		_t = 0.0
		rig.set_riding("")
		model.animate(0.0, 0.0, delta)
		global_basis = _target.basis
		return
	var want: float = dist / maxf(left_s, 0.05)
	if dist < 2.5:
		want = minf(want, 0.6 + dist)
	_speed = lerpf(_speed, minf(want, _info.base.top), 1.0 - exp(-4.0 * delta))
	var step: float = minf(_speed * delta, dist)
	global_position += to / dist * step
	var face: float = atan2(-to.x, -to.z) if dist > 1.2 else _target.basis.get_euler().y
	var turn: float = angle_difference(_yaw, face)
	_yaw += turn * (1.0 - exp(-6.0 * delta))
	global_basis = Basis(Vector3.UP, _yaw)
	if _info.kind == "bike":
		rig.set_pedal_rate(model.pedal_rate(_speed))
		model.set_pedal(rig.pedal_phase())
	model.animate(_speed, clampf(turn, -0.4, 0.4), delta)


## 세워 두고 손을 흔든다 (탈것은 ParkedVehicles 로 넘긴다). 그다음 걸어 나간다.
func _park() -> void:
	phase = Phase.WAVE
	_t = 0.0
	var vehicle: VehicleModel = model
	model = null
	arrived.emit(vehicle)
	rig.play_emote("hello")
	EmoteBubble.say(rig, "배달 왔어요!", 2.2)
	# 왔던 쪽으로 걸어 나간다.
	_leave_dir = ((_start - global_position) * Vector3(1, 0, 1)).normalized()
	if _leave_dir == Vector3.ZERO:
		_leave_dir = Vector3.BACK
