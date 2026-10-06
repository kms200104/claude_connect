class_name CharacterModel
extends RefCounted
## 캐릭터 메시 공방: 겉모습(CharacterLook)으로 몸·팔·다리·눈·도구 메시를 만든다. 같은 겉모습은 한 번만 만든다.
## 2.5등신 점토 인형 비율 — 옆으로 살짝 넓은 큰 머리와 작은 귀, 덩어리진 가닥으로 만든 머리(10가지), 니트 스웨터, 반바지, 부츠.
## 눈·코·입은 data/looks/face_parts.json 의 도형을 머리 겉면에 촘촘히 붙인 얇은 판 (FaceShapes).
## 좌표는 리그(Visual) 기준: 발바닥 y = -0.8, 머리 꼭대기 ≈ 0.8, 정면 = -Z.
## 정점 색만 쓰므로 머티리얼은 흰 툰 머티리얼 하나 (캐릭터 하나 = 드로우콜 8: 몸통, 머리, 골반, 눈, 팔 2, 다리 2).
## v0.13: 허리·목 관절 — 몸통(body: 스웨터)은 허리 위, 머리(head: 머리·얼굴·머리카락·귀)는 목 위, 반바지(hips)는 골반에 단다.
## 세 메시 모두 같은 Visual 좌표로 만들고, 리그가 관절 노드 안에서 원래 자리를 되돌려 놓는다.

const HEAD_CENTER: Vector3 = Vector3(0.0, 0.4, 0.0)
## 옆으로 넓고 앞뒤로 살짝 납작한 찹쌀떡 머리 (얼굴이 덜 휘어 눈코입이 평평하게 보인다). x·z 는 정수리 쪽 반지름이고
## 볼·턱 쪽은 head_width 만큼 넓어진다.
const HEAD_RADII: Vector3 = Vector3(0.37, 0.37, 0.3)
## 볼·턱 쪽이 정수리 쪽보다 넓은 비율.
const HEAD_JOWL: float = 0.11
## 팔·다리 관절 (Visual 기준). 리그 씬의 ArmL/ArmR/LegL/LegR 노드 위치와 같아야 한다.
const SHOULDER: Vector3 = Vector3(0.23, -0.05, 0.0)
const HIP: Vector3 = Vector3(0.1, -0.42, 0.0)
## 어깨에서 손(도구를 쥐는 곳)까지.
const HAND_OFFSET: Vector3 = Vector3(0.0, -0.3, 0.0)
const EYE_CENTER: Vector3 = Vector3(0.0, 0.35, -0.3)

const MOUTH_COLOR: Color = Color("#5A3326")

## 얼굴 부품을 머리 겉면에서 띄우는 거리 (m). 눈은 시선을 따라 머리 중심을 축으로 굴러서(타원체라 최대 3mm 안쪽으로 든다) 더 띄운다.
const CHEEK_LIFT: float = 0.002
const FEATURE_LIFT: float = 0.003
const EYE_LIFT: float = 0.0055
## 같은 부품 안에서 층마다 더 띄우는 거리 (깊이 겹침 방지).
const LAYER_LIFT: float = 0.0009
## 머리 타원체 [둘레 칸, 위아래 칸] — 촘촘함 0 (절약) / 1 / 2 (고화질). 머리카락에 늘 덮이는 정수리·뒤통수 면은 만들지 않는다.
const HEAD_SEGMENTS: Array[Vector2i] = [Vector2i(24, 16), Vector2i(38, 26), Vector2i(48, 32)]
## 머리카락 껍질 [둘레 칸, 위아래 칸].
const HAIR_SEGMENTS: Array[Vector2i] = [Vector2i(20, 12), Vector2i(34, 20), Vector2i(44, 26)]
## 머리카락 다발 [마디 수, 단면 꼭짓점 수].
const LOCK_SEGMENTS: Array[Vector2i] = [Vector2i(5, 5), Vector2i(9, 7), Vector2i(12, 9)]
## 다발 단면을 렌즈 모양으로 (가운데 도톰, 가장자리 얇게).
const LOCK_LENS: float = 0.55
## 머리카락 껍질의 중심과 반지름 (머리보다 조금 크고 위·뒤로 치우친 타원체). 다발은 이 겉면을 따라 내려온다.
const HAIR_CENTER: Vector3 = Vector3(0.0, 0.43, 0.02)
const HAIR_RADII: Vector3 = Vector3(0.44, 0.39, 0.36)
## 귀 (머리 옆, 눈 아래쪽 높이에 도톰하게 반쯤 묻힌다).
const EAR_CENTER: Vector3 = Vector3(0.4, 0.33, 0.03)
const EAR_RADII: Vector3 = Vector3(0.05, 0.08, 0.06)

## 0 = 절약 … MAX_DETAIL = 고화질 (Quality 가 정한다). 바꾸면 clear_cache() 로 메시를 다시 만든다.
static var detail: int = 1
const MAX_DETAIL: int = 2
## 촘촘함별 얼굴 도형 삼각형의 가장 긴 변 (m).
const FACE_MAX_EDGE: Array[float] = [0.05, 0.032, 0.022]
## 촘촘함별 얼굴 도형 둘레(눈·눈동자·입·표정의 원과 호) 배율 — 크게 보이는 고화질일수록 둥글게 (FaceShapes).
const FACE_OUTLINE: Array[float] = [1.0, 2.0, 3.5]
## 몸통·팔·다리 둘레 칸 배율 (v0.11.2: 고화질은 소매·부츠·몸통도 매끈하게).
const BODY_DETAIL: Array[float] = [1.0, 1.5, 2.0]
static var _cache: Dictionary[String, ArrayMesh] = {}


## 화질이 바뀌었을 때: 만들어 둔 메시를 버린다 (리그는 set_look 을 다시 불러 새로 만든다).
## 몸 부위 둘레 칸 수: 절약 화질의 칸 수 × BODY_DETAIL.
static func _seg(base: int) -> int:
	return int(round(float(base) * BODY_DETAIL[clampi(detail, 0, MAX_DETAIL)]))


## 몸통 윤곽을 촘촘함만큼 곱게 (점 사이를 Catmull-Rom 으로 1~2번 더 나눈다). 절약 화질은 그대로.
static func _smooth_profile(points: PackedVector2Array) -> PackedVector2Array:
	var splits: int = clampi(detail, 0, MAX_DETAIL)
	if splits == 0:
		return points
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = points.size()
	for i: int in n - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, n - 1)]
		for k: int in splits + 1:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / float(splits + 1)))
	out.append(points[n - 1])
	return out


## 둥근 모서리를 나누는 칸 수 (고화질에서 한 칸씩 더).
static func _round_steps(base: int) -> int:
	return base + clampi(detail, 0, MAX_DETAIL)


static func clear_cache() -> void:
	_cache.clear()


