class_name PartMesh
extends RefCounted
## 데이터의 도형 목록({s, size, at, c, …})으로 메시 하나를 만든다. 가구·옷·상점 장식·아이템 모형이 쓴다.
## 도형마다 정점 색을 칠해 머티리얼 1개(foliage.tres 처럼 흰 툰 머티리얼)로 그리므로 물건 하나 = 드로우콜 1.
##   s: box(size = [x, y, z]) / cyl(size = [반지름, 높이]) / cone(size = [밑 반지름, 높이]) / sphere(size = [반지름] 또는 [x, y, z])
##      rbox(모서리가 둥근 상자, size = [x, y, z], r = 둥근 정도 0.1~1) / torus(size = [고리 반지름, 굵기])
##      cap(둥근 막대, at → to, size = [반지름]) / rod(막대, at → to, size = [시작 반지름, 끝 반지름])
##      blob(울퉁불퉁한 덩어리, size = [x, y, z], seed)
##   at: 가운데 위치 [x, y, z] (cap·rod 는 시작점), c: "#RRGGBB" 또는 [아래 색, 위 색](세로 그라데이션)
##   rot: [x, y, z] 도 단위 회전 (선택), r: cyl·cone 의 모서리 둥글기 (선택, 없으면 각진 원기둥)

static var _cache: Dictionary[String, ArrayMesh] = {}
## false 면(절약 화질) 줄인 모형 <key>_low.glb 를 먼저 찾는다. Quality 가 정하고 바꾸면 clear_cache() 한다.
static var full_models: bool = true
## 둥근 도형을 나누는 칸 수 배율 (화질의 mesh_detail). 바꾸면 clear_cache().
static var detail: float = 1.0
## 텍스처를 쓰는 모형(<key>.jpg|png 가 함께 있는 Tripo 모형)의 툰 머티리얼. key 로 한 번만 만든다.
static var _materials: Dictionary[String, Material] = {}
const TOON_SHADER: String = "res://assets/shaders/toon_world.gdshader"


## key 모형의 머티리얼: 같은 이름의 텍스처가 있으면 그 텍스처를 꽂은 툰 머티리얼, 없으면 fallback (정점 색 모형).
## 모형을 그리는 곳은 material_override 에 이것을 넣는다.
static func material_for(key: String, fallback: Material) -> Material:
	if _materials.has(key):
		return _materials[key]
	var texture: Texture2D = null
	for ext: String in ["jpg", "png"]:
		var path: String = "%s/%s.%s" % [MODEL_DIR, key, ext]
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
			break
	if texture == null:
		return fallback
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(TOON_SHADER)
	material.set_shader_parameter("albedo_texture", texture)
	_materials[key] = material
	return material


## 화질이 바뀌었을 때: 만들어 둔 메시를 버린다 (다음에 찾을 때 그 화질의 모형으로 다시 만든다).
static func clear_cache() -> void:
	_cache.clear()


## Blender 로 다시 만든 모형 (tools/blender/build_items.py, v0.11): 있으면 절차 모형 대신 쓴다.
const MODEL_DIR: String = "res://assets/models/items"


## key 로 한 번만 만든다 (같은 아이템은 메시 공유). Blender 모형(<key>.glb)이 있으면 그것을 쓴다.
static func get_mesh(key: String, parts: Array) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var mesh: ArrayMesh = load_model(key)
	if mesh == null:
		mesh = build(parts)
	_cache[key] = mesh
	return mesh


## assets/models/items/<key>.glb 의 첫 메시. 없거나 읽지 못하면 null.
## 절약 화질이면 폴리곤을 줄인 <key>_low.glb 가 있을 때 그것을 쓴다 (tools/blender/import_tripo.py).
static func load_model(key: String) -> ArrayMesh:
	var path: String = "%s/%s.glb" % [MODEL_DIR, key]
	var low: String = "%s/%s_low.glb" % [MODEL_DIR, key]
	if not full_models and ResourceLoader.exists(low):
		path = low
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: ArrayMesh = (found[0] as MeshInstance3D).mesh as ArrayMesh if not found.is_empty() else null
	root.free()
	return mesh


static func build(parts: Array) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var added: int = 0
	for part: Variant in parts:
		if part is Dictionary and _add_part(st, part):
			added += 1
	if added == 0:
		ClayMesh.add_primitive(st, BoxMesh.new(), Transform3D(Basis(), Vector3(0, 0.5, 0)), Color.MAGENTA)
	return ClayMesh.commit(st)


