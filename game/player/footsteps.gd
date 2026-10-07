class_name Footsteps
extends RefCounted
## 발소리: 걸은 거리가 보폭을 넘을 때마다 발밑 재질에 맞는 소리를 낸다.
##   grass 풀밭 · dirt 흙길·모래톱·모래사장 · stone 광장(돌 포장) · wood 선착장·상점 안 · metal 공항 활주로 · water 바닷가 물기 있는 모래
## 비가 오면 바깥의 흙·돌 바닥은 물웅덩이(water) 소리. 풀·흙에서 달리면 쿵쿵 더 센 달리기 소리(step_run),
## 그 밖의 재질은 달려도 그 재질 소리를 조금 크게 낸다.
## 내 캐릭터는 위치 없는 소리, 상대 플레이어는 그 자리에서 나는 3D 소리로 낸다 (RemotePlayer 도 이 클래스).
## v0.13.3: 같은 박자에 발밑 파티클(FootFx)도 튄다 — 흙먼지 · 모래 · 풀잎 · 물방울. 걸으면 살짝, 달리면 세게.

## 보폭: 걷기 애니메이션(0.6초에 두 걸음)·달리기 애니메이션(0.4초에 두 걸음)과 발이 땅에 닿는 박자가 맞도록
## 걷기 4.5m/s ÷ 초당 3.3걸음, 달리기 7m/s ÷ 초당 5걸음.
const WALK_STRIDE: float = 1.35
const RUN_STRIDE: float = 1.4
## 재질별 소리 파일 수 (assets/audio/sfx/step_<재질>_<n>.wav).
const VARIANTS: Dictionary[String, int] = {"grass": 3, "dirt": 3, "run": 3, "wood": 2, "stone": 3, "metal": 2, "water": 2}
## 재질별 걷기 소리 크기 (dB). 달리면 +4.
const VOLUME: Dictionary[String, float] = {"grass": -5.0, "dirt": -5.0, "wood": -5.0, "stone": -6.0, "metal": -7.0, "water": -5.0}
## 바닷가에서 물기 있는 모래로 치는 폭 (해안선에서 m, 바닥 그림의 젖은 모래 띠와 같다).
const WET_BEACH: float = 2.5

var _travelled: float = 0.0
var _index: int = 0
## 지난 프레임 자리 (걸어가는 방향 → 발 뒤로 차올리는 쪽).
var _last: Vector3 = Vector3.INF
## 파티클을 낼지 (헤드리스 테스트 · 끄고 싶을 때).
var particles: bool = true


## moved: 이번 프레임에 수평으로 움직인 거리.
func advance(moved: float, running: bool, position: Vector3, positional: bool) -> void:
	var back: Vector3 = Vector3.ZERO
	if _last != Vector3.INF:
		back = Vector3(_last.x - position.x, 0.0, _last.z - position.z)
		back = back.normalized() if back.length() > 0.0001 else Vector3.ZERO
	_last = position
	if moved < 0.0005:
		_travelled = minf(_travelled, WALK_STRIDE * 0.5)
		return
	_travelled += moved
	var stride: float = RUN_STRIDE if running else WALK_STRIDE
	if _travelled < stride:
		return
	_travelled = 0.0
	_index += 1
	var sound: String = surface_sound(position, running)
	var material: String = sound.trim_prefix("step_")
	var id: String = "%s_%d" % [sound, 1 + _index % int(VARIANTS.get(material, 2))]
	var volume: float = float(VOLUME.get(surface_of(position), -5.0)) + (4.0 if running else 0.0)
	if positional:
		Audio.play_at(id, position, volume - 2.0)
	else:
		Audio.play_sfx(id, volume)
	if particles and DisplayServer.get_name() != "headless":
		FootFx.step(position, particle_surface(position), running, back)


## 파티클 재질: 발소리 재질에서 모래사장(밝은 모래)과 비 오는 날 물기를 따로 고른다.
static func particle_surface(position: Vector3) -> String:
	var surface: String = surface_of(position)
	if (surface == "dirt" or surface == "stone") and is_raining_outside(position):
		return "water"
	if surface == "dirt" and GameData.layout != null and not GameData.layout.on_grass_land(Vector2(position.x, position.z), -1.0):
		return "sand"
	return surface


## 이 자리·이 걸음에 낼 소리 이름 (step_grass, step_run, step_stone …). 비 오는 바깥의 흙·돌은 물웅덩이.
static func surface_sound(position: Vector3, running: bool) -> String:
	var surface: String = surface_of(position)
	if (surface == "dirt" or surface == "stone") and is_raining_outside(position):
		surface = "water"
	if running and (surface == "grass" or surface == "dirt"):
		return "step_run"
	return "step_" + surface


## 비가 오고 바깥(상점 안이 아님)인지.
static func is_raining_outside(position: Vector3) -> bool:
	if Net.weather != NetProtocol.WEATHER_RAIN and Net.weather != NetProtocol.WEATHER_THUNDER:
		return false
	return GameData.shop == null or not GameData.shop.is_inside(position)


## 발밑 바닥: wood(선착장·상점 안) / metal(공항 활주로) / water(바닷가 젖은 모래) / dirt(모래사장·길·모래톱) /
## stone(큰 광장·박물관 앞·공항 앞 광장) / grass.
static func surface_of(position: Vector3) -> String:
	var p: Vector2 = Vector2(position.x, position.z)
	if GameData.shop != null and GameData.shop.is_inside(position):
		return "wood"
	var layout: VillageLayout = GameData.layout
	if layout == null:
		return "grass"
	# 해안선 너머 멀리 = 바다 건너 실내 (아파트 집 안): 마루.
	if layout.island_half > 0.0 and layout.island_shape(p) > SpotInfo.SEA_STAND_MAX:
		return "wood"
	if layout.dock_size.x > 0.0 and layout.dock_rect().grow(0.1).has_point(p):
		return "wood"
	if GameData.airport != null:
		var runway: Dictionary = GameData.airport.extra.get("runway", {})
		if not runway.is_empty() and p.x >= float(runway.x0) and p.x <= float(runway.x1) and absf(p.y - float(runway.z)) <= float(runway.width) * 0.5:
			return "metal"
	if not layout.on_grass_land(p, -1.0):
		# 모래사장: 해안선 가까이 젖은 띠는 철벅철벅.
		var to_coast: float = (1.0 - layout.island_shape(p)) * layout.island_half
		return "water" if layout.island_half > 0.0 and to_coast < WET_BEACH else "dirt"
	if p.distance_to(layout.plaza_center) <= layout.plaza_radius + 0.1:
		return "stone"
	for plaza: Vector3 in layout.plazas:
		if p.distance_to(Vector2(plaza.x, plaza.y)) <= plaza.z + 0.1:
			return "stone"
	if layout.on_path(p, 0.1):
		return "dirt"
	# 여울(얕은 물)에 들어가 있으면 첨벙첨벙 (v9).
	if not Field.zone_at(Vector3(p.x, 0.0, p.y), 0.1).is_empty():
		return "water"
	if not Field.tile_at(roundi(p.x), roundi(p.y)).is_empty():
		return "dirt"
	for spot: SpotInfo in GameData.spots.values():
		if spot.has_outline():
			if spot.signed_distance(p) < layout.lake_shore:
				return "dirt"
			continue
		var q: Vector2 = (p - spot.center).abs() / (spot.half_extent + Vector2.ONE * layout.lake_shore)
		if pow(q.x, layout.lake_shape_power) + pow(q.y, layout.lake_shape_power) < 1.0:
			return "dirt"
	return "grass"