## 몸통 (허리 위): 스웨터 + 밑단 고무단 + 목폴라.
static func body(look: CharacterLook) -> ArrayMesh:
	var key: String = "body|%d|%s" % [detail, look.key()]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	var knit: Callable = _knit(look.top)
	# 스웨터: 아래 단이 살짝 넓고 어깨가 둥근 몸통 + 목폴라 + 밑단 고무단.
	var torso: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -0.37), Vector2(0.2, -0.37), Vector2(0.225, -0.33), Vector2(0.215, -0.22), Vector2(0.225, -0.1),
		Vector2(0.215, -0.02), Vector2(0.16, 0.03), Vector2(0.0, 0.05)])
	ClayMesh.add_lathe(st, _smooth_profile(torso), _seg(16), Transform3D(), knit)
	ClayMesh.add_torus(st, Vector3(0.0, -0.345, 0.0), 0.205, 0.03, look.top.darkened(0.08), _seg(16), _seg(4))
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.125, 0.115, -0.01, 0.1, 0.03, _round_steps(1)), _seg(12), Transform3D(), _knit(look.top.darkened(0.04)))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 골반 (허리 아래): 반바지 — 허리에서 두 다리 통으로 갈라지고, 끝단을 접어 올렸다.
static func hips(look: CharacterLook) -> ArrayMesh:
	var key: String = "hips|%d|%s" % [detail, look.key()]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.205, 0.215, -0.47, -0.3, 0.05, _round_steps(2)), _seg(14), Transform3D(), look.bottom)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.1, 0.1, -0.53, -0.42, 0.03, _round_steps(1)), _seg(8), Transform3D(Basis(), Vector3(HIP.x * side, 0.0, 0.0)), look.bottom)
		ClayMesh.add_torus(st, Vector3(HIP.x * side, -0.525, 0.0), 0.095, 0.022, look.bottom.lightened(0.12), _seg(8), _seg(4))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 머리 (목 위): 머리 · 귀 · 얼굴 · 머리카락.
static func head(look: CharacterLook) -> ArrayMesh:
	var key: String = "head|%d|%d|%s" % [detail, 1 if hair_models else 0, look.key()]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	# 머리: 볼·턱 쪽이 넓은 찹쌀떡 (높이마다 옆·앞뒤 반지름에 head_width 를 곱한 회전체). 둘레를 촘촘히 나눠
	# 얼굴 부품과 겉면 사이가 벌어지거나 파묻히지 않게 한다. 얼굴 부품은 같은 겉면(face_point)에 붙는다.
	var segs: Vector2i = HEAD_SEGMENTS[clampi(detail, 0, MAX_DETAIL)]
	var cover: float = _hair_cover_bottom(look.hair_style)
	var head_profile: PackedVector2Array = PackedVector2Array()
	for i: int in segs.y + 1:
		var a: float = -PI * 0.5 + PI * float(i) / float(segs.y)
		head_profile.append(Vector2(cos(a) * head_width(sin(a)), sin(a) * HEAD_RADII.y))
	ClayMesh.add_lathe(st, head_profile, segs.x, Transform3D(Basis.from_scale(Vector3(HEAD_RADII.x, 1.0, HEAD_RADII.z)), HEAD_CENTER), look.skin)
	# 귀: 머리카락이 옆을 다 덮는 긴 머리에서는 만들지 않는다.
	if cover > -0.4:
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_ellipsoid(st, Vector3(EAR_CENTER.x * side, EAR_CENTER.y, EAR_CENTER.z), EAR_RADII, look.skin.darkened(0.03), 8 + 2 * detail, 5 + detail, Basis(Vector3.UP, 0.3 * side))
	_add_face(st, look)
	_add_hair(st, look)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 팔 하나 (어깨 기준): 소매 + 소매 끝단 + 손.
static func arm(look: CharacterLook) -> ArrayMesh:
	var key: String = "arm|%d|%s" % [detail, look.key()]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_capsule(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.21, 0.0), 0.068, _knit(look.top), _seg(8), _round_steps(2))
	ClayMesh.add_torus(st, Vector3(0.0, -0.225, 0.0), 0.06, 0.022, look.top.darkened(0.08), _seg(8), _seg(4))
	ClayMesh.add_ellipsoid(st, HAND_OFFSET + Vector3(0.0, 0.02, 0.0), Vector3(0.062, 0.066, 0.062), look.skin, _seg(7), _seg(4))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 다리 하나 (골반 기준): 짧은 다리 + 접은 단이 있는 부츠.
static func leg(look: CharacterLook) -> ArrayMesh:
	var key: String = "leg|%d|%s" % [detail, look.key()]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_capsule(st, Vector3(0.0, -0.02, 0.0), Vector3(0.0, -0.2, 0.0), 0.058, look.skin, _seg(6), _round_steps(1))
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.082, 0.078, -0.37, -0.17, 0.03, _round_steps(1)), _seg(8), Transform3D(), look.shoes)
	ClayMesh.add_torus(st, Vector3(0.0, -0.175, 0.0), 0.08, 0.024, look.shoes.lightened(0.1), _seg(8), _seg(4))
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.335, -0.045), Vector3(0.155, 0.09, 0.24), 0.45, look.shoes, Basis(), _seg(8), _seg(4))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 두 눈 (모양은 look.eyes, 눈동자 색은 look.eye_color). 머리 중심(HEAD_CENTER) 기준 좌표로 만들어
## 시선을 돌릴 때는 머리 중심을 축으로 살짝 굴린다 (옮기면 둥근 얼굴에서 떠오르거나 파묻힌다).
static func eyes(look: CharacterLook = null) -> ArrayMesh:
	var l: CharacterLook = look if look != null else CharacterLook.new()
	var key: String = "eyes|%d|%s" % [detail, l.eye_key()]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	var catalog: FaceCatalog = _catalog()
	var part: FaceCatalog.Part = catalog.part("eyes", l.eyes) if catalog != null else null
	if part == null and catalog != null and not catalog.eyes.is_empty():
		part = catalog.eyes[0]
	if part != null:
		var anchor: Vector2 = catalog.anchors.get("eye", Vector2(0.19, 0.35))
		var palette: Dictionary[String, Color] = face_palette(l)
		for side: float in [-1.0, 1.0]:
			_emit_face(st, part.layers, palette, Vector2(anchor.x * side, anchor.y), side < 0.0, HEAD_CENTER, EYE_LIFT)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 감정표현 하는 동안 얼굴에 덧그리는 눈썹·눈물(머리 겉면에 붙인 판)과 머리 옆 땀방울 (face_parts.json 의 expressions).
