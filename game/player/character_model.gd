class_name CharacterModel
extends RefCounted
## 캐릭터 메시 공방: 겉모습(CharacterLook)으로 몸·팔·다리·눈·도구 메시를 만든다. 같은 겉모습은 한 번만 만든다.
## 2.5등신 점토 인형 비율 — 옆으로 살짝 넓은 큰 머리와 작은 귀, 덩어리진 가닥으로 만든 머리(10가지), 니트 스웨터, 반바지, 부츠.
## 눈·코·입은 data/looks/face_parts.json 의 도형을 머리 겉면에 촘촘히 붙인 얇은 판 (FaceShapes).
## 좌표는 리그(Visual) 기준: 발바닥 y = -0.8, 머리 꼭대기 ≈ 0.8, 정면 = -Z.
## 정점 색만 쓰므로 머티리얼은 흰 툰 머티리얼 하나 (캐릭터 하나 = 드로우콜 6: 몸, 눈, 팔 2, 다리 2).

const HEAD_CENTER: Vector3 = Vector3(0.0, 0.4, 0.0)
const HEAD_RADII: Vector3 = Vector3(0.375, 0.34, 0.33)
## 팔·다리 관절 (Visual 기준). 리그 씬의 ArmL/ArmR/LegL/LegR 노드 위치와 같아야 한다.
const SHOULDER: Vector3 = Vector3(0.23, -0.05, 0.0)
const HIP: Vector3 = Vector3(0.1, -0.42, 0.0)
## 어깨에서 손(도구를 쥐는 곳)까지.
const HAND_OFFSET: Vector3 = Vector3(0.0, -0.3, 0.0)
const EYE_CENTER: Vector3 = Vector3(0.0, 0.385, -0.3)

const MOUTH_COLOR: Color = Color("#5A3326")

## 얼굴 부품을 머리 겉면에서 띄우는 거리 (m). 눈은 시선을 따라 머리 중심을 축으로 굴러서(타원체라 최대 3mm 안쪽으로 든다) 더 띄운다.
const CHEEK_LIFT: float = 0.002
const FEATURE_LIFT: float = 0.003
const EYE_LIFT: float = 0.0055
## 같은 부품 안에서 층마다 더 띄우는 거리 (깊이 겹침 방지).
const LAYER_LIFT: float = 0.0009
## 머리 타원체 [둘레 칸, 위아래 칸] — 절약(0) / 고화질(1). 머리카락에 늘 덮이는 정수리·뒤통수 면은 만들지 않는다.
const HEAD_SEGMENTS: Array[Vector2i] = [Vector2i(22, 14), Vector2i(26, 18)]
## 머리카락 껍질 [둘레 칸, 위아래 칸].
const HAIR_SEGMENTS: Array[Vector2i] = [Vector2i(18, 11), Vector2i(22, 13)]
## 머리카락 다발 [마디 수, 단면 꼭짓점 수].
const LOCK_SEGMENTS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(6, 5)]
## 머리카락 껍질의 중심과 반지름 (머리보다 조금 크고 위·뒤로 치우친 타원체). 다발은 이 겉면을 따라 내려온다.
const HAIR_CENTER: Vector3 = Vector3(0.0, 0.43, 0.02)
const HAIR_RADII: Vector3 = Vector3(0.4, 0.365, 0.37)
## 귀 (머리 옆, 눈높이보다 조금 아래).
const EAR_CENTER: Vector3 = Vector3(0.368, 0.355, 0.02)
const EAR_RADII: Vector3 = Vector3(0.034, 0.058, 0.044)

## 0 = 절약, 1 = 고화질 (Quality 가 정한다). 바꾸면 clear_cache() 로 메시를 다시 만든다.
static var detail: int = 1
static var _cache: Dictionary[String, ArrayMesh] = {}


