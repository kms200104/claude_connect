class_name DeliveryRobot
extends Node3D
## 탈것 배달 로봇 "솔봇" (v0.17): 탈것을 부르면 이 로봇이 그 탈것을 몰고 와 세워 두고, 손을 흔든 뒤 날아서 돌아간다 (VehicleCourier).
## 배달 알바 복장과 같은 색 (파란 모자 · 청록 보냉 상자에 "배달의 솔"). 다리 대신 아래의 추진기로 떠 있다.
## - 머리: 둥근 흰 상자에 어두운 화면, 화면 속 하늘색 LED 눈 (보통 · 웃음 ^ ^ · 깜빡임), 귀 모양 센서, 배달 모자, 깜빡이는 안테나.
## - 몸통: 흰 몸에 파란 배 판 · 가슴 불빛, 등에 청록 보냉 상자, 아래는 추진기 (빛나는 고리 · 바람 기둥).
## - 팔: 어깨 · 팔꿈치 두 마디. 손이 닿을 자리(hold · 흔들기 · 쉬는 자세)를 정하면 두 마디 IK 로 팔을 굽힌다.
## 좌표: 바닥(추진기 아래) = 원점, 앞 = -Z, 키 약 1.1m (주민과 비슷).

enum Face { NORMAL, HAPPY, BLINK }

const WHITE: Color = Color("#EEF2F7")
const PEARL: Color = Color("#D5DDE8")
const BLUE: Color = Color("#2F6FD6")
const BLUE_DARK: Color = Color("#1B4A9A")
const TEAL: Color = Color("#1E9C98")
const TEAL_LIGHT: Color = Color("#2EC4BF")
const TEAL_DARK: Color = Color("#178480")
const GRAPHITE: Color = Color("#2B3038")
const STEEL: Color = Color("#8C97A6")
const SCREEN: Color = Color("#0F1A29")
const LED: Color = Color("#7FF3FF")
const AMBER: Color = Color("#FFB547")
const TEXT: String = "배달의 솔"

## 어깨 자리 (오른쪽, 왼쪽은 x 를 뒤집는다) · 위팔 · 아래팔 길이 (손 가운데까지).
const SHOULDER: Vector3 = Vector3(0.255, 0.445, -0.01)
const UPPER: float = 0.17
const FORE: float = 0.185
## 목 (머리 마디의 원점).
const NECK: Vector3 = Vector3(0.0, 0.56, 0.0)
## 머리 상자 (머리 마디 기준).
const HEAD_CENTER: Vector3 = Vector3(0.0, 0.2, 0.0)
const HEAD_SIZE: Vector3 = Vector3(0.5, 0.38, 0.42)
## 화면 앞면 (LED 를 붙이는 z).
const SCREEN_Z: float = -0.228
## 등의 보냉 상자.
const BOX_CENTER: Vector3 = Vector3(0.0, 0.36, 0.25)
const BOX_SIZE: Vector3 = Vector3(0.38, 0.34, 0.22)
## 떠 있을 때 몸이 오르내리는 폭 (m).
const BOB: float = 0.022
## 바닥(원점)에서 추진기까지 뜬 높이 — 그 아래로 바람 기둥이 나온다. 탈것 위에서는 VehicleCourier 가 이만큼 내려 앉힌다.
const GROUND_GAP: float = 0.14

static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _led_material: StandardMaterial3D = null
static var _amber_material: StandardMaterial3D = null
static var _jet_material: StandardMaterial3D = null

## 추진 세기 (0 = 떠 있기만, 1 = 날아오름: 바람 기둥이 길고 밝다).
var thrust: float = 0.0
## 옆으로 기울기 (라디안, 탈것이 돌 때).
var lean: float = 0.0

var _hover: Node3D = null
var _head: Node3D = null
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _faces: Dictionary[int, MeshInstance3D] = {}
var _antenna_tip: MeshInstance3D = null
var _chest: MeshInstance3D = null
var _jet: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _riding: String = ""
## 손이 닿을 자리 (월드). INF = 쉬는 자세.
var _grips: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _waving: bool = false
var _time: float = 0.0
var _blink_in: float = 2.4
var _face: Face = Face.NORMAL
var _face_hold: float = 0.0
var _base_face: Face = Face.NORMAL