## 표정이 없는 감정표현이면 null. 정점은 리그(Visual) 기준이라 몸 메시와 같은 자리에 둔다.
static func expression(look: CharacterLook, emote_id: String) -> ArrayMesh:
	var catalog: FaceCatalog = _catalog()
	var part: FaceCatalog.Part = catalog.expressions.get(emote_id) if catalog != null else null
	if part == null:
		return null
	var key: String = "expr|%d|%s|%s" % [detail, part.id, look.hair.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	var palette: Dictionary[String, Color] = face_palette(look)
	_emit_face(st, part.layers, palette, Vector2.ZERO, false, Vector3.ZERO, FEATURE_LIFT)
	for layer: Dictionary in part.layers:
		if str(layer.get("shape", "")) == "sweat":
			_add_sweat(st, layer, palette.get("sweat", Color("#A8DDF7")))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 땀방울: 끝이 위로 뾰족한 물방울 회전체 + 작은 반짝임. at = 아래 둥근 부분의 중심, s = 전체 높이.
static func _add_sweat(st: SurfaceTool, layer: Dictionary, color: Color) -> void:
	var at_raw: Array = layer.get("at", [0.4, 0.62, -0.24])
	var at: Vector3 = Vector3(float(at_raw[0]), float(at_raw[1]), float(at_raw[2]))
	var radius: float = float(layer.get("s", 0.1)) * 0.32
	var half: int = 3 + detail
	var profile: PackedVector2Array = PackedVector2Array()
	# 아래 반은 둥근 공, 위 반은 뾰족하게 모이는 고깔.
	for i: int in half + 1:
		var a: float = -PI * 0.5 + PI * 0.5 * float(i) / float(half)
		profile.append(Vector2(cos(a), sin(a)) * radius)
	for i: int in range(1, half + 1):
		var t: float = float(i) / float(half)
		profile.append(Vector2(radius * (1.0 - t) * (1.0 - t * 0.3), radius * 2.1 * t))
	var basis: Basis = Basis(Vector3.BACK, deg_to_rad(float(layer.get("tilt", 0.0))))
	ClayMesh.add_lathe(st, profile, 8 + 2 * detail, Transform3D(basis, at), color)
	ClayMesh.add_ellipsoid(st, at + basis * Vector3(-radius * 0.4, radius * 0.35, -radius * 0.85), Vector3(radius * 0.2, radius * 0.3, radius * 0.12), Color.WHITE, 6, 4, basis)


## 낚싯대: 손잡이(감은 끈) · 릴 · 가늘어지는 대 · 줄 고리. 손에서 +Y 로 뻗는다.
static func rod() -> ArrayMesh:
	if _cache.has("rod"):
		return _cache["rod"]
	var st: SurfaceTool = ClayMesh.begin()
	var wood: Color = Color("#D9A86C")
	ClayMesh.add_rod(st, Vector3(0.0, -0.12, 0.0), Vector3(0.0, 0.16, 0.0), 0.036, 0.032, Color("#8A5A3A"), 8)
	for i: int in 4:
		ClayMesh.add_torus(st, Vector3(0.0, -0.08 + 0.065 * i, 0.0), 0.034, 0.008, Color("#6E452C"), 8, 3)
	ClayMesh.add_rod(st, Vector3(0.0, 0.16, 0.0), Vector3(0.0, 1.55, 0.0), 0.028, 0.012, wood, 7)
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.06, 0.06, -0.02, 0.02, 0.012, 1), 10, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.055, 0.22, 0.0)), Color("#C99A60"))
	for y: float in [0.6, 1.0, 1.35]:
		ClayMesh.add_torus(st, Vector3(0.0, y, 0.0), 0.02, 0.006, Color("#A0704A"), 6, 3)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["rod"] = mesh
	return mesh


## 도끼: 나무 자루 + 은빛 날. 손에서 +Y 로 뻗는다.
static func axe() -> ArrayMesh:
	if _cache.has("axe"):
		return _cache["axe"]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.62, 0.0), 0.032, 0.028, Color("#B07A45"), 8)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.56, 0.0), Vector3(0.09, 0.15, 0.08), 0.4, Color("#7C5A3C"), Basis(), 8, 5)
	var blade: Callable = ClayMesh.vertical_gradient(Color("#8E9BA6"), Color("#D3DCE2"), 1.0)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.56, -0.13), Vector3(0.05, 0.2, 0.2), 0.35, blade, Basis(), 8, 5)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["axe"] = mesh
	return mesh


## 식칼: 나무 손잡이 + 넓적한 은빛 날. 손에서 +Y 로 뻗는다.
static func knife() -> ArrayMesh:
	if _cache.has("knife"):
		return _cache["knife"]
	var model: ArrayMesh = PartMesh.load_model("tool_knife")
	if model != null:
		_cache["knife"] = model
		return model
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.07, 0.0), 0.022, 0.02, Color("#6E452C"), 8)
	var blade: Callable = ClayMesh.vertical_gradient(Color("#9AA6AF"), Color("#E3EAEE"), 1.0)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.17, -0.025), Vector3(0.012, 0.2, 0.075), 0.3, blade, Basis(), 6, 4)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["knife"] = mesh
	return mesh


## 배달 물건 (v0.12 일거리): 손에 매달아 드는 꼴이라 손잡이가 원점, 물건은 +Y 쪽(팔 아래)으로 늘어진다.
## parcel = 노끈으로 묶은 갈색 상자, lunchbox = 보자기로 싼 도시락(매듭이 손잡이), envelope = 노란 서류 봉투.
static func carry_prop(prop_id: String) -> ArrayMesh:
	if _cache.has("carry_" + prop_id):
		return _cache["carry_" + prop_id]
	var st: SurfaceTool = ClayMesh.begin()
	match prop_id:
		"parcel":
			var kraft: Color = Color("#C49A62")
			var twine: Color = Color("#F1E6CC")
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.17, 0.0), Vector3(0.24, 0.18, 0.2), 0.12, kraft, Basis(), 8, 6)
			ClayMesh.add_box(st, Vector3(0.0, 0.17, 0.0), Vector3(0.245, 0.185, 0.025), twine)
			ClayMesh.add_box(st, Vector3(0.0, 0.17, 0.0), Vector3(0.025, 0.185, 0.205), twine)
			ClayMesh.add_torus(st, Vector3(0.0, 0.035, 0.0), 0.045, 0.008, twine, 10, 4, Basis(Vector3.RIGHT, PI * 0.5))
			ClayMesh.add_box(st, Vector3(0.06, 0.255, 0.05), Vector3(0.06, 0.004, 0.045), Color("#FFFFFF"), Basis(Vector3.RIGHT, PI * 0.5))
		"lunchbox":
			var cloth: Color = Color("#E05A63")
			var dots: Color = Color("#FFE7C8")
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.2, 0.0), Vector3(0.24, 0.13, 0.17), 0.35, cloth, Basis(), 10, 6)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.11, 0.0), Vector3(0.045, 0.04, 0.035), cloth, 8, 5)
			ClayMesh.add_ellipsoid(st, Vector3(-0.055, 0.075, 0.0), Vector3(0.04, 0.025, 0.02), cloth, 6, 4, Basis(Vector3.BACK, 0.7))
			ClayMesh.add_ellipsoid(st, Vector3(0.055, 0.075, 0.0), Vector3(0.04, 0.025, 0.02), cloth, 6, 4, Basis(Vector3.BACK, -0.7))
			for d: Vector2 in [Vector2(-0.07, 0.17), Vector2(0.05, 0.22), Vector2(-0.02, 0.25), Vector2(0.08, 0.16)]:
				ClayMesh.add_ellipsoid(st, Vector3(d.x, d.y, 0.086), Vector3(0.012, 0.012, 0.004), dots, 6, 3)
		_:
			var paper: Color = Color("#E8C877")
			ClayMesh.add_rounded_box(st, Vector3(0.0, 0.13, 0.0), Vector3(0.2, 0.26, 0.018), 0.15, paper, Basis(), 6, 4)
			ClayMesh.add_box(st, Vector3(0.0, 0.035, 0.0), Vector3(0.18, 0.05, 0.022), paper.darkened(0.12))
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.05, 0.012), Vector3(0.016, 0.016, 0.005), Color("#B23A32"), 8, 3)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["carry_" + prop_id] = mesh
	return mesh


## 프라이팬: 손잡이 끝에 둥근 팬 (팬 바닥은 손잡이와 직각).
static func pan() -> ArrayMesh:
	if _cache.has("pan"):
		return _cache["pan"]
	# Tripo 로 만든 모형이 있으면 그것을 쓴다 (tools/blender/import_tripo.py).
	var model: ArrayMesh = PartMesh.load_model("tool_pan")
	if model != null:
		_cache["pan"] = model
		return model
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.06, 0.0), Vector3(0.0, 0.16, 0.0), 0.022, 0.02, Color("#3A2E28"), 8)
	var dish: PackedVector2Array = PackedVector2Array([Vector2(0.0, -0.02), Vector2(0.15, -0.02), Vector2(0.17, 0.03), Vector2(0.155, 0.035), Vector2(0.14, -0.005), Vector2(0.0, -0.005)])
	ClayMesh.add_lathe(st, dish, 14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.32, 0.0)), Color("#4A4E56"))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["pan"] = mesh
	return mesh


