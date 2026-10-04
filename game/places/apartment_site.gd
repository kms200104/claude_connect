class_name ApartmentSite
extends Node3D
## 솔바람 성성호수 푸르지오: 성성호수 북쪽 물가의 10층 아파트 세 동 + 단지 문 + 부동산·은행 부스.
## 동·층·호는 data/realestate/apartments.json (서버와 같은 파일). 누가 산 집은 그 호수 발코니에 깃발이 걸린다
## (내 집 = 금빛, 친구 집 = 하늘빛). 부스에서 "부동산"을 누르면 휴대폰의 부동산 앱이 열린다.

@export var clay_material: Material
@export var window_material: Material

## 한 층 높이 (m). 캐릭터 키가 1.6m 라 실제보다 낮게 줄였다.
const FLOOR_HEIGHT: float = 1.5
## 동 하나의 너비(x) · 깊이(z).
const TOWER_SIZE: Vector2 = Vector2(9.0, 6.0)
const WALL: Array = ["#E9E4DA", "#F8F6F0"]
const BAND: String = "#C9C2B4"
const ACCENT: Array = ["#4E7FA8", "#7AA8CC"]
const ROOF: Array = ["#5C6670", "#7E8A94"]
const MINE: Color = Color("#F2C14E")
const FRIEND: Color = Color("#7EC8E8")

var _towers: Dictionary[String, Node3D] = {}
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
	var x: float = (-TOWER_SIZE.x * 0.25) if u.line == 1 else (TOWER_SIZE.x * 0.25)
	return tower.global_transform * Vector3(x, (u.floor - 1) * FLOOR_HEIGHT + 1.0, TOWER_SIZE.y * 0.5 + 0.35)


func _build_tower(b: Dictionary) -> void:
	var tower: Node3D = Node3D.new()
	tower.name = "Tower_%s" % str(b.get("id", ""))
	add_child(tower)
	tower.global_position = Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)))
	tower.rotation.y = float(b.get("yaw", 0.0))
	_towers[str(b.get("id", ""))] = tower
	var floors: int = int(b.get("floors", 10))
	var lines: int = int(b.get("lines", 2))
	var height: float = floors * FLOOR_HEIGHT
	var w: float = TOWER_SIZE.x
	var d: float = TOWER_SIZE.y
	var parts: Array = []
	# 1층 필로티(기둥) 위에 몸통, 층마다 띠, 가운데 세로 포인트 색, 옥상 왕관.
	parts.append(KeeperSite.p("rbox", [w + 0.6, 0.2, d + 0.6], Vector3(0.0, 0.1, 0.0), ["#B8B2A6", "#D8D2C6"], 0.2))
	parts.append(KeeperSite.p("rbox", [w, height - 0.2, d], Vector3(0.0, height * 0.5 + 0.1, 0.0), WALL, 0.04))
	for f: int in range(1, floors + 1):
		parts.append(KeeperSite.p("box", [w + 0.12, 0.1, d + 0.12], Vector3(0.0, f * FLOOR_HEIGHT, 0.0), BAND))
	parts.append(KeeperSite.p("rbox", [1.1, height, d + 0.16], Vector3(0.0, height * 0.5, 0.0), ACCENT, 0.1))
	parts.append(KeeperSite.p("rbox", [w + 0.5, 0.35, d + 0.5], Vector3(0.0, height + 0.18, 0.0), ROOF, 0.3))
	parts.append(KeeperSite.p("rbox", [w * 0.55, 1.1, d * 0.6], Vector3(0.0, height + 0.9, -0.4), WALL, 0.15))
	parts.append(KeeperSite.p("rbox", [w * 0.6, 0.25, d * 0.66], Vector3(0.0, height + 1.55, -0.4), ROOF, 0.3))
	# 발코니 난간 (호수 쪽 앞면): 호마다 층마다.
	for f: int in floors:
		var y: float = f * FLOOR_HEIGHT + 0.42
		for line: int in lines:
			var x: float = (-w * 0.25) if line == 0 else (w * 0.25)
			parts.append(KeeperSite.p("box", [w * 0.42, 0.42, 0.06], Vector3(x, y, d * 0.5 + 0.3), "#DDE6EC"))
			parts.append(KeeperSite.p("box", [w * 0.42, 0.05, 0.36], Vector3(x, y - 0.22, d * 0.5 + 0.13), BAND))
	# 공동 현관 (가운데 아래) + 동 번호 판.
	parts.append(KeeperSite.p("rbox", [2.4, 0.18, 1.4], Vector3(0.0, 2.1, d * 0.5 + 0.7), ROOF, 0.3))
	parts.append(KeeperSite.p("rbox", [1.6, 1.9, 0.1], Vector3(0.0, 0.95, d * 0.5 + 0.02), ["#3E4A54", "#5E6A74"], 0.2))
	tower.add_child(_mesh(PartMesh.build(parts), clay_material))
	# 창문 (밤에 빛난다): 호마다 큰 거실 창 하나 + 옆면 작은 창.
	var windows: Array = []
	for f: int in floors:
		var y: float = f * FLOOR_HEIGHT + 0.85
		for line: int in lines:
			var x: float = (-w * 0.25) if line == 0 else (w * 0.25)
			windows.append(KeeperSite.p("box", [w * 0.36, 0.75, 0.04], Vector3(x, y, d * 0.5 + 0.02), "#FFFFFF"))
		for side: float in [-1.0, 1.0]:
			windows.append(KeeperSite.p("box", [0.04, 0.55, 1.2], Vector3(side * (w * 0.5 + 0.02), y, 0.0), "#FFFFFF"))
	tower.add_child(_mesh(PartMesh.build(windows), window_material))
	var label: Label3D = _label("%s동" % str(b.get("id", "")), 120, Color("#FFFFFF"))
	tower.add_child(label)
	label.position = Vector3(0.0, height - 0.8, d * 0.5 + 0.1)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(w, 4.0, d + 0.6)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, 0.3)
	body.add_child(shape)
	tower.add_child(body)


## 단지 이름 문 (가운데 동 앞 길가) + 낮은 회양목 울타리.
func _build_gate(econ: EconData) -> void:
	var list: Array = econ.buildings()
	if list.is_empty():
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


func _label(text: String, size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 16
	label.modulate = color
	label.outline_modulate = Color("#3A3A44")
	return label
