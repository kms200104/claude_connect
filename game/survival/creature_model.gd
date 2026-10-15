class_name CreatureModel
extends RefCounted
## v0.28.3 크리처 모형 (그림만): 관절이 있는 썩어 가는 사람 몸 — 골반 · 척추(몸통) · 목 · 머리 · 턱 · 어깨 · 팔꿈치 · 허벅지 · 무릎.
## 부위마다 메시 하나 (CreatureField 가 관절을 돌려 절뚝이고 · 고개가 꺾이고 · 턱이 벌어지게 움직인다).
## 살은 정점 색 알파 0.3 (셰이더가 멍 · 곰팡이 얼룩 · 핏줄 · 땀구멍 무늬와 축축한 광택을 그린다), 상처 · 피는 0.4 (번들거리는 검붉은 살).
## 퀭한 눈구멍 안에 빛나는 눈 (어둠 속에서 먼저 보인다), 누런 이빨, 드러난 갈비뼈 · 척추 돌기 · 견갑골, 구멍 난 옷 · 늘어진 넝마,
## 긴 손가락 끝의 검은 손톱. 종류마다 실루엣이 다르다:
##   어슬렁이 — 구부정, 한쪽 다리를 절며 두 팔을 앞으로 · 듬성듬성 빠진 머리 · 찢긴 셔츠 사이 갈비뼈.
##   달리미 — 바싹 마른 몸 · 긴 팔 · 찢긴 빨간 후드 · 붉은 눈, 앞으로 고꾸라질 듯 달린다.
##   퉁퉁이 — 터질 듯 부푼 배 (핏줄 · 고름 물집) · 짧고 굵은 다리.
##   기어미 — 다리가 짓이겨져 뼈가 드러난 채 두 팔로 끌고 온다, 등뼈가 드러남.
##   비명이 — 창백하고 긴 목 · 얼굴을 덮은 긴 검은 머리칼 · 턱이 빠질 듯 벌어진다 · 흰 눈.
##   철갑이 — 거대한 몸에 녹슨 철판을 볼트로 박고 철근이 어깨를 꿰뚫었다 · 쇠사슬 · 주황 눈.
##   독침이 — 목에 부푼 초록 독주머니 (빛남) · 뺨에 뚫린 구멍 · 등의 빛나는 고름 물집.

const GLOW: Material = preload("res://assets/materials/lamp_glow.tres")

## 부위 메시와 치수 (종류마다 한 번 만들어 둔다).
class Parts:
	var kind: String = ""
	var hip_y: float = 0.92
	var hip_w: float = 0.1
	var torso_h: float = 0.56
	var shoulder_w: float = 0.2
	var neck_len: float = 0.1
	var upper_arm: float = 0.3
	var fore_arm: float = 0.28
	var thigh: float = 0.44
	var shin: float = 0.44
	var scale: float = 1.0
	var eye_color: Color = Color("#E8D86A")
	var meshes: Dictionary[String, ArrayMesh] = {}
	## 빛나는 부위 (눈 · 독주머니 · 물집) — 부위 이름 → 메시.
	var glows: Dictionary[String, ArrayMesh] = {}
	var glow_colors: Dictionary[String, Color] = {}


## 관절 노드 (CreatureField 가 돌린다).
class Rig:
	var root: Node3D
	var hips: Node3D
	var spine: Node3D
	var neck: Node3D
	var head: Node3D
	var jaw: Node3D
	var shoulder_l: Node3D
	var shoulder_r: Node3D
	var elbow_l: Node3D
	var elbow_r: Node3D
	var thigh_l: Node3D
	var thigh_r: Node3D
	var knee_l: Node3D
	var knee_r: Node3D
	## 독침이 독주머니 (숨쉬듯 부푼다), 없으면 null.
	var sac: Node3D
	var parts: Parts


static var _cache: Dictionary[String, Parts] = {}
static var _glow_materials: Dictionary[String, Material] = {}


# ---- 색 ----

## 살 (알파 0.3): 아래 · 그늘진 면일수록 어둡게, 위는 조금 밝게.
static func flesh(c: Color) -> Callable:
	return func(_p: Vector3, n: Vector3) -> Color:
		var k: float = clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
		var col: Color = c.darkened(0.38 * (1.0 - k)).lightened(0.06 * k)
		return Color(col.r, col.g, col.b, 0.3)


## 상처 · 피 (알파 0.4).
static func gore(c: Color = Color("#5A0C0C")) -> Callable:
	return func(p: Vector3, _n: Vector3) -> Color:
		var v: float = 0.5 + 0.5 * sin(p.x * 61.0 + p.y * 37.0) * sin(p.z * 53.0 - p.y * 29.0)
		var col: Color = c.darkened(0.35 * v)
		return Color(col.r, col.g, col.b, 0.4)


## 옷: 밑단일수록 때 · 군데군데 핏물 얼룩 (알파 1).
static func cloth(c: Color, blood: float = 0.5) -> Callable:
	return func(p: Vector3, n: Vector3) -> Color:
		var k: float = clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
		var col: Color = c.darkened(0.3 * (1.0 - k))
		var stain: float = sin(p.x * 13.0 + p.y * 7.0 + 1.3) * sin(p.z * 11.0 - p.y * 5.0 + 0.7) + sin(p.y * 17.0 + p.x * 3.0) * 0.4
		if stain > 1.0 - blood * 0.6:
			col = col.lerp(Color("#3A0A08"), clampf((stain - (1.0 - blood * 0.6)) * 2.5, 0.0, 0.85))
		var grime: float = 0.5 + 0.5 * sin(p.x * 23.0 - p.z * 19.0 + p.y * 9.0)
		col = col.lerp(Color("#2E261C"), grime * 0.22)
		return col


static func bone() -> Callable:
	return func(_p: Vector3, n: Vector3) -> Color:
		return Color("#B4A486").darkened(0.35 * (1.0 - clampf(n.y * 0.5 + 0.5, 0.0, 1.0)))


