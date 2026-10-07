class_name FishingSpot
extends Node3D
## 낚시터(수역). 위치와 크기는 data/fish/spots.json 에서 읽는다 — 서버가 판정에 쓰는 값과 같은 출처.
## 윤곽(outline)이 있는 호수는 거리 그림(data/fish/sdf/<id>.json)으로 물 모양을 자르고, 물 막이는 윤곽을 안쪽으로 줄인 다각형으로 만든다.
## v9: 여울(shallows)은 물 막이를 비워 걸어 들어갈 수 있고, 밝고 맑은 물빛 + "얕은 물" 팻말로, 나머지 가운데는 짙은 물빛("깊은 물")으로 보인다.

@export var spot_id: String = "pond"
@export var water: MeshInstance3D
## 물에 들어가지 못하게 막는 충돌체 (BoxShape3D). 크기는 데이터의 수역보다 가장자리만큼 작게 맞춘다.
@export var blocker: CollisionShape3D
## 물가에 설 수 있는 폭. 서버의 낚시 판정 거리(cast_range) 안쪽이어야 한다.
@export_range(0.0, 2.0, 0.05, "suffix:m") var shore_margin: float = 0.5
## 수면 높이. 바닥(y=0)과 겹쳐 깜빡이지 않게 살짝 띄운다.
@export_range(0.0, 0.2, 0.005, "suffix:m") var water_height: float = 0.03

var info: SpotInfo = null


func _ready() -> void:
	add_to_group(&"fishing_spots")
	info = GameData.spots.get(spot_id)
	if info == null:
		push_error("FishingSpot: spots.json 에 '%s' 가 없음" % spot_id)
		return
	global_position = Vector3(info.center.x, 0.0, info.center.y)
	if water != null:
		# 같은 씬 자원을 여러 낚시터가 나눠 쓰므로 크기를 바꾸기 전에 제 것으로 만든다.
		water.mesh = water.mesh.duplicate()
		if water.material_override != null:
			water.material_override = water.material_override.duplicate()
		var surface: Material = water.get_surface_override_material(0)
		if surface != null:
			water.set_surface_override_material(0, surface.duplicate())
		var plane: PlaneMesh = water.mesh
		plane.size = info.half_extent * 2.0
		# 월드 커브는 정점 단위로 휘므로, 수면도 1m 격자로 쪼개야 지면과 같이 휜다.
		plane.subdivide_width = maxi(int(plane.size.x), 1)
		plane.subdivide_depth = maxi(int(plane.size.y), 1)
		water.position = Vector3(0.0, water_height, 0.0)
		var mat: ShaderMaterial = _water_material()
		if mat != null:
			mat.set_shader_parameter("half_extent", info.half_extent)
			if info.has_outline():
				_apply_outline_sdf(mat)
	if blocker != null and blocker.shape is BoxShape3D:
		blocker.shape = blocker.shape.duplicate()
		if info.has_outline():
			_build_outline_blocker()
		else:
			_build_blocker()
	_build_depth()


func _water_material() -> ShaderMaterial:
	if water == null:
		return null
	if water.material_override is ShaderMaterial:
		return water.material_override
	if water.get_surface_override_material(0) is ShaderMaterial:
		return water.get_surface_override_material(0) as ShaderMaterial
	return null


## 윤곽 호수의 거리 그림 (tools/art/gen_lake_sdf.py 가 만든 JSON: size² L8 또는 RG8, base64)을 물 셰이더에 넣는다.
func _apply_outline_sdf(mat: ShaderMaterial) -> void:
	var path: String = "res://data/fish/sdf/%s.json" % spot_id
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:
		push_error("FishingSpot: 거리 그림 없음 — python3 tools/art/gen_lake_sdf.py (%s)" % path)
		return
	var size: int = int(doc["size"])
	# v0.13.5: 두 채널(RG8: R = 물가 ±range m, G = 깊이 ±far_range m)이면 큰 호수 가운데까지 깊이를 잰다.
	var two: bool = int(doc.get("channels", 1)) == 2
	var image: Image = Image.create_from_data(size, size, false, Image.FORMAT_RG8 if two else Image.FORMAT_L8, Marshalls.base64_to_raw(str(doc["data"])))
	var half: Array = doc["half"]
	mat.set_shader_parameter("use_outline", true)
	mat.set_shader_parameter("outline_sdf", ImageTexture.create_from_image(image))
	mat.set_shader_parameter("sdf_half", Vector2(float(half[0]), float(half[1])))
	mat.set_shader_parameter("sdf_range", float(doc["range"]))
	mat.set_shader_parameter("sdf_far_range", float(doc.get("far_range", 0.0)) if two else 0.0)


