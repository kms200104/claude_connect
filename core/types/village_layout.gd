class_name VillageLayout
extends RefCounted
## data/world/village_layout.json: 바닥 그림(길·광장·모래톱)과 장식(바위·울타리·꽃밭·풀·선착장) 배치.
## 서버 판정에는 쓰지 않는 순수 꾸밈 데이터. 바닥 텍스처는 tools/art/gen_ground.py 가 같은 파일로 만든다.

class Rock:
	var position: Vector2 = Vector2.ZERO
	var size: float = 1.0
	## 충돌체가 있는 큰 바위 (작은 돌은 그냥 지나간다).
	var solid: bool = false

class FlowerBed:
	var center: Vector2 = Vector2.ZERO
	var radius: float = 1.5
	var count: int = 20

var map_extent: float = 64.0
## 섬: 해안선 반경(둥근 사각형 |x/h|^p + |z/h|^p = 1), 모래사장 폭. half 가 0 이면 섬이 아니다 (끝없는 땅).
var island_half: float = 0.0
var island_power: float = 4.0
var island_beach: float = 8.0
## 큰 광장 말고 작은 광장들 (박물관 앞, 공항 앞).
var plazas: Array[Vector3] = []
## 마을에 놓인 거울: (x, z, yaw) — yaw 는 거울 앞면이 보는 방향 (+Z 를 yaw 만큼 돌린 쪽).
var mirrors: Array[Vector3] = []
var path_width: float = 2.6
var plaza_center: Vector2 = Vector2.ZERO
var plaza_radius: float = 6.0
## 길: 점 목록(x, z)의 목록.
var paths: Array[PackedVector2Array] = []
var lake_shore: float = 1.6
var lake_shape_power: float = 4.0
var rocks: Array[Rock] = []
var fences: Array[PackedVector2Array] = []
var flower_beds: Array[FlowerBed] = []
## 선착장: 가운데(x, z)에서 X 방향으로 length, Z 방향으로 width.
var dock_center: Vector2 = Vector2.ZERO
var dock_size: Vector2 = Vector2.ZERO
var grass_count: int = 0
var wild_flower_count: int = 0


static func from_dict(data: Dictionary) -> VillageLayout:
	var layout: VillageLayout = VillageLayout.new()
	layout.map_extent = float(data.get("map_extent", layout.map_extent))
	layout.path_width = float(data.get("path_width", layout.path_width))
	var plaza: Variant = data.get("plaza", {})
	if plaza is Dictionary:
		layout.plaza_center = Vector2(float(plaza.get("x", 0.0)), float(plaza.get("z", 0.0)))
		layout.plaza_radius = float(plaza.get("r", layout.plaza_radius))
	var island: Variant = data.get("island", {})
	if island is Dictionary and not island.is_empty():
		layout.island_half = float(island.get("half", 0.0))
		layout.island_power = float(island.get("power", 4.0))
		layout.island_beach = float(island.get("beach", 8.0))
	for entry: Variant in data.get("plazas", []):
		if entry is Dictionary:
			layout.plazas.append(Vector3(float(entry.get("x", 0.0)), float(entry.get("z", 0.0)), float(entry.get("r", 4.0))))
	for entry: Variant in data.get("mirrors", []):
		if entry is Dictionary:
			layout.mirrors.append(Vector3(float(entry.get("x", 0.0)), float(entry.get("z", 0.0)), float(entry.get("yaw", 0.0))))
	for line: Variant in data.get("paths", []):
		layout.paths.append(_points(line))
	layout.lake_shore = float(data.get("lake_shore", layout.lake_shore))
	layout.lake_shape_power = float(data.get("lake_shape_power", layout.lake_shape_power))
	for entry: Variant in data.get("rocks", []):
		if entry is Dictionary:
			var rock: Rock = Rock.new()
			rock.position = Vector2(float(entry.get("x", 0.0)), float(entry.get("z", 0.0)))
			rock.size = float(entry.get("size", 1.0))
			rock.solid = bool(entry.get("solid", false))
			layout.rocks.append(rock)
	for line: Variant in data.get("fences", []):
		layout.fences.append(_points(line))
	for entry: Variant in data.get("flower_beds", []):
		if entry is Dictionary:
			var bed: FlowerBed = FlowerBed.new()
			bed.center = Vector2(float(entry.get("x", 0.0)), float(entry.get("z", 0.0)))
			bed.radius = float(entry.get("r", 1.5))
			bed.count = int(entry.get("count", 20))
			layout.flower_beds.append(bed)
	var dock: Variant = data.get("dock", {})
	if dock is Dictionary and not dock.is_empty():
		layout.dock_center = Vector2(float(dock.get("x", 0.0)), float(dock.get("z", 0.0)))
		layout.dock_size = Vector2(float(dock.get("length", 0.0)), float(dock.get("width", 0.0)))
	layout.grass_count = int(data.get("grass_count", 0))
	layout.wild_flower_count = int(data.get("wild_flower_count", 0))
	return layout


## 길·광장 위인지 (가장자리에서 margin 만큼 더 넓게 본다).
func on_path(point: Vector2, margin: float = 0.0) -> bool:
	if point.distance_to(plaza_center) <= plaza_radius + margin:
		return true
	for p: Vector3 in plazas:
		if point.distance_to(Vector2(p.x, p.y)) <= p.z + margin:
			return true
	var half: float = path_width * 0.5 + margin
	for line: PackedVector2Array in paths:
		for i: int in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1]).distance_to(point) <= half:
				return true
	return false


## 섬 모양 값: 1 이면 해안선, 작을수록 안쪽 (서버 world.js 의 islandShape 와 같은 식).
func island_shape(point: Vector2) -> float:
	if island_half <= 0.0:
		return 0.0
	return pow(pow(absf(point.x / island_half), island_power) + pow(absf(point.y / island_half), island_power), 1.0 / island_power)


## 모래사장 안쪽 풀밭인지 (margin: 모래사장 폭에 더해 떨어질 거리).
func on_grass_land(point: Vector2, margin: float = 0.0) -> bool:
	return island_half <= 0.0 or island_shape(point) <= 1.0 - (island_beach + margin) / island_half


## 선착장 바닥 사각형 (XZ).
func dock_rect() -> Rect2:
	return Rect2(dock_center - dock_size * 0.5, dock_size)


static func _points(value: Variant) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if value is Array:
		for p: Variant in value:
			if p is Array and p.size() >= 2:
				points.append(Vector2(float(p[0]), float(p[1])))
	return points
