class_name KitchenProps
extends RefCounted
## 주방 조리대의 3D 모형 (v0.18 리듬 요리, 위에서 내려다보는 주방): 조리 도구와 재료를 실제 크기(m)로 빚는다.
## 도마 40×27cm · 식칼 30cm · 팬 지름 26cm · 냄비 24cm · 웍 32cm · 접시 24cm, 소고기 한 덩이 12cm · 표고 6cm · 달걀 5.5cm …
## 모두 점토 머티리얼(정점 색)로 그리고, 한 번 빚은 것은 나눠 쓴다. 삼각형 수는 따지지 않는다 (작은 창 하나에만 그린다).
## 좌표: 바닥(놓인 면) y = 0, 앞(보는 사람 쪽) = +Z, 오른쪽 = +X.

const STEEL: Color = Color("#C9CED6")
const STEEL_DARK: Color = Color("#7E8692")
const BLACK_PAN: Color = Color("#2A2C31")
const WOOD_LIGHT: Color = Color("#D9B27E")
const WOOD_DARK: Color = Color("#A8743F")
const HANDLE: Color = Color("#2E2622")
const CERAMIC: Color = Color("#F6F3EC")
const BAMBOO: Color = Color("#D8BC7C")
const BAMBOO_DARK: Color = Color("#A88A4A")

static var _cache: Dictionary[String, ArrayMesh] = {}


static func mesh(key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	match key:
		"counter":
			_counter(st)
		"board":
			_board(st)
		"knife":
			_knife(st)
		"pan":
			_pan(st, false)
		"grill_pan":
			_pan(st, true)
		"pot":
			_pot(st)
		"pot_lid":
			_lid(st, 0.125)
		"wok":
			_wok(st)
		"fryer":
			_fryer(st)
		"basket":
			_basket(st)
		"steamer":
			_steamer(st)
		"steamer_lid":
			_steamer_lid(st)
		"plate":
			_plate(st)
		"bowl":
			_bowl(st)
		"shaker":
			_shaker(st)
		"ladle":
			_ladle(st)
		"turner":
			_turner(st)
		"skewer":
			ClayMesh.add_rod(st, Vector3(-0.13, 0.0, 0.0), Vector3(0.13, 0.0, 0.0), 0.0035, 0.002, WOOD_LIGHT, 8)
		"burner":
			_burner(st)
		"pitcher":
			_pitcher(st)
		"towel":
			_towel(st)
		"jar":
			_jar(st)
		_:
			pass
	var m: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = m
	return m


# ---- 조리대 ----

## 조리대: 나뭇결 판 여러 장 (1.8 × 0.9m, 두께 4cm) + 뒤쪽 타일 벽 걸레받이.
static func _counter(st: SurfaceTool) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var planks: int = 12
	for i: int in planks:
		var z: float = -0.45 + 1.2 * (float(i) + 0.5) / float(planks)
		var shade: float = rng.randf_range(-0.06, 0.06)
		var base: Color = Color("#C89A66").lightened(shade) if shade > 0.0 else Color("#C89A66").darkened(-shade)
		var grain: Callable = func(p: Vector3, _n: Vector3) -> Color:
			var g: float = 0.5 + 0.5 * sin(p.x * 38.0 + sin(p.x * 7.0 + float(i)) * 2.5 + float(i) * 1.7)
			return base.darkened(0.08 * g)
		ClayMesh.add_rounded_box(st, Vector3(0.0, -0.02, z), Vector3(2.2, 0.04, 1.2 / float(planks) - 0.003), 0.12, grain, Basis(), 24, 6)
	# 뒤쪽 벽 타일 (화면 위쪽 끝에 살짝 보인다).
	for tx: int in 15:
		for ty: int in 3:
			ClayMesh.add_rounded_box(st, Vector3(-1.05 + 0.15 * float(tx), 0.06 + 0.1 * float(ty), -0.47), Vector3(0.145, 0.095, 0.02), 0.2, Color("#EAF2F0").darkened(0.03 * float((tx + ty) % 2)), Basis(), 10, 4)


static func _board(st: SurfaceTool) -> void:
	var size: Vector3 = Vector3(0.4, 0.024, 0.27)
	var grain: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var g: float = 0.5 + 0.5 * sin(p.x * 55.0 + sin(p.z * 14.0) * 3.0)
		return WOOD_LIGHT.darkened(0.07 * g)
	ClayMesh.add_rounded_box(st, Vector3(0.0, size.y * 0.5, 0.0), size, 0.15, grain, Basis(), 40, 10)
	# 즙 받이 홈 (가장자리 둘레의 얕은 줄).
	var groove: Color = WOOD_DARK.lightened(0.15)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rounded_box(st, Vector3(0.0, size.y + 0.0005, side * (size.z * 0.5 - 0.022)), Vector3(size.x - 0.05, 0.002, 0.006), 0.4, groove, Basis(), 16, 3)
		ClayMesh.add_rounded_box(st, Vector3(side * (size.x * 0.5 - 0.022), size.y + 0.0005, 0.0), Vector3(0.006, 0.002, size.z - 0.05), 0.4, groove, Basis(), 16, 3)


## 식칼: 날 (긴 쪽 = X, 날 끝 = +X), 손잡이는 -X. 원점 = 날과 손잡이 사이 아래 (도마에 닿는 날 아래쪽).
static func _knife(st: SurfaceTool) -> void:
	var blade: PackedVector2Array = PackedVector2Array()
	# 옆모습 (x, y): 등은 곧고, 날은 끝으로 갈수록 둥글게 올라간다.
	for i: int in 13:
		var t: float = float(i) / 12.0
		blade.append(Vector2(lerpf(0.0, 0.19, t), 0.045 - 0.01 * t * t))
	for i: int in 13:
		var t: float = 1.0 - float(i) / 12.0
		blade.append(Vector2(lerpf(0.0, 0.19, t), 0.002 + 0.03 * pow(t, 3.0)))
	_extrude(st, blade, 0.0025, STEEL, Color("#EEF2F6"))
	# 손잡이 + 리벳 세 개 + 받침쇠.
	ClayMesh.add_rounded_box(st, Vector3(-0.065, 0.026, 0.0), Vector3(0.12, 0.024, 0.017), 0.3, HANDLE, Basis(), 20, 8)
	ClayMesh.add_rounded_box(st, Vector3(-0.004, 0.026, 0.0), Vector3(0.012, 0.03, 0.02), 0.3, STEEL_DARK, Basis(), 12, 6)
	for k: int in 3:
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_ellipsoid(st, Vector3(-0.03 - 0.035 * float(k), 0.026, side * 0.0086), Vector3(0.004, 0.004, 0.0012), STEEL, 10, 6)


## 옆모습 다각형을 두께 thickness 로 밀어낸 판 (칼날). 앞뒤 면 + 둘레.
static func _extrude(st: SurfaceTool, outline: PackedVector2Array, thickness: float, color: Color, edge: Color) -> void:
	var n: int = outline.size()
	var center: Vector2 = Vector2.ZERO
	for p: Vector2 in outline:
		center += p
	center /= float(n)
	for side: float in [-1.0, 1.0]:
		var z: float = side * thickness * 0.5
		for i: int in n:
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % n]
			var tri: Array[Vector3] = [Vector3(center.x, center.y, z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, z)]
			if side < 0.0:
				tri = [tri[0], tri[2], tri[1]]
			for v: Vector3 in tri:
				st.set_color(color.lightened(0.12 * (v.y / 0.045)))
				st.set_normal(Vector3(0.0, 0.0, side))
				st.add_vertex(v)
	for i: int in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var nrm: Vector3 = Vector3(b.y - a.y, -(b.x - a.x), 0.0).normalized()
		var h: float = thickness * 0.5
		for v: Vector3 in [Vector3(a.x, a.y, -h), Vector3(b.x, b.y, -h), Vector3(b.x, b.y, h), Vector3(a.x, a.y, -h), Vector3(b.x, b.y, h), Vector3(a.x, a.y, h)]:
			st.set_color(edge)
			st.set_normal(nrm)
			st.add_vertex(v)