func _init() -> void:
	name = "DeliveryRobot"


## 모양 만들기 (clay = 캐릭터와 같은 점토 머티리얼).
func build(clay: Material) -> void:
	_hover = Node3D.new()
	_hover.name = "Hover"
	add_child(_hover)
	_mesh_node("Body", _mesh("body"), _hover, clay)
	# 등 보냉 상자의 글씨 (배달 알바 가방과 같은 글씨 · 머티리얼).
	var text: TextMesh = TextMesh.new()
	text.text = TEXT
	text.font_size = 64
	text.depth = 0.006
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font: Font = ThemeDB.fallback_font
	var px: Vector2 = font.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, text.font_size) if font != null else Vector2(320, 64)
	text.pixel_size = minf((BOX_SIZE.x - 0.07) / maxf(px.x, 1.0), 0.085 / maxf(px.y, 1.0))
	var label: MeshInstance3D = MeshInstance3D.new()
	label.name = "BoxText"
	label.mesh = text
	label.material_override = CharacterRig._uniform_text_material(clay)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 등 쪽(+Z) 면에 (글씨 앞면이 +Z 를 본다).
	label.position = BOX_CENTER + Vector3(0.0, 0.01, BOX_SIZE.z * 0.5 + 0.004)
	_hover.add_child(label)
	_chest = _mesh_node("ChestLight", _mesh("chest_light"), _hover, _amber())
	_chest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring = _mesh_node("JetRing", _mesh("jet_ring"), _hover, _led())
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jet = _mesh_node("Jet", _mesh("jet"), _hover, _jet_mat())
	_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 머리 (목을 축으로 갸웃).
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = NECK
	_hover.add_child(_head)
	_mesh_node("HeadMesh", _mesh("head"), _head, clay)
	_antenna_tip = _mesh_node("AntennaTip", _mesh("antenna_tip"), _head, _amber())
	_antenna_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for face: int in [Face.NORMAL, Face.HAPPY, Face.BLINK]:
		var mi: MeshInstance3D = _mesh_node("Face%d" % face, _mesh("face%d" % face), _head, _led())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_faces[face] = mi
	# 팔 두 개 (어깨 → 팔꿈치 → 손).
	for side: float in [-1.0, 1.0]:
		var shoulder: Node3D = Node3D.new()
		shoulder.name = "ShoulderL" if side < 0.0 else "ShoulderR"
		shoulder.position = Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
		_hover.add_child(shoulder)
		_mesh_node("UpperArm", _mesh("upper_arm"), shoulder, clay)
		var elbow: Node3D = Node3D.new()
		elbow.name = "Elbow"
		elbow.position = Vector3(0.0, -UPPER, 0.0)
		shoulder.add_child(elbow)
		_mesh_node("Forearm", _mesh("forearm_l" if side < 0.0 else "forearm_r"), elbow, clay)
		_shoulders.append(shoulder)
		_elbows.append(elbow)
	_show_face(Face.NORMAL)
	_pose(0.0)


## 탈것에 탄다 (kind = bike · moto · boat …, 빈 문자열 = 내림).
func ride(kind: String) -> void:
	_riding = kind
	if kind.is_empty():
		release()


func riding_kind() -> String:
	return _riding


## 두 손을 이 자리(월드)에 둔다 — 핸들 손잡이. 매 프레임 불러 따라가게 한다.
func hold(left: Vector3, right: Vector3) -> void:
	_grips = [left, right]


func release() -> void:
	_grips = [Vector3.INF, Vector3.INF]


## 오른손을 흔든다 (그동안 웃는 눈).
func wave(on: bool) -> void:
	_waving = on
	_base_face = Face.HAPPY if on else Face.NORMAL
	_show_face(_base_face)


## 잠깐 이 얼굴 (hold 초 뒤 원래 얼굴로).
func set_face(face: Face, hold_s: float = 1.0) -> void:
	_face_hold = hold_s
	_show_face(face)


func _process(delta: float) -> void:
	if _hover == null:
		return
	_time += delta
	_pose(delta)


