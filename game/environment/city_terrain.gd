class_name CityTerrain
extends Node3D
## 탕정 제2지구 강변도시 지형 (v0.21, 예전 섬 지형 IslandTerrain 을 바꾼 것):
## - 바닥: CHUNK m 칸으로 나눈 높이 메시 (칸마다 visibility range — 멀리 있는 칸은 그리지 않는다).
##   곡교천 안은 강 바닥으로 파이고, 강 건너는 둑(풀 언덕)이 솟고 침수 구역은 물 밑으로 꺼진다.
## - 충돌: 평평한 바닥 상자 + 도시 끝 벽(예전 해안 벽, island 모양) + 강 한가운데(south 줄) 벽 + 보(weir) 자리 막이.
##   강물은 낚시터(FishingSpot: seongseong · sea)가 물 막이를 따로 세운다.
## - 강 건너 침수 수면 (물 셰이더, 4m 격자 — 땅 휘기를 따라 휜다).
## - 상점 실내(도시 밖 멀리) 아래 바닥.
## 모양 데이터: GameData.layout(island) · GameData.city(곡교천 가장자리 · 침수 다각형).

@export var ground_mesh: MeshInstance3D
@export var ground_shape: CollisionShape3D
@export var water_material: ShaderMaterial
## 바닥을 깔 범위 (가운데 ±미터). 도시 끝(island.half) 너머 들판까지.
@export_range(100.0, 800.0, 1.0, "suffix:m") var extent: float = 480.0
## 바닥 칸 크기 · 정점 간격 (강 둘레 칸은 river_cell 로 촘촘히).
@export_range(16.0, 240.0, 1.0, "suffix:m") var chunk: float = 120.0
@export_range(1.0, 8.0, 0.5, "suffix:m") var cell: float = 4.0
@export_range(0.5, 4.0, 0.5, "suffix:m") var river_cell: float = 2.0
## 이 거리 너머 바닥 칸은 그리지 않는다 (땅 휘기로 어차피 지평선 아래).
@export_range(100.0, 1000.0, 10.0, "suffix:m") var draw_distance: float = 360.0
## 강 바닥 깊이 · 강 건너 둑 높이.
@export_range(0.2, 5.0, 0.1, "suffix:m") var river_depth: float = 2.2
@export_range(0.0, 4.0, 0.1, "suffix:m") var levee_height: float = 1.4
## 도시 끝 벽을 경계에서 얼마나 안쪽에 세울지.
@export_range(0.0, 5.0, 0.1, "suffix:m") var wall_inset: float = 1.0
@export_range(16, 512) var wall_segments: int = 240
@export var player: Node3D

var _layout: VillageLayout = null
var _city: CityData = null
var _flood_poly: PackedVector2Array = PackedVector2Array()
var _chunks: Array[MeshInstance3D] = []


func _ready() -> void:
	_layout = GameData.layout
	_city = GameData.city
	if _layout == null or _city == null:
		return
	_flood_poly = _city.flood_polygon
	if ground_mesh != null:
		var ground_material: Material = ground_mesh.get_surface_override_material(0)
		if ground_material == null:
			ground_material = ground_mesh.material_override
		ground_mesh.mesh = null
		ground_mesh.visible = false
		# 색 지도가 덮는 범위는 village_layout.json 의 map_extent 와 같아야 한다.
		if ground_material is ShaderMaterial:
			(ground_material as ShaderMaterial).set_shader_parameter("map_extent", _layout.map_extent)
			(ground_material as ShaderMaterial).set_shader_parameter("town_extent", _layout.town_extent)
		_build_ground(ground_material)
	if ground_shape != null and ground_shape.shape is BoxShape3D:
		(ground_shape.shape as BoxShape3D).size = Vector3(extent * 2.0, 1.0, extent * 2.0)
	_build_edge_walls()
	_build_flood_water()
	_build_shop_floor()


