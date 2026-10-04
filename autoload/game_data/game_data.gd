extends Node
## 정적 게임 데이터(data/) 조회. 서버와 같은 JSON 파일을 읽는다.

const FISH_PATH: String = "res://data/fish/fish.json"
const SPOTS_PATH: String = "res://data/fish/spots.json"

var fish: Dictionary[String, FishInfo] = {}
var spots: Dictionary[String, SpotInfo] = {}


func _ready() -> void:
	for entry: Variant in _read_json(FISH_PATH).get("fish", []):
		if entry is Dictionary:
			var info: FishInfo = FishInfo.from_dict(entry)
			fish[info.id] = info
	for entry: Variant in _read_json(SPOTS_PATH).get("spots", []):
		if entry is Dictionary:
			var spot: SpotInfo = SpotInfo.from_dict(entry)
			spots[spot.id] = spot


func fish_name(id: String) -> String:
	var info: FishInfo = fish.get(id)
	return info.display_name if info != null else id


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("GameData: %s 를 읽을 수 없음" % path)
	return {}