## 상처: 살 표면(center, 바깥 법선 n)에 납작하게 붙은 찢긴 자리 — 거무죽죽한 가장자리 살 · 검붉은 속 · 더 검은 가운데.
static func wound(st: SurfaceTool, center: Vector3, n: Vector3, size: Vector2, seed_v: int, skin_c: Color) -> void:
	var up: Vector3 = Vector3.UP if absf(n.normalized().dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var b: Basis = Basis.looking_at(n.normalized(), up)
	var nn: Vector3 = n.normalized()
	var ragged: Callable = func(seed_w: int, depth: float) -> Callable:
		var ph: float = float(seed_w) * 0.77
		return func(angle: float, _t: float) -> float:
			return 1.0 + depth * (0.55 * sin(angle * 3.0 + ph) + 0.3 * sin(angle * 7.0 - ph * 1.3) + 0.15 * sin(angle * 13.0 + ph * 2.1))
	ClayMesh.add_ellipsoid(st, center + nn * 0.002, Vector3(size.x * 1.18, size.y * 1.18, 0.006), flesh(skin_c.lerp(Color("#4A2A2C"), 0.3)), 28, 6, b, ragged.call(seed_v, 0.22))
	ClayMesh.add_ellipsoid(st, center + nn * 0.004, Vector3(size.x, size.y, 0.007), gore(Color("#4A0606")), 28, 6, b, ragged.call(seed_v + 5, 0.3))
	ClayMesh.add_ellipsoid(st, center + nn * 0.0055, Vector3(size.x * 0.5, size.y * 0.55, 0.006), gore(Color("#1C0202")), 20, 5, b, ragged.call(seed_v + 9, 0.35))


## 빛나는 머티리얼 (등불 셰이더): 낮에는 albedo (어두운 바탕), 밤 · 지하에는 c 로 빛난다.
static func glow_material(c: Color, albedo: Color = Color(-1, 0, 0)) -> Material:
	var key: String = c.to_html(false) + albedo.to_html(false)
	if not _glow_materials.has(key):
		var m: ShaderMaterial = (GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("albedo", c.lightened(0.3) if albedo.r < 0.0 else albedo)
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_energy", 3.2)
		_glow_materials[key] = m
	return _glow_materials[key]


# ---- 모양 ----

## a 에서 b 로 가는 근육진 팔다리 (가운데가 bulge 만큼 불룩, 끝은 둥글게 닫힌다).
static func limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, color: Variant, seg: int = 14, bulge: float = 0.12) -> void:
	var length: float = a.distance_to(b)
	var p: PackedVector2Array = PackedVector2Array()
	for i: int in 4:
		var t: float = -PI * 0.5 + PI * 0.5 * float(i) / 4.0
		p.append(Vector2(cos(t) * r0, r0 + sin(t) * r0))
	for i: int in 9:
		var u: float = float(i) / 8.0
		var r: float = lerpf(r0, r1, u) * (1.0 + bulge * sin(u * PI) * (1.0 - u * 0.5))
		p.append(Vector2(r, lerpf(r0, length - r1, u)))
	for i: int in 5:
		var t: float = PI * 0.5 * float(i) / 4.0
		p.append(Vector2(cos(t) * r1, length - r1 + sin(t) * r1))
	ClayMesh.add_lathe(st, p, seg, Transform3D(ClayMesh._basis_along(b - a), a), color)


## 손: 손목(0) 에서 아래(-Y)로 손바닥 · 앞(-Z)으로 굽은 긴 손가락 넷 · 엄지 · 검은 손톱.
static func hand(st: SurfaceTool, wrist: Vector3, size: float, skin: Callable, rng: RandomNumberGenerator, claw_len: float = 0.035) -> void:
	ClayMesh.add_ellipsoid(st, wrist + Vector3(0.0, -0.05, -0.005) * size, Vector3(0.045, 0.06, 0.022) * size, skin, 12, 8)
	var nail: Color = Color("#1E1814")
	for i: int in 4:
		var x: float = (-0.03 + 0.02 * float(i)) * size
		var base: Vector3 = wrist + Vector3(x, -0.1 * size, -0.008 * size)
		var curl: float = 0.35 + rng.randf() * 0.5
		var l1: float = (0.06 + (0.012 if i in [1, 2] else 0.0)) * size
		var k1: Vector3 = base + Vector3(x * 0.15, -l1, -l1 * 0.25)
		var k2: Vector3 = k1 + Vector3(0.0, -l1 * 0.8 * cos(curl), -l1 * 0.8 * sin(curl))
		limb(st, base, k1, 0.011 * size, 0.009 * size, skin, 8, 0.2)
		limb(st, k1, k2, 0.009 * size, 0.007 * size, skin, 8, 0.1)
		var tip: Vector3 = k2 + (k2 - k1).normalized() * claw_len * size
		ClayMesh.add_rod(st, k2, tip, 0.008 * size, 0.0, nail, 6)
	var tb: Vector3 = wrist + Vector3(-0.04, -0.05, -0.02) * size
	var tt: Vector3 = tb + Vector3(-0.02, -0.05, -0.035) * size
	limb(st, tb, tt, 0.012 * size, 0.009 * size, skin, 8, 0.2)
	ClayMesh.add_rod(st, tt, tt + (tt - tb).normalized() * claw_len * 0.8 * size, 0.008 * size, 0.0, nail, 6)


## 맨발 (발목 0 기준, 앞 -Z): 발등 · 발가락 다섯 · 검은 발톱.
static func foot(st: SurfaceTool, ankle: Vector3, size: float, skin: Callable) -> void:
	ClayMesh.add_ellipsoid(st, ankle + Vector3(0.0, -0.035, -0.06) * size, Vector3(0.05, 0.035, 0.11) * size, skin, 12, 8)
	ClayMesh.add_ellipsoid(st, ankle + Vector3(0.0, -0.03, 0.03) * size, Vector3(0.04, 0.04, 0.045) * size, skin, 10, 6)
	for i: int in 5:
		var x: float = (-0.034 + 0.017 * float(i)) * size
		var t: Vector3 = ankle + Vector3(x, -0.055, -0.17 + absf(float(i) - 1.0) * 0.008) * size
		ClayMesh.add_ellipsoid(st, t, Vector3(0.009, 0.012, 0.018) * size * (1.3 if i == 0 else 1.0), skin, 6, 4)
		ClayMesh.add_ellipsoid(st, t + Vector3(0.0, 0.004, -0.014) * size, Vector3(0.007, 0.004, 0.007) * size, Color("#2A2018"), 6, 3)


## 낡은 신발 (발목 0 기준).
static func shoe(st: SurfaceTool, ankle: Vector3, size: float, c: Color) -> void:
	ClayMesh.add_rounded_box(st, ankle + Vector3(0.0, -0.04, -0.06) * size, Vector3(0.11, 0.08, 0.27) * size, 0.35, cloth(c, 0.3))
	ClayMesh.add_rounded_box(st, ankle + Vector3(0.0, -0.075, -0.06) * size, Vector3(0.115, 0.025, 0.28) * size, 0.3, Color("#1A1612"))


## 늘어진 넝마 띠 (top 에서 아래로 len, 끝이 해져 가늘어진다).
static func rag(st: SurfaceTool, top: Vector3, length: float, width: float, color: Variant, rng: RandomNumberGenerator, out: Vector3) -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	var sway: Vector3 = Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.04, 0.04))
	for i: int in 5:
		var u: float = float(i) / 4.0
		pts.append(top + Vector3(0.0, -length * u, 0.0) + sway * u * u + out.normalized() * 0.01 * u)
	ClayMesh.add_strand(st, pts, width, 0.006, top - out.normalized(), color, func(u: float) -> float: return 1.0 - u * 0.7, 4)


# ---- 종류별 설정 ----

