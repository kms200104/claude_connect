class_name ApartmentSite
extends Node3D
## 솔바람 리버파크 (v0.21 강변도시): 살 수 있는 단지(buildings) + 단지 문 · 조경 · 지하주차장 입구 + 부동산·은행 부스, 그리고 둘레의 다른 단지(samples, 겉모습만).
## 동 모양은 ApartmentKit (필로티 · 발코니 · 실외기실 · 계단실 · 옥상 크라운) — 살 수 있는 동은 FULL, 둘레 단지는 SIMPLE.
## 동·층·호는 data/realestate/apartments.json (서버와 같은 파일). 동마다 w·d(바닥 크기)와 yaw(앞면 방향)를 지도대로 줄 수 있다.
## 누가 산 집은 그 호수 발코니에 깃발이 걸린다 (내 집 = 금빛, 친구 집 = 하늘빛). 부스에서 "부동산"을 누르면 휴대폰의 부동산 앱이 열린다.
## samples 는 동마다 메시 둘(점토 + 창)로, 멀면 그리지 않는다 (visibility range).

@export var clay_material: Material
@export var window_material: Material

## 한 층 높이 (m) · 필로티 높이 — v0.21 강변도시는 실제 크기 (ApartmentKit 과 같다).
const FLOOR_HEIGHT: float = ApartmentKit.FLOOR_HEIGHT
## 동 하나의 기본 너비(x) · 깊이(z). 데이터의 w·d 가 있으면 그것을 쓴다.
const TOWER_SIZE: Vector2 = Vector2(9.0, 6.0)
const WALL: Array = ["#E9E4DA", "#F8F6F0"]
const BAND: String = "#C9C2B4"
const ACCENT: Array = ["#4E7FA8", "#7AA8CC"]
const ROOF: Array = ["#5C6670", "#7E8A94"]
## e편한세상 성성호수공원 외관 (v0.13.8): 모든 동 5m 필로티(층 높이를 줄인 것과 같은 비율로 2.6m), 흰 몸통 + 짙은 회색 세로 프레임,
## 유리 난간 발코니, 옆면 꼭대기에 브랜드 · 동 번호, 옥상 크라운 틀 + 경관조명, 105동 최상층 스카이라운지 (분양 자료 기준).
const PILOTI_HEIGHT: float = ApartmentKit.PILOTI_HEIGHT
const STONE_DARK: Array = ["#5F5B57", "#77726C"]
const STONE_LIGHT: Array = ["#CFCAC2", "#DDD9D2"]
const CHARCOAL: String = "#3B4046"
const CROWN: String = "#5A6068"
const BODY_WHITE: Array = ["#EFEDE8", "#FAF9F6"]
const WALL_TRIM: Array = ["#E6E3DD", "#F4F2EE"]
const RAIL_GLASS: Array = ["#9FB8C6", "#C2D4DE"]
const BRAND_ORANGE: String = "#E9822E"
const BRAND_TEXT: String = "e편한세상"
const SKY_LOUNGE_TOWER: String = "105"
## 벽에 칠한 글씨를 벽면에서 띄우는 거리 (깜빡이지 않을 만큼만).
const WALL_TEXT_OFFSET: float = 0.015
const MINE: Color = Color("#F2C14E")
const FRIEND: Color = Color("#7EC8E8")

var _towers: Dictionary[String, Node3D] = {}
var _text_materials: Dictionary[String, Material] = {}
var _flags: Node3D = null
var _office: Vector3 = Vector3.ZERO
var _office_range: float = 3.0


