class_name CivicSite
extends Node3D
## 솔바람동 행정복지센터 (동사무소): 하얀 2층 건물 + 파란 간판 + 유리 현관, 앞 차양 아래 창구 세 곳(민원 · 복지 · 서민금융).
## 창구마다 직원이 서 있고, 곁에서 상황 버튼을 누르면 그 창구의 일(CivicWindow)을 본다. 위치·직원은 data/civic/civic.json.

@export var actor_scene: PackedScene
@export var clay_material: Material
@export var window_material: Material

const WALL: Array = ["#E8E6E0", "#FAF9F6"]
const TRIM: Array = ["#7A8A9A", "#9AAABA"]
const BLUE: Array = ["#2E5E9A", "#4A7EBA"]
const DESK: Array = ["#B89A70", "#D8BA90"]

var _staff: Dictionary[String, NpcActor] = {}
var _desks: Dictionary[String, Dictionary] = {}
var _range: float = 2.6


func _ready() -> void:
	var civic: Dictionary = GameData.econ.civic if GameData.econ != null else {}
	if civic.is_empty():
		return
	_range = float(civic.get("service_range", 2.6))
	_build_building(civic)
	for s: Variant in civic.get("staff", []):
		if s is Dictionary:
			_add_staff(s)


## 가장 가까운 창구 (max_distance 안): "civil" | "welfare" | "finance", 없으면 빈 문자열.
func nearest_desk(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = minf(max_distance, _range)
	for desk: String in _desks:
		var s: Dictionary = _desks[desk]
		var d: float = Vector2(position.x - float(s["x"]), position.z - float(s["z"])).length()
		if d <= best_d:
			best_d = d
			best = desk
	return best


func desk_info(desk: String) -> Dictionary:
	return _desks.get(desk, {})


func staff_actor(desk: String) -> NpcActor:
	return _staff.get(desk)


## 창구 앞, 사람이 서는 자리.
func desk_front(desk: String) -> Vector3:
	var s: Dictionary = _desks.get(desk, {})
	return Vector3(float(s.get("x", 0.0)), 0.0, float(s.get("z", 0.0)) + 1.5)


func _add_staff(s: Dictionary) -> void:
	var desk: String = str(s.get("desk", ""))
	_desks[desk] = s
	if actor_scene == null:
		return
	var info: NpcInfo = NpcInfo.from_dict(s)
	var actor: NpcActor = actor_scene.instantiate()
	add_child(actor)
	actor.setup(info)
	var state: NetNpcState = NetNpcState.new()
	state.id = info.id
	state.position = Vector3(float(s.get("x", 0.0)), 0.0, float(s.get("z", 0.0)))
	state.yaw = float(s.get("yaw", PI))
	actor.apply_state(state)
	actor.name_label.text = "%s · %s" % [info.display_name, str(s.get("desk_name", ""))]
	_staff[desk] = actor
	# 직원 앞 창구 책상 + 창구 이름표.
	var at: Vector3 = state.position
	var parts: Array = [
		KeeperSite.p("rbox", [1.7, 0.95, 0.55], at + Vector3(0.0, 0.475, 0.62), DESK, 0.15),
		KeeperSite.p("rbox", [1.8, 0.06, 0.65], at + Vector3(0.0, 0.97, 0.62), ["#E8DCC8", "#F8F0E0"], 0.4),
		KeeperSite.p("rbox", [0.5, 0.36, 0.05], at + Vector3(-0.45, 1.2, 0.5), ["#3A4450", "#5A6470"], 0.2, Vector3(-12.0, 0.0, 0.0)),
		KeeperSite.p("cyl", [0.08, 0.16], at + Vector3(0.55, 1.08, 0.62), "#F4F1EA", 0.03),
	]
	var desk_mesh: MeshInstance3D = MeshInstance3D.new()
	desk_mesh.mesh = PartMesh.build(parts)
	desk_mesh.material_override = clay_material
	add_child(desk_mesh)
	var sign_label: Label3D = _label(str(s.get("desk_name", "")), 44, Color("#FFFFFF"))
	add_child(sign_label)
	sign_label.position = at + Vector3(0.0, 2.55, 0.4)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.8, 1.0, 1.4)
	shape.shape = box
	shape.position = at + Vector3(0.0, 0.5, 0.25)
	body.add_child(shape)
	add_child(body)


