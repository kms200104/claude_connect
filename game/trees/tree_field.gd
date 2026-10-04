class_name TreeField
extends Node3D
## 마을의 나무 전체. 위치는 data/world/trees.json(서버 판정과 같은 출처), 상태(다 자람/그루터기/묘목)는 서버가 알려 준다.
## 나무 한 그루 = 메시 1개(줄기·잎을 정점 색으로 칠해 머티리얼 1개) + 충돌체. 같은 모양은 메시를 공유한다.

@export var foliage_material: Material
## 이 거리보다 먼 나무는 그리지 않는다 (카메라 높이 포함).
@export_range(10.0, 200.0, 1.0, "suffix:m") var draw_distance: float = 55.0

const TRUNK_COLOR: Color = Color(0.48, 0.32, 0.2)
const LEAF_ROUND: Color = Color(0.42, 0.68, 0.36)
const LEAF_PINE: Color = Color(0.25, 0.5, 0.35)
const STUMP_TOP: Color = Color(0.78, 0.62, 0.42)

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


## 모양별 메시를 한 번만 만든다. 부위마다 정점 색을 칠해 머티리얼 1개로 그린다 (나무 1그루 = 드로우콜 1).
static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"pine":
			_add_part(st, _cylinder(0.18, 0.24, 1.2, 7), Transform3D(Basis(), Vector3(0, 0.6, 0)), TRUNK_COLOR)
			_add_part(st, _cylinder(0.0, 1.3, 1.8, 8), Transform3D(Basis(), Vector3(0, 1.9, 0)), LEAF_PINE)
			_add_part(st, _cylinder(0.0, 0.95, 1.5, 8), Transform3D(Basis(), Vector3(0, 2.9, 0)), LEAF_PINE.lightened(0.08))
		"stump":
			_add_part(st, _cylinder(0.32, 0.4, 0.45, 9), Transform3D(Basis(), Vector3(0, 0.22, 0)), TRUNK_COLOR)
			_add_part(st, _cylinder(0.3, 0.3, 0.02, 9), Transform3D(Basis(), Vector3(0, 0.455, 0)), STUMP_TOP)
		"sapling":
			_add_part(st, _cylinder(0.05, 0.07, 0.6, 6), Transform3D(Basis(), Vector3(0, 0.3, 0)), TRUNK_COLOR)
			_add_part(st, _sphere(0.32, 8, 5), Transform3D(Basis(), Vector3(0, 0.75, 0)), LEAF_ROUND.lightened(0.1))
		_:
			_add_part(st, _cylinder(0.2, 0.26, 1.5, 7), Transform3D(Basis(), Vector3(0, 0.75, 0)), TRUNK_COLOR)
			_add_part(st, _sphere(1.25, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.85, 1.0)), Vector3(0, 2.35, 0)), LEAF_ROUND)
	st.index()
	var mesh: ArrayMesh = st.commit()
	_meshes[kind] = mesh
	return mesh


static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func _sphere(radius: float, segments: int, rings: int) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func _add_part(st: SurfaceTool, primitive: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays: Array = primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis: Basis = xform.basis.inverse().transposed()
	for i: int in indices:
		st.set_color(color)
		st.set_normal((normal_basis * normals[i]).normalized())
		st.add_vertex(xform * verts[i])
