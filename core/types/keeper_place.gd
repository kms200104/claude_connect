class_name KeeperPlace
extends RefCounted
## 지기가 지키는 건물 (data/places/museum.json · airport.json): 건물 자리, 앞에 선 지기(관장·조종사), 곁에서 하는 일의 거리.

var display_name: String = ""
## 건물 앞면 가운데 바닥 (앞면이 +Z 를 보게 지은 뒤 building_yaw 만큼 돈다).
var building_position: Vector3 = Vector3.ZERO
var building_yaw: float = 0.0
## 가로 × 깊이.
var building_size: Vector2 = Vector2(10.0, 8.0)
var keeper: NpcInfo = null
var keeper_position: Vector3 = Vector3.ZERO
var keeper_yaw: float = 0.0
## 지기 곁에서 기증·사기를 할 수 있는 거리 (서버 판정과 같은 값).
var work_range: float = 3.2
## 공항 기념품 (아이템 id).
var stock: PackedStringArray = []
## 그 밖의 장소별 값 (박물관: aquarium · reward_sol · milestones, 공항: runway · flight).
var extra: Dictionary = {}


static func from_dict(data: Dictionary, keeper_key: String, range_key: String) -> KeeperPlace:
	var place: KeeperPlace = KeeperPlace.new()
	place.display_name = str(data.get("name", ""))
	var b: Dictionary = data.get("building", {})
	place.building_position = Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)))
	place.building_yaw = float(b.get("yaw", 0.0))
	place.building_size = Vector2(float(b.get("width", 10.0)), float(b.get("depth", 8.0)))
	var k: Dictionary = data.get(keeper_key, {})
	place.keeper = NpcInfo.from_dict(k)
	place.keeper_position = Vector3(float(k.get("x", 0.0)), 0.0, float(k.get("z", 0.0)))
	place.keeper_yaw = float(k.get("yaw", 0.0))
	place.keeper.home = place.keeper_position
	place.work_range = float(data.get(range_key, place.work_range))
	for id: Variant in data.get("stock", []):
		place.stock.append(str(id))
	place.extra = data
	return place


## 지기 곁인지 (서버와 같은 거리).
func near_keeper(position: Vector3) -> bool:
	return Vector2(position.x - keeper_position.x, position.z - keeper_position.z).length() <= work_range
