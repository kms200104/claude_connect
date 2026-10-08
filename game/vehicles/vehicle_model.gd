class_name VehicleModel
extends Node3D
## 차고 탈것 모형 (v19): 자전거 · 전기오토바이를 모델(style)과 끼운 부품(fit)대로 점토 도형으로 빚는다.
## 원점 = 바닥(두 바퀴 사이), 앞 = -Z. 타는 캐릭터의 리그 자세(ride_bike · ride_moto)에 맞춘 자리(anchors)를 쓴다.
## 나뉜 마디: 몸체(Frame) · 앞바퀴와 핸들(Steer, 조향축으로 돈다) · 뒷바퀴 · 크랭크와 페달(자전거) · 빛나는 렌즈와 장식.
## animate(속도, 조향, delta) 로 바퀴 · 크랭크 · 핸들을 돌린다. 밤(night_light)에는 전조등(SpotLight)과 언더글로우가 켜진다.

const METAL: Color = Color("#9AA0A8")
const DARK: Color = Color("#2A2A2E")
const RUBBER: Color = Color("#232326")
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

static var _glow_materials: Dictionary[String, Material] = {}
static var _clay_material: Material = null


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
	if info == null:
		return
	if _clay_material == null:
		_clay_material = load("res://assets/materials/foliage.tres")
	_clay = _clay_material
	if info.kind == "bike":
		_build_bike()
	else:
		_build_moto()


## 바퀴(속도 m/s)를 굴리고 핸들을 조향 각도(rad, + = 왼쪽)로 돌린다. 크랭크는 set_pedal (리그 위상).
func animate(speed: float, steer: float, delta: float) -> void:
	if info == null:
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
func set_pedal(phase: float) -> void:
	pedal_phase = fposmod(phase, 1.0)
	if _crank == null:
		return
	var a: float = pedal_phase * TAU
	_crank.rotation.x = -a
	for pedal: Node3D in _pedals:
		pedal.rotation.x = a


## 이 빠르기(m/s)에서 페달을 밟는 빠르기 (초당 바퀴 수, 기어비).
func pedal_rate(speed: float) -> float:
	return speed / (TAU * maxf(info.wheel, 0.05)) / maxf(info.gear, 0.5) if info != null else 0.0


