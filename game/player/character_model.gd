class_name CharacterModel
extends RefCounted
## 캐릭터 메시 공방: 겉모습(CharacterLook)으로 몸·팔·다리·눈·도구 메시를 만든다. 같은 겉모습은 한 번만 만든다.
## 2.5등신 점토 인형 비율 — 큰 머리(머리 모양 10가지), 니트 스웨터, 반바지, 부츠.
## 눈·코·입은 data/looks/face_parts.json 의 도형을 머리 겉면에 촘촘히 붙인 얇은 판 (FaceShapes).
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

## 얼굴 부품을 머리 겉면에서 띄우는 거리 (m). 눈은 시선을 따라 머리 중심을 축으로 굴러서(타원체라 최대 3mm 안쪽으로 든다) 더 띄운다.
const CHEEK_LIFT: float = 0.002
const FEATURE_LIFT: float = 0.003
const EYE_LIFT: float = 0.0055
## 같은 부품 안에서 층마다 더 띄우는 거리 (깊이 겹침 방지).
const LAYER_LIFT: float = 0.0009
## 머리 타원체 [둘레 칸, 위아래 칸] — 절약(0) / 고화질(1).
const HEAD_SEGMENTS: Array[Vector2i] = [Vector2i(24, 16), Vector2i(28, 20)]
## 머리카락 껍질 [둘레 칸, 위아래 칸].
const HAIR_SEGMENTS: Array[Vector2i] = [Vector2i(20, 13), Vector2i(24, 14)]

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
	# 머리: 살짝 납작한 큰 공. 둘레를 촘촘히 나눠 얼굴 부품과 겉면 사이가 벌어지거나 파묻히지 않게 한다.
	var head: Vector2i = HEAD_SEGMENTS[clampi(detail, 0, 1)]
	ClayMesh.add_ellipsoid(st, HEAD_CENTER, HEAD_RADII, look.skin, head.x, head.y)
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
		var anchor: Vector2 = catalog.anchors.get("eye", Vector2(0.125, 0.39))
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


## 얼굴: 볼터치, 코, 입 (눈은 따로 움직이는 메시). 모두 머리 겉면에 붙인 얇은 판이라 머리 속으로 파묻히지 않는다.
static func _add_face(st: SurfaceTool, look: CharacterLook) -> void:
	var catalog: FaceCatalog = _catalog()
	if catalog == null:
		return
	var palette: Dictionary[String, Color] = face_palette(look)
	var cheek: Vector2 = catalog.anchors.get("cheek", Vector2(0.2, 0.3))
	var blush: Array[Dictionary] = [{"shape": "ellipse", "c": [0.0, 0.0], "r": [0.058, 0.036], "color": "cheek"}]
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


