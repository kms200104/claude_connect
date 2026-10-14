class_name VehicleModel
extends Node3D
## 차고 탈것 모형 (v19): 자전거 · 전기오토바이 · 보트 · 차량(v0.26 ATV · 미니트럭)을 모델(style)과 끼운 부품(fit)대로 빚는다.
## v21: 실제 제품 모양을 따라 매끈한 곡면(로프트 · 스윕 · 회전체)으로 — bike_parts · moto_parts · boat_parts (도구는 vehicle_shapes).
## 원점 = 바닥(두 바퀴 사이), 앞 = -Z. 타는 캐릭터의 리그 자세(ride_bike · ride_moto)에 맞춘 자리(anchors)를 쓴다.
## 나뉜 마디: 몸체(Frame) · 앞바퀴와 핸들(Steer, 조향축으로 돈다) · 뒷바퀴 · 크랭크와 페달(자전거) · 빛나는 렌즈와 장식.
## animate(속도, 조향, delta) 로 바퀴 · 크랭크 · 핸들을 돌린다. 밤(night_light)에는 전조등(SpotLight)과 언더글로우가 켜진다.
const Shapes := preload("res://game/vehicles/vehicle_shapes.gd")
const BikeKit := preload("res://game/vehicles/bike_parts.gd")
const MotoKit := preload("res://game/vehicles/moto_parts.gd")
const BoatKit := preload("res://game/vehicles/boat_parts.gd")
const CarKit := preload("res://game/vehicles/car_parts.gd")

const DARK: Color = Color("#2A2A2E")
const LENS: Color = Color("#F4F1E6")
const TAIL: Color = Color("#E0483A")
## 캐릭터 골반 관절 (발 기준, 타지 않을 때) · 크랭크 가운데 (골반 기준 y, z) — gen_character_rig.py 의 CRANK.
const RIDER_HIP: Vector3 = Vector3(0.0, 0.39, 0.064)
const CRANK: Vector2 = Vector2(-0.26, -0.07)
const CRANK_R: float = 0.075
## 기본 전조등 · 미등 (부품을 끼우지 않았을 때).
const STOCK_LIGHT: Dictionary = {"range": 6.0, "energy": 0.7, "angle": 36.0, "color": "#FFE2B0", "lens": 0.9}
const STOCK_TAIL: Dictionary = {"energy": 1.4, "size": 1.0}

var model_id: String = ""
var fit: Dictionary = {}
var info: VehicleCatalog.Model = null
## 크랭크 위치 (0~1, 0 = 왼발 페달이 맨 위). 리그가 다리 자세를 여기에 맞춘다.
var pedal_phase: float = 0.0
## 전조등 켜기 (탈 때 · 배달 올 때). 세워 두면 끈다 (빛 장식 · 미등 렌즈는 그대로 빛난다).
var lights_on: bool = true

var _frame: MeshInstance3D = null
var _steer: Node3D = null
var _steer_axis: Vector3 = Vector3.UP
var _front_spin: Node3D = null
var _rear_spin: Node3D = null
var _crank: Node3D = null
var _pedals: Array[Node3D] = []
var _head_light: SpotLight3D = null
var _under_light: OmniLight3D = null
var _light_energy: float = 0.0
var _under_energy: float = 0.0
var _wheel_angle: float = 0.0
var _steer_angle: float = 0.0
var _key: String = ""
var _clay: Material = null
## 보트 (v20): 카약 노 · 모터보트 선외기, 물 위에 세워 두면 출렁인다(floating), 달리면 뒤로 물보라.
var floating: bool = false
var _paddle: Node3D = null
var _motor: Node3D = null
## 뱃머리 등 자리.
var _steer_head: Vector3 = Vector3.ZERO
var _bob_t: float = 0.0
var _wake_left: float = 0.0
## 차량 (v0.26): 네 바퀴 (도는 마디) · 앞바퀴 꺾는 마디 · 운전대 돌리는 배율.
var _car_spins: Array[Node3D] = []
var _car_pivots: Array[Node3D] = []
var _wheel_turn: float = 1.0

static var _glow_materials: Dictionary[String, Material] = {}
static var _clay_material: Material = null
## 빚은 메시 (v21): 같은 모델 · 같은 부품이면 다시 빚지 않고 나눠 쓴다 (세워 둔 탈것 · 배달 · 타는 탈것 · 친구).
## 실제 모양은 빚는 데 오래 걸려(수십 ms) 폰에서 끊기지 않게 한다. 오래된 것부터 버린다.
static var _mesh_cache: Dictionary[String, ArrayMesh] = {}
static var _cache_order: PackedStringArray = []
const MESH_CACHE_MAX: int = 64
## 이보다 먼 탈것 메시는 그리지 않는다 (m).
const DRAW_DISTANCE: float = 45.0


