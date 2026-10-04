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
const ICON_DIR: String = "res://assets/icons/items"

## 자리(slot) 번호별 플레이어 캐릭터 이름. 대사의 {player} 자리에 들어간다.
const PLAYER_NAMES: PackedStringArray = ["보리", "새미"]

var fish: Dictionary[String, FishInfo] = {}
var spots: Dictionary[String, SpotInfo] = {}
## 물고기를 포함한 인벤토리 아이템 전체.
var items: Dictionary[String, ItemInfo] = {}
var trees: Dictionary[String, TreeInfo] = {}
var npcs: Dictionary[String, NpcInfo] = {}
## 나무를 베어 볼 수 있는 거리 (서버 판정과 같은 값).
var chop_range: float = 2.2
## 주민에게 말을 걸 수 있는 거리 (서버 판정과 같은 값).
var talk_range: float = 3.0

## 상점 데이터 (data/shop/shop.json): 문·실내 위치, 단계별 이름·포인트·진열품.
var shop: ShopData = null
## 마을 꾸밈 배치 (길·바위·울타리·꽃밭·선착장).
var layout: VillageLayout = null
## 마을 이벤트 종류 (id → 정보). 언제 열리는지는 서버가 알려 준다 (Net.events).
var events: Dictionary[String, EventInfo] = {}
## 선물·별 조각을 주울 수 있는 거리 (서버 판정과 같은 값).
var collect_range: float = 2.0

var _icons: Dictionary[String, Texture2D] = {}
var _dialogue: Dictionary = {}
var _choices: Dictionary = {}


func _ready() -> void:
	for entry: Variant in _read_json(FISH_PATH).get("fish", []):
		if entry is Dictionary:
			var info: FishInfo = FishInfo.from_dict(entry)
			fish[info.id] = info
			items[info.id] = ItemInfo.from_fish(info, str(entry.get("desc", "")), int(entry.get("price", 0)))
	for entry: Variant in _read_json(SPOTS_PATH).get("spots", []):
		if entry is Dictionary:
			var spot: SpotInfo = SpotInfo.from_dict(entry)
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
	for entry: Variant in npcs_file.get("npcs", []):
		if entry is Dictionary:
			var npc: NpcInfo = NpcInfo.from_dict(entry)
			npcs[npc.id] = npc
	var dialogue_file: Dictionary = _read_json(DIALOGUE_PATH)
	_dialogue = dialogue_file.get("personalities", {})
	_choices = dialogue_file.get("choices", {})
	shop = ShopData.from_dict(_read_json(SHOP_PATH))
	layout = VillageLayout.from_dict(_read_json(LAYOUT_PATH))
	var events_file: Dictionary = _read_json(EVENTS_PATH)
	collect_range = float(events_file.get("collect_range", collect_range))
	for group: String in ["daily", "night"]:
		for entry: Variant in events_file.get(group, []):
			if entry is Dictionary:
				var ev: EventInfo = EventInfo.from_dict(entry)
				events[ev.id] = ev


func fish_name(id: String) -> String:
	var info: FishInfo = fish.get(id)
	return info.display_name if info != null else id


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


func event_info(id: String) -> EventInfo:
	return events.get(id)


func item_name(id: String) -> String:
	var info: ItemInfo = items.get(id)
	return info.display_name if info != null else id


func npc_name(id: String) -> String:
	var info: NpcInfo = npcs.get(id)
	return info.display_name if info != null else id


func player_name(slot: int) -> String:
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


## 대화 선택지 문구 (accept / decline / turn_in / not_yet / bye).
func choice_text(key: String) -> String:
	return str(_choices.get(key, key))


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("GameData: %s 를 읽을 수 없음" % path)
	return {}