static func _params(kind: String) -> Dictionary:
	var d: Dictionary = {
		"skin": Color("#7A846E"), "shirt": Color("#8E887C"), "pants": Color("#3E4450"), "hair": Color("#2A2420"),
		"thin": 1.0, "belly": 0.0, "arm_len": 1.0, "leg_len": 1.0, "neck": 0.1, "eye": Color("#E8D86A"), "scale": 1.0,
		"hair_style": "patchy", "shirt_holes": 0.55, "shoes": 1, "seed": 101,
	}
	match kind:
		"runner":
			d.merge({"skin": Color("#848C90"), "shirt": Color("#6A2420"), "pants": Color("#2E3238"), "thin": 0.78, "arm_len": 1.18, "eye": Color("#FF3A2A"), "hair_style": "short", "shirt_holes": 0.62, "shoes": 2, "seed": 202}, true)
		"bloated":
			d.merge({"skin": Color("#8C8A6C"), "shirt": Color("#A8A08A"), "pants": Color("#4A4E40"), "thin": 1.15, "belly": 0.42, "leg_len": 0.9, "eye": Color("#D8E040"), "hair_style": "bald", "shirt_holes": 0.5, "shoes": 0, "seed": 303}, true)
		"crawler":
			d.merge({"skin": Color("#767A72"), "shirt": Color("#4E463E"), "pants": Color("#363A40"), "thin": 0.9, "eye": Color("#FF4A3A"), "hair_style": "patchy", "shirt_holes": 0.45, "shoes": 0, "seed": 404}, true)
		"screamer":
			d.merge({"skin": Color("#B4B6B0"), "shirt": Color("#A8A498"), "pants": Color("#B0AC9E"), "hair": Color("#0E0C0C"), "thin": 0.72, "arm_len": 1.15, "neck": 0.2, "eye": Color("#F0F6FF"), "hair_style": "long", "shirt_holes": 0.6, "shoes": 0, "seed": 505}, true)
		"brute":
			d.merge({"skin": Color("#646E5A"), "shirt": Color("#3E3E44"), "pants": Color("#33353A"), "thin": 1.45, "belly": 0.08, "arm_len": 1.08, "eye": Color("#FF8A2A"), "hair_style": "bald", "shirt_holes": 0.4, "shoes": 2, "scale": 1.22, "seed": 606}, true)
		"spitter":
			d.merge({"skin": Color("#6A8458"), "shirt": Color("#5A6A40"), "pants": Color("#3E4632"), "thin": 0.92, "eye": Color("#9AFF4A"), "hair_style": "patchy", "shirt_holes": 0.55, "shoes": 1, "seed": 707}, true)
	return d


static func parts(kind: String) -> Parts:
	if _cache.has(kind):
		return _cache[kind]
	var d: Dictionary = _params(kind)
	var p: Parts = Parts.new()
	p.kind = kind
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(d["seed"])
	var thin: float = d["thin"]
	var belly: float = d["belly"]
	var skin: Callable = flesh(d["skin"])
	var shirt: Color = d["shirt"]
	var pants: Color = d["pants"]
	p.eye_color = d["eye"]
	p.scale = d["scale"]
	p.thigh = 0.44 * float(d["leg_len"])
	p.shin = 0.42 * float(d["leg_len"])
	p.hip_y = p.thigh + p.shin + 0.06
	p.hip_w = 0.09 * thin
	p.torso_h = 0.56
	p.shoulder_w = 0.19 * thin
	p.neck_len = d["neck"]
	p.upper_arm = 0.3 * float(d["arm_len"])
	p.fore_arm = 0.27 * float(d["arm_len"])
	_build_pelvis(p, d, rng, skin, pants)
	_build_torso(p, d, rng, skin, shirt)
	_build_neck(p, d, rng, skin)
	_build_head(p, d, rng, skin)
	_build_arms(p, d, rng, skin, shirt)
	_build_legs(p, d, rng, skin, pants)
	_cache[kind] = p
	return p


static func _build_pelvis(p: Parts, d: Dictionary, rng: RandomNumberGenerator, skin: Callable, pants: Color) -> void:
	var st: SurfaceTool = ClayMesh.begin()
	var thin: float = d["thin"]
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.0, 0.0), Vector3(0.15 * thin + float(d["belly"]) * 0.2, 0.1, 0.11 * thin), cloth(pants, 0.6), 16, 10)
	# 허리띠 · 늘어진 천 조각.
	ClayMesh.add_torus(st, Vector3(0.0, 0.07, 0.0), 0.14 * thin + float(d["belly"]) * 0.2, 0.018, Color("#2A221C"), 16, 5, Basis.from_scale(Vector3(1.0, 1.0, 0.78)))
	for i: int in 4:
		var a: float = rng.randf() * TAU
		var at: Vector3 = Vector3(cos(a) * 0.14 * thin, -0.04, sin(a) * 0.1 * thin)
		rag(st, at, rng.randf_range(0.1, 0.22), 0.025, cloth(pants.darkened(0.15), 0.8), rng, at)
	if p.kind == "crawler":
		# 찢긴 허리에 드러난 등뼈 끝 · 핏물.
		ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.02, 0.1), Vector3(0.08, 0.05, 0.03), gore(), 10, 6)
	p.meshes["pelvis"] = ClayMesh.commit(st)


