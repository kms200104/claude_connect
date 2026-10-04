class_name TreeField
extends Node3D
## 마을의 나무 전체. 위치는 data/world/trees.json(서버 판정과 같은 출처), 상태(다 자람/그루터기/묘목)는 서버가 알려 준다.
## 나무 한 그루 = 메시 1개(줄기·잎을 정점 색으로 칠해 머티리얼 1개) + 충돌체. 같은 모양은 메시를 공유한다.

@export var foliage_material: Material
## 이 거리보다 먼 나무는 그리지 않는다 (카메라 높이 포함).
@export_range(10.0, 200.0, 1.0, "suffix:m") var draw_distance: float = 55.0

const TRUNK_COLOR: Color = Color(0.6, 0.38, 0.24)
const LEAF_ROUND: Color = Color(0.45, 0.7, 0.4)
const LEAF_PINE: Color = Color(0.27, 0.52, 0.36)
const LEAF_PINE_TIP: Color = Color(0.36, 0.62, 0.42)
const LEAF_BIRCH: Color = Color(0.58, 0.76, 0.4)
const BIRCH_BARK: Color = Color(0.93, 0.91, 0.86)
const BIRCH_MARK: Color = Color(0.25, 0.22, 0.2)
const STUMP_TOP: Color = Color(0.86, 0.7, 0.5)
const FLOWER_CENTER: Color = Color(1.0, 0.86, 0.4)
const NO_FLOWERS: Array[Color] = []
const FLOWER_COLORS: Array[Color] = [Color(0.98, 0.66, 0.74), Color(1.0, 0.86, 0.45), Color(0.62, 0.74, 0.98), Color(0.82, 0.66, 0.92)]

static var _meshes: Dictionary[String, ArrayMesh] = {}

var _trees: Dictionary[String, TreeNode] = {}


class TreeNode:
	var info: TreeInfo
	var body: StaticBody3D
	var mesh: MeshInstance3D
	var shape: CollisionShape3D
	var stage: String = NetProtocol.TREE_GROWN
	var tween: Tween = null


func _ready() -> void:
	for info: TreeInfo in GameData.trees.values():
		_trees[info.id] = _spawn(info)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _apply_all())
	Net.tree_changed.connect(func(id: String, stage: String, _chops: int) -> void: _set_stage(id, stage, true))
	Net.chop_succeeded.connect(func(id: String, _item: String, _felled: bool) -> void: shake(id))
	Net.peer_action.connect(_on_peer_action)


func _on_peer_action(_player_id: int, kind: String, target: String) -> void:
	if kind == "chop":
		shake(target)