## 모양 만들기 (같은 모델 · 같은 부품이면 그대로 둔다).
func build(new_model: String, new_fit: Dictionary) -> void:
	var key: String = "%s|%s|%d" % [new_model, JSON.stringify(new_fit, "", true), int(PartMesh.detail * 10.0)]
	if key == _key:
		return
	_key = key
	model_id = new_model
	fit = new_fit.duplicate()
	info = GameData.garage.model(new_model)
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_pedals.clear()
	_crank = null
	_head_light = null
	_under_light = null
	_paddle = null
	_motor = null
	_steer = null
	_front_spin = null
	_rear_spin = null
	_car_spins.clear()
	_car_pivots.clear()
	if info == null:
		return
	if _clay_material == null:
		_clay_material = load("res://assets/materials/foliage.tres")
	_clay = _clay_material
	if info.kind == "bike":
		_build_bike()
	elif info.kind == "boat":
		_build_boat()
	elif info.kind == "car":
		_build_car()
	else:
		_build_moto()


## 바퀴(속도 m/s)를 굴리고 핸들을 조향 각도(rad, + = 왼쪽)로 돌린다. 크랭크는 set_pedal (리그 위상).
func animate(speed: float, steer: float, delta: float) -> void:
	if info == null:
		return
	if info.kind == "boat":
		_animate_boat(speed, steer, delta)
		return
	if info.kind == "car":
		_wheel_angle = fmod(_wheel_angle + speed * delta / maxf(info.wheel, 0.05), TAU)
		for spin: Node3D in _car_spins:
			spin.rotation.x = -_wheel_angle
		_steer_angle = lerpf(_steer_angle, clampf(steer, -0.5, 0.5), 1.0 - exp(-12.0 * delta))
		for pivot: Node3D in _car_pivots:
			pivot.rotation.y = _steer_angle * 1.2
		if _steer != null:
			_steer.basis = Basis(_steer_axis, _steer_angle * _wheel_turn)
		return
	var turn: float = speed * delta / maxf(info.wheel, 0.05)
	_wheel_angle = fmod(_wheel_angle + turn, TAU)
	if _front_spin != null:
		_front_spin.rotation.x = -_wheel_angle
	if _rear_spin != null:
		_rear_spin.rotation.x = -_wheel_angle
	set_pedal(pedal_phase)
	_steer_angle = lerpf(_steer_angle, clampf(steer, -0.5, 0.5), 1.0 - exp(-12.0 * delta))
	if _steer != null:
		_steer.basis = Basis(_steer_axis, _steer_angle)


## 크랭크 위상 (0~1, 0 = 왼발 페달이 맨 위, 앞으로 밟는 쪽으로 는다). 타는 캐릭터 리그의 pedal_phase 를 넣는다.
## 카약은 노 젓기 위상 (0 = 몸을 왼쪽으로 틀고 왼쪽 날이 물에, 0.5 = 오른쪽) — 리그 ride_kayak 과 같다.
func set_pedal(phase: float) -> void:
	pedal_phase = fposmod(phase, 1.0)
	if _paddle != null:
		var c: float = cos(pedal_phase * TAU)
		_paddle.rotation = Vector3(0.0, 0.32 * c, 0.5 * c)
	if _crank == null:
		return
	var a: float = pedal_phase * TAU
	_crank.rotation.x = -a
	for pedal: Node3D in _pedals:
		pedal.rotation.x = a


## 이 빠르기(m/s)에서 페달을 밟는 빠르기 (초당 바퀴 수, 기어비).
## 핸들 손잡이 자리 (월드, side -1 = 왼쪽 · 1 = 오른쪽). 핸들을 꺾으면 따라 돈다 (배달 로봇이 잡는다).
func grip(side: float) -> Vector3:
	var p: Vector3 = info.anchor("bar") + Vector3(side * 0.21, 0.02, 0.02) if info != null else Vector3(side * 0.21, 0.8, -0.3)
	if _steer != null:
		return _steer.global_transform * (p - _steer.position)
	return global_transform * p


func pedal_rate(speed: float) -> float:
	return speed / (TAU * maxf(info.wheel, 0.05)) / maxf(info.gear, 0.5) if info != null else 0.0


func _process(delta: float) -> void:
	if floating and info != null and info.kind == "boat":
		# 물 위에 세워 둔 보트: 물결에 천천히 출렁인다.
		_bob_t += delta
		position.y = sin(_bob_t * 1.6) * 0.025
		rotation.x = sin(_bob_t * 1.1) * 0.02
		rotation.z = sin(_bob_t * 1.3 + 1.0) * 0.03
	var night: float = SkyController.night_light
	if _head_light != null:
		_head_light.visible = night > 0.04 and lights_on
		_head_light.light_energy = _light_energy * night
	if _under_light != null:
		_under_light.visible = night > 0.04
		_under_light.light_energy = _under_energy * night


## 이 모양(_key)의 part 메시: 빚어 둔 게 있으면 그대로, 없으면 make 로 빚어 둔다.
func _cached(part: String, make: Callable) -> ArrayMesh:
	var k: String = "%s#%s" % [_key, part]
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var mesh: ArrayMesh = make.call()
	_mesh_cache[k] = mesh
	_cache_order.append(k)
	if _cache_order.size() > MESH_CACHE_MAX:
		_mesh_cache.erase(_cache_order[0])
		_cache_order.remove_at(0)
	return mesh


