class_name FishInfo
extends RefCounted
## data/fish/fish.json 의 물고기 한 종.

var id: String = ""
var display_name: String = ""
var size: String = "M"
var rarity: String = "common"
var hook_window_ms: int = 600
## 겉모습 (아이콘·모형용): 몸 모양 slim / carp / perch / trout / eel / catfish / goldfish / puffer / sturgeon.
var shape: String = "slim"
var body_color: Color = Color("#9A9A7A")
var belly_color: Color = Color("#EEE8D0")
var fin_color: Color = Color("#7A7A5A")
## 무늬: none / stripe(옆줄) / band(세로 띠) / spots(점).
var pattern: String = "none"
var accent_color: Color = Color("#4A4A3A")


static func from_dict(data: Dictionary) -> FishInfo:
	var info: FishInfo = FishInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.size = str(data.get("size", "M"))
	info.rarity = str(data.get("rarity", "common"))
	info.hook_window_ms = int(data.get("hook_window_ms", 600))
	var look: Variant = data.get("look", {})
	if look is Dictionary:
		info.shape = str(look.get("shape", info.shape))
		info.body_color = Color.html(str(look.get("body", info.body_color.to_html(false))))
		info.belly_color = Color.html(str(look.get("belly", info.belly_color.to_html(false))))
		info.fin_color = Color.html(str(look.get("fin", info.fin_color.to_html(false))))
		info.pattern = str(look.get("pattern", info.pattern))
		info.accent_color = Color.html(str(look.get("accent", info.accent_color.to_html(false))))
	return info
