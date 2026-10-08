class_name FishModel
extends RefCounted
## 물고기 모형 (아이콘 · 자랑 · 전시 · 떨어진 물건). v0.16: 사진 같은 물고기.
## 몸 설계(data/fish/fish_plans.json: 옆모습 윤곽 · 단면 · 지느러미 자리와 모양 · 꼬리 모양 · 눈 · 수염)로 몸을 짜 올리고(loft),
## 살갗은 미리 그린 텍스처(assets/textures/fish/<id>.jpg, tools/art/gen_fish_textures.py — 비늘 · 옆줄 · 아가미뚜껑 · 무늬 ·
## 지느러미 줄기 · 금빛 눈)를 입힌다. 머리는 -X, 길이(주둥이 → 꼬리 끝) 약 0.6m. 가재 · 자라는 예전처럼 점토 모형.
##
## 텍스처 UV (gen_fish_textures.py 와 같다): 몸 x 0.01~0.99 = 주둥이 u 0 → 꼬리자루 u 1, y 0.01~0.71 = 등 → 옆 → 배 → 옆 → 등.
## 지느러미 x 0.01~0.74 = 밑동을 따라, y 0.76~0.98 = 밑동 → 끝. 눈 가운데 (0.875, 0.87), 반지름 (0.1, 0.2).

const PLANS_PATH: String = "res://data/fish/fish_plans.json"
const TEXTURE_DIR: String = "res://assets/textures/fish"
const TOON_SHADER: String = "res://assets/shaders/toon_world.gdshader"
## 몸을 길이 · 둘레로 나누는 칸 수.
const NU: int = 40
const NV: int = 28
## 모형 전체 길이 (주둥이 → 꼬리 끝, m).
const TOTAL_LENGTH: float = 0.62

static var _cache: Dictionary[String, ArrayMesh] = {}
static var _materials: Dictionary[String, Material] = {}
static var _plans: Dictionary = {}


static func mesh(fish: FishInfo) -> ArrayMesh:
	if _cache.has(fish.id):
		return _cache[fish.id]
	var built: ArrayMesh = null
	if fish.shape == "crayfish" or fish.shape == "turtle":
		var st: SurfaceTool = ClayMesh.begin()
		if fish.shape == "crayfish":
			_add_crayfish(st, fish)
		else:
			_add_turtle(st, fish)
		built = ClayMesh.commit(st)
	else:
		built = _Builder.new(fish, plan_of(fish.shape)).build()
	_cache[fish.id] = built
	return built


## 이 물고기를 그리는 머티리얼: 살갗 텍스처가 있으면 그것을 입힌 툰 머티리얼, 없으면 fallback (정점 색 점토).
static func material(fish: FishInfo, fallback: Material) -> Material:
	if _materials.has(fish.id):
		return _materials[fish.id]
	var path: String = "%s/%s.jpg" % [TEXTURE_DIR, fish.id]
	if fish.shape == "crayfish" or fish.shape == "turtle" or not ResourceLoader.exists(path):
		return fallback
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(TOON_SHADER)
	m.set_shader_parameter("albedo_texture", load(path) as Texture2D)
	_materials[fish.id] = m
	return m


