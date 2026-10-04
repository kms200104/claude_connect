class_name Puff
extends RefCounted
## 작은 점토 덩어리가 사방으로 튀었다가 줄어들며 사라지는 효과 (흙먼지·흙 파기·반짝임).
## 색은 정점 색에 구워 두고 마을 공용 툰 머티리얼을 그대로 쓴다 (머티리얼을 새로 만들지 않는다).

const MATERIAL: Material = preload("res://assets/materials/foliage.tres")

static var _meshes: Dictionary[Color, ArrayMesh] = {}


## parent 아래에 count 개를 center 에서 튀긴다. spread = 퍼지는 거리, rise = 위로 솟는 정도, size = 덩어리 반지름.
static func burst(parent: Node, center: Vector3, color: Color, count: int = 8, spread: float = 0.7, rise: float = 0.35, size: float = 0.09, life: float = 0.55) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mesh: ArrayMesh = _mesh(color)
	for i: int in count:
		var blob: MeshInstance3D = MeshInstance3D.new()
		blob.mesh = mesh
		blob.material_override = MATERIAL
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(blob)
		blob.global_position = center
		var s: float = size * randf_range(0.7, 1.3)
		blob.scale = Vector3.ONE * s
		var a: float = randf() * TAU
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a)) * spread * randf_range(0.5, 1.0) + Vector3(0.0, rise * randf_range(0.5, 1.0), 0.0)
		var tween: Tween = blob.create_tween().set_parallel(true)
		tween.tween_property(blob, "global_position", center + out, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(blob, "scale", Vector3.ONE * s * 1.6, life * 0.5)
		tween.chain().tween_property(blob, "scale", Vector3.ONE * 0.001, life * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(blob.queue_free)


## 발밑 흙먼지 (풀밭은 연두, 흙길은 모래색, 돌 광장은 연한 베이지, 활주로는 회색, 젖은 모래는 물보라).
static func dust_color(position: Vector3) -> Color:
	match Footsteps.surface_of(position):
		"wood":
			return Color("#C9A37A")
		"dirt":
			return Color("#E3CFA4")
		"stone":
			return Color("#EBDDC0")
		"metal":
			return Color("#B9BCC2")
		"water":
			return Color("#CFE9EE")
	return Color("#C8DCA0")


static func _mesh(color: Color) -> ArrayMesh:
	if not _meshes.has(color):
		var st: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3.ONE, color, 7, 4)
		_meshes[color] = ClayMesh.commit(st)
	return _meshes[color]