## 윤곽 호수의 물 막이: 윤곽을 물가 폭만큼 안쪽으로 줄인 다각형(들)을 한 칸 높이로 세운다. 선착장·여울 자리는 뺀다.
func _build_outline_blocker() -> void:
	var gaps: Array[PackedVector2Array] = []
	var layout: VillageLayout = GameData.layout
	if layout != null and layout.dock_size.x > 0.0:
		gaps.append(_rect_polygon(layout.dock_rect()))
	for z: Dictionary in info.shallows:
		gaps.append(_rect_polygon(Rect2(float(z["x"]) - float(z["half_x"]) - 0.6, float(z["z"]) - float(z["half_z"]) - 0.6, float(z["half_x"]) * 2.0 + 1.2, float(z["half_z"]) * 2.0 + 1.2)))
	var pieces: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in Geometry2D.offset_polygon(info.outline, -shore_margin, Geometry2D.JOIN_ROUND):
		if Geometry2D.is_polygon_clockwise(poly):
			continue  # 구멍(바깥쪽)으로 나온 조각은 건너뛴다.
		pieces.append(poly)
	for gap: PackedVector2Array in gaps:
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			for part: PackedVector2Array in Geometry2D.clip_polygons(piece, gap):
				if not Geometry2D.is_polygon_clockwise(part):
					next.append(part)
		pieces = next
	blocker.disabled = true
	var body: Node = blocker.get_parent()
	for poly: PackedVector2Array in pieces:
		var node: CollisionPolygon3D = CollisionPolygon3D.new()
		node.polygon = poly
		node.depth = 2.0
		body.add_child(node)
		# 폴리곤은 로컬 XY 평면 → X 축으로 90° 눕혀 월드 XZ 에 놓는다 (월드 원점 기준 좌표를 그대로 쓴다).
		node.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.0, 0.0))


