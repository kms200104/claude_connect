class_name DungeonField
extends Node3D
## v0.28.2 게이트 안 던전 (그림 · 바닥 · 벽 충돌만, 판정은 서버 gates.js · dungeon.js): 게이트에 들어가면 서버가
## 도시 밖 먼 곳(게이트 자리마다 하나, HunterRules.dungeon_origin)으로 옮겨 준다. 내 자리가 던전 영역이면 그 게이트의 지도
## (무너진 지하철역 · 이끼 낀 동굴)를 짓고, 하늘은 지하처럼 어둡게 (SkyController.underground). 남쪽 끝에 "나가는 균열".
## 공략 뒤 서버가 게이트 앞으로 옮겨 주기 전까지는 (게이트가 사라져도) 지도를 그대로 둔다.

const CLAY: Material = preload("res://assets/materials/foliage.tres")
const WALL_H: float = 3.6

var player: Player = null
var sky: SkyController = null
## 지금 지어 둔 지도 (게이트 자리 · 지도 id) — 비어 있으면 없음.
var built_spot: String = ""
var built_map: String = ""
var _root: Node3D = null
var _exit: Node3D = null
var _flicker: Array[OmniLight3D] = []
var _time: float = 0.0
static var _glow: Dictionary[String, ShaderMaterial] = {}


func _ready() -> void:
	name = "Dungeon"


## 내가 던전 안에 있는지.
func inside() -> bool:
	return not built_spot.is_empty() and player != null and GameData.hunter.dungeon_spot_at(player.global_position) == built_spot


## 내가 있는 던전의 게이트 id (공략이 끝나 게이트가 사라졌으면 빈 글자).
func gate_id() -> String:
	if not inside():
		return ""
	for id: String in Net.gates:
		if str(Net.gates[id]["spot"]) == built_spot:
			return id
	return ""


func map() -> HunterRules.DungeonMap:
	return GameData.hunter.dungeon_maps.get(built_map)


## 나가는 균열 (월드).
func exit_position() -> Vector3:
	var m: HunterRules.DungeonMap = map()
	if m == null:
		return Vector3.INF
	return GameData.hunter.dungeon_origin(built_spot) + Vector3(m.exit.x, 0.0, m.exit.y)


func _process(delta: float) -> void:
	_time += delta
	if player == null or GameData.hunter == null:
		return
	var spot: String = GameData.hunter.dungeon_spot_at(player.global_position)
	if spot.is_empty():
		if not built_spot.is_empty():
			_clear()
		return
	if spot != built_spot:
		var map_id: String = ""
		for id: String in Net.gates:
			if str(Net.gates[id]["spot"]) == spot:
				map_id = str(Net.gates[id].get("map", ""))
		if map_id.is_empty() or not GameData.hunter.dungeon_maps.has(map_id):
			return
		_build(spot, map_id)
	for i: int in _flicker.size():
		var l: OmniLight3D = _flicker[i]
		var f: float = sin(_time * (7.0 + float(i) * 3.1)) + sin(_time * (13.0 + float(i)))
		l.light_energy = float(l.get_meta("base", 1.0)) * (0.25 if f > 1.3 else 1.0)
	if _exit != null:
		_exit.rotation.y = 0.0
		(_exit.get_child(0) as Node3D).rotation.z += delta * 0.8


func _clear() -> void:
	built_spot = ""
	built_map = ""
	_flicker.clear()
	_exit = null
	if _root != null:
		_root.queue_free()
		_root = null
	if sky != null:
		sky.underground = false


func _build(spot: String, map_id: String) -> void:
	_clear()
	built_spot = spot
	built_map = map_id
	var m: HunterRules.DungeonMap = GameData.hunter.dungeon_maps[map_id]
	_root = Node3D.new()
	_root.name = "Map_%s" % map_id
	add_child(_root)
	_root.global_position = GameData.hunter.dungeon_origin(spot)
	_collision(m)
	if map_id == "cave":
		_build_cave(m)
	else:
		_build_subway(m)
	_build_exit(m)
	var title: Label3D = Label3D.new()
	title.name = "DungeonTitle"
	title.text = m.name
	title.font_size = 64
	title.pixel_size = 0.012
	title.outline_size = 14
	title.modulate = Color("#D8E4F0")
	title.outline_modulate = Color("#0A0C12")
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = Vector3(0.0, 4.6, -m.size.y * 0.5 + 0.5)
	_root.add_child(title)
	if sky != null:
		sky.underground = true


