class_name ParkSite
extends Node3D
## 성성호수공원 시설: 호수 서쪽 방문자센터, 동쪽 호숫가 정자, 둘레길 벤치. 자리는 data/world/village_layout.json 의 park.
## 방문자센터는 앞면 가운데 바닥이 원점, 앞면이 +Z (KeeperSite 와 같은 기준) — yaw π/2 면 앞면이 동쪽(호수 쪽)이다.
## 벤치는 MultiMesh 하나(드로우콜 1), 건물·정자는 PartMesh 하나씩. 서버는 건물·정자 자리만 막는다 (world.js).

@export var clay_material: Material
@export var window_material: Material

const WALL: Array = ["#EFE6D2", "#FBF5E6"]
const BASE: Array = ["#B9B0A0", "#D6CEBE"]
const ROOF: Array = ["#5E8A6A", "#7FAA88"]
const WOOD: Array = ["#B58A5C", "#D6AE7E"]
const WOOD_DARK: Array = ["#8A6444", "#A98260"]
const TILE: Array = ["#6E7C74", "#8A9A90"]


func _ready() -> void:
	var park: Dictionary = GameData.layout.park if GameData.layout != null else {}
	if park.is_empty():
		return
	if park.has("visitor_center"):
		_build_visitor_center(park["visitor_center"])
	if park.has("pavilion"):
		_build_pavilion(park["pavilion"])
	_build_benches(park.get("benches", []))


func _build_visitor_center(v: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = "VisitorCenter"
	add_child(root)
	root.global_position = Vector3(float(v["x"]), 0.0, float(v["z"]))
	root.rotation.y = float(v.get("yaw", 0.0))
	var w: float = float(v.get("width", 12.0))
	var d: float = float(v.get("depth", 7.0))
	var parts: Array = []
	# 바닥 단 + 앞 데크
	parts.append(KeeperSite.p("rbox", [w + 1.0, 0.2, d + 3.0], Vector3(0.0, 0.1, -d * 0.5 + 1.0), BASE, 0.1))
	# 본관 (낮은 단층, 크림색) + 아랫단 나무 판벽
	parts.append(KeeperSite.p("rbox", [w, 3.7, d], Vector3(0.0, 2.05, -d * 0.5), WALL, 0.05))
	parts.append(KeeperSite.p("rbox", [w + 0.06, 0.9, d + 0.06], Vector3(0.0, 0.65, -d * 0.5), WOOD, 0.08))
	# 넓게 내민 초록 지붕 + 처마 끝 띠
	parts.append(KeeperSite.p("rbox", [w + 1.8, 0.34, d + 2.6], Vector3(0.0, 4.05, -d * 0.5 + 0.7), ROOF, 0.3))
	parts.append(KeeperSite.p("rbox", [w + 1.9, 0.14, d + 2.7], Vector3(0.0, 3.82, -d * 0.5 + 0.7), WOOD_DARK, 0.3))
	# 앞 처마 기둥
	for x: float in [-w * 0.42, -w * 0.14, w * 0.14, w * 0.42]:
		parts.append(KeeperSite.p("cyl", [0.12, 3.4], Vector3(x, 1.9, 1.9), ["#D8CBB0", "#F0E4CA"], 0.05))
	# 전망 탑 (뒤쪽 왼편, 호수를 내다보는 작은 탑 + 둥근 지붕)
	parts.append(KeeperSite.p("rbox", [2.8, 3.2, 2.8], Vector3(-w * 0.32, 5.5, -d + 1.3), WALL, 0.05))
	parts.append(KeeperSite.p("cone", [2.3, 1.7], Vector3(-w * 0.32, 8.0, -d + 1.3), ROOF, 0.08))
	parts.append(KeeperSite.p("sphere", [0.16], Vector3(-w * 0.32, 8.95, -d + 1.3), "#D9B44A"))
	# 현관 계단 · 화분 · 안내 입간판
	parts.append(KeeperSite.p("rbox", [3.0, 0.14, 1.0], Vector3(w * 0.22, 0.2, 0.55), ["#C8C4BA", "#E0DCD2"], 0.2))
	for x: float in [w * 0.22 - 1.8, w * 0.22 + 1.8]:
		parts.append(KeeperSite.p("cyl", [0.3, 0.5], Vector3(x, 0.25, 0.7), ["#8A6A4A", "#AA8A6A"], 0.05))
		parts.append(KeeperSite.p("blob", [0.36, 0.46, 0.36], Vector3(x, 0.78, 0.7), ["#3E7A3A", "#6AA85A"]))
	parts.append(KeeperSite.p("rbox", [0.9, 1.1, 0.08], Vector3(-w * 0.3, 0.9, 2.6), WOOD, 0.2, Vector3(0.0, 0.0, 0.0)))
	parts.append(KeeperSite.p("cyl", [0.05, 0.4], Vector3(-w * 0.3, 0.2, 2.6), WOOD_DARK, 0.0))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	var windows: Array = []
	# 앞면 큰 유리창 둘 + 문, 옆면 창
	windows.append(KeeperSite.p("box", [w * 0.34, 2.1, 0.05], Vector3(-w * 0.22, 2.0, 0.03), "#FFFFFF"))
	windows.append(KeeperSite.p("box", [w * 0.22, 2.1, 0.05], Vector3(w * 0.22, 1.9, 0.03), "#FFFFFF"))
	for side: float in [-1.0, 1.0]:
		for z: float in [-d * 0.3, -d * 0.7]:
			windows.append(KeeperSite.p("box", [0.05, 1.3, 1.5], Vector3(side * (w * 0.5 + 0.03), 2.4, z), "#FFFFFF"))
	windows.append(KeeperSite.p("box", [1.0, 1.1, 0.05], Vector3(-w * 0.32, 5.6, -d + 1.3 + 1.43), "#FFFFFF"))
	root.add_child(_mesh(PartMesh.build(windows), window_material))
	var title: Label3D = _label(str(v.get("name", "방문자센터")), 64, Color("#FFFFFF"), Color("#3E5E48"))
	root.add_child(title)
	title.position = Vector3(0.0, 3.45, 2.0)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(w, 4.0, d)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, -d * 0.5)
	body.add_child(shape)
	root.add_child(body)


