class_name PhoneProp
extends Node3D
## 손에 든 휴대폰 (v0.14). 휴대폰 창을 여는 동안 캐릭터가 오른손에 들고 내려다본다.
## 민트색 말랑한 케이스 · 앞면 검은 테두리 · 빛나는 화면(홈 화면: 배경 그라데이션 + 앱 아이콘 2×4 + 아래 막대) ·
## 뒷면 카메라 섬(렌즈 둘 + 플래시) · 하트 스티커 · 옆 단추. 화면을 누르면 잠깐 밝아지고(flash), 앱마다 화면 색이 바뀐다(set_app).
## 크기는 캐릭터 손에 맞춘 것 (높이 17cm — 캐릭터가 작아서 실제보다 조금 크다).

const SIZE: Vector3 = Vector3(0.09, 0.17, 0.016)
const CASE: Color = Color("#8FD6C4")
const BEZEL: Color = Color("#2A2830")
const LENS: Color = Color("#1B1E2A")
const METAL: Color = Color("#D5D9DE")
## 홈 화면 앱 아이콘 색 (PhoneWindow.Tab 과 같은 순서, v16: 카메라 · 앨범 · 지도 · 도감 · 날씨 · 음악 · 업적).
const ICON_COLORS: Array[Color] = [Color("#E8594A"), Color("#4C8FE0"), Color("#3DAA6D"), Color("#F2B53A"), Color("#FFD84D"), Color("#9B6AD8"), Color("#F28A3C"), Color("#8C97A6"),
	Color("#5C6B7A"), Color("#F598B4"), Color("#3FB8A6"), Color("#7AAE48"), Color("#5AB0F0"), Color("#D46AB8"), Color("#E0A020"), Color("#2FA0A8")]
const SCREEN_ENERGY: float = 0.9

static var _body_mesh: ArrayMesh = null
static var _home_texture: Texture2D = null

var _screen: MeshInstance3D = null
var _screen_material: StandardMaterial3D = null
var _flash: float = 0.0


func _init(clay: Material = null) -> void:
	name = "Phone"
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh()
	body.material_override = clay
	add_child(body)
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SIZE.x - 0.014, SIZE.y - 0.016)
	_screen.mesh = quad
	_screen.position = Vector3(0.0, 0.0, SIZE.z * 0.5 + 0.0016)
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_screen_material = StandardMaterial3D.new()
	_screen_material.albedo_texture = home_texture()
	_screen_material.emission_enabled = true
	_screen_material.emission_texture = home_texture()
	_screen_material.emission_energy_multiplier = SCREEN_ENERGY
	_screen_material.roughness = 0.15
	_screen_material.metallic_specular = 0.8
	_screen.material_override = _screen_material
	add_child(_screen)


## 화면을 누른 순간: 잠깐 밝아진다.
func flash() -> void:
	_flash = 1.0
	set_process(true)


## 열린 앱 색으로 화면을 물들인다 (-1 = 홈 화면).
func set_app(index: int) -> void:
	if _screen_material == null:
		return
	_screen_material.albedo_color = Color.WHITE if index < 0 else Color.WHITE.lerp(ICON_COLORS[index % ICON_COLORS.size()], 0.45)


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 5.0)
	_screen_material.emission_energy_multiplier = SCREEN_ENERGY + _flash * 0.9
	if _flash <= 0.0:
		set_process(false)


