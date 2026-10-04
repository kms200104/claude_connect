class_name FlowerField
extends Node3D
## 마을에 심은 꽃 (서버가 알려 준다: Net.flowers). 새싹(떡잎) → 꽃봉오리 → 활짝 핀 꽃.
## 모양은 종류·색·단계마다 한 번만 만들어 공유하고, 정점 색 툰 머티리얼 1개로 그린다. 핀 꽃은 따면 봉오리로 돌아간다.

@export var clay_material: Material
## 이 거리보다 먼 꽃은 그리지 않는다.
@export_range(10.0, 200.0, 1.0, "suffix:m") var draw_distance: float = 45.0

const STEM: Color = Color("#5E9A4A")
const LEAF: Color = Color("#7FB86A")
const DIRT: Color = Color("#8A6A4A")

static var _meshes: Dictionary[String, ArrayMesh] = {}

var _nodes: Dictionary[String, MeshInstance3D] = {}


func _ready() -> void:
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _rebuild())
	Net.flower_changed.connect(_on_flower_changed)
	_rebuild()


## 활짝 핀 꽃 중 가장 가까운 것 (max_distance 안). 없으면 빈 문자열.
func nearest_bloom(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for f: FlowerState in Net.flowers.values():
		if f.stage != NetProtocol.FLOWER_BLOOM:
			continue
		var d: float = Vector2(position.x - f.position.x, position.z - f.position.z).length()
		if d <= best_d:
			best_d = d
			best = f.id
	return best


func flower_position(id: String) -> Vector3:
	var f: FlowerState = Net.flowers.get(id)
	return f.position if f != null else Vector3.ZERO


func has_flower(id: String) -> bool:
	return _nodes.has(id)


## 이 자리에 꽃을 심을 수 있을 만큼 다른 꽃과 떨어져 있는지 (서버와 같은 간격).
func clear_for(position: Vector3, clearance: float) -> bool:
	for f: FlowerState in Net.flowers.values():
		if Vector2(position.x - f.position.x, position.z - f.position.z).length() < clearance:
			return false
	return true


func _rebuild() -> void:
	for node: MeshInstance3D in _nodes.values():
		node.queue_free()
	_nodes.clear()
	for f: FlowerState in Net.flowers.values():
		_show(f, false)


func _on_flower_changed(f: FlowerState, by: int) -> void:
	var existed: bool = _nodes.has(f.id)
	var before: String = _nodes[f.id].get_meta("stage", "") if existed else ""
	_show(f, true)
	var node: MeshInstance3D = _nodes[f.id]
	if not existed:
		# 막 심었다: 흙이 튀고 새싹이 쏙.
		Puff.burst(self, f.position + Vector3(0.0, 0.05, 0.0), DIRT, 5, 0.35, 0.2, 0.06)
		if by != 0:
			Audio.play_at("dig", f.position, -2.0)
	elif before == NetProtocol.FLOWER_BLOOM and f.stage == NetProtocol.FLOWER_BUD:
		# 땄다: 꽃잎이 흩날린다.
		var species: FlowerSpecies = GameData.flowers.get(f.species)
		Puff.burst(self, f.position + Vector3(0.0, 0.4, 0.0), species.color(f.color_index) if species != null else Color.WHITE, 8, 0.5, 0.4, 0.05)
	elif f.stage != before:
		Audio.play_at("grow", f.position, -6.0, 1.2)
	node.scale = Vector3(0.6, 0.6, 0.6) if existed else Vector3(0.05, 0.05, 0.05)
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show(f: FlowerState, _animate: bool) -> void:
	var node: MeshInstance3D = _nodes.get(f.id)
	if node == null:
		node = MeshInstance3D.new()
		node.name = "Flower_%s" % f.id
		node.material_override = clay_material
		node.visibility_range_end = draw_distance
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.global_position = f.position
		node.rotation.y = float(f.id.hash() % 628) / 100.0
		_nodes[f.id] = node
	node.mesh = mesh_for(f.species, f.color_index, f.stage)
	node.set_meta("stage", f.stage)


## 종류·색·단계별 꽃 모양 (한 번 만들어 공유).
static func mesh_for(species_id: String, color_index: int, stage: String) -> ArrayMesh:
	var species: FlowerSpecies = GameData.flowers.get(species_id)
	var color: Color = species.color(color_index) if species != null else Color.WHITE
	var key: String = "%s/%d/%s" % [species_id, color_index, stage]
	if _meshes.has(key):
		return _meshes[key]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.01, 0.0), Vector3(0.18, 0.04, 0.18), DIRT, 8, 3)
	match stage:
		NetProtocol.FLOWER_SPROUT:
			ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 0.12, 0.0), 0.015, 0.012, STEM, 4)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_ellipsoid(st, Vector3(side * 0.06, 0.13, 0.0), Vector3(0.07, 0.02, 0.04), LEAF.lightened(0.15), 6, 2, Basis(Vector3.BACK, side * 0.4))
		NetProtocol.FLOWER_BUD:
			var h: float = _height(species_id) * 0.75
			_stem(st, h, species_id == "sunflower")
			ClayMesh.add_ellipsoid(st, Vector3(0.0, h + 0.05, 0.0), Vector3(0.05, 0.08, 0.05), ClayMesh.vertical_gradient(LEAF.darkened(0.1), color.lerp(LEAF, 0.4), 0.16), 8, 4)
		_:
			var h2: float = _height(species_id)
			_stem(st, h2, species_id == "sunflower")
			_bloom(st, species_id, color, Vector3(0.0, h2, 0.0))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_meshes[key] = mesh
	return mesh