# ---- 충돌 (바닥 · 둘레 벽 · 기둥 · 잔해) ----

func _collision(m: HunterRules.DungeonMap) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Solid"
	_root.add_child(body)
	_shape(body, Vector3(0.0, -0.5, 0.0), Vector3(m.size.x + 4.0, 1.0, m.size.y + 4.0))
	var hw: float = m.size.x * 0.5
	var hd: float = m.size.y * 0.5
	_shape(body, Vector3(-hw - 0.5, 1.5, 0.0), Vector3(1.0, 3.0, m.size.y + 2.0))
	_shape(body, Vector3(hw + 0.5, 1.5, 0.0), Vector3(1.0, 3.0, m.size.y + 2.0))
	_shape(body, Vector3(0.0, 1.5, -hd - 0.5), Vector3(m.size.x + 2.0, 3.0, 1.0))
	_shape(body, Vector3(0.0, 1.5, hd + 0.5), Vector3(m.size.x + 2.0, 3.0, 1.0))
	for p: Vector3 in m.pillars:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = p.z
		cyl.height = 3.0
		cs.shape = cyl
		cs.position = Vector3(p.x, 1.5, p.y)
		body.add_child(cs)
	for r: Rect2 in m.rubble:
		_shape(body, Vector3(r.get_center().x, 1.0, r.get_center().y), Vector3(r.size.x, 2.0, r.size.y))


