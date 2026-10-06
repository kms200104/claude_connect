class_name EventInfo
extends RefCounted
## data/events/events.json 의 이벤트 한 종류 (보여 주기용 이름·설명·그림과 규칙 값). 언제 열릴지는 서버가 정한다.

const BARGAIN: String = "bargain"
const MERCHANT: String = "merchant"
const FISHING_DERBY: String = "fishing_derby"
const LUMBER_DAY: String = "lumber_day"
const GIFT_DAY: String = "gift_day"
const METEOR_SHOWER: String = "meteor_shower"

## 종류 (v0.12, 서버 events.js eventKind 와 같다): 같은 종류는 같은 규칙.
const KIND_BARGAIN: String = "bargain"
const KIND_VISITOR: String = "visitor"
const KIND_DERBY: String = "derby"
const KIND_LUMBER: String = "lumber"
const KIND_FLOWERS: String = "flowers"
const KIND_GIFT: String = "gift"
const KIND_METEOR: String = "meteor"
const KIND_ECONOMY: String = "economy"
const LEGACY_KIND: Dictionary[String, String] = {BARGAIN: KIND_BARGAIN, MERCHANT: KIND_VISITOR, FISHING_DERBY: KIND_DERBY, LUMBER_DAY: KIND_LUMBER, GIFT_DAY: KIND_GIFT, METEOR_SHOWER: KIND_METEOR}

var id: String = ""
var kind: String = ""
## 계절 축제면 그 계절들 (v0.12).
var seasons: PackedStringArray = []
## 광장 손님이 파는 값 배율 (v0.12, 중고 가구상 0.7).
var buy_mult: float = 1.0
## 낚시 대회가 열리는 낚시터 (비면 어디서나).
var spots: PackedStringArray = []
## 경제 소식의 효과 { type, delta | mult, item_kind } (v0.12).
var effect: Dictionary = {}
var display_name: String = ""
var description: String = ""
## 그림 이름: coin / merchant / fishing / axe / gift / star.
var icon: String = ""
## 사 주는 값 배율 (특가 매입·떠돌이 상인).
var multiplier: float = 1.0
## 떠돌이 상인이 파는 물건.
var stock: PackedStringArray = []
## 열리는 시각 [시작, 끝) (v16 달력에 보이기용, 비면 하루 종일).
var hours: PackedInt32Array = []
## 떠돌이 상인이 서는 자리와 방향.
var spot: Vector3 = Vector3.ZERO
var spot_yaw: float = 0.0
var npc: NpcInfo = null
## 낚시 대회 상금 (희귀도 → 솔).
var bonus: Dictionary[String, int] = {}
var drop_multiplier: int = 1


static func from_dict(data: Dictionary) -> EventInfo:
	var info: EventInfo = EventInfo.new()
	info.id = str(data.get("id", ""))
	info.kind = str(data.get("kind", LEGACY_KIND.get(info.id, info.id)))
	for s: Variant in data.get("seasons", []):
		info.seasons.append(str(s))
	info.buy_mult = float(data.get("buy_mult", 1.0))
	for h: Variant in data.get("hours", []):
		info.hours.append(int(h))
	for s: Variant in data.get("spots", []):
		info.spots.append(str(s))
	var fx: Variant = data.get("effect", {})
	info.effect = fx if fx is Dictionary else {}
	info.display_name = str(data.get("name", info.id))
	info.description = str(data.get("desc", ""))
	info.icon = str(data.get("icon", ""))
	info.multiplier = float(data.get("multiplier", 1.0))
	info.drop_multiplier = int(data.get("drop_multiplier", 1))
	for id: Variant in data.get("stock", []):
		info.stock.append(str(id))
	var at: Variant = data.get("spot", {})
	if at is Dictionary:
		info.spot = Vector3(float(at.get("x", 0.0)), 0.0, float(at.get("z", 0.0)))
		info.spot_yaw = float(at.get("yaw", 0.0))
	var npc_data: Variant = data.get("npc", null)
	if npc_data is Dictionary:
		info.npc = NpcInfo.from_dict(npc_data)
		info.npc.home = info.spot
	var bonus_data: Variant = data.get("bonus", {})
	if bonus_data is Dictionary:
		for rarity: Variant in bonus_data:
			info.bonus[str(rarity)] = int(bonus_data[rarity])
	return info