func _pose(delta: float) -> void:
	# 떠 있기: 천천히 오르내리고, 기울기는 몸 전체 (추진기 축).
	var bob: float = sin(_time * 2.4) * BOB * (0.4 if not _riding.is_empty() else 1.0)
	var pitch: float = -0.12 * thrust - (0.1 if not _riding.is_empty() else 0.0)
	_hover.transform = Transform3D(Basis(Vector3.BACK, lean) * Basis(Vector3.RIGHT, pitch), Vector3(0.0, GROUND_GAP + bob, 0.0))
	# 머리: 살짝 갸웃 (손 흔들 땐 더).
	var tilt: float = sin(_time * 1.3) * 0.05 + (0.16 * sin(_time * 3.0) if _waving else 0.0)
	_head.rotation = Vector3(sin(_time * 0.9) * 0.03, sin(_time * 0.7) * 0.08, tilt)
	# 안테나 불빛: 1.2초마다 반짝.
	var blink: float = fmod(_time, 1.2)
	_antenna_tip.scale = Vector3.ONE * (1.25 if blink < 0.18 else 0.9)
	_chest.scale = Vector3.ONE * (1.0 + 0.06 * sin(_time * 5.0))
	# 추진기: 떠 있을 땐 짧고 흔들리는 바람 기둥, 날아오를 땐 길게.
	var flicker: float = 0.92 + 0.08 * sin(_time * 37.0) * sin(_time * 23.0)
	var jet_len: float = (0.25 if not _riding.is_empty() else 0.55) + 1.9 * thrust
	_jet.scale = Vector3(1.0 + 0.15 * thrust, jet_len * flicker, 1.0 + 0.15 * thrust)
	_ring.scale = Vector3.ONE * (1.0 + 0.05 * thrust)
	# 눈 깜빡임 · 잠깐 얼굴.
	if _face_hold > 0.0:
		_face_hold -= delta
		if _face_hold <= 0.0:
			_show_face(_base_face)
	elif _base_face == Face.NORMAL:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_show_face(Face.BLINK)
			_face_hold = 0.12
			_blink_in = randf_range(2.0, 4.2)
	# 팔: 손이 닿을 자리 → 두 마디 IK.
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var target: Vector3
		var pole: Vector3
		if _grips[i] != Vector3.INF and is_inside_tree():
			target = _hover.global_transform.affine_inverse() * _grips[i]
			# 핸들을 잡으면 팔꿈치는 바깥 · 아래로.
			pole = Vector3(side * 0.9, -0.5, 0.25)
		elif _waving and side > 0.0:
			target = Vector3(0.36 + 0.06 * sin(_time * 11.0), 0.74 + 0.02 * cos(_time * 11.0), -0.1)
			pole = Vector3(1.0, -0.4, 0.3)
		elif thrust > 0.3:
			# 날아갈 때: 팔을 뒤로 젖힌다.
			target = Vector3(side * 0.31, 0.26, 0.14)
			pole = Vector3(side * 0.4, -0.2, -0.9)
		else:
			target = Vector3(side * 0.3, 0.17 + 0.012 * sin(_time * 2.4 + side), -0.06)
			pole = Vector3(side * 0.45, -0.1, 0.9)
		_solve_arm(i, target, pole)


## 두 마디 IK: 어깨에서 target 까지, 팔꿈치는 pole 쪽으로 굽는다 (모두 Hover 좌표).
func _solve_arm(i: int, target: Vector3, pole: Vector3) -> void:
	var shoulder: Node3D = _shoulders[i]
	var s: Vector3 = shoulder.position
	var to: Vector3 = target - s
	var d: float = clampf(to.length(), 0.04, UPPER + FORE - 0.002)
	var u: Vector3 = to.normalized() if to.length() > 0.0001 else Vector3.DOWN
	var cos_a: float = clampf((UPPER * UPPER + d * d - FORE * FORE) / (2.0 * UPPER * d), -1.0, 1.0)
	var v: Vector3 = (pole - u * pole.dot(u))
	v = v.normalized() if v.length() > 0.0001 else Vector3.BACK
	var elbow: Vector3 = s + UPPER * (u * cos_a + v * sqrt(1.0 - cos_a * cos_a))
	var hand: Vector3 = s + u * d
	var b1: Basis = _aim(s, elbow, v)
	var b2: Basis = _aim(elbow, hand, v)
	shoulder.basis = b1
	_elbows[i].basis = b1.inverse() * b2