## 정자: 네 기둥 + 나무 마루 + 둥근 기와 지붕. 기둥만 막고 안은 걸어 들어갈 수 있다.
func _build_pavilion(pv: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Pavilion"
	add_child(root)
	root.global_position = Vector3(float(pv["x"]), 0.0, float(pv["z"]))
	var s: float = float(pv.get("size", 4.6))
	var h: float = s * 0.5 - 0.25
	var parts: Array = []
	parts.append(KeeperSite.p("rbox", [s, 0.4, s], Vector3(0.0, 0.2, 0.0), BASE, 0.1))
	parts.append(KeeperSite.p("rbox", [s - 0.4, 0.08, s - 0.4], Vector3(0.0, 0.44, 0.0), WOOD, 0.2))
	var posts: Array[Vector2] = [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	for post: Vector2 in posts:
		parts.append(KeeperSite.p("cyl", [0.17, 3.0], Vector3(post.x, 1.95, post.y), ["#9A3E36", "#B8564A"], 0.05))
	# 난간: 기둥 사이 가로대 (앞면 가운데는 비워 출입구)
	for i: int in 4:
		var a: Vector2 = posts[i]
		var b: Vector2 = posts[(i + 1) % 4]
		var mid: Vector2 = (a + b) * 0.5
		var along_x: bool = absf(a.y - b.y) < 0.01
		if i == 2:
			continue
		parts.append(KeeperSite.p("rbox", [s - 0.7, 0.1, 0.1] if along_x else [0.1, 0.1, s - 0.7], Vector3(mid.x, 1.0, mid.y), WOOD_DARK, 0.3))
	# 지붕: 두 겹 처마 + 기와 꼭대기 + 금빛 꼭지
	parts.append(KeeperSite.p("cone", [s * 0.84, 1.1], Vector3(0.0, 3.85, 0.0), TILE, 0.08))
	parts.append(KeeperSite.p("cone", [s * 0.5, 0.9], Vector3(0.0, 4.65, 0.0), TILE, 0.08))
	parts.append(KeeperSite.p("sphere", [0.18], Vector3(0.0, 5.2, 0.0), "#D9B44A"))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	var body: StaticBody3D = StaticBody3D.new()
	for post: Vector2 in posts:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = 0.2
		cyl.height = 3.0
		shape.shape = cyl
		shape.position = Vector3(post.x, 1.5, post.y)
		body.add_child(shape)
	root.add_child(body)
	var title: Label3D = _label(str(pv.get("name", "정자")), 44, Color("#FFF4DC"), Color("#4A3020"))
	root.add_child(title)
	title.position = Vector3(0.0, 5.7, 0.0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED


## 둘레길 벤치 (호수를 바라본다): MultiMesh 하나.
func _build_benches(benches: Array) -> void:
	if benches.is_empty():
		return
	var parts: Array = [
		KeeperSite.p("rbox", [1.5, 0.1, 0.5], Vector3(0.0, 0.46, 0.0), WOOD, 0.3),
		KeeperSite.p("rbox", [1.5, 0.42, 0.07], Vector3(0.0, 0.78, -0.24), WOOD, 0.3),
		KeeperSite.p("box", [0.08, 0.46, 0.46], Vector3(-0.64, 0.23, 0.0), WOOD_DARK),
		KeeperSite.p("box", [0.08, 0.46, 0.46], Vector3(0.64, 0.23, 0.0), WOOD_DARK),
	]
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PartMesh.build(parts)
	mm.instance_count = benches.size()
	for i: int in benches.size():
		var b: Array = benches[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(b[2])), Vector3(float(b[0]), 0.0, float(b[1]))))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Benches"
	mmi.multimesh = mm
	mmi.material_override = clay_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


func _label(text: String, size: int, color: Color, outline: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = outline
	return label
