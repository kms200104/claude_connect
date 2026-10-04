class_name FishingSpot
extends Node3D
## 낚시터(수역). 위치와 크기는 data/fish/spots.json 에서 읽는다 — 서버가 판정에 쓰는 값과 같은 출처.

@export var spot_id: String = "pond"
@export var water: MeshInstance3D
## 수면 높이. 바닥(y=0)과 겹쳐 깜빡이지 않게 살짝 띄운다.
@export_range(0.0, 0.2, 0.005, "suffix:m") var water_height: float = 0.03

var info: SpotInfo = null


func _ready() -> void:
	info = GameData.spots.get(spot_id)
	if info == null:
		push_error("FishingSpot: spots.json 에 '%s' 가 없음" % spot_id)
		return
	global_position = Vector3(info.center.x, 0.0, info.center.y)
	if water != null:
		var plane: PlaneMesh = water.mesh
		plane.size = info.half_extent * 2.0
		# 월드 커브는 정점 단위로 휘므로, 수면도 1m 격자로 쪼개야 지면과 같이 휜다.
		plane.subdivide_width = maxi(int(plane.size.x), 1)
		plane.subdivide_depth = maxi(int(plane.size.y), 1)
		water.position = Vector3(0.0, water_height, 0.0)


## 서버 판정(cast_range)보다 약간 안쪽에서만 던질 수 있게 해서, 경계에서 서버에 거절당하지 않게 한다.
func can_cast_from(position: Vector3, safety_margin: float = 0.3) -> bool:
	return info != null and info.distance_to(position) <= info.cast_range - safety_margin