## 화질이 바뀌었을 때: 만들어 둔 메시를 버린다 (리그는 set_look 을 다시 불러 새로 만든다).
static func clear_cache() -> void:
	_cache.clear()


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
	ClayMesh.add_lathe(st, torso, 16, Transform3D(), knit)
	ClayMesh.add_torus(st, Vector3(0.0, -0.345, 0.0), 0.205, 0.03, look.top.darkened(0.08), 16, 4)
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.125, 0.115, -0.01, 0.1, 0.03, 1), 12, Transform3D(), _knit(look.top.darkened(0.04)))
	# 반바지: 허리에서 두 다리 통으로 갈라지고, 끝단을 접어 올렸다.
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.205, 0.215, -0.47, -0.3, 0.05, 2), 14, Transform3D(), look.bottom)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.1, 0.1, -0.53, -0.42, 0.03, 1), 8, Transform3D(Basis(), Vector3(HIP.x * side, 0.0, 0.0)), look.bottom)
		ClayMesh.add_torus(st, Vector3(HIP.x * side, -0.525, 0.0), 0.095, 0.022, look.bottom.lightened(0.12), 8, 4)
	# 머리: 옆으로 살짝 넓은 큰 공. 둘레를 촘촘히 나눠 얼굴 부품과 겉면 사이가 벌어지거나 파묻히지 않게 하고,
	# 어떤 머리 모양이든 덮는 정수리·뒤통수는 비우고, 긴 머리가 덮는 뒤쪽·옆쪽은 더 비운다 (머리카락 껍질이 그 위를 넉넉히 덮는다).
	var head: Vector2i = HEAD_SEGMENTS[clampi(detail, 0, 1)]
	var one: Callable = func(_d: Vector3) -> float: return 1.0
	var cover: float = _hair_cover_bottom(look.hair_style)
	var bare: Callable = func(dir: Vector3) -> bool:
		if dir.y > 0.62 or (dir.z > 0.5 and dir.y > -0.1):
			return false
		return not (dir.y > cover and (dir.z > 0.05 or absf(dir.x) > 0.9))
	ClayMesh.add_shell(st, HEAD_CENTER, HEAD_RADII, look.skin, bare, one, head.x, head.y)
	# 귀: 머리카락이 옆을 다 덮는 긴 머리에서는 만들지 않는다.
	if cover > -0.4:
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_ellipsoid(st, Vector3(EAR_CENTER.x * side, EAR_CENTER.y, EAR_CENTER.z), EAR_RADII, look.skin.darkened(0.03), 7, 4, Basis(Vector3.UP, 0.35 * side))
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
	ClayMesh.add_ellipsoid(st, HAND_OFFSET + Vector3(0.0, 0.02, 0.0), Vector3(0.062, 0.066, 0.062), look.skin, 7, 4)
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
		var anchor: Vector2 = catalog.anchors.get("eye", Vector2(0.17, 0.385))
		var palette: Dictionary[String, Color] = face_palette(l)
		for side: float in [-1.0, 1.0]:
			_emit_face(st, part.layers, palette, Vector2(anchor.x * side, anchor.y), side < 0.0, HEAD_CENTER, EYE_LIFT)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache[key] = mesh
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


## 식칼: 나무 손잡이 + 넓적한 은빛 날. 손에서 +Y 로 뻗는다.
static func knife() -> ArrayMesh:
	if _cache.has("knife"):
		return _cache["knife"]
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.07, 0.0), 0.022, 0.02, Color("#6E452C"), 8)
	var blade: Callable = ClayMesh.vertical_gradient(Color("#9AA6AF"), Color("#E3EAEE"), 1.0)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.17, -0.025), Vector3(0.012, 0.2, 0.075), 0.3, blade, Basis(), 6, 4)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_cache["knife"] = mesh
	return mesh


## 프라이팬: 손잡이 끝에 둥근 팬 (팬 바닥은 손잡이와 직각).
static func pan() -> ArrayMesh:
	if _cache.has("pan"):
		return _cache["pan"]
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
	var cheek: Vector2 = catalog.anchors.get("cheek", Vector2(0.215, 0.32))
	var blush: Array[Dictionary] = [{"shape": "ellipse", "c": [0.0, 0.0], "r": [0.048, 0.03], "color": "cheek"}]
	var brow_at: Vector2 = catalog.anchors.get("brow", Vector2(0.17, 0.47))
	# 눈썹: 머리색보다 짙은 도톰한 선, 바깥 끝이 살짝 내려온다 (x 는 바깥쪽이 +).
	var brow: Array[Dictionary] = [{"shape": "stroke", "pts": [[-0.036, -0.002], [-0.006, 0.007], [0.034, 0.0]], "w": 0.017, "color": "brow"}]
	for side: float in [-1.0, 1.0]:
		_emit_face(st, blush, palette, Vector2(cheek.x * side, cheek.y), side < 0.0, Vector3.ZERO, CHEEK_LIFT)
		_emit_face(st, brow, palette, Vector2(brow_at.x * side, brow_at.y), side < 0.0, Vector3.ZERO, FEATURE_LIFT)
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
	palette["lid"] = look.skin.darkened(0.07)
	palette["brow"] = look.hair.darkened(0.3)
	return palette