## 몸 설계 (base 가 있으면 그 설계를 이어받아 덮어쓴다).
static func plan_of(shape: String) -> Dictionary:
	if _plans.is_empty():
		var file: FileAccess = FileAccess.open(PLANS_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_plans = parsed if parsed is Dictionary else {}
	var plan: Dictionary = (_plans.get(shape, _plans.get("slim", {})) as Dictionary).duplicate()
	if plan.has("base"):
		var merged: Dictionary = (_plans.get(str(plan["base"]), {}) as Dictionary).duplicate()
		merged.merge(plan, true)
		plan = merged
	return plan


## 몸 하나를 짜는 일꾼 (설계 · 길이 · 좌표 도우미를 한곳에).
class _Builder:
	var fish: FishInfo
	var plan: Dictionary
	var L: float
	var x0: float
	var sides: float
	# 삼각형을 SurfaceTool 대신 배열에 바로 쌓는다 (처음 보는 물고기를 만들 때 끊김이 덜하게).
	var _verts: PackedVector3Array = PackedVector3Array()
	var _normals: PackedVector3Array = PackedVector3Array()
	var _uvs: PackedVector2Array = PackedVector2Array()
	var _colors: PackedColorArray = PackedColorArray()
	var prof_u: PackedFloat32Array = PackedFloat32Array()
	var prof_v: Array[Vector3] = []

	func _init(f: FishInfo, p: Dictionary) -> void:
		fish = f
		plan = p
		var tail: Dictionary = plan.get("tail", {})
		var tail_len: float = float(tail.get("len", 0.25)) if str(tail.get("type", "")) != "none" else 0.0
		# 꼬리까지 합쳐 TOTAL_LENGTH 가 되게 몸길이를 맞춘다.
		L = TOTAL_LENGTH / (1.0 + tail_len * 0.9)
		x0 = -TOTAL_LENGTH * 0.5
		sides = float(plan.get("sides", 2.0))
		for row: Variant in plan.get("prof", []):
			var r: Array = row
			prof_u.append(float(r[0]))
			prof_v.append(Vector3(float(r[1]), float(r[2]), float(r[3])))

	func build() -> ArrayMesh:
		_body()
		_fins()
		_eyes()
		_extras()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_COLOR] = _colors
		var out: ArrayMesh = ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out

	# ---- 몸 윤곽 ----

	## u 자리의 (등 높이, 배 깊이, 반폭) m. 귀상어는 머리 앞이 망치처럼 넓적하다.
	func prof(u: float) -> Vector3:
		var v: Vector3 = prof_v[prof_v.size() - 1]
		for i: int in prof_u.size() - 1:
			if u <= prof_u[i + 1]:
				var t: float = (u - prof_u[i]) / maxf(prof_u[i + 1] - prof_u[i], 0.0001)
				# 부드럽게 (모서리가 생기지 않게).
				t = t * t * (3.0 - 2.0 * t) * 0.5 + t * 0.5
				v = prof_v[i].lerp(prof_v[i + 1], t)
				break
		if plan.has("hammer"):
			var hm: Array = plan["hammer"]
			var hl: float = float(hm[0])
			if u < hl * 1.6:
				var k: float = clampf(1.0 - pow(u / (hl * 1.6), 3.0), 0.0, 1.0)
				var flat: float = clampf(u / 0.015, 0.0, 1.0)
				v.z = lerpf(v.z, float(hm[1]) * flat, k)
				v.x = lerpf(v.x, 0.035 * flat, k * 0.7)
				v.y = lerpf(v.y, 0.03 * flat, k * 0.7)
		return v * L

	func x_of(u: float) -> float:
		return x0 + u * L

	## 몸 겉면 한 점: θ 0 = 등, π/2 = 오른쪽(+Z) 옆, π = 배.
	func surf(u: float, theta: float) -> Vector3:
		return surf_at(prof(u), x_of(u), theta)

	## surf 와 같지만 그 자리의 윤곽(prof)을 미리 구해 둔 것 (한 둘레를 만들 때 한 번만 구한다).
	func surf_at(p: Vector3, x: float, theta: float) -> Vector3:
		var cy: float = (p.x - p.y) * 0.5
		var ry: float = (p.x + p.y) * 0.5
		var c: float = cos(theta)
		var s: float = sin(theta)
		var e: float = 2.0 / sides
		var cc: float = signf(c) * pow(absf(c), e)
		var ss: float = signf(s) * pow(absf(s), e)
		return Vector3(x, cy + ry * cc, p.z * ss)

	## 높이 -1(배) ~ 1(등) → θ (오른쪽 옆).
	static func theta_of(h: float) -> float:
		return acos(clampf(h, -0.999, 0.999))

	func axis(u: float) -> Vector3:
		var p: Vector3 = prof(u)
		return Vector3(x_of(u), (p.x - p.y) * 0.5, 0.0)

	# ---- 삼각형 ----

	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color = Color.WHITE) -> void:
		# 앞면이 법선 쪽을 보게 (Godot 은 시계 방향이 앞면).
		var face: Vector3 = (b - a).cross(c - a)
		if face.dot(na + nb + nc) > 0.0:
			var t: Vector3 = b
			b = c
			c = t
			var tn: Vector3 = nb
			nb = nc
			nc = tn
			var tu: Vector2 = ub
			ub = uc
			uc = tu
		_verts.append(a)
		_verts.append(b)
		_verts.append(c)
		_normals.append(na)
		_normals.append(nb)
		_normals.append(nc)
		_uvs.append(ua)
		_uvs.append(ub)
		_uvs.append(uc)
		_colors.append(col)
		_colors.append(col)
		_colors.append(col)

	func body_uv(u: float, j_frac: float) -> Vector2:
		return Vector2(0.01 + 0.98 * clampf(u, 0.0, 1.0), 0.01 + 0.70 * j_frac)

	static func fin_uv(s: float, t: float) -> Vector2:
		return Vector2(0.01 + 0.73 * clampf(s, 0.0, 1.0), 0.76 + 0.22 * clampf(t, 0.0, 1.0))

	# ---- 몸통 ----

	func _body() -> void:
		var grid: Array[PackedVector3Array] = []
		var us: PackedFloat32Array = PackedFloat32Array()
		var axes: PackedVector3Array = PackedVector3Array()
		for i: int in NU + 1:
			# 주둥이와 꼬리자루 쪽을 촘촘히.
			var u: float = 0.5 - 0.5 * cos(PI * float(i) / float(NU))
			us.append(u)
			var p: Vector3 = prof(u)
			var x: float = x_of(u)
			axes.append(Vector3(x, (p.x - p.y) * 0.5, 0.0))
			var ring: PackedVector3Array = PackedVector3Array()
			for j: int in NV + 1:
				ring.append(surf_at(p, x, TAU * float(j) / float(NV)))
			grid.append(ring)
		var normals: Array[PackedVector3Array] = []
		for i: int in NU + 1:
			var row: PackedVector3Array = PackedVector3Array()
			for j: int in NV + 1:
				var a: Vector3 = grid[mini(i + 1, NU)][j] - grid[maxi(i - 1, 0)][j]
				var b: Vector3 = grid[i][(j + 1) % NV] - grid[i][(j - 1 + NV) % NV]
				var n: Vector3 = a.cross(b).normalized()
				var out: Vector3 = grid[i][j] - axes[i]
				if i == 0:
					out = Vector3.LEFT
				if n.length() < 0.5:
					n = out.normalized() if out.length() > 0.0001 else Vector3.LEFT
				if n.dot(out) < 0.0:
					n = -n
				row.append(n)
			normals.append(row)
		for i: int in NU:
			for j: int in NV:
				var a: Vector3 = grid[i][j]
				var b: Vector3 = grid[i + 1][j]
				var c: Vector3 = grid[i + 1][j + 1]
				var d: Vector3 = grid[i][j + 1]
				var ua: Vector2 = body_uv(us[i], float(j) / NV)
				var ub: Vector2 = body_uv(us[i + 1], float(j) / NV)
				var uc: Vector2 = body_uv(us[i + 1], float(j + 1) / NV)
				var ud: Vector2 = body_uv(us[i], float(j + 1) / NV)
				tri(a, b, c, normals[i][j], normals[i + 1][j], normals[i + 1][j + 1], ua, ub, uc)
				tri(a, c, d, normals[i][j], normals[i + 1][j + 1], normals[i][j + 1], ua, uc, ud)
		# 꼬리자루 끝을 막는다 (꼬리지느러미가 없으면 보인다).
		var end_c: Vector3 = axis(1.0)
		for j: int in NV:
			tri(grid[NU][j], grid[NU][j + 1], end_c, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, body_uv(1.0, float(j) / NV), body_uv(1.0, float(j + 1) / NV), body_uv(1.0, 0.25))

	# ---- 지느러미 ----

	## 밑동 점들 → 끝 점들 사이를 rows 칸으로 메운 얇은 막 (양면). side_n = 막의 한쪽 법선.
	func membrane(base: PackedVector3Array, tip: PackedVector3Array, side_n: Vector3, rows: int = 3, bulge: Vector3 = Vector3.ZERO) -> void:
		var n: int = base.size()
		var pts: Array[PackedVector3Array] = []
		for r: int in rows + 1:
			var t: float = float(r) / float(rows)
			var row: PackedVector3Array = PackedVector3Array()
			for k: int in n:
				# 막이 살짝 휘어 (줄기가 바깥으로 굽는다) 평평한 판처럼 보이지 않는다.
				row.append(base[k].lerp(tip[k], t) + bulge * sin(PI * t) * sin(PI * float(k) / maxf(n - 1, 1)))
			pts.append(row)
		for face: float in [1.0, -1.0]:
			# 얇은 막이라 빛이 비쳐 든다: 법선을 위쪽으로 기울여 어느 쪽에서 봐도 너무 어둡지 않게.
			var nn: Vector3 = (side_n * face + Vector3.UP * 0.55).normalized()
			var off: Vector3 = side_n * face * 0.0012
			for r: int in rows:
				for k: int in n - 1:
					var s0: float = float(k) / float(n - 1)
					var s1: float = float(k + 1) / float(n - 1)
					var t0: float = float(r) / float(rows)
					var t1: float = float(r + 1) / float(rows)
					tri(pts[r][k] + off, pts[r + 1][k] + off, pts[r + 1][k + 1] + off, nn, nn, nn, fin_uv(s0, t0), fin_uv(s0, t1), fin_uv(s1, t1))
					tri(pts[r][k] + off, pts[r + 1][k + 1] + off, pts[r][k + 1] + off, nn, nn, nn, fin_uv(s0, t0), fin_uv(s1, t1), fin_uv(s1, t0))

	## 지느러미 높이 모양 (s = 밑동 앞 0 → 뒤 1).
	static func fin_height(kind: String, s: float, k: int) -> float:
		match kind:
			"spiny":
				var spike: float = 1.0 if k % 2 == 0 else 0.72
				return (0.95 - 0.3 * s) * spike * smoothstep(0.0, 0.12, s + 0.02)
			"tri":
				return pow(s / 0.45, 0.85) if s < 0.45 else pow(1.0 - (s - 0.45) / 0.55, 1.6)
			"low":
				return smoothstep(0.0, 0.08, s) * (1.0 - 0.3 * s)
			"finlet":
				var f: float = fmod(s * 6.0, 1.0)
				return (1.0 - f) * 0.9 + 0.1
			_:
				# 부드러운 지느러미: 앞쪽 줄기가 가장 길고 둥글게 줄어든다.
				return sin(PI * minf(s * 1.8 + 0.12, 1.0) * 0.5) * (1.0 - 0.6 * s) + 0.08

	## 등(top = true) 또는 배 가운데 줄을 따라 선 지느러미.
	func median_fin(spec: Array, top: bool) -> void:
		var u0: float = float(spec[0])
		var u1: float = minf(float(spec[1]), 0.995)
		var h: float = float(spec[2]) * L
		var kind: String = str(spec[3]) if spec.size() > 3 else "soft"
		var n: int = clampi(int((u1 - u0) * 60.0) + 4, 5, 34)
		if kind == "spiny":
			n = n + (1 - n % 2)
		var base: PackedVector3Array = PackedVector3Array()
		var tip: PackedVector3Array = PackedVector3Array()
		var dir: float = 1.0 if top else -1.0
		var sweep: float = 0.65 if kind == "tri" else (0.25 if kind == "spiny" else 0.45)
		for k: int in n:
			var s: float = float(k) / float(n - 1)
			var u: float = lerpf(u0, u1, s)
			var b: Vector3 = surf(u, 0.0 if top else PI) - Vector3(0.0, dir * 0.003, 0.0)
			var hh: float = h * fin_height(kind, s, k)
			base.append(b)
			tip.append(b + Vector3(sweep * hh, dir * hh, 0.0))
		membrane(base, tip, Vector3.BACK, 3)

	## 옆구리에 붙은 한 쌍 (가슴 · 배지느러미): 밑동 짧은 줄에서 뒤 · 바깥 · 아래로 부채꼴.
	func paired_fin(u: float, h: float, length: float, spread: float, droop: float) -> void:
		for side: float in [1.0, -1.0]:
			var th: float = theta_of(h)
			var base: PackedVector3Array = PackedVector3Array()
			var tip: PackedVector3Array = PackedVector3Array()
			var n: int = 9
			for k: int in n:
				var s: float = float(k) / float(n - 1)
				var bu: float = u + 0.035 * s
				var b: Vector3 = surf(bu, th + (0.18 - 0.36 * s) * 0.0)
				b.z *= side
				b += Vector3(0.0, (0.5 - s) * 0.01 * L, 0.0)
				var a: float = lerpf(-0.55, 0.75, s)
				var reach: float = length * L * (0.55 + 0.45 * sin(PI * clampf(s * 0.9 + 0.1, 0.0, 1.0)))
				var d: Vector3 = Vector3(cos(a) * 0.85, -sin(a) * 0.55 - droop, side * spread).normalized()
				base.append(b)
				tip.append(b + d * reach)
			var nrm: Vector3 = (tip[n / 2] - base[n / 2]).cross(base[n - 1] - base[0]).normalized()
			membrane(base, tip, nrm, 3)

	## 꼬리지느러미: 꼬리자루 끝 세로 줄에서 모양대로.
	func caudal() -> void:
		var tail: Dictionary = plan.get("tail", {})
		var kind: String = str(tail.get("type", "forked"))
		if kind == "none":
			return
		var length: float = float(tail.get("len", 0.3)) * L
		var height: float = float(tail.get("h", 0.4)) * L
		var notch: float = float(tail.get("notch", 0.4))
		var p: Vector3 = prof(1.0)
		var end_x: float = x_of(1.0) - 0.004
		var cy: float = (p.x - p.y) * 0.5
		var n: int = 21
		var layers: Array[float] = [0.0]
		if kind == "fan":
			layers = [0.42, -0.42]
		for tilt: float in layers:
			var base: PackedVector3Array = PackedVector3Array()
			var tip: PackedVector3Array = PackedVector3Array()
			for k: int in n:
				var s: float = float(k) / float(n - 1)
				var e: float = absf(2.0 * s - 1.0)
				var bx: float = end_x
				var by: float = cy + lerpf(-p.y, p.x, s) * 0.85
				var tx: float = 0.0
				var ty: float = (s - 0.5) * height
				match kind:
					"forked":
						tx = length * (notch + (1.0 - notch) * pow(e, 0.75))
					"lunate":
						tx = length * (0.22 + 0.78 * pow(e, 0.55))
						ty = (s - 0.5) * height * (1.0 + 0.1 * e)
					"truncate":
						tx = length * (0.9 + 0.1 * e)
						ty = (s - 0.5) * height * 0.95
					"rounded":
						tx = length * (0.35 + 0.65 * sqrt(maxf(1.0 - e * e, 0.0)))
					"hetero":
						# 상어: 위 갈래가 길게 위로 솟고, 아래 갈래는 짧다.
						ty = lerpf(-0.32, 0.72, s) * height
						tx = length * (0.48 - 0.25 * (0.3 - s) / 0.3) if s < 0.3 else length * (0.22 + 0.78 * pow((s - 0.3) / 0.7, 0.85))
						if s > 0.3 and s < 0.42:
							tx *= 0.8
					"fan":
						tx = length * (0.75 + 0.25 * sin(PI * s)) * (1.0 + 0.08 * sin(s * 18.0))
						ty = (s - 0.5) * height
					"pointed":
						tx = length * (1.0 - e)
						ty = (s - 0.5) * height
				base.append(Vector3(bx, by, 0.0))
				tip.append(Vector3(bx + tx, cy + ty, tx * tilt))
			membrane(base, tip, Vector3(0.0, -tilt, 1.0).normalized(), 4, Vector3(0.0, 0.0, 0.008 * L))

	func _fins() -> void:
		caudal()
		for spec: Variant in plan.get("dorsal", []):
			median_fin(spec, true)
		for spec: Variant in plan.get("anal", []):
			median_fin(spec, false)
		if plan.has("adipose"):
			var ad: Array = plan["adipose"]
			median_fin([float(ad[0]), float(ad[0]) + 0.07, float(ad[1]), "soft"], true)
		if plan.has("pectoral"):
			var pc: Array = plan["pectoral"]
			paired_fin(float(pc[0]), float(pc[1]), float(pc[2]), 0.42, 0.1)
		if plan.has("pelvic"):
			var pv: Array = plan["pelvic"]
			paired_fin(float(pv[0]), -0.9, float(pv[1]), 0.28, 0.45)

	# ---- 눈 ----

	## 눈알: 겉면에서 살짝 솟은 볼록렌즈 (텍스처의 금빛 홍채 · 눈동자 · 반짝).
	func eye_at(center: Vector3, normal: Vector3, radius: float) -> void:
		var n: Vector3 = normal.normalized()
		var t: Vector3 = n.cross(Vector3.UP)
		if t.length() < 0.1:
			t = n.cross(Vector3.FORWARD)
		t = t.normalized()
		var b: Vector3 = n.cross(t).normalized()
		# 홍채 그림이 앞(-X 쪽)을 보도록 가로축 방향을 맞춘다.
		if t.dot(Vector3.LEFT) < 0.0:
			t = -t
		var rings: int = 5
		var segs: int = 18
		var pts: Array[PackedVector3Array] = []
		var uvs: Array[PackedVector2Array] = []
		var nrms: Array[PackedVector3Array] = []
		for r: int in rings + 1:
			var a: float = float(r) / float(rings) * PI * 0.5
			var rr: float = sin(a) * radius
			var hh: float = cos(a) * radius * 0.42
			var row: PackedVector3Array = PackedVector3Array()
			var urow: PackedVector2Array = PackedVector2Array()
			var nrow: PackedVector3Array = PackedVector3Array()
			for k: int in segs + 1:
				var phi: float = TAU * float(k) / float(segs)
				var dir: Vector3 = t * cos(phi) + b * sin(phi)
				row.append(center + n * (hh - radius * 0.12) + dir * rr)
				var f: float = sin(a)
				urow.append(Vector2(0.875 + 0.1 * cos(phi) * f, 0.87 - 0.2 * sin(phi) * f))
				nrow.append((n * cos(a) + dir * sin(a)).normalized())
			pts.append(row)
			uvs.append(urow)
			nrms.append(nrow)
		for r: int in rings:
			for k: int in segs:
				tri(pts[r][k], pts[r + 1][k], pts[r + 1][k + 1], nrms[r][k], nrms[r + 1][k], nrms[r + 1][k + 1], uvs[r][k], uvs[r + 1][k], uvs[r + 1][k + 1])
				tri(pts[r][k], pts[r + 1][k + 1], pts[r][k + 1], nrms[r][k], nrms[r + 1][k + 1], nrms[r][k + 1], uvs[r][k], uvs[r + 1][k + 1], uvs[r][k + 1])

	func _eyes() -> void:
		var e: Array = plan.get("eye", [0.1, 0.3, 0.03])
		var radius: float = float(e[2]) * L
		if plan.has("hammer"):
			# 귀상어: 망치 머리 양 끝에 눈.
			var hu: float = float((plan["hammer"] as Array)[0]) * 0.55
			for side: float in [1.0, -1.0]:
				var p: Vector3 = surf(hu, PI * 0.5)
				p.z *= side
				eye_at(p, Vector3(-0.25, 0.1, side), radius * 1.2)
			return
		var th: float = theta_of(float(e[1]))
		for side: float in [1.0, -1.0]:
			var p: Vector3 = surf(float(e[0]), th)
			p.z *= side
			var out: Vector3 = p - axis(float(e[0]))
			eye_at(p, out + Vector3(-0.15 * radius / L, 0.0, 0.0), radius)

	# ---- 수염 · 부리 · 가시 · 골판 ----

	## 가는 원뿔 막대 (수염 · 부리 · 가시). uv = 칠할 자리, col = 덧칠할 색.
	func rod(from: Vector3, to: Vector3, r0: float, r1: float, uv: Vector2, col: Color, segs: int = 6) -> void:
		var axis_d: Vector3 = (to - from).normalized()
		var t: Vector3 = axis_d.cross(Vector3.UP)
		if t.length() < 0.1:
			t = axis_d.cross(Vector3.BACK)
		t = t.normalized()
		var b: Vector3 = axis_d.cross(t).normalized()
		for k: int in segs:
			var a0: float = TAU * float(k) / float(segs)
			var a1: float = TAU * float(k + 1) / float(segs)
			var d0: Vector3 = t * cos(a0) + b * sin(a0)
			var d1: Vector3 = t * cos(a1) + b * sin(a1)
			tri(from + d0 * r0, to + d0 * r1, to + d1 * r1, d0, d0, d1, uv, uv, uv, col)
			tri(from + d0 * r0, to + d1 * r1, from + d1 * r0, d0, d1, d1, uv, uv, uv, col)

	func _extras() -> void:
		var barbels: Array = plan.get("barbels", []).duplicate()
		if fish.barbels and barbels.is_empty():
			barbels = [[0.03, -0.2, 0.09, 2]]
		for spec: Variant in barbels:
			var b: Array = spec
			for k: int in int(b[3]):
				for side: float in [1.0, -1.0]:
					var start: Vector3 = surf(float(b[0]) + 0.01 * k, theta_of(float(b[1])))
					start.z *= side * 0.8
					var length: float = float(b[2]) * L
					var to: Vector3 = start + Vector3(0.35 + 0.2 * k, -0.75, side * (0.35 + 0.2 * k)).normalized() * length
					rod(start, to, 0.006, 0.0015, Vector2(0.3, 0.8), Color.WHITE)
		if plan.has("beak"):
			var bk: Array = plan["beak"]
			var start: Vector3 = surf(0.015, theta_of(float(bk[1])))
			start.z = 0.0
			rod(start, start + Vector3(-float(bk[0]) * L, -0.01, 0.0), 0.012, 0.002, Vector2(0.3, 0.05), Color(0.45, 0.45, 0.6))
			rod(start + Vector3(-float(bk[0]) * L * 0.85, -0.01, 0.0), start + Vector3(-float(bk[0]) * L, -0.012, 0.0), 0.004, 0.001, body_uv(0.5, 0.5), Color(0.95, 0.35, 0.3))
		if plan.has("spines"):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = fish.id.hash()
			for k: int in int(plan["spines"]):
				var u: float = rng.randf_range(0.12, 0.72)
				var th: float = rng.randf_range(0.2, PI - 0.3) * (1.0 if k % 2 == 0 else -1.0)
				var p: Vector3 = surf(u, th)
				var out: Vector3 = (p - axis(u)).normalized()
				rod(p - out * 0.003, p + out * 0.018 + Vector3(0.006, 0.0, 0.0), 0.004, 0.0005, body_uv(u, fposmod(th, TAU) / TAU), Color.WHITE)
		if plan.has("scutes"):
			var sc: Array = plan["scutes"]
			var size: float = float(sc[1]) * L
			for row_th: float in [0.0, PI * 0.42, -PI * 0.42, PI * 0.72, -PI * 0.72]:
				for k: int in 11:
					var u: float = 0.3 + 0.62 * float(k) / 10.0
					var p: Vector3 = surf(u, row_th)
					var out: Vector3 = (p - axis(u)).normalized()
					var uv: Vector2 = body_uv(u, fposmod(row_th, TAU) / TAU)
					var c: Color = Color(1.0, 1.0, 0.96)
					rod(p - out * 0.002, p + out * size * 0.6, size * 0.55, 0.001, uv, c, 4)