## -Y 가 from → to 를 향하는 기저 (hint 쪽이 +Z 에 가깝게).
static func _aim(from: Vector3, to: Vector3, hint: Vector3) -> Basis:
	var y: Vector3 = (from - to).normalized()
	var x: Vector3 = y.cross(hint)
	if x.length() < 0.0001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)


func _show_face(face: Face) -> void:
	_face = face
	for key: int in _faces:
		_faces[key].visible = key == face


func _mesh_node(node_name: String, mesh: Mesh, parent: Node3D, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	return mi


# ---- 머티리얼 (LED · 불빛 · 추진기: 낮에도 빛나 보이게 그림자 없이) ----

static func _led() -> StandardMaterial3D:
	if _led_material == null:
		_led_material = StandardMaterial3D.new()
		_led_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_led_material.vertex_color_use_as_albedo = true
		_led_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _led_material


static func _amber() -> StandardMaterial3D:
	if _amber_material == null:
		_amber_material = StandardMaterial3D.new()
		_amber_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_amber_material.albedo_color = AMBER
	return _amber_material


static func _jet_mat() -> StandardMaterial3D:
	if _jet_material == null:
		_jet_material = StandardMaterial3D.new()
		_jet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_jet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_jet_material.vertex_color_use_as_albedo = true
		_jet_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_jet_material.no_depth_test = false
	return _jet_material


# ---- 모양 (한 번 빚어 모든 로봇이 나눠 쓴다) ----

static func _mesh(part: String) -> ArrayMesh:
	if _meshes.has(part):
		return _meshes[part]
	var st: SurfaceTool = ClayMesh.begin()
	match part:
		"body":
			_add_body(st)
		"head":
			_add_head(st)
		"upper_arm":
			# 어깨 공(파랑) · 흰 위팔 · 팔꿈치 마디(쇠).
			ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(0.062, 0.062, 0.062), BLUE, 24, 14)
			ClayMesh.add_capsule(st, Vector3(0.0, -0.02, 0.0), Vector3(0.0, -UPPER + 0.02, 0.0), 0.043, WHITE, 20, 5)
			ClayMesh.add_torus(st, Vector3(0.0, -0.055, 0.0), 0.044, 0.007, PEARL, 24, 6)
			ClayMesh.add_ellipsoid(st, Vector3(0.0, -UPPER, 0.0), Vector3(0.045, 0.045, 0.045), STEEL, 20, 12)
		"forearm_l", "forearm_r":
			var side: float = -1.0 if part == "forearm_l" else 1.0
			ClayMesh.add_capsule(st, Vector3(0.0, -0.01, 0.0), Vector3(0.0, -FORE + 0.06, 0.0), 0.041, WHITE, 20, 5)
			# 파란 소매 띠.
			ClayMesh.add_torus(st, Vector3(0.0, -FORE + 0.07, 0.0), 0.043, 0.011, BLUE, 24, 8)
			# 손: 둥근 장갑 + 엄지 (손바닥이 안쪽).
			var palm: Vector3 = Vector3(0.0, -FORE, 0.0)
			ClayMesh.add_ellipsoid(st, palm, Vector3(0.047, 0.056, 0.05), GRAPHITE, 22, 12)
			ClayMesh.add_ellipsoid(st, palm + Vector3(-side * 0.032, 0.012, -0.03), Vector3(0.018, 0.03, 0.019), GRAPHITE, 14, 8, Basis(Vector3.BACK, side * 0.5))
			ClayMesh.add_torus(st, palm + Vector3(0.0, 0.042, 0.0), 0.04, 0.008, GRAPHITE, 20, 6)
		"chest_light":
			ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.452, -0.196), Vector3(0.024, 0.024, 0.012), AMBER, 18, 10)
		"antenna_tip":
			ClayMesh.add_ellipsoid(st, Vector3(0.11, 0.53, 0.05), Vector3(0.028, 0.028, 0.028), AMBER, 18, 10)
		"jet_ring":
			ClayMesh.add_torus(st, Vector3(0.0, 0.035, 0.0), 0.1, 0.012, LED, 32, 8)
		"jet":
			_add_jet(st)
		"face0":
			# 보통: 세로로 긴 둥근 네모 눈 둘.
			for side: float in [-1.0, 1.0]:
				_flat_rrect(st, Vector2(side * 0.085, HEAD_CENTER.y + 0.012), Vector2(0.058, 0.084), 0.026, SCREEN_Z, LED)
			_flat_stroke(st, _arc(Vector2(0.0, HEAD_CENTER.y - 0.062), 0.03, 200.0, 340.0, 8), 0.012, SCREEN_Z, LED.darkened(0.15))
		"face1":
			# 웃음: ^ ^ 눈 + 크게 웃는 입.
			for side: float in [-1.0, 1.0]:
				var c: Vector2 = Vector2(side * 0.085, HEAD_CENTER.y + 0.0)
				_flat_stroke(st, PackedVector2Array([c + Vector2(-0.034, -0.012), c + Vector2(0.0, 0.026), c + Vector2(0.034, -0.012)]), 0.019, SCREEN_Z, LED)
			_flat_stroke(st, _arc(Vector2(0.0, HEAD_CENTER.y - 0.05), 0.045, 200.0, 340.0, 10), 0.016, SCREEN_Z, LED)
			# 볼 (분홍 LED).
			for side: float in [-1.0, 1.0]:
				_flat_rrect(st, Vector2(side * 0.14, HEAD_CENTER.y - 0.04), Vector2(0.04, 0.018), 0.009, SCREEN_Z, Color("#FF8FB8"))
		"face2":
			# 깜빡임: 가로 줄.
			for side: float in [-1.0, 1.0]:
				_flat_rrect(st, Vector2(side * 0.085, HEAD_CENTER.y + 0.004), Vector2(0.062, 0.013), 0.006, SCREEN_Z, LED)
			_flat_stroke(st, _arc(Vector2(0.0, HEAD_CENTER.y - 0.062), 0.03, 200.0, 340.0, 8), 0.012, SCREEN_Z, LED.darkened(0.15))
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_meshes[part] = mesh
	return mesh


