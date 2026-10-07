extends Node
## 정적 게임 데이터(data/) 조회. 서버와 같은 JSON 파일을 읽는다.

const FISH_PATH: String = "res://data/fish/fish.json"
const SPOTS_PATH: String = "res://data/fish/spots.json"
const ITEMS_PATH: String = "res://data/items/items.json"
const TREES_PATH: String = "res://data/world/trees.json"
const NPCS_PATH: String = "res://data/npcs/npcs.json"
const DIALOGUE_PATH: String = "res://data/npcs/dialogue.json"
const SHOP_PATH: String = "res://data/shop/shop.json"
const LAYOUT_PATH: String = "res://data/world/village_layout.json"
const EVENTS_PATH: String = "res://data/events/events.json"
const PLANTS_PATH: String = "res://data/plants/plants.json"
const EMOTES_PATH: String = "res://data/emotes/emotes.json"
const MUSEUM_PATH: String = "res://data/places/museum.json"
const AIRPORT_PATH: String = "res://data/places/airport.json"
const FACE_PATH: String = "res://data/looks/face_parts.json"
const MBTI_PATH: String = "res://data/npcs/mbti.json"
const ACHIEVEMENTS_PATH: String = "res://data/achievements/achievements.json"
const ICON_DIR: String = "res://assets/icons/items"

## 자리(slot) 번호별 플레이어 캐릭터 이름. 대사의 {player} 자리에 들어간다.
const PLAYER_NAMES: PackedStringArray = ["보리", "새미"]

var fish: Dictionary[String, FishInfo] = {}
var spots: Dictionary[String, SpotInfo] = {}
## 바다 낚시터 (v0.12, 섬 둘레 바닷가 어디서나). 없으면 null.
var sea_spot: SpotInfo = null
## 물고기를 포함한 인벤토리 아이템 전체.
var items: Dictionary[String, ItemInfo] = {}
var trees: Dictionary[String, TreeInfo] = {}
var npcs: Dictionary[String, NpcInfo] = {}
## 나무를 베어 볼 수 있는 거리 (서버 판정과 같은 값).
var chop_range: float = 2.2
## 주민에게 말을 걸 수 있는 거리 (서버 판정과 같은 값).
var talk_range: float = 3.0
## 마을톡 규칙과 주민 문자 (data/messenger/messenger.json, v0.11). 테스트 서버가 쓴다.
var messenger: Dictionary = {}
## 친한 주민이 먼저 다가와 말 걸기 규칙 (data/npcs/npcs.json 의 approach, v0.11).
var npc_approach: Dictionary = {}

## 상점 데이터 (data/shop/shop.json): 문·실내 위치, 단계별 이름·포인트·진열품.
var shop: ShopData = null
## 마을 꾸밈 배치 (길·바위·울타리·꽃밭·선착장).
var layout: VillageLayout = null
## 마을 이벤트 종류 (id → 정보). 언제 열리는지는 서버가 알려 준다 (Net.events).
var events: Dictionary[String, EventInfo] = {}
## 선물·별 조각을 주울 수 있는 거리 (서버 판정과 같은 값).
var collect_range: float = 2.0
## 꽃 종류 (id → 정보).
var flowers: Dictionary[String, FlowerSpecies] = {}
## 씨앗을 심을 수 있는 거리, 나무·꽃끼리 떨어져야 하는 거리 (서버 판정과 같은 값).
var plant_range: float = 2.2
var tree_clearance: float = 2.2
var flower_clearance: float = 0.85
## 감정표현 (순서 = 감정표현 창에 늘어놓는 순서).
var emotes: Array[EmoteInfo] = []
var emote_quick_slots: int = 4
## 박물관 · 공항.
var museum: KeeperPlace = null
## 얼굴 꾸미기 목록 (눈·코·입·피부·머리 모양·머리 색).
var face: FaceCatalog = null
## 주민 MBTI 표 (types 별명, empathy 반응, topic_bias, lines 대사).
var mbti: Dictionary = {}
var airport: KeeperPlace = null
## 경제 (v8): 증권 종목 · 아파트 · 은행 · 식당 요리와 손님.
var econ: EconData = null
## 일거리 (v0.12): 배달 알바 거리.
var jobs: JobRules = JobRules.new()
## v16 업적 (데이터 순서 그대로) · id → 업적 · 판정 값 이름 → 설명.
var achievements: Array[AchievementInfo] = []
var achievement_by_id: Dictionary[String, AchievementInfo] = {}
var stat_names: Dictionary[String, String] = {}

var _icons: Dictionary[String, Texture2D] = {}
var _dialogue: Dictionary = {}
var _choices: Dictionary = {}
## 물고기를 낚았을 때의 외침 (희귀도 → 문장 목록).
var _catch_shouts: Dictionary = {}


