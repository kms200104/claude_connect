class_name CharacterModel
extends RefCounted
## 캐릭터 메시 공방: 겉모습(CharacterLook)으로 몸·팔·다리·눈·도구 메시를 만든다. 같은 겉모습은 한 번만 만든다.
## 2.5등신 점토 인형 비율 — 큰 머리(단발·짧은 머리·올림머리), 니트 스웨터, 반바지, 부츠.
## 좌표는 리그(Visual) 기준: 발바닥 y = -0.8, 머리 꼭대기 ≈ 0.8, 정면 = -Z.
## 정점 색만 쓰므로 머티리얼은 흰 툰 머티리얼 하나 (캐릭터 하나 = 드로우콜 6: 몸, 눈, 팔 2, 다리 2).

const HEAD_CENTER: Vector3 = Vector3(0.0, 0.4, 0.0)
const HEAD_RADII: Vector3 = Vector3(0.36, 0.34, 0.33)
## 팔·다리 관절 (Visual 기준). 리그 씬의 ArmL/ArmR/LegL/LegR 노드 위치와 같아야 한다.
const SHOULDER: Vector3 = Vector3(0.23, -0.05, 0.0)
const HIP: Vector3 = Vector3(0.1, -0.42, 0.0)
## 어깨에서 손(도구를 쥐는 곳)까지.
const HAND_OFFSET: Vector3 = Vector3(0.0, -0.3, 0.0)
const EYE_CENTER: Vector3 = Vector3(0.0, 0.39, -0.3)

const MOUTH_COLOR: Color = Color("#5A3326")
const NOSE_COLOR: Color = Color("#EE9C80")
const EYE_COLOR: Color = Color("#2B211E")

static var _cache: Dictionary[String, ArrayMesh] = {}


static func body(look: CharacterLook) -> ArrayMesh:
	var key: String = "body|" + look.key()
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	var knit: Callable = _knit(look.top)
	# 스웨터: 아래 단이 살짝 넓고 어깨가 둥근 몸통 + 목폴라 + 밑단 고무단.
	var torso: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -0.37), Vector2(0.2, -0.37), Vector2(0.225, -0.33), Vector2(0.215, -0.22), Vector2(0.225, -0.1),
		Vector2(0.215, -0.02), Vector2(0.16, 0.03), Vector2(0.0, 0.05)])
	ClayMesh.add_lathe(st, torso, 16, Transform3D(), knit)
	ClayMesh.add_torus(st, Vector3(0.0, -0.345, 0.0), 0.205, 0.03, look.top.darkened(0.08), 16, 5)
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.125, 0.115, -0.01, 0.1, 0.03, 1), 12, Transform3D(), _knit(look.top.darkened(0.04)))
	# 반바지: 허리에서 두 다리 통으로 갈라지고, 끝단을 접어 올렸다.
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.205, 0.215, -0.47, -0.3, 0.05, 2), 14, Transform3D(), look.bottom)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.1, 0.1, -0.53, -0.42, 0.03, 1), 8, Transform3D(Basis(), Vector3(HIP.x * side, 0.0, 0.0)), look.bottom)
		ClayMesh.add_torus(st, Vector3(HIP.x * side, -0.525, 0.0), 0.095, 0.022, look.bottom.lightened(0.12), 8, 4)
	# 머리: 살짝 납작한 큰 공.
	ClayMesh.add_ellipsoid(st, HEAD_CENTER, HEAD_RADII, look.skin, 14, 10)
	_add_face(st, look)
	_add_hair(st, look)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 팔 하나 (어깨 기준): 소매 + 소매 끝단 + 손.
static func arm(look: CharacterLook) -> ArrayMesh:
	var key: String = "arm|" + look.key()
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_capsule(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.21, 0.0), 0.068, _knit(look.top), 8, 2)
	ClayMesh.add_torus(st, Vector3(0.0, -0.225, 0.0), 0.06, 0.022, look.top.darkened(0.08), 8, 4)
	ClayMesh.add_ellipsoid(st, HAND_OFFSET + Vector3(0.0, 0.02, 0.0), Vector3(0.062, 0.066, 0.062), look.skin, 8, 5)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 다리 하나 (골반 기준): 짧은 다리 + 접은 단이 있는 부츠.
static func leg(look: CharacterLook) -> ArrayMesh:
	var key: String = "leg|" + look.key()
	if _cache.has(key):
		return _cache[key]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_capsule(st, Vector3(0.0, -0.02, 0.0), Vector3(0.0, -0.2, 0.0), 0.058, look.skin, 6, 1)
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.082, 0.078, -0.37, -0.17, 0.03, 1), 8, Transform3D(), look.shoes)
	ClayMesh.add_torus(st, Vector3(0.0, -0.175, 0.0), 0.08, 0.024, look.shoes.lightened(0.1), 8, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.335, -0.045), Vector3(0.155, 0.09, 0.24), 0.45, look.shoes, Basis(), 8, 4)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
	return mesh