## 케이스 · 테두리 · 카메라 · 단추 (화면은 따로 빛나는 판).
static func body_mesh() -> ArrayMesh:
	if _body_mesh != null:
		return _body_mesh
	var st: SurfaceTool = ClayMesh.begin()
	var half: Vector3 = SIZE * 0.5
	# 말랑한 케이스 (모서리가 둥근 판).
	ClayMesh.add_rounded_box(st, Vector3.ZERO, SIZE, 0.22, CASE, Basis(), 20, 12)
	# 앞면 검은 테두리 (케이스보다 살짝 작게, 앞으로 조금 나온다).
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.0, half.z - 0.0012), Vector3(SIZE.x - 0.006, SIZE.y - 0.006, 0.004), 0.18, BEZEL, Basis(), 20, 4)
	# 위쪽 스피커 홈 · 앞 카메라 점.
	ClayMesh.add_box(st, Vector3(0.0, half.y - 0.0055, half.z + 0.0012), Vector3(0.018, 0.0018, 0.001), Color("#55535C"))
	ClayMesh.add_ellipsoid(st, Vector3(0.012, half.y - 0.0055, half.z + 0.0012), Vector3(0.0016, 0.0016, 0.0008), LENS, 8, 4)
	# 뒷면 카메라 섬 + 렌즈 둘 + 플래시.
	var back: float = -half.z - 0.0022
	var island: Vector3 = Vector3(-half.x + 0.022, half.y - 0.024, back)
	ClayMesh.add_rounded_box(st, island, Vector3(0.032, 0.034, 0.006), 0.3, CASE.darkened(0.12), Basis(), 14, 6)
	for lens: Vector2 in [Vector2(-0.0065, 0.0075), Vector2(-0.0065, -0.0075)]:
		var c: Vector3 = island + Vector3(lens.x, lens.y, -0.0032)
		ClayMesh.add_torus(st, c, 0.0055, 0.0013, METAL, 14, 5, Basis(Vector3.RIGHT, PI * 0.5))
		ClayMesh.add_ellipsoid(st, c, Vector3(0.0048, 0.0048, 0.0018), LENS, 12, 6)
		ClayMesh.add_ellipsoid(st, c + Vector3(0.0015, 0.0015, -0.0012), Vector3(0.0012, 0.0012, 0.0005), Color("#9FB4D8"), 6, 3)
	ClayMesh.add_ellipsoid(st, island + Vector3(0.0085, 0.0075, -0.0032), Vector3(0.0026, 0.0026, 0.001), Color("#FFF1C2"), 8, 4)
	# 뒷면 하트 스티커.
	var heart: Vector3 = Vector3(0.012, -0.03, -half.z - 0.0006)
	ClayMesh.add_ellipsoid(st, heart + Vector3(-0.0055, 0.003, 0.0), Vector3(0.0075, 0.0075, 0.0012), Color("#FF9DB0"), 10, 4)
	ClayMesh.add_ellipsoid(st, heart + Vector3(0.0055, 0.003, 0.0), Vector3(0.0075, 0.0075, 0.0012), Color("#FF9DB0"), 10, 4)
	ClayMesh.add_box(st, heart + Vector3(0.0, -0.003, 0.0), Vector3(0.012, 0.012, 0.0022), Color("#FF9DB0"), Basis(Vector3.BACK, PI * 0.25))
	# 옆 단추 (오른쪽 전원 · 왼쪽 소리 둘).
	ClayMesh.add_rounded_box(st, Vector3(half.x + 0.0008, 0.03, 0.0), Vector3(0.003, 0.024, 0.006), 0.4, CASE.darkened(0.18), Basis(), 8, 4)
	for y: float in [0.045, 0.02]:
		ClayMesh.add_rounded_box(st, Vector3(-half.x - 0.0008, y, 0.0), Vector3(0.003, 0.016, 0.006), 0.4, CASE.darkened(0.18), Basis(), 8, 4)
	# 아래 충전 단자.
	ClayMesh.add_rounded_box(st, Vector3(0.0, -half.y - 0.0004, 0.0), Vector3(0.014, 0.002, 0.005), 0.4, Color("#5B5960"), Basis(), 8, 4)
	_body_mesh = ClayMesh.commit(st)
	return _body_mesh


## 홈 화면 그림: 위 상태 막대 · 앱 아이콘 4줄(4 × 4, 마지막 줄 셋) · 아래 홈 막대, 배경은 복숭아 → 하늘 그라데이션.
static func home_texture() -> Texture2D:
	if _home_texture != null:
		return _home_texture
	var w: int = 120
	var h: int = 240
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top: Color = Color("#FFD8B8")
	var bottom: Color = Color("#A9D8F2")
	for y: int in h:
		img.fill_rect(Rect2i(0, y, w, 1), top.lerp(bottom, float(y) / float(h - 1)))
	# 상태 막대: 시계 · 배터리.
	img.fill_rect(Rect2i(10, 8, 22, 6), Color(0.25, 0.2, 0.18, 0.85))
	img.fill_rect(Rect2i(w - 26, 8, 16, 6), Color(0.25, 0.2, 0.18, 0.85))
	# 날짜 위젯.
	_round_rect(img, Rect2i(12, 30, w - 24, 44), 8, Color(1.0, 1.0, 1.0, 0.55))
	img.fill_rect(Rect2i(22, 42, 40, 8), Color(0.35, 0.27, 0.22))
	img.fill_rect(Rect2i(22, 56, 60, 5), Color(0.5, 0.42, 0.34))
	# 앱 아이콘.
	var size: int = 18
	var gap: int = (w - 4 * size) / 5
	for i: int in ICON_COLORS.size():
		var col: int = i % 4
		var row: int = i / 4
		var x: int = gap + col * (size + gap)
		var y: int = 84 + row * (size + 10)
		_round_rect(img, Rect2i(x, y, size, size), 5, ICON_COLORS[i])
		img.fill_rect(Rect2i(x + 6, y + 6, size - 12, size - 12), Color(1, 1, 1, 0.85))
		img.fill_rect(Rect2i(x + 2, y + size + 3, size - 4, 2), Color(0.3, 0.24, 0.2, 0.6))
	# 아래 독 · 홈 막대.
	_round_rect(img, Rect2i(10, h - 44, w - 20, 26), 10, Color(1.0, 1.0, 1.0, 0.45))
	img.fill_rect(Rect2i(w / 2 - 16, h - 12, 32, 3), Color(0.25, 0.2, 0.18, 0.8))
	img.generate_mipmaps()
	_home_texture = ImageTexture.create_from_image(img)
	return _home_texture


static func _round_rect(img: Image, r: Rect2i, radius: int, color: Color) -> void:
	for y: int in r.size.y:
		for x: int in r.size.x:
			var dx: int = maxi(maxi(radius - x, x - (r.size.x - 1 - radius)), 0)
			var dy: int = maxi(maxi(radius - y, y - (r.size.y - 1 - radius)), 0)
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(r.position.x + x, r.position.y + y, img.get_pixel(r.position.x + x, r.position.y + y).blend(color))
