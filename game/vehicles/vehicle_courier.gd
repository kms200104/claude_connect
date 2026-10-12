class_name VehicleCourier
extends Node3D
## 탈것 배달 (v19.1): 배달 로봇 솔봇(v0.17, DeliveryRobot)이 그 탈것을 몰고 와서 정해진 자리(target)에 세워 두고, 손을 흔든 뒤 날아서 떠난다.
## 서버가 정한 도착 시각(arrive_ms, 서버 시계)에 딱 닿게 빠르기를 맞추고, 마지막 몇 m 는 천천히 들어와 세운다.
## 출발 자리는 화면 연출: 세울 자리에서 막힌 데(건물 · 호수 · 바닷가 벽) 없이 가장 멀리 트인 쪽 (최대 START_MAX m).
## 세우고 나면 arrived 로 탈것 모형을 넘긴다 (ParkedVehicles 가 받아 세워 둔다). 판정과 상관없는 그림이다.
## 보트(v20): 물이 길게 트인 쪽 물 위에서 출발해 곧장 몰고 오고(그 길은 모두 물), 띄워 둔 뒤 곁의 땅으로 날아 내려 손을 흔들고 떠난다.
## npc_id 는 서버가 정한 배달 담당 (휴대폰 앱 표시 · 테스트용), 화면에는 로봇이 온다.

signal arrived(model: VehicleModel)

enum Phase { RIDE, HOP_OFF, WAVE, LEAVE, DONE }

const CLAY: Material = preload("res://assets/materials/foliage.tres")
const START_MAX: float = 20.0
const START_MIN: float = 5.0
## 내려서는 시간 · 손 흔드는 시간 · 날아가는 시간 · 거리 · 높이.
const HOP_S: float = 0.6
const WAVE_S: float = 1.6
const LEAVE_S: float = 2.6
const LEAVE_M: float = 7.0
const LEAVE_UP: float = 6.0

var npc_id: String = ""
var model: VehicleModel = null
var robot: DeliveryRobot = null
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
var _boat: bool = false
## 보트: 내려설 땅 (월드).
var _land: Vector3 = Vector3.INF
## 내려서기 시작한 자리 · 내려설 자리 (이 노드 좌표).
var _hop_from: Vector3 = Vector3.ZERO
var _hop_to: Vector3 = Vector3.ZERO
## 크랭크가 돈 양 (바퀴 수).
var _pedal: float = 0.0


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
	robot = DeliveryRobot.new()
	add_child(robot)
	robot.build(CLAY)
	robot.ride(_info.kind if _info != null else "bike")
	model.lights_on = true
	robot.position = seat_spot(_info)
	_boat = _info != null and GameData.garage.is_water_kind(_info.kind)
	_start = _pick_water_start(target.origin) if _boat else _pick_start(target.origin, exclude)
	var flat: Vector3 = (target.origin - _start) * Vector3(1, 0, 1)
	_yaw = atan2(-flat.x, -flat.z) if flat.length() > 0.01 else target.basis.get_euler().y
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _start)


## 보트: 세울 자리에서 물이 가장 길게 이어지는 쪽으로 물러난 자리 (그 사이는 모두 물이라 곧장 몰고 온다).
func _pick_water_start(at: Vector3) -> Vector3:
	var best: Vector3 = at
	var best_len: float = 0.0
	for i: int in 16:
		var a: float = TAU * float(i) / 16.0
		var dir: Vector2 = Vector2(sin(a), cos(a))
		var reach: float = 0.0
		while reach < START_MAX and WaterRules.is_water(Vector2(at.x, at.z) + dir * (reach + 1.0)):
			reach += 1.0
		if reach > best_len:
			best_len = reach
			best = at + Vector3(dir.x, 0.0, dir.y) * reach
	return Vector3(best.x, at.y, best.z)


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


## 탈것 위 로봇 자리: 추진기 밑동이 안장에 닿고, 손이 핸들에 닿게 조금 앞으로.
static func seat_spot(info: VehicleCatalog.Model) -> Vector3:
	if info == null:
		return Vector3(0.0, 0.3, 0.0)
	var seat: Vector3 = info.anchor("seat")
	var bar: Vector3 = info.anchor("bar")
	return Vector3(0.0, seat.y - DeliveryRobot.GROUND_GAP - 0.02, minf(seat.z, bar.z + 0.29))


