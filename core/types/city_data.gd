class_name CityData
extends RefCounted
## data/world/city.json (v0.21 탕정 제2지구 강변도시, tools/art/gen_city.py 가 만든다):
## 도로 · 구역 · 회색 건물 · 곡교천(가운데 줄 · 북쪽 · 남쪽 가장자리) · 보 · 강 건너 침수 구역.
## 서버(world.js)는 건물 사각형만 놓기 · 심기 금지 자리로 쓰고, 나머지는 그림(CityTerrain · CityDistricts · 지도)에 쓴다.

class Road:
	var id: String = ""
	var name: String = ""
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	## 차도 너비 (m). 양쪽 인도는 CityData.sidewalk.
	var width: float = 12.0

	## 차도 + 인도 사각형 (XZ, 축에 나란한 길만).
	func rect(sidewalk: float) -> Rect2:
		var half: float = width * 0.5 + sidewalk
		var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		if is_zero_approx(a.y - b.y):
			return Rect2(lo.x, lo.y - half, hi.x - lo.x, half * 2.0)
		return Rect2(lo.x - half, lo.y, half * 2.0, hi.y - lo.y)

	func horizontal() -> bool:
		return is_zero_approx(a.y - b.y)


class Building:
	var id: String = ""
	var kind: String = ""
	var name: String = ""
	var center: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2.ONE
	var floors: int = 1
	var color: Color = Color.WHITE
	## 길가 상가의 앞면 (+1 = 남쪽(+Z), -1 = 북쪽, 0 = 정하지 않음).
	var front: int = 0

	func rect() -> Rect2:
		return Rect2(center - size * 0.5, size)


class District:
	var id: String = ""
	var name: String = ""
	var kind: String = ""
	var rect: Rect2 = Rect2()


var name: String = ""
var sidewalk: float = 3.0
var floor_height: float = 3.0
var roads: Array[Road] = []
var buildings: Array[Building] = []
var districts: Array[District] = []
## 곡교천: 가운데 줄 · 북쪽(도시 쪽) · 남쪽(강 건너) 가장자리 (x 가 커지는 순서).
var river_center: PackedVector2Array = PackedVector2Array()
var river_north: PackedVector2Array = PackedVector2Array()
var river_south: PackedVector2Array = PackedVector2Array()
var river_name: String = ""
## 보(수중보): x, 북쪽 · 남쪽 끝 z.
var weir: Vector3 = Vector3.ZERO
var bike_path_z: float = 128.0
var bike_path_width: float = 3.0
## 강 건너 침수 구역 다각형과 수면 높이, 둑이 터진 자리.
var flood_polygon: PackedVector2Array = PackedVector2Array()
var flood_level: float = 0.35
var flood_breach: Vector2 = Vector2.ZERO


static func from_dict(data: Dictionary) -> CityData:
	var city: CityData = CityData.new()
	city.name = str(data.get("name", ""))
	city.sidewalk = float(data.get("sidewalk", city.sidewalk))
	city.floor_height = float(data.get("floor_height", city.floor_height))
	for entry: Variant in data.get("roads", []):
		if entry is Dictionary:
			var road: Road = Road.new()
			road.id = str(entry.get("id", ""))
			road.name = str(entry.get("name", ""))
			road.a = _v2(entry.get("a", []))
			road.b = _v2(entry.get("b", []))
			road.width = float(entry.get("w", road.width))
			city.roads.append(road)
	for entry: Variant in data.get("buildings", []):
		if entry is Dictionary:
			var b: Building = Building.new()
			b.id = str(entry.get("id", ""))
			b.kind = str(entry.get("kind", ""))
			b.name = str(entry.get("name", ""))
			b.center = Vector2(float(entry.get("x", 0.0)), float(entry.get("z", 0.0)))
			b.size = Vector2(float(entry.get("w", 10.0)), float(entry.get("d", 10.0)))
			b.floors = int(entry.get("floors", 1))
			b.color = Color(str(entry.get("color", "#DDDDDD")))
			b.front = int(entry.get("front", 0))
			city.buildings.append(b)
	for entry: Variant in data.get("districts", []):
		if entry is Dictionary:
			var d: District = District.new()
			d.id = str(entry.get("id", ""))
			d.name = str(entry.get("name", ""))
			d.kind = str(entry.get("kind", ""))
			var r: Array = entry.get("rect", [0, 0, 0, 0])
			d.rect = Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
			city.districts.append(d)
	var river: Dictionary = data.get("river", {})
	city.river_name = str(river.get("name", ""))
	city.river_center = _points(river.get("centerline", []))
	city.river_north = _points(river.get("north", []))
	city.river_south = _points(river.get("south", []))
	var weir: Dictionary = data.get("weir", {})
	city.weir = Vector3(float(weir.get("x", 0.0)), float(weir.get("z0", 0.0)), float(weir.get("z1", 0.0)))
	var bike: Dictionary = data.get("bike_path", {})
	city.bike_path_z = float(bike.get("z", city.bike_path_z))
	city.bike_path_width = float(bike.get("w", city.bike_path_width))
	var flood: Dictionary = data.get("flood", {})
	city.flood_polygon = _points(flood.get("polygon", []))
	city.flood_level = float(flood.get("level", city.flood_level))
	city.flood_breach = _v2(flood.get("breach", []))
	return city


## 강 가장자리 z (x 에서, 선 사이를 이어서). edge = river_north 또는 river_south.
static func edge_z(edge: PackedVector2Array, x: float) -> float:
	if edge.is_empty():
		return 0.0
	if x <= edge[0].x:
		return edge[0].y
	for i: int in edge.size() - 1:
		if x <= edge[i + 1].x:
			var t: float = (x - edge[i].x) / maxf(edge[i + 1].x - edge[i].x, 0.001)
			return lerpf(edge[i].y, edge[i + 1].y, t)
	return edge[edge.size() - 1].y


func north_z(x: float) -> float:
	return edge_z(river_north, x)


func south_z(x: float) -> float:
	return edge_z(river_south, x)


## 이 자리가 들어 있는 구역 (없으면 null).
func district_at(p: Vector2) -> District:
	for d: District in districts:
		if d.rect.has_point(p):
			return d
	return null


## 도로(차도 + 인도) 위인지.
func on_road(p: Vector2, margin: float = 0.0) -> bool:
	for road: Road in roads:
		if road.rect(sidewalk).grow(margin).has_point(p):
			return true
	return false


static func _v2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _points(value: Variant) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if value is Array:
		for p: Variant in value:
			out.append(_v2(p))
	return out
