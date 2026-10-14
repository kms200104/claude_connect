class_name AirDrop
extends Node3D
## 보급 낙하 (v0.26): 헬기 보급으로 부른 탈것 (서버 veh_call mode air, npc "heli").
## 헬기 그림자가 땅 위를 지나가며 (회전날개가 도는 그림자) 세울 자리 위에서 낙하산 단 나무 상자를 떨어뜨린다.
## 떨어지는 동안 내릴 자리에 빨간 표시 고리가 깜빡이고, 상자 그림자가 점점 커진다 (상자가 화면 위쪽이어도 어디로 오는지 보인다).
## 상자는 서버가 정한 도착 시각(arrive_ms)에 딱 땅에 닿고, 쿵 하고 먼지가 일며 낙하산이 접히고 옆판이 열려 탈것이 나온다.
## 그다음 arrived 로 탈것 모형을 넘긴다 (ParkedVehicles 가 받아 세워 둔다). 판정과 상관없는 그림이다.

signal arrived(model: VehicleModel)

const CLAY: Material = preload("res://assets/materials/foliage.tres")
## 떨어지는 시간 (초) · 떨어뜨리는 높이 · 그림자가 지나가는 빠르기 (m/s) · 보이는 거리.
const DROP_S: float = 4.0
const DROP_H: float = 18.0
const SHADOW_SPEED: float = 14.0
const SHADOW_SHOW: float = 34.0
## 땅에 닿은 뒤 옆판이 열리는 시간 · 다 열린 뒤 치우기까지.
const OPEN_S: float = 0.7
const CLEAR_S: float = 1.6

const WOOD: Color = Color("#9A7448")
const WOOD_DARK: Color = Color("#6E5232")
const SHADOW: Color = Color("#2A2E33")

var model: VehicleModel = null
var _target: Transform3D = Transform3D()
var _arrive_ms: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _shadow: Node3D = null
var _rotor: Node3D = null
var _crate: Node3D = null
var _chute: Node3D = null
var _panels: Array[Node3D] = []
## 내릴 자리 표시 고리 · 상자 그림자.
var _marker: Node3D = null
var _blob: Node3D = null
var _size: Vector3 = Vector3(1.2, 1.4, 2.2)
var _landed: bool = false
var _land_t: float = 0.0
var _done: bool = false


## model 은 이미 빚은 탈것 (이 노드 아래로 옮긴다). target = 세울 자리 (바닥 높이 · 방향).
func setup(vehicle: VehicleModel, target: Transform3D, arrive_ms: float) -> void:
	model = vehicle
	_target = target
	_arrive_ms = arrive_ms
	name = "AirDrop"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(arrive_ms)
	_dir = Basis(Vector3.UP, rng.randf() * TAU) * Vector3.FORWARD
	if vehicle.info != null and vehicle.info.kind == "car":
		_size = Vector3(2.1, 2.3, 4.0) if vehicle.info.style == "truck" else Vector3(1.6, 1.6, 2.6)
	_build_shadow()
	_build_crate()
	_build_marker()
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	_crate.add_child(model)
	model.transform = Transform3D()
	model.visible = false
	_process(0.0)