func _process(delta: float) -> void:
	if robot == null or delta <= 0.0 or phase == Phase.RIDE and model == null:
		return
	match phase:
		Phase.RIDE:
			_ride(delta)
			if model != null:
				robot.hold(model.grip(-1.0), model.grip(1.0))
		Phase.HOP_OFF:
			_t += delta
			# 안장에서 떠올라 옆(보트는 곁의 땅)으로 사뿐히 날아 내린다.
			var k: float = clampf(_t / HOP_S, 0.0, 1.0)
			var e: float = k * k * (3.0 - 2.0 * k)
			robot.position = _hop_from.lerp(_hop_to, e) + Vector3(0.0, sin(k * PI) * 0.35, 0.0)
			robot.thrust = sin(k * PI) * 0.6
			if k >= 1.0:
				_park()
		Phase.WAVE:
			_t += delta
			# 받는 사람 쪽(세운 탈것 쪽)을 보며 손을 흔든다.
			robot.rotation.y = lerp_angle(robot.rotation.y, atan2(_hop_to.x, _hop_to.z), 1.0 - exp(-6.0 * delta))
			if _t >= WAVE_S:
				phase = Phase.LEAVE
				_t = 0.0
				robot.wave(false)
				Audio.play_at("line_zip", global_position, -6.0, 0.7)
		Phase.LEAVE:
			_t += delta
			# 떠난 방향으로 몸을 돌려 비스듬히 날아오른다.
			var face: float = atan2(-_leave_dir.x, -_leave_dir.z) - global_rotation.y
			robot.rotation.y = lerp_angle(robot.rotation.y, face, 1.0 - exp(-5.0 * delta))
			var k2: float = clampf(_t / LEAVE_S, 0.0, 1.0)
			robot.thrust = minf(1.0, _t * 2.5)
			robot.position += global_basis.inverse() * _leave_dir * (LEAVE_M / LEAVE_S) * delta * k2 * 2.0
			robot.position.y = _hop_to.y + LEAVE_UP * k2 * k2
			if _t > LEAVE_S - 0.5:
				robot.scale = Vector3.ONE * clampf((LEAVE_S - _t) / 0.5, 0.01, 1.0)
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
		global_basis = _target.basis
		phase = Phase.HOP_OFF
		_t = 0.0
		robot.ride("")
		robot.lean = 0.0
		_hop_from = robot.position
		# 왼쪽으로 내려선다 (보트는 곁의 땅으로).
		_hop_to = Vector3(-0.75, 0.0, 0.1)
		if _boat:
			var land: Vector2 = WaterRules.landing_near(Vector2(_target.origin.x, _target.origin.z), 8.0)
			_land = Vector3(land.x, 0.0, land.y) if land != Vector2.INF else _start
			_hop_to = global_transform.affine_inverse() * _land
		Audio.play_at("kick_latch", global_position, -6.0, 1.3)
		model.animate(0.0, 0.0, delta)
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
		# 로봇은 페달을 밟지 않는다 (전기 보조로 간다) — 크랭크는 천천히 함께 돈다.
		_pedal += model.pedal_rate(_speed) * delta
		model.set_pedal(_pedal)
	# 도는 쪽으로 몸을 기울인다.
	robot.lean = lerpf(robot.lean, clampf(turn * 0.6, -0.25, 0.25), 1.0 - exp(-6.0 * delta))
	model.animate(_speed, clampf(turn, -0.4, 0.4), delta)


## 세워 두고 손을 흔든다 (탈것은 ParkedVehicles 로 넘긴다). 그다음 날아서 떠난다.
func _park() -> void:
	phase = Phase.WAVE
	_t = 0.0
	robot.thrust = 0.0
	var vehicle: VehicleModel = model
	model = null
	arrived.emit(vehicle)
	robot.wave(true)
	EmoteBubble.say(robot, "배달 완료! 삐빅", 1.75, 2.2)
	Audio.play_at("ui_confirm", robot.global_position, -2.0, 1.25, 0.0)
	# 왔던 쪽으로 날아 나간다 (보트는 물에서 뭍 안쪽으로).
	_leave_dir = ((_start - global_position) * Vector3(1, 0, 1)).normalized()
	if _boat and _land != Vector3.INF:
		_leave_dir = ((_land - global_position) * Vector3(1, 0, 1)).normalized()
	if _leave_dir == Vector3.ZERO:
		_leave_dir = Vector3.BACK