func _process(_delta: float) -> void:
	var night: float = SkyController.night_light
	if _head_light != null:
		_head_light.visible = night > 0.04 and lights_on
		_head_light.light_energy = _light_energy * night
	if _under_light != null:
		_under_light.visible = night > 0.04
		_under_light.light_energy = _under_energy * night


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
	var tube: float = 0.026 if info.style != "road" else 0.03
	var st: SurfaceTool = ClayMesh.begin()
	var seat_top: Vector3 = Vector3(0.0, seat.y - 0.07, seat.z - 0.03)
	match info.style:
		"city":
			# 낮게 휜 앞 관(스텝스루) + 뒷바퀴 흙받이 · 체인 덮개.
			var mid: Vector3 = Vector3(0.0, bb.y + 0.05, (head_bottom.z + bb.z) * 0.5 + 0.02)
			ClayMesh.add_capsule(st, head_bottom, mid, tube, paint, _seg(8), 2)
			ClayMesh.add_capsule(st, mid, bb, tube, paint, _seg(8), 2)
			ClayMesh.add_capsule(st, head_top + Vector3(0.0, -0.06, 0.0), mid + Vector3(0.0, 0.04, -0.06), tube * 0.8, paint, _seg(8), 2)
			_arc(st, axle_r, r + 0.03, -20.0, 150.0, 12, 0.02, 0.075, paint)
			ClayMesh.add_rounded_box(st, Vector3(0.06, bb.y + 0.02, (bb.z + axle_r.z) * 0.5 - 0.04), Vector3(0.025, 0.12, 0.42), 0.4, paint.darkened(0.15), Basis(), _seg(8), 4)
		"mini":
			ClayMesh.add_capsule(st, head_top + Vector3(0.0, -0.04, 0.0), seat_top + Vector3(0.0, -0.08, 0.0), tube * 1.1, paint, _seg(8), 2)
			ClayMesh.add_capsule(st, head_bottom, bb, tube, paint, _seg(8), 2)
			_arc(st, axle_r, r + 0.045, -10.0, 150.0, 11, 0.02, 0.06, trim)
		"mtb":
			var tt: Vector3 = seat_top + Vector3(0.0, -0.06, -0.02)
			ClayMesh.add_capsule(st, head_top + Vector3(0.0, -0.03, 0.0), tt, tube * 1.15, paint, _seg(8), 2)
			ClayMesh.add_capsule(st, head_bottom, bb, tube * 1.35, paint, _seg(8), 2)
			# 앞 서스펜션 (굵은 포크 다리는 핸들 쪽에서 만든다) · 뒤 쇼크.
			ClayMesh.add_capsule(st, tt + Vector3(0.0, -0.02, 0.02), Vector3(0.0, axle_r.y + 0.12, axle_r.z - 0.12), 0.022, DARK, _seg(6), 2)
		_:
			# 로드: 수평에 가까운 위 관 + 굵은 아래 관 (에어로).
			ClayMesh.add_capsule(st, head_top + Vector3(0.0, -0.02, 0.0), seat_top + Vector3(0.0, -0.04, 0.0), tube, paint, _seg(8), 2)
			ClayMesh.add_rounded_box(st, (head_bottom + bb) * 0.5, Vector3(0.05, 0.06, head_bottom.distance_to(bb) + 0.03), 0.5, paint, _basis_z(bb - head_bottom), _seg(8), 4)
	# 머리 관 · 안장 관 · 체인 · 시트 스테이 (모든 자전거).
	ClayMesh.add_rod(st, head_bottom, head_top, tube * 1.25, tube * 1.25, paint, _seg(8))
	ClayMesh.add_capsule(st, bb, seat_top, tube, paint, _seg(8), 2)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(st, bb + Vector3(0.03 * side, 0.0, 0.0), axle_r + Vector3(0.045 * side, 0.0, 0.0), tube * 0.6, paint, _seg(6), 2)
		ClayMesh.add_capsule(st, seat_top + Vector3(0.02 * side, -0.02, 0.0), axle_r + Vector3(0.045 * side, 0.0, 0.0), tube * 0.55, paint, _seg(6), 2)
	ClayMesh.add_rod(st, bb + Vector3(-0.045, 0.0, 0.0), bb + Vector3(0.045, 0.0, 0.0), 0.03, 0.03, DARK, _seg(8))
	# 안장 · 안장 기둥.
	ClayMesh.add_rod(st, seat_top, seat + Vector3(0.0, -0.02, 0.0), 0.014, 0.014, METAL, _seg(6))
	_saddle(st, seat)
	# 받침대.
	ClayMesh.add_rod(st, bb + Vector3(-0.05, -0.01, 0.06), bb + Vector3(-0.13, -bb.y + 0.02, 0.16), 0.01, 0.008, DARK, _seg(5))
	_add_body_parts(st)
	_frame = _add_mesh("Frame", ClayMesh.commit(st), self)
	# 크랭크 · 페달 (돈다).
	_crank = Node3D.new()
	_crank.name = "Crank"
	_crank.position = bb
	add_child(_crank)
	var cs: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_torus(cs, Vector3(0.055, 0.0, 0.0), 0.07, 0.008, METAL, _seg(12), 4, Basis(Vector3.BACK, PI * 0.5))
	ClayMesh.add_rod(cs, Vector3(0.065, 0.0, 0.0), Vector3(0.075, CRANK_R, 0.0), 0.01, 0.009, DARK, _seg(5))
	ClayMesh.add_rod(cs, Vector3(-0.065, 0.0, 0.0), Vector3(-0.075, -CRANK_R, 0.0), 0.01, 0.009, DARK, _seg(5))
	_add_mesh("Mesh", ClayMesh.commit(cs), _crank)
	for side: float in [-1.0, 1.0]:
		var pedal: Node3D = Node3D.new()
		pedal.name = "PedalL" if side < 0.0 else "PedalR"
		pedal.position = Vector3(0.1 * side, -CRANK_R * side, 0.0)
		_crank.add_child(pedal)
		var ps: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_rounded_box(ps, Vector3.ZERO, Vector3(0.07, 0.016, 0.05), 0.3, DARK, Basis(), _seg(6), 3)
		_add_mesh("Mesh", ClayMesh.commit(ps), pedal)
		_pedals.append(pedal)
	# 뒷바퀴.
	_rear_spin = _wheel_node("RearWheel", axle_r, self, false)
	# 핸들 쪽: 조향축(머리 관)으로 도는 마디 — 포크 · 앞바퀴 · 핸들 · 앞 장착 · 전조등.
	_steer = Node3D.new()
	_steer.name = "Steer"
	_steer.position = head_top
	_steer_axis = (head_top - axle_f).normalized()
	add_child(_steer)
	var ss: SurfaceTool = ClayMesh.begin()
	var to_local: Callable = func(v: Vector3) -> Vector3: return v - head_top
	var fork_w: float = 0.022 if info.style != "mtb" else 0.03
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(ss, to_local.call(head_bottom + Vector3(0.03 * side, 0.0, 0.0)), to_local.call(axle_f + Vector3(0.045 * side, 0.0, 0.0)), fork_w * (0.8 if info.style == "road" else 1.0), trim if info.style != "mtb" else DARK, _seg(6), 2)
	ClayMesh.add_rod(ss, Vector3.ZERO, to_local.call(bar), 0.016, 0.016, METAL, _seg(6))
	var grip_z: float = 0.03
	if info.style == "road":
		# 드롭 바: 앞으로 굽었다가 아래로 말린다.
		for side: float in [-1.0, 1.0]:
			var a: Vector3 = to_local.call(bar + Vector3(0.0, 0.0, 0.0))
			var b: Vector3 = to_local.call(bar + Vector3(0.2 * side, 0.0, 0.0))
			var c: Vector3 = to_local.call(bar + Vector3(0.24 * side, -0.02, -0.08))
			var d: Vector3 = to_local.call(bar + Vector3(0.25 * side, -0.1, -0.02))
			ClayMesh.add_capsule(ss, a, b, 0.013, trim, _seg(6), 2)
			ClayMesh.add_capsule(ss, b, c, 0.014, RUBBER, _seg(6), 2)
			ClayMesh.add_capsule(ss, c, d, 0.014, RUBBER, _seg(6), 2)
			ClayMesh.add_capsule(ss, b, to_local.call(bar + Vector3(0.31 * side, 0.0, grip_z)), 0.016, RUBBER, _seg(6), 2)
	else:
		var sweep: float = 0.05 if info.style == "city" else 0.02
		for side: float in [-1.0, 1.0]:
			var mid: Vector3 = to_local.call(bar + Vector3(0.18 * side, 0.01, 0.0))
			ClayMesh.add_capsule(ss, Vector3(0.0, bar.y - head_top.y, bar.z - head_top.z), mid, 0.013, trim, _seg(6), 2)
			ClayMesh.add_capsule(ss, mid, to_local.call(bar + Vector3(0.33 * side, 0.01, sweep)), 0.019, RUBBER if info.style != "city" else Color("#7A4E30"), _seg(6), 2)
	if info.style == "city" or info.style == "mini":
		_arc(ss, to_local.call(axle_f), r + 0.03, 30.0, 175.0, 10, 0.02, 0.075, paint if info.style == "city" else trim)
	# 전조등 갓.
	var head: Vector3 = to_local.call(info.anchor("head"))
	var lens_r: float = 0.04 * float(_light().get("lens", 1.0))
	ClayMesh.add_rod(ss, head + Vector3(0.0, 0.0, 0.03), head + Vector3(0.0, 0.0, -0.035), lens_r + 0.012, lens_r + 0.008, trim, _seg(10))
	ClayMesh.add_rod(ss, head + Vector3(0.0, 0.0, 0.04), to_local.call(bar) + Vector3(0.0, -0.02, 0.0), 0.008, 0.008, METAL, _seg(5))
	_add_steer_parts(ss, head_top)
	_add_mesh("Mesh", ClayMesh.commit(ss), _steer)
	_front_spin = _wheel_node("FrontWheel", to_local.call(axle_f), _steer, true)
	_add_head_glow(head, lens_r)
	_add_tail(info.anchor("tail"), 0.035)
	var glow: Dictionary = _glow()
	if str(glow.get("where", "")) == "frame":
		var gs: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_capsule(gs, head_bottom + Vector3(0.03, 0.0, 0.0), bb + Vector3(0.03, 0.03, 0.0), 0.008, LENS, _seg(5), 2)
		ClayMesh.add_capsule(gs, bb + Vector3(0.05, 0.0, 0.0), axle_r + Vector3(0.06, 0.0, 0.0), 0.007, LENS, _seg(5), 2)
		_add_glow_mesh("FrameGlow", ClayMesh.commit(gs), self, Color.html(str(glow.get("c", "#FFFFFF"))), 1.1)