static func _build_torso(p: Parts, d: Dictionary, rng: RandomNumberGenerator, skin: Callable, shirt: Color) -> void:
	var st: SurfaceTool = ClayMesh.begin()
	var thin: float = d["thin"]
	var belly: float = d["belly"]
	var h: float = p.torso_h
	var lumps: Callable = ClayMesh.blob_wobble(int(d["seed"]), 0.05, 4)
	# 몸: 꺼진 배 · 앙상한 가슴통 · 어깨.
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.17, 0.005), Vector3(0.135, 0.18, 0.1) * Vector3(thin, 1.0, thin), skin, 20, 14, Basis(), lumps)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.37, 0.01), Vector3(0.18, 0.19, 0.125) * Vector3(thin, 1.0, thin), skin, 22, 14, Basis(), lumps)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, h - 0.04, 0.03), Vector3(0.11, 0.05, 0.07) * Vector3(thin, 1.0, thin), skin, 14, 8)
	limb(st, Vector3(-p.shoulder_w, h - 0.06, 0.02), Vector3(p.shoulder_w, h - 0.06, 0.02), 0.055 * thin, 0.055 * thin, skin, 12, 0.25)
	# 등: 척추 돌기 · 툭 튀어나온 견갑골 (위에서 내려다보면 가장 잘 보인다).
	for i: int in 8:
		var y: float = 0.06 + float(i) * 0.06
		var z: float = (0.1 if y < 0.26 else 0.125) * thin + 0.004
		ClayMesh.add_ellipsoid(st, Vector3(0.0, y, z), Vector3(0.02, 0.016, 0.018), skin, 8, 5)
	for s: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(s * 0.085 * thin, 0.42, 0.105 * thin), Vector3(0.06, 0.075, 0.025) * Vector3(thin, 1.0, 1.0), skin, 12, 8, Basis(Vector3.BACK, s * 0.25))
	var skin_c: Color = d["skin"]
	var chest: Vector3 = Vector3(0.18, 0.19, 0.125) * Vector3(thin, 1.0, thin)
	var on_chest: Callable = func(dir: Vector3) -> Array:
		var n: Vector3 = dir.normalized()
		return [Vector3(0.0, 0.37, 0.01) + n * chest, (n / chest).normalized()]
	# 앞: 살이 뜯겨 나간 가슴 구멍 안의 갈비뼈 (어슬렁이 · 달리미 · 비명이).
	if p.kind in ["shambler", "runner", "screamer"]:
		var hole: Array = on_chest.call(Vector3(-0.45, 0.0, -1.0))
		var hc: Vector3 = hole[0]
		var hn: Vector3 = hole[1]
		var hb: Basis = Basis.looking_at(hn, Vector3.UP)
		var cav: Callable = func(angle: float, _t: float) -> float:
			return 1.0 + 0.18 * sin(angle * 3.0 + 1.1) + 0.1 * sin(angle * 7.0 + 0.3) + 0.06 * sin(angle * 13.0)
		ClayMesh.add_ellipsoid(st, hc + hn * 0.002, Vector3(0.088, 0.105, 0.008), flesh(skin_c.lerp(Color("#4A2A2C"), 0.55)), 30, 6, hb, cav)
		ClayMesh.add_ellipsoid(st, hc + hn * 0.004, Vector3(0.07, 0.088, 0.008), gore(Color("#2A0404")), 30, 6, hb, cav)
		var rib_c: Callable = func(q: Vector3, n: Vector3) -> Color:
			var v: float = 0.5 + 0.5 * sin(q.x * 140.0 + q.y * 90.0)
			return Color("#9A8468").lerp(Color("#4A1010"), 0.25 + 0.35 * v).darkened(0.3 * (1.0 - clampf(n.y * 0.5 + 0.5, 0.0, 1.0)))
		for i: int in 4:
			var y: float = -0.062 + float(i) * 0.036 + rng.randf_range(-0.006, 0.006)
			var x0: float = rng.randf_range(-0.06, -0.045)
			var x1: float = rng.randf_range(0.02, 0.055) if i != 2 else -0.005
			var pts: Array[Vector3] = []
			for k: int in 5:
				var x: float = lerpf(x0, x1, float(k) / 4.0)
				pts.append(hc + hb * Vector3(x, y - x * 0.3, -0.011 - 0.007 * sin(float(k) / 4.0 * PI)))
			for k: int in 4:
				limb(st, pts[k], pts[k + 1], 0.0058, 0.005, rib_c, 6, 0.0)
		ClayMesh.add_ellipsoid(st, hc + hn * 0.006 + Vector3(0.0, -0.11, 0.0), Vector3(0.01, 0.06, 0.004), gore(Color("#3A0404")), 6, 4, hb)
	# 상처 몇 곳 (살 표면에 납작하게).
	var wounds: Array[Vector3] = [Vector3(0.7, -0.9, -0.8), Vector3(0.4, 0.6, 1.0), Vector3(-0.9, -0.3, 0.3)]
	for i: int in wounds.size():
		var w: Array = on_chest.call(wounds[i])
		wound(st, w[0], w[1], Vector2(0.03, 0.045) * rng.randf_range(0.8, 1.3), int(d["seed"]) + i * 7, skin_c)
	# 부푼 배: 늘어진 배 (아래로 처짐) · 비치는 검푸른 핏줄 · 고름 물집 · 터진 자리.
	if belly > 0.0:
		var bc: Vector3 = Vector3(0.0, 0.14, -0.06)
		var br: Vector3 = Vector3(0.2 + belly * 0.45, 0.22 + belly * 0.25, 0.14 + belly * 0.55)
		var belly_skin: Callable = func(q: Vector3, n: Vector3) -> Color:
			var k: float = clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
			var col: Color = skin_c.lerp(Color("#8A7A86"), 0.35).darkened(0.4 * (1.0 - k))
			var vein: float = absf(sin(q.x * 31.0 + sin(q.y * 17.0) * 2.0) * sin(q.y * 23.0 + q.z * 13.0))
			if vein < 0.08:
				col = col.lerp(Color("#2A3A3A"), 0.6)
			return Color(col.r, col.g, col.b, 0.3)
		ClayMesh.add_ellipsoid(st, bc, br, belly_skin, 30, 22, Basis(), func(angle: float, t: float) -> float:
			return 1.0 + 0.05 * sin(angle * 5.0 + t * 9.0) + 0.1 * maxf(0.0, 0.5 - t))
		for i: int in 6:
			var a: float = rng.randf_range(PI * 1.15, PI * 1.85)
			var y: float = rng.randf_range(-0.05, 0.3)
			var dir: Vector3 = Vector3(cos(a), (y - 0.14) * 2.0, sin(a)).normalized()
			var at: Vector3 = bc + dir * br * 0.985
			ClayMesh.add_ellipsoid(st, at, Vector3.ONE * rng.randf_range(0.014, 0.028), flesh(Color("#8E8A50")), 8, 6)
			ClayMesh.add_ellipsoid(st, at + dir * 0.012, Vector3.ONE * 0.006, Color("#C8B850"), 6, 4)
		# 배꼽 자리에서 터져 검은 피가 흐른다 · 갈라진 살.
		wound(st, bc + Vector3(0.05, -0.04, -br.z * 0.99), Vector3(0.1, -0.1, -1.0), Vector2(0.05, 0.07), 31, skin_c)
		wound(st, bc + Vector3(-0.12, 0.08, -br.z * 0.92), Vector3(-0.5, 0.2, -0.8), Vector2(0.025, 0.06), 33, skin_c)
	# 옷: 구멍 난 셔츠 껍질 · 밑단의 넝마.
	var holes: float = d["shirt_holes"]
	var seed_v: float = float(d["seed"]) * 0.13
	var keep: Callable = func(dir: Vector3) -> bool:
		# 왼쪽 가슴 (갈비뼈) 은 크게 찢겼다.
		if dir.z < -0.35 and dir.x < 0.2 and dir.x > -0.75 and dir.y > -0.05 and dir.y < 0.6:
			return false
		var n: float = sin(dir.x * 7.1 + seed_v) * sin(dir.y * 6.3 - seed_v * 0.7) + sin(dir.z * 8.7 + dir.x * 3.0 + seed_v) * 0.6
		if n > holes * 1.4:
			return false
		# 밑단이 들쭉날쭉.
		return dir.y > -0.62 + 0.12 * sin(atan2(dir.z, dir.x) * 7.0 + seed_v)
	var flare: Callable = func(dir: Vector3) -> float:
		return 1.0 + 0.04 * sin(dir.x * 11.0 + dir.y * 7.0)
	var sr: Vector3 = Vector3(0.205 * thin + belly * 0.4, 0.29, 0.145 * thin + belly * 0.45)
	ClayMesh.add_shell(st, Vector3(0.0, 0.29, 0.0), sr, cloth(shirt, 0.7), keep, flare, 28, 18)
	for i: int in 7:
		var a: float = rng.randf() * TAU
		var at: Vector3 = Vector3(cos(a) * sr.x, 0.29 - sr.y * 0.6, sin(a) * sr.z)
		rag(st, at, rng.randf_range(0.08, 0.2), 0.03, cloth(shirt.darkened(0.1), 0.9), rng, at)
	match p.kind:
		"runner":
			# 찢긴 후드 (등에 늘어진 모자).
			ClayMesh.add_shell(st, Vector3(0.0, h + 0.02, 0.1), Vector3(0.13, 0.09, 0.08), cloth(shirt, 0.6), func(dir: Vector3) -> bool: return dir.z > -0.2, func(_dir: Vector3) -> float: return 1.0, 16, 10)
		"brute":
			_brute_armor(st, p, rng)
		"spitter":
			# 등의 고름 물집 자리 (빛나는 쪽은 glows["pustules"]).
			var gs: SurfaceTool = ClayMesh.begin()
			for i: int in 7:
				var at: Vector3 = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.12, 0.48), 0.12 * thin + 0.02)
				ClayMesh.add_ellipsoid(st, at - Vector3(0.0, 0.0, 0.008), Vector3.ONE * 0.034, gore(Color("#4A3A10")), 8, 5)
				ClayMesh.add_ellipsoid(gs, at, Vector3.ONE * rng.randf_range(0.016, 0.028), Color.WHITE, 8, 6)
			p.glows["pustules"] = ClayMesh.commit(gs)
			p.glow_colors["pustules"] = Color("#8AE040")
	p.meshes["torso"] = ClayMesh.commit(st)