## 가재: 마디진 몸 + 부채 꼬리 + 집게 두 개 + 더듬이. 머리는 -X.
static func _add_crayfish(st: SurfaceTool, fish: FishInfo) -> void:
	var shell: Callable = ClayMesh.vertical_gradient(fish.belly_color, fish.body_color, 0.6)
	ClayMesh.add_ellipsoid(st, Vector3(-0.08, 0.0, 0.0), Vector3(0.14, 0.08, 0.09), shell, 12, 7)
	for i: int in 4:
		var x: float = 0.06 + 0.07 * float(i)
		var k: float = 1.0 - 0.15 * float(i)
		ClayMesh.add_ellipsoid(st, Vector3(x, -0.005 * float(i), 0.0), Vector3(0.045, 0.06 * k, 0.07 * k), shell, 10, 5)
	for side: float in [-1.0, 0.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(0.37, -0.02, side * 0.04), Vector3(0.05, 0.012, 0.035), fish.fin_color, 6, 3, Basis(Vector3.UP, side * 0.5))
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(st, Vector3(-0.15, -0.01, side * 0.07), Vector3(-0.27, 0.0, side * 0.17), 0.025, fish.body_color, 6, 1)
		ClayMesh.add_ellipsoid(st, Vector3(-0.33, 0.0, side * 0.19), Vector3(0.07, 0.035, 0.045), shell, 8, 4, Basis(Vector3.UP, side * 0.3))
		ClayMesh.add_ellipsoid(st, Vector3(-0.39, 0.0, side * 0.16), Vector3(0.04, 0.02, 0.025), fish.fin_color, 6, 3, Basis(Vector3.UP, side * 0.6))
		ClayMesh.add_capsule(st, Vector3(-0.2, 0.02, side * 0.03), Vector3(-0.42, 0.06, side * 0.12), 0.006, fish.fin_color, 4, 1)
		for leg: int in 3:
			ClayMesh.add_capsule(st, Vector3(-0.04 + 0.05 * float(leg), -0.05, side * 0.06), Vector3(-0.02 + 0.05 * float(leg), -0.09, side * 0.14), 0.01, fish.fin_color, 4, 1)
		var eye: Vector3 = Vector3(-0.2, 0.06, side * 0.045)
		ClayMesh.add_ellipsoid(st, eye, Vector3(0.025, 0.028, 0.025), Color("#2B211E"), 8, 4)
		ClayMesh.add_ellipsoid(st, eye + Vector3(-0.01, 0.012, side * 0.012), Vector3(0.008, 0.008, 0.006), Color.WHITE, 4, 2)