## 국자: 긴 자루 끝에 오목한 그릇.
static func ladle() -> ArrayMesh:
	if _cache.has("ladle"):
		return _cache["ladle"]
	var model: ArrayMesh = PartMesh.load_model("tool_ladle")
	if model != null:
		_cache["ladle"] = model
		return model
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.3, 0.0), 0.016, 0.013, Color("#C9CED3"), 7)
	var cup: PackedVector2Array = PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.05, -0.04), Vector2(0.07, 0.0), Vector2(0.06, 0.01), Vector2(0.0, -0.035)])
	ClayMesh.add_lathe(st, cup, 10, Transform3D(Basis(), Vector3(0.0, 0.33, -0.04)), Color("#B7BEC5"))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["ladle"] = mesh
	return mesh


## 뜰채: 긴 자루 끝에 둥근 테와 그물 주머니. 손에서 +Y 로 뻗는다.
static func landing_net() -> ArrayMesh:
	if _cache.has("landing_net"):
		return _cache["landing_net"]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.85, 0.0), 0.022, 0.018, Color("#B07A45"), 7)
	ClayMesh.add_torus(st, Vector3(0.0, 1.05, 0.0), 0.2, 0.018, Color("#5A6A7A"), 14, 4, Basis(Vector3.RIGHT, PI * 0.5))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 1.05, 0.1), Vector3(0.18, 0.18, 0.12), ClayMesh.vertical_gradient(Color("#9CC8E0"), Color("#D8EEF8"), 1.0), 10, 6)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["landing_net"] = mesh
	return mesh


## 삽: 나무 자루 + 손잡이 + 은빛 날. 손에서 +Y 로 뻗는다.
static func shovel() -> ArrayMesh:
	if _cache.has("shovel"):
		return _cache["shovel"]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.15, 0.0), Vector3(0.0, 0.72, 0.0), 0.024, 0.022, Color("#B07A45"), 7)
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.17, 0.0), Vector3(0.16, 0.05, 0.05), 0.4, Color("#7C5A3C"), Basis(), 6, 3)
	var blade: Callable = ClayMesh.vertical_gradient(Color("#8E9BA6"), Color("#D3DCE2"), 1.0)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.85, 0.0), Vector3(0.2, 0.26, 0.035), 0.35, blade, Basis(), 6, 4)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["shovel"] = mesh
	return mesh


## 얼굴: 볼터치, 코, 입 (눈은 따로 움직이는 메시). 모두 머리 겉면에 붙인 얇은 판이라 머리 속으로 파묻히지 않는다.
static func _add_face(st: SurfaceTool, look: CharacterLook) -> void:
	var catalog: FaceCatalog = _catalog()
	if catalog == null:
		return
	var palette: Dictionary[String, Color] = face_palette(look)
	var cheek: Vector2 = catalog.anchors.get("cheek", Vector2(0.245, 0.262))
	var blush: Array[Dictionary] = [{"shape": "ellipse", "c": [0.0, 0.0], "r": [0.056, 0.034], "color": "cheek"}]
	for side: float in [-1.0, 1.0]:
		_emit_face(st, blush, palette, Vector2(cheek.x * side, cheek.y), side < 0.0, Vector3.ZERO, CHEEK_LIFT)
	var nose_part: FaceCatalog.Part = catalog.part("nose", look.nose)
	if nose_part != null:
		_emit_face(st, nose_part.layers, palette, catalog.anchors.get("nose", Vector2(0.0, 0.315)), false, Vector3.ZERO, FEATURE_LIFT)
	var mouth_part: FaceCatalog.Part = catalog.part("mouth", look.mouth)
	if mouth_part != null:
		_emit_face(st, mouth_part.layers, palette, catalog.anchors.get("mouth", Vector2(0.0, 0.255)), false, Vector3.ZERO, FEATURE_LIFT)


## 얼굴 도형에 쓰는 색: 데이터의 고정 색(ink, mouth …) + 이 사람의 피부·볼·눈동자·코 색.
static func face_palette(look: CharacterLook) -> Dictionary[String, Color]:
	var palette: Dictionary[String, Color] = {}
	var catalog: FaceCatalog = _catalog()
	if catalog != null:
		palette.merge(catalog.colors)
	palette["iris"] = look.eye_color
	palette["skin"] = look.skin
	palette["cheek"] = look.cheeks
	palette["nose"] = look.skin.lerp(look.cheeks, 0.6).darkened(0.03)
	palette["nose_dark"] = look.skin.darkened(0.42).lerp(MOUTH_COLOR, 0.35)
	palette["nose_ball"] = look.cheeks.darkened(0.08)
	# 세모 코: 볼보다 진한 살구색.
	palette["nose_tri"] = look.cheeks.lerp(Color("#E8794F"), 0.6)
	# 눈동자 가운데 (눈동자 색보다 짙게).
	palette["pupil"] = look.eye_color.darkened(0.45)
	palette["lid"] = look.skin.darkened(0.07)
	# 표정 눈썹: 머리 색보다 진하게 (밝은 머리에서도 보이게 잉크 쪽으로 조금).
	palette["brow"] = look.hair.darkened(0.3).lerp(palette.get("ink", Color("#4A2B1F")), 0.25)
	return palette


## 도형 층들을 머리 겉면에 붙인다. anchor = 부품 자리(얼굴 x, y), mirror = 좌우 뒤집기(왼쪽 눈, gaze 층은 빼고),
## origin = 정점 좌표의 원점(눈은 머리 중심), lift = 겉면에서 띄우는 거리 (층마다 LAYER_LIFT 씩 더 띄운다).
static func _emit_face(st: SurfaceTool, layers: Array[Dictionary], palette: Dictionary[String, Color], anchor: Vector2, mirror: bool, origin: Vector3, lift: float) -> void:
	var entries: Array[Dictionary] = FaceShapes.triangles(layers, palette, _face_max_edge(), FACE_OUTLINE[clampi(detail, 0, MAX_DETAIL)])
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var tris: PackedVector2Array = entry["tris"]
		var color: Color = entry["color"]
		var dome: Vector3 = entry["dome"]
		var center: Vector2 = entry["center"]
		var layer_lift: float = lift + LAYER_LIFT * float(i)
		var flip: bool = mirror and not bool(entry["gaze"])
		for t: int in range(0, tris.size(), 3):
			var pos: Array[Vector3] = []
			var nrm: Array[Vector3] = []
			for k: int in 3:
				var q: Vector2 = tris[t + k]
				pos.append(_feature_point(q, anchor, flip, layer_lift, center, dome))
				nrm.append(_feature_normal(q, anchor, flip, layer_lift, center, dome))
			# 앞면 = 안쪽을 향하는 외적 (ClayMesh 와 같은 감김). 뒤집혔으면 두 점을 맞바꾼다.
			var outward: Vector3 = head_normal((pos[0] + pos[1] + pos[2]) / 3.0)
			if (pos[1] - pos[0]).cross(pos[2] - pos[0]).dot(outward) > 0.0:
				var tp: Vector3 = pos[1]
				pos[1] = pos[2]
				pos[2] = tp
				var tn: Vector3 = nrm[1]
				nrm[1] = nrm[2]
				nrm[2] = tn
			for k: int in 3:
				st.set_color(color)
				st.set_normal(nrm[k])
				st.add_vertex(pos[k] - origin)