## 도형 층들을 머리 겉면에 붙인다. anchor = 부품 자리(얼굴 x, y), mirror = 좌우 뒤집기(왼쪽 눈),
## origin = 정점 좌표의 원점(눈은 머리 중심), lift = 겉면에서 띄우는 거리 (층마다 LAYER_LIFT 씩 더 띄운다).
static func _emit_face(st: SurfaceTool, layers: Array[Dictionary], palette: Dictionary[String, Color], anchor: Vector2, mirror: bool, origin: Vector3, lift: float) -> void:
	var entries: Array[Dictionary] = FaceShapes.triangles(layers, palette, _face_max_edge())
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var tris: PackedVector2Array = entry["tris"]
		var color: Color = entry["color"]
		var dome: Vector3 = entry["dome"]
		var center: Vector2 = entry["center"]
		var layer_lift: float = lift + LAYER_LIFT * float(i)
		for t: int in range(0, tris.size(), 3):
			var pos: Array[Vector3] = []
			var nrm: Array[Vector3] = []
			for k: int in 3:
				var q: Vector2 = tris[t + k]
				pos.append(_feature_point(q, anchor, mirror, layer_lift, center, dome))
				nrm.append(_feature_normal(q, anchor, mirror, layer_lift, center, dome))
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
	var nx: float = x / HEAD_RADII.x
	var ny: float = (y - HEAD_CENTER.y) / HEAD_RADII.y
	var nz: float = sqrt(maxf(1.0 - nx * nx - ny * ny, 0.0))
	var surface: Vector3 = Vector3(x, y, -nz * HEAD_RADII.z)
	return surface + head_normal(surface) * lift


## 머리 타원체의 바깥 법선 (p 는 Visual 좌표).
static func head_normal(p: Vector3) -> Vector3:
	var d: Vector3 = p - HEAD_CENTER
	return Vector3(d.x / (HEAD_RADII.x * HEAD_RADII.x), d.y / (HEAD_RADII.y * HEAD_RADII.y), d.z / (HEAD_RADII.z * HEAD_RADII.z)).normalized()


## 머리 겉면 위의 점 (x, y 를 주면 z 를 얼굴 표면에 맞춘다). lift 만큼 바깥으로.
static func _on_head(x: float, y: float, lift: float) -> Vector3:
	return face_point(x, y, lift)


static func _catalog() -> FaceCatalog:
	return GameData.face if GameData != null else null


## 얼굴 도형 삼각형의 가장 긴 변 (머리 반지름 0.33m 에서 0.045m 변은 가운데가 겉면보다 0.8mm 안쪽).
static func _face_max_edge() -> float:
	return 0.045 if detail >= 1 else 0.055


## 머리카락: 머리보다 조금 큰 껍질(얼굴 자리는 머리 속으로 눌러 넣고, 결을 따라 살짝 골이 진다) 위에 끝이 모이는 도톰한 다발을 얹는다.
## 다발은 껍질 겉면을 따라 내려오다 늘어뜨린다 (_lock). 앞머리·옆머리·뒷머리·묶은 머리가 모양마다 다르다.
static func _add_hair(st: SurfaceTool, look: CharacterLook) -> void:
	var color: Callable = ClayMesh.vertical_gradient(look.hair.darkened(0.2), look.hair.lightened(0.1), 1.0)
	var lock_seg: Vector2i = LOCK_SEGMENTS[clampi(detail, 0, 1)]
	var one: Callable = func(_d: Vector3) -> float: return 1.0
	# 정수리에서 내려오는 결: 둘레를 따라 넓은 골이 진다 (아래로 갈수록 옅다).
	var grooves: Callable = func(dir: Vector3) -> float:
		var around: float = atan2(dir.x, -dir.z)
		return 1.0 + 0.028 * (absf(sin(around * 4.0)) - 0.5) * clampf(dir.y + 0.4, 0.0, 1.0)
	var tie: Color = Color("#F07A8A")
	match look.hair_style:
		"short":
			# 분홍 삐죽 숏컷: 끝이 뾰족한 앞머리가 이리저리 뻗치고, 귀 옆과 목덜미도 뾰족하게.
			_hair_shell(st, color, 0.42, 0.66, -0.05, -0.3, grooves)
			for b: Vector3 in [Vector3(-50.0, 6.0, 12.0), Vector3(-25.0, -10.0, 8.0), Vector3(0.0, 8.0, 6.0), Vector3(25.0, -8.0, 9.0), Vector3(50.0, 10.0, 13.0)]:
				_lock(st, color, b.x, 60.0, b.z, 0.08, 0.04, b.y, 0.0, 0.03, 0.06)
			for side: float in [-1.0, 1.0]:
				_lock(st, color, 80.0 * side, 34.0, -16.0, 0.08, 0.04, 8.0 * side, 0.0, 0.02, 0.08)
			for yaw: float in [150.0, 180.0, 210.0]:
				_lock(st, color, yaw, 10.0, -36.0, 0.09, 0.04, 0.0, 0.03, 0.02, 0.06)
		"bun":
			# 금발 똥머리: 옆으로 넘긴 앞머리, 얼굴 옆에 흘러내린 두 가닥, 정수리 위 동그란 올림머리.
			_hair_shell(st, color, 0.42, 0.66, -0.05, -0.3, grooves)
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
			_hair_shell(st, color, 0.42, 0.66, -0.05, -0.3, one)
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
			_hair_shell(st, color, 0.42, 0.66, -0.05, -0.3, grooves)
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
			_hair_shell(st, color, 0.46, 0.66, -0.02, -0.3, grooves, Vector3(0.97, 0.95, 0.97))
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


