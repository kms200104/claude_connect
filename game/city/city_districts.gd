class_name CityDistricts
extends Node3D
## 탕정 제2지구 강변도시 겉모습 (v0.21, data/world/city.json — GameData.city):
## - 회색 건물(상가 · 오피스 · 빌라 · 공장 · 학교 · 도서관 · 역): 층 띠, 창(밤에 불 켜짐), 1층 가게 유리 · 간판 · 차양, 옥상 실외기 · 물탱크.
## - 강 건너 잠긴 구시가지: 같은 건물이 흙탕물에 잠기고 벽에 물 자국, 물 위로 지붕만 보이는 차 · 떠다니는 잔해.
## - 곡교천: 북쪽 호안(돌 쌓기) 위 난간, 보(수중보)와 흰 물살, 강 건너 둑의 터진 자리, 끊긴 다리(곡교천교 · 통행 금지).
## - 길가 가로수 · 가로등 (MultiMesh, 칸마다 visibility range).
## 모두 CHUNK m 칸마다 메시 하나로 합쳐(점토 · 창 두 장), 칸 가운데에 노드를 두고 visibility range 로 먼 칸은 그리지 않는다.

const CHUNK: float = 120.0
const PROP_CHUNK: float = 60.0
const SHOP_SIGNS: Array[String] = ["#E04B3C", "#2F7DD1", "#F2A93B", "#35A26B", "#8E5BD0", "#E2689A", "#1FA3A8"]
## 창 머티리얼(building_window)이 유리 색을 정하므로 정점 색은 거의 흰색 (밤에는 불빛).
const GLASS_DARK: Color = Color("#F2F6FA")
const MUD_LINE: Color = Color("#7A6A52")
const STONE: Color = Color("#9C9890")
const STONE_TOP: Color = Color("#B9B5AC")
const RAIL: Color = Color("#5E6B74")
const CONCRETE: Color = Color("#B8B6B0")

@export var clay_material: Material
@export var window_material: Material
@export var foliage_material: Material
## 건물 칸을 그리는 거리 (땅 휘기로 그 너머는 지평선 아래).
@export_range(80.0, 800.0, 10.0, "suffix:m") var draw_distance: float = 300.0
## 가로수 · 가로등을 그리는 거리.
@export_range(30.0, 300.0, 5.0, "suffix:m") var prop_distance: float = 110.0

var _city: CityData = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 칸 열쇠 → [점토 BoxBatch, 창 BoxBatch].
var _chunks: Dictionary[Vector2i, Array] = {}
var triangles: int = 0


func _ready() -> void:
	_city = GameData.city
	if _city == null:
		return
	_rng.seed = 2141
	for b: CityData.Building in _city.buildings:
		_building(b)
	_revetment()
	_weir()
	_bridge()
	_levee_debris()
	_road_markings()
	_flush()
	_street_props()


func _batches(at: Vector2) -> Array:
	var key: Vector2i = Vector2i(floori(at.x / CHUNK), floori(at.y / CHUNK))
	if not _chunks.has(key):
		var clay: BoxBatch = BoxBatch.new()
		var glass: BoxBatch = BoxBatch.new()
		# 바닥에 붙은 판(차선 · 건널목)은 내 캐릭터 둘레를 비우는 see-through 를 쓰지 않는다 (발밑 차선이 사라지지 않게).
		var flat: BoxBatch = BoxBatch.new()
		var origin: Vector3 = Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		clay.origin = origin
		glass.origin = origin
		flat.origin = origin
		_chunks[key] = [clay, glass, flat]
	return _chunks[key]


func _flush() -> void:
	for key: Vector2i in _chunks:
		var origin: Vector3 = (_chunks[key][0] as BoxBatch).origin
		for i: int in 3:
			var batch: BoxBatch = _chunks[key][i]
			if batch.is_empty():
				continue
			triangles += batch.triangle_count()
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "%s_%d_%d" % [["Clay", "Glass", "Flat"][i], key.x, key.y]
			mi.mesh = batch.commit()
			mi.material_override = [clay_material, window_material, foliage_material][i]
			mi.position = origin
			mi.visibility_range_end = draw_distance + CHUNK * 0.7
			mi.visibility_range_end_margin = 20.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if i == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	_chunks.clear()


