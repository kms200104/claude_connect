extends RefCounted
## 탈것을 실제 모양처럼 빚는 도구 (v21): 단면을 이어 붙인 매끈한 곡면(loft — 선체 · 탱크 · 카울 · 바나나 튜브),
## 부드러운 곡선을 따라 굴린 관(sweep — 자전거 프레임 · 핸들 · 난간), 축 둘레로 돌린 바퀴 부품(lathe — 타이어 · 림 · 허브).
## 모두 ClayMesh 의 정점 색 SurfaceTool 에 쌓는다 (머티리얼 하나). 법선은 같은 자리끼리 평균해 매끈하다.
## 표면 마감은 정점 색 알파로 표시한다 — toon 셰이더(toon_common)가 이 값을 보고 하늘을 비추는 반사를 더한다:
##   GLOSS = 광택 도장(투명 코팅), CHROME = 크롬 · 연마 금속, GLASS = 유리 · 바이저, 그 밖(1.0) = 무광.

const GLOSS: float = 0.72
const CHROME: float = 0.82
const GLASS: float = 0.62


static func gloss(c: Color) -> Color:
	return Color(c.r, c.g, c.b, GLOSS)


static func chrome(c: Color = Color("#D9DCE0")) -> Color:
	return Color(c.r, c.g, c.b, CHROME)


static func glass(c: Color = Color("#2E3A44")) -> Color:
	return Color(c.r, c.g, c.b, GLASS)


static func matte(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 1.0)


# ---- 단면 ----

## XY 평면의 둥근 단면 (z 자리), 위에서 시작해 오른쪽(+x)으로 돈다 (loft 가 바깥 법선을 맞춘다).
## half_w = 반폭, top / bottom = 가운데(cy)에서 위 · 아래 높이, square = 0(타원) ~ 1(거의 네모).
static func section(cx: float, cy: float, z: float, half_w: float, top: float, bottom: float, n: int, square: float = 0.0) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var e: float = lerpf(1.0, 0.25, clampf(square, 0.0, 1.0))
	for i: int in n:
		var t: float = TAU * float(i) / float(n)
		var s: float = sin(t)
		var c: float = cos(t)
		var x: float = signf(s) * pow(absf(s), e) * half_w
		var y: float = signf(c) * pow(absf(c), e) * (top if c >= 0.0 else bottom)
		out.append(Vector3(cx + x, cy + y, z))
	return out


## XZ 평면(높이 y)의 둥근 네모 단면 — 위로 쌓아 올리는 집채 · 조타실 · 콘솔 (loft 의 고리를 y 로 늘어놓는다).
static func ring_xz(cx: float, y: float, cz: float, half_x: float, half_z: float, n: int, square: float = 0.7) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var e: float = lerpf(1.0, 0.25, clampf(square, 0.0, 1.0))
	for i: int in n:
		var t: float = TAU * float(i) / float(n)
		var s: float = sin(t)
		var c: float = cos(t)
		out.append(Vector3(cx + signf(c) * pow(absf(c), e) * half_x, y, cz + signf(s) * pow(absf(s), e) * half_z))
	return out


