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
## 창유리: 바깥 풍경 사진을 읽는 머티리얼 (set_view). 하나를 모든 창이 같이 쓴다.
const WINDOW_VIEW_SHADER: String = "res://assets/shaders/window_view.gdshader"
var _view_material: ShaderMaterial = null
## 벽 너머 가리기 (v0.13.6, HomeSight): 집 안 모든 메시(가구 포함)에 덮어 그리는 머티리얼. null 이면 없음.
var sight_overlay: Material = null
## 시야를 막는 벽 (창 있는 벽 포함, 문 자리 제외) — 이 노드 기준 상자. HomeSight 가 거리 지도를 만든다.
var wall_boxes: Array[AABB] = []
var _furniture_root: Node3D = null
var _furniture_nodes: Dictionary[String, StaticBody3D] = {}
var _labels: Array[Label3D] = []
var _wall_height: float = 2.3
var _wall_thickness: float = 0.14
var _door_width: float = 1.2


## 평면도대로 짓는다. 원점(평면도 왼쪽 위)은 이 노드의 위치.
func build(new_plan: FloorPlan) -> void:
	plan = new_plan
	var rules: Dictionary = GameData.econ.home_rules
	_wall_height = float(rules.get("wall_height", 2.3))
	_wall_thickness = float(rules.get("wall_thickness", 0.14))
	_door_width = float(rules.get("door_width", 1.2))
	for c: Node in get_children():
		c.queue_free()
	_furniture_nodes.clear()
	_labels.clear()
	wall_boxes.clear()
	var parts: Array = []
	var glass: Array = []
	var colliders: Array[AABB] = []
	_build_floors(parts, colliders)
	_build_walls(parts, glass, colliders)
	_build_fixtures(parts, colliders)
	_build_front_door(parts)
	add_child(_mesh(PartMesh.build(parts), clay_material))
	if not glass.is_empty():
		add_child(_mesh(PartMesh.build(glass), _window_view_material()))
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
## 창밖 풍경 (HomeView 가 찍은 사진 여섯 장). null 이면 하늘색 유리.
func set_view(view: HomeView.View) -> void:
	var material: ShaderMaterial = _window_view_material()
	material.set_shader_parameter("has_view", 1.0 if view != null else 0.0)
	if view == null:
		return
	material.set_shader_parameter("faces", view.faces)
	material.set_shader_parameter("face_dir", view.dirs)
	material.set_shader_parameter("face_right", view.rights)
	material.set_shader_parameter("face_up", view.ups)


## 1인칭 창밖 보기: 실시간 화면(null 이면 끄고 찍어 둔 사진으로 돌아간다).
func set_live_view(texture: Texture2D) -> void:
	var material: ShaderMaterial = _window_view_material()
	material.set_shader_parameter("use_live", 1.0 if texture != null else 0.0)
	material.set_shader_parameter("live_view", texture)


func _window_view_material() -> ShaderMaterial:
	if _view_material == null:
		_view_material = ShaderMaterial.new()
		_view_material.shader = load(WINDOW_VIEW_SHADER)
	return _view_material


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
	mi.material_overlay = sight_overlay
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
			# 벽을 따라 문 폭 안, 벽에서 수직으로는 조금 벗어나도 (평면도 문 점이 벽선에 딱 붙지 않을 수 있다).
			var along: float = (mid - d).x if ai == bi else (mid - d).y
			var across: float = (mid - d).y if ai == bi else (mid - d).x
			if absf(along) <= _door_width * 0.5 and absf(across) <= 0.35:
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
		wall_boxes.append(colliders[-1])
		return
	parts.append(_wall_part(horizontal, size_along, t, 0.0, h, center, WALL_COLOR))
	# 벽 윗면 띠 (위에서 볼 때 평면도처럼 진한 선).
	parts.append(_wall_part(horizontal, size_along, t + 0.005, h - 0.01, h + 0.005, center, WALL_TOP))
	# 걸레받이.
	parts.append(_wall_part(horizontal, size_along, t + 0.02, 0.0, 0.08, center, "#D8CEC0"))
	colliders.append(_wall_box(horizontal, size_along, t, h, center))
	wall_boxes.append(colliders[-1])


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
				_entry(parts, colliders, r)
			"dress":
				_dress(parts, colliders, r)
			"balcony":
				# 화분 두 개.
				for k: int in 2:
					var at: Vector3 = Vector3(r.position.x + 0.35 + k * (r.size.x - 0.7), 0.0, r.end.y - 0.35)
					parts.append(KeeperSite.p("cyl", [0.16, 0.32], at + Vector3(0.0, 0.16, 0.0), ["#B87A50", "#D0946A"], 0.05))
					parts.append(KeeperSite.p("blob", [0.24, 0.4, 0.24], at + Vector3(0.0, 0.55, 0.0), ["#4E8A4A", "#7AB46A"]))
			"utility", "pantry":
				_shelf(parts, colliders, r)