static func _height(species_id: String) -> float:
	match species_id:
		"sunflower":
			return 0.62
		"hydrangea":
			return 0.32
		"cosmos":
			return 0.46
	return 0.38


static func _stem(st: SurfaceTool, h: float, thick: bool) -> void:
	ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, h, 0.0), 0.022 if thick else 0.014, 0.016 if thick else 0.011, STEM, 5)
	ClayMesh.add_ellipsoid(st, Vector3(0.06, h * 0.32, 0.0), Vector3(0.07, 0.02, 0.035), LEAF, 6, 2, Basis(Vector3.BACK, 0.5))
	ClayMesh.add_ellipsoid(st, Vector3(-0.055, h * 0.5, 0.01), Vector3(0.06, 0.02, 0.03), LEAF, 6, 2, Basis(Vector3.BACK, -0.5))


static func _bloom(st: SurfaceTool, species_id: String, color: Color, top: Vector3) -> void:
	var paint: Callable = ClayMesh.vertical_gradient(color.darkened(0.18), color.lightened(0.12), 0.15)
	match species_id:
		"tulip":
			ClayMesh.add_ellipsoid(st, top + Vector3(0.0, 0.07, 0.0), Vector3(0.075, 0.1, 0.075), paint, 10, 6)
			for k: int in 3:
				var a: float = TAU * float(k) / 3.0
				ClayMesh.add_ellipsoid(st, top + Vector3(cos(a) * 0.045, 0.1, sin(a) * 0.045), Vector3(0.045, 0.085, 0.03), paint, 6, 4, Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.25))
		"cosmos":
			for k: int in 8:
				var a: float = TAU * float(k) / 8.0
				ClayMesh.add_ellipsoid(st, top + Vector3(cos(a) * 0.075, 0.0, sin(a) * 0.075), Vector3(0.06, 0.012, 0.03), paint, 6, 2, Basis(Vector3.UP, -a))
			ClayMesh.add_ellipsoid(st, top + Vector3(0.0, 0.01, 0.0), Vector3(0.03, 0.02, 0.03), Color("#F2C14E"), 6, 2)
		"sunflower":
			# 해님 쪽(+Z 위)으로 고개를 든 큰 꽃.
			var face: Basis = Basis(Vector3.RIGHT, -0.9)
			for k: int in 12:
				var a: float = TAU * float(k) / 12.0
				ClayMesh.add_ellipsoid(st, top + face * Vector3(cos(a) * 0.12, 0.0, sin(a) * 0.12), Vector3(0.07, 0.014, 0.032), paint, 6, 2, face * Basis(Vector3.UP, -a))
			ClayMesh.add_ellipsoid(st, top + face * Vector3(0.0, 0.012, 0.0), Vector3(0.075, 0.03, 0.075), ClayMesh.vertical_gradient(Color("#4A2E18"), Color("#7A5230"), 0.05), 10, 3, face)
		_:
			# 수국: 작은 꽃이 공처럼 모였다.
			for k: int in 9:
				var a: float = TAU * float(k) / 7.0
				var off: Vector3 = Vector3(cos(a) * 0.07, 0.05 + 0.03 * float(k % 3), sin(a) * 0.07) if k < 7 else Vector3(0.0, 0.11 + 0.02 * float(k - 7), 0.0)
				ClayMesh.add_ellipsoid(st, top + off, Vector3(0.05, 0.045, 0.05), paint if k % 2 == 0 else ClayMesh.vertical_gradient(color.lightened(0.05), color.lightened(0.25), 0.15), 7, 4)
