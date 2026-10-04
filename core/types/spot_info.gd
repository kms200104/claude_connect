class_name SpotInfo
extends RefCounted
## data/fish/spots.json 의 낚시터 한 곳 (x/z 중심, 반 너비/깊이로 된 사각형 수역).

var id: String = ""
var display_name: String = ""
var center: Vector2 = Vector2.ZERO
var half_extent: Vector2 = Vector2.ONE
var cast_range: float = 3.5


static func from_dict(data: Dictionary) -> SpotInfo:
	var info: SpotInfo = SpotInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.center = Vector2(float(data.get("x", 0.0)), float(data.get("z", 0.0)))
	info.half_extent = Vector2(float(data.get("half_x", 1.0)), float(data.get("half_z", 1.0)))
	info.cast_range = float(data.get("cast_range", 3.5))
	return info


## 수역 사각형까지의 거리 (안쪽이면 0). 서버의 distanceToSpot 과 같은 식.
func distance_to(position: Vector3) -> float:
	var dx: float = maxf(absf(position.x - center.x) - half_extent.x, 0.0)
	var dz: float = maxf(absf(position.z - center.y) - half_extent.y, 0.0)
	return Vector2(dx, dz).length()


## 수역 안쪽(가장자리에서 margin 만큼 들어간) 가장 가까운 점.
func clamp_inside(position: Vector3, margin: float = 0.4) -> Vector3:
	var hx: float = maxf(half_extent.x - margin, 0.0)
	var hz: float = maxf(half_extent.y - margin, 0.0)
	return Vector3(
		clampf(position.x, center.x - hx, center.x + hx),
		position.y,
		clampf(position.z, center.y - hz, center.y + hz))