## 철갑이: 볼트로 박은 녹슨 철판 (가슴 · 배 · 어깨) · 어깨를 꿰뚫은 철근 · 감긴 쇠사슬.
static func _brute_armor(st: SurfaceTool, p: Parts, rng: RandomNumberGenerator) -> void:
	var rust: Callable = func(q: Vector3, n: Vector3) -> Color:
		var r: float = 0.5 + 0.5 * sin(q.x * 37.0 + q.y * 23.0) * sin(q.z * 31.0 - q.y * 17.0)
		return Color("#5E6066").lerp(Color("#6A3A1E"), r * 0.7).darkened(0.25 * (1.0 - clampf(n.y * 0.5 + 0.5, 0.0, 1.0)))
	var plates: Array[Array] = [[Vector3(-0.07, 0.38, -0.2), Vector3(0.2, 0.2, 0.03), -0.12], [Vector3(0.1, 0.18, -0.17), Vector3(0.16, 0.14, 0.03), 0.1], [Vector3(0.0, 0.4, 0.2), Vector3(0.3, 0.22, 0.03), 0.04]]
	for pl: Array in plates:
		var c: Vector3 = pl[0]
		var s: Vector3 = pl[1]
		var b: Basis = Basis(Vector3.BACK, float(pl[2]))
		ClayMesh.add_rounded_box(st, c, s, 0.25, rust, b, 12, 8)
		for k: int in 4:
			var off: Vector3 = Vector3((0.4 if k % 2 == 0 else -0.4) * s.x, (0.4 if k < 2 else -0.4) * s.y, -signf(c.z) * 0.018)
			ClayMesh.add_ellipsoid(st, c + b * off, Vector3(0.012, 0.012, 0.01), Color("#2E3034"), 6, 4)
		# 철판 둘레에 짓눌린 살 · 피.
		ClayMesh.add_ellipsoid(st, c + Vector3(0.0, -s.y * 0.5, 0.0), Vector3(s.x * 0.45, 0.02, 0.025), gore(), 10, 4)
	for sd: float in [-1.0, 1.0]:
		ClayMesh.add_rounded_box(st, Vector3(sd * p.shoulder_w * 1.05, p.torso_h - 0.02, 0.0), Vector3(0.2, 0.08, 0.24), 0.35, rust, Basis(Vector3.BACK, sd * 0.4), 12, 8)
	# 철근: 오른쪽 어깨를 앞뒤로 꿰뚫었다.
	ClayMesh.add_rod(st, Vector3(0.14, 0.62, -0.32), Vector3(0.1, 0.36, 0.36), 0.016, 0.016, Color("#5A3A26"), 8)
	ClayMesh.add_ellipsoid(st, Vector3(0.12, 0.5, -0.13), Vector3(0.04, 0.04, 0.02), gore(), 8, 5)
	# 쇠사슬: 몸통을 비스듬히 감는다.
	for i: int in 14:
		var a: float = lerpf(-PI * 0.9, PI * 0.9, float(i) / 13.0)
		var at: Vector3 = Vector3(sin(a) * 0.27, 0.12 + float(i) * 0.03, -cos(a) * 0.2)
		ClayMesh.add_torus(st, at, 0.022, 0.007, Color("#4A4C50"), 8, 4, Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5 * float(i % 2)))


static func _build_neck(p: Parts, d: Dictionary, rng: RandomNumberGenerator, skin: Callable) -> void:
	var st: SurfaceTool = ClayMesh.begin()
	var thin: float = d["thin"]
	limb(st, Vector3(0.0, -0.03, 0.0), Vector3(0.0, p.neck_len + 0.02, -0.01), 0.048 * thin, 0.042 * thin, skin, 14, 0.05)
	# 힘줄 두 가닥 · 물린 자국.
	for s: float in [-1.0, 1.0]:
		limb(st, Vector3(s * 0.025, 0.0, -0.035 * thin), Vector3(s * 0.012, p.neck_len, -0.03), 0.009, 0.007, skin, 6, 0.0)
	ClayMesh.add_ellipsoid(st, Vector3(0.035, p.neck_len * 0.5, -0.025), Vector3(0.03, 0.035, 0.022), gore(), 10, 6)
	if p.kind == "spitter":
		# 독주머니 (빛나는 껍질은 glows["sac"], 관절 rig.sac 이 숨쉬듯 부풀린다).
		var gs: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_ellipsoid(gs, Vector3(0.0, 0.0, 0.0), Vector3(0.085, 0.075, 0.08), Color.WHITE, 18, 12, Basis(), ClayMesh.blob_wobble(5, 0.12, 3))
		p.glows["sac"] = ClayMesh.commit(gs)
		p.glow_colors["sac"] = Color("#4A8A1A")
	p.meshes["neck"] = ClayMesh.commit(st)