## 부품 좌표 q → 얼굴 위 점 (dome 이면 그만큼 솟는다).
static func _feature_point(q: Vector2, anchor: Vector2, mirror: bool, lift: float, center: Vector2, dome: Vector3) -> Vector3:
	var h: float = FaceShapes.dome_height(q, center, dome) if dome != Vector3.ZERO else 0.0
	return face_point(anchor.x + (-q.x if mirror else q.x), anchor.y + q.y, lift + h)


## 평평한 도형은 머리 법선 그대로 (얼굴에 그린 것처럼 같은 명암), 솟은 코는 언덕의 기울기를 따른다.
static func _feature_normal(q: Vector2, anchor: Vector2, mirror: bool, lift: float, center: Vector2, dome: Vector3) -> Vector3:
	var p: Vector3 = _feature_point(q, anchor, mirror, lift, center, dome)
	var n: Vector3 = head_normal(p)
	if dome == Vector3.ZERO:
		return n
	var e: float = 0.002
	var du: Vector3 = _feature_point(q + Vector2(e, 0.0), anchor, mirror, lift, center, dome) - _feature_point(q - Vector2(e, 0.0), anchor, mirror, lift, center, dome)
	var dv: Vector3 = _feature_point(q + Vector2(0.0, e), anchor, mirror, lift, center, dome) - _feature_point(q - Vector2(0.0, e), anchor, mirror, lift, center, dome)
	var m: Vector3 = du.cross(dv).normalized()
	return m if m.dot(n) > 0.0 else -m


## 머리(타원체) 앞쪽 겉면에서 (x, y) 자리의 점을 바깥 법선 방향으로 lift 만큼 띄운 점.
static func face_point(x: float, y: float, lift: float) -> Vector3:
	var ny: float = (y - HEAD_CENTER.y) / HEAD_RADII.y
	var w: float = head_width(ny)
	var nx: float = x / (HEAD_RADII.x * w)
	var nz: float = sqrt(maxf(1.0 - nx * nx - ny * ny, 0.0))
	var surface: Vector3 = Vector3(x, y, -nz * HEAD_RADII.z * w)
	return surface + head_normal(surface) * lift


## 높이(ny: 머리 중심 -1 ~ 정수리 1)마다 옆·앞뒤 반지름 배율: 눈 위로는 1, 볼·턱으로 갈수록 1 + HEAD_JOWL.
static func head_width(ny: float) -> float:
	return 1.0 + HEAD_JOWL * _ramp(0.5, -0.3, ny)


## 머리 겉면의 바깥 법선 (p 는 Visual 좌표). 겉면 F = (x / (rx·w))² + ny² + (z / (rz·w))² = 1 의 기울기.
static func head_normal(p: Vector3) -> Vector3:
	var d: Vector3 = p - HEAD_CENTER
	var ny: float = d.y / HEAD_RADII.y
	var w: float = head_width(ny)
	var dw: float = (head_width(ny + 0.001) - head_width(ny - 0.001)) / 0.002
	var a: float = d.x / (HEAD_RADII.x * w)
	var c: float = d.z / (HEAD_RADII.z * w)
	return Vector3(a / (HEAD_RADII.x * w), ny / HEAD_RADII.y - (a * a + c * c) * dw / (w * HEAD_RADII.y), c / (HEAD_RADII.z * w)).normalized()


## 머리 겉면 위의 점 (x, y 를 주면 z 를 얼굴 표면에 맞춘다). lift 만큼 바깥으로.
static func _on_head(x: float, y: float, lift: float) -> Vector3:
	return face_point(x, y, lift)


static func _catalog() -> FaceCatalog:
	return GameData.face if GameData != null else null


## 얼굴 도형 삼각형의 가장 긴 변 (머리 반지름 0.32m 에서 0.035m 변은 가운데가 겉면보다 0.5mm 안쪽).
static func _face_max_edge() -> float:
	return FACE_MAX_EDGE[clampi(detail, 0, MAX_DETAIL)]


## 머리카락: 머리보다 조금 큰 껍질(얼굴 자리는 머리 속으로 눌러 넣고, 결을 따라 살짝 골이 진다) 위에 끝이 모이는 도톰한 다발을 얹는다.
## 다발은 껍질 겉면을 따라 내려오다 늘어뜨린다 (_lock). 앞머리·옆머리·뒷머리·묶은 머리가 모양마다 다르다.
## 머리카락 모형 (v0.13, tools/blender/build_hair.py → assets/models/hair/<스타일>.glb): 있으면 절차 가닥 대신 쓴다.
## 끄면(비교용) 예전 절차 머리카락.
static var hair_models: bool = true
const HAIR_MODEL_DIR: String = "res://assets/models/hair"
static var _hair_meshes: Dictionary[String, ArrayMesh] = {}


## 이 스타일의 머리카락 모형 (없으면 null). 촘촘함 0 · 1 · 2 단계에 _low · _mid · 원본 (캐릭터 삼각형 예산).
static func hair_model(style: String) -> ArrayMesh:
	if not hair_models:
		return null
	var key: String = style + (["_low", "_mid", ""] as Array[String])[clampi(detail, 0, MAX_DETAIL)]
	if _hair_meshes.has(key):
		return _hair_meshes[key]
	var path: String = "%s/%s.glb" % [HAIR_MODEL_DIR, key]
	if not ResourceLoader.exists(path):
		path = "%s/%s.glb" % [HAIR_MODEL_DIR, style]
	var mesh: ArrayMesh = null
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path) as PackedScene
		var root: Node = scene.instantiate() if scene != null else null
		if root != null:
			var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
			mesh = (found[0] as MeshInstance3D).mesh as ArrayMesh if not found.is_empty() else null
			root.free()
	_hair_meshes[key] = mesh
	return mesh


## 머리카락 모형을 머리 메시에 덧붙이며 머리 색을 입힌다. 모형의 정점 색: R = 그늘(AO), G = 윤기 띠.
## 위를 보는 면은 밝게, 그늘진 곳은 어둡게, 윤기 띠는 밝게 (알파 1 — 툰 셰이더의 가는 결 선은 그리지 않는다).
static func _append_hair_model(st: SurfaceTool, mesh: ArrayMesh, hair: Color) -> void:
	var dark: Color = hair.darkened(0.2)
	var light: Color = hair.lightened(0.08)
	var shine: Color = hair.lightened(0.3)
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var order: PackedInt32Array = indices
		if order.is_empty():
			order.resize(verts.size())
			for i: int in verts.size():
				order[i] = i
		for i: int in order:
			var n: Vector3 = normals[i]
			var data: Color = colors[i] if i < colors.size() else Color.WHITE
			var c: Color = dark.lerp(light, clampf(n.y * 0.5 + 0.5, 0.0, 1.0))
			c = c.darkened(0.32 * (1.0 - clampf(data.r, 0.0, 1.0)))
			c = c.lerp(shine, clampf(data.g, 0.0, 1.0) * 0.5)
			c.a = 1.0
			st.set_color(c)
			st.set_normal(n)
			st.add_vertex(verts[i])