## 프라이팬 (지름 26cm) · 그릴팬 (바닥에 굵은 줄 홈). 손잡이는 -X 쪽.
static func _pan(st: SurfaceTool, ridges: bool) -> void:
	var r: float = 0.13
	var inside: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.006), Vector2(r - 0.02, 0.006), Vector2(r - 0.008, 0.012), Vector2(r - 0.002, 0.035), Vector2(r + 0.004, 0.045)])
	var outside: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(r - 0.016, 0.0), Vector2(r - 0.004, 0.006), Vector2(r + 0.006, 0.035), Vector2(r + 0.01, 0.045)])
	ClayMesh.add_lathe(st, outside, 64, Transform3D(), BLACK_PAN.darkened(0.2))
	# 안쪽은 아래에서 위로 바라보는 면이라 반대로 돌린다 (안을 향한다).
	var inv: PackedVector2Array = inside.duplicate()
	inv.reverse()
	ClayMesh.add_lathe(st, inv, 64, Transform3D(), BLACK_PAN)
	ClayMesh.add_torus(st, Vector3(0.0, 0.045, 0.0), r + 0.007, 0.0035, STEEL_DARK, 64, 6)
	if ridges:
		for k: int in 9:
			var z: float = -0.096 + 0.024 * float(k)
			var half: float = sqrt(maxf(0.0, (r - 0.025) * (r - 0.025) - z * z))
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.009, z), Vector3(half * 2.0, 0.006, 0.006), 0.5, BLACK_PAN.lightened(0.08), Basis(), 12, 4)
	ClayMesh.add_rod(st, Vector3(-r - 0.005, 0.04, 0.0), Vector3(-r - 0.04, 0.05, 0.0), 0.009, 0.009, STEEL_DARK, 12)
	ClayMesh.add_rounded_box(st, Vector3(-r - 0.12, 0.058, 0.0), Vector3(0.17, 0.022, 0.03), 0.4, HANDLE, Basis(Vector3.BACK, -0.08), 24, 8)
	ClayMesh.add_torus(st, Vector3(-r - 0.195, 0.064, 0.0), 0.008, 0.003, STEEL_DARK, 16, 6, Basis(Vector3.RIGHT, PI * 0.5))