## 머리 (목 관절 기준, 얼굴 -Z): 길쭉하고 앙상한 머리 · 튀어나온 눈썹뼈 · 광대뼈 · 꺼진 볼 · 거무죽죽한 눈두덩 안의 탁한 눈알 ·
## 떨어져 나간 코 (콧구멍만) · 입술이 없어 드러난 잇몸과 누런 이빨 · 한쪽 볼이 찢겨 어금니가 보인다 · 듬성듬성 빠진 머리.
## 턱(jaw)은 따로 (귀 밑에서 돈다). 눈동자는 빛나는 메시 (glows["eyes"], 밤 · 지하에 빛난다).
static func _build_head(p: Parts, d: Dictionary, rng: RandomNumberGenerator, skin: Callable) -> void:
	var st: SurfaceTool = ClayMesh.begin()
	var hc: Vector3 = Vector3(0.0, 0.13, 0.0)
	var big: float = 1.12 if p.kind == "brute" else 1.0
	var skin_c: Color = d["skin"]
	var dark: Callable = flesh(skin_c.lerp(Color("#3A2A30"), 0.55))
	var tooth: Callable = func(_q: Vector3, n: Vector3) -> Color:
		return Color("#B8A272").darkened(0.35 * (1.0 - clampf(n.y * 0.5 + 0.5, 0.0, 1.0)))
	# 머리뼈 (뒤로 길쭉) · 얼굴 (턱 위).
	ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, 0.035, 0.012) * big, Vector3(0.094, 0.108, 0.118) * big, skin, 24, 16, Basis(), ClayMesh.blob_wobble(int(d["seed"]) + 3, 0.035, 3))
	ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, -0.025, -0.045) * big, Vector3(0.07, 0.075, 0.07) * big, skin, 18, 12)
	# 눈썹뼈 · 광대뼈 · 꺼진 볼 (거무죽죽).
	ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, 0.046, -0.093) * big, Vector3(0.074, 0.015, 0.024) * big, skin, 16, 6)
	for s: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.057, -0.004, -0.074) * big, Vector3(0.02, 0.014, 0.026) * big, skin, 10, 6)
		ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.05, -0.04, -0.072) * big, Vector3(0.018, 0.024, 0.008) * big, dark, 10, 6, Basis(Vector3.UP, s * 0.5))
		# 눈두덩: 검붉게 꺼진 자리 · 그 안의 탁한 눈알 (핏발).
		ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.034, 0.02, -0.097) * big, Vector3(0.023, 0.017, 0.01) * big, Color("#1C0C0C"), 12, 6)
		ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.034, 0.012, -0.099) * big, Vector3(0.024, 0.01, 0.008) * big, dark, 10, 5)
		var eye: Callable = func(q: Vector3, _n: Vector3) -> Color:
			var v: float = sin(q.x * 900.0 + q.y * 400.0)
			return Color("#C8C0A0").lerp(Color("#8A3A2A"), 0.35 if v > 0.85 else 0.0)
		ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.034, 0.02, -0.101) * big, Vector3(0.013, 0.011, 0.009) * big, eye, 10, 8)
		# 귀 (왼쪽은 뜯겨 나갔다).
		if s < 0.0:
			ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.096, 0.0, 0.01) * big, Vector3(0.011, 0.028, 0.02) * big, skin, 8, 6)
		else:
			wound(st, hc + Vector3(0.094, 0.0, 0.01) * big, Vector3(1.0, 0.0, 0.0), Vector2(0.014, 0.02) * big, 41, skin_c)
	# 코: 떨어져 나가 콧대 조금 · 검은 콧구멍 둘.
	ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, 0.004, -0.108) * big, Vector3(0.009, 0.02, 0.01) * big, skin, 8, 6)
	ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, -0.016, -0.111) * big, Vector3(0.018, 0.012, 0.006) * big, flesh(Color("#4A2626")), 10, 4)
	for s: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, hc + Vector3(s * 0.007, -0.018, -0.116) * big, Vector3(0.005, 0.009, 0.004) * big, Color("#0A0404"), 6, 4, Basis(Vector3.BACK, s * 0.35))
	# 입: 입술 없이 드러난 잇몸 · 누런 윗니 (들쭉날쭉, 하나 빠짐).
	ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, -0.046, -0.098) * big, Vector3(0.043, 0.011, 0.014) * big, gore(Color("#5A1A1A")), 14, 6)
	for i: int in 10:
		if i == 6:
			continue
		var a: float = lerpf(-1.0, 1.0, float(i) / 9.0)
		var at: Vector3 = hc + Vector3(sin(a) * 0.04, -0.052, -0.072 - cos(a) * 0.036) * big
		var l: float = rng.randf_range(0.013, 0.022) * big
		ClayMesh.add_rod(st, at, at + Vector3(rng.randf_range(-0.002, 0.002), -l, -0.002), 0.0052 * big, 0.0032 * big, tooth, 6)
	# 오른쪽 볼이 찢겨 어금니가 보인다.
	wound(st, hc + Vector3(0.056, -0.05, -0.068) * big, Vector3(0.8, -0.1, -0.6), Vector2(0.018, 0.016) * big, 43, skin_c)
	for i: int in 2:
		var at: Vector3 = hc + Vector3(0.062, -0.05, -0.07 + float(i) * 0.012) * big
		ClayMesh.add_ellipsoid(st, at, Vector3(0.005, 0.007, 0.005) * big, tooth, 6, 4)
	# 머리 위 상처 (두피가 벗겨졌다) · 입가에서 흘러내린 피.
	wound(st, hc + Vector3(0.035, 0.14, 0.02) * big, Vector3(0.3, 1.0, 0.1), Vector2(0.035, 0.045) * big, 45, skin_c)
	ClayMesh.add_ellipsoid(st, hc + Vector3(-0.025, -0.075, -0.088) * big, Vector3(0.008, 0.026, 0.006) * big, gore(), 6, 4, Basis(Vector3.RIGHT, -0.5))
	_hair(st, p, d, rng, hc, big)
	if p.kind == "spitter":
		# 왼뺨에 뚫린 구멍 (안이 검다) · 흘러내린 초록 침.
		wound(st, hc + Vector3(-0.062, -0.035, -0.06), Vector3(-0.9, 0.0, -0.4), Vector2(0.016, 0.02), 47, skin_c)
		ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, -0.085, -0.1), Vector3(0.008, 0.03, 0.006), flesh(Color("#5A7A2A")), 6, 4)
	p.meshes["head"] = ClayMesh.commit(st)
	# 눈동자: 탁한 눈알 앞의 작은 점 (밤 · 지하에 빛난다).
	var es: SurfaceTool = ClayMesh.begin()
	for s: float in [-1.0, 1.0]:
		var r: float = 0.0062 if p.kind != "screamer" else 0.0085
		ClayMesh.add_ellipsoid(es, hc + Vector3(s * 0.034, 0.02, -0.1095) * big, Vector3(r, r, 0.0025) * big, Color.WHITE, 10, 4)
	p.glows["eyes"] = ClayMesh.commit(es)
	p.glow_colors["eyes"] = p.eye_color
	# 턱 (턱 관절 = 귀 밑 기준): 아래턱뼈 · 잇몸 · 아랫니 · 검은 혀 · 늘어진 살 조각.
	var js: SurfaceTool = ClayMesh.begin()
	var jc: Vector3 = Vector3(0.0, -0.088, -0.058) * big
	ClayMesh.add_ellipsoid(js, jc, Vector3(0.056, 0.022, 0.055) * big, skin, 16, 8)
	ClayMesh.add_ellipsoid(js, jc + Vector3(0.0, -0.012, -0.03) * big, Vector3(0.026, 0.016, 0.02) * big, skin, 10, 6)
	ClayMesh.add_ellipsoid(js, jc + Vector3(0.0, 0.012, -0.008) * big, Vector3(0.042, 0.009, 0.042) * big, gore(Color("#4A1414")), 12, 6)
	ClayMesh.add_ellipsoid(js, jc + Vector3(0.0, 0.016, 0.004) * big, Vector3(0.022, 0.008, 0.034) * big, Color("#2A1012"), 10, 6)
	for i: int in 9:
		var a: float = lerpf(-0.95, 0.95, float(i) / 8.0)
		var at: Vector3 = jc + Vector3(sin(a) * 0.037, 0.014, -cos(a) * 0.04 + 0.004) * big
		ClayMesh.add_rod(js, at, at + Vector3(0.0, rng.randf_range(0.011, 0.018) * big, -0.001), 0.0048 * big, 0.0026 * big, tooth, 6)
	ClayMesh.add_ellipsoid(js, jc + Vector3(-0.022, -0.02, -0.02) * big, Vector3(0.012, 0.028, 0.006) * big, gore(), 6, 4)
	p.meshes["jaw"] = ClayMesh.commit(js)


