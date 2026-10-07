class_name SpotInfo
extends RefCounted
## data/fish/spots.json 의 낚시터 한 곳 (x/z 중심, 반 너비/깊이로 된 사각형 수역).

var id: String = ""
var display_name: String = ""
var center: Vector2 = Vector2.ZERO
var half_extent: Vector2 = Vector2.ONE
var cast_range: float = 3.5
## 실제 모양 윤곽 (게임 좌표 [x, z] 다각형, 반시계). 비어 있으면 center/half_extent 사각형이 곧 수역이다.
## 있으면 center/half_extent 는 그 윤곽의 바깥 사각형 — 서버 outline.js 와 같은 식으로 안팎·거리를 잰다.
var outline: PackedVector2Array = PackedVector2Array()
## 여울 (얕은 물, v9): [{ id, name, x, z, half_x, half_z, max, fish[] }] — 들어가서 뜰채로 물고기를 몬다. 나머지는 깊은 물.
var shallows: Array[Dictionary] = []
## 바다 (v0.12, kind: sea): 사각형 대신 섬 모양으로 — 해안선까지의 거리로 판정하고, 찌는 바다 쪽으로 던진다.
var is_sea: bool = false
## 바닷가에 설 수 있는 섬 모양 값의 끝 (서버 gamedata.js SEA_STAND_MAX).
const SEA_STAND_MAX: float = 1.06
var island: VillageLayout = null
## 낚이는 물고기 id.
var fish_ids: PackedStringArray = []


static func from_dict(data: Dictionary) -> SpotInfo:
	var info: SpotInfo = SpotInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.center = Vector2(float(data.get("x", 0.0)), float(data.get("z", 0.0)))
	info.half_extent = Vector2(float(data.get("half_x", 1.0)), float(data.get("half_z", 1.0)))
	info.cast_range = float(data.get("cast_range", 3.5))
	for pt: Variant in data.get("outline", []):
		if pt is Array and (pt as Array).size() >= 2:
			info.outline.append(Vector2(float(pt[0]), float(pt[1])))
	info.is_sea = str(data.get("kind", "")) == "sea"
	for id: Variant in data.get("fish", []):
		info.fish_ids.append(str(id))
	for z: Variant in data.get("shallows", []):
		if z is Dictionary:
			info.shallows.append(z)
	return info


## 윤곽(다각형)이 있는 수역인지.
func has_outline() -> bool:
	return outline.size() >= 3


## 수역까지의 거리 (안쪽이면 0). 서버의 distanceToSpot 과 같은 식. 바다는 해안선까지의 거리.
func distance_to(position: Vector3) -> float:
	if is_sea:
		if island == null:
			return INF
		# 해안선 너머 멀리 서 있다면 바다 건너 실내(상점 · 집 안)다 → 바다 낚시 아님 (서버 SEA_STAND_MAX 와 같다).
		var shape: float = island.island_shape(Vector2(position.x, position.z))
		if shape > SEA_STAND_MAX:
			return INF
		return maxf(0.0, (1.0 - shape) * island.island_half)
	return maxf(signed_distance(Vector2(position.x, position.z)), 0.0)


## 부호 있는 거리: 수역 안쪽이면 음수(경계까지), 바깥이면 양수.
func signed_distance(p: Vector2) -> float:
	if not has_outline():
		var dx: float = absf(p.x - center.x) - half_extent.x
		var dz: float = absf(p.y - center.y) - half_extent.y
		return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0)
	var box: Vector2 = (p - center).abs() - half_extent
	if maxf(box.x, box.y) > 8.0:
		return Vector2(maxf(box.x, 0.0), maxf(box.y, 0.0)).length()
	var d: float = boundary_nearest(p).distance_to(p)
	return -d if Geometry2D.is_point_in_polygon(p, outline) else d


## 수역 안(경계 포함)에서 p 와 가장 가까운 점.
func nearest_in_water(p: Vector2) -> Vector2:
	if not has_outline():
		return Vector2(
			clampf(p.x, center.x - half_extent.x, center.x + half_extent.x),
			clampf(p.y, center.y - half_extent.y, center.y + half_extent.y))
	if Geometry2D.is_point_in_polygon(p, outline):
		return p
	return boundary_nearest(p)


func boundary_nearest(p: Vector2) -> Vector2:
	var best: Vector2 = outline[0]
	var best_d: float = INF
	var n: int = outline.size()
	for i: int in n:
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % n])
		var d: float = c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


## 수역 안쪽(가장자리에서 margin 만큼 들어간) 가장 가까운 점.
func clamp_inside(position: Vector3, margin: float = 0.4) -> Vector3:
	if is_sea:
		return _sea_point(position, margin)
	if has_outline():
		var p: Vector2 = Vector2(position.x, position.z)
		if signed_distance(p) <= -margin:
			return position
		# 경계 가까이면: 가장 가까운 물 점 둘레에서, margin 만큼 안쪽이면서 p 에 가장 가까운 점을 고른다.
		var q: Vector2 = nearest_in_water(p)
		var best: Vector2 = q
		var best_d: float = INF
		for i: int in 24:
			var cand: Vector2 = q + Vector2.from_angle(TAU * float(i) / 24.0) * (margin + 0.05)
			if signed_distance(cand) <= -margin and cand.distance_squared_to(p) < best_d:
				best_d = cand.distance_squared_to(p)
				best = cand
		return Vector3(best.x, position.y, best.y)
	var hx: float = maxf(half_extent.x - margin, 0.0)
	var hz: float = maxf(half_extent.y - margin, 0.0)
	return Vector3(
		clampf(position.x, center.x - hx, center.x + hx),
		position.y,
		clampf(position.z, center.y - hz, center.y + hz))


## 바다: 섬 가운데에서 이 자리를 지나는 방향으로, 해안선 바깥 margin + 1.5m 이상 나간 점 (이미 바다면 그대로).
func _sea_point(position: Vector3, margin: float) -> Vector3:
	if island == null:
		return position
	var flat: Vector2 = Vector2(position.x, position.z)
	var shape: float = island.island_shape(flat)
	var want: float = 1.0 + (margin + 1.5) / island.island_half
	if shape >= want or shape <= 0.0001:
		return position
	var out: Vector2 = flat * (want / shape)
	return Vector3(out.x, position.y, out.y)


## 이 자리에서 가장 가까운 물이 여울인지 (서버 shallowAt 과 같은 식) — 얕은 곳에서 낚으면 작은 물고기.
func shallow_near(position: Vector3) -> Dictionary:
	var near: Vector2 = nearest_in_water(Vector2(position.x, position.z))
	for z: Dictionary in shallows:
		if absf(near.x - float(z["x"])) <= float(z["half_x"]) + 0.4 and absf(near.y - float(z["z"])) <= float(z["half_z"]) + 0.4:
			return z
	return {}