func _build_building(civic: Dictionary) -> void:
	var b: Dictionary = civic.get("building", {})
	var root: Node3D = Node3D.new()
	root.name = "Building"
	add_child(root)
	# 앞면 가운데 바닥이 원점, 앞면이 +Z (KeeperSite 와 같은 기준).
	root.global_position = Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)))
	root.rotation.y = float(b.get("yaw", 0.0))
	var w: float = float(b.get("width", 13.0))
	var d: float = float(b.get("depth", 8.0))
	var parts: Array = []
	parts.append(KeeperSite.p("rbox", [w + 1.0, 0.16, d + 3.4], Vector3(0.0, 0.08, -d * 0.5 + 1.2), ["#B8B4AA", "#D8D4CA"], 0.1))
	parts.append(KeeperSite.p("rbox", [w, 6.0, d], Vector3(0.0, 3.0, -d * 0.5), WALL, 0.04))
	parts.append(KeeperSite.p("rbox", [w + 0.3, 0.25, d + 0.3], Vector3(0.0, 3.05, -d * 0.5), TRIM, 0.3))
	parts.append(KeeperSite.p("rbox", [w + 0.5, 0.4, d + 0.5], Vector3(0.0, 6.15, -d * 0.5), TRIM, 0.3))
	# 앞 차양 (창구 위) + 기둥
	parts.append(KeeperSite.p("rbox", [w * 0.9, 0.18, 3.4], Vector3(0.0, 2.9, 1.5), BLUE, 0.3))
	for x: float in [-w * 0.43, -w * 0.15, w * 0.15, w * 0.43]:
		parts.append(KeeperSite.p("cyl", [0.12, 2.8], Vector3(x, 1.45, 3.0), ["#C8C8C4", "#E8E8E4"], 0.02))
	# 파란 간판 띠 + 국기 게양대 둘
	parts.append(KeeperSite.p("rbox", [w * 0.8, 1.0, 0.18], Vector3(0.0, 4.4, 0.08), BLUE, 0.2))
	for x: float in [w * 0.5 + 1.2, w * 0.5 + 2.0]:
		parts.append(KeeperSite.p("rod", [0.05, 0.04], Vector3(x, 0.0, 1.5), "#C8C8C8"))
		parts[-1]["to"] = [x, 5.2, 1.5]
	parts.append(KeeperSite.p("rbox", [0.04, 0.6, 0.9], Vector3(w * 0.5 + 1.2, 4.75, 1.95), ["#E8E8E8", "#FFFFFF"], 0.1))
	parts.append(KeeperSite.p("sphere", [0.12, 0.12, 0.03], Vector3(w * 0.5 + 1.22, 4.75, 1.95), "#C8303A", -1.0, Vector3(0.0, 90.0, 0.0)))
	parts.append(KeeperSite.p("rbox", [0.04, 0.6, 0.9], Vector3(w * 0.5 + 2.0, 4.75, 1.95), ["#1E4E9A", "#3A6EBA"], 0.1))
	# 현관 계단 · 화분
	parts.append(KeeperSite.p("rbox", [3.2, 0.12, 1.0], Vector3(w * 0.32, 0.18, 0.5), ["#C8C4BA", "#E0DCD2"], 0.2))
	for x: float in [w * 0.32 - 1.9, w * 0.32 + 1.9]:
		parts.append(KeeperSite.p("cyl", [0.3, 0.5], Vector3(x, 0.25, 0.6), ["#8A6A4A", "#AA8A6A"], 0.05))
		parts.append(KeeperSite.p("blob", [0.35, 0.45, 0.35], Vector3(x, 0.75, 0.6), ["#3E7A3A", "#6AA85A"]))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	var windows: Array = []
	for floor_y: float in [1.6, 4.4]:
		for x: float in [-w * 0.38, -w * 0.13, w * 0.13]:
			if floor_y > 4.0 and absf(x) < w * 0.3:
				continue
			windows.append(KeeperSite.p("box", [1.9, 1.3, 0.05], Vector3(x, floor_y, 0.03), "#FFFFFF"))
	windows.append(KeeperSite.p("box", [2.2, 2.4, 0.05], Vector3(w * 0.32, 1.35, 0.03), "#FFFFFF"))
	for side: float in [-1.0, 1.0]:
		for z: float in [-d * 0.3, -d * 0.7]:
			windows.append(KeeperSite.p("box", [0.05, 1.2, 1.6], Vector3(side * (w * 0.5 + 0.03), 4.4, z), "#FFFFFF"))
	root.add_child(_mesh(PartMesh.build(windows), window_material))
	var title: Label3D = _label(str(civic.get("name", "행정복지센터")), 84, Color("#FFFFFF"))
	root.add_child(title)
	title.position = Vector3(0.0, 4.4, 0.2)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(w, 6.0, d)
	shape.shape = box
	shape.position = Vector3(0.0, 3.0, -d * 0.5)
	body.add_child(shape)
	root.add_child(body)


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
	label.outline_modulate = Color("#1E3050")
	return label
