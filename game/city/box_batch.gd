class_name BoxBatch
extends RefCounted
## 상자 수천 개를 정점 색 메시 하나로 빠르게 모은다 (v0.21 도시 건물 · 도로 소품).
## ClayMesh.add_box 는 상자마다 BoxMesh 를 새로 만들어 느리므로, 면 6개를 바로 쓴다 (면마다 정점 4 · 삼각형 2).

const _FACES: Array[Array] = [
	[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
	[Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.LEFT, Vector3.UP],
	[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
]

var verts: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var colors: PackedColorArray = PackedColorArray()
var indices: PackedInt32Array = PackedInt32Array()
## 메시 원점 (정점은 이만큼 빼서 넣는다 — 노드를 칸 가운데에 두어 visibility range 가 맞게).
var origin: Vector3 = Vector3.ZERO


func is_empty() -> bool:
	return verts.is_empty()


## 위를 보는 면은 이 크기 칸으로 쪼갠다 — 땅 휘기(world curve)는 정점만 내리므로, 큰 판은 가운데가 휜 땅 밑으로 꺼진다.
const FLAT_CELL: float = 2.5


## 상자: 가운데 · 크기 · 색, basis 로 돌린다 (밑면을 빼면 땅에 묻힌 면 삼각형을 아낀다).
func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis(), bottom: bool = false) -> void:
	var half: Vector3 = size * 0.5
	var c: Vector3 = center - origin
	for f: Array in _FACES:
		var n: Vector3 = f[0]
		if n == Vector3.DOWN and not bottom:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var uh: Vector3 = u * absf(u.dot(half))
		var vh: Vector3 = v * absf(v.dot(half))
		var nu: int = 1
		var nv: int = 1
		if n == Vector3.UP:
			nu = maxi(ceili(uh.length() * 2.0 / FLAT_CELL), 1)
			nv = maxi(ceili(vh.length() * 2.0 / FLAT_CELL), 1)
		# 바깥에서 볼 때 시계 방향 (Godot 앞면): 면의 (n, u, v) 손 방향에 따라 감는 순서가 다르다.
		_grid(c, basis * (n * half), basis * uh, basis * vh, (basis * n).normalized(), color, nu, nv, n.cross(u).dot(v) > 0.0)


## 위를 보는 평평한 사각 판 (두께 없이, FLAT_CELL 칸으로 쪼갠다).
func quad_up(center: Vector3, size: Vector2, color: Color, yaw: float = 0.0) -> void:
	var basis: Basis = Basis(Vector3.UP, yaw)
	var hx: Vector3 = basis * Vector3(size.x * 0.5, 0.0, 0.0)
	var hz: Vector3 = basis * Vector3(0.0, 0.0, size.y * 0.5)
	var nu: int = maxi(ceili(size.x / FLAT_CELL), 1)
	var nv: int = maxi(ceili(size.y / FLAT_CELL), 1)
	_grid(center - origin, Vector3.ZERO, hx, hz, Vector3.UP, color, nu, nv, false)


## 면 하나를 nu × nv 칸으로: 꼭짓점 = c + nh + uh·(2i/nu − 1) + vh·(2j/nv − 1).
## flip = 감는 순서를 뒤집는다 (모서리 순서 (−u,−v) (+u,−v) (+u,+v) (−u,+v) 기준).
func _grid(c: Vector3, nh: Vector3, uh: Vector3, vh: Vector3, normal: Vector3, color: Color, nu: int, nv: int, flip: bool) -> void:
	var base: int = verts.size()
	for j: int in nv + 1:
		for i: int in nu + 1:
			verts.append(c + nh + uh * (2.0 * float(i) / float(nu) - 1.0) + vh * (2.0 * float(j) / float(nv) - 1.0))
			normals.append(normal)
			colors.append(color)
	for j: int in nv:
		for i: int in nu:
			var a: int = base + j * (nu + 1) + i
			var b: int = a + 1
			var d: int = a + nu + 1
			var e: int = d + 1
			if flip:
				indices.append_array([a, e, b, a, d, e])
			else:
				indices.append_array([a, b, e, a, e, d])


func commit() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func triangle_count() -> int:
	return indices.size() / 3