## 다 자란 나무 중 가장 가까운 것 (max_distance 안). 없으면 빈 문자열.
func nearest_grown(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for node: TreeNode in _trees.values():
		if node.stage != NetProtocol.TREE_GROWN:
			continue
		var d: float = Vector2(position.x - node.info.position.x, position.z - node.info.position.z).length()
		if d <= best_d:
			best_d = d
			best = node.info.id
	return best


func tree_position(id: String) -> Vector3:
	var node: TreeNode = _trees.get(id)
	return node.info.position if node != null else Vector3.ZERO


func stage_of(id: String) -> String:
	var node: TreeNode = _trees.get(id)
	return node.stage if node != null else ""


## 도끼에 맞은 나무가 흔들린다.
func shake(id: String) -> void:
	var node: TreeNode = _trees.get(id)
	if node == null:
		return
	if node.tween != null and node.tween.is_valid():
		node.tween.kill()
	node.mesh.rotation = Vector3.ZERO
	node.tween = create_tween()
	node.tween.tween_property(node.mesh, "rotation:z", 0.08, 0.06)
	node.tween.tween_property(node.mesh, "rotation:z", -0.06, 0.1)
	node.tween.tween_property(node.mesh, "rotation:z", 0.0, 0.12)


func _apply_all() -> void:
	for id: String in _trees:
		_set_stage(id, Net.tree_stages.get(id, NetProtocol.TREE_GROWN), false)


func _spawn(info: TreeInfo) -> TreeNode:
	var node: TreeNode = TreeNode.new()
	node.info = info
	node.body = StaticBody3D.new()
	node.body.name = "Tree_%s" % info.id
	add_child(node.body)
	node.body.global_position = info.position
	# 같은 종류라도 조금씩 돌려 놓아 복사한 티가 덜 나게 한다 (id로 정해서 매번 같다).
	node.body.rotation.y = float(info.id.hash() % 628) / 100.0
	node.mesh = MeshInstance3D.new()
	node.mesh.material_override = foliage_material
	node.mesh.visibility_range_end = draw_distance
	node.body.add_child(node.mesh)
	node.shape = CollisionShape3D.new()
	node.shape.shape = CylinderShape3D.new()
	node.body.add_child(node.shape)
	_apply_stage(node, NetProtocol.TREE_GROWN)
	return node


func _set_stage(id: String, stage: String, animate: bool) -> void:
	var node: TreeNode = _trees.get(id)
	if node == null or node.stage == stage:
		return
	_apply_stage(node, stage)
	if animate:
		# 쓰러지거나 자라날 때 살짝 튀어 오르는 연출.
		node.mesh.scale = Vector3(1.15, 0.7, 1.15)
		create_tween().tween_property(node.mesh, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_stage(node: TreeNode, stage: String) -> void:
	node.stage = stage
	var cylinder: CylinderShape3D = node.shape.shape
	match stage:
		NetProtocol.TREE_STUMP:
			node.mesh.mesh = _mesh("stump")
			cylinder.radius = 0.45
			cylinder.height = 0.5
			node.shape.disabled = false
		NetProtocol.TREE_SAPLING:
			node.mesh.mesh = _mesh("sapling")
			node.shape.disabled = true
		_:
			node.mesh.mesh = _mesh(node.info.kind)
			cylinder.radius = 0.4
			cylinder.height = 3.0
			node.shape.disabled = false
	node.shape.position = Vector3(0.0, cylinder.height * 0.5, 0.0)


## 모양별 메시를 한 번만 만든다. 부위마다 정점 색을 칠해 머티리얼 1개로 그린다 (나무 1그루 = 드로우콜 1, 1,200 삼각형 이하).
static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st: SurfaceTool = ClayMesh.begin()
	match kind:
		"pine":
			_add_trunk(st, 0.2, 1.0, TRUNK_COLOR)
			# 아래가 넓은 물결 모양 층 4개. 위로 갈수록 작고 밝다.
			var tiers: Array[Vector3] = [Vector3(1.35, 0.75, 1.15), Vector3(1.1, 1.45, 1.0), Vector3(0.85, 2.1, 0.9), Vector3(0.55, 2.7, 0.8)]
			for i: int in tiers.size():
				var tier: Vector3 = tiers[i]
				var color: Color = LEAF_PINE.lerp(LEAF_PINE_TIP, float(i) / 3.0)
				ClayMesh.add_lathe(st, _tier_profile(tier.x, tier.z), 18, Transform3D(Basis(), Vector3(0.0, tier.y, 0.0)),
						ClayMesh.vertical_gradient(color.darkened(0.18), color.lightened(0.08), 1.5), ClayMesh.scallop_wobble(9, 0.16, float(i)))
		"birch":
			_add_trunk(st, 0.16, 1.9, BIRCH_BARK, true)
			_add_canopy(st, LEAF_BIRCH, 0.82, Vector3(0.0, 2.55, 0.0), 1.18, 41, NO_FLOWERS)
		"stump":
			var stump_color: Callable = func(local: Vector3, normal: Vector3) -> Color:
				if normal.y > 0.8:
					# 나이테: 가운데에서 멀어질수록 밝고 어두운 고리가 번갈아.
					var ring: float = sin(Vector2(local.x, local.z).length() * 38.0)
					return STUMP_TOP.lerp(STUMP_TOP.darkened(0.18), clampf(ring * 0.5 + 0.5, 0.0, 1.0) * 0.6)
				return TRUNK_COLOR.darkened(0.08 * (1.0 - local.y))
			ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.46, 0.36, 0.0, 0.45, 0.05, 2), 14, Transform3D(), stump_color)
		"sapling":
			ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 0.62, 0.0), 0.05, 0.035, TRUNK_COLOR, 6)
			for i: int in 3:
				var a: float = TAU * float(i) / 3.0 + 0.4
				var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
				ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.55 + 0.08 * i, 0.0) + dir * 0.16, Vector3(0.17, 0.06, 0.1), LEAF_ROUND.lightened(0.12), 8, 4, Basis(Vector3.UP, -a))
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.7, 0.0), Vector3(0.14, 0.16, 0.14), LEAF_ROUND.lightened(0.18), 8, 5)
		_:
			_add_trunk(st, 0.24, 1.5, TRUNK_COLOR)
			_add_canopy(st, LEAF_ROUND, 1.0, Vector3(0.0, 2.35, 0.0), 1.0, 7, FLOWER_COLORS)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_meshes[kind] = mesh
	return mesh