## 머리카락 껍질. 얼굴 자리(앞쪽, dir.y < face_top, |dir.x| < face_half)는 잘라 내는 대신 머리 속으로 부드럽게 눌러 넣어
## 머리 겉면과 만나는 선이 계단 없이 둥글고, 완전히 파묻힌 면만 뺀다. 아래 끝은 앞(bottom)에서 뒤(bottom_back)로 이어진다.
## shape 는 방향별 반지름 배율 (결·곱슬), scale 은 껍질 반지름 배율.
static func _hair_shell(st: SurfaceTool, color: Variant, face_top: float, face_half: float, bottom: float, bottom_back: float, shape: Callable, scale: Vector3 = Vector3.ONE) -> void:
	var seg: Vector2i = HAIR_SEGMENTS[clampi(detail, 0, 1)]
	var face: Callable = func(dir: Vector3) -> float:
		return _ramp(face_top + 0.08, face_top - 0.06, dir.y) * _ramp(face_half + 0.08, face_half - 0.06, absf(dir.x)) * _ramp(-0.02, -0.22, dir.z)
	var keep: Callable = func(dir: Vector3) -> bool:
		return float(face.call(dir)) < 0.99 and dir.y > lerpf(bottom, bottom_back, _ramp(-0.05, 0.25, dir.z))
	var flare: Callable = func(dir: Vector3) -> float:
		return lerpf(float(shape.call(dir)), 0.74, float(face.call(dir)))
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
		_lock(st, color, yaw, 62.0, 13.0 + absf(yaw) * 0.08, 0.095, 0.04, 0.0, 0.0, 0.03, 0.0, 0.0, 1.0)


## 옆으로 넘긴 앞머리 (direction 1 = 캐릭터 오른쪽 가르마에서 왼쪽으로 넘긴다).
static func _side_bangs(st: SurfaceTool, color: Variant, direction: float) -> void:
	for b: Vector3 in [Vector3(36.0, 18.0, -40.0), Vector3(12.0, 12.0, -32.0), Vector3(-14.0, 14.0, -22.0), Vector3(-40.0, 10.0, -10.0)]:
		_lock(st, color, b.x * direction, 60.0, b.y, 0.09, 0.04, b.z * direction, 0.0, 0.03, 0.04)


## 머리카락 다발 하나: 껍질 위 (yaw, pitch0) 에서 (yaw + sweep, pitch1) 까지 겉면을 따라 내려오고 hang(m) 만큼 더 늘어뜨린다.
## yaw 0 = 정면, 양수 = 캐릭터 오른쪽(+X). pitch 0 = 껍질 중심 높이, 90 = 정수리. width·thick = 뿌리 쪽 옆·두께 반지름.
## lift = 껍질에서 띄우는 비율, flip = 끝을 바깥으로 젖히는 정도, wave = 늘어뜨린 부분의 물결(0~1), blunt = 끝을 똑 자른 정도(0~1).
static func _lock(st: SurfaceTool, color: Variant, yaw: float, pitch0: float, pitch1: float, width: float, thick: float,
		sweep: float = 0.0, hang: float = 0.0, lift: float = 0.03, flip: float = 0.0, wave: float = 0.0, blunt: float = 0.0) -> void:
	var lock_seg: Vector2i = LOCK_SEGMENTS[clampi(detail, 0, 1)]
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
	ClayMesh.add_strand(st, points, width, thick, HAIR_CENTER, color, profile, lock_seg.y)


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