# ---------------------------------------------------------------- 건물


func _building(b: CityData.Building) -> void:
	var batches: Array = _batches(b.center)
	var clay: BoxBatch = batches[0]
	var glass: BoxBatch = batches[1]
	var fh: float = _city.floor_height
	var flooded: bool = b.kind == "flooded"
	var ground_floor: float = fh * (1.4 if b.kind in ["shop", "office", "station"] else 1.0)
	var height: float = ground_floor + fh * float(maxi(b.floors - 1, 0))
	if b.kind == "factory":
		height = fh * 3.0 * float(b.floors)
	var c: Vector3 = Vector3(b.center.x, 0.0, b.center.y)
	var w: float = b.size.x
	var d: float = b.size.y
	var wall: Color = b.color
	# 몸통.
	clay.box(c + Vector3(0.0, height * 0.5 - (0.5 if flooded else 0.0), 0.0), Vector3(w, height + (1.0 if flooded else 0.0), d), wall)
	match b.kind:
		"factory":
			_factory(clay, glass, c, w, d, height, wall)
			return
		"station":
			_station(clay, glass, c, w, d, height, wall)
			return
	# 1층: 가게 유리(상가 · 오피스) 또는 벽 그대로.
	var storefront: bool = b.kind in ["shop", "office", "flooded"] or (b.kind == "villa" and _rng.randf() < 0.3)
	var front_dir: int = b.front if b.front != 0 else (1 if _rng.randf() < 0.5 else -1)
	if storefront:
		var gf: float = ground_floor
		var z_face: float = c.z + float(front_dir) * (d * 0.5 + 0.02)
		glass.box(Vector3(c.x, gf * 0.45, z_face), Vector3(w * 0.86, gf * 0.62, 0.06), GLASS_DARK)
		# 간판 띠 + 차양.
		var sign_color: Color = Color(SHOP_SIGNS[_rng.randi() % SHOP_SIGNS.size()])
		clay.box(Vector3(c.x, gf * 0.86, c.z + float(front_dir) * (d * 0.5 + 0.12)), Vector3(w * 0.9, gf * 0.2, 0.2), sign_color.darkened(0.25) if flooded else sign_color)
		if b.kind == "shop" and _rng.randf() < 0.6:
			clay.box(Vector3(c.x, gf * 0.74, c.z + float(front_dir) * (d * 0.5 + 0.7)), Vector3(w * 0.7, 0.08, 1.4), sign_color.lightened(0.35), Basis(Vector3.RIGHT, -0.18 * float(front_dir)))
	# 층마다 창 (앞 · 뒤 · 옆). 오피스는 층마다 이어진 띠 유리.
	var start: int = 1 if storefront else 0
	for f: int in range(start, b.floors):
		var y: float = (ground_floor if f > 0 else 0.0) + fh * float(maxi(f - 1, 0)) + fh * 0.55
		if f == 0:
			y = fh * 0.55
		if b.kind == "office":
			for s: int in [-1, 1]:
				glass.box(Vector3(c.x, y, c.z + float(s) * (d * 0.5 + 0.03)), Vector3(w * 0.92, fh * 0.62, 0.06), GLASS_DARK)
			for s: int in [-1, 1]:
				glass.box(Vector3(c.x + float(s) * (w * 0.5 + 0.03), y, c.z), Vector3(0.06, fh * 0.62, d * 0.88), GLASS_DARK)
			# 층 띠 (살짝 튀어나온 슬래브).
			clay.box(Vector3(c.x, y - fh * 0.42, c.z), Vector3(w + 0.16, 0.18, d + 0.16), wall.darkened(0.12))
		else:
			var n: int = maxi(int(w / 3.2), 1)
			for i: int in n:
				var x: float = c.x - w * 0.5 + (float(i) + 0.5) * w / float(n)
				for s: int in [-1, 1]:
					glass.box(Vector3(x, y, c.z + float(s) * (d * 0.5 + 0.03)), Vector3(minf(1.6, w / float(n) * 0.6), fh * 0.45, 0.06), GLASS_DARK)
			var m: int = maxi(int(d / 4.0), 1)
			for i: int in m:
				var z: float = c.z - d * 0.5 + (float(i) + 0.5) * d / float(m)
				for s: int in [-1, 1]:
					glass.box(Vector3(c.x + float(s) * (w * 0.5 + 0.03), y, z), Vector3(0.06, fh * 0.45, minf(1.4, d / float(m) * 0.55)), GLASS_DARK)
	# 옥상: 난간 턱 · 실외기 · 물탱크 · 옥탑.
	var roof: Color = wall.darkened(0.22)
	clay.box(c + Vector3(0.0, height + 0.25, d * 0.5 - 0.15), Vector3(w, 0.5, 0.3), roof)
	clay.box(c + Vector3(0.0, height + 0.25, -d * 0.5 + 0.15), Vector3(w, 0.5, 0.3), roof)
	clay.box(c + Vector3(w * 0.5 - 0.15, height + 0.25, 0.0), Vector3(0.3, 0.5, d), roof)
	clay.box(c + Vector3(-w * 0.5 + 0.15, height + 0.25, 0.0), Vector3(0.3, 0.5, d), roof)
	for k: int in mini(int(w * d / 60.0), 6):
		var p: Vector3 = c + Vector3(_rng.randf_range(-w * 0.35, w * 0.35), height + 0.45, _rng.randf_range(-d * 0.3, d * 0.3))
		clay.box(p, Vector3(1.0, 0.9, 0.7), Color("#D9DCDD"))
	if b.floors >= 5:
		clay.box(c + Vector3(w * 0.22, height + 1.5, 0.0), Vector3(minf(5.0, w * 0.3), 3.0, minf(4.0, d * 0.5)), wall.darkened(0.06))
	if b.kind == "villa" or b.kind == "flooded":
		clay.box(c + Vector3(-w * 0.25, height + 0.9, d * 0.1), Vector3(1.6, 1.4, 1.6), Color("#5A8FBF"))
	if flooded:
		_flood_marks(clay, c, w, d)
	if not b.name.is_empty():
		_name_sign(b, height)


## 잠긴 건물: 벽에 물 자국 띠, 둘레에 지붕만 나온 차 · 떠다니는 잔해.
func _flood_marks(clay: BoxBatch, c: Vector3, w: float, d: float) -> void:
	var level: float = _city.flood_level
	clay.box(c + Vector3(0.0, level + 0.75, 0.0), Vector3(w + 0.04, 0.5, d + 0.04), MUD_LINE)
	if _rng.randf() < 0.45:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var p: Vector3 = c + Vector3(_rng.randf_range(-w * 0.4, w * 0.4), level - 0.05, side * (d * 0.5 + 2.2))
		var yaw: float = _rng.randf_range(-0.3, 0.3)
		var car: Color = Color(["#C9CED3", "#2E3338", "#A33B33", "#F2F2EE", "#3B5D8C"][_rng.randi() % 5])
		clay.box(p + Vector3(0.0, 0.18, 0.0), Vector3(1.75, 0.5, 4.2), car, Basis(Vector3.UP, yaw))
	if _rng.randf() < 0.5:
		var p2: Vector3 = c + Vector3(_rng.randf_range(-w, w), level + 0.02, _rng.randf_range(-d, d) + d)
		clay.box(p2, Vector3(_rng.randf_range(1.0, 2.6), 0.12, _rng.randf_range(0.3, 0.8)), Color("#8A7452"), Basis(Vector3.UP, _rng.randf() * TAU))


func _factory(clay: BoxBatch, glass: BoxBatch, c: Vector3, w: float, d: float, h: float, wall: Color) -> void:
	# 톱날 지붕 줄 + 파란 띠 + 큰 셔터 문 + 굴뚝.
	var ribs: int = maxi(int(w / 9.0), 2)
	for i: int in ribs:
		var x: float = c.x - w * 0.5 + (float(i) + 0.5) * w / float(ribs)
		clay.box(Vector3(x, h + 1.0, c.z), Vector3(w / float(ribs) * 0.5, 2.0, d * 0.96), wall.darkened(0.1), Basis(Vector3.FORWARD, 0.0))
		glass.box(Vector3(x + w / float(ribs) * 0.26, h + 1.0, c.z), Vector3(0.1, 1.6, d * 0.9), GLASS_DARK)
	clay.box(c + Vector3(0.0, h * 0.78, 0.0), Vector3(w + 0.08, 1.2, d + 0.08), Color("#2F6FB0"))
	for s: int in [-1, 1]:
		clay.box(c + Vector3(w * 0.2, 2.8, float(s) * (d * 0.5 + 0.05)), Vector3(8.0, 5.6, 0.1), Color("#8E969C"))
		glass.box(c + Vector3(-w * 0.2, h * 0.5, float(s) * (d * 0.5 + 0.04)), Vector3(w * 0.4, 1.6, 0.06), GLASS_DARK)
	if _rng.randf() < 0.5:
		clay.box(c + Vector3(-w * 0.4, h + 6.0, -d * 0.3), Vector3(1.6, 12.0, 1.6), Color("#C8C4BC"))


func _station(clay: BoxBatch, glass: BoxBatch, c: Vector3, w: float, d: float, h: float, wall: Color) -> void:
	# 유리 앞면 + 넓은 지붕 + 고가 철길(남북) + 승강장 지붕.
	glass.box(c + Vector3(0.0, h * 0.5, d * 0.5 + 0.03), Vector3(w * 0.9, h * 0.8, 0.06), GLASS_DARK)
	clay.box(c + Vector3(0.0, h + 0.4, 0.0), Vector3(w + 4.0, 0.8, d + 4.0), wall.darkened(0.15))
	var rail_x: float = c.x + w * 0.5 + 8.0
	var z: float = -420.0
	while z < 240.0:
		var batches: Array = _batches(Vector2(rail_x, z))
		var b2: BoxBatch = batches[0]
		b2.box(Vector3(rail_x, 3.5, z), Vector3(1.6, 7.0, 1.6), CONCRETE)
		b2.box(Vector3(rail_x, 7.4, z + 12.0), Vector3(9.0, 0.8, 24.0), CONCRETE.lightened(0.1))
		b2.box(Vector3(rail_x - 4.3, 8.2, z + 12.0), Vector3(0.3, 0.8, 24.0), CONCRETE.darkened(0.1))
		b2.box(Vector3(rail_x + 4.3, 8.2, z + 12.0), Vector3(0.3, 0.8, 24.0), CONCRETE.darkened(0.1))
		z += 24.0
	clay.box(Vector3(rail_x, 11.5, c.z), Vector3(12.0, 0.4, w * 0.9), wall.darkened(0.1))
	for k: int in 6:
		clay.box(Vector3(rail_x - 5.0, 9.6, c.z - w * 0.4 + float(k) * w * 0.16), Vector3(0.3, 3.8, 0.3), CONCRETE.darkened(0.2))


func _name_sign(b: CityData.Building, height: float) -> void:
	var label: Label3D = Label3D.new()
	label.name = "Sign_%s" % b.id
	label.text = b.name
	label.font_size = 96
	label.pixel_size = 0.02
	label.outline_size = 16
	label.modulate = Color("#24323C")
	label.outline_modulate = Color(1, 1, 1, 0.9)
	label.position = Vector3(b.center.x, minf(height - 1.2, 14.0), b.center.y + b.size.y * 0.5 + 0.12)
	label.visibility_range_end = 140.0
	add_child(label)


# ---------------------------------------------------------------- 곡교천


## 북쪽 호안: 가장자리를 따라 돌 쌓기 윗면 + 낮은 난간 (여울 · 선착장 · 물놀이 잔교 자리는 비운다).
func _revetment() -> void:
	var edge: PackedVector2Array = _city.river_north
	var gaps: Array[Vector2] = _rail_gaps()
	var half: float = GameData.layout.island_half
	for i: int in edge.size() - 1:
		var a: Vector2 = edge[i]
		var b: Vector2 = edge[i + 1]
		if absf(a.x) > half + 20.0:
			continue
		var steps: int = maxi(int(a.distance_to(b) / 2.0), 1)
		for k: int in steps:
			var p: Vector2 = a.lerp(b, (float(k) + 0.5) / float(steps))
			var dir: Vector2 = (b - a).normalized()
			var basis: Basis = Basis(Vector3.UP, -dir.angle())
			var batch: BoxBatch = _batches(p)[0]
			# 돌 쌓기 (물 쪽으로 비스듬히 내려가는 벽 윗단).
			batch.box(Vector3(p.x, -0.35, p.y + 0.35), Vector3(a.distance_to(b) / float(steps) + 0.05, 0.9, 0.9), STONE if (i + k) % 3 else STONE.darkened(0.08), basis)
			batch.box(Vector3(p.x, 0.04, p.y - 0.35), Vector3(a.distance_to(b) / float(steps) + 0.05, 0.08, 0.7), STONE_TOP, basis)
			var blocked: bool = false
			for g: Vector2 in gaps:
				if absf(p.x - g.x) < g.y:
					blocked = true
					break
			if blocked:
				continue
			batch.box(Vector3(p.x, 0.95, p.y - 0.55), Vector3(a.distance_to(b) / float(steps) + 0.05, 0.07, 0.07), RAIL, basis)
			if k % 2 == 0:
				batch.box(Vector3(p.x, 0.5, p.y - 0.55), Vector3(0.08, 1.0, 0.08), RAIL)


## 난간을 비울 자리: (x, 반 너비).
func _rail_gaps() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var layout: VillageLayout = GameData.layout
	if layout.dock_size.x > 0.0:
		out.append(Vector2(layout.dock_center.x, layout.dock_size.x * 0.5 + 1.5))
	for spot: SpotInfo in GameData.spots.values():
		for z: Dictionary in spot.shallows:
			if spot.half_extent.x > 100.0:
				out.append(Vector2(float(z["x"]), float(z["half_x"]) + 2.0))
	if GameData.aqua != null and GameData.aqua.dock != Vector2.ZERO:
		out.append(Vector2(GameData.aqua.dock.x, 6.0))
	# 낚시하기 좋게 군데군데 (40m 마다 8m) 난간 없는 물가.
	var x: float = -400.0
	while x < 400.0:
		out.append(Vector2(x, 4.0))
		x += 40.0
	return out


## 보 (수중보): 강을 가로지르는 콘크리트 턱 + 아래쪽 흰 물살.
func _weir() -> void:
	var x: float = _city.weir.x
	var z0: float = _city.weir.y
	var z1: float = _city.weir.z
	var z: float = z0
	while z < z1:
		var batch: BoxBatch = _batches(Vector2(x, z))[0]
		var seg: float = minf(6.0, z1 - z)
		batch.box(Vector3(x, -0.25, z + seg * 0.5), Vector3(2.4, 0.9, seg), CONCRETE)
		batch.box(Vector3(x + 1.8, 0.07, z + seg * 0.5), Vector3(1.4, 0.04, seg), Color("#F4F8FA"))
		z += 6.0


## 끊긴 다리 (역전로 → 강 건너): 다리 몸 · 교각 · 통행 금지 바리케이드 · 팻말.
func _bridge() -> void:
	var road: CityData.Road = null
	for r: CityData.Road in _city.roads:
		if r.id == "east2":
			road = r
	if road == null:
		return
	var x: float = road.a.x
	var z_start: float = _city.north_z(x) - 2.0
	var z_end: float = _city.south_z(x) + 8.0
	var deck: float = 2.2
	var z: float = z_start
	while z < z_end:
		var batch: BoxBatch = _batches(Vector2(x, z))[0]
		var seg: float = minf(10.0, z_end - z)
		# 강 한가운데 한 칸은 무너져 없다.
		var broken: bool = absf(z + seg * 0.5 - (_city.north_z(x) + _city.south_z(x)) * 0.5) < 6.0
		if not broken:
			batch.box(Vector3(x, deck, z + seg * 0.5), Vector3(road.width + 2.0, 0.7, seg), CONCRETE)
			batch.box(Vector3(x - road.width * 0.5 - 0.8, deck + 0.75, z + seg * 0.5), Vector3(0.3, 0.8, seg), CONCRETE.darkened(0.08))
			batch.box(Vector3(x + road.width * 0.5 + 0.8, deck + 0.75, z + seg * 0.5), Vector3(0.3, 0.8, seg), CONCRETE.darkened(0.08))
		if int(z - z_start) % 20 == 0:
			batch.box(Vector3(x, (deck - 2.4) * 0.5 - 1.0, z), Vector3(road.width * 0.6, deck + 2.4, 1.6), CONCRETE.darkened(0.12))
		z += 10.0
	# 바리케이드 (빨강 · 흰 줄).
	var bz: float = z_start + 1.0
	var bb: BoxBatch = _batches(Vector2(x, bz))[0]
	for k: int in 6:
		var px: float = x - road.width * 0.5 + (float(k) + 0.5) * road.width / 6.0
		bb.box(Vector3(px, 0.55, bz - 3.5), Vector3(road.width / 6.0 - 0.2, 0.3, 0.2), Color("#E23B2E") if k % 2 == 0 else Color.WHITE)
		bb.box(Vector3(px, 0.3, bz - 3.5), Vector3(0.12, 0.6, 0.5), Color("#3A3A3A"))
	var sign: Label3D = Label3D.new()
	sign.name = "BridgeClosedSign"
	sign.text = "곡교천교 · 침수 피해로 통행 금지"
	sign.font_size = 64
	sign.pixel_size = 0.012
	sign.outline_size = 12
	sign.modulate = Color("#C0281C")
	sign.outline_modulate = Color.WHITE
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(x, 2.0, bz - 3.5)
	sign.visibility_range_end = 90.0
	add_child(sign)


## 강 건너 둑이 터진 자리: 무너진 둑 덩어리 · 넘어진 가드레일.
func _levee_debris() -> void:
	var c: Vector2 = _city.flood_breach
	for k: int in 14:
		var p: Vector2 = c + Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(4.0, 16.0))
		var batch: BoxBatch = _batches(p)[0]
		batch.box(Vector3(p.x, _rng.randf_range(0.1, 0.6), p.y), Vector3(_rng.randf_range(1.0, 3.4), _rng.randf_range(0.6, 1.4), _rng.randf_range(1.0, 2.6)),
			Color("#8F877A").darkened(_rng.randf() * 0.2), Basis.from_euler(Vector3(_rng.randf() * 0.5, _rng.randf() * TAU, _rng.randf() * 0.5)))


# ---------------------------------------------------------------- 차선 · 건널목


## 차선 (바닥 지도로는 흐릿해서 얇은 판으로): 가운데 노란 두 줄, 차로 흰 점선, 교차로 건널목 · 정지선.
func _road_markings() -> void:
	var yellow: Color = Color("#F2C440")
	var white: Color = Color("#F4F4F0")
	for road: CityData.Road in _city.roads:
		var length: float = road.a.distance_to(road.b)
		var dir: Vector2 = (road.b - road.a).normalized()
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var yaw: float = -dir.angle()
		var t: float = 0.0
		while t < length:
			var seg: float = minf(12.0, length - t)
			var mid: Vector2 = road.a + dir * (t + seg * 0.5)
			t += 12.0
			if _in_other_road(road, mid, 2.5):
				continue
			var batch: BoxBatch = _batches(mid)[2]
			for s: float in [-0.18, 0.18]:
				var p: Vector2 = mid + side * s
				batch.quad_up(Vector3(p.x, 0.025, p.y), Vector2(seg, 0.14), yellow, yaw)
		t = 2.0
		while t < length - 3.0:
			var mid2: Vector2 = road.a + dir * (t + 1.5)
			t += 9.0
			if _in_other_road(road, mid2, 4.0):
				continue
			var batch2: BoxBatch = _batches(mid2)[2]
			for s: float in [-1.0, 1.0]:
				var p2: Vector2 = mid2 + side * s * road.width * 0.25
				batch2.quad_up(Vector3(p2.x, 0.025, p2.y), Vector2(3.0, 0.14), white, yaw)
	# 교차로: 네 방향 건널목 줄무늬 + 정지선.
	for h: CityData.Road in _city.roads:
		if not h.horizontal():
			continue
		for v: CityData.Road in _city.roads:
			if v.horizontal():
				continue
			var x: float = v.a.x
			var z: float = h.a.y
			if x < minf(h.a.x, h.b.x) or x > maxf(h.a.x, h.b.x) or z < minf(v.a.y, v.b.y) - 1.0 or z > maxf(v.a.y, v.b.y) + 1.0:
				continue
			var hw: float = v.width * 0.5
			var hd: float = h.width * 0.5
			# 남북 건널목 (가로 길을 건넌다): 교차로 동 · 서쪽.
			for sx: float in [-1.0, 1.0]:
				var cx: float = x + sx * (hw + 2.2)
				var batch: BoxBatch = _batches(Vector2(cx, z))[2]
				var n: int = int(h.width / 1.0)
				for i: int in n:
					var zz: float = z - hd + (float(i) + 0.5) * h.width / float(n)
					batch.quad_up(Vector3(cx, 0.026, zz), Vector2(3.0, 0.5), white)
				batch.quad_up(Vector3(x + sx * (hw + 4.4), 0.026, z - sx * hd * 0.5), Vector2(0.4, hd), white)
			# 동서 건널목 (세로 길을 건넌다): 교차로 남 · 북쪽.
			for sz: float in [-1.0, 1.0]:
				var cz: float = z + sz * (hd + 2.2)
				var batch3: BoxBatch = _batches(Vector2(x, cz))[2]
				var m: int = int(v.width / 1.0)
				for i: int in m:
					var xx: float = x - hw + (float(i) + 0.5) * v.width / float(m)
					batch3.quad_up(Vector3(xx, 0.026, cz), Vector2(0.5, 3.0), white)
				batch3.quad_up(Vector3(x + sz * hw * 0.5, 0.026, z + sz * (hd + 4.4)), Vector2(hw, 0.4), white)


## 다른 길의 차도 + 건널목 자리(margin) 안인지.
func _in_other_road(road: CityData.Road, p: Vector2, margin: float) -> bool:
	for other: CityData.Road in _city.roads:
		if other != road and other.rect(0.0).grow(margin + _city.sidewalk).has_point(p):
			return true
	return false


# ---------------------------------------------------------------- 길가 가로수 · 가로등


func _street_props() -> void:
	var trees: Dictionary[Vector2i, Array] = {}
	var lamps: Dictionary[Vector2i, Array] = {}
	var half: float = GameData.layout.island_half
	for road: CityData.Road in _city.roads:
		var length: float = road.a.distance_to(road.b)
		var dir: Vector2 = (road.b - road.a).normalized()
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var off: float = road.width * 0.5 + _city.sidewalk * 0.72
		var t: float = 6.0
		var k: int = 0
		while t < length - 6.0:
			var center: Vector2 = road.a + dir * t
			for s: float in [-1.0, 1.0]:
				var p: Vector2 = center + side * off * s
				if absf(p.x) > half - 4.0 or absf(p.y) > half - 4.0 or _city.on_road(p, -0.5) and _crossing(road, p):
					continue
				if _blocked(p):
					continue
				var key: Vector2i = Vector2i(floori(p.x / PROP_CHUNK), floori(p.y / PROP_CHUNK))
				if k % 2 == 0:
					if not trees.has(key):
						trees[key] = []
					trees[key].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.85, 1.15)), Vector3(p.x, 0.0, p.y)))
				else:
					if not lamps.has(key):
						lamps[key] = []
					lamps[key].append(Transform3D(Basis(Vector3.UP, atan2(-side.x * s, -side.y * s)), Vector3(p.x, 0.0, p.y)))
			t += 14.0
			k += 1
	var tree_mesh: ArrayMesh = _tree_mesh()
	var lamp_mesh: ArrayMesh = _lamp_mesh()
	for key: Vector2i in trees:
		_multi("Trees_%d_%d" % [key.x, key.y], tree_mesh, foliage_material, trees[key], key)
	for key: Vector2i in lamps:
		_multi("Lamps_%d_%d" % [key.x, key.y], lamp_mesh, clay_material, lamps[key], key)


## 다른 길과 겹치는 교차로 자리인지.
func _crossing(road: CityData.Road, p: Vector2) -> bool:
	for other: CityData.Road in _city.roads:
		if other != road and other.rect(_city.sidewalk).grow(1.0).has_point(p):
			return true
	return false


## 가로수 · 가로등을 세우면 안 되는 자리 (시설 · 단지 문 · 건물).
func _blocked(p: Vector2) -> bool:
	for b: CityData.Building in _city.buildings:
		if b.rect().grow(1.0).has_point(p):
			return true
	return false


func _multi(node_name: String, mesh: Mesh, material: Material, xforms: Array, key: Vector2i) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	var origin: Vector3 = Vector3((key.x + 0.5) * PROP_CHUNK, 0.0, (key.y + 0.5) * PROP_CHUNK)
	for i: int in xforms.size():
		var xf: Transform3D = xforms[i]
		xf.origin -= origin
		mm.set_instance_transform(i, xf)
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.position = origin
	mmi.visibility_range_end = prop_distance
	mmi.visibility_range_end_margin = 10.0
	add_child(mmi)
	triangles += mesh.get_faces().size() / 3 * xforms.size()


func _tree_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 2.4, 0.0), 0.16, 0.11, Color("#7A5A3A"), 6)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 3.4, 0.0), Vector3(1.5, 1.4, 1.5), Color("#5F9E4F"), 10, 6, Basis(), ClayMesh.blob_wobble(3, 0.14))
	ClayMesh.add_ellipsoid(st, Vector3(0.4, 4.3, 0.2), Vector3(0.95, 0.85, 0.95), Color("#74B25F"), 8, 5, Basis(), ClayMesh.blob_wobble(5, 0.12))
	# 나무 둘레 철망 덮개.
	ClayMesh.add_box(st, Vector3(0.0, 0.03, 0.0), Vector3(1.4, 0.06, 1.4), Color("#4E5358"))
	return ClayMesh.commit(st)


func _lamp_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 6.0, 0.0), 0.11, 0.08, Color("#5A646C"), 6)
	ClayMesh.add_rod(st, Vector3(0.0, 5.9, 0.0), Vector3(0.0, 6.1, 1.6), 0.06, 0.05, Color("#5A646C"), 5)
	ClayMesh.add_box(st, Vector3(0.0, 6.0, 1.8), Vector3(0.36, 0.14, 0.7), Color("#F4E7B8"))
	return ClayMesh.commit(st)