## 지금 끼운 그 칸 부품 (없으면 null).
func part_in(slot: String) -> VehicleCatalog.Part:
	return GameData.garage.part(str(fit.get(slot, "")))


func _color(slot: String, fallback: Color) -> Color:
	var p: VehicleCatalog.Part = part_in(slot)
	return p.color if p != null and p.color.a > 0.0 else fallback


func _paint() -> Color:
	return _color("paint", info.paint)


func _trim() -> Color:
	return _color("trim", info.trim)


func _seat_color() -> Color:
	var p: VehicleCatalog.Part = part_in("seat")
	return Color.html(str(p.seat.get("c", "#232326"))) if p != null else info.seat


func _tire() -> Dictionary:
	var p: VehicleCatalog.Part = part_in("tire")
	return p.tire if p != null else {}


func _light() -> Dictionary:
	var p: VehicleCatalog.Part = part_in("light")
	return p.light if p != null else STOCK_LIGHT


func _tail() -> Dictionary:
	var p: VehicleCatalog.Part = part_in("tail")
	return p.tail if p != null else STOCK_TAIL


func _glow() -> Dictionary:
	var p: VehicleCatalog.Part = part_in("glow")
	return p.glow if p != null else {}


## 둥근 면을 나누는 칸 수: 탈것은 가까이서 오래 보니 다른 소품보다 1.6배 촘촘히 (삼각형 예산보다 매끈함을 먼저).
func _seg(n: int) -> int:
	return maxi(6, roundi(float(n) * PartMesh.detail * 1.6))


## 크랭크 가운데 (타는 높이에 맞춘 페달 원의 가운데).
func _bb() -> Vector3:
	return Vector3(0.0, RIDER_HIP.y + info.lift + CRANK.x, RIDER_HIP.z + CRANK.y)


# ---- 자전거 ----

func _build_bike() -> void:
	var paint: Color = _paint()
	var trim: Color = _trim()
	var r: float = info.wheel
	var axle_f: Vector3 = info.anchor("axle_f")
	var axle_r: Vector3 = info.anchor("axle_r")
	var bar: Vector3 = info.anchor("bar")
	var seat: Vector3 = info.anchor("seat")
	var bb: Vector3 = _bb()
	var head_top: Vector3 = Vector3(0.0, bar.y - 0.08, bar.z - 0.1)
	var head_bottom: Vector3 = head_top + (axle_f - head_top).normalized() * 0.16
	var seat_top: Vector3 = Vector3(0.0, seat.y - 0.07, seat.z - 0.03)
	var rear_part: VehicleCatalog.Part = part_in("rear")
	var front_part: VehicleCatalog.Part = part_in("front")
	# 몸체: 실제 자전거 모양 (bike_parts — 프레임 · 체인 · 흙받이 · 짐받이 · 받침대) + 안장 + 끼운 부품.
	var points: Dictionary = {"head_top": head_top, "head_bottom": head_bottom, "bb": bb, "seat_top": seat_top, "seat": seat, "axle_r": axle_r, "axle_f": axle_f, "r": r}
	var seat_part: VehicleCatalog.Part = part_in("seat")
	_frame = _add_mesh("Frame", _cached("frame", func() -> ArrayMesh:
		var st: SurfaceTool = ClayMesh.begin()
		BikeKit.frame(st, info.style, paint, trim, points, rear_part != null and not rear_part.model.is_empty(), _seg(8))
		BikeKit.saddle(st, seat, info.style, _seat_color(), seat_part != null and str(seat_part.seat.get("shape", "")) == "wide")
		_add_body_parts(st)
		return ClayMesh.commit(st)), self)
	# 크랭크 · 페달 (돈다).
	_crank = Node3D.new()
	_crank.name = "Crank"
	_crank.position = bb
	add_child(_crank)
	_add_mesh("Mesh", _cached("crank", func() -> ArrayMesh:
		var cs: SurfaceTool = ClayMesh.begin()
		BikeKit.crank(cs, info.style, CRANK_R)
		return ClayMesh.commit(cs)), _crank)
	for side: float in [-1.0, 1.0]:
		var pedal: Node3D = Node3D.new()
		pedal.name = "PedalL" if side < 0.0 else "PedalR"
		pedal.position = Vector3(0.076 * side, -CRANK_R * side, 0.0)
		_crank.add_child(pedal)
		_add_mesh("Mesh", _cached("pedal%d" % int(side), func() -> ArrayMesh:
			var ps: SurfaceTool = ClayMesh.begin()
			BikeKit.pedal(ps, side, info.style)
			return ClayMesh.commit(ps)), pedal)
		_pedals.append(pedal)
	# 뒷바퀴.
	_rear_spin = _wheel_node("RearWheel", axle_r, self, false)
	# 핸들 쪽: 조향축(머리 관)으로 도는 마디 — 포크 · 앞바퀴 · 핸들 · 앞 장착 · 전조등.
	_steer = Node3D.new()
	_steer.name = "Steer"
	_steer.position = head_top
	_steer_axis = (head_top - axle_f).normalized()
	add_child(_steer)
	var to_local: Callable = func(v: Vector3) -> Vector3: return v - head_top
	var head: Vector3 = to_local.call(info.anchor("head"))
	var lens_r: float = 0.034 * float(_light().get("lens", 1.0))
	var q: Dictionary = {"head_bottom": to_local.call(head_bottom), "axle_f": to_local.call(axle_f), "bar": to_local.call(bar), "head": head, "front": to_local.call(info.anchor("front"))}
	_add_mesh("Mesh", _cached("steer", func() -> ArrayMesh:
		var ss: SurfaceTool = ClayMesh.begin()
		BikeKit.steer(ss, info.style, paint, trim, q, r, front_part != null and not front_part.model.is_empty(), _seg(8))
		BikeKit.lamp(ss, info.style, head, lens_r, trim)
		_add_steer_parts(ss, head_top)
		return ClayMesh.commit(ss)), _steer)
	_front_spin = _wheel_node("FrontWheel", to_local.call(axle_f), _steer, true)
	_add_head_glow(head, lens_r)
	_add_tail(info.anchor("tail"), 0.03)
	var glow: Dictionary = _glow()
	if str(glow.get("where", "")) == "frame":
		var gs: SurfaceTool = ClayMesh.begin()
		Shapes.sweep(gs, PackedVector3Array([head_bottom + Vector3(0.024, 0.0, 0.0), bb + Vector3(0.024, 0.03, 0.0)]), 0.006, LENS, 6, true)
		Shapes.sweep(gs, PackedVector3Array([bb + Vector3(0.05, 0.0, 0.0), axle_r + Vector3(0.06, 0.0, 0.0)]), 0.005, LENS, 6, true)
		_add_glow_mesh("FrameGlow", ClayMesh.commit(gs), self, Color.html(str(glow.get("c", "#FFFFFF"))), 1.1)


