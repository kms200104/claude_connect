class_name TreeField
extends Node3D
## 마을의 나무 전체. 위치는 data/world/trees.json(서버 판정과 같은 출처) + 씨앗을 심어 생긴 나무(서버가 알려 준다).
## 상태(새싹 → 묘목 → 어린 나무 → 다 자람, 베면 그루터기)는 서버가 알려 주고, 자랄 때마다 쑥 소리와 함께 통통 튄다.
## 나무 한 그루 = 메시 1개(줄기·잎을 정점 색으로 칠해 머티리얼 1개) + 충돌체. 같은 모양은 메시를 공유한다.

@export var foliage_material: Material
## 쓰러지는 방향(찍은 사람 반대쪽)을 정할 때 쓴다.
@export var player: Node3D
@export var replicator: PlayerReplicator
## 쓰러지는 데 걸리는 시간 (나무가 땅에 닿을 때 쿵 소리).
@export_range(0.3, 3.0, 0.05, "suffix:s") var fall_time: float = 0.8
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
## 코드로 빚은 나무의 줄기 반지름 (그루터기도 같은 굵기로).
const TRUNK_RADIUS: Dictionary[String, float] = {"round": 0.24, "pine": 0.2, "birch": 0.16}
const FLOWER_CENTER: Color = Color(1.0, 0.86, 0.4)
const NO_FLOWERS: Array[Color] = []
const FLOWER_COLORS: Array[Color] = [Color(0.98, 0.66, 0.74), Color(1.0, 0.86, 0.45), Color(0.62, 0.74, 0.98), Color(0.82, 0.66, 0.92)]

## 다 자란 나무 모양 → Tripo 모형 (tools/blender/import_tripo.py, v0.11.3). 없으면 코드로 빚은 나무.
const MODELS: Dictionary[String, String] = {"pine": "tree_pine", "round": "tree_round"}
## 그루터기 높이 (m). Tripo 모형의 그루터기 정보(<모형>.stump.json)도 이 높이에서 쟀다.
const STUMP_HEIGHT: float = 0.45

static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _leaf_mesh: ArrayMesh = null

var _trees: Dictionary[String, TreeNode] = {}
## 내가 쓰러뜨린 나무 → 시각(ms). 곧이어 오는 서버의 'tree' 알림으로 한 번 더 넘어지지 않게.
var _local_fells: Dictionary[String, int] = {}


class TreeNode:
	var info: TreeInfo
	var body: StaticBody3D
	var mesh: MeshInstance3D
	var shape: CollisionShape3D
	var stage: String = NetProtocol.TREE_GROWN
	var tween: Tween = null
	## 어린 나무는 다 자란 나무를 작게 줄여 그린다.
	var base_scale: float = 1.0


func _ready() -> void:
	for info: TreeInfo in GameData.trees.values():
		_trees[info.id] = _spawn(info)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _apply_all())
	Net.tree_planted.connect(_on_tree_planted)
	Net.tree_changed.connect(_on_tree_changed)
	Net.chop_succeeded.connect(_on_chop_succeeded)
	Net.peer_action.connect(_on_peer_action)
	Quality.changed.connect(_on_quality_changed)


## 화질이 바뀌면 Tripo 나무를 그 화질의 모형(고화질 원본 / 절약 _low)으로 바꿔 끼운다.
func _on_quality_changed() -> void:
	for kind: String in MODELS:
		_meshes.erase(kind)
	for node: TreeNode in _trees.values():
		_apply_stage(node, node.stage)


func _on_peer_action(_player_id: int, kind: String, target: String) -> void:
	if kind == "chop":
		shake(target)


func _on_chop_succeeded(id: String, _item: String, felled: bool) -> void:
	if felled and player != null:
		_local_fells[id] = Time.get_ticks_msec()
		fell(id, player.global_position)
	else:
		shake(id)


