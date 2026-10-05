class_name HomeInterior
extends Node3D
## 평면도(FloorPlan)대로 지은 아파트 집 안: 방마다 바닥, 방과 방 사이 벽(거실·주방·복도·현관은 벽 없이 이어짐),
## 문 자리, 바깥 벽의 큰 창, 붙박이(주방 조리대 · 욕실 · 신발장 · 드레스룸 행거), 조명. 가구는 Home.furniture 를 그린다.
## 벽은 평면도를 10cm 칸으로 나눠 이웃 칸의 방이 다른 곳마다 세운 뒤 한 줄로 합친다 (방 사각형만 적으면 벽이 저절로 생긴다).

## 가구를 눌렀을 때 고르기 위한 자리 표시 (꾸미기 모드).
signal built

const CELL: float = 0.1
const FLOOR_COLORS: Dictionary = {
	"wood": ["#C8925E", "#D6A26C"],
	"light_wood": ["#E2C49A", "#ECD2AC"],
	"tile": ["#D4E0E6", "#E6EEF2"],
	"entry": ["#CFC8BC", "#DDD8CE"],
	"balcony": ["#E2D6C2", "#EEE4D4"],
	"utility": ["#C4C8CC", "#D2D6DA"],
}
const WALL_COLOR: Array = ["#EEE8DE", "#F8F5F0"]
const WALL_TOP: String = "#8A8076"
const WINDOW_KINDS: PackedStringArray = ["living", "master", "bedroom", "kitchen", "balcony"]

@export var clay_material: Material
@export var window_material: Material

var plan: FloorPlan = null
var _furniture_root: Node3D = null
var _furniture_nodes: Dictionary[String, StaticBody3D] = {}
var _labels: Array[Label3D] = []
var _wall_height: float = 2.3
var _wall_thickness: float = 0.14
var _door_width: float = 0.9


## 평면도대로 짓는다. 원점(평면도 왼쪽 위)은 이 노드의 위치.
func build(new_plan: FloorPlan) -> void:
	plan = new_plan
	var rules: Dictionary = GameData.econ.home_rules
	_wall_height = float(rules.get("wall_height", 2.3))
	_wall_thickness = float(rules.get("wall_thickness", 0.14))
	_door_width = float(rules.get("door_width", 0.9))
	for c: Node in get_children():
		c.queue_free()
	_furniture_nodes.clear()
	_labels.clear()
	var parts: Array = []
	var glass: Array = []
	var colliders: Array[AABB] = []
	_build_floors(parts, colliders)
	_build_walls(parts, glass, colliders)
	_build_fixtures(parts, colliders)
	_build_front_door(parts)
	add_child(_mesh(PartMesh.build(parts), clay_material))
	if not glass.is_empty():
		add_child(_mesh(PartMesh.build(glass), window_material))
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	for box: AABB in colliders:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = box.size
		shape.shape = b
		shape.position = box.get_center()
		body.add_child(shape)
	_build_lights()
	_build_labels()
	_furniture_root = Node3D.new()
	_furniture_root.name = "Furniture"
	add_child(_furniture_root)
	built.emit()


## 방 이름표 (꾸미기 모드의 위에서 본 화면에서만).
func set_labels_visible(on: bool) -> void:
	for l: Label3D in _labels:
		l.visible = on


func furniture_node(id: String) -> StaticBody3D:
	return _furniture_nodes.get(id)


## Home.furniture 대로 가구를 다시 놓는다 (바뀐 것만 옮기고, 없어진 건 지우고, 새것은 만든다).
func sync_furniture(list: Array[Home.Furniture]) -> void:
	if _furniture_root == null:
		return
	var seen: Dictionary[String, bool] = {}
	for f: Home.Furniture in list:
		seen[f.id] = true
		var node: StaticBody3D = _furniture_nodes.get(f.id)
		if node == null or str(node.get_meta("item", "")) != f.item:
			if node != null:
				node.queue_free()
			node = _make_furniture(f.item)
			if node == null:
				continue
			node.name = "F_%s" % f.id
			node.set_meta("id", f.id)
			_furniture_root.add_child(node)
			_furniture_nodes[f.id] = node
		node.position = Vector3(f.position.x, 0.0, f.position.y)
		node.rotation.y = f.rot * PI * 0.25
	for id: String in _furniture_nodes.keys():
		if not seen.has(id):
			_furniture_nodes[id].queue_free()
			_furniture_nodes.erase(id)