func _shape(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	body.add_child(cs)


func _mesh(mesh: ArrayMesh, mesh_name: String, material: Material = CLAY, shadow: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.material_override = material
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	return mi


func _light(at: Vector3, color: Color, energy: float, light_range: float, flicker: bool = false) -> OmniLight3D:
	var l: OmniLight3D = OmniLight3D.new()
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	l.set_meta("base", energy)
	_root.add_child(l)
	if flicker:
		_flicker.append(l)
	return l


## 빛나는 머티리얼 (등불 셰이더, 색만 — GateField 와 같은 방식).
static func glow(c: Color) -> ShaderMaterial:
	var key: String = c.to_html(false)
	if not _glow.has(key):
		var mat: ShaderMaterial = (GateField.GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("albedo", c.lightened(0.2))
		mat.set_shader_parameter("emission", c)
		mat.set_shader_parameter("emission_energy", 2.0)
		_glow[key] = mat
	return _glow[key]


## 콘크리트 · 바위 잔해 더미 (사각형 안에 크기가 다른 덩어리 · 철근).
func _rubble_pile(b: BoxBatch, r: Rect2, rng: RandomNumberGenerator, base: Color, rods: SurfaceTool) -> void:
	var c: Vector2 = r.get_center()
	var n: int = clampi(int(r.size.x * r.size.y * 1.6), 4, 26)
	for i: int in n:
		var at: Vector2 = c + Vector2((rng.randf() - 0.5) * r.size.x * 0.9, (rng.randf() - 0.5) * r.size.y * 0.9)
		var edge: float = minf(r.size.x * 0.5 - absf(at.x - c.x), r.size.y * 0.5 - absf(at.y - c.y))
		var h: float = 0.3 + rng.randf() * (0.5 + edge * 0.8)
		var s: Vector3 = Vector3(0.5 + rng.randf() * 0.9, h, 0.4 + rng.randf() * 0.8)
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, (rng.randf() - 0.5) * 0.6) * Basis(Vector3.BACK, (rng.randf() - 0.5) * 0.5)
		b.box(Vector3(at.x, h * 0.4, at.y), s, base.darkened(rng.randf() * 0.25).lightened(rng.randf() * 0.08), basis)
		if rods != null and i % 3 == 0:
			var from: Vector3 = Vector3(at.x, h * 0.6, at.y)
			ClayMesh.add_rod(rods, from, from + Vector3(rng.randf() - 0.5, 0.5 + rng.randf() * 0.6, rng.randf() - 0.5), 0.025, 0.02, Color("#6A4A36"), 4)


## 바닥에 깔린 둥근 얼룩 (이끼 · 물 · 때): 납작한 타원 두세 겹.
func _blob(st: SurfaceTool, at: Vector3, r: Vector2, color: Color, rng: RandomNumberGenerator, lift: float) -> void:
	var yaw: Basis = Basis(Vector3.UP, rng.randf() * TAU)
	ClayMesh.add_ellipsoid(st, at + Vector3(0.0, lift, 0.0), Vector3(r.x, 0.015, r.y), color, 10, 2, yaw)
	for i: int in 2:
		var off: Vector3 = yaw * Vector3((rng.randf() - 0.5) * r.x, 0.0, (rng.randf() - 0.5) * r.y)
		ClayMesh.add_ellipsoid(st, at + off + Vector3(0.0, lift + 0.002, 0.0), Vector3(r.x, 0.015, r.y) * rng.randf_range(0.45, 0.7), color.lightened(0.04 * float(i + 1)), 8, 2, yaw)


## 마석 결정 무리 (보랏빛, 빛난다).
func _crystals(st: SurfaceTool, at: Vector3, rng: RandomNumberGenerator, n: int, size: float) -> void:
	for i: int in n:
		var dir: Vector3 = Vector3((rng.randf() - 0.5) * 0.9, 1.0, (rng.randf() - 0.5) * 0.9).normalized()
		var base: Vector3 = at + Vector3((rng.randf() - 0.5) * size, 0.0, (rng.randf() - 0.5) * size)
		var l: float = size * (0.5 + rng.randf() * 0.9)
		ClayMesh.add_rod(st, base, base + dir * l, size * 0.14, 0.0, Color.WHITE, 5)


# ---- 무너진 지하철역 ----

func _build_subway(m: HunterRules.DungeonMap) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2802
	var hw: float = m.size.x * 0.5
	var hd: float = m.size.y * 0.5
	var track_x: float = 4.8
	var b: BoxBatch = BoxBatch.new()
	# 승강장 바닥 (낡은 타일: 1m 칸 · 줄눈) · 노란 안전선 · 점자 블록.
	b.box(Vector3((-hw + track_x) * 0.5, -0.05, 0.0), Vector3(track_x + hw, 0.1, m.size.y), Color("#8E8A82"))
	for i: int in int(m.size.y) + 1:
		b.box(Vector3((-hw + track_x) * 0.5, 0.005, -hd + float(i)), Vector3(track_x + hw, 0.01, 0.04), Color("#6E6A64"))
	for i: int in int(track_x + hw) + 1:
		b.box(Vector3(-hw + float(i), 0.005, 0.0), Vector3(0.04, 0.01, m.size.y), Color("#6E6A64"))
	b.box(Vector3(track_x - 0.55, 0.012, 0.0), Vector3(0.3, 0.02, m.size.y), Color("#D8B43A"))
	b.box(Vector3(track_x - 0.05, 0.03, 0.0), Vector3(0.1, 0.06, m.size.y), Color("#5C5A56"))
	# 얼룩 · 물웅덩이 (둥근 얼룩) · 금 간 자리.
	var stains: SurfaceTool = ClayMesh.begin()
	for i: int in 14:
		var at: Vector3 = Vector3(rng.randf_range(-hw + 1.0, track_x - 1.0), 0.0, rng.randf_range(-hd + 1.0, hd - 1.0))
		_blob(stains, at, Vector2(rng.randf_range(0.5, 1.3), rng.randf_range(0.4, 0.9)), Color("#6A6660") if i % 3 else Color("#3A4248"), rng, 0.012 + float(i) * 0.0004)
	_mesh(ClayMesh.commit(stains), "Stains", CLAY, false)
	for i: int in 10:
		var at: Vector3 = Vector3(rng.randf_range(-hw + 1.0, track_x - 1.0), 0.014, rng.randf_range(-hd + 1.0, hd - 1.0))
		b.box(at, Vector3(rng.randf_range(1.2, 3.0), 0.01, 0.06), Color("#3A3836"), Basis(Vector3.UP, rng.randf() * TAU))
	# 선로 (자갈 바닥 · 침목 · 레일 둘).
	b.box(Vector3((track_x + hw) * 0.5, -0.06, 0.0), Vector3(hw - track_x, 0.08, m.size.y), Color("#4E4A44"))
	for i: int in int(m.size.y / 0.8):
		b.box(Vector3(8.4, 0.0, -hd + 0.4 + float(i) * 0.8), Vector3(2.6, 0.08, 0.24), Color("#4A3E34"))
	for rx: float in [7.6, 9.2]:
		b.box(Vector3(rx, 0.08, 0.0), Vector3(0.08, 0.1, m.size.y), Color("#8A8E92"))
	# 왼쪽 벽 (크림색 타일 · 파란 띠 · 광고판 틀) · 뒤 벽 (역 이름판 · 터널 입구) · 오른쪽 터널 벽.
	b.box(Vector3(-hw - 0.2, WALL_H * 0.5, 0.0), Vector3(0.4, WALL_H, m.size.y + 0.4), Color("#D8D0BC"))
	b.box(Vector3(-hw + 0.01, 1.3, 0.0), Vector3(0.04, 0.36, m.size.y), Color("#2E5A9A"))
	for i: int in 4:
		var z: float = -hd + 5.0 + float(i) * 9.0
		b.box(Vector3(-hw + 0.03, 2.3, z), Vector3(0.06, 1.2, 2.6), Color("#2A2A2E"))
		b.box(Vector3(-hw + 0.05, 2.3, z), Vector3(0.04, 1.0, 2.4), Color("#4A5868").darkened(rng.randf() * 0.4))
	b.box(Vector3(0.0, WALL_H * 0.5, -hd - 0.2), Vector3(m.size.x + 0.8, WALL_H, 0.4), Color("#CFC6B2"))
	b.box(Vector3(-3.0, 2.5, -hd + 0.02), Vector3(5.2, 0.9, 0.04), Color("#1E4E8A"))
	b.box(Vector3(8.4, 1.5, -hd + 0.02), Vector3(3.4, 3.0, 0.04), Color("#08080A"))
	b.box(Vector3(hw + 0.2, WALL_H * 0.5, 0.0), Vector3(0.4, WALL_H, m.size.y + 0.4), Color("#5A5650"))
	for i: int in 6:
		b.box(Vector3(hw - 0.02, 2.6, -hd + 3.0 + float(i) * 6.5), Vector3(0.06, 0.12, 4.0), Color("#3A3A3A"))
	# 남쪽 끝: 낮은 턱 · 올라가는 계단 (카메라를 가리지 않게 낮게).
	b.box(Vector3(0.0, 0.25, hd + 0.3), Vector3(m.size.x + 0.8, 0.5, 0.6), Color("#7A766E"))
	for i: int in 4:
		b.box(Vector3(m.exit.x, 0.06 + float(i) * 0.12, hd - 0.5 + float(i) * 0.25), Vector3(3.2, 0.12, 0.3), Color("#9A968C").darkened(float(i) * 0.05))
	# 기둥 (네모 · 타일 · 파란 띠), 하나는 부러졌다.
	for i: int in m.pillars.size():
		var p: Vector3 = m.pillars[i]
		var h: float = 1.4 if i == 3 else WALL_H
		var s: float = p.z * 1.6
		b.box(Vector3(p.x, h * 0.5, p.y), Vector3(s, h, s), Color("#D2CAB6"))
		b.box(Vector3(p.x, 1.3, p.y), Vector3(s + 0.04, 0.3, s + 0.04), Color("#2E5A9A"))
		if i == 3:
			b.box(Vector3(p.x + 0.9, 0.3, p.y + 0.4), Vector3(s * 0.9, 0.6, 1.8), Color("#C4BCA8"), Basis(Vector3.UP, 0.6) * Basis(Vector3.BACK, 0.25))
	# 무너진 천장 덩어리 (기울어진 판) · 잔해 더미 (마지막 사각형은 선로 위 전동차).
	var rods: SurfaceTool = ClayMesh.begin()
	for i: int in m.rubble.size():
		var r: Rect2 = m.rubble[i]
		if r.size.y > 10.0:
			continue
		_rubble_pile(b, r, rng, Color("#8A847A"), rods)
		b.box(Vector3(r.get_center().x, 0.9, r.get_center().y), Vector3(r.size.x * 0.9, 0.25, r.size.y * 0.8), Color("#A29A8A"), Basis(Vector3.UP, rng.randf() * 0.6) * Basis(Vector3.BACK, 0.45))
	# 버려진 것들: 의자 · 쓰러진 휴지통 · 흩어진 종이 · 개찰구 표지.
	for at: Vector2 in [Vector2(-9.6, -2.0), Vector2(-9.6, 7.0)]:
		b.box(Vector3(at.x, 0.42, at.y), Vector3(0.5, 0.06, 2.2), Color("#3A6AA8"))
		b.box(Vector3(at.x - 0.22, 0.7, at.y), Vector3(0.06, 0.5, 2.2), Color("#3A6AA8"))
		b.box(Vector3(at.x, 0.2, at.y), Vector3(0.4, 0.4, 0.1), Color("#6A6A6A"))
	b.box(Vector3(-1.5, 0.22, 6.5), Vector3(0.5, 0.44, 0.5), Color("#5A6A5A"), Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, 0.4))
	for i: int in 24:
		b.box(Vector3(rng.randf_range(-hw + 1.0, track_x - 1.0), 0.02, rng.randf_range(-hd + 1.0, hd - 1.0)), Vector3(0.22, 0.01, 0.3), Color("#D8D4C8").darkened(rng.randf() * 0.3), Basis(Vector3.UP, rng.randf() * TAU))
	# 전동차 (선로 위, 조금 기울어 멈춘 채): 은빛 몸 · 창 띠 · 문 · 파란 줄.
	var car: Rect2 = m.rubble[m.rubble.size() - 1]
	var cc: Vector3 = Vector3(car.get_center().x, 0.0, car.get_center().y)
	var tilt: Basis = Basis(Vector3.BACK, -0.07) * Basis(Vector3.UP, 0.03)
	b.box(cc + tilt * Vector3(0.0, 1.45, 0.0), Vector3(car.size.x - 0.2, 2.5, car.size.y - 0.2), Color("#B8BCC0"), tilt)
	b.box(cc + tilt * Vector3(0.0, 1.85, 0.0), Vector3(car.size.x - 0.12, 0.7, car.size.y - 0.6), Color("#22282E"), tilt)
	b.box(cc + tilt * Vector3(0.0, 1.0, 0.0), Vector3(car.size.x - 0.1, 0.18, car.size.y - 0.3), Color("#2E5A9A"), tilt)
	for i: int in 3:
		b.box(cc + tilt * Vector3(-car.size.x * 0.5 + 0.06, 1.25, -car.size.y * 0.33 + float(i) * car.size.y * 0.33), Vector3(0.06, 2.0, 1.2), Color("#8A9096"), tilt)
	b.box(cc + tilt * Vector3(0.0, 2.75, 0.0), Vector3(car.size.x - 0.6, 0.12, car.size.y - 0.4), Color("#9A9EA2"), tilt)
	_mesh(b.commit(), "Station")
	_mesh(ClayMesh.commit(rods), "Rebar")
	# 역 이름판 · 비상구 표지 글자.
	var sign_label: Label3D = Label3D.new()
	sign_label.text = "솔내  Solnae"
	sign_label.font_size = 72
	sign_label.pixel_size = 0.01
	sign_label.modulate = Color("#F4F4F0")
	sign_label.outline_size = 0
	sign_label.position = Vector3(-3.0, 2.5, -hd + 0.06)
	_root.add_child(sign_label)
	# 형광등 (몇 개만 켜져 깜빡) · 붉은 비상등 · 균열에서 새어 나온 마석 결정.
	var tubes: SurfaceTool = ClayMesh.begin()
	# 형광등은 벽에 (천장에 달면 내려다보는 카메라를 가린다). 하나는 떨어져 바닥에 깨져 있다.
	for i: int in 5:
		var z: float = -hd + 4.0 + float(i) * 8.0
		ClayMesh.add_box(tubes, Vector3(-hw + 0.1, 3.1, z), Vector3(0.1, 0.1, 1.6), Color.WHITE)
	ClayMesh.add_box(tubes, Vector3(-1.0, 0.05, -1.5), Vector3(0.1, 0.08, 1.2), Color.WHITE, Basis(Vector3.UP, 0.7))
	_mesh(ClayMesh.commit(tubes), "Tubes", glow(Color("#D8E8FF")), false)
	_light(Vector3(-hw + 1.2, 3.0, -12.0), Color("#D8E8FF"), 1.4, 10.0, true)
	_light(Vector3(-hw + 1.2, 3.0, 4.0), Color("#D8E8FF"), 1.2, 10.0, true)
	var red: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_box(red, Vector3(-hw + 0.08, 2.9, 12.0), Vector3(0.1, 0.25, 0.5), Color.WHITE)
	ClayMesh.add_box(red, Vector3(hw - 0.08, 2.9, -10.0), Vector3(0.1, 0.25, 0.5), Color.WHITE)
	_mesh(ClayMesh.commit(red), "EmergencyLights", glow(Color("#FF3A2A")), false)
	_light(Vector3(-hw + 1.0, 2.6, 12.0), Color("#FF4A3A"), 1.4, 8.0)
	_light(Vector3(hw - 1.5, 2.6, -10.0), Color("#FF4A3A"), 1.2, 8.0)
	var cr: SurfaceTool = ClayMesh.begin()
	_crystals(cr, Vector3(-7.5, 0.2, -10.0), rng, 6, 0.9)
	_crystals(cr, Vector3(0.5, 0.2, -18.0), rng, 7, 1.0)
	_crystals(cr, Vector3(3.5, 0.3, 11.0), rng, 4, 0.7)
	_mesh(ClayMesh.commit(cr), "ManaCrystals", glow(Color("#9A5AF0")), false)
	_light(Vector3(-1.0, 1.4, -8.0), Color("#9A6AF0"), 1.8, 12.0)
	_light(Vector3(7.0, 2.6, 6.0), Color("#C8D8F0"), 0.9, 9.0, true)


# ---- 이끼 낀 동굴 ----

func _build_cave(m: HunterRules.DungeonMap) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2803
	var hw: float = m.size.x * 0.5
	var hd: float = m.size.y * 0.5
	var b: BoxBatch = BoxBatch.new()
	# 바닥: 어두운 돌 · 이끼 얼룩 · 고인 물.
	b.box(Vector3(0.0, -0.05, 0.0), Vector3(m.size.x + 2.0, 0.1, m.size.y + 2.0), Color("#3A3832"))
	_mesh(b.commit(), "Floor", CLAY, false)
	var moss: SurfaceTool = ClayMesh.begin()
	for i: int in 34:
		var at: Vector3 = Vector3(rng.randf_range(-hw, hw), 0.0, rng.randf_range(-hd, hd))
		var green: Color = Color("#3E6A34").lerp(Color("#6A9A44"), rng.randf())
		_blob(moss, at, Vector2(rng.randf_range(0.6, 1.8), rng.randf_range(0.5, 1.4)), green if i % 4 else Color("#4A463E"), rng, 0.01 + float(i) * 0.0005)
	_mesh(ClayMesh.commit(moss), "Moss", CLAY, false)
	var rocks: SurfaceTool = ClayMesh.begin()
	# 둘레 바위벽 (크고 작은 덩어리 · 이끼 모자). 남쪽은 낮게 (카메라를 가리지 않게).
	var edges: Array[Array] = [[Vector2(-hw, -hd), Vector2(hw, -hd), 3.6], [Vector2(-hw, -hd), Vector2(-hw, hd), 3.0], [Vector2(hw, -hd), Vector2(hw, hd), 3.0], [Vector2(-hw, hd), Vector2(hw, hd), 0.7]]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var c: Vector2 = e[1]
		var h: float = e[2]
		var n: int = int(a.distance_to(c) / 2.2)
		for i: int in n + 1:
			var t: float = float(i) / float(n)
			var p: Vector2 = a.lerp(c, t)
			# 남쪽은 작은 돌 (나가는 균열 자리는 비운다).
			if h < 1.0 and absf(p.x - m.exit.x) < 2.6:
				continue
			var r: float = rng.randf_range(1.3, 2.2) if h > 1.0 else rng.randf_range(0.7, 1.1)
			var rh: float = h * rng.randf_range(0.7, 1.25)
			var rock: Color = Color("#5A564E").lerp(Color("#6E665A"), rng.randf())
			ClayMesh.add_ellipsoid(rocks, Vector3(p.x, rh * 0.45, p.y), Vector3(r, rh * 0.6, r), rock, 8, 5, Basis(Vector3.UP, rng.randf() * TAU))
			if h > 1.0:
				ClayMesh.add_ellipsoid(rocks, Vector3(p.x, rh * 0.95, p.y), Vector3(r * 0.8, 0.25, r * 0.8), Color("#4E7A3A"), 8, 3)
	# 석순 기둥 (원뿔 · 이끼 띠) · 무너진 바위 더미.
	for p: Vector3 in m.pillars:
		var h: float = 2.0 + p.z * 1.4
		ClayMesh.add_rod(rocks, Vector3(p.x, 0.0, p.y), Vector3(p.x + rng.randf_range(-0.2, 0.2), h, p.y), p.z, 0.08, Color("#6A645A"), 8)
		ClayMesh.add_ellipsoid(rocks, Vector3(p.x, 0.25, p.y), Vector3(p.z * 1.15, 0.35, p.z * 1.15), Color("#4A7A38"), 8, 3)
		ClayMesh.add_rod(rocks, Vector3(p.x + p.z * 0.9, 0.0, p.y + 0.3), Vector3(p.x + p.z * 1.0, 0.8, p.y + 0.4), p.z * 0.35, 0.03, Color("#625C52"), 6)
	var pile: BoxBatch = BoxBatch.new()
	for r: Rect2 in m.rubble:
		_rubble_pile(pile, r, rng, Color("#625C52"), null)
	# 땅에 기어가는 뿌리 · 덩굴.
	for i: int in 9:
		var from: Vector3 = Vector3(rng.randf_range(-hw + 1.0, hw - 1.0), 0.04, -hd + 0.6)
		var to: Vector3 = from + Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(2.0, 6.0))
		ClayMesh.add_rod(rocks, from + Vector3(0.0, 1.6, -0.3), from, 0.07, 0.06, Color("#5A4632"), 4)
		ClayMesh.add_rod(rocks, from, to, 0.06, 0.02, Color("#5A4632"), 4)
	_mesh(ClayMesh.commit(rocks), "Rocks")
	_mesh(pile.commit(), "RockPiles")
	# 고인 물 (푸르게 빛나는 웅덩이).
	var pool: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(pool, Vector3(-3.0, 0.0, 9.5), Vector3(2.6, 0.03, 1.6), Color.WHITE, 16, 2)
	_mesh(ClayMesh.commit(pool), "Pool", glow(Color("#1E5A6A")), false)
	# 빛나는 버섯 (청록 갓) · 마석 결정 (보라).
	var caps: SurfaceTool = ClayMesh.begin()
	var stems: SurfaceTool = ClayMesh.begin()
	for spot: Vector2 in [Vector2(-10, -6), Vector2(9, -2), Vector2(-6, 12), Vector2(11, 12), Vector2(-2, -15), Vector2(5, -12)]:
		for i: int in 5:
			var at: Vector3 = Vector3(spot.x + rng.randf_range(-0.8, 0.8), 0.0, spot.y + rng.randf_range(-0.8, 0.8))
			var h: float = rng.randf_range(0.2, 0.55)
			ClayMesh.add_rod(stems, at, at + Vector3(0.0, h, 0.0), 0.04, 0.03, Color("#C8C0A8"), 5)
			ClayMesh.add_ellipsoid(caps, at + Vector3(0.0, h, 0.0), Vector3(0.16, 0.08, 0.16) * rng.randf_range(0.8, 1.5), Color.WHITE, 8, 3)
	_mesh(ClayMesh.commit(stems), "MushroomStems", CLAY, false)
	_mesh(ClayMesh.commit(caps), "MushroomCaps", glow(Color("#3AE0C8")), false)
	var cr: SurfaceTool = ClayMesh.begin()
	_crystals(cr, Vector3(-9.0, 0.4, -13.0), rng, 7, 1.1)
	_crystals(cr, Vector3(12.0, 0.4, -15.0), rng, 6, 1.0)
	_crystals(cr, Vector3(10.0, 0.6, 5.0), rng, 5, 0.9)
	_crystals(cr, Vector3(0.0, 0.0, -6.0), rng, 4, 0.6)
	_mesh(ClayMesh.commit(cr), "ManaCrystals", glow(Color("#9A5AF0")), false)
	_light(Vector3(-9.0, 1.6, -11.0), Color("#9A6AF0"), 1.6, 11.0)
	_light(Vector3(10.0, 1.6, 4.0), Color("#8A6AF0"), 1.4, 10.0)
	_light(Vector3(-6.0, 1.2, 11.0), Color("#3AE0C8"), 1.3, 9.0)
	_light(Vector3(0.0, 2.2, -6.0), Color("#5AC0B0"), 1.2, 12.0, true)
	_light(Vector3(9.0, 1.2, -2.0), Color("#3AE0C8"), 1.0, 8.0)


