class_name IslandTerrain
extends Node3D
## 섬 지형: 바닥 메시(안쪽은 평평하고 모래사장 끝에서 바닷속으로 비스듬히 내려간다), 섬을 둘러싼 바다,
## 바다로 걸어 들어가지 못하게 해안선을 따라 세운 보이지 않는 벽. 모양은 village_layout.json 의 island.
## 바다는 호수와 같은 물 셰이더를 쓴다 (셰이더를 늘리지 않는다). 상점 실내(바다 너머 멀리)에서는 바다를 숨긴다.

@export var ground_mesh: MeshInstance3D
@export var ground_shape: CollisionShape3D
@export var water_material: ShaderMaterial
## 바닥 정점 간격 (월드 커브가 매끄럽게 휘도록 촘촘히).
@export_range(0.5, 8.0, 0.5, "suffix:m") var cell: float = 2.0
## 바닥을 깔 범위 (가운데 ±미터).
@export_range(50.0, 300.0, 1.0, "suffix:m") var extent: float = 124.0
## 바다 수면 높이.
@export_range(-2.0, 0.0, 0.01, "suffix:m") var sea_level: float = -0.28
## 해안선 너머 바닥 깊이.
@export_range(0.2, 5.0, 0.1, "suffix:m") var sea_depth: float = 1.8
## 해안 벽을 해안선에서 얼마나 안쪽에 세울지 (물가 젖은 모래까지는 걸을 수 있게).
@export_range(0.0, 5.0, 0.1, "suffix:m") var wall_inset: float = 1.0
@export_range(16, 256) var wall_segments: int = 120
## 상점 안에 들어가면 바다를 숨긴다 (실내가 바다 너머에 있다).
@export var player: Node3D

var _ocean: MeshInstance3D = null
var _layout: VillageLayout = null


func _ready() -> void:
	_layout = GameData.layout
	if _layout == null or _layout.island_half <= 0.0:
		return
	if ground_mesh != null:
		# 메시를 바꾸면 표면별 머티리얼이 풀리므로 머티리얼을 통째로 옮겨 단다.
		var ground_material: Material = ground_mesh.get_surface_override_material(0) if ground_mesh.mesh != null else null
		ground_mesh.mesh = _build_ground()
		if ground_material != null:
			ground_mesh.material_override = ground_material
	if ground_shape != null and ground_shape.shape is BoxShape3D:
		(ground_shape.shape as BoxShape3D).size = Vector3(extent * 2.0, 1.0, extent * 2.0)
	_build_ocean()
	_build_coast_walls()
	_build_shop_floor()


func _process(_delta: float) -> void:
	if _ocean != null and player != null and GameData.shop != null:
		_ocean.visible = not GameData.shop.is_inside(player.global_position)


## 해안선까지의 거리 (안쪽이 음수, 미터).
func coast_distance(point: Vector2) -> float:
	return (_layout.island_shape(point) - 1.0) * _layout.island_half


func _height(point: Vector2) -> float:
	var d: float = coast_distance(point)
	# 모래사장 끝(해안선 2m 안쪽)부터 바닷속으로 부드럽게 내려간다.
	return -sea_depth * smoothstep(-2.0, 6.0, d)


func _build_ground() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = int(extent * 2.0 / cell)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for j: int in n + 1:
		for i: int in n + 1:
			heights[j * (n + 1) + i] = _height(Vector2(-extent + i * cell, -extent + j * cell))
	for j: int in n:
		for i: int in n:
			var x0: float = -extent + i * cell
			var z0: float = -extent + j * cell
			var a: Vector3 = Vector3(x0, heights[j * (n + 1) + i], z0)
			var b: Vector3 = Vector3(x0 + cell, heights[j * (n + 1) + i + 1], z0)
			var c: Vector3 = Vector3(x0, heights[(j + 1) * (n + 1) + i], z0 + cell)
			var d: Vector3 = Vector3(x0 + cell, heights[(j + 1) * (n + 1) + i + 1], z0 + cell)
			for v: Vector3 in [a, b, c, b, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _build_ocean() -> void:
	_ocean = MeshInstance3D.new()
	_ocean.name = "Ocean"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	plane.subdivide_width = 99
	plane.subdivide_depth = 99
	_ocean.mesh = plane
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if water_material != null:
		var sea: ShaderMaterial = water_material.duplicate()
		# 물 셰이더는 half_extent 밖을 잘라 내므로 바다 전체를 덮도록 크게 잡는다 (물가 거품 띠는 보이지 않는 먼 곳).
		sea.set_shader_parameter("half_extent", Vector2(1000.0, 1000.0))
		sea.set_shader_parameter("shallow_color", Color(0.5, 0.84, 0.86))
		sea.set_shader_parameter("deep_color", Color(0.34, 0.68, 0.82))
		_ocean.material_override = sea
	add_child(_ocean)
	_ocean.position = Vector3(0.0, sea_level, 0.0)


## 해안선 안쪽을 따라 낮은 벽 조각을 이어 세운다 (보이지 않는다).
func _build_coast_walls() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "CoastWalls"
	add_child(body)
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in wall_segments:
		var a: float = TAU * float(k) / float(wall_segments)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		# 이 방향의 해안선까지 거리: 섬 모양 값이 1 - inset/half 가 되는 반지름.
		var target: float = 1.0 - wall_inset / _layout.island_half
		var r: float = _layout.island_half * target / _layout.island_shape(dir * _layout.island_half)
		points.append(dir * r)
	for k: int in points.size():
		var p: Vector2 = points[k]
		var q: Vector2 = points[(k + 1) % points.size()]
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(p.distance_to(q) + 0.4, 3.0, 0.6)
		shape.shape = box
		body.add_child(shape)
		var mid: Vector2 = (p + q) * 0.5
		shape.position = Vector3(mid.x, 1.5, mid.y)
		shape.rotation.y = -(q - p).angle()


## 상점 실내 아래 바닥과 충돌체 (실내는 바다 너머 멀리 있어서 섬 바닥이 닿지 않는다).
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