## 안장 (seat 부품 모양: soft · wide · 로드는 좁고 길게).
func _saddle(st: SurfaceTool, at: Vector3) -> void:
	var c: Color = _seat_color()
	var p: VehicleCatalog.Part = part_in("seat")
	var shape: String = str(p.seat.get("shape", "")) if p != null else ""
	var w: float = 0.075
	if shape == "wide" or info.style == "city":
		w = 0.1
	elif info.style == "road":
		w = 0.06
	ClayMesh.add_ellipsoid(st, at + Vector3(0.0, 0.0, 0.03), Vector3(w, 0.028, 0.08), c, _seg(10), 5)
	ClayMesh.add_ellipsoid(st, at + Vector3(0.0, 0.004, -0.06), Vector3(w * 0.45, 0.022, 0.07), c, _seg(8), 4)


# ---- 전기오토바이 ----

func _build_moto() -> void:
	var paint: Color = _paint()
	var trim: Color = _trim()
	var r: float = info.wheel
	var axle_f: Vector3 = info.anchor("axle_f")
	var axle_r: Vector3 = info.anchor("axle_r")
	var bar: Vector3 = info.anchor("bar")
	var seat: Vector3 = info.anchor("seat")
	var floor_at: Vector3 = info.anchor("floor")
	var head_top: Vector3 = Vector3(0.0, bar.y - 0.06, bar.z - 0.08)
	var st: SurfaceTool = ClayMesh.begin()
	match info.style:
		"scooter":
			# 넓은 발판 · 다리 가림판 · 뒷바퀴를 덮는 둥근 몸통.
			ClayMesh.add_rounded_box(st, Vector3(0.0, floor_at.y - 0.02, floor_at.z), Vector3(0.27, 0.06, 0.5), 0.35, trim.darkened(0.3), Basis(), _seg(10), 4)
			ClayMesh.add_rounded_box(st, Vector3(0.0, floor_at.y + 0.22, -0.4), Vector3(0.3, 0.5, 0.09), 0.45, paint, Basis(Vector3.RIGHT, deg_to_rad(-16.0)), _seg(12), 6)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.36, axle_r.z - 0.04), Vector3(0.16, 0.17, 0.32), paint, _seg(12), 7)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.3, axle_r.z + 0.12), Vector3(0.12, 0.12, 0.2), paint.darkened(0.08), _seg(10), 5)
			_arc(st, axle_r, r + 0.03, -10.0, 60.0, 5, 0.03, 0.12, DARK)
			# 허브 모터 · 스윙암.
			ClayMesh.add_rounded_box(st, Vector3(0.09, axle_r.y + 0.03, axle_r.z - 0.16), Vector3(0.05, 0.08, 0.34), 0.4, DARK, Basis(), _seg(8), 4)
		"classic":
			# 둥근 탱크(무릎 사이) · 배터리 상자 · 관 프레임 · 둥근 흙받이.
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.5, -0.2), Vector3(0.085, 0.075, 0.18), paint, _seg(12), 6)
			ClayMesh.add_torus(st, Vector3(0.0, 0.52, -0.2), 0.07, 0.008, trim, _seg(12), 4, Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.BACK, 0.0))
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.33, -0.12), Vector3(0.15, 0.17, 0.32), 0.3, DARK, Basis(), _seg(10), 4)
			ClayMesh.add_capsule(st, head_top + Vector3(0.0, -0.08, 0.0), Vector3(0.0, 0.47, 0.2), 0.024, DARK, _seg(6), 2)
			ClayMesh.add_capsule(st, head_top + Vector3(0.0, -0.14, 0.0), Vector3(0.0, 0.24, -0.06), 0.026, DARK, _seg(6), 2)
			ClayMesh.add_capsule(st, Vector3(0.0, 0.24, -0.06), Vector3(0.0, 0.26, 0.24), 0.026, DARK, _seg(6), 2)
			_arc(st, axle_r, r + 0.05, -30.0, 130.0, 10, 0.03, 0.1, paint)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_capsule(st, Vector3(0.07 * side, 0.27, 0.22), axle_r + Vector3(0.07 * side, 0.0, 0.0), 0.02, DARK, _seg(6), 2)
				ClayMesh.add_capsule(st, Vector3(0.07 * side, 0.46, 0.34), axle_r + Vector3(0.07 * side, 0.02, 0.0), 0.016, METAL, _seg(6), 2)
		_:
			# 스포츠: 날렵한 옆 카울 · 꼬리 카울 · 아래 배터리 · 스윙암.
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.4, -0.22), Vector3(0.2, 0.26, 0.5), 0.55, paint, Basis(Vector3.RIGHT, deg_to_rad(-8.0)), _seg(12), 6)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.52, -0.2), Vector3(0.07, 0.06, 0.16), paint.lightened(0.08), _seg(10), 5)
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.28, -0.08), Vector3(0.15, 0.13, 0.36), 0.35, DARK, Basis(), _seg(10), 4)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.5, axle_r.z + 0.05), Vector3(0.09, 0.07, 0.28), paint, _seg(12), 6, Basis(Vector3.RIGHT, deg_to_rad(10.0)))
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.4, 0.42), Vector3(0.06, 0.06, 0.3), 0.4, trim, Basis(), _seg(8), 4)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_rounded_box(st, Vector3(0.075 * side, axle_r.y + 0.04, (axle_r.z + 0.05) * 0.5), Vector3(0.03, 0.06, axle_r.z - 0.02), 0.4, trim, Basis(), _seg(8), 3)
	# 발판 받침 (클래식 · 스포츠는 발 받침대).
	if info.style != "scooter":
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_rod(st, Vector3(0.05 * side, floor_at.y, floor_at.z), Vector3(0.13 * side, floor_at.y, floor_at.z), 0.014, 0.014, METAL, _seg(5))
	# 시트.
	_moto_seat(st, seat)
	# 뒤 흙받이 · 번호판.
	ClayMesh.add_rounded_box(st, info.anchor("tail") + Vector3(0.0, -0.08, 0.05), Vector3(0.12, 0.07, 0.01), 0.2, Color("#F2EEE4"), Basis(Vector3.RIGHT, deg_to_rad(-15.0)), _seg(6), 3)
	_add_body_parts(st)
	_frame = _add_mesh("Frame", ClayMesh.commit(st), self)
	_rear_spin = _wheel_node("RearWheel", axle_r, self, false)
	# 조향 마디: 앞 포크 · 앞바퀴 · 핸들 · 전조등.
	_steer = Node3D.new()
	_steer.name = "Steer"
	_steer.position = head_top
	_steer_axis = (head_top - axle_f).normalized()
	add_child(_steer)
	var ss: SurfaceTool = ClayMesh.begin()
	var to_local: Callable = func(v: Vector3) -> Vector3: return v - head_top
	for side: float in [-1.0, 1.0]:
		var top_at: Vector3 = to_local.call(head_top + (axle_f - head_top) * 0.25 + Vector3(0.06 * side, 0.0, 0.0))
		var low_at: Vector3 = to_local.call(axle_f + Vector3(0.065 * side, 0.0, 0.0))
		ClayMesh.add_capsule(ss, top_at, low_at.lerp(top_at, 0.45), 0.03, METAL if info.style != "sport" else Color("#D8B060"), _seg(6), 2)
		ClayMesh.add_capsule(ss, low_at.lerp(top_at, 0.45), low_at, 0.036, DARK, _seg(6), 2)
	ClayMesh.add_rod(ss, Vector3.ZERO, to_local.call(head_top + (axle_f - head_top) * 0.25), 0.03, 0.03, DARK, _seg(6))
	ClayMesh.add_rod(ss, to_local.call(head_top + (axle_f - head_top) * 0.25) + Vector3(-0.07, 0.0, 0.0), to_local.call(head_top + (axle_f - head_top) * 0.25) + Vector3(0.07, 0.0, 0.0), 0.022, 0.022, DARK, _seg(6))
	ClayMesh.add_rod(ss, Vector3.ZERO, to_local.call(bar), 0.02, 0.02, METAL, _seg(6))
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(ss, to_local.call(bar), to_local.call(bar + Vector3(0.24 * side, 0.0, 0.01)), 0.016, METAL if info.style == "classic" else DARK, _seg(6), 2)
		ClayMesh.add_capsule(ss, to_local.call(bar + Vector3(0.24 * side, 0.0, 0.01)), to_local.call(bar + Vector3(0.34 * side, 0.0, 0.03)), 0.022, RUBBER, _seg(6), 2)
		# 브레이크 레버.
		ClayMesh.add_capsule(ss, to_local.call(bar + Vector3(0.2 * side, 0.01, -0.03)), to_local.call(bar + Vector3(0.32 * side, 0.0, -0.05)), 0.007, METAL, _seg(4), 1)
	if info.style == "scooter":
		# 핸들 덮개 · 계기판.
		ClayMesh.add_rounded_box(ss, to_local.call(bar + Vector3(0.0, -0.01, -0.03)), Vector3(0.3, 0.08, 0.14), 0.5, paint, Basis(), _seg(10), 4)
		ClayMesh.add_rounded_box(ss, to_local.call(bar + Vector3(0.0, 0.035, 0.0)), Vector3(0.11, 0.015, 0.07), 0.4, DARK, Basis(Vector3.RIGHT, deg_to_rad(-20.0)), _seg(8), 3)
	else:
		ClayMesh.add_rod(ss, to_local.call(bar + Vector3(0.0, 0.02, 0.02)), to_local.call(bar + Vector3(0.0, 0.07, 0.04)), 0.045, 0.045, DARK, _seg(10))
	# 앞 흙받이.
	_arc(ss, to_local.call(axle_f), r + 0.04, 10.0 if info.style != "sport" else 30.0, 160.0, 9, 0.03, 0.1, paint if info.style != "classic" else trim)
	var head: Vector3 = to_local.call(info.anchor("head"))
	var lens_r: float = (0.05 if info.style == "scooter" else 0.065) * float(_light().get("lens", 1.0))
	if info.style == "sport":
		# 날렵한 앞 카울 (전조등을 감싼다).
		ClayMesh.add_ellipsoid(ss, head + Vector3(0.0, 0.03, 0.08), Vector3(0.16, 0.14, 0.17), paint, _seg(12), 6)
		ClayMesh.add_rounded_box(ss, head + Vector3(0.0, 0.16, 0.1), Vector3(0.22, 0.14, 0.02), 0.6, Color("#BFDCEB"), Basis(Vector3.RIGHT, deg_to_rad(-40.0)), _seg(8), 3)
	else:
		ClayMesh.add_rod(ss, head + Vector3(0.0, 0.0, 0.05), head + Vector3(0.0, 0.0, -0.03), lens_r + 0.02, lens_r + 0.015, trim if info.style == "classic" else paint, _seg(12))
	_add_steer_parts(ss, head_top)
	_add_mesh("Mesh", ClayMesh.commit(ss), _steer)
	_front_spin = _wheel_node("FrontWheel", to_local.call(axle_f), _steer, true)
	_add_head_glow(head, lens_r)
	_add_tail(info.anchor("tail"), 0.05)
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