# ---- 나가는 균열 ----

func _build_exit(m: HunterRules.DungeonMap) -> void:
	_exit = Node3D.new()
	_exit.name = "Exit"
	# 바닥에 누운 균열 (서 있으면 남쪽 끝이라 카메라와 사람 사이를 가린다).
	_exit.position = Vector3(m.exit.x, 0.06, m.exit.y)
	_root.add_child(_exit)
	var holder: Node3D = Node3D.new()
	holder.rotation.x = -PI * 0.5
	_exit.add_child(holder)
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_torus(st, Vector3.ZERO, 0.95, 0.1, Color.WHITE, 24, 5, Basis(Vector3.RIGHT, PI * 0.5))
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		ClayMesh.add_rod(st, Vector3(cos(a), sin(a), 0.0) * 1.0, Vector3(cos(a), sin(a), 0.0) * 1.35, 0.06, 0.0, Color.WHITE, 4)
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.mesh = ClayMesh.commit(st)
	ring.material_override = glow(Color("#8FD0FF"))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring)
	var vs: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(vs, Vector3.ZERO, Vector3(0.88, 0.88, 0.02), Color.WHITE, 20, 6)
	var veil: MeshInstance3D = MeshInstance3D.new()
	veil.mesh = ClayMesh.commit(vs)
	veil.material_override = glow(Color("#2A4A7A"))
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(veil)
	var l: OmniLight3D = OmniLight3D.new()
	l.light_color = Color("#8FD0FF")
	l.light_energy = 1.4
	l.omni_range = 6.0
	l.position = Vector3(0.0, 1.2, 0.0)
	_exit.add_child(l)
	var label: Label3D = Label3D.new()
	label.name = "ExitLabel"
	label.text = "나가는 균열"
	label.font_size = 44
	label.pixel_size = 0.007
	label.outline_size = 10
	label.modulate = Color("#CFE8FF")
	label.outline_modulate = Color("#0A0C12")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.9, 0.0)
	_exit.add_child(label)