static func _rect_polygon(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## 물 막이: 수역보다 물가 폭만큼 작은 상자. 선착장이 물 위로 나와 있으면 그 자리만 비워 걸어 들어갈 수 있게 한다.
func _build_blocker() -> void:
	var half: Vector2 = Vector2(maxf(info.half_extent.x - shore_margin, 0.05), maxf(info.half_extent.y - shore_margin, 0.05))
	var whole: Rect2 = Rect2(info.center - half, half * 2.0)
	var pieces: Array[Rect2] = [whole]
	var gaps: Array[Rect2] = []
	var layout: VillageLayout = GameData.layout
	if layout != null and layout.dock_size.x > 0.0:
		gaps.append(layout.dock_rect())
	# 여울은 걸어 들어갈 수 있게 비운다 (물가 쪽으로 살짝 넓혀 틈이 없게).
	for z: Dictionary in info.shallows:
		gaps.append(Rect2(float(z["x"]) - float(z["half_x"]) - 0.6, float(z["z"]) - float(z["half_z"]) - 0.6, float(z["half_x"]) * 2.0 + 1.2, float(z["half_z"]) * 2.0 + 1.2))
	for gap: Rect2 in gaps:
		var next: Array[Rect2] = []
		for piece: Rect2 in pieces:
			if piece.intersects(gap):
				next.append_array(_subtract(piece, gap.intersection(piece)))
			else:
				next.append(piece)
		pieces = next
	var box: BoxShape3D = blocker.shape
	for i: int in pieces.size():
		var shape: CollisionShape3D = blocker
		if i > 0:
			shape = CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			blocker.get_parent().add_child(shape)
		var r: Rect2 = pieces[i]
		(shape.shape as BoxShape3D).size = Vector3(r.size.x, 2.0, r.size.y)
		shape.global_position = Vector3(r.get_center().x, 1.0, r.get_center().y)
	if pieces.is_empty():
		box.size = Vector3(0.01, 0.01, 0.01)


## 깊이 표시: 여울은 밝고 맑은 물(발목까지 잠기는 높이), 가운데 깊은 곳은 짙은 물빛. 팻말 둘.
func _build_depth() -> void:
	if info.shallows.is_empty():
		return
	# 물빛은 물 셰이더가 칠한다 (여울 = 모래가 비치는 맑은 물, 나머지 가운데 = 짙은 물) — 호수 둥근 모양을 그대로 따른다.
	var mat: ShaderMaterial = null
	if water != null:
		if water.material_override is ShaderMaterial:
			mat = water.material_override
		elif water.get_surface_override_material(0) is ShaderMaterial:
			mat = water.get_surface_override_material(0)
	var names: PackedStringArray = ["shallow_a", "shallow_b"]
	for i: int in mini(info.shallows.size(), names.size()):
		var z: Dictionary = info.shallows[i]
		if mat != null:
			mat.set_shader_parameter(names[i], Vector4(float(z["x"]) - info.center.x, float(z["z"]) - info.center.y, float(z["half_x"]), float(z["half_z"])))
		_add_sign(str(z.get("name", "얕은 물")) + " · 들어갈 수 있어요", _shore_point(z))


## 여울 쪽 물가 (팻말 자리): 여울에서 수역 가장자리로 가장 가까운 바깥.
func _shore_point(z: Dictionary) -> Vector3:
	if info.has_outline():
		# 윤곽에서 여울 가운데에 가장 가까운 점을 지나, 물 바깥쪽으로 1m.
		var c: Vector2 = Vector2(float(z["x"]), float(z["z"]))
		var edge: Vector2 = info.boundary_nearest(c)
		var out: Vector2 = edge + (edge - c).normalized() * 1.0
		return Vector3(out.x, 0.0, out.y)
	var zx: float = float(z["x"])
	var zz: float = float(z["z"])
	var left: float = zx - float(z["half_x"]) - (info.center.x - info.half_extent.x)
	var right: float = info.center.x + info.half_extent.x - (zx + float(z["half_x"]))
	if left < right:
		return Vector3(info.center.x - info.half_extent.x - 1.0, 0.0, zz)
	return Vector3(info.center.x + info.half_extent.x + 1.0, 0.0, zz)


func _add_sign(text: String, at: Vector3) -> void:
	var post: MeshInstance3D = MeshInstance3D.new()
	var parts: Array = [
		KeeperSite.p("rod", [0.05, 0.045], Vector3.ZERO, "#7A5A3A"),
		KeeperSite.p("rbox", [0.9, 0.45, 0.06], Vector3(0.0, 1.05, 0.0), ["#B88A5A", "#D8AA7A"], 0.3),
	]
	parts[0]["to"] = [0.0, 1.0, 0.0]
	post.mesh = PartMesh.build(parts)
	post.material_override = load("res://assets/materials/foliage.tres")
	add_child(post)
	post.global_position = at
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.008
	label.outline_size = 10
	label.modulate = Color("#FFF4DC")
	label.outline_modulate = Color("#4A3020")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.global_position = at + Vector3(0.0, 1.5, 0.0)


## 사각형 a 에서 b(a 안쪽)를 빼고 남은 조각들 (왼쪽·오른쪽 전체 높이, 가운데 위·아래).
static func _subtract(a: Rect2, b: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if b.position.x > a.position.x:
		out.append(Rect2(a.position, Vector2(b.position.x - a.position.x, a.size.y)))
	if b.end.x < a.end.x:
		out.append(Rect2(Vector2(b.end.x, a.position.y), Vector2(a.end.x - b.end.x, a.size.y)))
	if b.position.y > a.position.y:
		out.append(Rect2(Vector2(b.position.x, a.position.y), Vector2(b.size.x, b.position.y - a.position.y)))
	if b.end.y < a.end.y:
		out.append(Rect2(Vector2(b.position.x, b.end.y), Vector2(b.size.x, a.end.y - b.end.y)))
	return out


## 서버 판정(cast_range)보다 약간 안쪽에서만 던질 수 있게 해서, 경계에서 서버에 거절당하지 않게 한다.
func can_cast_from(position: Vector3, safety_margin: float = 0.3) -> bool:
	return info != null and info.distance_to(position) <= info.cast_range - safety_margin