## 배 단면: 갑판(위로 볼록) · 뱃전(flare) · 바닥 V(deadrise). half_w = 뱃전 반폭, deck = 갑판 높이, sheer = 뱃전 높이,
## keel = 용골 깊이(음수), chine = 바닥이 꺾이는 자리 (반폭 비율), dead = 바닥 V 기울기 (0 = 납작).
static func hull_section(z: float, half_w: float, deck: float, sheer: float, keel: float, chine: float, dead: float, n: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	# 반 바퀴(오른쪽)를 위 가운데 → 뱃전 → 차인 → 용골 순서로 짓고 왼쪽은 거울로.
	var half: PackedVector3Array = PackedVector3Array()
	var m: int = maxi(4, n / 2)
	for i: int in m + 1:
		var t: float = float(i) / float(m)
		var p: Vector2
		if t < 0.3:
			# 갑판: 가운데에서 뱃전까지 둥글게 내려온다.
			var u: float = t / 0.3
			p = Vector2(half_w * sin(u * PI * 0.5), lerpf(deck, sheer, 1.0 - cos(u * PI * 0.5)))
		elif t < 0.55:
			# 뱃전 옆면: 차인까지 살짝 안으로 (아래로 갈수록 좁아진다).
			var u2: float = (t - 0.3) / 0.25
			var chine_y: float = keel + (half_w * chine) * dead + 0.02
			p = Vector2(lerpf(half_w, half_w * lerpf(chine, 1.0, 0.55), u2 * u2), lerpf(sheer, chine_y, u2))
		else:
			# 바닥: 차인에서 용골까지 V.
			var u3: float = (t - 0.55) / 0.45
			var x0: float = half_w * lerpf(chine, 1.0, 0.55)
			var chine_y2: float = keel + (half_w * chine) * dead + 0.02
			var bend: float = sin(u3 * PI * 0.5)
			p = Vector2(x0 * (1.0 - bend), lerpf(chine_y2, keel, bend))
		half.append(Vector3(p.x, p.y, z))
	# 위 가운데 → 오른쪽 → 바닥 가운데 → 왼쪽 → 위 (시계 방향, section 과 같은 순서).
	for i: int in half.size():
		out.append(half[i])
	for i: int in range(half.size() - 2, 0, -1):
		out.append(Vector3(-half[i].x, half[i].y, z))
	return out


# ---- 곡면 ----

## 같은 점 수의 닫힌 고리들을 차례로 이은 곡면. cap 이면 양 끝을 가운데 한 점으로 모아 닫는다 (둥근 코 · 꼬리는 끝 고리를 작게).
## 고리 차례가 바뀌어도 바깥 법선이 나오도록 스스로 맞춘다.
static func loft(st: SurfaceTool, rings: Array[PackedVector3Array], color: Variant, cap_start: bool = true, cap_end: bool = true) -> void:
	if rings.size() < 2:
		return
	var cols: int = rings[0].size()
	var ordered: Array[PackedVector3Array] = rings
	if _inward(rings):
		ordered = []
		for r: PackedVector3Array in rings:
			var rev: PackedVector3Array = r.duplicate()
			rev.reverse()
			ordered.append(rev)
	var pts: PackedVector3Array = PackedVector3Array()
	var rows: int = 0
	if cap_start:
		pts.append_array(_collapsed(ordered[0]))
		rows += 1
	for r: PackedVector3Array in ordered:
		pts.append_array(r)
		rows += 1
	if cap_end:
		pts.append_array(_collapsed(ordered[ordered.size() - 1]))
		rows += 1
	ClayMesh._emit_grid(st, pts, rows, cols, Transform3D(), color)


## 고리를 그 가운데 한 점으로 모은 고리 (끝 막기).
static func _collapsed(ring: PackedVector3Array) -> PackedVector3Array:
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in ring:
		c += p
	c /= float(ring.size())
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(ring.size())
	out.fill(c)
	return out


## 이 차례로 이으면 법선이 안쪽을 보는지 (가운데쯤 고리에서 판다).
static func _inward(rings: Array[PackedVector3Array]) -> bool:
	var k: int = clampi(rings.size() / 2, 0, rings.size() - 2)
	var ring: PackedVector3Array = rings[k]
	var nxt: PackedVector3Array = rings[k + 1]
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in ring:
		c += p
	c /= float(ring.size())
	var score: float = 0.0
	for i: int in ring.size():
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % ring.size()]
		var q0: Vector3 = nxt[i]
		score += ((q0 - p0).cross(p1 - p0)).dot(p0 - c)
	return score < 0.0


## 곡선을 따라 굴린 관. path 의 점마다 radius(배열 또는 하나) 크기의 둥근 단면 (sides 각).
## squash = 단면의 side_hint 쪽 반폭 배율 (에어로 관은 옆(X)으로 0.5), side_hint = 단면 x 축으로 삼을 방향 (없으면 알아서).
static func sweep(st: SurfaceTool, path: PackedVector3Array, radius: Variant, color: Variant, sides: int = 10, cap: bool = true, squash: float = 1.0, side_hint: Vector3 = Vector3.ZERO) -> void:
	if path.size() < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var frames: Array[Basis] = transport_frames(path, side_hint)
	for i: int in path.size():
		var r: float = float(radius[i]) if radius is PackedFloat32Array or radius is Array else float(radius)
		var b: Basis = frames[i]
		var ring: PackedVector3Array = PackedVector3Array()
		for k: int in sides:
			var a: float = TAU * float(k) / float(sides)
			ring.append(path[i] + b.x * cos(a) * r * squash + b.y * sin(a) * r)
		rings.append(ring)
	loft(st, rings, color, cap, cap)


## 곡선의 점마다 (x, y = 단면 축, z = 진행 방향) — 비틀리지 않게 앞 틀을 옮겨 간다 (평행 이동).
## side_hint 가 있으면 첫 틀의 x 를 그쪽으로 (옆으로 납작한 관).
static func transport_frames(path: PackedVector3Array, side_hint: Vector3 = Vector3.ZERO) -> Array[Basis]:
	var out: Array[Basis] = []
	var t0: Vector3 = (path[1] - path[0]).normalized()
	var x: Vector3
	if side_hint != Vector3.ZERO and absf(side_hint.normalized().dot(t0)) < 0.98:
		x = (side_hint - t0 * side_hint.dot(t0)).normalized()
	else:
		var ref: Vector3 = Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		x = ref.cross(t0).normalized()
	var y: Vector3 = t0.cross(x).normalized()
	for i: int in path.size():
		var t: Vector3
		if i == 0:
			t = t0
		elif i == path.size() - 1:
			t = (path[i] - path[i - 1]).normalized()
		else:
			t = (path[i + 1] - path[i - 1]).normalized()
		# 앞 틀의 x 를 새 진행 방향에 수직으로 다시 세운다.
		x = (x - t * x.dot(t)).normalized()
		y = t.cross(x).normalized()
		out.append(Basis(x, y, t))
	return out


