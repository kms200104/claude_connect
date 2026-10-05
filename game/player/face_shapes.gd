class_name FaceShapes
extends RefCounted
## 얼굴 부품 도형(data/looks/face_parts.json 의 layers) → 2D 삼각형. 같은 삼각형으로
## 3D 얼굴(CharacterModel 이 머리 겉면에 붙인다)과 거울 창의 부품 아이콘을 그린다.
##
## 도형: ellipse(c, r, rot) · poly(pts) · stroke(pts, w) · arc(c, r, a0, a1, w) · chord(c, r, a0, a1) ·
##       star(c, r, inner, n, rot) · heart(c, s) · dome(c, r, h — 3D에서는 볼록 솟은 혹, 아이콘에서는 타원).
## 각도는 도(degree), 0 = 오른쪽(+x), 90 = 위. mirror: true 인 층은 좌우로 하나씩 더 그린다.
## gaze: true 인 층(눈동자·하이라이트)은 왼쪽 눈에서도 좌우를 뒤집지 않는다 — 두 눈이 같은 쪽을 본다 (x 양수 = 캐릭터 오른쪽).
## 긴 변은 max_edge 보다 짧아질 때까지 반으로 나눈다 — 둥근 머리에 붙여도 평평한 삼각형이 머리 속으로 파묻히지 않게.

## 가장 적은 칸 수 (작은 도형도 이만큼은 둥글게).
const CIRCLE_STEPS: int = 16
const ARC_STEPS: int = 14
const JOINT_STEPS: int = 8
const HEART_STEPS: int = 28
## 둘레를 나누는 한 칸의 길이 (m, outline = 1 일 때). 큰 원일수록 칸이 많아져 화면에서 각이 보이지 않는다.
const OUTLINE_SEGMENT: float = 0.03
const MAX_STEPS: int = 96

## 지금 만드는 도형의 둘레 촘촘함 배율 (triangles 가 정한다). 1 = 기본, 2 = 두 배 촘촘.
static var _outline: float = 1.0
## 이 각도(도)보다 덜 꺾인 마디는 둥근 마디를 생략한다 (틈이 선 굵기에 비해 아주 작다).
const JOINT_MIN_TURN: float = 25.0


## 층 하나를 삼각형으로: {"tris": PackedVector2Array(3개씩), "color": Color, "dome": Vector3(높이, 반지름 x, 반지름 y) 또는 ZERO, "center": Vector2, "gaze": bool}.
static func layer_triangles(layer: Dictionary, palette: Dictionary[String, Color], max_edge: float = 0.0, outline: float = 1.0) -> Dictionary:
	_outline = maxf(outline, 0.1)
	var tris: PackedVector2Array = PackedVector2Array()
	var shape: String = str(layer.get("shape", ""))
	var c: Vector2 = _vec(layer.get("c", [0.0, 0.0]))
	var r: Vector2 = _vec(layer.get("r", [0.01, 0.01]))
	var dome: Vector3 = Vector3.ZERO
	match shape:
		"ellipse":
			tris = _fan(_ellipse_points(c, r, deg_to_rad(float(layer.get("rot", 0.0))), _steps(_ellipse_length(r), CIRCLE_STEPS)), c)
		"dome":
			# 가운데에서 바깥으로 고리를 여러 겹 — 솟은 높이를 고르게 나누려고 부채꼴 대신 동심원 격자.
			tris = _rings(c, r, 3, _steps(_ellipse_length(r), CIRCLE_STEPS))
			dome = Vector3(float(layer.get("h", 0.01)), r.x, r.y)
		"poly":
			tris = _polygon(_points(layer.get("pts", [])))
		"stroke":
			tris = _stroke(_points(layer.get("pts", [])), float(layer.get("w", 0.01)))
		"arc":
			tris = _stroke(_arc_points(c, r, float(layer.get("a0", 0.0)), float(layer.get("a1", 180.0))), float(layer.get("w", 0.01)))
		"chord":
			tris = _polygon(_arc_points(c, r, float(layer.get("a0", 0.0)), float(layer.get("a1", 180.0))))
		"star":
			tris = _polygon(_star_points(c, float(layer.get("r", 0.02)), float(layer.get("inner", 0.4)), int(layer.get("n", 5)), float(layer.get("rot", 90.0))))
		"heart":
			tris = _polygon(_heart_points(c, float(layer.get("s", 0.05))))
	if bool(layer.get("mirror", false)):
		var mirrored: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, tris.size(), 3):
			# 좌우를 뒤집으면 감김 방향도 바뀌니 순서를 바꿔 넣는다.
			mirrored.append(Vector2(-tris[i].x, tris[i].y))
			mirrored.append(Vector2(-tris[i + 2].x, tris[i + 2].y))
			mirrored.append(Vector2(-tris[i + 1].x, tris[i + 1].y))
		tris.append_array(mirrored)
	if max_edge > 0.0 and dome == Vector3.ZERO:
		tris = subdivide(tris, max_edge)
	var color_key: String = str(layer.get("color", "ink"))
	var color: Color = palette.get(color_key, Color.html(color_key) if Color.html_is_valid(color_key) else Color.MAGENTA)
	return {"tris": tris, "color": color, "dome": dome, "center": c, "gaze": bool(layer.get("gaze", false))}