## 바닥 높이 (그림만 — 충돌은 평평한 y = 0).
func height(p: Vector2) -> float:
	var nz: float = _city.north_z(p.x)
	var sz: float = _city.south_z(p.x)
	if p.y > nz - 0.5 and p.y < sz + 0.5:
		# 강 바닥: 가장자리에서 6m 안쪽까지 비스듬히 (호안 아래).
		var inside: float = minf(p.y - nz, sz - p.y)
		return -river_depth * smoothstep(-0.4, 5.0, inside)
	if p.y >= sz:
		var d: float = p.y - sz
		var h: float = levee_height * smoothstep(3.0, 6.5, d) * smoothstep(17.0, 11.0, d)
		# 둑이 터진 자리 둘레는 둑이 없다.
		h *= smoothstep(18.0, 34.0, absf(p.x - _city.flood_breach.x))
		if _flood_poly.size() >= 3:
			var sd: float = _poly_distance(p)
			h = lerpf(h, -0.3, smoothstep(4.0, -1.0, sd))
			# 침수 둘레는 물가가 살짝 올라와 수면 끝이 땅에 닿는다.
			h += 0.6 * smoothstep(-1.0, 3.0, sd) * smoothstep(12.0, 4.0, sd)
		return h
	return 0.0


func _poly_distance(p: Vector2) -> float:
	var best: float = INF
	var n: int = _flood_poly.size()
	for i: int in n:
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(p, _flood_poly[i], _flood_poly[(i + 1) % n])
		best = minf(best, c.distance_to(p))
	return -best if Geometry2D.is_point_in_polygon(p, _flood_poly) else best


func _build_ground(material: Material) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "GroundChunks"
	add_child(holder)
	var n: int = int(ceil(extent * 2.0 / chunk))
	for cj: int in n:
		for ci: int in n:
			var x0: float = -extent + ci * chunk
			var z0: float = -extent + cj * chunk
			# 강 · 강 건너를 지나는 칸은 촘촘히 (호안 · 둑 모양).
			var near_river: bool = z0 + chunk > _city.north_z(x0) - 30.0 and z0 < 280.0
			var step: float = river_cell if near_river else cell
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = _chunk_mesh(x0, z0, step, near_river)
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = draw_distance + chunk * 0.7
			mi.visibility_range_end_margin = 20.0
			# visibility range 는 메시 가운데로부터의 거리 — 칸 가운데에 노드를 둔다.
			mi.position = Vector3(x0 + chunk * 0.5, 0.0, z0 + chunk * 0.5)
			holder.add_child(mi)
			_chunks.append(mi)