# ---- 차량 (v0.26) ----

func _build_car() -> void:
	var paint: Color = _paint()
	var trim: Color = _trim()
	var truck: bool = info.style == "truck"
	_frame = _add_mesh("Frame", _cached("frame", func() -> ArrayMesh:
		var st: SurfaceTool = ClayMesh.begin()
		CarKit.body(st, info.style, paint, trim, _seat_color(), _seg(6))
		return ClayMesh.commit(st)), self)
	# 네 바퀴: 앞바퀴는 꺾는 마디 안에서 돈다.
	var track: float = 0.7 if truck else 0.54
	var width: float = 0.24 if truck else 0.27
	var wheel: ArrayMesh = _cached("wheel", func() -> ArrayMesh:
		var ws: SurfaceTool = ClayMesh.begin()
		CarKit.wheel(ws, info.wheel, width, trim, _seg(10))
		return ClayMesh.commit(ws))
	for axle: String in ["axle_f", "axle_r"]:
		var at: Vector3 = info.anchor(axle)
		for side: float in [-1.0, 1.0]:
			var pivot: Node3D = Node3D.new()
			pivot.name = "Wheel%s%s" % ["F" if axle == "axle_f" else "R", "L" if side < 0.0 else "R"]
			pivot.position = Vector3(side * track, at.y, at.z)
			add_child(pivot)
			var spin: Node3D = Node3D.new()
			spin.name = "Spin"
			pivot.add_child(spin)
			_add_mesh("Mesh", wheel, spin)
			_car_spins.append(spin)
			if axle == "axle_f":
				_car_pivots.append(pivot)
	# 운전대 · 핸들 (조향 마디 — 배달 로봇 · 타는 사람의 손이 잡는다).
	_steer = Node3D.new()
	_steer.name = "Steer"
	_steer.position = info.anchor("bar")
	_steer_axis = Vector3(0.0, cos(PI * 0.5 - 0.5), sin(PI * 0.5 - 0.5)).normalized() if truck else Vector3.UP
	_wheel_turn = 4.0 if truck else 1.0
	add_child(_steer)
	_add_mesh("Mesh", _cached("steer", func() -> ArrayMesh:
		var ss: SurfaceTool = ClayMesh.begin()
		CarKit.steer(ss, info.style, trim)
		return ClayMesh.commit(ss)), _steer)
	var head: Vector3 = info.anchor("head")
	var spread: float = 0.55 if truck else 0.22
	_add_head_glow(head, 0.05, self, [head + Vector3(-spread, 0.0, 0.0), head + Vector3(spread, 0.0, 0.0)])
	var tail: Vector3 = info.anchor("tail")
	for side: float in [-1.0, 1.0]:
		_add_tail(tail + Vector3(side * (0.62 if truck else 0.36), 0.0, 0.0), 0.05)


# ---- 전기오토바이 ----

