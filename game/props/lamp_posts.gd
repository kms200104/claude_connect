class_name LampPosts
extends Node3D
## 광장 가로등: 자식 StaticBody3D 마다 Post(기둥)·Bulb(등불) 메시를 점토 느낌의 나무 기둥 + 작은 초롱으로 바꾼다.
## 위치·충돌체·불빛(OmniLight3D)은 씬에 둔 그대로 쓴다. 메시는 모두 공유한다.

## 정점 색을 쓰는 흰 툰 머티리얼 (기둥).
@export var clay_material: Material

const LANTERN_HEIGHT: float = 2.35

static var _post: ArrayMesh = null
static var _glass: ArrayMesh = null


func _ready() -> void:
	for lamp: Node in get_children():
		var post: MeshInstance3D = lamp.get_node_or_null("Post")
		var bulb: MeshInstance3D = lamp.get_node_or_null("Bulb")
		if post != null:
			post.mesh = _post_mesh()
			post.position = Vector3.ZERO
			post.material_override = clay_material
		if bulb != null:
			bulb.mesh = _glass_mesh()
			bulb.position = Vector3(0.0, LANTERN_HEIGHT, 0.0)


static func _post_mesh() -> ArrayMesh:
	if _post != null:
		return _post
	var st: SurfaceTool = ClayMesh.begin()
	var wood: Callable = ClayMesh.vertical_gradient(Color("#7A4E30"), Color("#B07A4A"), 1.0)
	var iron: Color = Color("#3F4A48")
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.2, 0.17, 0.0, 0.18, 0.05, 2), 10, Transform3D(), Color("#A7A39A"))
	ClayMesh.add_rod(st, Vector3(0.0, 0.15, 0.0), Vector3(0.0, LANTERN_HEIGHT + 0.45, 0.0), 0.085, 0.07, wood, 8)
	# 초롱 틀: 바닥판 · 네 기둥 · 지붕 · 고리.
	ClayMesh.add_rounded_box(st, Vector3(0.0, LANTERN_HEIGHT - 0.24, 0.0), Vector3(0.36, 0.06, 0.36), 0.3, iron, Basis(), 8, 4)
	for x: float in [-0.15, 0.15]:
		for z: float in [-0.15, 0.15]:
			ClayMesh.add_rod(st, Vector3(x, LANTERN_HEIGHT - 0.22, z), Vector3(x, LANTERN_HEIGHT + 0.2, z), 0.02, 0.02, iron, 4)
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.28, 0.05), Vector2(0.12, 0.2), Vector2(0.0, 0.24)]), 4,
			Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, LANTERN_HEIGHT + 0.2, 0.0)), Color("#4E5B58"))
	ClayMesh.add_torus(st, Vector3(0.0, LANTERN_HEIGHT + 0.5, 0.0), 0.05, 0.015, iron, 8, 3, Basis(Vector3.RIGHT, PI * 0.5))
	_post = ClayMesh.commit(st)
	return _post


static func _glass_mesh() -> ArrayMesh:
	if _glass != null:
		return _glass
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rounded_box(st, Vector3.ZERO, Vector3(0.27, 0.38, 0.27), 0.35, Color.WHITE, Basis(), 8, 6)
	_glass = ClayMesh.commit(st)
	return _glass