## 몸통: 추진기 치마 · 둥근 몸 · 파란 배 판 · 옆 환기구 · 어깨 받침 · 목 · 등의 보냉 상자.
static func _add_body(st: SurfaceTool) -> void:
	# 추진기: 아래로 좁아지는 쇠 치마 + 파란 테.
	var skirt: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.02), Vector2(0.085, 0.02), Vector2(0.12, 0.035), Vector2(0.165, 0.09), Vector2(0.185, 0.13), Vector2(0.17, 0.15), Vector2(0.0, 0.15)])
	ClayMesh.add_lathe(st, skirt, 40, Transform3D(), GRAPHITE)
	ClayMesh.add_torus(st, Vector3(0.0, 0.135, 0.0), 0.183, 0.016, BLUE, 40, 8)
	# 노즐 안쪽 (어둡게) — 빛나는 고리가 그 둘레에 붙는다.
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.03), Vector2(0.07, 0.03), Vector2(0.09, 0.045), Vector2(0.0, 0.045)]), 32, Transform3D(), Color("#14181E"))
	# 몸: 아래가 좁고 가슴이 넓은 둥근 통.
	var torso: PackedVector2Array = PackedVector2Array()
	var rows: int = 14
	for k: int in rows + 1:
		var t: float = float(k) / float(rows)
		var y: float = lerpf(0.13, 0.55, t)
		var r: float = 0.17 + 0.07 * sin(PI * clampf(t * 0.85 + 0.1, 0.0, 1.0))
		# 위아래를 둥글게 닫는다.
		var cap: float = sqrt(clampf(1.0 - pow((t - 0.5) / 0.5, 8.0), 0.0, 1.0))
		torso.append(Vector2(r * cap, y))
	torso.insert(0, Vector2(0.0, 0.13))
	torso.append(Vector2(0.0, 0.55))
	ClayMesh.add_lathe(st, torso, 48, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.86)), Vector3.ZERO), ClayMesh.vertical_gradient(PEARL, WHITE, 2.0))
	# 허리 띠 (몸통과 추진기 사이).
	ClayMesh.add_torus(st, Vector3(0.0, 0.17, 0.0), 0.185, 0.02, STEEL, 40, 8, Basis.from_scale(Vector3(1.0, 1.0, 0.88)))
	# 파란 배 판 · 가슴 불빛 테 · 배달 표시 (흰 화살 상자).
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.305, -0.198), Vector3(0.24, 0.17, 0.05), 0.35, BLUE, Basis(Vector3.RIGHT, -0.08), 24, 12)
	ClayMesh.add_torus(st, Vector3(0.0, 0.452, -0.19), 0.031, 0.007, STEEL, 24, 6, Basis(Vector3.RIGHT, PI * 0.5))
	_add_parcel_mark(st, Vector3(0.0, 0.3, -0.226))
	# 옆 환기구 (가는 홈 셋).
	for side: float in [-1.0, 1.0]:
		for k: int in 3:
			ClayMesh.add_rounded_box(st, Vector3(side * 0.225, 0.27 + 0.035 * float(k), -0.01), Vector3(0.012, 0.016, 0.1), 0.4, STEEL, Basis(Vector3.FORWARD, side * 0.25), 12, 6)
	# 어깨 받침 (팔이 끼는 둥근 홈).
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_torus(st, Vector3(side * 0.232, SHOULDER.y, SHOULDER.z), 0.05, 0.016, STEEL, 24, 8, Basis(Vector3.BACK, PI * 0.5))
	# 목.
	ClayMesh.add_rod(st, Vector3(0.0, 0.53, 0.0), NECK + Vector3(0.0, 0.04, 0.0), 0.06, 0.055, GRAPHITE, 24)
	ClayMesh.add_torus(st, NECK + Vector3(0.0, 0.0, 0.0), 0.062, 0.012, STEEL, 24, 6)
	# 등의 보냉 상자 (배달 알바 가방과 같은 청록) · 뚜껑 띠 · 손잡이 · 받침 걸쇠.
	ClayMesh.add_rounded_box(st, BOX_CENTER, BOX_SIZE, 0.18, ClayMesh.vertical_gradient(TEAL, TEAL_LIGHT, 1.0), Basis(), 28, 14)
	ClayMesh.add_rounded_box(st, BOX_CENTER + Vector3(0.0, BOX_SIZE.y * 0.5 - 0.01, 0.0), Vector3(BOX_SIZE.x + 0.016, 0.05, BOX_SIZE.z + 0.016), 0.4, TEAL_DARK, Basis(), 24, 8)
	ClayMesh.add_capsule(st, BOX_CENTER + Vector3(-0.07, BOX_SIZE.y * 0.5 + 0.028, 0.0), BOX_CENTER + Vector3(0.07, BOX_SIZE.y * 0.5 + 0.028, 0.0), 0.012, GRAPHITE, 12, 3)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rod(st, BOX_CENTER + Vector3(side * 0.07, BOX_SIZE.y * 0.5 + 0.028, 0.0), BOX_CENTER + Vector3(side * 0.07, BOX_SIZE.y * 0.5 + 0.005, 0.0), 0.009, 0.009, GRAPHITE, 10)
		ClayMesh.add_rounded_box(st, Vector3(side * 0.11, 0.36, 0.13), Vector3(0.05, 0.09, 0.04), 0.4, STEEL, Basis(), 12, 6)
	# 상자 옆의 반사 띠 (밤길 안전).
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rounded_box(st, BOX_CENTER + Vector3(side * (BOX_SIZE.x * 0.5 + 0.002), -0.06, 0.0), Vector3(0.008, 0.035, BOX_SIZE.z * 0.8), 0.4, Color("#F2F4F6"), Basis(), 12, 6)