func _build_moto() -> void:
	var paint: Color = _paint()
	var trim: Color = _trim()
	var r: float = info.wheel
	var axle_f: Vector3 = info.anchor("axle_f")
	var axle_r: Vector3 = info.anchor("axle_r")
	var bar: Vector3 = info.anchor("bar")
	var head_top: Vector3 = Vector3(0.0, bar.y - 0.06, bar.z - 0.08)
	var seat_part: VehicleCatalog.Part = part_in("seat")
	var shape: String = str(seat_part.seat.get("shape", "")) if seat_part != null else ""
	# 몸체: 실제 전기 오토바이 모양 (moto_parts — 스쿠터 모노코크 · 카페 레이서 · 풀 카울 스포츠) + 끼운 부품.
	var points: Dictionary = {"axle_f": axle_f, "axle_r": axle_r, "head_top": head_top, "seat": info.anchor("seat"), "floor": info.anchor("floor"), "tail": info.anchor("tail"), "frame": info.anchor("frame"), "r": r}
	_frame = _add_mesh("Frame", _cached("frame", func() -> ArrayMesh:
		var st: SurfaceTool = ClayMesh.begin()
		MotoKit.body(st, info.style, paint, trim, _seat_color(), shape, points, _seg(8))
		_add_body_parts(st)
		return ClayMesh.commit(st)), self)
	_rear_spin = _wheel_node("RearWheel", axle_r, self, false)
	# 조향 마디: 앞 포크 · 앞바퀴 · 핸들 · 등 껍데기.
	_steer = Node3D.new()
	_steer.name = "Steer"
	_steer.position = head_top
	_steer_axis = (head_top - axle_f).normalized()
	add_child(_steer)
	var to_local: Callable = func(v: Vector3) -> Vector3: return v - head_top
	var head: Vector3 = to_local.call(info.anchor("head"))
	var lens_r: float = (0.045 if info.style == "scooter" else 0.058) * float(_light().get("lens", 1.0))
	var q: Dictionary = {"axle_f": to_local.call(axle_f), "bar": to_local.call(bar), "head": head}
	_add_mesh("Mesh", _cached("steer", func() -> ArrayMesh:
		var ss: SurfaceTool = ClayMesh.begin()
		MotoKit.steer(ss, info.style, paint, trim, q, r, lens_r, _seg(8))
		_add_steer_parts(ss, head_top)
		return ClayMesh.commit(ss)), _steer)
	_front_spin = _wheel_node("FrontWheel", to_local.call(axle_f), _steer, true)
	if info.style == "sport":
		# 스포츠: 두 눈 전조등은 돌지 않는 앞 카울에 있다.
		var nose: Node3D = Node3D.new()
		nose.name = "Nose"
		add_child(nose)
		_add_head_glow(Vector3(0.0, 0.6, -0.6), 0.024, nose, [Vector3(-0.055, 0.6, -0.62), Vector3(0.055, 0.6, -0.62)])
	else:
		_add_head_glow(head, lens_r)
	_add_tail(info.anchor("tail"), 0.045)
	var glow: Dictionary = _glow()
	if str(glow.get("where", "")) == "under":
		var color: Color = Color.html(str(glow.get("c", "#FFFFFF")))
		var gs: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_rounded_box(gs, Vector3(0.0, 0.12, (axle_f.z + axle_r.z) * 0.5), Vector3(0.12, 0.012, absf(axle_r.z - axle_f.z) * 0.55), 0.3, LENS, Basis(), _seg(6), 2)
		_add_glow_mesh("UnderGlow", ClayMesh.commit(gs), self, color, 1.2)
		_under_light = OmniLight3D.new()
		_under_light.name = "UnderLight"
		_under_light.light_color = color
		_under_light.omni_range = 1.7
		_under_light.position = Vector3(0.0, 0.1, (axle_f.z + axle_r.z) * 0.5)
		_under_light.shadow_enabled = false
		_under_energy = 2.2
		add_child(_under_light)


# ---- 보트 (v20) ----
# 수면이 y = 0 이다 (배 밑은 물에 잠긴다). 뱃머리 = -z.