## 머리카락: 머리보다 조금 큰 껍질에서 얼굴 자리를 비우고, 앞머리·끝단·묶은 머리를 도톰하게 붙인다.
static func _add_hair(st: SurfaceTool, look: CharacterLook) -> void:
	var color: Callable = ClayMesh.vertical_gradient(look.hair.darkened(0.2), look.hair.lightened(0.1), 1.0)
	var center: Vector3 = HEAD_CENTER + Vector3(0.0, 0.035, 0.02)
	var seg: Vector2i = HAIR_SEGMENTS[clampi(detail, 0, 1)]
	var one: Callable = func(_d: Vector3) -> float: return 1.0
	# 짧은 머리 껍질: 이마 위로 얼굴을 비우고, 뒤로는 목덜미까지.
	var short_keep: Callable = func(dir: Vector3) -> bool:
		if dir.z < -0.15 and dir.y < 0.42 and absf(dir.x) < 0.8:
			return false
		return dir.y > (-0.3 if dir.z > 0.0 else -0.05)
	# 단발 껍질: 턱선까지 내려오고 얼굴만 비운다.
	var bob_keep: Callable = func(dir: Vector3) -> bool:
		if dir.z < -0.2 and dir.y < 0.3 and absf(dir.x) < 0.74:
			return false
		return dir.y > -0.62
	var flare: Callable = func(dir: Vector3) -> float:
		return 1.0 + 0.1 * clampf(-dir.y, 0.0, 1.0)
	var tie: Color = Color("#F07A8A")
	match look.hair_style:
		"short", "bun":
			ClayMesh.add_shell(st, center, Vector3(0.385, 0.365, 0.37), color, short_keep, one, seg.x, seg.y)
			# 이마 위로 넘긴 앞머리.
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.17, -0.27), Vector3(0.27, 0.08, 0.1), look.hair, 12, 6, Basis(Vector3.RIGHT, 0.5))
			if look.hair_style == "bun":
				ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.36, 0.12), Vector3(0.14, 0.13, 0.14), color, 12, 8, Basis(), ClayMesh.blob_wobble(3, 0.06, 4))
		"long":
			ClayMesh.add_shell(st, center, Vector3(0.405, 0.37, 0.385), color, bob_keep, one, seg.x, seg.y)
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.1, -0.3), Vector3(0.3, 0.075, 0.09), look.hair, 12, 5)
			# 등 뒤로 어깨까지 내려오는 머리와 얼굴 옆으로 흘러내린 두 가닥.
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, -0.24, 0.16), Vector3(0.37, 0.36, 0.2), color, 10, 6)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_ellipsoid(st, center + Vector3(0.345 * side, -0.2, -0.1), Vector3(0.075, 0.26, 0.1), color, 6, 5)
		"pigtails":
			var pig_keep: Callable = func(dir: Vector3) -> bool:
				if dir.z < -0.2 and dir.y < 0.3 and absf(dir.x) < 0.74:
					return false
				return dir.y > -0.32
			ClayMesh.add_shell(st, center, Vector3(0.4, 0.37, 0.385), color, pig_keep, one, seg.x, seg.y)
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.1, -0.3), Vector3(0.3, 0.075, 0.09), look.hair, 12, 5)
			for side: float in [-1.0, 1.0]:
				ClayMesh.add_ellipsoid(st, center + Vector3(0.46 * side, -0.16, 0.08), Vector3(0.11, 0.25, 0.11), color, 10, 6, Basis(Vector3.FORWARD, -0.35 * side))
				ClayMesh.add_ellipsoid(st, center + Vector3(0.39 * side, 0.03, 0.07), Vector3(0.05, 0.05, 0.05), tie, 6, 4)
		"ponytail":
			ClayMesh.add_shell(st, center, Vector3(0.39, 0.367, 0.375), color, short_keep, one, seg.x, seg.y)
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.12, -0.3), Vector3(0.29, 0.075, 0.09), look.hair, 14, 6, Basis(Vector3.RIGHT, 0.25))
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, -0.02, 0.48), Vector3(0.11, 0.27, 0.11), color, 10, 6, Basis(Vector3.RIGHT, 0.45))
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.19, 0.37), Vector3(0.055, 0.055, 0.055), tie, 6, 4)
		"curly":
			# 뽀글 파마: 껍질 겉면을 방향마다 울퉁불퉁하게 부풀린다.
			var curl: Callable = func(dir: Vector3) -> float:
				return 1.04 + 0.07 * sin(dir.x * 13.0 + 1.0) * sin(dir.y * 11.0) * sin(dir.z * 12.0 + 0.5) + 0.04 * clampf(-dir.y, 0.0, 1.0)
			var curly_keep: Callable = func(dir: Vector3) -> bool:
				if dir.z < -0.18 and dir.y < 0.36 and absf(dir.x) < 0.76:
					return false
				return dir.y > (-0.42 if dir.z > -0.2 else -0.1)
			ClayMesh.add_shell(st, center, Vector3(0.4, 0.38, 0.39), color, curly_keep, curl, seg.x + 2, seg.y + 1)
			for i: int in 4:
				var x: float = -0.2 + 0.4 * float(i) / 3.0
				ClayMesh.add_ellipsoid(st, center + Vector3(x, 0.15 + 0.02 * float(i % 2), -0.3 + absf(x) * 0.18), Vector3(0.085, 0.07, 0.07), color, 8, 5)
		"spiky":
			ClayMesh.add_shell(st, center, Vector3(0.38, 0.362, 0.368), color, short_keep, one, seg.x, seg.y)
			var spikes: Array[Vector3] = [Vector3(0.0, 1.0, -0.1), Vector3(0.5, 0.8, -0.05), Vector3(-0.5, 0.8, -0.05), Vector3(0.0, 0.8, 0.55),
				Vector3(0.45, 0.6, 0.55), Vector3(-0.45, 0.6, 0.55), Vector3(0.25, 0.75, -0.55), Vector3(-0.25, 0.75, -0.55)]
			for d: Vector3 in spikes:
				var dir: Vector3 = d.normalized()
				var base: Vector3 = center + dir * Vector3(0.33, 0.31, 0.32)
				ClayMesh.add_rod(st, base, base + dir * 0.17, 0.075, 0.006, color, 5)
		"side":
			ClayMesh.add_shell(st, center, Vector3(0.4, 0.37, 0.385), color, bob_keep, flare, seg.x, seg.y)
			# 한쪽으로 비스듬히 넘긴 앞머리.
			ClayMesh.add_ellipsoid(st, center + Vector3(0.07, 0.12, -0.29), Vector3(0.3, 0.085, 0.1), look.hair, 14, 6, Basis(Vector3.FORWARD, -0.28) * Basis(Vector3.RIGHT, 0.3))
		"buzz":
			var buzz_keep: Callable = func(dir: Vector3) -> bool:
				if dir.z < -0.1 and dir.y < 0.5:
					return false
				return dir.y > (-0.5 if dir.z > 0.2 else 0.0)
			ClayMesh.add_shell(st, center, Vector3(0.373, 0.353, 0.346), ClayMesh.vertical_gradient(look.hair.darkened(0.1), look.hair.lightened(0.15), 1.0), buzz_keep, one, seg.x, seg.y)
		_:
			# 단발: 턱선까지 내려와 끝이 살짝 퍼지고, 일자 앞머리.
			ClayMesh.add_shell(st, center, Vector3(0.405, 0.37, 0.385), color, bob_keep, flare, seg.x, seg.y)
			ClayMesh.add_ellipsoid(st, center + Vector3(0.0, 0.1, -0.3), Vector3(0.3, 0.075, 0.09), look.hair, 12, 5)


## 니트 결: 세로 골이 진 듯 줄마다 조금씩 어둡게.
static func _knit(base: Color) -> Callable:
	return func(local: Vector3, normal: Vector3) -> Color:
		var rib: float = sin(atan2(local.z, local.x) * 22.0) * 0.5 + 0.5
		return base.darkened(0.06 * rib + 0.08 * clampf(-normal.y, 0.0, 1.0))