## 배 판의 배달 표시: 작은 상자와 앞으로 가는 화살.
static func _add_parcel_mark(st: SurfaceTool, at: Vector3) -> void:
	# 앞에서 보면 [상자 →] (로봇의 +X 가 보는 사람의 왼쪽).
	ClayMesh.add_rounded_box(st, at + Vector3(0.03, 0.0, 0.0), Vector3(0.07, 0.06, 0.012), 0.3, WHITE, Basis(), 12, 6)
	ClayMesh.add_rounded_box(st, at + Vector3(0.03, 0.0, -0.004), Vector3(0.012, 0.062, 0.008), 0.4, BLUE_DARK, Basis(), 8, 4)
	ClayMesh.add_rounded_box(st, at + Vector3(-0.045, 0.0, 0.0), Vector3(0.05, 0.014, 0.01), 0.4, WHITE, Basis(), 10, 4)
	ClayMesh.add_rounded_box(st, at + Vector3(-0.068, 0.009, 0.0), Vector3(0.026, 0.012, 0.01), 0.4, WHITE, Basis(Vector3.BACK, 0.75), 10, 4)
	ClayMesh.add_rounded_box(st, at + Vector3(-0.068, -0.009, 0.0), Vector3(0.026, 0.012, 0.01), 0.4, WHITE, Basis(Vector3.BACK, -0.75), 10, 4)