func _build_boat() -> void:
	var paint: Color = _paint()
	var trim: Color = _trim()
	var seat_c: Color = _seat_color()
	_steer = Node3D.new()
	_steer.name = "Steer"
	add_child(_steer)
	var lens_r: float = 0.05 * float(_light().get("lens", 1.0))
	match info.style:
		"kayak":
			# 노 (리그의 노 젓기에 맞춰 돈다 · set_pedal).
			_paddle = Node3D.new()
			_paddle.name = "Paddle"
			_paddle.position = info.anchor("bar")
			add_child(_paddle)
			_add_mesh("PaddleMesh", _cached("paddle", func() -> ArrayMesh:
				var ps: SurfaceTool = ClayMesh.begin()
				BoatKit.paddle(ps, trim)
				return ClayMesh.commit(ps)), _paddle)
			_steer.position = info.anchor("head")
		"motor":
			# 운전대 (키를 돌리는 만큼 돈다 · _steer): 크롬 바퀴 · 세 살 · 가운데 손잡이.
			_steer.position = info.anchor("bar")
			_steer_axis = Basis(Vector3.RIGHT, deg_to_rad(-55.0)).y
			_add_mesh("Wheel", _cached("helm", func() -> ArrayMesh:
				var ws: SurfaceTool = ClayMesh.begin()
				var tilt: Basis = Basis(Vector3.RIGHT, deg_to_rad(35.0))
				ClayMesh.add_torus(ws, Vector3.ZERO, 0.13, 0.014, Shapes.chrome(), 28, 8, tilt)
				for k: int in 3:
					var a: float = TAU * float(k) / 3.0 + PI * 0.5
					Shapes.rod(ws, Vector3.ZERO, tilt * Vector3(cos(a) * 0.125, 0.0, sin(a) * 0.125), 0.008, Shapes.chrome(), 6)
				ClayMesh.add_lathe(ws, PackedVector2Array([Vector2(0.0, -0.02), Vector2(0.03, -0.02), Vector2(0.026, 0.02), Vector2(0.0, 0.022)]), 16, Transform3D(tilt, Vector3.ZERO), Shapes.gloss(DARK))
				Shapes.rod(ws, Vector3.ZERO, tilt * Vector3(0.0, -0.18, 0.0), 0.014, Shapes.gloss(DARK), 8)
				return ClayMesh.commit(ws)), _steer)
			# 선외기 (고물, 키 반대로 돈다).
			_motor = Node3D.new()
			_motor.name = "Outboard"
			_motor.position = Vector3(0.0, 0.42, 1.98)
			add_child(_motor)
			_add_mesh("OutboardMesh", _cached("outboard", func() -> ArrayMesh:
				var ms: SurfaceTool = ClayMesh.begin()
				BoatKit.outboard(ms, trim)
				return ClayMesh.commit(ms)), _motor)
			_steer_head = info.anchor("head")
		_:
			var bar: Vector3 = info.anchor("bar")
			var column: Vector3 = Vector3(0.0, 0.62, -0.62)
			_steer.position = column
			_steer_axis = (bar - column).normalized()
			_add_mesh("Bars", _cached("bars", func() -> ArrayMesh:
				var hs: SurfaceTool = ClayMesh.begin()
				BoatKit.jet_bars(hs, paint, bar - column)
				return ClayMesh.commit(hs)), _steer)
			_steer_head = info.anchor("head")
	# 선체 (boat_parts — 카약 · 낚시 스키프 · 수상오토바이) + 끼운 부품.
	_frame = _add_mesh("Frame", _cached("frame", func() -> ArrayMesh:
		var st: SurfaceTool = ClayMesh.begin()
		match info.style:
			"kayak":
				BoatKit.kayak(st, paint, trim, seat_c, _seg(8))
			"motor":
				BoatKit.skiff(st, paint, trim, seat_c, _seg(8))
			_:
				BoatKit.jetski(st, paint, trim, seat_c, _seg(8))
		_add_body_parts(st)
		var front: VehicleCatalog.Part = part_in("front")
		if front != null and not front.model.is_empty():
			_append_part(st, front, info.anchor(front.anchor), Vector3.ZERO)
		return ClayMesh.commit(st)), self)
	# 앞 등 (조향 마디가 아니라 뱃머리에 고정).
	var light_holder: Node3D = _steer
	if info.style != "kayak":
		light_holder = Node3D.new()
		light_holder.name = "Bow"
		light_holder.position = _steer_head
		add_child(light_holder)
	var keep: Node3D = _steer
	_steer = light_holder
	_add_head_glow(Vector3.ZERO, lens_r)
	_steer = keep if info.style != "kayak" else null
	_add_tail(info.anchor("tail"), 0.04)
	var glow: Dictionary = _glow()
	if str(glow.get("where", "")) == "under":
		var color: Color = Color.html(str(glow.get("c", "#FFFFFF")))
		var gs: SurfaceTool = ClayMesh.begin()
		var half_len: float = absf(info.anchor("axle_r").z - info.anchor("axle_f").z) * 0.4
		for side3: float in [-1.0, 1.0]:
			ClayMesh.add_rounded_box(gs, Vector3(side3 * (0.3 if info.style == "kayak" else (0.8 if info.style == "motor" else 0.46)), 0.06, 0.1), Vector3(0.02, 0.02, half_len * 2.0), 0.3, LENS, Basis(), _seg(6), 2)
		_add_glow_mesh("UnderGlow", ClayMesh.commit(gs), self, color, 1.4)
		_under_light = OmniLight3D.new()
		_under_light.name = "UnderLight"
		_under_light.light_color = color
		_under_light.omni_range = 2.2
		_under_light.position = Vector3(0.0, 0.02, 0.1)
		_under_light.shadow_enabled = false
		_under_energy = 2.4
		add_child(_under_light)
	# 타는 사람(모형 원점)이 앉는 자리가 의자 위에 오게 배 전체를 앞뒤로 민다 (자전거처럼 안장 ≈ 원점).
	var hull_node: Node3D = Node3D.new()
	hull_node.name = "Hull"
	hull_node.position = Vector3(0.0, 0.0, -info.anchor("seat").z)
	for c: Node in get_children():
		remove_child(c)
		hull_node.add_child(c)
	add_child(hull_node)


