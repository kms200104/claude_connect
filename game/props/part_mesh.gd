class_name PartMesh
extends RefCounted
## 데이터의 도형 목록({s, size, at, c})으로 메시 하나를 만든다. 가구·옷·상점 장식이 쓴다.
## 도형마다 정점 색을 칠해 머티리얼 1개(foliage.tres 처럼 흰 툰 머티리얼)로 그리므로 물건 하나 = 드로우콜 1.
##   s: box(size = [x, y, z]) / cyl(size = [반지름, 높이]) / cone(size = [밑 반지름, 높이]) / sphere(size = [반지름])
##   at: 가운데 위치 [x, y, z], c: "#RRGGBB"

static var _cache: Dictionary[String, ArrayMesh] = {}


## key 로 한 번만 만든다 (같은 아이템은 메시 공유).
static func get_mesh(key: String, parts: Array) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var mesh: ArrayMesh = build(parts)
	_cache[key] = mesh
	return mesh


static func build(parts: Array) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var added: int = 0
	for part: Variant in parts:
		if not part is Dictionary:
			continue
		var primitive: PrimitiveMesh = _primitive(str(part.get("s", "box")), part.get("size", [0.5, 0.5, 0.5]))
		if primitive == null:
			continue
		var at: Array = part.get("at", [0, 0, 0])
		var offset: Vector3 = Vector3(float(at[0]), float(at[1]), float(at[2])) if at.size() >= 3 else Vector3.ZERO
		add_primitive(st, primitive, Transform3D(Basis(), offset), Color.html(str(part.get("c", "#FFFFFF"))))
		added += 1
	if added == 0:
		add_primitive(st, BoxMesh.new(), Transform3D(Basis(), Vector3(0, 0.5, 0)), Color.MAGENTA)
	st.index()
	return st.commit()


static func add_primitive(st: SurfaceTool, primitive: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays: Array = primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis: Basis = xform.basis.inverse().transposed()
	for i: int in indices:
		st.set_color(color)
		st.set_normal((normal_basis * normals[i]).normalized())
		st.add_vertex(xform * verts[i])


static func _primitive(shape: String, size: Variant) -> PrimitiveMesh:
	var v: Array = size if size is Array else [0.5]
	var a: float = float(v[0]) if v.size() > 0 else 0.5
	var b: float = float(v[1]) if v.size() > 1 else a
	var c: float = float(v[2]) if v.size() > 2 else a
	match shape:
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(a, b, c)
			return box
		"cyl", "cone":
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.bottom_radius = a
			cyl.top_radius = 0.0 if shape == "cone" else a
			cyl.height = b
			cyl.radial_segments = 12
			cyl.rings = 1
			return cyl
		"sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = a
			sphere.height = a * 2.0
			sphere.radial_segments = 10
			sphere.rings = 6
			return sphere
	return null
