class_name EventInfo
extends RefCounted
## data/events/events.json 의 이벤트 한 종류 (보여 주기용 이름·설명·그림과 규칙 값). 언제 열릴지는 서버가 정한다.

const BARGAIN: String = "bargain"
const MERCHANT: String = "merchant"
const FISHING_DERBY: String = "fishing_derby"
const LUMBER_DAY: String = "lumber_day"
const GIFT_DAY: String = "gift_day"
const METEOR_SHOWER: String = "meteor_shower"

var id: String = ""
var display_name: String = ""
var description: String = ""
## 그림 이름: coin / merchant / fishing / axe / gift / star.
var icon: String = ""
## 사 주는 값 배율 (특가 매입·떠돌이 상인).
var multiplier: float = 1.0
## 떠돌이 상인이 파는 물건.
var stock: PackedStringArray = []
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