func _ready() -> void:
	var econ: EconData = GameData.econ
	if econ == null:
		return
	for b: Variant in econ.buildings():
		if b is Dictionary:
			_build_tower(b)
	_build_gate(econ)
	_build_estate(econ.apartments.get("estate", {}))
	for complex: Variant in econ.apartments.get("samples", []):
		if complex is Dictionary:
			_build_sample(complex)
	var office: Dictionary = econ.apartments.get("office", {})
	_office = Vector3(float(office.get("x", 0.0)), 0.0, float(office.get("z", 0.0)))
	_office_range = float(office.get("range", 3.0))
	_build_office()
	_flags = Node3D.new()
	_flags.name = "Flags"
	add_child(_flags)
	Economy.homes_changed.connect(_refresh_flags)
	_refresh_flags()


## 부동산 부스 곁인지 (상황 버튼 "부동산").
func near_office(position: Vector3, max_distance: float) -> bool:
	return Vector2(position.x - _office.x, position.z - _office.z).length() <= minf(max_distance, _office_range)


func office_position() -> Vector3:
	return _office


## 그 호수 발코니의 월드 위치 (깃발·카메라용).
func unit_position(unit_id: String) -> Vector3:
	var u: EconData.Unit = GameData.econ.unit(unit_id)
	var tower: Node3D = _towers.get(u.building) if u != null else null
	if tower == null:
		return Vector3.ZERO
	var size: Vector2 = tower_size(tower.get_meta(&"data", {}))
	var lines: int = int((tower.get_meta(&"data", {}) as Dictionary).get("lines", 2))
	var x: float = _line_x(u.line - 1, lines, size.x)
	return tower.global_transform * Vector3(x, PILOTI_HEIGHT + (u.floor - 1) * FLOOR_HEIGHT + 1.2, size.y * 0.5 + ApartmentKit.BALCONY + 0.1)


## 그 집이 있는 동의 방향 (로컬 +Z = 앞면 · 발코니 쪽). 없으면 기본 방향.
func unit_basis(unit_id: String) -> Basis:
	var u: EconData.Unit = GameData.econ.unit(unit_id)
	var tower: Node3D = _towers.get(u.building) if u != null else null
	return tower.global_basis.orthonormalized() if tower != null else Basis.IDENTITY


## 그 집이 있는 동의 그림(메시 · 이름표) — 1인칭 창밖 풍경에서 자기 동은 감춘다 (HomeFirstPerson).
func unit_tower_visuals(unit_id: String) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	var u: EconData.Unit = GameData.econ.unit(unit_id)
	var tower: Node3D = _towers.get(u.building) if u != null else null
	if tower == null:
		return out
	for c: Node in tower.get_children():
		if c is VisualInstance3D:
			out.append(c)
	return out


## 동의 바닥 크기 (너비 x · 깊이 z). 서버 world.js 의 막힌 자리와 같은 값.
static func tower_size(b: Dictionary) -> Vector2:
	return Vector2(float(b.get("w", TOWER_SIZE.x)), float(b.get("d", TOWER_SIZE.y)))