## 점들을 부드럽게 잇는 곡선 (Catmull-Rom, 마디마다 steps 점). 끝점은 그대로 지난다.
static func spline(points: PackedVector3Array, steps: int = 8) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var n: int = points.size()
	if n < 3:
		return points
	for i: int in n - 1:
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, n - 1)]
		for s: int in steps:
			var t: float = float(s) / float(steps)
			var t2: float = t * t
			var t3: float = t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[n - 1])
	return out


## 곧은 관 (두 점, 굵기 둘). 자전거 살 · 가는 봉.
static func rod(st: SurfaceTool, a: Vector3, b: Vector3, r: float, color: Variant, sides: int = 6, r_end: float = -1.0) -> void:
	var radii: PackedFloat32Array = PackedFloat32Array([r, r if r_end < 0.0 else r_end])
	sweep(st, PackedVector3Array([a, b]), radii, color, sides, true)


## 고리 위의 점들 (가운데 c, 축 axis 둘레, 반지름 r, n 개).
static func circle(c: Vector3, axis: Vector3, r: float, n: int, phase: float = 0.0) -> PackedVector3Array:
	var b: Basis = ClayMesh._basis_along(axis.normalized())
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in n:
		var a: float = phase + TAU * float(i) / float(n)
		out.append(c + b.x * cos(a) * r + b.z * sin(a) * r)
	return out


## 축(X) 둘레로 돌린 회전체 — profile 은 (축에서 거리, 축 방향 x) 점 목록. 바퀴 · 허브 · 원판 · 램프 갓.
static func lathe_x(st: SurfaceTool, center: Vector3, profile: PackedVector2Array, segments: int, color: Variant, closed: bool = false) -> void:
	var prof: PackedVector2Array = profile
	if closed:
		prof = profile.duplicate()
		prof.append(profile[0])
	# ClayMesh.add_lathe 는 Y 축 둘레 (반지름, y) — Y 를 X 로 눕힌다.
	var lat: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in prof:
		lat.append(Vector2(p.x, p.y))
	ClayMesh.add_lathe(st, lat, segments, Transform3D(Basis(Vector3.BACK, -PI * 0.5), center), color)


## 고리 단면 하나를 다른 고리로 옮기며 비트는 곡면 (모서리 둥근 판재 — 흙받이 · 체인 덮개 · 앞 가림판).
## path 를 따라 폭 width(가로 축 = side) · 두께 thick 의 둥근 판을 굴린다.
static func strip(st: SurfaceTool, path: PackedVector3Array, side: Vector3, width: Variant, thick: float, color: Variant, sides: int = 12) -> void:
	var rings: Array[PackedVector3Array] = []
	for i: int in path.size():
		var t: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var x: Vector3 = (side - t * side.dot(t)).normalized()
		var y: Vector3 = t.cross(x).normalized()
		var w: float = float(width[i]) if width is PackedFloat32Array or width is Array else float(width)
		var ring: PackedVector3Array = PackedVector3Array()
		for k: int in sides:
			var a: float = TAU * float(k) / float(sides)
			var s: float = sin(a)
			var c: float = cos(a)
			# 납작한 둥근 네모 (판재).
			var sx: float = signf(c) * pow(absf(c), 0.35) * w * 0.5
			var sy: float = signf(s) * pow(absf(s), 0.35) * thick * 0.5
			ring.append(path[i] + x * sx + y * sy)
		rings.append(ring)
	loft(st, rings, color, true, true)


## 원호 위의 점 (가운데 c, YZ 평면, 각도 도: 0 = 뒤(+z), 90 = 위, 180 = 앞(-z)).
static func arc_points(c: Vector3, r: float, from_deg: float, to_deg: float, n: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in n + 1:
		var a: float = deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(n)))
		out.append(c + Vector3(0.0, sin(a) * r, cos(a) * r))
	return out


## 나선 (용수철 — 뒤 쇼크). a → b 축, 반지름 r, 감은 수 turns.
static func helix(a: Vector3, b: Vector3, r: float, turns: float, n: int) -> PackedVector3Array:
	var axis: Vector3 = b - a
	var basis: Basis = ClayMesh._basis_along(axis.normalized())
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in n + 1:
		var t: float = float(i) / float(n)
		var ang: float = TAU * turns * t
		out.append(a + axis * t + basis.x * cos(ang) * r + basis.z * sin(ang) * r)
	return out