## 냄비 (지름 24cm, 높이 12cm) 양 손잡이.
static func _pot(st: SurfaceTool) -> void:
	var r: float = 0.12
	var h: float = 0.12
	var outer: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(r - 0.01, 0.0), Vector2(r, 0.01), Vector2(r, h - 0.006), Vector2(r + 0.004, h)])
	ClayMesh.add_lathe(st, outer, 64, Transform3D(), ClayMesh.vertical_gradient(STEEL_DARK, STEEL, 1.0))
	var inner: PackedVector2Array = PackedVector2Array([Vector2(r - 0.003, h), Vector2(r - 0.006, 0.01), Vector2(r - 0.016, 0.004), Vector2(0.0, 0.004)])
	ClayMesh.add_lathe(st, inner, 64, Transform3D(), STEEL_DARK.lightened(0.15))
	ClayMesh.add_torus(st, Vector3(0.0, h, 0.0), r + 0.002, 0.004, STEEL, 64, 6)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_torus(st, Vector3(side * (r + 0.022), h - 0.025, 0.0), 0.02, 0.006, STEEL_DARK, 20, 6, Basis(Vector3.BACK, side * 0.25))


static func _lid(st: SurfaceTool, r: float) -> void:
	var dome: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = PI * 0.5 * (1.0 - float(i) / 9.0)
		dome.append(Vector2(r * cos(a), 0.025 * sin(a)))
	dome.reverse()
	dome.insert(0, Vector2(r + 0.003, 0.0))
	ClayMesh.add_lathe(st, dome, 64, Transform3D(), STEEL.lightened(0.05))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.032, 0.0), Vector3(0.02, 0.012, 0.02), HANDLE, 20, 10)
	ClayMesh.add_rod(st, Vector3(0.0, 0.022, 0.0), Vector3(0.0, 0.03, 0.0), 0.006, 0.006, STEEL_DARK, 10)


## 웍 (지름 32cm, 둥근 바닥) + 긴 손잡이 (-X).
static func _wok(st: SurfaceTool) -> void:
	var r: float = 0.16
	var shell: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var t: float = float(i) / 12.0
		shell.append(Vector2(r * t, 0.085 * t * t))
	ClayMesh.add_lathe(st, shell, 64, Transform3D(), Color("#3A3B40"))
	var inner: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var t: float = 1.0 - float(i) / 12.0
		inner.append(Vector2((r - 0.004) * t, 0.004 + 0.085 * t * t))
	ClayMesh.add_lathe(st, inner, 64, Transform3D(), Color("#4A4B52"))
	ClayMesh.add_torus(st, Vector3(0.0, 0.087, 0.0), r, 0.004, STEEL_DARK, 64, 6)
	ClayMesh.add_rod(st, Vector3(-r + 0.01, 0.085, 0.0), Vector3(-r - 0.05, 0.1, 0.0), 0.008, 0.008, STEEL_DARK, 12)
	ClayMesh.add_capsule(st, Vector3(-r - 0.05, 0.1, 0.0), Vector3(-r - 0.24, 0.12, 0.0), 0.014, WOOD_DARK, 16, 4)


## 튀김 냄비 (깊은 냄비, 기름은 KitchenCounter 가 따로 그린다).
static func _fryer(st: SurfaceTool) -> void:
	var r: float = 0.12
	var h: float = 0.15
	var outer: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(r - 0.01, 0.0), Vector2(r, 0.01), Vector2(r, h)])
	ClayMesh.add_lathe(st, outer, 64, Transform3D(), ClayMesh.vertical_gradient(Color("#3C3E44"), Color("#5A5C64"), 1.0))
	var inner: PackedVector2Array = PackedVector2Array([Vector2(r - 0.004, h), Vector2(r - 0.004, 0.006), Vector2(0.0, 0.006)])
	ClayMesh.add_lathe(st, inner, 64, Transform3D(), Color("#2A2C30"))
	ClayMesh.add_torus(st, Vector3(0.0, h, 0.0), r, 0.005, STEEL_DARK, 64, 6)