func _process(delta: float) -> void:
	if _done:
		return
	var now: float = Net.server_time_ms()
	var drop_at: float = _arrive_ms - DROP_S * 1000.0
	# 헬기 그림자: 떨어뜨리는 순간 세울 자리 위를 지나간다.
	var along: float = (now - drop_at) / 1000.0 * SHADOW_SPEED
	_shadow.visible = absf(along) < SHADOW_SHOW
	_shadow.global_position = _target.origin + _dir * along + Vector3(0.0, 0.04, 0.0)
	_shadow.global_basis = Basis(Vector3.UP, atan2(-_dir.x, -_dir.z))
	_rotor.rotation.y += delta * 22.0
	if now < drop_at:
		_crate.visible = false
		_marker.visible = false
		_blob.visible = false
		return
	_crate.visible = true
	if not _landed:
		var k: float = clampf((now - drop_at) / (DROP_S * 1000.0), 0.0, 1.0)
		_marker.visible = fmod(now / 350.0, 2.0) < 1.4
		_marker.rotation.y += delta * 1.5
		_blob.visible = true
		_blob.scale = Vector3.ONE * lerpf(0.25, 1.0, k)
		# 낙하산이 펴지면 천천히 (처음 조금 빨리 떨어지다가 일정하게).
		var fall: float = 1.0 - (k * 0.85 + (1.0 - pow(1.0 - k, 3.0)) * 0.15)
		_crate.global_transform = Transform3D(_target.basis * Basis(Vector3.BACK, sin(now / 600.0) * 0.06 * fall), _target.origin + Vector3(0.0, DROP_H * fall, 0.0))
		if k >= 1.0:
			_land()
		return
	_land_t += delta
	# 낙하산이 옆으로 쓰러지며 접히고, 옆판이 바깥으로 열린다.
	_chute.rotation.z = minf(_land_t * 2.0, 1.4)
	_chute.scale = Vector3.ONE * maxf(0.05, 1.0 - _land_t * 0.8)
	_chute.position.y = _size.y + 0.8 - minf(_land_t * 2.5, 2.4)
	var open: float = clampf(_land_t / OPEN_S, 0.0, 1.0)
	for i: int in _panels.size():
		var p: Node3D = _panels[i]
		var out: float = (1.0 - pow(1.0 - open, 2.0)) * PI * 0.5
		if i < 4:
			# 위 모서리가 바깥으로 넘어가게 (앞 −z · 뒤 +z · 왼 −x · 오른 +x).
			p.rotation.x = -out if i == 0 else (out if i == 1 else 0.0)
			p.rotation.z = (out if i == 2 else -out) if i >= 2 else 0.0
		else:
			# 뚜껑은 튀어 올라 옆으로 떨어진다.
			p.position = Vector3(_size.x * 0.9 * open, _size.y + sin(open * PI) * 0.8 - open * _size.y, 0.0)
			p.rotation.z = open * 1.2
	if _land_t > OPEN_S + CLEAR_S:
		_finish()
	elif _land_t > OPEN_S + CLEAR_S - 0.5:
		var fade: float = clampf((OPEN_S + CLEAR_S - _land_t) / 0.5, 0.0, 1.0)
		for p: Node3D in _panels:
			p.scale = Vector3(1.0, fade, 1.0)


func _land() -> void:
	_landed = true
	_marker.visible = false
	_blob.visible = false
	_land_t = 0.0
	_crate.global_transform = _target
	model.visible = true
	Puff.burst(get_parent(), _target.origin + Vector3(0.0, 0.2, 0.0), Color(0.8, 0.74, 0.6, 0.9), 16, _size.z * 0.6, 0.35, 0.14, 0.7)
	Audio.play_at("kick_latch", _target.origin, -2.0, 0.5)
	Prefs.vibrate(80, 0.5)


func _finish() -> void:
	_done = true
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	arrived.emit(model)
	queue_free()


func _build_shadow() -> void:
	_shadow = Node3D.new()
	_shadow.name = "HeliShadow"
	add_child(_shadow)
	var b: BoxBatch = BoxBatch.new()
	# 몸통 · 꼬리 · 꼬리 날개 · 발 (위에서 본 헬기 그림자).
	b.box(Vector3(0.0, 0.0, 0.0), Vector3(1.6, 0.02, 3.4), SHADOW)
	b.box(Vector3(0.0, 0.0, 3.4), Vector3(0.36, 0.02, 3.6), SHADOW)
	b.box(Vector3(0.0, 0.0, 5.1), Vector3(1.4, 0.02, 0.3), SHADOW)
	for side: float in [-1.0, 1.0]:
		b.box(Vector3(side * 1.0, 0.0, 0.0), Vector3(0.14, 0.02, 2.6), SHADOW)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = b.commit()
	body.material_override = CLAY
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.add_child(body)
	_rotor = Node3D.new()
	_rotor.name = "Rotor"
	_rotor.position = Vector3(0.0, 0.01, -0.2)
	_shadow.add_child(_rotor)
	var r: BoxBatch = BoxBatch.new()
	for i: int in 2:
		r.box(Vector3.ZERO, Vector3(9.0, 0.02, 0.28), SHADOW, Basis(Vector3.UP, PI * 0.5 * float(i)))
	var blades: MeshInstance3D = MeshInstance3D.new()
	blades.mesh = r.commit()
	blades.material_override = CLAY
	blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotor.add_child(blades)