## 머리: 둥근 흰 상자 · 어두운 화면 (테두리 · 유리 반짝임) · 귀 센서 · 배달 모자 · 안테나.
static func _add_head(st: SurfaceTool) -> void:
	ClayMesh.add_rounded_box(st, HEAD_CENTER, HEAD_SIZE, 0.28, ClayMesh.vertical_gradient(PEARL, WHITE, 1.5), Basis(), 40, 22)
	# 화면 테두리 (회색) · 화면.
	ClayMesh.add_rounded_box(st, HEAD_CENTER + Vector3(0.0, -0.005, -0.192), Vector3(0.42, 0.29, 0.05), 0.24, STEEL, Basis(), 36, 14)
	ClayMesh.add_rounded_box(st, HEAD_CENTER + Vector3(0.0, -0.005, -0.2), Vector3(0.39, 0.26, 0.05), 0.24, SCREEN, Basis(), 36, 14)
	# 유리 반짝임 (화면 왼쪽 위 비스듬한 줄).
	ClayMesh.add_rounded_box(st, HEAD_CENTER + Vector3(-0.13, 0.085, -0.2262), Vector3(0.07, 0.012, 0.002), 0.4, Color("#3A4C66"), Basis(Vector3.BACK, 0.35), 12, 4)
	# 귀 센서: 파란 원판 + 쇠 테 + 가운데 불빛 자리.
	for side: float in [-1.0, 1.0]:
		var ear: Vector3 = HEAD_CENTER + Vector3(side * (HEAD_SIZE.x * 0.5 + 0.012), -0.01, 0.0)
		# 원판 축(Y)을 바깥(±X)으로.
		var axis: Basis = Basis(Vector3.BACK, -side * PI * 0.5)
		ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.085, 0.075, -0.02, 0.03, 0.015, 3), 36, Transform3D(axis, ear), BLUE)
		ClayMesh.add_torus(st, ear + Vector3(side * 0.032, 0.0, 0.0), 0.062, 0.01, STEEL, 32, 6, axis)
		ClayMesh.add_ellipsoid(st, ear + Vector3(side * 0.034, 0.0, 0.0), Vector3(0.012, 0.035, 0.035), BLUE_DARK, 18, 10)
	# 배달 모자: 머리 위 반구 + 앞 챙 + 꼭지 단추 + 흰 줄.
	var dome: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var a: float = PI * 0.5 * float(i) / 12.0
		dome.append(Vector2(cos(a), sin(a)))
	var cap_c: Vector3 = HEAD_CENTER + Vector3(0.0, HEAD_SIZE.y * 0.5 - 0.035, 0.015)
	var cap_r: Vector3 = Vector3(0.235, 0.12, 0.215)
	ClayMesh.add_lathe(st, dome, 44, Transform3D(Basis.from_scale(cap_r), cap_c), BLUE)
	ClayMesh.add_lathe(st, dome, 44, Transform3D(Basis.from_scale(Vector3(0.05, cap_r.y + 0.004, cap_r.z + 0.004)), cap_c), WHITE)
	ClayMesh.add_torus(st, cap_c, 1.0, 0.07, BLUE_DARK, 44, 6, Basis.from_scale(Vector3(cap_r.x, 0.25, cap_r.z)))
	ClayMesh.add_rounded_box(st, cap_c + Vector3(0.0, 0.0, -cap_r.z - 0.07), Vector3(0.3, 0.022, 0.16), 0.3, BLUE_DARK, Basis(Vector3.RIGHT, -0.12), 28, 8)
	ClayMesh.add_ellipsoid(st, cap_c + Vector3(0.0, cap_r.y, 0.0), Vector3(0.025, 0.016, 0.025), BLUE_DARK, 16, 8)
	# 안테나 (오른쪽 뒤, 끝의 불빛은 따로 깜빡인다).
	ClayMesh.add_rod(st, Vector3(0.1, 0.36, 0.06), Vector3(0.11, 0.51, 0.05), 0.009, 0.006, STEEL, 12)
	ClayMesh.add_torus(st, Vector3(0.1, 0.365, 0.06), 0.018, 0.006, GRAPHITE, 16, 6)