## 누군가 씨앗을 심었다: 새싹이 흙에서 쏙 올라온다.
func _on_tree_planted(info: TreeInfo) -> void:
	if _trees.has(info.id):
		return
	var node: TreeNode = _spawn(info)
	_trees[info.id] = node
	_apply_stage(node, Net.tree_stages.get(info.id, NetProtocol.TREE_SPROUT))
	node.mesh.scale = Vector3(0.01, 0.01, 0.01)
	create_tween().tween_property(node.mesh, "scale", Vector3.ONE * node.base_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Puff.burst(self, info.position + Vector3(0.0, 0.05, 0.0), Color("#8A6A4A"), 6, 0.5, 0.3, 0.07)


func _on_tree_changed(id: String, stage: String, _chops: int) -> void:
	var node: TreeNode = _trees.get(id)
	var was_grown: bool = node != null and node.stage == NetProtocol.TREE_GROWN
	var grew: bool = node != null and _stage_rank(stage) > _stage_rank(node.stage) and stage != NetProtocol.TREE_STUMP
	_set_stage(id, stage, true)
	if grew:
		# 한 단계 자랐다: 쑥 소리와 반짝이는 잎.
		Audio.play_at("grow", node.info.position + Vector3(0.0, 0.5, 0.0), -3.0)
		Puff.burst(self, node.info.position + Vector3(0.0, 0.4 + 0.6 * node.base_scale, 0.0), LEAF_ROUND.lightened(0.25), 7, 0.6, 0.5, 0.06)
	# 상대가 쓰러뜨린 나무: 가장 가까이 있는 사람 반대쪽으로 넘어진다 (내가 쓰러뜨린 건 이미 넘어지는 중).
	if stage == NetProtocol.TREE_STUMP and was_grown and Time.get_ticks_msec() - _local_fells.get(id, -100000) > 1500:
		fell(id, _nearest_chopper(tree_position(id)))


## 나무가 넘어지는 연출: 다 자란 나무 모양이 밑동을 축으로 from 반대쪽으로 점점 빠르게 넘어가 쿵 하고 튕긴 뒤,
## 잎사귀가 흩어지며 사라진다. 그동안 제자리에는 그루터기가 남는다. 충돌체 없음 (보기만).
func fell(id: String, from: Vector3) -> void:
	var node: TreeNode = _trees.get(id)
	if node == null:
		return
	var base: Vector3 = node.info.position
	var dir: Vector3 = Vector3(base.x - from.x, 0.0, base.z - from.z)
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var pivot: Node3D = Node3D.new()
	pivot.name = "Falling_%s" % id
	add_child(pivot)
	pivot.global_position = base
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.mesh = _mesh(node.info.kind)
	trunk.material_override = _material(node.info.kind)
	trunk.rotation.y = node.body.rotation.y
	pivot.add_child(trunk)
	var axis: Vector3 = Vector3.UP.cross(dir).normalized()
	var state: Dictionary = {"angle": 0.0}
	var apply: Callable = func(angle: float) -> void:
		state["angle"] = angle
		pivot.basis = Basis(axis, angle)
	var tween: Tween = create_tween()
	tween.tween_interval(0.12)
	tween.tween_method(apply, 0.0, deg_to_rad(86.0), fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		Audio.play_at("tree_land", base + dir * 2.0, 1.0, 1.0, 0.05)
		_leaf_puff(base + dir * 2.3 + Vector3(0.0, 0.6, 0.0), node.info.kind))
	tween.tween_method(apply, deg_to_rad(86.0), deg_to_rad(78.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(apply, deg_to_rad(78.0), deg_to_rad(88.0), 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_property(pivot, "scale", Vector3(0.01, 0.01, 0.01), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(pivot.queue_free)
	Audio.play_at("tree_creak", base + Vector3(0.0, 1.5, 0.0), -2.0)


## 쓰러진 나무에서 잎 덩어리가 사방으로 튀었다가 사라진다.
func _leaf_puff(center: Vector3, kind: String) -> void:
	var color: Color = LEAF_PINE if kind == "pine" else (LEAF_BIRCH if kind == "birch" else LEAF_ROUND)
	if _leaf_mesh == null:
		var st: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(0.12, 0.05, 0.08), Color.WHITE, 6, 3)
		_leaf_mesh = ClayMesh.commit(st)
	var material: ShaderMaterial = (foliage_material as ShaderMaterial).duplicate() if foliage_material is ShaderMaterial else null
	if material != null:
		material.set_shader_parameter("albedo", color)
	for i: int in 10:
		var leaf: MeshInstance3D = MeshInstance3D.new()
		leaf.mesh = _leaf_mesh
		leaf.material_override = material
		add_child(leaf)
		leaf.global_position = center
		leaf.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var out: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.2), randf_range(-1.0, 1.0)).normalized() * randf_range(0.8, 1.8)
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(leaf, "global_position", center + out, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(leaf, "rotation", leaf.rotation + Vector3(2.0, 3.0, 1.0), 0.9)
		tween.tween_property(leaf, "scale", Vector3(0.01, 0.01, 0.01), 0.5).set_delay(0.5)
		tween.chain().tween_callback(leaf.queue_free)


func _nearest_chopper(tree: Vector3) -> Vector3:
	var best: Vector3 = player.global_position if player != null else tree + Vector3.BACK
	if replicator != null:
		for p: Vector3 in replicator.remote_positions():
			if p.distance_to(tree) < best.distance_to(tree):
				best = p
	return best


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
	# 다른 마을의 심은 나무는 치우고, 이 마을의 심은 나무를 세운다.
	for id: String in _trees.keys():
		var node: TreeNode = _trees[id]
		if node.info.planted and not Net.planted_trees.has(id):
			node.body.queue_free()
			_trees.erase(id)
	for info: TreeInfo in Net.planted_trees.values():
		if not _trees.has(info.id):
			_trees[info.id] = _spawn(info)
	for id: String in _trees:
		_set_stage(id, Net.tree_stages.get(id, NetProtocol.TREE_GROWN), false)


## 자란 정도 (새싹 1 · 묘목 2 · 어린 나무 3 · 다 자람 4, 그루터기 0).
static func _stage_rank(stage: String) -> int:
	match stage:
		NetProtocol.TREE_SPROUT:
			return 1
		NetProtocol.TREE_SAPLING:
			return 2
		NetProtocol.TREE_YOUNG:
			return 3
		NetProtocol.TREE_GROWN:
			return 4
	return 0


## 이 자리에 나무를 심을 수 있을 만큼 다른 나무와 떨어져 있는지 (서버와 같은 간격).
func clear_for_tree(position: Vector3, clearance: float) -> bool:
	for node: TreeNode in _trees.values():
		if Vector2(position.x - node.info.position.x, position.z - node.info.position.z).length() < clearance:
			return false
	return true


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
		node.mesh.scale = Vector3(1.15, 0.7, 1.15) * node.base_scale
		create_tween().tween_property(node.mesh, "scale", Vector3.ONE * node.base_scale, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_stage(node: TreeNode, stage: String) -> void:
	node.stage = stage
	node.base_scale = 1.0
	var cylinder: CylinderShape3D = node.shape.shape
	node.mesh.material_override = foliage_material
	match stage:
		NetProtocol.TREE_SPROUT:
			node.mesh.mesh = _mesh("sprout")
			node.shape.disabled = true
		NetProtocol.TREE_YOUNG:
			node.mesh.mesh = _mesh(node.info.kind)
			node.mesh.material_override = _material(node.info.kind)
			node.base_scale = 0.62
			cylinder.radius = 0.3
			cylinder.height = 1.9
			node.shape.disabled = false
		NetProtocol.TREE_STUMP:
			# 그 나무의 줄기 굵기·껍질 색에 맞춘 그루터기.
			var stump: Dictionary = stump_info(node.info.kind)
			node.mesh.mesh = _mesh("stump_" + node.info.kind)
			cylinder.radius = maxf(float(stump["cut_radius"]) + 0.04, 0.2)
			cylinder.height = STUMP_HEIGHT + 0.05
			node.shape.disabled = false
		NetProtocol.TREE_SAPLING:
			node.mesh.mesh = _mesh("sapling")
			node.shape.disabled = true
		_:
			node.mesh.mesh = _mesh(node.info.kind)
			node.mesh.material_override = _material(node.info.kind)
			cylinder.radius = 0.4
			cylinder.height = 3.0
			node.shape.disabled = false
	node.mesh.scale = Vector3.ONE * node.base_scale
	node.shape.position = Vector3(0.0, cylinder.height * 0.5, 0.0)


## 다 자란 나무를 그릴 머티리얼: Tripo 모형이면 그 텍스처를 꽂은 툰 머티리얼, 아니면 정점 색 머티리얼.
func _material(kind: String) -> Material:
	return material_for_kind(kind, foliage_material)


static func material_for_kind(kind: String, fallback: Material) -> Material:
	if MODELS.has(kind) and PartMesh.load_model(MODELS[kind]) != null:
		return PartMesh.material_for(MODELS[kind], fallback)
	return fallback


## 나무 종류별 그루터기: {root_radius 뿌리 쪽 반지름, cut_radius 자른 곳 반지름, center 줄기 가운데(x, z), bark 껍질 색, birch 흰 껍질 무늬}.
## Tripo 모형은 가져올 때 잰 값(<모형>.stump.json), 코드로 빚은 나무는 그 줄기(_add_trunk)와 같은 값.
static func stump_info(kind: String) -> Dictionary:
	if MODELS.has(kind) and PartMesh.load_model(MODELS[kind]) != null:
		var path: String = "%s/%s.stump.json" % [PartMesh.MODEL_DIR, MODELS[kind]]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if parsed is Dictionary:
			var center: Array = (parsed as Dictionary).get("center", [0.0, 0.0])
			return {"root_radius": float(parsed.get("root_radius", 0.4)), "cut_radius": float(parsed.get("cut_radius", 0.3)),
				"center": Vector2(float(center[0]), float(center[1])), "bark": Color.html(str(parsed.get("bark", "#995F3D"))), "birch": false}
	var radius: float = TRUNK_RADIUS.get(kind, TRUNK_RADIUS["round"])
	# _add_trunk 의 윤곽: 바닥 1.9r → 0.12m 1.35r → 0.35m 1.05r.
	return {"root_radius": radius * 1.9, "cut_radius": radius * 1.04, "center": Vector2.ZERO,
		"bark": BIRCH_BARK if kind == "birch" else TRUNK_COLOR, "birch": kind == "birch"}


## 모양별 메시를 한 번만 만든다. 부위마다 정점 색을 칠해 머티리얼 1개로 그린다 (나무 1그루 = 드로우콜 1, 2,500 삼각형 이하 —
## 기준 기기(S24 · 폴드7)에 맞춰 둥근 면을 촘촘히. 화면에 동시에 보이는 나무는 10그루 남짓이고 draw_distance 밖은 그리지 않는다).
static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st: SurfaceTool = ClayMesh.begin()
	match kind:
		"pine" when _model("pine") != null:
			_meshes[kind] = _model("pine")
			return _meshes[kind]
		"round" when _model("round") != null:
			_meshes[kind] = _model("round")
			return _meshes[kind]
		"pine":
			_add_trunk(st, TRUNK_RADIUS["pine"], 1.0, TRUNK_COLOR)
			# 아래가 넓은 물결 모양 층 4개. 위로 갈수록 작고 밝다.
			var tiers: Array[Vector3] = [Vector3(1.35, 0.75, 1.15), Vector3(1.1, 1.45, 1.0), Vector3(0.85, 2.1, 0.9), Vector3(0.55, 2.7, 0.8)]
			for i: int in tiers.size():
				var tier: Vector3 = tiers[i]
				var color: Color = LEAF_PINE.lerp(LEAF_PINE_TIP, float(i) / 3.0)
				ClayMesh.add_lathe(st, _tier_profile(tier.x, tier.z), 27, Transform3D(Basis(), Vector3(0.0, tier.y, 0.0)),
						ClayMesh.vertical_gradient(color.darkened(0.18), color.lightened(0.08), 1.5), ClayMesh.scallop_wobble(9, 0.16, float(i)))
		"birch":
			_add_trunk(st, TRUNK_RADIUS["birch"], 1.9, BIRCH_BARK, true)
			_add_canopy(st, LEAF_BIRCH, 0.82, Vector3(0.0, 2.55, 0.0), 1.18, 41, NO_FLOWERS)
		"stump", "stump_round", "stump_pine", "stump_birch":
			_add_stump(st, stump_info(kind.trim_prefix("stump_") if kind != "stump" else "round"))
		"sprout":
			# 흙 둔덕 위에 떡잎 두 장.
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.02, 0.0), Vector3(0.28, 0.07, 0.28), Color("#8A6A4A"), 10, 3)
			ClayMesh.add_rod(st, Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.22, 0.0), 0.02, 0.016, Color("#6FA35A"), 5)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_ellipsoid(st, Vector3(side * 0.08, 0.24, 0.0), Vector3(0.09, 0.025, 0.05), LEAF_ROUND.lightened(0.22), 8, 3, Basis(Vector3.BACK, side * 0.4))
		"sapling":
			ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 0.62, 0.0), 0.05, 0.035, TRUNK_COLOR, 6)
			for i: int in 3:
				var a: float = TAU * float(i) / 3.0 + 0.4
				var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
				ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.55 + 0.08 * i, 0.0) + dir * 0.16, Vector3(0.17, 0.06, 0.1), LEAF_ROUND.lightened(0.12), 8, 4, Basis(Vector3.UP, -a))
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.7, 0.0), Vector3(0.14, 0.16, 0.14), LEAF_ROUND.lightened(0.18), 8, 5)
		_:
			_add_trunk(st, TRUNK_RADIUS["round"], 1.5, TRUNK_COLOR)
			_add_canopy(st, LEAF_ROUND, 1.0, Vector3(0.0, 2.35, 0.0), 1.0, 7, FLOWER_COLORS)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_meshes[kind] = mesh
	return mesh


