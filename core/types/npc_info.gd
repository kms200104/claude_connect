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
## 말버릇 (기분이 좋을 때 말끝에 붙는다).
var catchphrase: String = ""
var hobby: String = ""
## 성격을 이루는 특징 몇 개 ("다정함", "승부욕" …).
var traits: PackedStringArray = []
## 대화 주제별 이야기 (hobby / past / dream / food → 문장 목록).
var topics: Dictionary[String, PackedStringArray] = {}
## 다른 주민에 대한 생각 (주민 id → 한마디).
var opinions: Dictionary[String, String] = {}
## 친해지면 가르쳐 주는 감정표현 (순서대로).
var teaches: PackedStringArray = []


static func from_dict(data: Dictionary) -> NpcInfo:
	var info: NpcInfo = NpcInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.personality = str(data.get("personality", "kind"))
	info.color = Color.html(str(data.get("color", "#FFFFFF")))
	info.about = str(data.get("about", ""))
	info.look = CharacterLook.from_dict(data.get("look"), info.color)
	var by_personality: Dictionary = {"kind": 0.9, "lively": 1.3, "lazy": 0.95, "gruff": 0.72, "shopkeeper": 1.1, "snooty": 1.18, "dreamy": 1.08}
	info.voice = float(data.get("voice", by_personality.get(info.personality, 1.0)))
	info.catchphrase = str(data.get("catchphrase", ""))
	info.hobby = str(data.get("hobby", ""))
	for t: Variant in data.get("traits", []):
		info.traits.append(str(t))
	var topic_data: Variant = data.get("topics", {})
	if topic_data is Dictionary:
		for key: Variant in topic_data:
			var lines: PackedStringArray = []
			for line: Variant in topic_data[key]:
				lines.append(str(line))
			info.topics[str(key)] = lines
	for pair: Variant in data.get("teaches", []):
		if pair is Array and not pair.is_empty():
			info.teaches.append(str(pair[0]))
	var opinion_data: Variant = data.get("opinions", {})
	if opinion_data is Dictionary:
		for key: Variant in opinion_data:
			info.opinions[str(key)] = str(opinion_data[key])
	var house: Variant = data.get("house", {})
	if house is Dictionary:
		info.house_position = Vector3(float(house.get("x", 0.0)), 0.0, float(house.get("z", 0.0)))
		info.house_yaw = float(house.get("yaw", 0.0))
	var waypoints: Variant = data.get("waypoints", [])
	if waypoints is Array and not waypoints.is_empty() and waypoints[0] is Array:
		info.home = Vector3(float(waypoints[0][0]), 0.0, float(waypoints[0][1]))
	return info