## 튀김 바구니: 철망 (가로 고리 + 세로 살) + 긴 손잡이 (-X).
static func _basket(st: SurfaceTool) -> void:
	var r: float = 0.09
	var h: float = 0.08
	for k: int in 6:
		var y: float = h * float(k) / 5.0
		ClayMesh.add_torus(st, Vector3(0.0, y, 0.0), r * (0.92 + 0.08 * float(k) / 5.0), 0.0016, STEEL, 48, 4)
	for k: int in 20:
		var a: float = TAU * float(k) / 20.0
		ClayMesh.add_rod(st, Vector3(cos(a) * r * 0.92, 0.0, sin(a) * r * 0.92), Vector3(cos(a) * r, h, sin(a) * r), 0.0014, 0.0014, STEEL, 4)
	for k: int in 7:
		var x: float = -r * 0.9 + r * 1.8 * float(k) / 6.0
		var half: float = sqrt(maxf(0.0, r * r * 0.85 - x * x))
		ClayMesh.add_rod(st, Vector3(x, 0.0, -half), Vector3(x, 0.0, half), 0.0014, 0.0014, STEEL, 4)
	ClayMesh.add_rod(st, Vector3(-r, h, 0.0), Vector3(-r - 0.16, h + 0.06, 0.0), 0.005, 0.005, STEEL_DARK, 10)
	ClayMesh.add_capsule(st, Vector3(-r - 0.16, h + 0.06, 0.0), Vector3(-r - 0.26, h + 0.1, 0.0), 0.012, HANDLE, 16, 4)


## 대나무 찜기 (지름 24cm): 테두리 · 바닥 살.
static func _steamer(st: SurfaceTool) -> void:
	var r: float = 0.12
	var h: float = 0.07
	var ring: PackedVector2Array = PackedVector2Array([Vector2(r - 0.008, 0.0), Vector2(r, 0.0), Vector2(r, h), Vector2(r - 0.008, h), Vector2(r - 0.008, 0.0)])
	ClayMesh.add_lathe(st, ring, 64, Transform3D(), ClayMesh.vertical_gradient(BAMBOO_DARK, BAMBOO, 1.0))
	for y: float in [0.008, h - 0.008]:
		ClayMesh.add_torus(st, Vector3(0.0, y, 0.0), r + 0.002, 0.004, BAMBOO_DARK, 64, 6)
	for k: int in 15:
		var x: float = -r + 0.012 + (2.0 * r - 0.024) * float(k) / 14.0
		var half: float = sqrt(maxf(0.0, (r - 0.008) * (r - 0.008) - x * x))
		ClayMesh.add_rounded_box(st, Vector3(x, 0.008, 0.0), Vector3(0.009, 0.004, half * 2.0), 0.4, BAMBOO.lightened(0.05 * float(k % 2)), Basis(), 8, 3)


static func _steamer_lid(st: SurfaceTool) -> void:
	var r: float = 0.123
	var dome: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = PI * 0.5 * float(i) / 9.0
		dome.append(Vector2(r * cos(a), 0.035 * sin(a)))
	ClayMesh.add_lathe(st, dome, 64, Transform3D(), BAMBOO)
	for k: int in 8:
		var a: float = TAU * float(k) / 8.0
		ClayMesh.add_rod(st, Vector3(cos(a) * 0.02, 0.034, sin(a) * 0.02), Vector3(cos(a) * r * 0.98, 0.002, sin(a) * r * 0.98), 0.0025, 0.0025, BAMBOO_DARK, 6)
	ClayMesh.add_torus(st, Vector3(0.0, 0.0, 0.0), r, 0.005, BAMBOO_DARK, 64, 6)


## 접시 (지름 24cm, 옅은 테두리 줄).
static func _plate(st: SurfaceTool) -> void:
	var r: float = 0.12
	var p: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.004), Vector2(r * 0.62, 0.004), Vector2(r * 0.7, 0.008), Vector2(r * 0.95, 0.017), Vector2(r, 0.016), Vector2(r * 0.96, 0.012), Vector2(r * 0.6, 0.0), Vector2(0.0, 0.0)])
	ClayMesh.add_lathe(st, p, 64, Transform3D(), CERAMIC)
	ClayMesh.add_torus(st, Vector3(0.0, 0.0165, 0.0), r * 0.965, 0.0015, Color("#5C88C8"), 64, 4)


## 무침 그릇 (스테인리스, 지름 22cm).
static func _bowl(st: SurfaceTool) -> void:
	var r: float = 0.11
	var outer: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var a: float = -PI * 0.5 + PI * 0.5 * float(i) / 12.0
		outer.append(Vector2(r * cos(a) * 1.0, 0.07 + 0.07 * sin(a)))
	outer[0] = Vector2(0.0, 0.0)
	ClayMesh.add_lathe(st, outer, 64, Transform3D(), ClayMesh.vertical_gradient(STEEL_DARK, STEEL, 1.0))
	var inner: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var a: float = -PI * 0.5 * float(i) / 12.0
		inner.append(Vector2((r - 0.003) * cos(a), 0.07 + 0.067 * sin(a)))
	inner[inner.size() - 1] = Vector2(0.0, 0.003)
	ClayMesh.add_lathe(st, inner, 64, Transform3D(), STEEL.lightened(0.1))
	ClayMesh.add_torus(st, Vector3(0.0, 0.07, 0.0), r, 0.003, STEEL, 64, 6)