## 두 눈 (반짝이 + 속눈썹 포함). 시선 방향으로 통째로 움직인다 (EYE_CENTER 기준).
static func eyes() -> ArrayMesh:
	if _cache.has("eyes"):
		return _cache["eyes"]
	var st: SurfaceTool = ClayMesh.begin()
	for side: float in [-1.0, 1.0]:
		var x: float = 0.125 * side
		var turn: Basis = Basis(Vector3.UP, -asin(x / HEAD_RADII.x) * 0.9)
		var at: Vector3 = Vector3(x, 0.0, -0.022 + absf(x) * 0.12)
		ClayMesh.add_ellipsoid(st, at, Vector3(0.056, 0.07, 0.028), EYE_COLOR, 10, 5, turn)
		ClayMesh.add_ellipsoid(st, at + turn * Vector3(0.016 * side, 0.026, -0.022), Vector3(0.018, 0.02, 0.01), Color.WHITE, 6, 3, turn)
		ClayMesh.add_ellipsoid(st, at + turn * Vector3(-0.014 * side, -0.03, -0.024), Vector3(0.008, 0.008, 0.006), Color(0.9, 0.9, 0.95), 4, 2, turn)
		# 바깥쪽 위 속눈썹 한 가닥.
		ClayMesh.add_ellipsoid(st, at + turn * Vector3(0.05 * side, 0.05, 0.0), Vector3(0.026, 0.009, 0.012), EYE_COLOR, 6, 3, turn * Basis(Vector3.FORWARD, 0.5 * side))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["eyes"] = mesh
	return mesh


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


## 얼굴: 코, 볼터치, 웃는 입 (눈은 따로 움직이는 메시).
static func _add_face(st: SurfaceTool, look: CharacterLook) -> void:
	ClayMesh.add_ellipsoid(st, _on_head(0.0, 0.315, -0.005), Vector3(0.03, 0.024, 0.022), NOSE_COLOR, 6, 3)
	for side: float in [-1.0, 1.0]:
		var at: Vector3 = _on_head(0.2 * side, 0.3, -0.01)
		ClayMesh.add_ellipsoid(st, at, Vector3(0.058, 0.036, 0.012), look.cheeks, 8, 3, Basis(Vector3.UP, -asin(0.2 * side / HEAD_RADII.x)))
	# 웃는 입: 작은 구슬 다섯 개를 아래로 휜 호 모양으로.
	for i: int in 5:
		var u: float = float(i) / 4.0 * 2.0 - 1.0
		var x: float = u * 0.055
		ClayMesh.add_ellipsoid(st, _on_head(x, 0.255 - 0.022 * (1.0 - u * u), -0.004), Vector3(0.021, 0.012, 0.01), MOUTH_COLOR, 4, 2)


## 머리 겉면 위의 점 (x, y 를 주면 z 를 얼굴 표면에 맞춘다). lift 만큼 바깥으로.
static func _on_head(x: float, y: float, lift: float) -> Vector3:
	var nx: float = x / HEAD_RADII.x
	var ny: float = (y - HEAD_CENTER.y) / HEAD_RADII.y
	var nz: float = sqrt(maxf(1.0 - nx * nx - ny * ny, 0.0))
	return Vector3(x, y, -nz * (HEAD_RADII.z - lift))


## 머리카락: 머리보다 조금 큰 껍질에서 얼굴 자리를 비우고, 앞머리·끝단을 도톰하게 붙인다.
static func _add_hair(st: SurfaceTool, look: CharacterLook) -> void:
	var color: Callable = ClayMesh.vertical_gradient(look.hair.darkened(0.2), look.hair.lightened(0.1), 1.0)
	var center: Vector3 = HEAD_CENTER + Vector3(0.0, 0.035, 0.02)
	match look.hair_style:
		CharacterLook.STYLE_SHORT, CharacterLook.STYLE_BUN:
			var radii: Vector3 = Vector3(0.385, 0.365, 0.37)
			var keep: Callable = func(dir: Vector3) -> bool:
				if dir.z < -0.15 and dir.y < 0.42 and absf(dir.x) < 0.8:
					return false
				return dir.y > (-0.3 if dir.z > 0.0 else -0.05)
			ClayMesh.add_shell(st, center, radii, color, keep, func(_d: Vector3) -> float: return 1.0, 20, 13)
			# 이마 위로 넘긴 앞머리.
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.17, -0.27), Vector3(0.27, 0.08, 0.1), look.hair, 12, 6, Basis(Vector3.RIGHT, 0.5))
			if look.hair_style == CharacterLook.STYLE_BUN:
				ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.36, 0.12), Vector3(0.14, 0.13, 0.14), color, 12, 8, Basis(), ClayMesh.blob_wobble(3, 0.06, 4))
		_:
			# 단발: 턱선까지 내려와 끝이 살짝 퍼지고, 일자 앞머리.
			var radii: Vector3 = Vector3(0.405, 0.37, 0.385)
			var keep: Callable = func(dir: Vector3) -> bool:
				if dir.z < -0.2 and dir.y < 0.3 and absf(dir.x) < 0.74:
					return false
				return dir.y > -0.62
			var flare: Callable = func(dir: Vector3) -> float:
				return 1.0 + 0.1 * clampf(-dir.y, 0.0, 1.0)
			ClayMesh.add_shell(st, center, radii, color, keep, flare, 20, 13)
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.1, -0.3), Vector3(0.3, 0.075, 0.09), look.hair, 14, 6)


## 니트 결: 세로 골이 진 듯 줄마다 조금씩 어둡게.
static func _knit(base: Color) -> Callable:
	return func(local: Vector3, normal: Vector3) -> Color:
		var rib: float = sin(atan2(local.z, local.x) * 22.0) * 0.5 + 0.5
		return base.darkened(0.06 * rib + 0.08 * clampf(-normal.y, 0.0, 1.0))