func _kitchen(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	# 막힌 벽(북쪽이 되면 북쪽)을 따라 조리대 (싱크대 · 쿡탑) + 위 수납장, 옆 벽이 막혀 있으면 ㄱ자로 꺾는다.
	var sides: Array[Vector2] = _closed_sides(r)
	if sides.is_empty():
		return
	var n: Vector2 = Vector2(0.0, -1.0) if Vector2(0.0, -1.0) in sides else sides[0]
	var depth: float = 0.6
	var xf: Transform3D = _wall_xf(r, n)
	var span: Vector2 = _wall_span(xf, _side_length(r, n), depth)
	var w: float = span.y - span.x
	if w < 1.2:
		return
	var cx: float = (span.x + span.y) * 0.5
	var cz: float = 0.07 + depth * 0.5
	var sink_x: float = span.x + w * 0.3
	var cook_x: float = span.y - 0.5
	var local: Array = [
		KeeperSite.p("box", [w, 0.86, depth], Vector3(cx, 0.43, cz), ["#E8E2D8", "#F6F2EC"]),
		KeeperSite.p("box", [w + 0.02, 0.04, depth + 0.02], Vector3(cx, 0.9, cz), "#7A746C"),
		KeeperSite.p("box", [0.55, 0.02, 0.4], Vector3(sink_x, 0.915, cz), "#B8C2C8"),
		KeeperSite.p("rod", [0.015, 0.012], Vector3(sink_x, 0.92, 0.15), "#9AA4AA"),
		KeeperSite.p("box", [0.6, 0.02, 0.5], Vector3(cook_x, 0.915, cz), "#24282C"),
		KeeperSite.p("box", [w, 0.6, 0.35], Vector3(cx, 1.75, 0.07 + 0.175), ["#E2DACE", "#F2ECE4"]),
	]
	local[3]["to"] = [sink_x, 1.15, 0.19]
	for k: int in 2:
		local.append(KeeperSite.p("cyl", [0.09, 0.01], Vector3(cook_x - 0.15 + k * 0.3, 0.93, cz), "#4A4E52"))
	parts.append_array(ApartmentSite.place_parts(local, xf))
	colliders.append(xf * AABB(Vector3(span.x, 0.0, 0.07), Vector3(w, 0.9, depth)))
	# ㄱ자: 조리대가 닿은 쪽 끝의 옆 벽이 막혀 있으면 그 벽을 따라 꺾는다.
	var along: Vector2 = Vector2(xf.basis.x.x, xf.basis.x.z)
	for end: int in 2:
		var side_n: Vector2 = -along if end == 0 else along
		var reaches: bool = span.x < 0.2 if end == 0 else span.y > _side_length(r, n) - 0.2
		if not reaches or not side_n in sides:
			continue
		var xf2: Transform3D = _wall_xf(r, side_n)
		var length2: float = _side_length(r, side_n)
		var corner: Vector3 = xf2.affine_inverse() * (xf * Vector3(0.0 if end == 0 else _side_length(r, n), 0.0, 0.0))
		var span2: Vector2 = _wall_span(xf2, length2, depth)
		var run: float = minf(length2 * 0.45, 1.6)
		var a: float = (0.07 + depth) if corner.x < length2 * 0.5 else (length2 - 0.07 - depth - run)
		var b: float = a + run
		a = maxf(a, span2.x)
		b = minf(b, span2.y)
		if b - a < 0.6:
			continue
		var side_local: Array = [
			KeeperSite.p("box", [b - a, 0.86, depth], Vector3((a + b) * 0.5, 0.43, cz), ["#E8E2D8", "#F6F2EC"]),
			KeeperSite.p("box", [b - a, 0.04, depth + 0.02], Vector3((a + b) * 0.5, 0.9, cz), "#7A746C"),
		]
		parts.append_array(ApartmentSite.place_parts(side_local, xf2))
		colliders.append(xf2 * AABB(Vector3(a, 0.0, 0.07), Vector3(b - a, 0.9, depth)))
		break


func _bath(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	# 욕조 (가장 긴 막힌 벽, 1.7m 이상이면 문에서 먼 쪽 끝) · 변기 · 세면대 (문에서 먼 구석부터).
	var used: Array[AABB] = []
	var sides: Array[Vector2] = _closed_sides(r)
	if not sides.is_empty() and _side_length(r, sides[0]) >= 1.7:
		var n: Vector2 = sides[0]
		var xf: Transform3D = _wall_xf(r, n)
		var length: float = _side_length(r, n)
		var span: Vector2 = _wall_span(xf, length, 0.72)
		var tl: float = minf(span.y - span.x, 1.5)
		if tl >= 1.2:
			var door_x: float = 0.0
			var count: int = 0
			for d: Vector2 in _all_doors(r):
				door_x += (xf.affine_inverse() * Vector3(d.x, 0.0, d.y)).x
				count += 1
			var x0: float = span.x if count == 0 or door_x / count > length * 0.5 else span.y - tl
			var local: Array = [
				KeeperSite.p("rbox", [tl, 0.55, 0.72], Vector3(x0 + tl * 0.5, 0.275, 0.08 + 0.36), ["#E6EEF2", "#FFFFFF"], 0.2),
				KeeperSite.p("rbox", [tl - 0.14, 0.04, 0.58], Vector3(x0 + tl * 0.5, 0.535, 0.08 + 0.36), "#9CCCE0", 0.6),
			]
			parts.append_array(ApartmentSite.place_parts(local, xf))
			var tub: AABB = xf * AABB(Vector3(x0, 0.0, 0.08), Vector3(tl, 0.55, 0.72))
			colliders.append(tub)
			used.append(tub)
	# 구석 넷: 문(과 그 앞 지나갈 자리)에서 먼 순서.
	var corners: Array[Vector3] = []
	for cx: float in [r.position.x + 0.3, r.end.x - 0.3]:
		for cz: float in [r.position.y + 0.35, r.end.y - 0.35]:
			corners.append(Vector3(cx, 0.0, cz))
	var doors: Array[Vector2] = _all_doors(r)
	corners.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _door_distance(a, doors) > _door_distance(b, doors))
	var toilet_done: bool = false
	for c: Vector3 in corners:
		var box: AABB = AABB(c - Vector3(0.2, 0.0, 0.25), Vector3(0.4, 0.6, 0.55))
		if _hits(box.grow(0.05), used) or _door_distance(c, doors) < _door_width * 0.5 + 0.7:
			continue
		if not toilet_done:
			# 변기: 물탱크는 가까운 벽 쪽.
			var back: float = 0.22 if c.z > r.get_center().y else -0.22
			parts.append(KeeperSite.p("rbox", [0.38, 0.4, 0.5], c + Vector3(0.0, 0.2, 0.0), ["#E8EEF2", "#FFFFFF"], 0.5))
			parts.append(KeeperSite.p("rbox", [0.36, 0.42, 0.16], c + Vector3(0.0, 0.55, back), ["#E8EEF2", "#FFFFFF"], 0.3))
			colliders.append(box)
			used.append(box)
			toilet_done = true
		else:
			# 세면대 (지나갈 수 있게 충돌체 없이).
			var wall_x: float = 0.27 if c.x > r.get_center().x else -0.27
			parts.append(KeeperSite.p("cyl", [0.06, 0.8], c + Vector3(0.0, 0.4, 0.0), "#E8EEF2", 0.02))
			parts.append(KeeperSite.p("rbox", [0.5, 0.12, 0.42], c + Vector3(0.0, 0.84, 0.0), ["#E8EEF2", "#FFFFFF"], 0.4))
			parts.append(KeeperSite.p("box", [0.04, 0.6, 0.45], c + Vector3(wall_x, 1.45, 0.0), "#C8E4F0"))
			break


## 드레스룸: 막힌 벽을 따라 행거 + 걸린 옷.
func _dress(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	var sides: Array[Vector2] = _closed_sides(r)
	if sides.is_empty():
		return
	var n: Vector2 = sides[0]
	var xf: Transform3D = _wall_xf(r, n)
	var span: Vector2 = _wall_span(xf, _side_length(r, n), 0.5)
	var rail: float = span.y - span.x - 0.2
	if rail < 0.6:
		return
	var cx: float = (span.x + span.y) * 0.5
	var local: Array = [KeeperSite.p("box", [rail, 0.03, 0.03], Vector3(cx, 1.7, 0.3), "#A8A8A8")]
	var colors: PackedStringArray = ["#E8A890", "#8EAED2", "#F2D68A", "#A8C8A0", "#C8A0C8", "#F4F0E8"]
	for k: int in int(rail / 0.18):
		local.append(KeeperSite.p("rbox", [0.06, 0.8, 0.4], Vector3(cx - rail * 0.5 + 0.1 + k * 0.18, 1.25, 0.3), colors[k % colors.size()], 0.3))
	parts.append_array(ApartmentSite.place_parts(local, xf))
	colliders.append(xf * AABB(Vector3(span.x, 0.0, 0.05), Vector3(span.y - span.x, 1.8, 0.5)))


## 다용도실·팬트리: 막힌 벽을 따라 선반.
func _shelf(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	var sides: Array[Vector2] = _closed_sides(r)
	if sides.is_empty():
		return
	var n: Vector2 = sides[0]
	var xf: Transform3D = _wall_xf(r, n)
	var span: Vector2 = _wall_span(xf, _side_length(r, n), 0.35)
	var w: float = span.y - span.x
	if w < 0.5:
		return
	var cx: float = (span.x + span.y) * 0.5
	var local: Array = [
		KeeperSite.p("box", [w, 0.04, 0.35], Vector3(cx, 0.4, 0.255), "#C8C0B4"),
		KeeperSite.p("box", [w, 0.04, 0.35], Vector3(cx, 1.1, 0.255), "#C8C0B4"),
		KeeperSite.p("rbox", [0.4, 0.3, 0.3], Vector3(cx - 0.2, 0.6, 0.255), "#E8D8B8", 0.2),
	]
	parts.append_array(ApartmentSite.place_parts(local, xf))
	colliders.append(xf * AABB(Vector3(span.x, 0.0, 0.08), Vector3(w, 1.6, 0.35)))


func _build_front_door(parts: Array) -> void:
	# 현관문: 바깥 벽 위의 짙은 나무 문 + 손잡이 + 발판 (나가기는 상황 버튼). 문이 놓인 현관 변 방향으로 돌린다.
	var f: Vector3 = Vector3(plan.front.x, 0.0, plan.front.y)
	var entry: FloorPlan.Room = plan.first_room("entry")
	var n: Vector2 = _front_side(entry.main_rect()) if entry != null else Vector2(0.0, -1.0)
	var local: Array = [
		KeeperSite.p("rbox", [0.92, 2.05, _wall_thickness + 0.06], Vector3(0.0, 1.025, 0.0), ["#5A4A3E", "#7A6656"], 0.06),
		KeeperSite.p("box", [0.05, 0.18, 0.06], Vector3(0.32, 1.0, _wall_thickness * 0.5 + 0.05), "#C8B080"),
		KeeperSite.p("box", [0.6, 0.02, 0.4], Vector3(0.0, 0.01, 0.4), "#9A8C7C"),
	]
	# 로컬 +Z = 집 안쪽 (변의 바깥 방향 n 의 반대).
	parts.append_array(ApartmentSite.place_parts(local, Transform3D(Basis(Vector3.UP, atan2(-n.x, -n.y)), f)))


# ---- 현관 ----

const SIDES: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2(1.0, 0.0)]


## 현관: 신발장은 현관문·열린 쪽(복도로 이어짐)·방문이 없는 막힌 벽 가운데 가장 긴 곳에, 현관 턱은 열린 쪽에.
## (평면마다 현관이 열리는 방향이 다르다 — 125㎡ 는 동쪽 복도로 열린다.)
func _entry(parts: Array, colliders: Array[AABB], r: Rect2) -> void:
	var sides: Array[Vector2] = _closed_sides(r)
	if not sides.is_empty():
		var n: Vector2 = sides[0]
		var xf: Transform3D = _wall_xf(r, n)
		var span: Vector2 = _wall_span(xf, _side_length(r, n), 0.32)
		span = Vector2(maxf(span.x, 0.3), minf(span.y, _side_length(r, n) - 0.3))
		var w: float = span.y - span.x
		if w >= 0.4:
			var cx: float = (span.x + span.y) * 0.5
			var local: Array = [
				KeeperSite.p("rbox", [w, 1.1, 0.32], Vector3(cx, 0.55, 0.06 + 0.16), ["#E6DCCC", "#F4EEE4"], 0.08),
				# 문짝 줄눈 (현관 쪽 면).
				KeeperSite.p("box", [w - 0.1, 1.0, 0.01], Vector3(cx, 0.55, 0.06 + 0.325), "#C4B49E"),
			]
			parts.append_array(ApartmentSite.place_parts(local, xf))
			colliders.append(xf * AABB(Vector3(span.x, 0.0, 0.06), Vector3(w, 1.1, 0.32)))
	# 현관 턱 (복도와 높이 차): 열린 변마다.
	for n: Vector2 in SIDES:
		if not _side_open(r, n):
			continue
		var mid: Vector2 = _side_point(r, n, 0.5) - n * 0.04
		var size: Array = [0.08, 0.05, r.size.y] if n.x != 0.0 else [r.size.x, 0.05, 0.08]
		parts.append(KeeperSite.p("box", size, Vector3(mid.x, 0.025, mid.y), "#A89C8C"))


## 현관문(plan.front)이 놓인 현관 변의 바깥 방향.
func _front_side(r: Rect2) -> Vector2:
	var best: Vector2 = SIDES[0]
	var best_d: float = INF
	for n: Vector2 in SIDES:
		var d: float = absf(plan.front.x - _side_point(r, n, 0.5).x) if n.x != 0.0 else absf(plan.front.y - _side_point(r, n, 0.5).y)
		if d < best_d:
			best_d = d
			best = n
	return best


## 그 변 너머가 벽 없이 이어지는 방(복도·거실 같은 open 종류)인지.
func _side_open(r: Rect2, n: Vector2) -> bool:
	for k: float in [0.25, 0.5, 0.75]:
		var room: FloorPlan.Room = plan.room_at(_side_point(r, n, k) + n * 0.12)
		if room != null and room.kind != "entry" and bool(GameData.econ.room_kind(room.kind).get("open", false)):
			return true
	return false


## 그 변 위에 방문 자리(plan.doors)나 현관문(plan.front)이 있는지.
func _side_has_door(r: Rect2, n: Vector2) -> bool:
	for d: Vector2 in plan.doors + [plan.front]:
		if n.x != 0.0:
			if absf(d.x - _side_point(r, n, 0.5).x) < 0.15 and d.y > r.position.y - 0.1 and d.y < r.end.y + 0.1:
				return true
		elif absf(d.y - _side_point(r, n, 0.5).y) < 0.15 and d.x > r.position.x - 0.1 and d.x < r.end.x + 0.1:
			return true
	return false


## 변 위의 점 (k = 0~1, 변을 따라).
static func _side_point(r: Rect2, n: Vector2, k: float) -> Vector2:
	if n.x == 0.0:
		return Vector2(lerpf(r.position.x, r.end.x, k), r.position.y if n.y < 0.0 else r.end.y)
	return Vector2(r.position.x if n.x < 0.0 else r.end.x, lerpf(r.position.y, r.end.y, k))


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
	mi.material_overlay = sight_overlay
	return mi


# ---- 벽에 붙는 붙박이 자리 ----

static func _side_length(r: Rect2, n: Vector2) -> float:
	return r.size.y if n.x != 0.0 else r.size.x


## 붙박이를 붙일 수 있는 벽 (열린 쪽도 아니고 방문·현관문도 없는 변), 긴 순서.
func _closed_sides(r: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for n: Vector2 in SIDES:
		if not _side_open(r, n) and not _side_has_door(r, n):
			out.append(n)
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _side_length(r, a) > _side_length(r, b) + 0.01)
	return out


## 그 변(바깥 방향 n)의 벽 좌표계: 로컬 +X 는 벽을 따라, +Z 는 방 안쪽, 원점은 벽의 한쪽 끝.
func _wall_xf(r: Rect2, n: Vector2) -> Transform3D:
	var basis: Basis = Basis(Vector3.UP, atan2(-n.x, -n.y))
	var mid: Vector2 = _side_point(r, n, 0.5)
	return Transform3D(basis, Vector3(mid.x, 0.0, mid.y) - basis.x * _side_length(r, n) * 0.5)


## 벽 좌표계에서 붙박이(깊이 depth)가 차지해도 되는 구간 [x0, x1]: 옆 벽 문으로 들어온 몸이 지나갈 자리는 비운다.
func _wall_span(xf: Transform3D, length: float, depth: float) -> Vector2:
	var x0: float = 0.07
	var x1: float = length - 0.07
	var inv: Transform3D = xf.affine_inverse()
	var half: float = _door_width * 0.5 + 0.45
	for d: Vector2 in plan.doors + [plan.front]:
		var l: Vector3 = inv * Vector3(d.x, 0.0, d.y)
		if l.z < -0.3 or l.z > depth + half + 0.45 or l.x < -0.3 or l.x > length + 0.3:
			continue
		if l.x <= 0.3:
			x0 = maxf(x0, 0.95)
		elif l.x >= length - 0.3:
			x1 = minf(x1, length - 0.95)
		elif l.x + half > x0 and l.x - half < x1:
			if (l.x - half) - x0 >= x1 - (l.x + half):
				x1 = l.x - half
			else:
				x0 = l.x + half
	return Vector2(x0, x1)


## 그 방 사각형 둘레에 걸친 방문·현관문 자리.
func _all_doors(r: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for d: Vector2 in plan.doors + [plan.front]:
		if r.grow(0.2).has_point(d):
			out.append(d)
	return out


static func _door_distance(at: Vector3, doors: Array[Vector2]) -> float:
	var best: float = INF
	for d: Vector2 in doors:
		best = minf(best, Vector2(at.x, at.z).distance_to(d))
	return best


static func _hits(box: AABB, list: Array[AABB]) -> bool:
	for b: AABB in list:
		if b.intersects(box):
			return true
	return false