## 모형 머리카락에 다는 것 (색이 머리와 달라 절차로 그린다): 머리끈. 자리는 tools/blender/build_hair.py 의 TIE_* 와 같다.
static func _hair_accessories(st: SurfaceTool, look: CharacterLook) -> void:
	var tie: Color = Color("#F07A8A")
	match look.hair_style:
		"ponytail":
			ClayMesh.add_ellipsoid(st, HAIR_CENTER + Vector3(0.0, 0.29, 0.41), Vector3(0.085, 0.085, 0.045), tie, 8, 5)
		"pigtails":
			for side: float in [-1.0, 1.0]:
				var root: Vector3 = HAIR_CENTER + Vector3(0.4 * side, -0.05, 0.15)
				ClayMesh.add_ellipsoid(st, root, Vector3(0.08, 0.045, 0.08), tie, 8, 5)
				ClayMesh.add_ellipsoid(st, root + Vector3(0.059 * side, -0.353, 0.017), Vector3(0.06, 0.035, 0.06), tie, 8, 5)


static func _add_hair(st: SurfaceTool, look: CharacterLook) -> void:
	var model: ArrayMesh = hair_model(look.hair_style)
	if model != null:
		_append_hair_model(st, model, look.hair)
		_hair_accessories(st, look)
		return
	var color: Callable = _hair_paint(look.hair)
	var lock_seg: Vector2i = LOCK_SEGMENTS[clampi(detail, 0, MAX_DETAIL)]
	var one: Callable = func(_d: Vector3) -> float: return 1.0
	# 정수리에서 내려오는 결: 둘레를 따라 넓은 골이 진다 (아래로 갈수록 옅다).
	var grooves: Callable = func(dir: Vector3) -> float:
		var around: float = atan2(dir.x, -dir.z)
		return 1.0 + 0.028 * (absf(sin(around * 4.0)) - 0.5) * clampf(dir.y + 0.4, 0.0, 1.0)
	var tie: Color = Color("#F07A8A")
	match look.hair_style:
		"short":
			# 분홍 삐죽 숏컷: 끝이 뾰족한 앞머리가 이리저리 뻗치고, 귀 옆과 목덜미도 뾰족하게.
			_hair_shell(st, color, 0.42, 0.7, -0.05, -0.3, grooves)
			for b: Vector3 in [Vector3(-50.0, 6.0, 12.0), Vector3(-25.0, -10.0, 8.0), Vector3(0.0, 8.0, 6.0), Vector3(25.0, -8.0, 9.0), Vector3(50.0, 10.0, 13.0)]:
				_lock(st, color, b.x, 60.0, b.z, 0.08, 0.04, b.y, 0.0, 0.03, 0.06)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 80.0 * side, 34.0, -16.0, 0.08, 0.04, 8.0 * side, 0.0, 0.02, 0.08)
			for yaw: float in [150.0, 180.0, 210.0]:
				_lock(st, color, yaw, 10.0, -36.0, 0.09, 0.04, 0.0, 0.03, 0.02, 0.06)
		"bun":
			# 금발 똥머리: 옆으로 넘긴 앞머리, 얼굴 옆에 흘러내린 두 가닥, 정수리 위 동그란 올림머리.
			_hair_shell(st, color, 0.42, 0.7, -0.05, -0.3, grooves)
			_side_bangs(st, color, 1.0)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 60.0 * side, 30.0, -24.0, 0.056, 0.03, 6.0 * side, 0.12, 0.02, 0.05, 1.0)
			ClayMesh.add_ellipsoid(st, HAIR_CENTER + Vector3(0.0, 0.37, 0.05), Vector3(0.14, 0.12, 0.14), color, 10 + 2 * detail, 6, Basis(), ClayMesh.blob_wobble(3, 0.08, 4))
		"long":
			# 갈색 웨이브 롱: 옆으로 넘긴 앞머리, 어깨 아래까지 물결치며 내려와 끝이 모인다.
			_hair_shell(st, color, 0.3, 0.7, -0.62, -0.8, grooves)
			_side_bangs(st, color, 1.0)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 62.0 * side, 34.0, -34.0, 0.1, 0.045, 4.0 * side, 0.3, 0.02, 0.07, 1.0)
				_lock(st, color, 100.0 * side, 20.0, -40.0, 0.12, 0.05, 0.0, 0.3, 0.02, 0.06, 1.0)
				_lock(st, color, 142.0 * side, 0.0, -48.0, 0.13, 0.05, 0.0, 0.26, 0.01, 0.04, 1.0)
			_lock(st, color, 180.0, 0.0, -50.0, 0.13, 0.05, 0.0, 0.26, 0.01, 0.04, 1.0)
		"pigtails":
			# 보라 땋은 양갈래: 일자 앞머리, 귀 뒤에서 묶어 마디진 땋은 머리를 늘어뜨린다.
			_hair_shell(st, color, 0.3, 0.7, -0.32, -0.32, grooves)
			_blunt_bangs(st, color)
			var beads: Callable = func(u: float) -> float:
				return (0.78 + 0.22 * absf(cos(u * PI * 4.0))) * (1.0 - smoothstep(0.86, 1.0, u) * 0.55)
			for side: float in [-1.0, 1.0]:
				var root: Vector3 = HAIR_CENTER + Vector3(0.35 * side, -0.1, 0.13)
				var braid: PackedVector3Array = PackedVector3Array()
				var rows: int = 6 + lock_seg.x
				for k: int in rows + 1:
					var u: float = float(k) / float(rows)
					braid.append(root + Vector3((0.05 + 0.04 * u) * side, -0.38 * u, -0.02 * u))
				ClayMesh.add_strand(st, braid, 0.06, 0.06, root + Vector3(-0.3 * side, 0.0, 0.0), color, beads, lock_seg.y + 1)
				ClayMesh.add_ellipsoid(st, root + Vector3(0.0, 0.01, 0.0), Vector3(0.045, 0.04, 0.045), tie, 6, 4)
				ClayMesh.add_ellipsoid(st, braid[rows - 1] + Vector3(0.0, -0.01, 0.0), Vector3(0.04, 0.03, 0.04), tie, 6, 4)
		"ponytail":
			# 검정 포니테일: 매끈하게 빗어 넘기고 옆으로 넘긴 앞머리, 뒤통수 위에서 묶어 크게 휘어 내린 꼬리.
			_hair_shell(st, color, 0.42, 0.7, -0.05, -0.3, one)
			_side_bangs(st, color, -1.0)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 78.0 * side, 30.0, -18.0, 0.056, 0.03, 4.0 * side, 0.04, 0.02, 0.05)
			var tail: PackedVector3Array = PackedVector3Array()
			var tail_rows: int = lock_seg.x + 3
			for k: int in tail_rows + 1:
				var u: float = float(k) / float(tail_rows)
				tail.append(HAIR_CENTER + Vector3(0.1 + 0.28 * sin(u * PI * 0.6), 0.28 + 0.16 * u - 0.72 * u * u, 0.3 + 0.08 * sin(u * PI)))
			var taper: Callable = func(u: float) -> float:
				return lerpf(0.7, 1.0, minf(u * 4.0, 1.0)) * (1.0 - smoothstep(0.45, 1.0, u))
			ClayMesh.add_strand(st, tail, 0.11, 0.09, HAIR_CENTER + Vector3(0.0, 0.2, 0.2), color, taper, lock_seg.y + 1)
			ClayMesh.add_ellipsoid(st, tail[0] + Vector3(0.0, -0.01, 0.02), Vector3(0.06, 0.05, 0.05), tie, 6, 4)
		"curly":
			# 초록 웨이브: 가운데 가르마에서 양옆으로 넘긴 물결 앞머리, 볼록볼록한 겉면, 턱 아래로 물결치는 옆머리.
			var curl: Callable = func(dir: Vector3) -> float:
				return 1.04 + 0.06 * sin(dir.x * 13.0 + 1.0) * sin(dir.y * 11.0) * sin(dir.z * 12.0 + 0.5) + 0.04 * clampf(-dir.y, 0.0, 1.0)
			_hair_shell(st, color, 0.36, 0.72, -0.1, -0.6, curl)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 8.0 * side, 64.0, 16.0, 0.1, 0.045, 40.0 * side, 0.0, 0.05, 0.05, 0.0, 1.0)
				_lock(st, color, 66.0 * side, 34.0, -30.0, 0.1, 0.05, 6.0 * side, 0.18, 0.05, 0.1, 1.0)
				_lock(st, color, 108.0 * side, 16.0, -40.0, 0.12, 0.055, 0.0, 0.18, 0.05, 0.1, 1.0)
				_lock(st, color, 150.0 * side, 0.0, -46.0, 0.12, 0.055, 0.0, 0.14, 0.04, 0.08, 1.0)
		"spiky":
			# 빨강 부스스 숏: 정수리부터 사방으로 뻗친 뾰족한 다발.
			_hair_shell(st, color, 0.42, 0.7, -0.05, -0.3, grooves)
			for b: Vector3 in [Vector3(-42.0, -14.0, 12.0), Vector3(-14.0, 10.0, 6.0), Vector3(16.0, -8.0, 8.0), Vector3(44.0, 12.0, 14.0)]:
				_lock(st, color, b.x, 62.0, b.z, 0.084, 0.045, b.y, 0.0, 0.05, 0.12)
			for yaw: float in [-120.0, -60.0, 0.0, 60.0, 120.0, 180.0]:
				_lock(st, color, yaw + 20.0, 88.0, 52.0, 0.09, 0.045, 18.0, 0.0, 0.06, 0.2)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 82.0 * side, 34.0, -14.0, 0.075, 0.04, 10.0 * side, 0.0, 0.03, 0.12)
		"side":
			# 파랑 옆으로 넘긴 중단발: 한쪽에서 넘어오는 긴 앞머리, 턱선에서 바깥으로 뻗친 끝.
			_hair_shell(st, color, 0.3, 0.7, -0.62, -0.62, grooves)
			_lock(st, color, 46.0, 64.0, 10.0, 0.11, 0.045, -88.0, 0.0, 0.04, 0.04)
			_lock(st, color, 24.0, 60.0, 16.0, 0.095, 0.045, -56.0, 0.0, 0.04, 0.04)
			_lock(st, color, -40.0, 50.0, 12.0, 0.08, 0.04, -14.0, 0.0, 0.03, 0.03)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 62.0 * side, 34.0, -32.0, 0.1, 0.045, 4.0 * side, 0.16, 0.03, 0.1)
				_lock(st, color, 105.0 * side, 16.0, -40.0, 0.12, 0.05, 4.0 * side, 0.16, 0.02, 0.1)
				_lock(st, color, 150.0 * side, 0.0, -46.0, 0.12, 0.05, 0.0, 0.12, 0.02, 0.08)
		"buzz":
			# 회색 짧은 남자 머리: 짧게 친 껍질, 이마에 짧은 앞머리 몇 가닥과 구레나룻.
			_hair_shell(st, color, 0.46, 0.7, -0.02, -0.3, grooves, Vector3(0.97, 0.95, 0.97))
			for b: Vector2 in [Vector2(-26.0, 6.0), Vector2(0.0, -6.0), Vector2(26.0, 8.0)]:
				_lock(st, color, b.x, 56.0, 24.0, 0.084, 0.035, b.y, 0.0, 0.0, 0.03)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 80.0 * side, 24.0, -6.0, 0.056, 0.029, 0.0, 0.0, -0.01, 0.0)
		_:
			# 청록 히메컷(단발): 일자 앞머리, 턱선에서 똑 자른 옆머리, 정수리 리본.
			_hair_shell(st, color, 0.3, 0.7, -0.62, -0.62, grooves)
			_blunt_bangs(st, color)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 68.0 * side, 32.0, -26.0, 0.075, 0.04, 2.0 * side, 0.16, 0.02, 0.0, 0.0, 1.0)
				_lock(st, color, 105.0 * side, 16.0, -40.0, 0.12, 0.05, 0.0, 0.14, 0.02, 0.02, 0.0, 1.0)
				_lock(st, color, 150.0 * side, 0.0, -46.0, 0.13, 0.05, 0.0, 0.12, 0.01, 0.02, 0.0, 1.0)
			var bow: Color = look.hair.darkened(0.22)
			var knot: Vector3 = HAIR_CENTER + Vector3(0.0, 0.37, -0.06)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_ellipsoid(st, knot + Vector3(0.075 * side, 0.02, 0.0), Vector3(0.075, 0.05, 0.035), bow, 7, 4, Basis(Vector3.BACK, -0.35 * side) * Basis(Vector3.RIGHT, -0.4))
			ClayMesh.add_ellipsoid(st, knot, Vector3(0.035, 0.035, 0.035), bow.darkened(0.08), 6, 4)