## 소금통: 유리병(희게 보이는 소금) + 구멍 뚫린 쇠뚜껑.
static func _shaker(st: SurfaceTool) -> void:
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.022, 0.02, 0.0, 0.07, 0.006, 3), 32, Transform3D(), Color("#F4F6F8"))
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.021, 0.021, 0.068, 0.088, 0.008, 3), 32, Transform3D(), STEEL)
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0
		ClayMesh.add_ellipsoid(st, Vector3(cos(a) * 0.009, 0.0885, sin(a) * 0.009), Vector3(0.0022, 0.0006, 0.0022), Color("#40444C"), 8, 4)


## 국자 (-X 쪽 손잡이).
static func _ladle(st: SurfaceTool) -> void:
	var cup: PackedVector2Array = PackedVector2Array()
	for i: int in 9:
		var a: float = -PI * 0.5 + PI * 0.5 * float(i) / 8.0
		cup.append(Vector2(0.04 * cos(a), 0.035 + 0.035 * sin(a)))
	cup[0] = Vector2(0.0, 0.0)
	ClayMesh.add_lathe(st, cup, 32, Transform3D(), STEEL)
	ClayMesh.add_capsule(st, Vector3(-0.04, 0.035, 0.0), Vector3(-0.27, 0.14, 0.0), 0.006, STEEL, 12, 3)


## 뒤집개 (넓은 날 +X, 손잡이 -X).
static func _turner(st: SurfaceTool) -> void:
	ClayMesh.add_rounded_box(st, Vector3(0.05, 0.002, 0.0), Vector3(0.1, 0.003, 0.08), 0.3, STEEL, Basis(), 20, 4)
	for k: int in 4:
		ClayMesh.add_rounded_box(st, Vector3(0.04 + 0.016 * float(k), 0.0036, 0.0), Vector3(0.006, 0.001, 0.05), 0.4, STEEL_DARK, Basis(), 8, 2)
	ClayMesh.add_capsule(st, Vector3(0.0, 0.004, 0.0), Vector3(-0.16, 0.03, 0.0), 0.009, HANDLE, 14, 4)


## 화구: 무쇠 받침살 + 버너 머리 (불꽃은 KitchenCounter 가 따로 그린다).
static func _burner(st: SurfaceTool) -> void:
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.002, 0.0), Vector3(0.36, 0.01, 0.36), 0.15, Color("#2E3036"), Basis(), 24, 6)
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.05, 0.045, 0.0, 0.018, 0.006, 2), 40, Transform3D(), Color("#3A3C42"))
	ClayMesh.add_torus(st, Vector3(0.0, 0.016, 0.0), 0.045, 0.004, Color("#1E2024"), 40, 6)
	for k: int in 4:
		var a: float = TAU * float(k) / 4.0 + PI * 0.25
		ClayMesh.add_rounded_box(st, Vector3(cos(a) * 0.1, 0.012, sin(a) * 0.1), Vector3(0.12, 0.012, 0.014), 0.3, Color("#1A1B1E"), Basis(Vector3.UP, -a), 16, 4)
	ClayMesh.add_torus(st, Vector3(0.0, 0.016, 0.0), 0.16, 0.006, Color("#1A1B1E"), 48, 6)


## 물 주전자 (찌기에 물을 붓는다): 몸 · 주둥이 (+X) · 손잡이 (-X).
static func _pitcher(st: SurfaceTool) -> void:
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.05, 0.042, 0.0, 0.13, 0.012, 3), 40, Transform3D(), STEEL)
	ClayMesh.add_rod(st, Vector3(0.035, 0.1, 0.0), Vector3(0.085, 0.14, 0.0), 0.012, 0.006, STEEL, 12)
	ClayMesh.add_torus(st, Vector3(-0.055, 0.075, 0.0), 0.035, 0.007, HANDLE, 24, 6, Basis(Vector3.RIGHT, PI * 0.5))


## 접어 둔 행주 (장식).
static func _towel(st: SurfaceTool) -> void:
	var check: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var c: int = int(floor(p.x * 60.0)) + int(floor(p.z * 60.0))
		return Color("#F2EEE4") if c % 2 == 0 else Color("#D8645A")
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.008, 0.0), Vector3(0.2, 0.016, 0.12), 0.35, check, Basis(), 24, 6)


## 양념 병 (장식, 뚜껑은 빨강).
static func _jar(st: SurfaceTool) -> void:
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.03, 0.03, 0.0, 0.08, 0.008, 3), 32, Transform3D(), Color("#E8D49A"))
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.032, 0.032, 0.078, 0.098, 0.006, 3), 32, Transform3D(), Color("#C8463E"))
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.04, 0.03), Vector3(0.04, 0.03, 0.004), 0.3, Color("#FFFFFF"), Basis(), 10, 4)