func _build_tower(b: Dictionary) -> void:
	var tower: Node3D = Node3D.new()
	tower.name = "Tower_%s" % str(b.get("id", ""))
	add_child(tower)
	tower.global_position = Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)))
	tower.rotation.y = float(b.get("yaw", 0.0))
	tower.set_meta(&"data", b)
	var id: String = str(b.get("id", ""))
	_towers[id] = tower
	var floors: int = int(b.get("floors", 10))
	var lines: int = int(b.get("lines", 2))
	var size: Vector2 = tower_size(b)
	var clay: BoxBatch = BoxBatch.new()
	var glass: BoxBatch = BoxBatch.new()
	var top: float = ApartmentKit.tower(clay, glass, size.x, size.y, floors, lines, ApartmentKit.Detail.FULL, id == SKY_LOUNGE_TOWER)
	tower.add_child(_mesh(clay.commit(), clay_material))
	tower.add_child(_mesh(glass.commit(), window_material))
	# ---- 측벽: 브랜드와 동 번호 (양쪽 옆면 꼭대기), 주황 포인트 띠 — 벽에 칠한 글씨처럼 벽 폭 안에 맞춘다 ----
	var w: float = size.x
	var d: float = size.y
	for side: float in [-1.0, 1.0]:
		var brand: MeshInstance3D = _wall_label(GameData.econ.complex_short(), 72, d * 0.78, 1.1)
		tower.add_child(brand)
		brand.position = Vector3(side * (w * 0.5 + WALL_TEXT_OFFSET), top - 1.9, 0.0)
		brand.rotation.y = side * PI * 0.5
		var number: MeshInstance3D = _wall_label(id, 150, d * 0.7, 2.6)
		tower.add_child(number)
		number.position = Vector3(side * (w * 0.5 + WALL_TEXT_OFFSET), top - 4.8, 0.0)
		number.rotation.y = side * PI * 0.5
	var stripe: BoxBatch = BoxBatch.new()
	for side: float in [-1.0, 1.0]:
		stripe.box(Vector3(side * (w * 0.5 + 0.01), top - 3.1, 0.0), Vector3(0.02, 0.16, d * 0.5), Color(BRAND_ORANGE))
	tower.add_child(_mesh(stripe.commit(), clay_material))
	# 필로티 기둥 사이로는 걸어 다닌다 — 몸통 아래 공동현관 · 계단실 덩어리만 막는다.
	var body: StaticBody3D = StaticBody3D.new()
	for box_def: Array in ApartmentKit.solid_boxes(w, d):
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = box_def[1]
		shape.shape = box
		shape.position = box_def[0]
		body.add_child(shape)
	tower.add_child(body)


## 앞면에서 호(라인)의 가로 자리 (왼쪽부터, 가운데 세로 프레임을 비켜).
static func _line_x(line: int, lines: int, w: float) -> float:
	return -w * 0.5 + (float(line) + 0.5) * w / float(lines)