## 머리카락 색 (v0.11.1 — 뭉친 떡처럼 보이지 않게):
##   - 위를 보는 면은 밝게, 아래는 어둡게 (기존 세로 그라데이션).
##   - 다발 가장자리·안쪽 면(법선이 머리 바깥을 향하지 않는 곳)은 어둡게 → 다발 사이에 골이 보여 한 가닥씩 갈라져 보인다.
##   - 정수리 아래 둘레에 결을 따라 끊어지는 윤기 띠(천사링) → 머리카락의 반짝임.
##   - 알파 0.5 로 표시해 두면 툰 셰이더가 가는 세로 결을 그린다.
static func _hair_paint(hair: Color) -> Callable:
	var dark: Color = hair.darkened(0.24)
	var light: Color = hair.lightened(0.1)
	var shine: Color = hair.lightened(0.34)
	return func(pos: Vector3, normal: Vector3) -> Color:
		var dir: Vector3 = (pos - HAIR_CENTER).normalized()
		var c: Color = dark.lerp(light, clampf(normal.y * 0.5 + 0.5, 0.0, 1.0))
		var facing: float = normal.dot(dir)
		c = c.darkened(0.2 * (1.0 - smoothstep(0.1, 0.6, facing)))
		var around: float = atan2(dir.x, -dir.z)
		var band: float = smoothstep(0.38, 0.5, dir.y) * (1.0 - smoothstep(0.62, 0.76, dir.y))
		var streak: float = 0.75 + 0.25 * sin(around * 9.0 + dir.y * 5.0)
		c = c.lerp(shine, band * streak * clampf(facing, 0.0, 1.0) * 0.55)
		# 알파 0.5 = 머리카락 표시: 툰 셰이더가 가는 결을 그린다 (toon_common.gdshaderinc).
		c.a = 0.5
		return c


## 머리카락 껍질. 얼굴 자리(앞쪽, dir.y < face_top, |dir.x| < face_half)는 잘라 내는 대신 머리 속으로 부드럽게 눌러 넣어
## 머리 겉면과 만나는 선이 계단 없이 둥글고, 완전히 파묻힌 면만 뺀다. 아래 끝은 앞(bottom)에서 뒤(bottom_back)로 이어진다.
## shape 는 방향별 반지름 배율 (결·곱슬), scale 은 껍질 반지름 배율.
static func _hair_shell(st: SurfaceTool, color: Variant, face_top: float, face_half: float, bottom: float, bottom_back: float, shape: Callable, scale: Vector3 = Vector3.ONE) -> void:
	var seg: Vector2i = HAIR_SEGMENTS[clampi(detail, 0, MAX_DETAIL)]
	var face: Callable = func(dir: Vector3) -> float:
		return _ramp(face_top + 0.08, face_top - 0.06, dir.y) * _ramp(face_half + 0.08, face_half - 0.06, absf(dir.x)) * _ramp(-0.02, -0.22, dir.z)
	var keep: Callable = func(dir: Vector3) -> bool:
		return float(face.call(dir)) < 0.99 and dir.y > lerpf(bottom, bottom_back, _ramp(-0.05, 0.25, dir.z))
	var flare: Callable = func(dir: Vector3) -> float:
		var jowl: float = 1.0 + HEAD_JOWL * _ramp(0.3, -0.5, dir.y)
		return lerpf(float(shape.call(dir)) * jowl, 0.72, float(face.call(dir)))
	ClayMesh.add_shell(st, HAIR_CENTER, HAIR_RADII * scale, color, keep, flare, seg.x, seg.y)