## 추진기 바람 기둥: 아래로 퍼지며 옅어지는 원뿔 (정점 색 알파, 더하기 섞기).
static func _add_jet(st: SurfaceTool) -> void:
	var seg: int = 32
	var rings: int = 6
	for r: int in rings:
		var t0: float = float(r) / float(rings)
		var t1: float = float(r + 1) / float(rings)
		var y0: float = 0.03 - 0.22 * t0
		var y1: float = 0.03 - 0.22 * t1
		var r0: float = lerpf(0.08, 0.13, t0)
		var r1: float = lerpf(0.08, 0.13, t1)
		var c0: Color = Color(0.55, 0.92, 1.0, 0.42 * (1.0 - t0))
		var c1: Color = Color(0.55, 0.92, 1.0, 0.42 * (1.0 - t1))
		for k: int in seg:
			var a0: float = TAU * float(k) / float(seg)
			var a1: float = TAU * float(k + 1) / float(seg)
			var p00: Vector3 = Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01: Vector3 = Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10: Vector3 = Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11: Vector3 = Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v: Array in [[p00, c0], [p10, c1], [p11, c1], [p00, c0], [p11, c1], [p01, c0]]:
				st.set_color(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	# 노즐의 빛나는 원판.
	for k: int in seg:
		var a0: float = TAU * float(k) / float(seg)
		var a1: float = TAU * float(k + 1) / float(seg)
		for v: Array in [[Vector3(0.0, 0.031, 0.0), 0.9], [Vector3(cos(a0) * 0.075, 0.031, sin(a0) * 0.075), 0.6], [Vector3(cos(a1) * 0.075, 0.031, sin(a1) * 0.075), 0.6]]:
			st.set_color(Color(LED.r, LED.g, LED.b, v[1]))
			st.set_normal(Vector3.DOWN)
			st.add_vertex(v[0])


# ---- 화면 속 LED (화면 앞면 z 에 붙인 납작한 도형, 머리 마디 좌표) ----

static func _flat_rrect(st: SurfaceTool, c: Vector2, size: Vector2, radius: float, z: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var half: Vector2 = size * 0.5 - Vector2(radius, radius)
	var corners: Array[Vector2] = [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]
	for q: int in 4:
		for k: int in 7:
			var a: float = PI * 0.5 * float(q) + PI * 0.5 * float(k) / 6.0
			pts.append(c + corners[q] + Vector2(cos(a), sin(a)) * radius)
	for i: int in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		for p: Vector2 in [c, a, b]:
			st.set_color(color)
			st.set_normal(Vector3.FORWARD)
			st.add_vertex(Vector3(p.x, p.y, z))


static func _flat_stroke(st: SurfaceTool, pts: PackedVector2Array, width: float, z: float, color: Color) -> void:
	var h: float = width * 0.5
	for i: int in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n: Vector2 = (b - a).orthogonal().normalized() * h
		for p: Vector2 in [a + n, a - n, b - n, a + n, b - n, b + n]:
			st.set_color(color)
			st.set_normal(Vector3.FORWARD)
			st.add_vertex(Vector3(p.x, p.y, z))
	# 마디 · 끝을 둥글게 (작은 원).
	for p: Vector2 in pts:
		for k: int in 10:
			var a0: float = TAU * float(k) / 10.0
			var a1: float = TAU * float(k + 1) / 10.0
			for q: Vector2 in [p, p + Vector2(cos(a0), sin(a0)) * h, p + Vector2(cos(a1), sin(a1)) * h]:
				st.set_color(color)
				st.set_normal(Vector3.FORWARD)
				st.add_vertex(Vector3(q.x, q.y, z))


static func _arc(c: Vector2, r: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in steps + 1:
		var a: float = deg_to_rad(lerpf(a0, a1, float(i) / float(steps)))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out
