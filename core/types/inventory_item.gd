class_name InventoryItem
extends RefCounted
## 인벤토리 한 칸 (물고기 한 종류와 개수).

var id: String = ""
var count: int = 0


func _init(item_id: String = "", item_count: int = 0) -> void:
	id = item_id
	count = item_count