## 뿌리 쪽이 넓게 퍼진 줄기. 자작나무는 흰 껍질에 검은 무늬.
static func _add_trunk(st: SurfaceTool, radius: float, height: float, color: Color, birch: bool = false) -> void:
	var profile: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(radius * 1.9, 0.0), Vector2(radius * 1.35, 0.12), Vector2(radius * 1.05, 0.35),
		Vector2(radius, height * 0.6), Vector2(radius * 0.85, height), Vector2(0.0, height + 0.05)])
	var paint: Variant = color
	if birch:
		paint = func(local: Vector3, _normal: Vector3) -> Color:
			var band: float = sin(local.y * 9.0 + sin(atan2(local.z, local.x) * 3.0) * 1.3)
			return BIRCH_MARK if band > 0.72 else color
	ClayMesh.add_lathe(st, profile, 9, Transform3D(), paint, ClayMesh.blob_wobble(5, 0.12, 4))


## 둥글게 부푼 잎 덩어리 세 개(위 하나, 옆 둘) + 겉에 박힌 작은 꽃. 덩어리 겉은 잔물결로 몽글몽글하게.
static func _add_canopy(st: SurfaceTool, leaf: Color, size: float, center: Vector3, stretch_y: float, seed_value: int, flowers: Array[Color]) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var paint: Callable = ClayMesh.vertical_gradient(leaf.darkened(0.28), leaf.lightened(0.16), 1.1)
	var spin: float = rng.randf() * TAU
	var lumps: Array[Vector4] = [Vector4(0.05, 0.32, 0.05, 0.92)]
	for i: int in 3:
		var a: float = spin + TAU * float(i) / 3.0
		lumps.append(Vector4(cos(a) * 0.62, rng.randf_range(-0.22, -0.08), sin(a) * 0.62, rng.randf_range(0.7, 0.8)))
	for lump: Vector4 in lumps:
		var c: Vector3 = center + Vector3(lump.x, lump.y * stretch_y, lump.z) * size
		var r: float = lump.w * size
		ClayMesh.add_ellipsoid(st, c, Vector3(r, r * stretch_y * 0.9, r), paint, 12, 9, Basis(), ClayMesh.blob_wobble(rng.randi(), 0.07, 7))
	if flowers.is_empty():
		return
	# 바깥·위쪽을 향한 자리에만 꽃을 박는다 (안쪽에 묻힌 꽃은 안 보이니 만들지 않는다). 꽃 하나 = 삼각형 20개.
	var placed: int = 0
	var tries: int = 0
	while placed < 16 and tries < 200:
		tries += 1
		var lump: Vector4 = lumps[rng.randi() % lumps.size()]
		var dir: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.1, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var lump_center: Vector3 = center + Vector3(lump.x, lump.y * stretch_y, lump.z) * size
		var surface: Vector3 = lump_center + Vector3(dir.x, dir.y * stretch_y * 0.9, dir.z) * lump.w * size
		var outward: Vector3 = surface - center
		if outward.normalized().dot(dir) < 0.35:
			continue
		var flower_basis: Basis = ClayMesh._basis_along(dir)
		var at: Vector3 = surface + dir * 0.04
		ClayMesh.add_ellipsoid(st, at, Vector3(0.12, 0.03, 0.12), flowers[placed % flowers.size()], 6, 2, flower_basis, ClayMesh.scallop_wobble(5, 0.5))
		ClayMesh.add_ellipsoid(st, at + dir * 0.025, Vector3(0.04, 0.025, 0.04), FLOWER_CENTER, 4, 2, flower_basis)
		placed += 1


## 소나무 한 층: 아래 테두리가 둥글게 말린 원뿔.
static func _tier_profile(radius: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -0.05), Vector2(radius * 0.7, -0.04), Vector2(radius * 0.97, 0.02), Vector2(radius, 0.1),
		Vector2(radius * 0.8, 0.22), Vector2(radius * 0.45, height * 0.6), Vector2(radius * 0.12, height * 0.92), Vector2(0.0, height)])
