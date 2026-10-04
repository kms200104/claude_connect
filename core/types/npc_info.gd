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


static func from_dict(data: Dictionary) -> NpcInfo:
	var info: NpcInfo = NpcInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.personality = str(data.get("personality", "kind"))
	info.color = Color.html(str(data.get("color", "#FFFFFF")))
	info.about = str(data.get("about", ""))
	var house: Variant = data.get("house", {})
	if house is Dictionary:
		info.house_position = Vector3(float(house.get("x", 0.0)), 0.0, float(house.get("z", 0.0)))
		info.house_yaw = float(house.get("yaw", 0.0))
	var waypoints: Variant = data.get("waypoints", [])
	if waypoints is Array and not waypoints.is_empty() and waypoints[0] is Array:
		info.home = Vector3(float(waypoints[0][0]), 0.0, float(waypoints[0][1]))
	return info