# ---- 재료 (날것, 실제 크기). 익힘은 KitchenCounter 가 머티리얼 색으로 입힌다. ----

## 재료 한 덩이 (도마 · 팬 · 꼬치 위의 통째 모습). 물고기는 FishModel 을 줄여 옆으로 눕힌다 (KitchenCounter).
static func food(id: String) -> ArrayMesh:
	var key: String = "food|" + id
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = id.hash()
	match FoodArt.kind_of(id):
		"steak":
			_steak(st, rng)
		"belly":
			_belly(st)
		"chicken":
			_chicken(st, rng)
		"mushroom":
			_mushroom(st)
		"clam":
			_clam(st, Color("#C9B8A0") if id != "corbicula" else Color("#5A4A32"), 0.045 if id != "corbicula" else 0.03)
		"razor":
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.012, 0.0), Vector3(0.13, 0.024, 0.026), 0.6, ClayMesh.vertical_gradient(Color("#B8A070"), Color("#E0CC98"), 1.0), Basis(), 24, 8)
		"scallop":
			_clam(st, Color("#4A4038"), 0.09)
		"egg":
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.024, 0.0), Vector3(0.022, 0.024, 0.028), Color("#F2DDBA"), 24, 14)
		"potato":
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.03, 0.0), Vector3(0.045, 0.03, 0.035), Color("#C8A060"), 24, 14, Basis(), ClayMesh.blob_wobble(rng.randi(), 0.08, 3))
			for k: int in 4:
				var a: float = rng.randf() * TAU
				ClayMesh.add_ellipsoid(st, Vector3(cos(a) * 0.035, 0.035 + rng.randf() * 0.015, sin(a) * 0.028), Vector3(0.003, 0.002, 0.003), Color("#8A6A3A"), 8, 4)
		"tofu":
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.02, 0.0), Vector3(0.1, 0.04, 0.07), 0.15, Color("#F5F2E8"), Basis(), 24, 8)
		"jeon":
			ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.07, 0.068, 0.0, 0.012, 0.005, 2), 48, Transform3D(Basis(), Vector3.ZERO), Color("#F0D58E"))
			for k: int in 9:
				var a: float = rng.randf() * TAU
				var d: float = rng.randf() * 0.055
				ClayMesh.add_ellipsoid(st, Vector3(cos(a) * d, 0.012, sin(a) * d), Vector3(0.008, 0.002, 0.004), Color("#5E9A48") if k % 2 == 0 else Color("#D9342B"), 8, 4, Basis(Vector3.UP, rng.randf() * PI))
		_:
			_veg(st, id, rng)
	var m: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = m
	return m


## 소고기 등심: 두툼한 덩이 + 마블링 (흰 결이 붉은 살 사이로) + 가장자리 지방.
static func _steak(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var seeds: Array[Vector3] = []
	for k: int in 14:
		seeds.append(Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.04, 0.04)))
	var marble: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var m: float = 0.0
		for s: Vector3 in seeds:
			var d: float = Vector2(p.x - s.x, (p.z - s.z) * 1.7).length()
			m = maxf(m, clampf(1.0 - d / 0.012, 0.0, 1.0))
		var lean: Color = Color("#B8323A").lerp(Color("#9A2630"), 0.5 + 0.5 * sin(p.x * 90.0))
		var fat_edge: float = clampf((p.z + 0.035) / -0.01, 0.0, 1.0)
		return lean.lerp(Color("#F2E4DA"), maxf(m * 0.75, fat_edge))
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.013, 0.0), Vector3(0.125, 0.026, 0.085), 0.4, marble, Basis(), 40, 12)


## 삼겹살: 살과 비계가 층층이 (옆에서 보면 줄무늬, 위는 껍질 쪽 비계).
static func _belly(st: SurfaceTool) -> void:
	var layers: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var band: float = 0.5 + 0.5 * sin(p.y * 520.0)
		return Color("#E07880").lerp(Color("#F6E6DA"), smoothstep(0.35, 0.7, band))
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.015, 0.0), Vector3(0.15, 0.03, 0.065), 0.2, layers, Basis(), 40, 12)


## 닭 다리살: 울퉁불퉁한 덩이 + 오돌토돌한 껍질.
static func _chicken(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var skin: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var bump: float = 0.5 + 0.5 * sin(p.x * 260.0) * sin(p.z * 240.0)
		return Color("#F2C8B0").darkened(0.06 * bump)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.02, 0.0), Vector3(0.06, 0.02, 0.045), skin, 32, 12, Basis(), ClayMesh.blob_wobble(rng.randi(), 0.12, 4))


