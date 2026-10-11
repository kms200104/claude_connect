class_name WaterRules
extends RefCounted
## 보트가 다니는 물 · 내릴 땅 (v20). 서버 server/src/water.js 와 같은 규칙 · 같은 값.
##   호수: 윤곽(또는 사각형) 안쪽 LAKE_MARGIN m 부터 (물가 바로 앞까지는 못 붙는다).
##   바다: 섬 모양 값 SEA_MIN ~ SEA_MAX (해안선 바깥 몇 m 부터 섬 둘레 띠 — 그 너머 바다 건너에는 상점 · 집 안 실내가 있다).
##   내릴 땅: 호수 윤곽 바깥 LAND_LAKE m, 바닷가는 해안선 안쪽 LAND_COAST m (해안 벽 안) — 그리고 섬 안.

const LAKE_MARGIN: float = 1.0
const SEA_MIN: float = 1.05
const SEA_MAX: float = 1.3
const LAKE_LEVEL: float = 0.03
const SEA_LEVEL: float = -0.28
const LAND_LAKE: float = 0.8
const LAND_COAST: float = 1.5
## 보트를 띄울 트인 물: 둘레 이만큼이 모두 물.
const OPEN_R: float = 1.2


## 이 자리의 보트 물 (낚시터 id, 물이 아니면 빈 문자열).
static func water_at(p: Vector2) -> String:
	for spot: SpotInfo in GameData.spots.values():
		if spot.is_sea:
			continue
		if absf(p.x - spot.center.x) > spot.half_extent.x or absf(p.y - spot.center.y) > spot.half_extent.y:
			continue
		if spot.signed_distance(p) <= -LAKE_MARGIN:
			return spot.id
	var sea: SpotInfo = GameData.sea_spot
	if sea != null and GameData.layout != null and GameData.layout.island_half > 0.0:
		var s: float = GameData.layout.island_shape(p)
		if s >= SEA_MIN and s <= SEA_MAX:
			return sea.id
	return ""


static func is_water(p: Vector2) -> bool:
	return not water_at(p).is_empty()


## 그 물의 수면 높이 (바다 · 호수).
static func level(spot_id: String) -> float:
	return SEA_LEVEL if GameData.sea_spot != null and spot_id == GameData.sea_spot.id else LAKE_LEVEL


static func level_at(p: Vector2) -> float:
	return level(water_at(p))


## 걸어 내릴 수 있는 땅인지 (호수 · 바다에서 충분히 떨어진 섬 안).
static func is_land(p: Vector2) -> bool:
	for spot: SpotInfo in GameData.spots.values():
		if spot.is_sea:
			continue
		if spot.signed_distance(p) < LAND_LAKE:
			return false
	var layout: VillageLayout = GameData.layout
	if layout == null or layout.island_half <= 0.0:
		return true
	return (layout.island_shape(p) - 1.0) * layout.island_half <= -LAND_COAST


## p 둘레 max_d 안에서 가장 가까운 내릴 땅 (없으면 Vector2.INF). 가까운 고리부터 24 방향씩 찾는다.
static func landing_near(p: Vector2, max_d: float) -> Vector2:
	return _search(p, max_d, func(q: Vector2) -> bool: return is_land(q))


## p 둘레 max_d 안에서 가장 가까운 트인 보트 물 (없으면 Vector2.INF).
## 둘레 OPEN_R m 도 모두 물인 곳만 — 물가의 좁은 웅덩이 · 갈라진 틈에 띄워 꼼짝 못 하게 되지 않도록.
static func water_near(p: Vector2, max_d: float) -> Vector2:
	return _search(p, max_d, func(q: Vector2) -> bool: return is_open_water(q))


static func is_open_water(p: Vector2) -> bool:
	if not is_water(p):
		return false
	for k: int in 8:
		if not is_water(p + Vector2.from_angle(TAU * float(k) / 8.0) * OPEN_R):
			return false
	return true


static func _search(p: Vector2, max_d: float, ok: Callable) -> Vector2:
	if bool(ok.call(p)):
		return p
	var r: float = 0.5
	while r <= max_d + 0.001:
		for k: int in 24:
			var q: Vector2 = p + Vector2.from_angle(TAU * float(k) / 24.0) * r
			if bool(ok.call(q)):
				return q
		r += 0.5
	return Vector2.INF
