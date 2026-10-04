class_name Footsteps
extends RefCounted
## 발소리: 걸은 거리가 보폭을 넘을 때마다 바닥에 맞는 소리(풀 · 흙길 · 나무 판자)를 낸다. 달릴 때는 쿵쿵 더 센 소리.
## 내 캐릭터는 위치 없는 소리, 상대 플레이어는 그 자리에서 나는 3D 소리로 낸다.

const WALK_STRIDE: float = 0.62
const RUN_STRIDE: float = 0.95

var _travelled: float = 0.0
var _index: int = 0


## moved: 이번 프레임에 수평으로 움직인 거리.
func advance(moved: float, running: bool, position: Vector3, positional: bool) -> void:
	if moved < 0.0005:
		_travelled = minf(_travelled, WALK_STRIDE * 0.5)
		return
	_travelled += moved
	var stride: float = RUN_STRIDE if running else WALK_STRIDE
	if _travelled < stride:
		return
	_travelled = 0.0
	_index += 1
	var id: String = "%s_%d" % [surface_sound(position, running), 1 + _index % (2 if surface_of(position) == "wood" else 3)]
	var volume: float = (-1.0 if running else -5.0) + (0.0 if positional else 0.0)
	if positional:
		Audio.play_at(id, position, volume - 2.0)
	else:
		Audio.play_sfx(id, volume)


static func surface_sound(position: Vector3, running: bool) -> String:
	var surface: String = surface_of(position)
	if surface == "wood":
		return "step_wood"
	if running:
		return "step_run"
	return "step_dirt" if surface == "dirt" else "step_grass"


## 발밑 바닥: wood(선착장·상점 안) / dirt(길·광장·모래톱) / grass.
static func surface_of(position: Vector3) -> String:
	var p: Vector2 = Vector2(position.x, position.z)
	if GameData.shop != null and GameData.shop.is_inside(position):
		return "wood"
	var layout: VillageLayout = GameData.layout
	if layout == null:
		return "grass"
	if layout.dock_size.x > 0.0 and layout.dock_rect().grow(0.1).has_point(p):
		return "wood"
	if layout.on_path(p, 0.1):
		return "dirt"
	for spot: SpotInfo in GameData.spots.values():
		var q: Vector2 = (p - spot.center).abs() / (spot.half_extent + Vector2.ONE * layout.lake_shore)
		if pow(q.x, layout.lake_shape_power) + pow(q.y, layout.lake_shape_power) < 1.0:
			return "dirt"
	return "grass"
