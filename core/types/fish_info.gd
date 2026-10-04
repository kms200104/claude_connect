class_name FishInfo
extends RefCounted
## data/fish/fish.json 의 물고기 한 종.

var id: String = ""
var display_name: String = ""
var size: String = "M"
var rarity: String = "common"
var hook_window_ms: int = 600


static func from_dict(data: Dictionary) -> FishInfo:
	var info: FishInfo = FishInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.size = str(data.get("size", "M"))
	info.rarity = str(data.get("rarity", "common"))
	info.hook_window_ms = int(data.get("hook_window_ms", 600))
	return info
