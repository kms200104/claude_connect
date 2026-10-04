class_name ClayMesh
extends RefCounted
## 점토 인형처럼 둥근 도형을 정점 색으로 칠해 SurfaceTool 하나에 쌓는다 (캐릭터·나무·바위·집·가구가 같이 쓴다).
## 모든 둥근 도형은 "회전체"(옆모습 윤곽을 축 둘레로 돌린 것)로 만들고, 둘레 방향 반지름을 함수로 흔들어
## 울퉁불퉁한 잎 덩어리·물결 모양 소나무 층을 만든다. 법선은 이웃 면을 평균해 매끈하게 한다.
##
## 윤곽(profile)은 (반지름, 높이) 점 목록으로, 아래에서 바깥쪽을 거쳐 위로 가는 순서(반시계)여야 바깥을 향한다.

## 둘레 방향 반지름 배율 함수가 없을 때.
static func _no_wobble(_angle: float, _t: float) -> float:
	return 1.0


static func begin() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


## 회전체. color 는 Color 또는 Callable(local: Vector3, normal: Vector3) -> Color.
## wobble 은 Callable(angle: float, t: float) -> float (t: 윤곽 위치 0~1), 둘레 방향 반지름 배율.
static func add_lathe(st: SurfaceTool, profile: PackedVector2Array, segments: int, xform: Transform3D, color: Variant, wobble: Callable = _no_wobble) -> void:
	var rows: int = profile.size()
	var cols: int = segments
	var points: PackedVector3Array = PackedVector3Array()
	points.resize(rows * cols)
	for r: int in rows:
		var t: float = float(r) / float(maxi(rows - 1, 1))
		for c: int in cols:
			var angle: float = TAU * float(c) / float(cols)
			var radius: float = profile[r].x * float(wobble.call(angle, t))
			points[r * cols + c] = Vector3(cos(angle) * radius, profile[r].y, sin(angle) * radius)
	_emit_grid(st, points, rows, cols, xform, color)


## 위아래 극에서 닫힌 타원체 (radii = 반지름 x, y, z).
static func add_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, color: Variant, segments: int = 12, rings: int = 8, basis: Basis = Basis(), wobble: Callable = _no_wobble) -> void:
	add_lathe(st, sphere_profile(rings), segments, Transform3D(basis * Basis.from_scale(radii), center), color, wobble)


## 반지름 1짜리 반원 윤곽 (아래 극 → 위 극).
static func sphere_profile(rings: int) -> PackedVector2Array:
	var profile: PackedVector2Array = PackedVector2Array()
	for i: int in rings + 1:
		var a: float = -PI * 0.5 + PI * float(i) / float(rings)
		profile.append(Vector2(cos(a), sin(a)))
	return profile


## 모서리를 둥글린 원기둥 (bottom 높이에서 top 높이까지, round 만큼 모서리를 깎는다).
static func rounded_cylinder_profile(radius_bottom: float, radius_top: float, bottom: float, top: float, round_amount: float, steps: int = 3) -> PackedVector2Array:
	var p: PackedVector2Array = PackedVector2Array()
	var rb: float = minf(round_amount, minf(radius_bottom, (top - bottom) * 0.5))
	var rt: float = minf(round_amount, minf(radius_top, (top - bottom) * 0.5))
	p.append(Vector2(0.0, bottom))
	for i: int in steps + 1:
		var a: float = -PI * 0.5 + PI * 0.5 * float(i) / float(steps)
		p.append(Vector2(radius_bottom - rb + cos(a) * rb, bottom + rb + sin(a) * rb))
	for i: int in steps + 1:
		var a: float = PI * 0.5 * float(i) / float(steps)
		p.append(Vector2(radius_top - rt + cos(a) * rt, top - rt + sin(a) * rt))
	p.append(Vector2(0.0, top))
	return p


## 두 점 사이 둥근 막대 (팔·다리·손잡이).
static func add_capsule(st: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Variant, segments: int = 8, rings: int = 3) -> void:
	var length: float = from.distance_to(to)
	var profile: PackedVector2Array = PackedVector2Array()
	for i: int in rings + 1:
		var a: float = -PI * 0.5 + PI * 0.5 * float(i) / float(rings)
		profile.append(Vector2(cos(a) * radius, sin(a) * radius))
	for i: int in rings + 1:
		var a: float = PI * 0.5 * float(i) / float(rings)
		profile.append(Vector2(cos(a) * radius, length + sin(a) * radius))
	add_lathe(st, profile, segments, Transform3D(_basis_along(to - from), from), color)


