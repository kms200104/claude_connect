class_name FishingSpot
extends Node3D
## 낚시터(수역). 위치와 크기는 data/fish/spots.json 에서 읽는다 — 서버가 판정에 쓰는 값과 같은 출처.
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
		if water.material_override is ShaderMaterial:
			(water.material_override as ShaderMaterial).set_shader_parameter("half_extent", info.half_extent)
		elif water.get_surface_override_material(0) is ShaderMaterial:
			(water.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("half_extent", info.half_extent)
	if blocker != null and blocker.shape is BoxShape3D:
		blocker.shape = blocker.shape.duplicate()
		_build_blocker()
	_build_depth()


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
	var shallow_mat: StandardMaterial3D = StandardMaterial3D.new()
	shallow_mat.albedo_color = Color(0.62, 0.9, 0.92, 0.42)
	shallow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shallow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shallow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var deep_mat: StandardMaterial3D = shallow_mat.duplicate()
	deep_mat.albedo_color = Color(0.05, 0.22, 0.38, 0.32)
	for z: Dictionary in info.shallows:
		var center: Vector3 = Vector3(float(z["x"]), 0.22, float(z["z"]))
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(float(z["half_x"]) * 2.0, float(z["half_z"]) * 2.0)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = shallow_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = center
		# 여울 바닥: 밝은 모래 (맑은 물 아래로 비친다).
		var bed: MeshInstance3D = MeshInstance3D.new()
		var bed_plane: PlaneMesh = PlaneMesh.new()
		bed_plane.size = plane.size
		bed.mesh = bed_plane
		var bed_mat: StandardMaterial3D = StandardMaterial3D.new()
		bed_mat.albedo_color = Color("#C8D8B0")
		bed.material_override = bed_mat
		add_child(bed)
		bed.global_position = Vector3(center.x, water_height + 0.01, center.z)
		_add_sign(str(z.get("name", "얕은 물")) + " · 들어갈 수 있어요", _shore_point(z))
	# 깊은 곳: 여울을 뺀 가운데를 짙게.
	var deep: Rect2 = Rect2(info.center - info.half_extent + Vector2(1.5, 1.5), info.half_extent * 2.0 - Vector2(3.0, 3.0))
	var pieces: Array[Rect2] = [deep]
	for z: Dictionary in info.shallows:
		var gap: Rect2 = Rect2(float(z["x"]) - float(z["half_x"]) - 1.0, float(z["z"]) - float(z["half_z"]) - 1.0, float(z["half_x"]) * 2.0 + 2.0, float(z["half_z"]) * 2.0 + 2.0)
		var next: Array[Rect2] = []
		for piece: Rect2 in pieces:
			if piece.intersects(gap):
				next.append_array(_subtract(piece, gap.intersection(piece)))
			else:
				next.append(piece)
		pieces = next
	for r: Rect2 in pieces:
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		var dm: MeshInstance3D = MeshInstance3D.new()
		var dp: PlaneMesh = PlaneMesh.new()
		dp.size = r.size
		dm.mesh = dp
		dm.material_override = deep_mat
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dm)
		dm.global_position = Vector3(r.get_center().x, water_height + 0.03, r.get_center().y)


## 여울 쪽 물가 (팻말 자리): 여울에서 수역 가장자리로 가장 가까운 바깥.
func _shore_point(z: Dictionary) -> Vector3:
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