func _ready() -> void:
	for entry: Variant in _read_json(FISH_PATH).get("fish", []):
		if entry is Dictionary:
			var info: FishInfo = FishInfo.from_dict(entry)
			fish[info.id] = info
			items[info.id] = ItemInfo.from_fish(info, str(entry.get("desc", "")), int(entry.get("price", 0)))
	for entry: Variant in _read_json(SPOTS_PATH).get("spots", []):
		if entry is Dictionary:
			var spot: SpotInfo = SpotInfo.from_dict(entry)
			# 바다(v0.12)는 사각형 낚시터 목록과 따로 둔다 (호수 둘레를 도는 코드가 바다를 사각형으로 보지 않게).
			if spot.is_sea:
				sea_spot = spot
			else:
				spots[spot.id] = spot
	for entry: Variant in _read_json(ITEMS_PATH).get("items", []):
		if entry is Dictionary:
			var item: ItemInfo = ItemInfo.from_item_dict(entry)
			items[item.id] = item
	var trees_file: Dictionary = _read_json(TREES_PATH)
	chop_range = float(trees_file.get("chop_range", chop_range))
	for entry: Variant in trees_file.get("trees", []):
		if entry is Dictionary:
			var tree: TreeInfo = TreeInfo.from_dict(entry)
			trees[tree.id] = tree
	var npcs_file: Dictionary = _read_json(NPCS_PATH)
	talk_range = float(npcs_file.get("talk_range", talk_range))
	npc_approach = npcs_file.get("approach", {})
	messenger = _read_json("res://data/messenger/messenger.json")
	for entry: Variant in npcs_file.get("npcs", []):
		if entry is Dictionary:
			var npc: NpcInfo = NpcInfo.from_dict(entry)
			npcs[npc.id] = npc
	var dialogue_file: Dictionary = _read_json(DIALOGUE_PATH)
	_dialogue = dialogue_file.get("personalities", {})
	_choices = dialogue_file.get("choices", {})
	_catch_shouts = dialogue_file.get("catch_shouts", {})
	shop = ShopData.from_dict(_read_json(SHOP_PATH))
	layout = VillageLayout.from_dict(_read_json(LAYOUT_PATH))
	if sea_spot != null:
		sea_spot.island = layout
	var plants_file: Dictionary = _read_json(PLANTS_PATH)
	plant_range = float(plants_file.get("plant_range", plant_range))
	tree_clearance = float(plants_file.get("tree_clearance", tree_clearance))
	flower_clearance = float(plants_file.get("flower_clearance", flower_clearance))
	for entry: Variant in plants_file.get("flowers", []):
		if entry is Dictionary:
			var flower: FlowerSpecies = FlowerSpecies.from_dict(entry)
			flowers[flower.id] = flower
	var emotes_file: Dictionary = _read_json(EMOTES_PATH)
	emote_quick_slots = int(emotes_file.get("quick_slots", emote_quick_slots))
	for entry: Variant in emotes_file.get("emotes", []):
		if entry is Dictionary:
			emotes.append(EmoteInfo.from_dict(entry))
	museum = KeeperPlace.from_dict(_read_json(MUSEUM_PATH), "curator", "donate_range")
	face = FaceCatalog.from_dict(_read_json(FACE_PATH))
	mbti = _read_json(MBTI_PATH)
	airport = KeeperPlace.from_dict(_read_json(AIRPORT_PATH), "pilot", "shop_range")
	econ = EconData.load_all()
	jobs = JobRules.from_dict(_read_json("res://data/jobs/jobs.json"))
	econ.build_customers(npcs)
	var ach_file: Dictionary = _read_json(ACHIEVEMENTS_PATH)
	for key: Variant in ach_file.get("stats", {}):
		stat_names[str(key)] = str(ach_file["stats"][key])
	for entry: Variant in ach_file.get("list", []):
		if entry is Dictionary:
			var a: AchievementInfo = AchievementInfo.from_dict(entry)
			achievements.append(a)
			achievement_by_id[a.id] = a
	var events_file: Dictionary = _read_json(EVENTS_PATH)
	collect_range = float(events_file.get("collect_range", collect_range))
	for group: String in ["daily", "night", "economy"]:
		for entry: Variant in events_file.get(group, []):
			if entry is Dictionary:
				var ev: EventInfo = EventInfo.from_dict(entry)
				events[ev.id] = ev


func fish_name(id: String) -> String:
	var info: FishInfo = fish.get(id)
	return info.display_name if info != null else id