## 두 점 사이 원기둥 (끝을 살짝 둥글린다).
static func add_rod(st: SurfaceTool, from: Vector3, to: Vector3, radius_from: float, radius_to: float, color: Variant, segments: int = 8) -> void:
	var length: float = from.distance_to(to)
	var profile: PackedVector2Array = rounded_cylinder_profile(radius_from, radius_to, 0.0, length, minf(radius_from, radius_to) * 0.4, 1)
	add_lathe(st, profile, segments, Transform3D(_basis_along(to - from), from), color)


## 도넛 (ring_radius: 가운데 원 반지름, tube: 굵기). basis 의 Y 가 도넛 축.
static func add_torus(st: SurfaceTool, center: Vector3, ring_radius: float, tube: float, color: Variant, segments: int = 16, sides: int = 6, basis: Basis = Basis()) -> void:
	var profile: PackedVector2Array = PackedVector2Array()
	for i: int in sides + 1:
		var a: float = -PI + TAU * float(i) / float(sides)
		profile.append(Vector2(ring_radius + cos(a) * tube, sin(a) * tube))
	add_lathe(st, profile, segments, Transform3D(basis, center), color)


## 모서리가 둥근 상자 (초타원체). roundness 0.1 = 거의 상자, 1 = 타원체.
static func add_rounded_box(st: SurfaceTool, center: Vector3, size: Vector3, roundness: float, color: Variant, basis: Basis = Basis(), segments: int = 12, rings: int = 8) -> void:
	var e: float = clampf(roundness, 0.05, 1.0)
	var half: Vector3 = size * 0.5
	var rows: int = rings + 1
	var cols: int = segments
	var points: PackedVector3Array = PackedVector3Array()
	points.resize(rows * cols)
	for r: int in rows:
		var phi: float = -PI * 0.5 + PI * float(r) / float(rings)
		for c: int in cols:
			var theta: float = TAU * float(c) / float(cols)
			var cp: float = cos(phi)
			var x: float = _spow(cp, e) * _spow(cos(theta), e)
			var z: float = _spow(cp, e) * _spow(sin(theta), e)
			var y: float = _spow(sin(phi), e)
			points[r * cols + c] = Vector3(x * half.x, y * half.y, z * half.z)
	_emit_grid(st, points, rows, cols, Transform3D(basis, center), color)


## 타원체 껍질 중 keep(방향) 이 참인 부분만 (얼굴 자리를 비운 머리카락 같은 것).
## keep 은 Callable(dir: Vector3) -> bool, dir 은 중심에서 본 단위 방향(면 가운데 기준).
## flare 는 Callable(dir: Vector3) -> float, 그 방향 반지름 배율 (단발머리 끝이 퍼지는 모양).
static func add_shell(st: SurfaceTool, center: Vector3, radii: Vector3, color: Variant, keep: Callable, flare: Callable, segments: int = 20, rings: int = 14) -> void:
	var rows: int = rings + 1
	var cols: int = segments
	var dirs: PackedVector3Array = PackedVector3Array()
	var points: PackedVector3Array = PackedVector3Array()
	dirs.resize(rows * cols)
	points.resize(rows * cols)
	for r: int in rows:
		var phi: float = -PI * 0.5 + PI * float(r) / float(rings)
		for c: int in cols:
			var theta: float = TAU * float(c) / float(cols)
			var dir: Vector3 = Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))
			dirs[r * cols + c] = dir
			points[r * cols + c] = center + dir * radii * float(flare.call(dir))
	var skip: PackedByteArray = PackedByteArray()
	skip.resize((rows - 1) * cols)
	for r: int in rows - 1:
		for c: int in cols:
			var c2: int = (c + 1) % cols
			var mid: Vector3 = (dirs[r * cols + c] + dirs[r * cols + c2] + dirs[(r + 1) * cols + c] + dirs[(r + 1) * cols + c2]).normalized()
			skip[r * cols + c] = 0 if bool(keep.call(mid)) else 1
	_emit_grid(st, points, rows, cols, Transform3D(), color, skip)