## 머리카락: patchy (빠져서 듬성듬성 · 기름진 덩어리 · 몇 가닥 늘어짐) · short · long (얼굴을 덮고 등까지) · bald.
static func _hair(st: SurfaceTool, p: Parts, d: Dictionary, rng: RandomNumberGenerator, hc: Vector3, big: float) -> void:
	var hair: Color = d["hair"]
	var style: String = d["hair_style"]
	match style:
		"patchy", "short":
			var n: int = 6 if style == "patchy" else 26
			for i: int in n:
				var a: float = rng.randf() * TAU
				var up: float = rng.randf_range(0.25, 1.0)
				var dir: Vector3 = Vector3(cos(a) * sqrt(1.0 - up * up), up, sin(a) * sqrt(1.0 - up * up))
				if dir.z < -0.55 and dir.y < 0.6:
					continue
				var at: Vector3 = hc + Vector3(0.0, 0.035, 0.012) * big + dir * Vector3(0.094, 0.108, 0.118) * big
				ClayMesh.add_ellipsoid(st, at, Vector3(0.024, 0.008, 0.026) * rng.randf_range(0.7, 1.3), hair.lightened(rng.randf() * 0.08), 8, 4, Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -acos(clampf(dir.y, -1.0, 1.0))))
			if style == "patchy":
				# 기름지게 엉겨 붙어 늘어진 몇 가닥 (정수리 뒤 · 옆에서).
				for i: int in 18:
					var a: float = rng.randf_range(-0.2, PI + 0.2)
					var up: float = rng.randf_range(0.35, 0.85)
					var dir: Vector3 = Vector3(cos(a) * sqrt(1.0 - up * up), up, sin(a) * sqrt(1.0 - up * up))
					var top: Vector3 = hc + Vector3(0.0, 0.035, 0.012) * big + dir * Vector3(0.096, 0.11, 0.12) * big
					var out: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
					var length: float = rng.randf_range(0.1, 0.24)
					var pts: PackedVector3Array = PackedVector3Array()
					for k: int in 6:
						var u: float = float(k) / 5.0
						pts.append(top + out * 0.03 * sin(minf(u * 2.0, 1.0) * PI * 0.5) + Vector3(0.0, -length * u, 0.0))
					ClayMesh.add_strand(st, pts, 0.006, 0.0025, hc, hair.lightened(rng.randf() * 0.1), func(u: float) -> float: return 1.0 - u * 0.75, 4)
		"long":
			# 축축하게 늘어진 긴 검은 머리칼: 정수리에서 얼굴 앞 · 어깨 · 등으로 (가운데가 조금 갈라져 눈 하나가 보인다).
			ClayMesh.add_ellipsoid(st, hc + Vector3(0.0, 0.06, 0.015), Vector3(0.112, 0.105, 0.13), hair, 18, 10)
			for i: int in 46:
				var a: float = TAU * float(i) / 46.0 + rng.randf() * 0.08
				var front: bool = sin(a) < -0.3
				if front and absf(cos(a)) < 0.12:
					continue
				var top: Vector3 = hc + Vector3(cos(a) * 0.08, 0.1, sin(a) * 0.09)
				var length: float = rng.randf_range(0.45, 0.62) if not front else rng.randf_range(0.28, 0.42)
				var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
				var pts: PackedVector3Array = PackedVector3Array()
				for k: int in 7:
					var u: float = float(k) / 6.0
					var bulge: float = (0.12 if not front else 0.135) * sin(minf(u * 2.2, 1.0) * PI * 0.5)
					pts.append(top + out * bulge + Vector3(rng.randf_range(-0.01, 0.01), -length * u, 0.0))
				ClayMesh.add_strand(st, pts, 0.012, 0.004, hc - out * 0.05, hair.lightened(rng.randf() * 0.06), func(u: float) -> float: return 1.0 - u * 0.6, 4)
		_:
			# 대머리: 핏줄 선 두피 · 꿰맨 자국.
			for i: int in 5:
				var at: Vector3 = hc + Vector3(-0.05 + 0.025 * float(i), 0.15, 0.0) * big
				ClayMesh.add_rod(st, at + Vector3(0.0, 0.0, -0.012), at + Vector3(0.0, 0.0, 0.012), 0.003, 0.003, Color("#1A1410"), 4)


static func _build_arms(p: Parts, d: Dictionary, rng: RandomNumberGenerator, skin: Callable, shirt: Color) -> void:
	var thin: float = d["thin"]
	var size: float = 1.0 * (1.35 if p.kind == "brute" else 1.0) * (1.08 if p.kind in ["runner", "screamer"] else 1.0)
	for side: String in ["l", "r"]:
		var s: float = -1.0 if side == "l" else 1.0
		var st: SurfaceTool = ClayMesh.begin()
		var bare: bool = (side == "l" and p.kind != "brute") or p.kind in ["bloated", "screamer"]
		var r0: float = 0.05 * thin
		limb(st, Vector3.ZERO, Vector3(0.0, -p.upper_arm, 0.0), r0, 0.038 * thin, skin, 14, 0.18)
		if not bare:
			# 찢긴 소매.
			ClayMesh.add_shell(st, Vector3(0.0, -p.upper_arm * 0.35, 0.0), Vector3(r0 * 1.35, p.upper_arm * 0.48, r0 * 1.35), cloth(shirt, 0.6), func(dir: Vector3) -> bool: return dir.y > -0.7 + 0.25 * sin(atan2(dir.z, dir.x) * 5.0), func(_dir: Vector3) -> float: return 1.0, 14, 10)
		else:
			ClayMesh.add_ellipsoid(st, Vector3(s * -0.02, -p.upper_arm * 0.55, -0.03), Vector3(0.022, 0.05, 0.015), gore(), 8, 6)
		# 팔꿈치 뼈.
		ClayMesh.add_ellipsoid(st, Vector3(0.0, -p.upper_arm, 0.028 * thin), Vector3(0.024, 0.024, 0.022), skin, 8, 6)
		p.meshes["upper_" + side] = ClayMesh.commit(st)
		st = ClayMesh.begin()
		limb(st, Vector3.ZERO, Vector3(0.0, -p.fore_arm, 0.0), 0.037 * thin, 0.026 * thin, skin, 12, 0.22)
		# 손목 힘줄 · 상처 (오른팔은 살이 뜯겨 뼈가 보인다).
		if side == "r" and p.kind in ["shambler", "crawler", "runner"]:
			ClayMesh.add_ellipsoid(st, Vector3(0.0, -p.fore_arm * 0.5, -0.025 * thin), Vector3(0.024, 0.07, 0.016), gore(), 10, 6)
			limb(st, Vector3(0.006, -p.fore_arm * 0.32, -0.032 * thin), Vector3(0.004, -p.fore_arm * 0.7, -0.03 * thin), 0.009, 0.008, bone(), 6, 0.0)
		hand(st, Vector3(0.0, -p.fore_arm, 0.0), size, skin, rng, 0.05 if p.kind in ["runner", "screamer", "brute"] else 0.035)
		p.meshes["fore_" + side] = ClayMesh.commit(st)


