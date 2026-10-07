class_name FishInfo
extends RefCounted
## data/fish/fish.json 의 물고기 한 종.

var id: String = ""
var display_name: String = ""
var size: String = "M"
var rarity: String = "common"
var hook_window_ms: int = 600
## 낚았을 때 나오는 한마디 ("붕어를 낚았다! 붕어빵엔 붕어가 없다던데…").
var catch_line: String = ""
var description: String = ""
## 잡히는 시간 [시작, 끝) (끝이 작으면 자정을 넘긴다). 비어 있으면 언제나.
var hours: PackedInt32Array = []
## 잡히는 날씨. 비어 있으면 아무 날씨.
var weathers: PackedStringArray = []
## 잡히는 계절 (v0.12: spring/summer/autumn/winter). 비어 있으면 사계절.
var seasons: PackedStringArray = []
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
	info.catch_line = str(data.get("catch", ""))
	info.description = str(data.get("desc", ""))
	var h: Variant = data.get("hours")
	if h is Array and h.size() == 2:
		info.hours = PackedInt32Array([int(h[0]), int(h[1])])
	var w: Variant = data.get("weather")
	if w is Array:
		for entry: Variant in w:
			info.weathers.append(str(entry))
	var se: Variant = data.get("seasons")
	if se is Array:
		for entry: Variant in se:
			info.seasons.append(str(entry))
	var look: Variant = data.get("look", {})
	if look is Dictionary:
		info.shape = str(look.get("shape", info.shape))
		info.body_color = Color.html(str(look.get("body", info.body_color.to_html(false))))
		info.belly_color = Color.html(str(look.get("belly", info.belly_color.to_html(false))))
		info.fin_color = Color.html(str(look.get("fin", info.fin_color.to_html(false))))
		info.pattern = str(look.get("pattern", info.pattern))
		info.accent_color = Color.html(str(look.get("accent", info.accent_color.to_html(false))))
	return info


## 이 시각·날씨(·계절)에 잡히는지 (서버 availableFish 와 같은 규칙). season 이 비어 있으면 계절은 보지 않는다.
func available(hour: float, weather: String, season: String = "") -> bool:
	if not weathers.is_empty() and not weather in weathers:
		return false
	if not season.is_empty() and not seasons.is_empty() and not season in seasons:
		return false
	if hours.size() != 2:
		return true
	var start: int = hours[0]
	var end: int = hours[1]
	return hour >= start and hour < end if start <= end else hour >= start or hour < end