## 내릴 자리: 빨간 표시 고리 (조각 8개) · 상자 그림자 (어두운 판, 떨어질수록 커진다).
func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "DropMarker"
	add_child(_marker)
	_marker.global_position = _target.origin + Vector3(0.0, 0.05, 0.0)
	var b: BoxBatch = BoxBatch.new()
	var r: float = maxf(_size.x, _size.z) * 0.75
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		b.box(Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3(0.7, 0.03, 0.22), Color("#E8483A"), Basis(Vector3.UP, -a + PI * 0.5))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = CLAY
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(mi)
	_blob = Node3D.new()
	_blob.name = "CrateShadow"
	add_child(_blob)
	_blob.global_position = _target.origin + Vector3(0.0, 0.03, 0.0)
	var sb: BoxBatch = BoxBatch.new()
	sb.box(Vector3.ZERO, Vector3(_size.x * 0.8, 0.02, _size.z * 0.8), Color("#4A5058"))
	var smi: MeshInstance3D = MeshInstance3D.new()
	smi.mesh = sb.commit()
	smi.material_override = CLAY
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.add_child(smi)


func _build_crate() -> void:
	_crate = Node3D.new()
	_crate.name = "Crate"
	add_child(_crate)
	var s: Vector3 = _size
	# 옆판 4장 (아래 모서리가 경첩) + 뚜껑. 판마다 따로 열린다.
	var specs: Array = [
		[Vector3(0.0, 0.0, -s.z * 0.5), Vector3(s.x, s.y, 0.08), Vector3(0.0, s.y * 0.5, 0.0)],
		[Vector3(0.0, 0.0, s.z * 0.5), Vector3(s.x, s.y, 0.08), Vector3(0.0, s.y * 0.5, 0.0)],
		[Vector3(-s.x * 0.5, 0.0, 0.0), Vector3(0.08, s.y, s.z), Vector3(0.0, s.y * 0.5, 0.0)],
		[Vector3(s.x * 0.5, 0.0, 0.0), Vector3(0.08, s.y, s.z), Vector3(0.0, s.y * 0.5, 0.0)],
		[Vector3(0.0, s.y, 0.0), Vector3(s.x + 0.1, 0.08, s.z + 0.1), Vector3.ZERO],
	]
	for spec: Array in specs:
		var hinge: Node3D = Node3D.new()
		hinge.position = spec[0]
		_crate.add_child(hinge)
		var size: Vector3 = spec[1]
		var b: BoxBatch = BoxBatch.new()
		b.box(spec[2], size, WOOD)
		# 덧댄 띠 (상자 느낌).
		var horizontal: bool = size.y < 0.2
		if horizontal:
			b.box(spec[2] + Vector3(0, 0.05, 0), Vector3(size.x, 0.03, 0.18), WOOD_DARK)
		elif size.x > size.z:
			b.box(spec[2] + Vector3(0, 0, 0.05 * signf(-spec[0].z + 0.001)), Vector3(size.x, 0.16, 0.03), WOOD_DARK)
			b.box(spec[2] + Vector3(0, 0, 0.05 * signf(-spec[0].z + 0.001)), Vector3(0.16, size.y, 0.03), WOOD_DARK)
		else:
			b.box(spec[2], Vector3(0.11, 0.16, size.z), WOOD_DARK)
			b.box(spec[2], Vector3(0.11, size.y, 0.16), WOOD_DARK)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = b.commit()
		mi.material_override = CLAY
		hinge.add_child(mi)
		_panels.append(hinge)
	# 낙하산 (빨강 · 하양 줄무늬 돔) · 줄.
	_chute = Node3D.new()
	_chute.name = "Parachute"
	_chute.position = Vector3(0.0, s.y + 0.8, 0.0)
	_crate.add_child(_chute)
	var st: SurfaceTool = ClayMesh.begin()
	var r: float = maxf(s.x, s.z) * 0.9
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 3.0, 0.0), Vector3(r, r * 0.45, r), Color("#E8483A"), 16, 6)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 3.05, 0.0), Vector3(r * 0.55, r * 0.3, r * 0.55), Color("#F4F0E8"), 12, 5)
	for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var low: Vector3 = Vector3(corner.x * s.x * 0.45, -0.8, corner.z * s.z * 0.45)
		ClayMesh.add_rod(st, low, Vector3(corner.x * r * 0.8, 2.9, corner.z * r * 0.8), 0.015, 0.015, Color("#E8E4DA"), 4)
	var chute: MeshInstance3D = MeshInstance3D.new()
	chute.mesh = ClayMesh.commit(st)
	chute.material_override = CLAY
	_chute.add_child(chute)