static func _build_legs(p: Parts, d: Dictionary, rng: RandomNumberGenerator, skin: Callable, pants: Color) -> void:
	var thin: float = d["thin"]
	var shoes: int = d["shoes"]
	for side: String in ["l", "r"]:
		var st: SurfaceTool = ClayMesh.begin()
		var r0: float = 0.072 * thin
		if p.kind == "crawler":
			# 짓이겨진 허벅지: 바지가 찢겨 뼈가 삐져나온다 (무릎 아래는 없다시피).
			limb(st, Vector3.ZERO, Vector3(0.0, -p.thigh * 0.8, 0.0), r0, 0.05, cloth(pants, 0.9), 12, 0.1)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, -p.thigh * 0.82, 0.0), Vector3(0.055, 0.04, 0.055), gore(), 12, 8)
			limb(st, Vector3(0.0, -p.thigh * 0.8, 0.0), Vector3(0.01, -p.thigh * 1.08, 0.01), 0.016, 0.012, bone(), 8, 0.0)
			ClayMesh.add_ellipsoid(st, Vector3(0.01, -p.thigh * 1.1, 0.01), Vector3(0.024, 0.02, 0.022), bone(), 8, 6)
			p.meshes["thigh_" + side] = ClayMesh.commit(st)
			p.meshes["shin_" + side] = _empty()
			continue
		limb(st, Vector3.ZERO, Vector3(0.0, -p.thigh, 0.0), r0, 0.05 * thin, cloth(pants, 0.5), 14, 0.15)
		ClayMesh.add_ellipsoid(st, Vector3(0.0, -p.thigh, -0.03 * thin), Vector3(0.042, 0.04, 0.03) * thin, cloth(pants.darkened(0.1), 0.6), 10, 6)
		p.meshes["thigh_" + side] = ClayMesh.commit(st)
		st = ClayMesh.begin()
		var torn: bool = side == "r"
		if torn:
			# 바지가 무릎 아래로 찢겨 앙상한 정강이 · 드러난 정강이뼈.
			limb(st, Vector3.ZERO, Vector3(0.0, -p.shin + 0.04, 0.0), 0.045 * thin, 0.03 * thin, skin, 12, 0.15)
			limb(st, Vector3(0.0, -0.08, -0.035 * thin), Vector3(0.0, -p.shin * 0.75, -0.03 * thin), 0.011, 0.01, bone(), 6, 0.0)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, -p.shin * 0.4, -0.03 * thin), Vector3(0.022, 0.08, 0.012), gore(), 10, 6)
			for i: int in 3:
				rag(st, Vector3(rng.randf_range(-0.04, 0.04), -0.02, rng.randf_range(-0.04, 0.04)), rng.randf_range(0.06, 0.12), 0.03, cloth(pants, 0.8), rng, Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)))
		else:
			limb(st, Vector3.ZERO, Vector3(0.0, -p.shin + 0.04, 0.0), 0.05 * thin, 0.04 * thin, cloth(pants, 0.5), 12, 0.12)
		var ankle: Vector3 = Vector3(0.0, -p.shin + 0.06, 0.0)
		var size: float = thin * (1.15 if p.kind == "brute" else 1.0)
		if (shoes == 2) or (shoes == 1 and side == "l"):
			shoe(st, ankle, size, Color("#3A3028"))
		else:
			foot(st, ankle, size, flesh(Color(d["skin"]).darkened(0.12)))
		p.meshes["shin_" + side] = ClayMesh.commit(st)


static func _empty() -> ArrayMesh:
	return ArrayMesh.new()


# ---- 조립 ----

## 관절 노드를 짓고 부위 메시를 붙인다. root 는 서 있는 자리 (발바닥 = 0).
static func build(kind: String, material: Material) -> Rig:
	var p: Parts = parts(kind)
	var r: Rig = Rig.new()
	r.parts = p
	r.root = Node3D.new()
	r.root.name = "Rig"
	r.hips = _joint(r.root, "Hips", Vector3(0.0, p.hip_y, 0.0))
	_mesh(r.hips, p.meshes["pelvis"], material)
	r.spine = _joint(r.hips, "Spine", Vector3(0.0, 0.04, 0.0))
	_mesh(r.spine, p.meshes["torso"], material)
	if p.glows.has("pustules"):
		_mesh(r.spine, p.glows["pustules"], glow_material(p.glow_colors["pustules"], Color("#6A7A2A")), false)
	r.neck = _joint(r.spine, "Neck", Vector3(0.0, p.torso_h - 0.02, 0.0))
	_mesh(r.neck, p.meshes["neck"], material)
	if p.glows.has("sac"):
		r.sac = _joint(r.neck, "Sac", Vector3(0.0, p.neck_len * 0.3, -0.07))
		_mesh(r.sac, p.glows["sac"], glow_material(p.glow_colors["sac"], Color("#3E5A1E")), false)
	r.head = _joint(r.neck, "Head", Vector3(0.0, p.neck_len, 0.0))
	_mesh(r.head, p.meshes["head"], material)
	_mesh(r.head, p.glows["eyes"], glow_material(p.glow_colors["eyes"], Color("#B8B094")), false)
	r.jaw = _joint(r.head, "Jaw", Vector3(0.0, 0.1, 0.0))
	_mesh(r.jaw, p.meshes["jaw"], material)
	for side: String in ["l", "r"]:
		var s: float = -1.0 if side == "l" else 1.0
		var sh: Node3D = _joint(r.spine, "Shoulder_" + side, Vector3(s * (p.shoulder_w + 0.02), p.torso_h - 0.07, 0.02))
		_mesh(sh, p.meshes["upper_" + side], material)
		var el: Node3D = _joint(sh, "Elbow_" + side, Vector3(0.0, -p.upper_arm, 0.0))
		_mesh(el, p.meshes["fore_" + side], material)
		var th: Node3D = _joint(r.hips, "Thigh_" + side, Vector3(s * p.hip_w, -0.03, 0.0))
		_mesh(th, p.meshes["thigh_" + side], material)
		var kn: Node3D = _joint(th, "Knee_" + side, Vector3(0.0, -p.thigh, 0.0))
		_mesh(kn, p.meshes["shin_" + side], material)
		if side == "l":
			r.shoulder_l = sh
			r.elbow_l = el
			r.thigh_l = th
			r.knee_l = kn
		else:
			r.shoulder_r = sh
			r.elbow_r = el
			r.thigh_r = th
			r.knee_r = kn
	r.root.scale = Vector3.ONE * p.scale
	return r


static func _joint(parent: Node3D, joint_name: String, at: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	n.name = joint_name
	n.position = at
	parent.add_child(n)
	return n


static func _mesh(parent: Node3D, mesh: ArrayMesh, material: Material, shadow: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 한 크리처의 삼각형 수 (점검용).
static func triangle_count(kind: String) -> int:
	var p: Parts = parts(kind)
	var n: int = 0
	for m: ArrayMesh in p.meshes.values():
		for s: int in m.get_surface_count():
			var idx: PackedInt32Array = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			n += idx.size() / 3
	for m: ArrayMesh in p.glows.values():
		for s: int in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n