## 가구의 바닥 크기 (회전 전, x·z). 모형의 AABB.
static func footprint(item_id: String) -> Vector2:
	var info: ItemInfo = GameData.item(item_id)
	if info == null:
		return Vector2(0.5, 0.5)
	var aabb: AABB = PartMesh.get_mesh(item_id, info.model).get_aabb()
	return Vector2(maxf(aabb.size.x, 0.2), maxf(aabb.size.z, 0.2))


## 그 자리·방향의 가구 네 귀퉁이 (평면도 기준).
static func corners(item_id: String, at: Vector2, rot: int) -> Array[Vector2]:
	var half: Vector2 = footprint(item_id) * 0.5
	var out: Array[Vector2] = []
	var angle: float = -rot * PI * 0.25
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			out.append(at + Vector2(sx * half.x, sz * half.y).rotated(angle))
	return out


func _make_furniture(item_id: String) -> StaticBody3D:
	var info: ItemInfo = GameData.item(item_id)
	if info == null:
		return null
	var body: StaticBody3D = StaticBody3D.new()
	body.set_meta("item", item_id)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = PartMesh.get_mesh(item_id, info.model)
	mi.material_override = clay_material
	body.add_child(mi)
	var aabb: AABB = mi.mesh.get_aabb()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = aabb.size.max(Vector3(0.2, 0.2, 0.2))
	shape.shape = box
	shape.position = aabb.get_center()
	body.add_child(shape)
	return body


# ---- 바닥 ----

func _build_floors(parts: Array, colliders: Array[AABB]) -> void:
	for room: FloorPlan.Room in plan.rooms:
		var floor_kind: String = str(GameData.econ.room_kind(room.kind).get("floor", "wood"))
		var color: Variant = FLOOR_COLORS.get(floor_kind, FLOOR_COLORS["wood"])
		for r: Rect2 in room.rects:
			parts.append(KeeperSite.p("box", [r.size.x, 0.04, r.size.y], Vector3(r.get_center().x, -0.02, r.get_center().y), color))
			if floor_kind == "wood" or floor_kind == "light_wood":
				# 마루 널 이음매 (가로줄).
				var z: float = r.position.y + 0.3
				while z < r.end.y - 0.1:
					parts.append(KeeperSite.p("box", [r.size.x - 0.04, 0.004, 0.012], Vector3(r.get_center().x, 0.001, z), "#B07E4E" if floor_kind == "wood" else "#CDB088"))
					z += 0.3
			elif floor_kind == "tile" or floor_kind == "entry":
				# 타일 줄눈 (40cm 칸).
				var x: float = r.position.x + 0.4
				while x < r.end.x - 0.05:
					parts.append(KeeperSite.p("box", [0.01, 0.004, r.size.y], Vector3(x, 0.001, r.get_center().y), "#B8C4CA" if floor_kind == "tile" else "#B4ACA0"))
					x += 0.4
				var zz: float = r.position.y + 0.4
				while zz < r.end.y - 0.05:
					parts.append(KeeperSite.p("box", [r.size.x, 0.004, 0.01], Vector3(r.get_center().x, 0.001, zz), "#B8C4CA" if floor_kind == "tile" else "#B4ACA0"))
					zz += 0.4
	# 걸어 다닐 바닥 (집 전체 한 판, 바다 위로 떨어지지 않게).
	colliders.append(AABB(Vector3(-0.5, -0.3, -0.5), Vector3(plan.size.x + 1.0, 0.3, plan.size.y + 1.0)))
	# 집 밖 바닥 (벽 바깥쪽 둘레, 위에서 볼 때 집이 떠 보이지 않게).
	parts.append(KeeperSite.p("box", [plan.size.x + 0.6, 0.3, plan.size.y + 0.6], Vector3(plan.size.x * 0.5, -0.19, plan.size.y * 0.5), ["#6E6A64", "#8A847C"]))


# ---- 벽 (10cm 칸 래스터) ----