## 이미 시작한 SurfaceTool 에 도형 목록을 덧붙인다 (다른 메시와 합칠 때). 붙인 도형 수를 돌려준다.
static func append(st: SurfaceTool, parts: Array) -> int:
	var added: int = 0
	for part: Variant in parts:
		if part is Dictionary and _add_part(st, part):
			added += 1
	return added


static func add_primitive(st: SurfaceTool, primitive: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	ClayMesh.add_primitive(st, primitive, xform, color)


static func _add_part(st: SurfaceTool, part: Dictionary) -> bool:
	var shape: String = str(part.get("s", "box"))
	var v: Array = part.get("size", [0.5]) if part.get("size") is Array else [0.5]
	var a: float = float(v[0]) if v.size() > 0 else 0.5
	var b: float = float(v[1]) if v.size() > 1 else a
	var c: float = float(v[2]) if v.size() > 2 else a
	var at: Vector3 = _vec(part.get("at", [0, 0, 0]))
	var basis: Basis = Basis.from_euler(_vec(part.get("rot", [0, 0, 0])) * (PI / 180.0)) if part.has("rot") else Basis()
	var paint: Variant = _paint(part.get("c", "#FFFFFF"))
	var flat: Color = paint if paint is Color else Color.WHITE
	var round_amount: float = float(part.get("r", 0.0))
	# 작은 도형은 면을 덜 쪼갠다. 고화질(detail 1.5)은 둥근 면을 1.5배 촘촘히.
	var extent: float = maxf(a, maxf(b, c)) * (1.0 if shape in ["box", "rbox"] else 2.0)
	var seg: int = roundi((8.0 if extent < 0.5 else (10.0 if extent < 1.5 else 12.0)) * detail / 2.0) * 2
	var rings: int = roundi((4.0 if extent < 0.5 else (6.0 if extent < 1.5 else 8.0)) * detail)
	match shape:
		"box":
			if part.get("c") is Array:
				ClayMesh.add_rounded_box(st, at, Vector3(a, b, c), 0.12, paint, basis, seg, rings)
			else:
				ClayMesh.add_box(st, at, Vector3(a, b, c), flat, basis)
		"rbox":
			ClayMesh.add_rounded_box(st, at, Vector3(a, b, c), float(part.get("r", 0.35)), paint, basis, seg, rings)
		"cyl", "cone":
			var top: float = 0.0 if shape == "cone" else a
			if round_amount > 0.0 or part.get("c") is Array:
				var profile: PackedVector2Array = ClayMesh.rounded_cylinder_profile(a, maxf(top, 0.001), -b * 0.5, b * 0.5, maxf(round_amount, 0.001), 2)
				ClayMesh.add_lathe(st, profile, seg + 2, Transform3D(basis, at), paint)
			else:
				var cyl: CylinderMesh = CylinderMesh.new()
				cyl.bottom_radius = a
				cyl.top_radius = top
				cyl.height = b
				cyl.radial_segments = roundi(12.0 * detail)
				cyl.rings = 1
				ClayMesh.add_primitive(st, cyl, Transform3D(basis, at), flat)
		"sphere":
			var radii: Vector3 = Vector3(a, b, c) if v.size() >= 3 else Vector3(a, a, a)
			ClayMesh.add_ellipsoid(st, at, radii, paint, seg, rings, basis)
		"blob":
			ClayMesh.add_ellipsoid(st, at, Vector3(a, b, c), paint, seg, rings + 1, basis, ClayMesh.blob_wobble(int(part.get("seed", 1)), 0.12, 4))
		"torus":
			ClayMesh.add_torus(st, at, a, b, paint, seg + 4, 4 if b < 0.05 else 5, basis)
		"cap":
			ClayMesh.add_capsule(st, at, _vec(part.get("to", [0, 1, 0])), a, paint, roundi(6.0 * detail), 2)
		"rod":
			ClayMesh.add_rod(st, at, _vec(part.get("to", [0, 1, 0])), a, b, paint, roundi(6.0 * detail))
		_:
			return false
	return true


static func _vec(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


## "#RRGGBB" → 단색, ["#아래", "#위"] → 위로 갈수록 밝아지는 그라데이션.
static func _paint(value: Variant) -> Variant:
	if value is Array and value.size() >= 2:
		return ClayMesh.vertical_gradient(Color.html(str(value[0])), Color.html(str(value[1])), 1.0)
	return Color.html(str(value))