func _chunk_mesh(x0: float, z0: float, step: float, shaped: bool) -> ArrayMesh:
	var k: int = int(round(chunk / step))
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var cx: float = x0 + chunk * 0.5
	var cz: float = z0 + chunk * 0.5
	var hs: PackedFloat32Array = PackedFloat32Array()
	hs.resize((k + 3) * (k + 3))
	# 법선을 이웃 높이로 구하려고 한 칸씩 더 둘레를 잰다.
	for j: int in k + 3:
		for i: int in k + 3:
			var p: Vector2 = Vector2(x0 + (i - 1) * step, z0 + (j - 1) * step)
			hs[j * (k + 3) + i] = height(p) if shaped else 0.0
	for j: int in k + 1:
		for i: int in k + 1:
			var h: float = hs[(j + 1) * (k + 3) + i + 1]
			verts.append(Vector3(x0 + i * step - cx, h, z0 + j * step - cz))
			var hl: float = hs[(j + 1) * (k + 3) + i]
			var hr: float = hs[(j + 1) * (k + 3) + i + 2]
			var hd: float = hs[j * (k + 3) + i + 1]
			var hu: float = hs[(j + 2) * (k + 3) + i + 1]
			normals.append(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
	for j: int in k:
		for i: int in k:
			var a: int = j * (k + 1) + i
			var b: int = a + 1
			var c: int = a + k + 1
			var d: int = c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 도시 끝 벽 (island 모양을 따라, 보이지 않는다) + 강 한가운데 south 줄 벽 + 보 자리 막이.
func _build_edge_walls() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "EdgeWalls"
	add_child(body)
	var half: float = _layout.island_half
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in wall_segments:
		var a: float = TAU * float(k) / float(wall_segments)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var shape: float = pow(pow(absf(dir.x), _layout.island_power) + pow(absf(dir.y), _layout.island_power), 1.0 / _layout.island_power)
		points.append(dir * (half - wall_inset) / shape)
	for k: int in points.size():
		var p: Vector2 = points[k]
		var q: Vector2 = points[(k + 1) % points.size()]
		if p.y > _layout.island_south and q.y > _layout.island_south:
			continue
		_wall(body, p, q, 3.0)
	if is_finite(_layout.island_south):
		_wall(body, Vector2(-half - 20.0, _layout.island_south), Vector2(half + 20.0, _layout.island_south), 3.0)
	# 보: 두 낚시터 물 막이 사이(1m 틈)를 막는다.
	if _city.weir.y < _city.weir.z:
		_wall(body, Vector2(_city.weir.x, _city.weir.y - 0.5), Vector2(_city.weir.x, _city.weir.z), 3.0, 2.4)


func _wall(body: StaticBody3D, p: Vector2, q: Vector2, height_m: float, thickness: float = 0.6) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(p.distance_to(q) + 0.4, height_m, thickness)
	shape.shape = box
	body.add_child(shape)
	var mid: Vector2 = (p + q) * 0.5
	shape.position = Vector3(mid.x, height_m * 0.5, mid.y)
	shape.rotation.y = -(q - p).angle()


## 강 건너 침수 수면: 다각형 둘레 4m 격자 (다각형 밖 한 칸까지 — 둘레 땅이 솟아 수면 끝을 덮는다).
func _build_flood_water() -> void:
	if _flood_poly.size() < 3 or water_material == null:
		return
	var lo: Vector2 = _flood_poly[0]
	var hi: Vector2 = _flood_poly[0]
	for p: Vector2 in _flood_poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var step: float = 4.0
	var center: Vector2 = (lo + hi) * 0.5
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var x: float = lo.x - step
	while x < hi.x + step:
		var z: float = lo.y - step
		while z < hi.y + step:
			var c: Vector2 = Vector2(x + step * 0.5, z + step * 0.5)
			if _poly_distance(c) < step * 1.5:
				var a: Vector3 = Vector3(x - center.x, 0.0, z - center.y)
				var b: Vector3 = a + Vector3(step, 0.0, 0.0)
				var cc: Vector3 = a + Vector3(0.0, 0.0, step)
				var d: Vector3 = a + Vector3(step, 0.0, step)
				for v: Vector3 in [a, b, cc, b, d, cc]:
					st.add_vertex(v)
			z += step
		x += step
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "FloodWater"
	water.mesh = st.commit()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: ShaderMaterial = water_material.duplicate()
	mat.set_shader_parameter("half_extent", Vector2(1000.0, 1000.0))
	# 흙탕물 (침수).
	mat.set_shader_parameter("shallow_color", Color(0.62, 0.56, 0.42))
	mat.set_shader_parameter("deep_color", Color(0.48, 0.44, 0.34))
	water.material_override = mat
	water.visibility_range_end = draw_distance + 200.0
	add_child(water)
	water.position = Vector3(center.x, _city.flood_level, center.y)


## 상점 실내 아래 바닥과 충돌체 (실내는 도시 밖 멀리 있어서 도시 바닥이 닿지 않는다).
func _build_shop_floor() -> void:
	if GameData.shop == null:
		return
	var center: Vector3 = GameData.shop.interior_center
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ShopFloor"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = Vector3(center.x, -0.5, center.z)
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_box(st, Vector3(center.x, -0.08, center.z), Vector3(60.0, 0.1, 60.0), Color("#6E5A44"), Basis())
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.name = "ShopGround"
	floor_mesh.mesh = ClayMesh.commit(st)
	floor_mesh.material_override = Puff.MATERIAL
	add_child(floor_mesh)