## 모든 층 (아래 → 위).
## outline: 둥근 둘레(원·호·하트·선 끝)의 촘촘함 배율 (캐릭터 화질별, 아이콘은 크게 그리니 촘촘하게).
static func triangles(layers: Array[Dictionary], palette: Dictionary[String, Color], max_edge: float = 0.0, outline: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for layer: Dictionary in layers:
		var entry: Dictionary = layer_triangles(layer, palette, max_edge, outline)
		if not (entry["tris"] as PackedVector2Array).is_empty():
			out.append(entry)
	return out


## 가장 긴 변을 반으로 나누기를 모든 변이 max_edge 이하가 될 때까지 (최대 6번).
static func subdivide(tris: PackedVector2Array, max_edge: float) -> PackedVector2Array:
	var current: PackedVector2Array = tris
	for _pass: int in 6:
		var next: PackedVector2Array = PackedVector2Array()
		var split: bool = false
		for i: int in range(0, current.size(), 3):
			var a: Vector2 = current[i]
			var b: Vector2 = current[i + 1]
			var c: Vector2 = current[i + 2]
			var ab: float = a.distance_to(b)
			var bc: float = b.distance_to(c)
			var ca: float = c.distance_to(a)
			var longest: float = maxf(ab, maxf(bc, ca))
			if longest <= max_edge:
				next.append_array(PackedVector2Array([a, b, c]))
				continue
			split = true
			if longest == ab:
				var m: Vector2 = (a + b) * 0.5
				next.append_array(PackedVector2Array([a, m, c, m, b, c]))
			elif longest == bc:
				var m: Vector2 = (b + c) * 0.5
				next.append_array(PackedVector2Array([a, b, m, a, m, c]))
			else:
				var m: Vector2 = (c + a) * 0.5
				next.append_array(PackedVector2Array([a, b, m, m, b, c]))
		current = next
		if not split:
			break
	return current


## dome 의 (u, v) 자리에서 솟은 높이 (가운데 h, 가장자리 0, 둥근 언덕).
static func dome_height(p: Vector2, center: Vector2, dome: Vector3) -> float:
	var q: Vector2 = Vector2((p.x - center.x) / maxf(dome.y, 0.0001), (p.y - center.y) / maxf(dome.z, 0.0001))
	return dome.x * sqrt(maxf(1.0 - q.length_squared(), 0.0))


static func _vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


static func _points(list: Variant) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if list is Array:
		for p: Variant in list:
			out.append(_vec(p))
	return out


## 둘레 길이 length 를 OUTLINE_SEGMENT / 배율 칸으로 (최소 least, 최대 MAX_STEPS).
static func _steps(length: float, least: int) -> int:
	return clampi(ceili(length * _outline / OUTLINE_SEGMENT), least, MAX_STEPS)


## 타원 둘레 (라마누잔 근사).
static func _ellipse_length(r: Vector2) -> float:
	var a: float = absf(r.x)
	var b: float = absf(r.y)
	return PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))


static func _ellipse_points(c: Vector2, r: Vector2, rot: float, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in steps:
		var a: float = TAU * float(i) / float(steps)
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	return out


static func _arc_points(c: Vector2, r: Vector2, a0: float, a1: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var steps: int = _steps(_ellipse_length(r) * absf(a1 - a0) / 360.0, ARC_STEPS)
	for i: int in steps + 1:
		var a: float = deg_to_rad(lerpf(a0, a1, float(i) / float(steps)))
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


static func _star_points(c: Vector2, r: float, inner: float, n: int, rot: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in n * 2:
		var a: float = deg_to_rad(rot) + PI * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * inner))
	return out


static func _heart_points(c: Vector2, s: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var steps: int = _steps(s * 3.3, HEART_STEPS)
	for i: int in steps:
		var t: float = TAU * float(i) / float(steps)
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(c + Vector2(x, y) * (s / 32.0))
	return out


static func _fan(outline: PackedVector2Array, center: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in outline.size():
		out.append_array(PackedVector2Array([center, outline[i], outline[(i + 1) % outline.size()]]))
	return out


## 동심원 격자 (rings 겹, 고리마다 steps 점).
static func _rings(c: Vector2, r: Vector2, rings: int, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for k: int in rings:
		var t0: float = float(k) / float(rings)
		var t1: float = float(k + 1) / float(rings)
		for i: int in steps:
			var a0: float = TAU * float(i) / float(steps)
			var a1: float = TAU * float(i + 1) / float(steps)
			var p00: Vector2 = c + Vector2(cos(a0) * r.x, sin(a0) * r.y) * t0
			var p01: Vector2 = c + Vector2(cos(a1) * r.x, sin(a1) * r.y) * t0
			var p10: Vector2 = c + Vector2(cos(a0) * r.x, sin(a0) * r.y) * t1
			var p11: Vector2 = c + Vector2(cos(a1) * r.x, sin(a1) * r.y) * t1
			if k == 0:
				out.append_array(PackedVector2Array([c, p10, p11]))
			else:
				out.append_array(PackedVector2Array([p00, p10, p11, p00, p11, p01]))
	return out


static func _polygon(outline: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if outline.size() < 3:
		return out
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for i: int in indices:
		out.append(outline[i])
	return out


## 굵은 선: 마디마다 사각형, 많이 꺾이는 곳과 양 끝은 동그랗게.
static func _stroke(points: PackedVector2Array, width: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var half: float = width * 0.5
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var d: Vector2 = b - a
		if d.length_squared() < 1e-12:
			continue
		var n: Vector2 = Vector2(-d.y, d.x).normalized() * half
		out.append_array(PackedVector2Array([a + n, b + n, b - n, a + n, b - n, a - n]))
	for i: int in points.size():
		var round_here: bool = i == 0 or i == points.size() - 1
		if not round_here:
			var turn: float = absf(rad_to_deg((points[i] - points[i - 1]).angle_to(points[i + 1] - points[i])))
			round_here = turn > JOINT_MIN_TURN
		if round_here:
			out.append_array(_fan(_ellipse_points(points[i], Vector2(half, half), 0.0, _steps(TAU * half, JOINT_STEPS)), points[i]))
	return out