## 평평한 상자 (각진 판자·책·창틀).
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis = Basis()) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	add_primitive(st, box, Transform3D(basis, center), color)


## Godot 기본 도형(PrimitiveMesh)을 정점 색으로 칠해 넣는다.
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


## 울퉁불퉁한 덩어리 (잎 뭉치·바위). seed 로 모양이 정해진다.
static func blob_wobble(seed_value: int, lumps: float = 0.12, frequency: int = 3) -> Callable:
	var phase_a: float = float(seed_value % 97) * 0.37
	var phase_b: float = float(seed_value % 61) * 0.71
	return func(angle: float, t: float) -> float:
		var lat: float = t * PI
		return 1.0 + lumps * (sin(angle * frequency + phase_a) * sin(lat * 2.0 + phase_b) * 0.6 + sin(angle * (frequency + 2) - phase_b + lat * 3.0) * 0.4)


## 둘레를 물결 모양으로 (소나무 층·주름 갓).
static func scallop_wobble(lobes: int, depth: float, phase: float = 0.0) -> Callable:
	return func(angle: float, _t: float) -> float:
		return 1.0 - depth * 0.5 + depth * 0.5 * cos(angle * float(lobes) + phase)


## 위쪽(법선 y)일수록 top 색, 아래일수록 bottom 색 — 이끼 낀 바위·햇빛 받는 잎.
static func vertical_gradient(bottom: Color, top: Color, sharpness: float = 1.0) -> Callable:
	return func(_local: Vector3, normal: Vector3) -> Color:
		var k: float = clampf(normal.y * 0.5 + 0.5, 0.0, 1.0)
		return bottom.lerp(top, pow(k, sharpness))


static func _spow(v: float, e: float) -> float:
	return signf(v) * pow(absf(v), e)


## +Y 를 dir 방향으로 돌리는 회전.
static func _basis_along(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	if y.is_zero_approx():
		return Basis()
	var helper: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = helper.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)


## 격자 점(행 = 윤곽을 따라 아래→위, 열 = 둘레)을 삼각형으로 잇는다. 열은 처음과 끝이 이어진다.
static func _emit_grid(st: SurfaceTool, points: PackedVector3Array, rows: int, cols: int, xform: Transform3D, color: Variant, skip: PackedByteArray = PackedByteArray()) -> void:
	var world: PackedVector3Array = PackedVector3Array()
	world.resize(points.size())
	for i: int in points.size():
		world[i] = xform * points[i]
	# 면 법선을 꼭짓점에 모아 매끈한 법선을 만든다 (극처럼 겹친 점은 같은 위치끼리 다시 평균).
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(world.size())
	var tris: PackedInt32Array = PackedInt32Array()
	for r: int in rows - 1:
		for c: int in cols:
			if not skip.is_empty() and skip[r * cols + c] == 1:
				continue
			var c2: int = (c + 1) % cols
			var a: int = r * cols + c
			var b: int = r * cols + c2
			var d: int = (r + 1) * cols + c2
			var e: int = (r + 1) * cols + c
			for tri: PackedInt32Array in [PackedInt32Array([a, b, d]), PackedInt32Array([a, d, e])]:
				var n: Vector3 = (world[tri[1]] - world[tri[0]]).cross(world[tri[2]] - world[tri[0]])
				if n.length_squared() < 1e-12:
					continue
				# 이 순서의 외적은 안쪽을 향한다 (Godot 앞면 = 시계 방향). 바깥 법선은 반대.
				for k: int in 3:
					normals[tri[k]] -= n
				tris.append_array(tri)
	var pooled: Dictionary[Vector3, Vector3] = {}
	for i: int in world.size():
		var key: Vector3 = world[i].snappedf(0.0001)
		pooled[key] = pooled.get(key, Vector3.ZERO) + normals[i]
	var use_callable: bool = color is Callable
	var fixed: Color = color if color is Color else Color.WHITE
	for i: int in tris:
		var n: Vector3 = pooled[world[i].snappedf(0.0001)].normalized()
		if n.is_zero_approx():
			n = Vector3.UP
		st.set_color((color as Callable).call(world[i], n) if use_callable else fixed)
		st.set_normal(n)
		st.add_vertex(world[i])