func _build_walls(parts: Array, glass: Array, colliders: Array[AABB]) -> void:
	var w: int = ceili(plan.size.x / CELL) + 2
	var h: int = ceili(plan.size.y / CELL) + 2
	var label: PackedInt32Array = PackedInt32Array()
	label.resize(w * h)
	var open: Array[bool] = []
	for room: FloorPlan.Room in plan.rooms:
		open.append(bool(GameData.econ.room_kind(room.kind).get("open", false)))
	for j: int in h:
		for i: int in w:
			var at: Vector2 = Vector2((i - 1 + 0.5) * CELL, (j - 1 + 0.5) * CELL)
			var index: int = 0
			for k: int in plan.rooms.size():
				for r: Rect2 in plan.rooms[k].rects:
					if r.has_point(at):
						index = k + 1
			label[j * w + i] = index
	# 가로 벽: (i, j-1) 과 (i, j) 사이 (z = (j-1)*CELL 선).
	for j: int in range(1, h):
		var run_start: int = -1
		var run_key: String = ""
		for i: int in range(0, w + 1):
			var key: String = _edge_key(label, w, open, i, j - 1, i, j, i < w) if i < w else ""
			if key == run_key and i < w:
				continue
			if not run_key.is_empty():
				_emit_run(parts, glass, colliders, true, (j - 1) * CELL, (run_start - 1) * CELL, (i - 1) * CELL, run_key)
			run_start = i
			run_key = key
	# 세로 벽: (i-1, j) 와 (i, j) 사이 (x = (i-1)*CELL 선).
	for i: int in range(1, w):
		var run_start: int = -1
		var run_key: String = ""
		for j: int in range(0, h + 1):
			var key: String = _edge_key(label, w, open, i - 1, j, i, j, j < h) if j < h else ""
			if key == run_key and j < h:
				continue
			if not run_key.is_empty():
				_emit_run(parts, glass, colliders, false, (i - 1) * CELL, (run_start - 1) * CELL, (j - 1) * CELL, run_key)
			run_start = j
			run_key = key


## 두 칸 사이에 벽이 있으면 그 종류 ("wall" / "window:<kind>"), 없으면 "".
func _edge_key(label: PackedInt32Array, w: int, open: Array[bool], ai: int, aj: int, bi: int, bj: int, valid: bool) -> String:
	if not valid:
		return ""
	var a: int = label[aj * w + ai]
	var b: int = label[bj * w + bi]
	if a == b:
		return ""
	if a > 0 and b > 0 and open[a - 1] and open[b - 1]:
		return ""
	# 문 자리 (방과 방 사이).
	var mid: Vector2 = Vector2((ai + bi + 1) * 0.5 - 1.0, (aj + bj + 1) * 0.5 - 1.0) * CELL
	if a > 0 and b > 0:
		for d: Vector2 in plan.doors:
			if mid.distance_to(d) <= _door_width * 0.5 and absf((mid - d).x if ai == bi else (mid - d).y) <= _door_width * 0.5:
				return "door"
	# 바깥 벽의 창 (집 밖 = 0 과 맞닿은 거실·침실·주방·발코니).
	if a == 0 or b == 0:
		var room: FloorPlan.Room = plan.rooms[maxi(a, b) - 1]
		if room.kind in WINDOW_KINDS:
			return "window:%s" % room.kind
	return "wall"


func _emit_run(parts: Array, glass: Array, colliders: Array[AABB], horizontal: bool, line: float, from: float, to: float, key: String) -> void:
	var length: float = to - from
	if length <= 0.01:
		return
	var t: float = _wall_thickness
	var h: float = _wall_height
	var mid: float = (from + to) * 0.5
	var center: Vector3 = Vector3(mid, 0.0, line) if horizontal else Vector3(line, 0.0, mid)
	var size_along: float = length + t
	if key == "door":
		# 문틀 위 인방(0.25m) + 문틀 양옆 기둥.
		parts.append(_wall_part(horizontal, size_along, t, 2.05, h, center, "#E4DCD0"))
		for side: float in [-1.0, 1.0]:
			var post: Vector3 = center + (Vector3(side * length * 0.5, 0.0, 0.0) if horizontal else Vector3(0.0, 0.0, side * length * 0.5))
			parts.append(_wall_part(horizontal, 0.06, t + 0.04, 0.0, 2.05, post, "#B89A78"))
		return
	var windowed: bool = key.begins_with("window:") and length >= 1.0
	if windowed:
		var kind: String = key.trim_prefix("window:")
		var sill: float = 0.15 if kind == "balcony" or kind == "living" else 0.85
		var top: float = 2.05
		parts.append(_wall_part(horizontal, size_along, t, 0.0, sill, center, WALL_COLOR))
		parts.append(_wall_part(horizontal, size_along, t, top, h, center, WALL_COLOR))
		# 창틀 + 유리 (가운데 문설주 하나).
		parts.append(_wall_part(horizontal, size_along, t + 0.03, sill, sill + 0.05, center, "#F4F4F2"))
		glass.append(_wall_part(horizontal, length - 0.08, 0.03, sill + 0.05, top, center, "#FFFFFF"))
		parts.append(_wall_part(horizontal, 0.05, t + 0.02, sill, top, center, "#F4F4F2"))
		colliders.append(_wall_box(horizontal, size_along, t, h, center))
		return
	parts.append(_wall_part(horizontal, size_along, t, 0.0, h, center, WALL_COLOR))
	# 벽 윗면 띠 (위에서 볼 때 평면도처럼 진한 선).
	parts.append(_wall_part(horizontal, size_along, t + 0.005, h - 0.01, h + 0.005, center, WALL_TOP))
	# 걸레받이.
	parts.append(_wall_part(horizontal, size_along, t + 0.02, 0.0, 0.08, center, "#D8CEC0"))
	colliders.append(_wall_box(horizontal, size_along, t, h, center))


