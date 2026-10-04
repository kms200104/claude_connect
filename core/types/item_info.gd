class_name ItemInfo
extends RefCounted
## 인벤토리에 들어가는 아이템 한 종류 (data/items/items.json 의 도구·재료, data/fish/fish.json 의 물고기).

const KIND_TOOL: String = "tool"
const KIND_MATERIAL: String = "material"
const KIND_FISH: String = "fish"
const KIND_GOODS: String = "goods"
const KIND_FURNITURE: String = "furniture"
const KIND_CLOTHING: String = "clothing"

var id: String = ""
var display_name: String = ""
var kind: String = KIND_MATERIAL
var description: String = ""
## 칸에 쓰는 짧은 이름 (두 글자 안팎). 없으면 이름 앞 두 글자.
var short_name: String = ""
## 아이콘 대신 칸에 칠하는 색.
var color: Color = Color.WHITE
## 물고기 희귀도 (common / uncommon / rare). 물고기가 아니면 빈 문자열.
var rarity: String = ""
## 상점에 팔 때 기본 가격 (0 = 못 판다).
var price: int = 0
## 상점에서 살 때 가격 (0 = 상점에 없음).
var buy_price: int = 0
## 옷이 들어가는 자리: hat / top (옷이 아니면 빈 문자열).
var wear_slot: String = ""
## 가구·옷 모양: 도형 목록 ({s, size, at, c}). PartMesh 가 메시로 만든다.
var model: Array = []


static func from_item_dict(data: Dictionary) -> ItemInfo:
	var info: ItemInfo = ItemInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.kind = str(data.get("kind", KIND_MATERIAL))
	info.description = str(data.get("desc", ""))
	info.short_name = str(data.get("abbr", info.display_name.left(2)))
	info.color = Color.html(str(data.get("color", "#FFFFFF")))
	info.price = int(data.get("price", 0))
	info.buy_price = int(data.get("buy", 0))
	info.wear_slot = str(data.get("wear", ""))
	var parts: Variant = data.get("model", [])
	if parts is Array:
		info.model = parts
	return info


static func from_fish(fish: FishInfo, description: String, sell_price: int = 0) -> ItemInfo:
	var info: ItemInfo = ItemInfo.new()
	info.id = fish.id
	info.display_name = fish.display_name
	info.kind = KIND_FISH
	info.description = description
	info.short_name = fish.display_name.left(2)
	info.rarity = fish.rarity
	info.price = sell_price
	match fish.rarity:
		"rare":
			info.color = Color(1.0, 0.78, 0.3)
		"uncommon":
			info.color = Color(0.5, 0.82, 0.6)
		_:
			info.color = Color(0.55, 0.72, 0.9)
	return info


func is_tool() -> bool:
	return kind == KIND_TOOL


func is_fish() -> bool:
	return kind == KIND_FISH


func is_furniture() -> bool:
	return kind == KIND_FURNITURE


func is_clothing() -> bool:
	return kind == KIND_CLOTHING


## 칸에서 쓰는 종류 이름.
func kind_label() -> String:
	match kind:
		KIND_TOOL:
			return "도구"
		KIND_FISH:
			return "물고기"
		KIND_GOODS:
			return "소지품"
		KIND_FURNITURE:
			return "가구"
		KIND_CLOTHING:
			return "옷 · 모자" if wear_slot == "hat" else "옷 · 상의"
		_:
			return "재료"