func _moto_seat(st: SurfaceTool, at: Vector3) -> void:
	var c: Color = _seat_color()
	var p: VehicleCatalog.Part = part_in("seat")
	var shape: String = str(p.seat.get("shape", "")) if p != null else ""
	var length: float = 0.42 if info.style != "sport" else 0.34
	ClayMesh.add_rounded_box(st, at + Vector3(0.0, -0.02, 0.0), Vector3(0.2 if info.style == "scooter" else 0.16, 0.07, length), 0.55, c, Basis(), _seg(10), 5)
	if shape == "quilt":
		for i: int in 4:
			var z: float = -length * 0.35 + float(i) * length * 0.23
			ClayMesh.add_rod(st, at + Vector3(-0.07, 0.016, z), at + Vector3(0.07, 0.016, z), 0.006, 0.006, c.darkened(0.25), _seg(4))
	elif shape == "sport":
		var c2: Color = _trim()
		ClayMesh.add_rounded_box(st, at + Vector3(0.0, 0.0, 0.0), Vector3(0.04, 0.07, length * 0.96), 0.4, c2, Basis(), _seg(6), 3)


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
	var width: float = (0.03 if bike else 0.055) * float(tire.get("w", 1.0)) * (1.35 if info.style == "mtb" else 1.0) * (0.75 if info.style == "road" else 1.0)
	var tire_color: Color = Color.html(str(tire.get("c", "#2A2A2E")))
	var axis: Basis = Basis(Vector3.BACK, PI * 0.5)
	var ws: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_torus(ws, Vector3.ZERO, r - width, width, RUBBER, _seg(20), 7, axis)
	if tire_color != Color("#2A2A2E") and tire_color != RUBBER:
		# 화이트월: 옆면 띠.
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_torus(ws, Vector3(width * 0.62 * side, 0.0, 0.0), r - width * 1.15, width * 0.42, tire_color, _seg(18), 3, axis)
	if bool(tire.get("tread", false)):
		for i: int in 12:
			var a: float = TAU * float(i) / 12.0
			ClayMesh.add_box(ws, Vector3(0.0, cos(a), sin(a)) * (r - width * 0.15), Vector3(width * 2.2, width * 0.5, width * 0.6), RUBBER, Basis(Vector3.RIGHT, -a))
	var trim: Color = _trim()
	var rim_r: float = r - width * 2.0
	ClayMesh.add_torus(ws, Vector3.ZERO, rim_r, 0.012 if bike else 0.02, trim if bike else trim.darkened(0.1), _seg(18), 4, axis)
	ClayMesh.add_rod(ws, Vector3(-0.035, 0.0, 0.0), Vector3(0.035, 0.0, 0.0), 0.022 if bike else 0.05, 0.022 if bike else 0.05, METAL if bike else DARK, _seg(8))
	if bike:
		var spokes: int = 3 if info.style == "road" else 8
		for i: int in spokes:
			var a: float = TAU * float(i) / float(spokes)
			var tip: Vector3 = Vector3(0.0, cos(a), sin(a)) * rim_r
			if info.style == "road":
				ClayMesh.add_rounded_box(ws, tip * 0.5, Vector3(0.012, rim_r, 0.03), 0.4, DARK, Basis(Vector3.RIGHT, -a), _seg(6), 3)
			else:
				ClayMesh.add_rod(ws, Vector3(0.02 * (1.0 if i % 2 == 0 else -1.0), 0.0, 0.0), tip, 0.004, 0.004, METAL, 4)
	else:
		# 휠: 다섯 살 + 브레이크 원판.
		for i: int in 5:
			var a: float = TAU * float(i) / 5.0
			ClayMesh.add_rounded_box(ws, Vector3(0.0, cos(a), sin(a)) * rim_r * 0.55, Vector3(0.02, rim_r * 0.85, 0.035), 0.4, trim, Basis(Vector3.RIGHT, -a), _seg(6), 3)
		if front:
			ClayMesh.add_rod(ws, Vector3(-0.05, 0.0, 0.0), Vector3(-0.04, 0.0, 0.0), rim_r * 0.62, rim_r * 0.62, METAL, _seg(14))
	_add_mesh("Mesh", ClayMesh.commit(ws), spin)
	var glow: Dictionary = _glow()
	if str(glow.get("where", "")) == "spoke":
		var gs: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_torus(gs, Vector3.ZERO, rim_r * 0.62, 0.008, LENS, _seg(16), 3, axis)
		for i: int in 4:
			var a: float = TAU * float(i) / 4.0 + 0.4
			ClayMesh.add_ellipsoid(gs, Vector3(0.0, cos(a), sin(a)) * rim_r * 0.82, Vector3(0.012, 0.02, 0.02), LENS, 6, 3)
		_add_glow_mesh("SpokeGlow", ClayMesh.commit(gs), spin, Color.html(str(glow.get("c", "#FFFFFF"))), 1.1)
	return spin