func _wall_part(horizontal: bool, along: float, thick: float, y0: float, y1: float, center: Vector3, color: Variant) -> Dictionary:
	var size: Array = [along, y1 - y0, thick] if horizontal else [thick, y1 - y0, along]
	return KeeperSite.p("box", size, Vector3(center.x, (y0 + y1) * 0.5, center.z), color)


func _wall_box(horizontal: bool, along: float, thick: float, h: float, center: Vector3) -> AABB:
	var size: Vector3 = Vector3(along, h, thick) if horizontal else Vector3(thick, h, along)
	return AABB(Vector3(center.x, h * 0.5, center.z) - size * 0.5, size)


# ---- 붙박이 ----

func _build_fixtures(parts: Array, colliders: Array[AABB]) -> void:
	for room: FloorPlan.Room in plan.rooms:
		var r: Rect2 = room.main_rect()
		match room.kind:
			"kitchen":
				_kitchen(parts, colliders, r)
			"bath":
				_bath(parts, colliders, r)
			"entry":
				# 신발장 (현관 한쪽 벽, 들어오는 길을 막지 않게 얇게).
				var cab: AABB = AABB(Vector3(r.end.x - 0.38, 0.0, r.position.y + 0.25), Vector3(0.32, 1.1, maxf(r.size.y - 0.6, 0.4)))
				parts.append(KeeperSite.p("rbox", [cab.size.x, cab.size.y, cab.size.z], cab.get_center(), ["#E6DCCC", "#F4EEE4"], 0.08))
				parts.append(KeeperSite.p("box", [0.01, 1.0, cab.size.z - 0.1], cab.get_center() + Vector3(-cab.size.x * 0.5, 0.0, 0.0), "#C4B49E"))
				colliders.append(cab)
				# 현관 턱 (복도와 높이 차).
				parts.append(KeeperSite.p("box", [r.size.x, 0.05, 0.08], Vector3(r.get_center().x, 0.025, r.end.y - 0.04), "#A89C8C"))
			"dress":
				# 옷 거는 행거 + 걸린 옷.
				var long_x: bool = r.size.x >= r.size.y
				var rail_len: float = (r.size.x if long_x else r.size.y) - 0.3
				var a: Vector3 = Vector3(r.get_center().x, 1.7, r.position.y + 0.3) if long_x else Vector3(r.position.x + 0.3, 1.7, r.get_center().y)
				parts.append(KeeperSite.p("box", [rail_len, 0.03, 0.03] if long_x else [0.03, 0.03, rail_len], a, "#A8A8A8"))
				var colors: PackedStringArray = ["#E8A890", "#8EAED2", "#F2D68A", "#A8C8A0", "#C8A0C8", "#F4F0E8"]
				var n: int = int(rail_len / 0.18)
				for k: int in n:
					var off: float = -rail_len * 0.5 + 0.1 + k * 0.18
					var at: Vector3 = a + (Vector3(off, -0.45, 0.0) if long_x else Vector3(0.0, -0.45, off))
					parts.append(KeeperSite.p("rbox", [0.06, 0.8, 0.4] if long_x else [0.4, 0.8, 0.06], at, colors[k % colors.size()], 0.3))
				var hang: AABB = AABB(Vector3(r.position.x + 0.05, 0.0, r.position.y + 0.05), Vector3(r.size.x - 0.1 if long_x else 0.5, 1.8, 0.5 if long_x else r.size.y - 0.1))
				colliders.append(hang)
			"balcony":
				# 화분 두 개.
				for k: int in 2:
					var at: Vector3 = Vector3(r.position.x + 0.35 + k * (r.size.x - 0.7), 0.0, r.end.y - 0.35)
					parts.append(KeeperSite.p("cyl", [0.16, 0.32], at + Vector3(0.0, 0.16, 0.0), ["#B87A50", "#D0946A"], 0.05))
					parts.append(KeeperSite.p("blob", [0.24, 0.4, 0.24], at + Vector3(0.0, 0.55, 0.0), ["#4E8A4A", "#7AB46A"]))
			"utility":
				# 선반 (다용도실 안쪽 벽).
				var shelf: AABB = AABB(Vector3(r.position.x + 0.1, 0.0, r.position.y + 0.08), Vector3(r.size.x - 0.2, 1.6, 0.35))
				parts.append(KeeperSite.p("box", [shelf.size.x, 0.04, shelf.size.z], shelf.get_center() + Vector3(0.0, -0.4, 0.0), "#C8C0B4"))
				parts.append(KeeperSite.p("box", [shelf.size.x, 0.04, shelf.size.z], shelf.get_center() + Vector3(0.0, 0.3, 0.0), "#C8C0B4"))
				parts.append(KeeperSite.p("rbox", [0.4, 0.3, 0.3], shelf.get_center() + Vector3(-0.2, -0.2, 0.0), "#E8D8B8", 0.2))
				colliders.append(shelf)