## 표고: 갓(별 모양 칼집) + 짧은 기둥.
static func _mushroom(st: SurfaceTool) -> void:
	var cap: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var a: float = atan2(p.z, p.x)
		var cut: float = clampf(1.0 - absf(sin(a * 3.0)) * 12.0, 0.0, 1.0) * clampf(1.0 - Vector2(p.x, p.z).length() / 0.025, 0.0, 1.0)
		return Color("#7A4E30").lerp(Color("#F2E2C8"), cut)
	var dome: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = PI * 0.5 * float(i) / 9.0
		dome.append(Vector2(0.032 * cos(a), 0.012 + 0.016 * sin(a)))
	dome.insert(0, Vector2(0.028, 0.01))
	ClayMesh.add_lathe(st, dome, 40, Transform3D(), cap)
	ClayMesh.add_rod(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.012, 0.0), 0.009, 0.011, Color("#E8D8BE"), 16)


## 조개: 결이 있는 껍데기 두 장 (위에서 보면 부채꼴).
static func _clam(st: SurfaceTool, color: Color, size: float) -> void:
	var ridges: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var a: float = atan2(p.z, p.x + size * 0.5)
		var r: float = 0.5 + 0.5 * sin(a * 28.0)
		var ring: float = 0.5 + 0.5 * sin(Vector2(p.x + size * 0.5, p.z).length() * 260.0)
		return color.darkened(0.12 * r + 0.06 * ring)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, size * 0.18, 0.0), Vector3(size * 0.5, size * 0.18, size * 0.42), ridges, 32, 12, Basis(), func(a: float, _t: float) -> float: return 1.0 - 0.18 * maxf(0.0, cos(a + PI)))


## 채소 · 양념 (무 · 대파 · 고추 · 마늘 · 양파 · 레몬 · 나물 · 쌀 · 밀가루 반죽 …).
static func _veg(st: SurfaceTool, id: String, rng: RandomNumberGenerator) -> void:
	match id:
		"radish":
			ClayMesh.add_capsule(st, Vector3(-0.09, 0.03, 0.0), Vector3(0.08, 0.028, 0.0), 0.03, ClayMesh.vertical_gradient(Color("#EDEBE0"), Color("#F8F7F0"), 1.0), 32, 6)
			ClayMesh.add_ellipsoid(st, Vector3(0.11, 0.03, 0.0), Vector3(0.03, 0.022, 0.026), Color("#9ACB78"), 24, 10)
			for k: int in 5:
				ClayMesh.add_ellipsoid(st, Vector3(0.15 + 0.01 * float(k % 2), 0.03, -0.03 + 0.015 * float(k)), Vector3(0.04, 0.004, 0.01), Color("#5E9A48"), 16, 6, Basis(Vector3.UP, -0.3 + 0.15 * float(k)))
		"scallion":
			ClayMesh.add_capsule(st, Vector3(-0.15, 0.008, 0.0), Vector3(0.0, 0.008, 0.0), 0.008, Color("#F2F4EA"), 16, 3)
			ClayMesh.add_capsule(st, Vector3(0.0, 0.008, 0.0), Vector3(0.14, 0.008, 0.012), 0.0075, Color("#5EA040"), 16, 3)
			ClayMesh.add_capsule(st, Vector3(0.0, 0.008, 0.0), Vector3(0.13, 0.008, -0.01), 0.006, Color("#6DB04C"), 16, 3)
			for k: int in 4:
				ClayMesh.add_rod(st, Vector3(-0.15, 0.006, 0.0), Vector3(-0.17, 0.004, -0.006 + 0.004 * float(k)), 0.0012, 0.0008, Color("#E8E2CC"), 4)
		"chili":
			var pts: PackedVector3Array = PackedVector3Array()
			for k: int in 9:
				var t: float = float(k) / 8.0
				pts.append(Vector3(-0.06 + 0.12 * t, 0.011, 0.015 * sin(t * PI)))
			for k: int in pts.size() - 1:
				ClayMesh.add_rod(st, pts[k], pts[k + 1], lerpf(0.011, 0.0025, float(k) / 8.0), lerpf(0.011, 0.0025, float(k + 1) / 8.0), Color("#D9342B"), 16)
			ClayMesh.add_rod(st, pts[0], pts[0] + Vector3(-0.018, 0.004, 0.0), 0.004, 0.003, Color("#3A7A2A"), 10)
		"garlic":
			for k: int in 5:
				var a: float = TAU * float(k) / 5.0
				ClayMesh.add_ellipsoid(st, Vector3(cos(a) * 0.012, 0.018, sin(a) * 0.012), Vector3(0.012, 0.018, 0.01), Color("#F1EBDD"), 16, 8, Basis(Vector3.UP, -a))
			ClayMesh.add_rod(st, Vector3(0.0, 0.03, 0.0), Vector3(0.0, 0.045, 0.0), 0.004, 0.002, Color("#C8B898"), 8)
		"onion":
			var peel: Callable = func(p: Vector3, _n: Vector3) -> Color:
				var line: float = 0.5 + 0.5 * sin(atan2(p.z, p.x) * 14.0)
				return Color("#C88A4A").darkened(0.1 * line)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.035, 0.0), Vector3(0.04, 0.035, 0.04), peel, 32, 14, Basis(), func(_a: float, t: float) -> float: return 1.0 - 0.25 * pow(t, 6.0))
			ClayMesh.add_rod(st, Vector3(0.0, 0.065, 0.0), Vector3(0.004, 0.08, 0.0), 0.005, 0.002, Color("#A8743F"), 8)
		"lemon":
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.028, 0.0), Vector3(0.042, 0.028, 0.03), Color("#F5D63A"), 24, 12, Basis(), func(a: float, _t: float) -> float: return 1.0 + 0.12 * pow(absf(cos(a)), 8.0))
		"wild_greens", "mugwort", "wild_chive":
			var green: Color = Color("#5E9A48") if id == "wild_greens" else (Color("#8AA870") if id == "mugwort" else Color("#7FB06A"))
			for k: int in 9:
				var a: float = rng.randf() * TAU
				ClayMesh.add_ellipsoid(st, Vector3(cos(a) * 0.02, 0.006 + 0.003 * float(k), sin(a) * 0.02), Vector3(0.045, 0.003, 0.014), green.lightened(rng.randf_range(-0.1, 0.12)), 18, 6, Basis(Vector3.UP, a))
		"rice":
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.03, 0.0), Vector3(0.045, 0.035, 0.038), Color("#F4F0E4"), 28, 12, Basis(), ClayMesh.blob_wobble(5, 0.05, 6))
		"laver":
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.002, 0.0), Vector3(0.12, 0.003, 0.1), 0.2, Color("#24302A"), Basis(), 16, 3)
		"flour":
			# 반죽 덩이.
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.03, 0.0), Vector3(0.06, 0.032, 0.055), Color("#F6EEDC"), 32, 14, Basis(), ClayMesh.blob_wobble(3, 0.05, 3))
		_:
			var info: ItemInfo = GameData.item(id)
			var c: Color = info.color if info != null else Color("#E8D8B0")
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.025, 0.0), Vector3(0.04, 0.025, 0.035), c, 24, 12, Basis(), ClayMesh.blob_wobble(rng.randi(), 0.06, 3))


