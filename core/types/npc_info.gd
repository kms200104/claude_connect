class_name NpcInfo
extends RefCounted
## data/npcs/npcs.json 의 주민 한 명.

var id: String = ""
var display_name: String = ""
## kind(다정) / lively(활발) / lazy(느긋) / gruff(무뚝뚝) — 대사 묶음을 고른다.
var personality: String = "kind"
var color: Color = Color.WHITE
var about: String = ""
var house_position: Vector3 = Vector3.ZERO
var house_yaw: float = 0.0
var home: Vector3 = Vector3.ZERO
## 겉모습 (머리·옷 색). 없으면 주민 색 윗옷.
var look: CharacterLook = null
## 말소리 높이 (1 = 보통). 없으면 성격으로 정한다.
var voice: float = 1.0


static func from_dict(data: Dictionary) -> NpcInfo:
	var info: NpcInfo = NpcInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.personality = str(data.get("personality", "kind"))
	info.color = Color.html(str(data.get("color", "#FFFFFF")))
	info.about = str(data.get("about", ""))
	info.look = CharacterLook.from_dict(data.get("look"), info.color)
	var by_personality: Dictionary = {"kind": 0.9, "lively": 1.3, "lazy": 0.95, "gruff": 0.72, "shopkeeper": 1.1}
	info.voice = float(data.get("voice", by_personality.get(info.personality, 1.0)))
	var house: Variant = data.get("house", {})
	if house is Dictionary:
		info.house_position = Vector3(float(house.get("x", 0.0)), 0.0, float(house.get("z", 0.0)))
		info.house_yaw = float(house.get("yaw", 0.0))
	var waypoints: Variant = data.get("waypoints", [])
	if waypoints is Array and not waypoints.is_empty() and waypoints[0] is Array:
		info.home = Vector3(float(waypoints[0][0]), 0.0, float(waypoints[0][1]))
	return info