## 다 자란 나무의 Tripo 모형 (없으면 null).
static func _model(kind: String) -> ArrayMesh:
	return PartMesh.load_model(MODELS[kind]) if MODELS.has(kind) else null


## 그루터기: 뿌리 쪽이 퍼진 밑동을 자른 높이까지, 옆은 그 나무의 껍질 색(세로 골), 윗면은 나이테 (굵을수록 고리가 많다).
## 자작나무는 흰 껍질에 검은 가로 무늬. 줄기 가운데(center)가 모형 원점에서 비켜 있으면 그만큼 옮긴다.
static func _add_stump(st: SurfaceTool, info: Dictionary) -> void:
	var root: float = float(info["root_radius"])
	var cut: float = float(info["cut_radius"])
	var bark: Color = info["bark"]
	var birch: bool = bool(info["birch"])
	var center: Vector2 = info["center"]
	var h: float = STUMP_HEIGHT
	var profile: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(root, 0.0), Vector2(lerpf(root, cut, 0.55), 0.06), Vector2(lerpf(root, cut, 0.85), 0.16),
		Vector2(cut * 1.01, h * 0.6), Vector2(cut, h - 0.03), Vector2(cut * 0.97, h), Vector2(cut * 0.9, h + 0.005), Vector2(0.0, h + 0.01)])
	var paint: Callable = func(local: Vector3, normal: Vector3) -> Color:
		var p: Vector2 = Vector2(local.x - center.x, local.z - center.y)
		if normal.y > 0.8 and p.length() < cut * 0.92:
			# 나이테: 가운데에서 멀어질수록 밝고 어두운 고리가 번갈아, 가장자리는 껍질 안쪽(형성층)이 조금 짙다.
			var ring: float = sin(p.length() * 70.0)
			var wood: Color = STUMP_TOP.lerp(STUMP_TOP.darkened(0.18), clampf(ring * 0.5 + 0.5, 0.0, 1.0) * 0.6)
			return wood.darkened(0.12 * smoothstep(0.75, 0.92, p.length() / cut))
		if birch:
			var band: float = sin(local.y * 9.0 + sin(atan2(p.y, p.x) * 3.0) * 1.3)
			return BIRCH_MARK if band > 0.72 else bark.darkened(0.04 * (1.0 - local.y / h))
		# 껍질: 세로 골을 따라 조금씩 어둡고, 뿌리 쪽이 더 짙다.
		var groove: float = 0.5 + 0.5 * sin(atan2(p.y, p.x) * 11.0 + local.y * 3.0)
		return bark.darkened(0.02 + 0.07 * groove + 0.07 * (1.0 - local.y / h))
	var segments: int = clampi(int(round(cut * 60.0)) + 14, 18, 40)
	ClayMesh.add_lathe(st, profile, segments, Transform3D(Basis(), Vector3(center.x, 0.0, center.y)), paint, ClayMesh.blob_wobble(5, 0.06, 4))


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
	ClayMesh.add_lathe(st, profile, 14, Transform3D(), paint, ClayMesh.blob_wobble(5, 0.12, 4))


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
		ClayMesh.add_ellipsoid(st, c, Vector3(r, r * stretch_y * 0.9, r), paint, 18, 13, Basis(), ClayMesh.blob_wobble(rng.randi(), 0.07, 7))
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