## 썰린 조각 하나 (도마 위 · 냄비 · 그릇 · 꼬치): 재료의 살빛 단면이 위로.
static func piece(id: String) -> ArrayMesh:
	var key: String = "piece|" + id
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	var base: Color = FoodArt.base_color(id)
	match FoodArt.kind_of(id):
		"fish":
			# 생선 토막: 흰 살 + 껍질 쪽 (은빛 · 몸 색).
			var skin: Color = GameData.fish[id].body_color if GameData.fish.has(id) else Color("#8A8F98")
			var cut: Callable = func(p: Vector3, _n: Vector3) -> Color:
				return base.lerp(skin, smoothstep(0.012, 0.022, p.z + 0.01)) if p.y > 0.004 else skin
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.009, 0.0), Vector3(0.028, 0.018, 0.036), 0.3, cut, Basis(), 16, 6)
		"steak", "belly", "chicken":
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.009, 0.0), Vector3(0.03, 0.018, 0.026), 0.35, base.lerp(Color("#F2E4DA"), 0.15), Basis(), 16, 6)
		"mushroom":
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.004, 0.0), Vector3(0.032, 0.008, 0.01), 0.4, Color("#E8D2B0"), Basis(), 12, 4)
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.0085, 0.0), Vector3(0.032, 0.002, 0.008), 0.4, Color("#7A4E30"), Basis(), 12, 3)
		_:
			match id:
				"radish", "potato":
					ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.026, 0.026, 0.0, 0.007, 0.002, 2), 28, Transform3D(), base.lightened(0.05))
				"scallion":
					ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.007, 0.007, 0.0, 0.006, 0.002, 2), 18, Transform3D(), Color("#7DB85A"))
				"chili":
					ClayMesh.add_torus(st, Vector3(0.0, 0.003, 0.0), 0.007, 0.0025, Color("#D9342B"), 18, 6)
				"onion":
					for k: int in 3:
						ClayMesh.add_torus(st, Vector3(0.0, 0.002, 0.0), 0.012 + 0.008 * float(k), 0.0018, Color("#F2E8D4"), 24, 4, Basis.from_scale(Vector3(1.0, 1.0, 0.6)))
				"garlic":
					ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.003, 0.0), Vector3(0.007, 0.003, 0.006), Color("#F6F0E2"), 12, 6)
				_:
					ClayMesh.add_rounded_box(st, Vector3(0.0, 0.007, 0.0), Vector3(0.026, 0.014, 0.022), 0.4, base, Basis(), 14, 6)
	var m: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = m
	return m