## 보트: 키를 돌리는 만큼 운전대 · 핸들이 돌고 선외기가 반대로, 달리면 고물 뒤로 물보라.
func _animate_boat(speed: float, steer: float, delta: float) -> void:
	_steer_angle = lerpf(_steer_angle, clampf(steer, -0.5, 0.5), 1.0 - exp(-8.0 * delta))
	if _steer != null:
		_steer.basis = Basis(_steer_axis, _steer_angle * (3.0 if info.style == "motor" else 1.0))
	if _motor != null:
		_motor.rotation.y = -_steer_angle * 1.2
	if speed > 0.7 and is_inside_tree():
		_wake_left -= delta
		if _wake_left <= 0.0:
			_wake_left = clampf(0.3 - speed * 0.015, 0.08, 0.3)
			var stern: Vector3 = global_transform * Vector3(0.0, 0.05, info.anchor("axle_r").z - info.anchor("seat").z + 0.1)
			Puff.burst(get_tree().current_scene, stern, Color(0.92, 0.97, 1.0, 0.85), 2 + int(speed / 4.0), 0.35 + speed * 0.03, 0.18 + speed * 0.02, 0.08 + speed * 0.006, 0.6)


# ---- 공용 ----

## 바퀴 (축 = X): 타이어 · 림 · 바퀴살(자전거) 또는 휠 살(오토바이) · 허브. 바퀴살 LED 가 있으면 빛 고리.
func _wheel_node(node_name: String, at: Vector3, parent: Node3D, front: bool) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	holder.position = at
	parent.add_child(holder)
	var spin: Node3D = Node3D.new()
	spin.name = "Spin"
	holder.add_child(spin)
	var r: float = info.wheel
	var tire: Dictionary = _tire()
	var bike: bool = info.kind == "bike"
	var axis: Basis = Basis(Vector3.BACK, PI * 0.5)
	var trim: Color = _trim()
	var rim_r: float
	if bike:
		rim_r = r - BikeKit.tire_width(info.style, tire) * 0.92 - 0.02
	else:
		rim_r = r - MotoKit.tire_width(info.style, not front, tire) * 0.82 * 0.92 - 0.02
	_add_mesh("Mesh", _cached("wheel_f" if front else "wheel_r", func() -> ArrayMesh:
		var ws: SurfaceTool = ClayMesh.begin()
		if bike:
			# 실제 자전거 바퀴: 타이어 · 림 · 허브 · 엇갈린 바퀴살 (MTB · 로드는 디스크 원판, 뒤는 스프로킷).
			BikeKit.wheel(ws, r, info.style, tire, trim, not front, info.style == "mtb" or info.style == "road", _seg(8))
		else:
			# 실제 오토바이 바퀴: 둥근 타이어 · 림 · 휠(스쿠터 5 살 · 클래식 철사살 · 스포츠 Y 살) · 디스크 · 허브 모터.
			MotoKit.wheel(ws, r, info.style, tire, trim, not front, _seg(8))
		return ClayMesh.commit(ws)), spin)
	var glow: Dictionary = _glow()
	if str(glow.get("where", "")) == "spoke":
		var gs: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_torus(gs, Vector3.ZERO, rim_r * 0.62, 0.008, LENS, _seg(16), 3, axis)
		for i: int in 4:
			var a: float = TAU * float(i) / 4.0 + 0.4
			ClayMesh.add_ellipsoid(gs, Vector3(0.0, cos(a), sin(a)) * rim_r * 0.82, Vector3(0.012, 0.02, 0.02), LENS, 6, 3)
		_add_glow_mesh("SpokeGlow", ClayMesh.commit(gs), spin, Color.html(str(glow.get("c", "#FFFFFF"))), 1.1)
	return spin


## 몸체에 붙는 부품 (뒤 장착 · 장식 · 구동 키트 · 줄무늬).
func _add_body_parts(st: SurfaceTool) -> void:
	for slot: String in ["rear", "deco", "drive"]:
		var p: VehicleCatalog.Part = part_in(slot)
		if p == null or p.model.is_empty() or p.anchor in ["bar", "front", "head"]:
			continue
		_append_part(st, p, info.anchor(p.anchor), Vector3.ZERO)
	var deco: VehicleCatalog.Part = part_in("deco")
	if deco != null and not deco.paint2.is_empty():
		var c: Color = _trim()
		var frame: Vector3 = info.anchor("frame")
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_rounded_box(st, frame + Vector3(0.035 * side if info.kind == "bike" else 0.105 * side, 0.0, 0.0), Vector3(0.006, 0.03, 0.34), 0.3, c, Basis(), 6, 2)


## 핸들 쪽에 붙는 부품 (앞 장착 · 핸들 장식). origin = 조향 마디 자리.
func _add_steer_parts(st: SurfaceTool, origin: Vector3) -> void:
	for slot: String in ["front", "deco"]:
		var p: VehicleCatalog.Part = part_in(slot)
		if p == null or p.model.is_empty() or not p.anchor in ["bar", "front", "head"]:
			continue
		_append_part(st, p, info.anchor(p.anchor), origin)