## 반원 흙받이 · 덮개 (center 둘레 YZ 평면의 굽은 띠, 각도는 위 = 90°, 앞(-z) = 180° 쪽, 도). 폭은 바퀴 축(X) 방향.
func _arc(st: SurfaceTool, center: Vector3, radius: float, from_deg: float, to_deg: float, steps: int, thick: float, width: float, color: Color) -> void:
	var half: float = width * 0.5
	for layer: int in 2:
		# 0 = 바깥 면, 1 = 안쪽 면 (두께만큼 안으로, 법선은 축 쪽).
		var r: float = radius if layer == 0 else radius - thick
		var sign: float = 1.0 if layer == 0 else -1.0
		for i: int in steps:
			var a0: float = deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(steps)))
			var a1: float = deg_to_rad(lerpf(from_deg, to_deg, float(i + 1) / float(steps)))
			var n0: Vector3 = Vector3(0.0, sin(a0), cos(a0))
			var n1: Vector3 = Vector3(0.0, sin(a1), cos(a1))
			var quad: Array[Vector3] = [center + n0 * r + Vector3(-half, 0, 0), center + n0 * r + Vector3(half, 0, 0), center + n1 * r + Vector3(half, 0, 0), center + n1 * r + Vector3(-half, 0, 0)]
			var normals: Array[Vector3] = [n0 * sign, n0 * sign, n1 * sign, n1 * sign]
			var order: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3]) if (layer == 0) == (to_deg > from_deg) else PackedInt32Array([0, 2, 1, 0, 3, 2])
			for k: int in order:
				st.set_color(color)
				st.set_normal(normals[k])
				st.add_vertex(quad[k])
	# 양 옆 면 (두께가 보이게).
	for side: float in [-1.0, 1.0]:
		for i: int in steps:
			var a0: float = deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(steps)))
			var a1: float = deg_to_rad(lerpf(from_deg, to_deg, float(i + 1) / float(steps)))
			var d0: Vector3 = Vector3(0.0, sin(a0), cos(a0))
			var d1: Vector3 = Vector3(0.0, sin(a1), cos(a1))
			var x: Vector3 = Vector3(half * side, 0.0, 0.0)
			var quad: Array[Vector3] = [center + x + d0 * radius, center + x + d1 * radius, center + x + d1 * (radius - thick), center + x + d0 * (radius - thick)]
			var flip: bool = (side > 0.0) != (to_deg > from_deg)
			var order: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3]) if flip else PackedInt32Array([0, 2, 1, 0, 3, 2])
			for k: int in order:
				st.set_color(color)
				st.set_normal(Vector3(side, 0.0, 0.0))
				st.add_vertex(quad[k])