## v0.21 단지 꾸밈 (apartments.json estate): 담장 + 회양목, 단지 안 길 · 보도블록, 클럽하우스, 놀이터, 지하주차장 입구, 환기구 · 조경 나무.
func _build_estate(estate: Dictionary) -> void:
	if estate.is_empty():
		return
	var root: Node3D = Node3D.new()
	root.name = "Estate"
	add_child(root)
	var clay: BoxBatch = BoxBatch.new()
	var glass: BoxBatch = BoxBatch.new()
	# 바닥 판(길 · 보도 · 놀이터 바닥)은 see-through 없는 재료로 (발밑이 비지 않게).
	var flat: BoxBatch = BoxBatch.new()
	var r: Array = estate.get("rect", [])
	var road: Dictionary = estate.get("road", {})
	var road_z: float = float(road.get("z", 0.0))
	var road_w: float = float(road.get("w", 7.0))
	if r.size() == 4:
		var x0: float = float(r[0])
		var z0: float = float(r[1])
		var x1: float = float(r[2])
		var z1: float = float(r[3])
		# 담장: 돌 턱 + 회양목 (문 · 길 자리는 비운다, 남쪽 강 쪽은 낮은 철제 울타리).
		for seg: Array in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x0, z0), Vector2(x0, z1)], [Vector2(x1, z0), Vector2(x1, road_z - road_w * 0.5 - 2.0)],
				[Vector2(x1, road_z + road_w * 0.5 + 2.0), Vector2(x1, z1)], [Vector2(x0, z1), Vector2(x1, z1)]]:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var mid: Vector2 = (a + b) * 0.5
			var horizontal: bool = absf(a.y - b.y) < 0.01
			var len_m: float = a.distance_to(b)
			var size_low: Vector3 = Vector3(len_m, 0.5, 0.5) if horizontal else Vector3(0.5, 0.5, len_m)
			clay.box(Vector3(mid.x, 0.25, mid.y), size_low, STONE_DARK_C)
			var size_hedge: Vector3 = Vector3(len_m, 0.8, 0.9) if horizontal else Vector3(0.9, 0.8, len_m)
			clay.box(Vector3(mid.x, 0.85, mid.y), size_hedge, Color("#4E8A44"))
		# 단지 안 길 (아스팔트 + 양쪽 보도블록).
		var rx0: float = float(road.get("x0", x0))
		var rx1: float = float(road.get("x1", x1))
		flat.quad_up(Vector3((rx0 + rx1) * 0.5, 0.02, road_z), Vector2(rx1 - rx0, road_w), Color("#4A4D52"))
		for s: float in [-1.0, 1.0]:
			flat.quad_up(Vector3((rx0 + rx1) * 0.5, 0.025, road_z + s * (road_w * 0.5 + 1.0)), Vector2(rx1 - rx0, 2.0), Color("#C9B9A6"))
		# 동 앞 보도 (동마다 현관에서 단지 안 길까지).
		for b: Variant in GameData.econ.buildings():
			if b is Dictionary:
				var bx: float = float(b.get("x", 0.0))
				var bz: float = float(b.get("z", 0.0))
				var bd: float = float(b.get("d", 6.0))
				flat.quad_up(Vector3(bx, 0.025, bz + bd * 0.5 + 4.0), Vector2(6.0, 8.0), Color("#D3C4B0"))
				flat.quad_up(Vector3(bx, 0.024, bz + bd * 0.5 + 8.6), Vector2(float(b.get("w", 9.0)) + 8.0, 2.2), Color("#C9B9A6"))
	for f: Variant in estate.get("facilities", []):
		if f is Dictionary:
			_facility(root, clay, glass, flat, f)
	# 환기구 (지하주차장 숨구멍): 동 사이 잔디밭에 군데군데.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	for b: Variant in GameData.econ.buildings():
		if b is Dictionary and rng.randf() < 0.6:
			var p: Vector3 = Vector3(float(b.get("x", 0.0)) + 14.0, 0.0, float(b.get("z", 0.0)) - 9.0)
			clay.box(p + Vector3(0.0, 0.9, 0.0), Vector3(1.4, 1.8, 1.4), Color("#9AA3A9"))
			clay.box(p + Vector3(0.0, 1.9, 0.0), Vector3(1.8, 0.2, 1.8), Color("#6F787E"))
	root.add_child(_mesh(clay.commit(), clay_material))
	root.add_child(_mesh(glass.commit(), window_material))
	root.add_child(_mesh(flat.commit(), Puff.MATERIAL))


const STONE_DARK_C: Color = Color("#77726C")