## 부품 도형을 anchor 자리로 옮기고 색 자리($paint · $trim · $seat)를 채워 붙인다.
func _append_part(st: SurfaceTool, p: VehicleCatalog.Part, anchor: Vector3, origin: Vector3) -> void:
	var colors: Dictionary[String, String] = {"$paint": "#" + _paint().to_html(false), "$trim": "#" + _trim().to_html(false), "$seat": "#" + _seat_color().to_html(false)}
	var shifted: Array = []
	var off: Vector3 = anchor - origin
	for raw: Variant in p.model:
		if not raw is Dictionary:
			continue
		var d: Dictionary = (raw as Dictionary).duplicate(true)
		for key: String in ["at", "to"]:
			var v: Variant = d.get(key)
			if v is Array and v.size() >= 3:
				d[key] = [float(v[0]) + off.x, float(v[1]) + off.y, float(v[2]) + off.z]
		var c: Variant = d.get("c")
		if c is String and colors.has(c):
			d["c"] = colors[c]
		shifted.append(d)
	PartMesh.append(st, shifted)


func _add_mesh(node_name: String, mesh: ArrayMesh, parent: Node3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _clay
	# 실제 모양 (v21) 은 탈것 하나에 2만 삼각형 남짓 — 멀리 세워 둔 것은 그리지 않는다.
	mi.visibility_range_end = DRAW_DISTANCE
	parent.add_child(mi)
	return mi


## 밤에 빛나는 도형 (같은 셰이더 toon_world 에 emission 색만 다른 머티리얼, 색마다 하나).
func _add_glow_mesh(node_name: String, mesh: ArrayMesh, parent: Node3D, color: Color, energy: float) -> MeshInstance3D:
	var mi: MeshInstance3D = _add_mesh(node_name, mesh, parent)
	mi.material_override = glow_material(color, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func glow_material(color: Color, energy: float) -> Material:
	var key: String = "%s|%.2f" % [color.to_html(false), energy]
	if _glow_materials.has(key):
		return _glow_materials[key]
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(PartMesh.TOON_SHADER)
	m.set_shader_parameter("albedo", Color(1, 1, 1).lerp(color, 0.25) if color.s < 0.3 else color.lightened(0.15))
	m.set_shader_parameter("emission", color)
	m.set_shader_parameter("emission_energy", energy)
	_glow_materials[key] = m
	return m


## 전조등 렌즈 (조향 마디 안) + 밤에 앞을 비추는 SpotLight.
## parent 가 없으면 조향 마디에 단다. lenses 가 있으면 그 자리마다 렌즈 (두 눈 전조등).
func _add_head_glow(head: Vector3, lens_r: float, parent: Node3D = null, lenses: Array = []) -> void:
	var holder: Node3D = parent if parent != null else _steer
	var light: Dictionary = _light()
	var color: Color = Color.html(str(light.get("color", "#FFF4DC")))
	var gs: SurfaceTool = ClayMesh.begin()
	if lenses.is_empty():
		ClayMesh.add_ellipsoid(gs, head + Vector3(0.0, 0.0, -0.035), Vector3(lens_r, lens_r, lens_r * 0.35), LENS, _seg(10), 4)
	else:
		for at: Variant in lenses:
			ClayMesh.add_ellipsoid(gs, (at as Vector3) + Vector3(0.0, 0.0, -0.004), Vector3(lens_r * 1.5, lens_r * 0.7, lens_r * 0.5), LENS, _seg(10), 4)
	if bool(light.get("drl", false)):
		ClayMesh.add_torus(gs, head + Vector3(0.0, 0.0, -0.04), lens_r + 0.008, 0.007, LENS, _seg(14), 3, Basis(Vector3.RIGHT, PI * 0.5))
	_add_glow_mesh("HeadGlow", ClayMesh.commit(gs), holder, color, 1.6 + float(light.get("energy", 1.0)))
	_head_light = SpotLight3D.new()
	_head_light.name = "HeadLight"
	_head_light.light_color = color
	_head_light.spot_range = float(light.get("range", 6.0))
	_head_light.spot_angle = float(light.get("angle", 34.0))
	_head_light.spot_attenuation = 0.8
	_head_light.shadow_enabled = false
	_head_light.position = head + Vector3(0.0, 0.0, -0.06)
	# 앞 아래로 살짝 숙여 길을 비춘다.
	_head_light.rotation = Vector3(deg_to_rad(-9.0), 0.0, 0.0)
	_light_energy = float(light.get("energy", 1.0)) * 1.6
	holder.add_child(_head_light)


func _add_tail(at: Vector3, size: float) -> void:
	var tail: Dictionary = _tail()
	var k: float = float(tail.get("size", 1.0))
	var ts: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rounded_box(ts, at, Vector3(size * 1.4 * k, size * 0.7, size * 0.5), 0.5, TAIL.lightened(0.3), Basis(), 8, 3)
	_add_glow_mesh("TailGlow", ClayMesh.commit(ts), self, TAIL, float(tail.get("energy", 1.4)))