## +Z 를 dir 쪽으로 (위 = 대략 +Y).
func _basis_z(dir: Vector3) -> Basis:
	var z: Vector3 = dir.normalized()
	var up: Vector3 = Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


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
func _add_head_glow(head: Vector3, lens_r: float) -> void:
	var light: Dictionary = _light()
	var color: Color = Color.html(str(light.get("color", "#FFF4DC")))
	var gs: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(gs, head + Vector3(0.0, 0.0, -0.035), Vector3(lens_r, lens_r, lens_r * 0.35), LENS, _seg(10), 4)
	if bool(light.get("drl", false)):
		ClayMesh.add_torus(gs, head + Vector3(0.0, 0.0, -0.04), lens_r + 0.008, 0.007, LENS, _seg(14), 3, Basis(Vector3.RIGHT, PI * 0.5))
	_add_glow_mesh("HeadGlow", ClayMesh.commit(gs), _steer, color, 1.6 + float(light.get("energy", 1.0)))
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
	_steer.add_child(_head_light)


func _add_tail(at: Vector3, size: float) -> void:
	var tail: Dictionary = _tail()
	var k: float = float(tail.get("size", 1.0))
	var ts: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rounded_box(ts, at, Vector3(size * 1.4 * k, size * 0.7, size * 0.5), 0.5, TAIL.lightened(0.3), Basis(), 8, 3)
	_add_glow_mesh("TailGlow", ClayMesh.commit(ts), self, TAIL, float(tail.get("energy", 1.4)))