func _facility(root: Node3D, clay: BoxBatch, glass: BoxBatch, flat: BoxBatch, f: Dictionary) -> void:
	var c: Vector3 = Vector3(float(f.get("x", 0.0)), 0.0, float(f.get("z", 0.0)))
	var w: float = float(f.get("w", 10.0))
	var d: float = float(f.get("d", 10.0))
	match str(f.get("kind", "")):
		"clubhouse":
			var h: float = 4.0 * float(f.get("floors", 2))
			clay.box(c + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), Color("#E9E5DD"))
			for fl: int in int(f.get("floors", 2)):
				glass.box(c + Vector3(0.0, 2.0 + fl * 4.0, d * 0.5 + 0.03), Vector3(w * 0.9, 2.8, 0.05), Color.WHITE)
				clay.box(c + Vector3(0.0, 4.0 + fl * 4.0, d * 0.5 + 0.5), Vector3(w + 0.4, 0.25, 1.0), Color(CHARCOAL))
			clay.box(c + Vector3(0.0, h + 0.3, 0.0), Vector3(w + 0.6, 0.6, d + 0.6), Color(CROWN))
		"playground":
			flat.quad_up(c + Vector3(0.0, 0.03, 0.0), Vector2(w, d), Color("#E07A4F"))
			flat.quad_up(c + Vector3(-w * 0.2, 0.035, 0.0), Vector2(w * 0.4, d * 0.6), Color("#5BA4D9"))
			# 미끄럼틀 탑 · 미끄럼판 · 그네 틀 · 시소.
			clay.box(c + Vector3(-w * 0.25, 1.2, 0.0), Vector3(2.4, 2.4, 2.4), Color("#F2C14E"))
			clay.box(c + Vector3(-w * 0.25, 2.8, 0.0), Vector3(2.8, 0.3, 2.8), Color("#E04B3C"))
			clay.box(c + Vector3(-w * 0.25 + 2.6, 1.1, 0.0), Vector3(3.6, 0.15, 1.0), Color("#35A26B"), Basis(Vector3.BACK, -0.55))
			for k: float in [-1.0, 1.0]:
				clay.box(c + Vector3(w * 0.22 + k * 2.0, 1.4, -d * 0.2), Vector3(0.15, 2.8, 0.15), Color("#5A646C"))
			clay.box(c + Vector3(w * 0.22, 2.8, -d * 0.2), Vector3(4.3, 0.15, 0.15), Color("#5A646C"))
			for k: float in [-0.8, 0.8]:
				clay.box(c + Vector3(w * 0.22 + k, 0.55, -d * 0.2), Vector3(0.6, 0.08, 0.3), Color("#8E5BD0"))
			clay.box(c + Vector3(w * 0.25, 0.45, d * 0.25), Vector3(3.6, 0.12, 0.4), Color("#2F7DD1"), Basis(Vector3.BACK, 0.12))
		"parking":
			# 지하주차장 입구: 비탈 지붕(짙은 회색) 아래 어두운 입구, 옆 벽, 높이 제한 막대 (노랑 · 검정).
			clay.box(c + Vector3(0.0, 3.0, 0.0), Vector3(w, 0.3, d + 0.6), Color("#7A838A"))
			flat.quad_up(c + Vector3(0.0, 3.17, 0.0), Vector2(w - 0.6, d), Color("#6FA35E"))
			for s: float in [-1.0, 1.0]:
				clay.box(c + Vector3(0.0, 1.5, s * (d * 0.5)), Vector3(w, 3.0, 0.3), Color("#C6C1B8"))
			clay.box(c + Vector3(w * 0.5, 1.5, 0.0), Vector3(0.3, 3.0, d), Color("#C6C1B8"))
			flat.quad_up(c + Vector3(-1.0, 0.04, 0.0), Vector2(w - 2.0, d - 0.4), Color("#1E2226"))
			for k: int in 5:
				clay.box(c + Vector3(-w * 0.5 - 0.2, 2.5, -d * 0.4 + float(k) * d * 0.2), Vector3(0.12, 0.25, d * 0.2), Color("#F2C14E") if k % 2 == 0 else Color("#222222"))
	var label: Label3D = _label(str(f.get("name", "")), 56, Color("#FFFFFF"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 60.0
	root.add_child(label)
	label.position = c + Vector3(0.0, 4.5 if str(f.get("kind", "")) != "clubhouse" else 9.5, 0.0)


## 단지 이름 문 (가운데 동 앞 길가) + 낮은 회양목 울타리. 데이터에 gate 가 있으면 그 자리에 문만 세운다.
func _build_gate(econ: EconData) -> void:
	var list: Array = econ.buildings()
	if list.is_empty():
		return
	var gate: Variant = econ.apartments.get("gate")
	if gate is Dictionary:
		_build_gate_at(econ, gate)
		return
	var first: Dictionary = list[0]
	var last: Dictionary = list[list.size() - 1]
	var x0: float = float(first.get("x", 0.0)) - TOWER_SIZE.x * 0.5
	var x1: float = float(last.get("x", 0.0)) + TOWER_SIZE.x * 0.5
	var z: float = float(first.get("z", 0.0)) + TOWER_SIZE.y * 0.5 + 2.2
	var root: Node3D = Node3D.new()
	root.name = "Gate"
	add_child(root)
	var parts: Array = []
	# 울타리: 부스 자리(가운데 사이)만 비우고 앞으로 쭉.
	var gap_x: float = float(econ.apartments.get("office", {}).get("x", (x0 + x1) * 0.5))
	for seg: Vector2 in [Vector2(x0, gap_x - 2.6), Vector2(gap_x + 2.6, x1)]:
		var length: float = seg.y - seg.x
		if length <= 0.5:
			continue
		parts.append(KeeperSite.p("blob", [length * 0.5, 0.4, 0.45], Vector3((seg.x + seg.y) * 0.5, 0.35, z), ["#3E7A3A", "#6AA85A"]))
	# 문 기둥 둘 + 가로 간판.
	for side: float in [-1.0, 1.0]:
		parts.append(KeeperSite.p("rbox", [0.5, 4.4, 0.5], Vector3(gap_x + side * 2.6, 2.2, z), ["#6A747E", "#8E98A2"], 0.2))
	parts.append(KeeperSite.p("rbox", [6.0, 0.8, 0.35], Vector3(gap_x, 4.5, z), ACCENT, 0.25))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	var sign_label: Label3D = _label(econ.complex_name(), 64, Color("#FFFFFF"))
	root.add_child(sign_label)
	sign_label.position = Vector3(gap_x, 4.5, z + 0.2)


## 단지 문 (gate: x, z = 문 가운데, yaw = 앞면 방향, width = 기둥 사이): 기둥 둘 + 가로 간판.
func _build_gate_at(econ: EconData, gate: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Gate"
	add_child(root)
	root.global_position = Vector3(float(gate.get("x", 0.0)), 0.0, float(gate.get("z", 0.0)))
	root.rotation.y = float(gate.get("yaw", 0.0))
	var half: float = float(gate.get("width", 5.2)) * 0.5
	# 문주 (v0.13.8): 돌 기둥 둘 위에 짙은 회색 가로 틀, 틀 아래 경관조명 띠, 기둥 앞 주황 포인트 — 동 외관과 같은 재료.
	var parts: Array = []
	var glow: Array = []
	for side: float in [-1.0, 1.0]:
		parts.append(KeeperSite.p("box", [0.9, 4.6, 0.9], Vector3(side * half, 2.3, 0.0), STONE_DARK))
		parts.append(KeeperSite.p("box", [0.08, 3.0, 0.02], Vector3(side * half, 2.0, 0.46), BRAND_ORANGE))
	parts.append(KeeperSite.p("box", [half * 2.0 + 1.6, 0.9, 0.7], Vector3(0.0, 5.0, 0.0), CHARCOAL))
	parts.append(KeeperSite.p("box", [half * 2.0 + 1.9, 0.12, 0.9], Vector3(0.0, 5.5, 0.0), STONE_LIGHT))
	glow.append(KeeperSite.p("box", [half * 2.0 - 0.4, 0.06, 0.5], Vector3(0.0, 4.53, 0.0), "#FFFFFF"))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	root.add_child(_mesh(PartMesh.build(glow), window_material))
	for face: float in [1.0, -1.0]:
		var sign_label: MeshInstance3D = _wall_label(econ.complex_name(), 64, half * 2.0 + 1.0, 0.5, Color("#F4F2EE"))
		root.add_child(sign_label)
		sign_label.position = Vector3(0.0, 5.0, face * (0.35 + WALL_TEXT_OFFSET))
		sign_label.rotation.y = 0.0 if face > 0.0 else PI


## 겉모습만 있는 둘레 단지: 동마다 몸통·층 띠·포인트 색·옥상, 창은 밤에 빛난다. 단지 하나 = 점토 메시 1 + 창 메시 1.
## complex: { name, floors, w, d, wall[2], accent[2], buildings[{ id, x, z, yaw, floors?, w?, d? }] }
func _build_sample(complex: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Sample_%s" % str(complex.get("id", "complex"))
	add_child(root)
	root.global_transform = Transform3D.IDENTITY
	var center: Vector3 = Vector3.ZERO
	var top: float = 0.0
	var list: Array = complex.get("buildings", [])
	var wall: Array = complex.get("wall", BODY_WHITE)
	var accent: Array = complex.get("accent", ACCENT)
	for entry: Variant in list:
		if not entry is Dictionary:
			continue
		var b: Dictionary = entry
		var size: Vector2 = Vector2(float(b.get("w", complex.get("w", TOWER_SIZE.x))), float(b.get("d", complex.get("d", TOWER_SIZE.y))))
		var floors: int = int(b.get("floors", complex.get("floors", 12)))
		var yaw: float = float(b.get("yaw", 0.0))
		var at: Vector3 = Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)))
		center += at
		# 동마다 노드 하나 (visibility range 가 동 자리에서 재도록).
		var node: Node3D = Node3D.new()
		node.name = "Tower_%s" % str(b.get("id", ""))
		root.add_child(node)
		node.position = at
		node.rotation.y = yaw
		var clay: BoxBatch = BoxBatch.new()
		var glass: BoxBatch = BoxBatch.new()
		var lines: int = 4 if size.x >= 18.0 else 2
		var t: float = ApartmentKit.tower(clay, glass, size.x, size.y, floors, lines, ApartmentKit.Detail.SIMPLE, false, Color(str(wall[0])), Color(str(accent[0])))
		top = maxf(top, t)
		for pair: Array in [[clay, clay_material], [glass, window_material]]:
			var mi: MeshInstance3D = _mesh((pair[0] as BoxBatch).commit(), pair[1])
			mi.visibility_range_end = 420.0
			node.add_child(mi)
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(size.x, 4.0, size.y)
		shape.shape = box
		shape.position = Vector3(0.0, 2.0, 0.0)
		body.add_child(shape)
		node.add_child(body)
	if list.is_empty():
		return
	var label: Label3D = _label(str(complex.get("name", "")), 96, Color("#FFFFFF"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 260.0
	root.add_child(label)
	label.position = center / float(list.size()) + Vector3(0.0, top + 4.0, 0.0)


## 로컬 도형들을 그 자리(xf: 회전 yaw + 위치)로 옮긴 도형들 (at·to 를 옮기고 rot 에 yaw 를 더한다). 집 안 붙박이도 쓴다.
static func place_parts(local: Array, xf: Transform3D) -> Array:
	var out: Array = []
	var yaw_deg: float = rad_to_deg(xf.basis.get_euler().y)
	for part: Dictionary in local:
		var at: Array = part["at"]
		var moved: Vector3 = xf * Vector3(float(at[0]), float(at[1]), float(at[2]))
		var q: Dictionary = part.duplicate()
		q["at"] = [moved.x, moved.y, moved.z]
		if part.has("to"):
			var to: Array = part["to"]
			var moved_to: Vector3 = xf * Vector3(float(to[0]), float(to[1]), float(to[2]))
			q["to"] = [moved_to.x, moved_to.y, moved_to.z]
		var rot: Array = part.get("rot", [0.0, 0.0, 0.0])
		q["rot"] = [float(rot[0]), float(rot[1]) + yaw_deg, float(rot[2])]
		out.append(q)
	return out


## 부동산·은행 부스: 작은 유리 부스 + 차양 + "부동산 · 은행" 간판.
func _build_office() -> void:
	var root: Node3D = Node3D.new()
	root.name = "Office"
	add_child(root)
	root.global_position = _office + Vector3(0.0, 0.0, -1.0)
	var parts: Array = []
	parts.append(KeeperSite.p("rbox", [2.2, 0.12, 1.6], Vector3(0.0, 0.06, 0.0), ["#B8B2A6", "#D8D2C6"], 0.3))
	parts.append(KeeperSite.p("rbox", [2.0, 2.0, 1.4], Vector3(0.0, 1.06, 0.0), ["#E2D8C2", "#F8F2E4"], 0.15))
	parts.append(KeeperSite.p("rbox", [2.5, 0.16, 1.9], Vector3(0.0, 2.15, 0.15), ACCENT, 0.4))
	parts.append(KeeperSite.p("rbox", [1.2, 0.8, 0.1], Vector3(0.0, 0.9, 0.68), ["#C9A23A", "#F0D27A"], 0.3))
	# 은행 ATM 단말 (옆) — 휴대폰 은행 앱과 같은 일.
	parts.append(KeeperSite.p("rbox", [0.55, 1.3, 0.5], Vector3(1.45, 0.65, 0.1), ["#4A5A6A", "#6E7E8E"], 0.25))
	parts.append(KeeperSite.p("box", [0.38, 0.28, 0.04], Vector3(1.45, 1.0, 0.36), "#9FE0C8"))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	var label: Label3D = _label("부동산 · 은행", 48, Color("#FFF4DC"))
	root.add_child(label)
	label.position = Vector3(0.0, 1.75, 0.72)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.6, 2.0, 1.4)
	shape.shape = box
	shape.position = Vector3(0.25, 1.0, 0.0)
	body.add_child(shape)
	root.add_child(body)


func _refresh_flags() -> void:
	if _flags == null:
		return
	for c: Node in _flags.get_children():
		c.queue_free()
	for unit_id: String in Economy.home_owners:
		var owner_slot: int = Economy.home_owners[unit_id]
		var at: Vector3 = unit_position(unit_id)
		if at == Vector3.ZERO:
			continue
		var color: Color = MINE if owner_slot == Net.my_id else FRIEND
		var parts: Array = [
			KeeperSite.p("rod", [0.025, 0.02], Vector3(0.0, 0.0, 0.0), "#8A8A8A"),
			KeeperSite.p("rbox", [0.5, 0.32, 0.03], Vector3(0.27, 0.42, 0.0), [color.darkened(0.15).to_html(false), color.lightened(0.15).to_html(false)], 0.2),
		]
		parts[0]["to"] = [0.0, 0.62, 0.0]
		var flag: MeshInstance3D = _mesh(PartMesh.get_mesh("apt_flag_%s" % color.to_html(false), parts), clay_material)
		_flags.add_child(flag)
		flag.global_position = at
		flag.rotation.y = _towers.get(unit_id.get_slice("-", 0), self).global_rotation.y


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


## 벽에 칠한 글씨 (옆면 동 번호 · 브랜드 · 문주 간판): 건물과 같은 셰이더를 쓰는 글자 메시(TextMesh)라 땅 휘기를 같이 따르고
## (Label3D 는 따르지 않아 먼 동일수록 글씨가 건물 위로 떠 보였다), 빛도 벽처럼 받는다. 벽 폭(max_width) · 높이(max_height, m) 안에 맞춘다.
func _wall_label(text: String, font_size: int, max_width: float, max_height: float, color: Color = Color(CHARCOAL)) -> MeshInstance3D:
	var mesh: TextMesh = TextMesh.new()
	mesh.text = text
	mesh.font_size = font_size
	mesh.depth = 0.01
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font: Font = mesh.font if mesh.font != null else ThemeDB.fallback_font
	var px: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) if font != null else Vector2(font_size * text.length(), font_size)
	mesh.pixel_size = minf(max_width / maxf(px.x, 1.0), max_height / maxf(px.y, 1.0))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _text_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 글씨 색마다 하나씩 (점토 머티리얼을 그 색으로).
func _text_material(color: Color) -> Material:
	var key: String = color.to_html(false)
	if not _text_materials.has(key):
		var m: Material = clay_material.duplicate() if clay_material != null else StandardMaterial3D.new()
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("albedo", color)
		elif m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = color
		_text_materials[key] = m
	return _text_materials[key]


func _label(text: String, size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 16
	label.modulate = color
	label.outline_modulate = Color("#3A3A44")
	return label
