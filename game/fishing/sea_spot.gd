class_name SeaSpot
extends FishingSpot
## 바다 낚시터 (v0.12): 섬 둘레 바닷가 어디서나 던진다. 수면 · 물 막이는 섬 지형(IslandTerrain)의 바다와 해안 벽을 쓰므로
## 여기서는 낚시터 정보(GameData.sea_spot)만 잇는다. 판정은 해안선까지의 거리 (서버 distanceToSpot 의 바다와 같은 식).

## 바다 수면 높이 (IslandTerrain.sea_level 과 같게). 찌가 이 높이에 뜬다.
@export_range(-2.0, 0.0, 0.01, "suffix:m") var sea_level: float = -0.28


func _ready() -> void:
	add_to_group(&"fishing_spots")
	water_height = sea_level
	info = GameData.sea_spot
	if info != null:
		spot_id = info.id