## from → to 사이에서 0 → 1 로 부드럽게 (from > to 여도 된다).
static func _ramp(from: float, to: float, x: float) -> float:
	var t: float = clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## 머리 모양이 머리(얼굴 뒤쪽과 옆)를 덮는 아래 끝 (머리 중심에서 본 방향의 y). 덮지 않으면 1.
static func _hair_cover_bottom(style: String) -> float:
	match style:
		"long", "bob", "side":
			return -0.45
		"curly", "pigtails":
			return -0.15
	return 1.0


## 일자 앞머리: 이마를 덮고 눈썹 위에서 똑 자른 다섯 다발.
static func _blunt_bangs(st: SurfaceTool, color: Variant) -> void:
	for yaw: float in [-46.0, -23.0, 0.0, 23.0, 46.0]:
		_lock(st, color, yaw, 62.0, 17.0 + absf(yaw) * 0.08, 0.095, 0.04, 0.0, 0.0, 0.03, 0.0, 0.0, 1.0)


## 옆으로 넘긴 앞머리 (direction 1 = 캐릭터 오른쪽 가르마에서 왼쪽으로 넘긴다).
static func _side_bangs(st: SurfaceTool, color: Variant, direction: float) -> void:
	for b: Vector3 in [Vector3(36.0, 22.0, -40.0), Vector3(12.0, 16.0, -32.0), Vector3(-14.0, 18.0, -22.0), Vector3(-40.0, 14.0, -10.0)]:
		_lock(st, color, b.x * direction, 60.0, b.y, 0.09, 0.04, b.z * direction, 0.0, 0.03, 0.04)


## 머리카락 다발 하나: 껍질 위 (yaw, pitch0) 에서 (yaw + sweep, pitch1) 까지 겉면을 따라 내려오고 hang(m) 만큼 더 늘어뜨린다.
## yaw 0 = 정면, 양수 = 캐릭터 오른쪽(+X). pitch 0 = 껍질 중심 높이, 90 = 정수리. width·thick = 뿌리 쪽 옆·두께 반지름.
## lift = 껍질에서 띄우는 비율, flip = 끝을 바깥으로 젖히는 정도, wave = 늘어뜨린 부분의 물결(0~1), blunt = 끝을 똑 자른 정도(0~1).
static func _lock(st: SurfaceTool, color: Variant, yaw: float, pitch0: float, pitch1: float, width: float, thick: float,
		sweep: float = 0.0, hang: float = 0.0, lift: float = 0.03, flip: float = 0.0, wave: float = 0.0, blunt: float = 0.0) -> void:
	var lock_seg: Vector2i = LOCK_SEGMENTS[clampi(detail, 0, MAX_DETAIL)]
	var points: PackedVector3Array = PackedVector3Array()
	var n: int = lock_seg.x
	for k: int in n + 1:
		var u: float = float(k) / float(n)
		var eased: float = u * (2.0 - u)
		points.append(_hair_point(yaw + sweep * eased, lerpf(pitch0, pitch1, u), lift + flip * u * u * u))
	if hang > 0.0:
		var last: Vector3 = points[n]
		var out: Vector3 = Vector3(last.x - HAIR_CENTER.x, 0.0, last.z - HAIR_CENTER.z).normalized()
		var across: Vector3 = Vector3.UP.cross(out)
		var h: int = maxi(2, n / 2)
		for k: int in range(1, h + 1):
			var v: float = float(k) / float(h)
			points.append(last + Vector3(0.0, -hang * v, 0.0) + out * (flip * 0.6 * v * v) + across * (wave * 0.025 * sin(v * PI * 1.5)))
	# 늘어뜨린 다발은 늘어진 부분까지 굵다가 끝에서만 모인다.
	var taper_from: float = 0.72 if hang > 0.0 else 0.5
	var profile: Callable = func(u: float) -> float:
		var root: float = lerpf(0.75, 1.0, minf(u * 5.0, 1.0))
		return root * (1.0 - smoothstep(taper_from, 1.0, u) * (1.0 - blunt * 0.65))
	ClayMesh.add_strand(st, points, width, thick, HAIR_CENTER, color, profile, lock_seg.y, LOCK_LENS)
	# 갈라진 끝: 넓은 다발은 끝쪽 절반에서 가는 가닥 둘이 양옆으로 갈라져 나온다 (한 덩어리로 뭉친 끝 → 머리카락 끝).
	if detail >= 1 and width >= 0.07 and blunt < 0.5:
		_split_tips(st, color, points, width, thick, lock_seg.y)


## 다발 끝에서 양옆으로 살짝 벌어지는 가는 가닥 두 개. points 는 다발의 중심선.
static func _split_tips(st: SurfaceTool, color: Variant, points: PackedVector3Array, width: float, thick: float, sides: int) -> void:
	var count: int = points.size()
	var start: int = count / 2
	for side: float in [-1.0, 1.0]:
		var tip: PackedVector3Array = PackedVector3Array()
		for k: int in range(start, count):
			var v: float = float(k - start) / float(count - 1 - start)
			var t: Vector3 = (points[mini(k + 1, count - 1)] - points[maxi(k - 1, 0)]).normalized()
			var out: Vector3 = (points[k] - HAIR_CENTER).normalized()
			var across: Vector3 = t.cross(out).normalized()
			tip.append(points[k] + across * side * width * (0.4 + 0.25 * v * v) + out * thick * 0.4 * v + t * width * 0.35 * v * v)
		var profile: Callable = func(u: float) -> float:
			return lerpf(0.6, 1.0, minf(u * 4.0, 1.0)) * (1.0 - smoothstep(0.3, 1.0, u))
		ClayMesh.add_strand(st, tip, width * 0.42, thick * 0.7, HAIR_CENTER, color, profile, maxi(4, sides - 3), LOCK_LENS)


## 머리카락 껍질 겉면에서 (yaw, pitch) 자리의 점, lift 비율만큼 바깥으로.
static func _hair_point(yaw: float, pitch: float, lift: float) -> Vector3:
	var a: float = deg_to_rad(yaw)
	var p: float = deg_to_rad(pitch)
	return HAIR_CENTER + Vector3(sin(a) * cos(p) * HAIR_RADII.x, sin(p) * HAIR_RADII.y, -cos(a) * cos(p) * HAIR_RADII.z) * (1.0 + lift)


## 니트 결: 세로 골이 진 듯 줄마다 조금씩 어둡게.
static func _knit(base: Color) -> Callable:
	return func(local: Vector3, normal: Vector3) -> Color:
		var rib: float = sin(atan2(local.z, local.x) * 22.0) * 0.5 + 0.5
		return base.darkened(0.06 * rib + 0.08 * clampf(-normal.y, 0.0, 1.0))