## 이 물고기가 낚이는 곳 이름 (v0.12: 마을 호수 · 성성호수 · 바다).
func fish_places(fish_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for spot: SpotInfo in spots.values():
		if fish_id in spot.fish_ids:
			out.append(spot.display_name)
	if sea_spot != null and fish_id in sea_spot.fish_ids:
		out.append(sea_spot.display_name)
	return out


## 바다에서만 낚이는 물고기인지.
func is_sea_fish(fish_id: String) -> bool:
	if sea_spot == null or not fish_id in sea_spot.fish_ids:
		return false
	for spot: SpotInfo in spots.values():
		if fish_id in spot.fish_ids:
			return false
	return true


func item(id: String) -> ItemInfo:
	return items.get(id)


## 아이템 아이콘 (assets/icons/items/<id>.png). 없으면 null — 칸은 색 동그라미로 대신 그린다.
func item_icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var path: String = "%s/%s.png" % [ICON_DIR, id]
	var icon: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[id] = icon
	return icon


func emote(id: String) -> EmoteInfo:
	for e: EmoteInfo in emotes:
		if e.id == id:
			return e
	return null


func emote_name(id: String) -> String:
	var e: EmoteInfo = emote(id)
	return e.display_name if e != null else id


## 주민·상점 주인·관장·조종사 누구든 id 로 찾는다.
func any_npc(id: String) -> NpcInfo:
	if npcs.has(id):
		return npcs[id]
	if shop != null and shop.keeper != null and shop.keeper.id == id:
		return shop.keeper
	if museum != null and museum.keeper.id == id:
		return museum.keeper
	if airport != null and airport.keeper.id == id:
		return airport.keeper
	# 광장 손님 (v0.12: 누리 · 바우 · 갈매).
	for ev: EventInfo in events.values():
		if ev.npc != null and ev.npc.id == id:
			return ev.npc
	return null


## 대사 묶음이 있는지 (성격 · 키).
func has_dialogue(personality: String, key: String) -> bool:
	var pool: Variant = _dialogue.get(personality, {}).get(key, [])
	return pool is Array and not pool.is_empty()


func event_info(id: String) -> EventInfo:
	return events.get(id)


func item_name(id: String) -> String:
	var info: ItemInfo = items.get(id)
	return info.display_name if info != null else id


func npc_name(id: String) -> String:
	var info: NpcInfo = any_npc(id)
	return info.display_name if info != null else id


func player_name(slot: int) -> String:
	# v14: 정한 닉네임이 있으면 그것.
	var nick: String = str(Net.names.get(slot, ""))
	return nick if not nick.is_empty() else default_player_name(slot)


## 닉네임을 정하지 않았을 때의 자리 기본 이름.
func default_player_name(slot: int) -> String:
	return PLAYER_NAMES[(slot - 1) % PLAYER_NAMES.size()] if slot >= 1 else "친구"


## 성격별 대사 묶음에서 한 줄을 고르고 {player} {item} {n} {reward} {npc} 를 채운다. 대사가 없으면 빈 문자열.
func dialogue_line(personality: String, key: String, values: Dictionary = {}) -> String:
	var pool: Variant = _dialogue.get(personality, {}).get(key, [])
	if not pool is Array or pool.is_empty():
		return ""
	var line: String = str(pool[randi() % pool.size()])
	for token: String in values:
		line = line.replace("{%s}" % token, str(values[token]))
	return line


## MBTI 대사 묶음에서 한 줄 (data/npcs/mbti.json 의 lines). 없으면 빈 문자열.
func mbti_line(key: String, values: Dictionary = {}) -> String:
	var pool: Variant = (mbti.get("lines", {}) as Dictionary).get(key, [])
	if not pool is Array or pool.is_empty():
		return ""
	var line: String = str(pool[randi() % pool.size()])
	for token: String in values:
		line = line.replace("{%s}" % token, str(values[token]))
	return line


## MBTI 별명 ("사교적인 외교관").
func mbti_nick(type: String) -> String:
	return str((mbti.get("types", {}) as Dictionary).get(type, ""))


## 희귀도별 낚시 외침 ("와---!! 대어를 낚았어!"). {fish} 를 채운다.
func catch_shout(rarity: String, fish_name_text: String) -> String:
	var pool: Variant = _catch_shouts.get(rarity, _catch_shouts.get("common", []))
	if not pool is Array or pool.is_empty():
		return "%s을(를) 낚았다!" % fish_name_text
	return str(pool[randi() % pool.size()]).replace("{fish}", fish_name_text)


## 대화 선택지 문구 (accept / decline / turn_in / not_yet / bye).
func choice_text(key: String) -> String:
	return str(_choices.get(key, key))


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("GameData: %s 를 읽을 수 없음" % path)
	return {}


## 플레이어 겉모습: 자리별 옷 색 + 거울에서 고른 얼굴 (face 가 비면 자리 기본 얼굴).
func player_look(slot: int, face_ids: Dictionary = {}) -> CharacterLook:
	var look: CharacterLook = CharacterLook.for_player(slot)
	if face != null:
		look.apply_face(face.sanitize(face_ids, slot), face)
	return look