func _kitchen(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	# 북쪽 벽을 따라 ㄱ자 조리대 (싱크대 · 쿡탑) + 위 수납장.
	var depth: float = 0.6
	var top: AABB = AABB(Vector3(r.position.x + 0.07, 0.0, r.position.y + 0.07), Vector3(r.size.x - 0.14, 0.9, depth))
	parts.append(KeeperSite.p("box", [top.size.x, 0.86, depth], top.get_center() + Vector3(0.0, -0.02, 0.0), ["#E8E2D8", "#F6F2EC"]))
	parts.append(KeeperSite.p("box", [top.size.x + 0.02, 0.04, depth + 0.02], Vector3(top.get_center().x, 0.9, top.get_center().z), "#7A746C"))
	parts.append(KeeperSite.p("box", [0.55, 0.02, 0.4], Vector3(top.position.x + top.size.x * 0.3, 0.915, top.get_center().z), "#B8C2C8"))
	parts.append(KeeperSite.p("rod", [0.015, 0.012], Vector3(top.position.x + top.size.x * 0.3, 0.92, top.position.z + 0.08), "#9AA4AA"))
	parts[-1]["to"] = [top.position.x + top.size.x * 0.3, 1.15, top.position.z + 0.12]
	parts.append(KeeperSite.p("box", [0.6, 0.02, 0.5], Vector3(top.end.x - 0.5, 0.915, top.get_center().z), "#24282C"))
	for k: int in 2:
		parts.append(KeeperSite.p("cyl", [0.09, 0.01], Vector3(top.end.x - 0.65 + k * 0.3, 0.93, top.get_center().z), "#4A4E52"))
	parts.append(KeeperSite.p("box", [top.size.x, 0.6, 0.35], Vector3(top.get_center().x, 1.75, top.position.z + 0.175), ["#E2DACE", "#F2ECE4"]))
	colliders.append(top)
	if r.size.y > 2.2:
		# 서쪽 벽을 따라 꺾이는 조리대 (ㄱ자).
		var side: AABB = AABB(Vector3(r.position.x + 0.07, 0.0, r.position.y + 0.07 + depth), Vector3(depth, 0.9, minf(r.size.y * 0.45, 1.6)))
		parts.append(KeeperSite.p("box", [depth, 0.86, side.size.z], side.get_center() + Vector3(0.0, -0.02, 0.0), ["#E8E2D8", "#F6F2EC"]))
		parts.append(KeeperSite.p("box", [depth + 0.02, 0.04, side.size.z], Vector3(side.get_center().x, 0.9, side.get_center().z), "#7A746C"))
		colliders.append(side)


func _bath(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	# 욕조 (긴 쪽 벽, 1.5m 이상이면) · 변기 · 세면대.
	var long_x: bool = r.size.x >= r.size.y
	var long: float = r.size.x if long_x else r.size.y
	if long >= 1.7:
		var tub: AABB = AABB(Vector3(r.position.x + 0.08, 0.0, r.position.y + 0.08), Vector3(minf(long - 0.16, 1.5), 0.55, 0.72)) if long_x else AABB(Vector3(r.position.x + 0.08, 0.0, r.position.y + 0.08), Vector3(0.72, 0.55, minf(long - 0.16, 1.5)))
		parts.append(KeeperSite.p("rbox", [tub.size.x, tub.size.y, tub.size.z], tub.get_center(), ["#E6EEF2", "#FFFFFF"], 0.2))
		parts.append(KeeperSite.p("rbox", [tub.size.x - 0.14, 0.04, tub.size.z - 0.14], tub.get_center() + Vector3(0.0, 0.26, 0.0), "#9CCCE0", 0.6))
		colliders.append(tub)
	var corner: Vector3 = Vector3(r.end.x - 0.3, 0.0, r.end.y - 0.35)
	parts.append(KeeperSite.p("rbox", [0.38, 0.4, 0.5], corner + Vector3(0.0, 0.2, 0.0), ["#E8EEF2", "#FFFFFF"], 0.5))
	parts.append(KeeperSite.p("rbox", [0.36, 0.42, 0.16], corner + Vector3(0.0, 0.55, 0.22), ["#E8EEF2", "#FFFFFF"], 0.3))
	colliders.append(AABB(corner - Vector3(0.2, 0.0, 0.25), Vector3(0.4, 0.6, 0.55)))
	var sink: Vector3 = Vector3(r.end.x - 0.3, 0.0, r.position.y + (0.95 if long >= 1.7 and not long_x else 0.3))
	if sink.z + 0.25 < corner.z - 0.25:
		parts.append(KeeperSite.p("cyl", [0.06, 0.8], sink + Vector3(0.0, 0.4, 0.0), "#E8EEF2", 0.02))
		parts.append(KeeperSite.p("rbox", [0.5, 0.12, 0.42], sink + Vector3(0.0, 0.84, 0.0), ["#E8EEF2", "#FFFFFF"], 0.4))
		parts.append(KeeperSite.p("box", [0.04, 0.6, 0.45], sink + Vector3(0.27, 1.45, 0.0), "#C8E4F0"))


func _build_front_door(parts: Array) -> void:
	# 현관문: 바깥 벽 위의 짙은 나무 문 + 손잡이 (나가기는 상황 버튼).
	var f: Vector3 = Vector3(plan.front.x, 0.0, plan.front.y)
	parts.append(KeeperSite.p("rbox", [0.92, 2.05, _wall_thickness + 0.06], f + Vector3(0.0, 1.025, 0.0), ["#5A4A3E", "#7A6656"], 0.06))
	parts.append(KeeperSite.p("box", [0.05, 0.18, 0.06], f + Vector3(0.32, 1.0, _wall_thickness * 0.5 + 0.05), "#C8B080"))
	parts.append(KeeperSite.p("box", [0.6, 0.02, 0.4], f + Vector3(0.0, 0.01, 0.4), "#9A8C7C"))


func _build_lights() -> void:
	# 거실·안방에 천장등 (그림자 없음, 따뜻한 빛).
	for kind: String in ["living", "master"]:
		var room: FloorPlan.Room = plan.first_room(kind)
		if room == null:
			continue
		var c: Vector2 = room.main_rect().get_center()
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = Color(1.0, 0.9, 0.74)
		light.light_energy = 0.55
		light.omni_range = maxf(room.main_rect().size.length(), 4.0)
		light.position = Vector3(c.x, _wall_height - 0.2, c.y)
		add_child(light)


func _build_labels() -> void:
	for room: FloorPlan.Room in plan.rooms:
		if room.kind in ["hall", "utility"]:
			continue
		var c: Vector2 = room.main_rect().get_center()
		var label: Label3D = Label3D.new()
		label.text = str(GameData.econ.room_kind(room.kind).get("name", room.kind))
		label.font_size = 64
		label.pixel_size = 0.006
		label.outline_size = 10
		label.modulate = Color(0.3, 0.26, 0.22, 0.75)
		label.outline_modulate = Color(1.0, 1.0, 1.0, 0.6)
		label.rotation.x = -PI * 0.5
		label.position = Vector3(c.x, 0.03, c.y)
		label.visible = false
		add_child(label)
		_labels.append(label)


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi
