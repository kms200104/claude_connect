class_name VillageDecor
extends Node3D
## 마을 꾸밈: 이끼 낀 바위, 나무 울타리, 꽃밭·들꽃, 풀 덤불, 호수 선착장, 바닷가 야자수·조개·불가사리. 배치는 data/world/village_layout.json.
## 반복되는 것(풀·꽃·울타리)은 MultiMesh 한 덩어리씩, 바위는 모두 합쳐 메시 하나로 그린다 (전부 드로우콜 9개).
## 큰 바위·울타리·선착장은 충돌체를 둔다. 풀·꽃은 길·호수·집·상점·나무 자리를 피해서 흩뿌린다 (시드 고정, 매번 같은 자리).

## 정점 색을 쓰는 흰 툰 머티리얼.
@export var clay_material: Material
@export var seed_value: int = 20240611
## 풀·꽃을 흩뿌리는 범위 (마을 가운데 ±미터).
@export_range(10.0, 120.0, 1.0, "suffix:m") var scatter_extent: float = 94.0
## 바닷가에 심는 야자수 수.
@export_range(0, 64) var palm_count: int = 26

const WOOD: Color = Color("#A9724A")
const WOOD_LIGHT: Color = Color("#C99466")
const ROCK: Color = Color("#A7A9A6")
const MOSS: Color = Color("#7FAE5A")
const PETALS: Array[Color] = [Color("#F6A6B8"), Color("#FFD866"), Color("#9EC1F2"), Color("#F4F1EA")]
const FENCE_SPACING: float = 2.0
const DOCK_TOP: float = 0.08

var _layout: VillageLayout = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_layout = GameData.layout
	if _layout == null:
		return
	Quality.changed.connect(rebuild)
	_build_all()


## 화질(풀·꽃·야자수 수)이 바뀌었을 때 처음부터 다시 꾸민다 (시드가 같아서 남는 것은 같은 자리).
func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build_all()


func _build_all() -> void:
	_rng.seed = seed_value
	_build_rocks()
	_build_fences()
	_build_dock()
	_build_flowers()
	_build_grass()
	_build_beach()


func _build_rocks() -> void:
	var st: SurfaceTool = ClayMesh.begin()
	var paint: Callable = ClayMesh.vertical_gradient(ROCK.darkened(0.25), ROCK.lightened(0.05), 1.0)
	var moss: Callable = func(local: Vector3, normal: Vector3) -> Color:
		var top: float = smoothstep(0.45, 0.8, normal.y + sin(local.x * 7.0 + local.z * 5.0) * 0.12)
		return (paint.call(local, normal) as Color).lerp(MOSS, top)
	for rock: VillageLayout.Rock in _layout.rocks:
		var base: Vector3 = Vector3(rock.position.x, 0.0, rock.position.y)
		var s: float = rock.size
		# 큰 돌 하나 + 작은 돌 두셋.
		ClayMesh.add_ellipsoid(st, base + Vector3(0.0, s * 0.35, 0.0), Vector3(s * 0.75, s * 0.55, s * 0.68), moss, 12, 8, Basis(Vector3.UP, _rng.randf() * TAU), ClayMesh.blob_wobble(_rng.randi(), 0.14, 3))
		for i: int in 2 + (1 if s > 1.0 else 0):
			var a: float = _rng.randf() * TAU
			var r: float = s * _rng.randf_range(0.25, 0.4)
			var at: Vector3 = base + Vector3(cos(a), 0.0, sin(a)) * s * 0.8 + Vector3(0.0, r * 0.45, 0.0)
			ClayMesh.add_ellipsoid(st, at, Vector3(r, r * 0.7, r * 0.9), moss, 9, 6, Basis(Vector3.UP, a), ClayMesh.blob_wobble(_rng.randi(), 0.12, 3))
		if rock.solid:
			_add_collider(base + Vector3(0.0, s * 0.5, 0.0), Vector3(s * 1.4, s, s * 1.3), 0.0)
	_add_mesh_instance("Rocks", ClayMesh.commit(st))


## 울타리: 기둥과 가로대 두 줄 (가로대는 칸 길이에 맞춰 늘인다). 선을 따라 2m 간격.
func _build_fences() -> void:
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for line: PackedVector2Array in _layout.fences:
		for i: int in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var length: float = a.distance_to(b)
			var count: int = maxi(int(ceil(length / FENCE_SPACING)), 1)
			var yaw: float = atan2(-(b.y - a.y), b.x - a.x)
			for k: int in count:
				var p: Vector2 = a.lerp(b, float(k) / float(count))
				var q: Vector2 = a.lerp(b, float(k + 1) / float(count))
				posts.append(Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.05, 0.05)), Vector3(p.x, 0.0, p.y)))
				var mid: Vector2 = (p + q) * 0.5
				rails.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(p.distance_to(q), 1.0, 1.0)), Vector3(mid.x, 0.0, mid.y)))
			_add_collider(Vector3((a.x + b.x) * 0.5, 0.5, (a.y + b.y) * 0.5), Vector3(length, 1.0, 0.25), yaw)
		var last: Vector2 = line[line.size() - 1]
		posts.append(Transform3D(Basis(), Vector3(last.x, 0.0, last.y)))
	var post_st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rounded_box(post_st, Vector3(0.0, 0.5, 0.0), Vector3(0.18, 1.0, 0.18), 0.35, ClayMesh.vertical_gradient(WOOD.darkened(0.15), WOOD_LIGHT, 1.0), Basis(), 8, 6)
	var rail_st: SurfaceTool = ClayMesh.begin()
	for y: float in [0.4, 0.74]:
		ClayMesh.add_rounded_box(rail_st, Vector3(0.0, y, 0.0), Vector3(1.0, 0.13, 0.08), 0.3, ClayMesh.vertical_gradient(WOOD.darkened(0.1), WOOD_LIGHT, 1.0), Basis(), 8, 5)
	_add_multimesh("FencePosts", ClayMesh.commit(post_st), posts)
	_add_multimesh("FenceRails", ClayMesh.commit(rail_st), rails)


## 호수 선착장: 가로 판자 + 양옆 들보 + 모서리 말뚝. 위를 걸을 수 있다 (FishingSpot 이 이 자리만 물 막이를 비운다).
func _build_dock() -> void:
	var rect: Rect2 = _layout.dock_rect()
	if rect.size.x <= 0.0:
		return
	var st: SurfaceTool = ClayMesh.begin()
	var center: Vector3 = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var planks: int = int(rect.size.x / 0.3)
	for i: int in planks:
		var x: float = rect.position.x + (float(i) + 0.5) * rect.size.x / float(planks)
		var tone: Color = WOOD_LIGHT.lerp(WOOD, _rng.randf_range(0.0, 0.5))
		ClayMesh.add_rounded_box(st, Vector3(x, DOCK_TOP - 0.04, center.z), Vector3(rect.size.x / float(planks) - 0.04, 0.08, rect.size.y), 0.2, tone, Basis(Vector3.UP, _rng.randf_range(-0.02, 0.02)), 8, 4)
	for side: float in [-1.0, 1.0]:
		var z: float = center.z + side * (rect.size.y * 0.5 - 0.06)
		ClayMesh.add_rounded_box(st, Vector3(center.x, DOCK_TOP - 0.13, z), Vector3(rect.size.x, 0.12, 0.12), 0.3, WOOD.darkened(0.15), Basis(), 8, 4)
		for x: float in [rect.position.x + 0.1, center.x, rect.end.x - 0.1]:
			ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.1, 0.09, -0.5, DOCK_TOP + 0.28, 0.05, 2), 10, Transform3D(Basis(), Vector3(x, 0.0, z + side * 0.05)), ClayMesh.vertical_gradient(WOOD.darkened(0.3), WOOD_LIGHT, 1.0))
	_add_mesh_instance("Dock", ClayMesh.commit(st))
	_add_collider(Vector3(center.x, DOCK_TOP - 0.1, center.z), Vector3(rect.size.x, 0.2, rect.size.y), 0.0)


## 꽃밭(뭉쳐 핀 꽃)과 들꽃(드문드문). 꽃잎 색마다 MultiMesh 하나.
func _build_flowers() -> void:
	var by_color: Array[Array] = []
	for c: Color in PETALS:
		by_color.append([])
	for bed: VillageLayout.FlowerBed in _layout.flower_beds:
		for i: int in bed.count:
			var r: float = bed.radius * sqrt(_rng.randf())
			var a: float = _rng.randf() * TAU
			var p: Vector2 = bed.center + Vector2(cos(a), sin(a)) * r
			by_color[_rng.randi() % PETALS.size()].append(_flower_xform(p))
	var placed: int = 0
	var tries: int = 0
	var wild_count: int = int(float(_layout.wild_flower_count) * Quality.density("wild_flowers"))
	while placed < wild_count and tries < wild_count * 20:
		tries += 1
		var p: Vector2 = _random_point()
		if _blocked(p, 0.4):
			continue
		# 들꽃은 두세 송이씩 모여 핀다.
		var color_index: int = _rng.randi() % PETALS.size()
		for k: int in _rng.randi_range(1, 3):
			by_color[color_index].append(_flower_xform(p + Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))))
		placed += 1
	for i: int in PETALS.size():
		var xforms: Array[Transform3D] = []
		for x: Variant in by_color[i]:
			xforms.append(x)
		_add_multimesh("Flowers_%d" % i, _flower_mesh(PETALS[i]), xforms)


func _flower_xform(p: Vector2) -> Transform3D:
	var s: float = _rng.randf_range(0.8, 1.25)
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, 0.0, p.y))


## 꽃 한 송이: 줄기 + 잎 두 장 + 다섯 갈래 꽃잎 + 노란 가운데 (삼각형 약 60개).
func _flower_mesh(petal: Color) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var stem: Color = Color("#5E9A4A")
	ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 0.3, 0.0), 0.012, 0.01, stem, 4)
	ClayMesh.add_ellipsoid(st, Vector3(0.05, 0.08, 0.0), Vector3(0.06, 0.012, 0.025), stem.lightened(0.1), 6, 2, Basis(Vector3.FORWARD, 0.5))
	ClayMesh.add_ellipsoid(st, Vector3(-0.045, 0.13, 0.0), Vector3(0.055, 0.012, 0.022), stem.lightened(0.1), 6, 2, Basis(Vector3.FORWARD, -0.5))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.31, 0.0), Vector3(0.085, 0.025, 0.085), petal, 10, 3, Basis(), ClayMesh.scallop_wobble(5, 0.55))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.33, 0.0), Vector3(0.03, 0.02, 0.03), Color("#F7C844"), 6, 2)
	return ClayMesh.commit(st)


## 풀 덤불: 가는 잎 다섯 가닥. 나무·바위·울타리 근처에 더 많이 모인다.
func _build_grass() -> void:
	var anchors: Array[Vector2] = []
	for tree: TreeInfo in GameData.trees.values():
		anchors.append(Vector2(tree.position.x, tree.position.z))
	for rock: VillageLayout.Rock in _layout.rocks:
		anchors.append(rock.position)
	var xforms: Array[Transform3D] = []
	var tries: int = 0
	var grass_count: int = int(float(_layout.grass_count) * Quality.density("grass"))
	while xforms.size() < grass_count and tries < grass_count * 20:
		tries += 1
		var p: Vector2 = _random_point()
		if _rng.randf() < 0.45 and not anchors.is_empty():
			var a: float = _rng.randf() * TAU
			p = anchors[_rng.randi() % anchors.size()] + Vector2(cos(a), sin(a)) * _rng.randf_range(0.7, 2.6)
		if _blocked(p, 0.2):
			continue
		var s: float = _rng.randf_range(0.7, 1.3)
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.2), s)), Vector3(p.x, 0.0, p.y)))
	var st: SurfaceTool = ClayMesh.begin()
	var blade: Callable = ClayMesh.vertical_gradient(Color("#4F8A3E"), Color("#9FD07A"), 0.8)
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0 + 0.3
		var lean: Vector3 = Vector3(cos(a), 0.0, sin(a)) * 0.09
		ClayMesh.add_rod(st, lean * 0.3, lean + Vector3(0.0, 0.22 + 0.05 * float(i % 3), 0.0), 0.03, 0.004, blade, 3)
	_add_multimesh("Grass", ClayMesh.commit(st), xforms)


func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(-scatter_extent, scatter_extent), _rng.randf_range(-scatter_extent, scatter_extent))


## 풀·들꽃이 나면 안 되는 자리: 바닷가, 길, 호수와 모래톱, 집, 상점·박물관·공항, 나무 밑동, 바위, 꽃밭.
func _blocked(p: Vector2, margin: float) -> bool:
	if not _layout.on_grass_land(p, margin + 0.5):
		return true
	if _layout.on_path(p, margin):
		return true
	for place: KeeperPlace in [GameData.museum, GameData.airport]:
		if place != null and _in_building(place, p, 1.0 + margin):
			return true
	var runway: Dictionary = GameData.airport.extra.get("runway", {}) if GameData.airport != null else {}
	if not runway.is_empty() and p.x > float(runway.x0) - 1.0 and p.x < float(runway.x1) + 1.0 and absf(p.y - float(runway.z)) < float(runway.width) * 0.5 + 1.0:
		return true
	for spot: SpotInfo in GameData.spots.values():
		if spot.has_outline():
			if spot.signed_distance(p) < _layout.lake_shore + margin:
				return true
			continue
		var q: Vector2 = (p - spot.center).abs() / (spot.half_extent + Vector2.ONE * (_layout.lake_shore + margin))
		if pow(q.x, _layout.lake_shape_power) + pow(q.y, _layout.lake_shape_power) < 1.0:
			return true
	for npc: NpcInfo in GameData.npcs.values():
		if npc.has_house and p.distance_to(Vector2(npc.house_position.x, npc.house_position.z)) < 3.2:
			return true
	for mirror: Vector3 in _layout.mirrors:
		if p.distance_to(Vector2(mirror.x, mirror.y)) < 1.2 + margin:
			return true
	var door: Vector2 = Vector2(GameData.shop.door.x, GameData.shop.door.z)
	if p.x > door.x - 5.5 and p.x < door.x + 5.5 and p.y < door.y + 1.5 and p.y > door.y - 8.0:
		return true
	for tree: TreeInfo in GameData.trees.values():
		if p.distance_to(Vector2(tree.position.x, tree.position.z)) < 0.6:
			return true
	for rock: VillageLayout.Rock in _layout.rocks:
		if p.distance_to(rock.position) < rock.size * 0.9:
			return true
	for bed: VillageLayout.FlowerBed in _layout.flower_beds:
		if p.distance_to(bed.center) < bed.radius:
			return true
	return false


## 건물 바닥 사각형 안인지 (앞면 가운데 기준, 앞면이 +Z).
static func _in_building(place: KeeperPlace, p: Vector2, pad: float) -> bool:
	var b: Vector3 = place.building_position
	var half_w: float = place.building_size.x * 0.5 + pad
	return p.x > b.x - half_w and p.x < b.x + half_w and p.y > b.z - place.building_size.y - pad and p.y < b.z + pad


## 바닷가: 모래사장을 따라 기우뚱한 야자수, 그리고 조개·불가사리.
func _build_beach() -> void:
	if _layout.island_half <= 0.0:
		return
	var palms: Array[Transform3D] = []
	var shells: Array[Transform3D] = []
	var stars: Array[Transform3D] = []
	var half: float = _layout.island_half
	var tries: int = 0
	var palm_total: int = int(float(palm_count) * Quality.density("palms"))
	while palms.size() < palm_total and tries < palm_total * 40:
		tries += 1
		var a: float = _rng.randf() * TAU
		var dir: Vector2 = Vector2(cos(a), sin(a))
		# 해안선에서 안쪽으로 모래사장 가운데쯤.
		var inset: float = _rng.randf_range(_layout.island_beach * 0.45, _layout.island_beach * 0.85)
		var r: float = half * (1.0 - inset / half) / _layout.island_shape(dir * half)
		var p: Vector2 = dir * r
		if _near_runway_or_building(p, 3.0):
			continue
		var too_close: bool = false
		for other: Transform3D in palms:
			if Vector2(other.origin.x, other.origin.z).distance_to(p) < 9.0:
				too_close = true
				break
		if too_close:
			continue
		# 바다 쪽으로 기울어 자란다.
		var lean: Basis = Basis(Vector3(dir.y, 0.0, -dir.x), -_rng.randf_range(0.12, 0.28))
		var s: float = _rng.randf_range(0.85, 1.2)
		palms.append(Transform3D(lean * Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, 0.0, p.y)))
		_add_collider(Vector3(p.x, 1.0, p.y), Vector3(0.6, 2.0, 0.6), 0.0)
	for i: int in 90:
		var a: float = _rng.randf() * TAU
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var inset: float = _rng.randf_range(1.2, _layout.island_beach - 1.0)
		var r: float = half * (1.0 - inset / half) / _layout.island_shape(dir * half)
		var p: Vector2 = dir * r
		if _near_runway_or_building(p, 1.0):
			continue
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3)), Vector3(p.x, 0.0, p.y))
		if i % 3 == 0:
			stars.append(xf)
		else:
			shells.append(xf)
	_add_multimesh("Palms", _palm_mesh(), palms)
	_add_multimesh("Shells", _shell_mesh(), shells)
	_add_multimesh("Starfish", _starfish_mesh(), stars)


func _near_runway_or_building(p: Vector2, pad: float) -> bool:
	for place: KeeperPlace in [GameData.museum, GameData.airport]:
		if place != null and _in_building(place, p, pad):
			return true
	var runway: Dictionary = GameData.airport.extra.get("runway", {}) if GameData.airport != null else {}
	return not runway.is_empty() and p.x > float(runway.x0) - pad and p.x < float(runway.x1) + pad and absf(p.y - float(runway.z)) < float(runway.width) * 0.5 + pad


## 야자수: 마디진 줄기 + 늘어진 잎 일곱 장 + 코코넛 셋 (삼각형 약 600개).
static func _palm_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var bark: Color = Color("#A9824E")
	var top: Vector3 = Vector3.ZERO
	for i: int in 6:
		var a: Vector3 = Vector3(0.05 * i * i * 0.08, 0.55 * i, 0.0)
		var b: Vector3 = Vector3(0.05 * (i + 1) * (i + 1) * 0.08, 0.55 * (i + 1), 0.0)
		ClayMesh.add_rod(st, a, b, 0.17 - 0.012 * i, 0.15 - 0.012 * i, bark.lightened(0.06 * float(i % 2)), 8)
		top = b
	var leaf: Callable = ClayMesh.vertical_gradient(Color("#3E7A3A"), Color("#7FBF5A"), 0.6)
	for k: int in 7:
		var a: float = TAU * float(k) / 7.0
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var mid: Vector3 = top + out * 0.75 + Vector3(0.0, 0.18, 0.0)
		ClayMesh.add_ellipsoid(st, mid, Vector3(0.85, 0.05, 0.22), leaf, 10, 3, Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -0.32))
		ClayMesh.add_ellipsoid(st, top + out * 1.45 - Vector3(0.0, 0.18, 0.0), Vector3(0.45, 0.04, 0.16), leaf, 8, 3, Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -0.75))
	for k: int in 3:
		var a: float = TAU * float(k) / 3.0 + 0.5
		ClayMesh.add_ellipsoid(st, top + Vector3(cos(a) * 0.17, -0.14, sin(a) * 0.17), Vector3(0.13, 0.14, 0.13), Color("#7A5230"), 8, 5)
	return ClayMesh.commit(st)


static func _shell_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.03, 0.0), Vector3(0.12, 0.05, 0.1), ClayMesh.vertical_gradient(Color("#E8B8A8"), Color("#FFF0E6"), 0.08), 10, 3, Basis(), ClayMesh.scallop_wobble(7, 0.35))
	return ClayMesh.commit(st)


static func _starfish_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0
		ClayMesh.add_ellipsoid(st, Vector3(cos(a) * 0.08, 0.02, sin(a) * 0.08), Vector3(0.1, 0.025, 0.04), Color("#F28A5A"), 6, 2, Basis(Vector3.UP, -a))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.03, 0.0), Vector3(0.05, 0.03, 0.05), Color("#F7A070"), 6, 2)
	return ClayMesh.commit(st)


func _add_mesh_instance(node_name: String, mesh: Mesh) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = clay_material
	add_child(mi)


func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = clay_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_collider(center: Vector3, size: Vector3, yaw: float) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), center)