## 자라: 납작한 등딱지 + 목을 내민 머리 + 지느러미발 넷. 머리는 -X.
static func _add_turtle(st: SurfaceTool, fish: FishInfo) -> void:
	ClayMesh.add_ellipsoid(st, Vector3(0.02, 0.02, 0.0), Vector3(0.24, 0.07, 0.2), ClayMesh.vertical_gradient(fish.belly_color, fish.body_color, 0.4), 16, 8)
	ClayMesh.add_ellipsoid(st, Vector3(0.02, -0.01, 0.0), Vector3(0.25, 0.03, 0.21), fish.belly_color, 16, 4)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = fish.id.hash()
	for i: int in 7:
		var a: float = rng.randf() * TAU
		var rr: float = rng.randf_range(0.0, 0.6)
		ClayMesh.add_ellipsoid(st, Vector3(0.02 + cos(a) * 0.24 * rr, 0.07 * sqrt(1.0 - rr * rr) + 0.02, sin(a) * 0.2 * rr), Vector3(0.03, 0.012, 0.03), fish.accent_color, 6, 2)
	ClayMesh.add_capsule(st, Vector3(-0.2, 0.01, 0.0), Vector3(-0.3, 0.03, 0.0), 0.04, fish.fin_color, 8, 2)
	ClayMesh.add_ellipsoid(st, Vector3(-0.34, 0.04, 0.0), Vector3(0.06, 0.05, 0.05), fish.fin_color, 10, 5)
	ClayMesh.add_ellipsoid(st, Vector3(-0.4, 0.04, 0.0), Vector3(0.02, 0.015, 0.015), fish.fin_color.darkened(0.2), 6, 3)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(-0.12, -0.01, side * 0.2), Vector3(0.08, 0.015, 0.05), fish.fin_color, 8, 3, Basis(Vector3.UP, side * -0.6))
		ClayMesh.add_ellipsoid(st, Vector3(0.16, -0.01, side * 0.17), Vector3(0.06, 0.015, 0.04), fish.fin_color, 8, 3, Basis(Vector3.UP, side * 0.6))
		var eye: Vector3 = Vector3(-0.36, 0.065, side * 0.03)
		ClayMesh.add_ellipsoid(st, eye, Vector3(0.016, 0.018, 0.014), Color("#2B211E"), 6, 3)
		ClayMesh.add_ellipsoid(st, Vector3(-0.33, 0.035, side * 0.045), Vector3(0.014, 0.01, 0.008), Color("#F4A6A0"), 4, 2)
	ClayMesh.add_ellipsoid(st, Vector3(0.27, 0.0, 0.0), Vector3(0.04, 0.015, 0.02), fish.fin_color, 6, 3)
