class_name EconData
extends RefCounted
## 경제 데이터 (data/market · realestate · bank · restaurant). 서버와 같은 파일을 읽고, 화면에 보여 줄 계산(시세·세금·금리 표)을
## 서버와 같은 식으로 한다. 실제 거래·이자·별점은 서버가 확정한다 (여기 값은 미리보기).

const MARKET_PATH: String = "res://data/market/stocks.json"
const APARTMENTS_PATH: String = "res://data/realestate/apartments.json"
const BANK_PATH: String = "res://data/bank/bank.json"
const RECIPES_PATH: String = "res://data/restaurant/recipes.json"
const RESTAURANT_PATH: String = "res://data/restaurant/restaurant.json"
const CIVIC_PATH: String = "res://data/civic/civic.json"
const DIG_PATH: String = "res://data/world/dig.json"
const FLOORPLANS_PATH: String = "res://data/realestate/floorplans.json"

const RARITY_RANK: Dictionary = {"common": 0, "uncommon": 1, "rare": 2}
const RARITY_NAMES: Dictionary = {"common": "흔한", "uncommon": "드문", "rare": "귀한"}
## 손님 취향 태그 → 한국어.
const TAG_NAMES: Dictionary = {"fishy": "생선", "savory": "짭짤", "light": "담백", "hearty": "든든", "fresh": "상큼", "spicy": "매콤", "sweet": "달콤", "fancy": "고급"}

## 아파트 한 호.
class Unit:
	var id: String = ""
	var building: String = ""
	var floor: int = 1
	var line: int = 1
	var type: String = ""

## 식당 손님 (주민 + 섬 밖 손님).
class Customer:
	var id: String = ""
	var display_name: String = ""
	var mbti: String = ""
	var villager: bool = false
	var likes: PackedStringArray = []
	var dislikes: PackedStringArray = []
	var about: String = ""
	var look: CharacterLook = null

var market: Dictionary = {}
var apartments: Dictionary = {}
var units: Array[Unit] = []
var bank: Dictionary = {}
var restaurant: Dictionary = {}
var cook_steps: Dictionary = {}
var recipes: Dictionary[String, RecipeInfo] = {}
## 메뉴판 순서 (단계 → 값).
var recipe_order: Array[RecipeInfo] = []
var customers: Dictionary[String, Customer] = {}
## 동사무소 (v9): 건물 · 직원 · 민원 · 정책 (data/civic/civic.json).
var civic: Dictionary = {}
## 삽 · 뜰채 규칙 (data/world/dig.json).
var dig: Dictionary = {}
## 집 안 (v0.10): 평면도 규칙(벽 높이·격자·집 안 자리·방 종류)과 평면도들.
var home_rules: Dictionary = {}
var plans: Dictionary[String, FloorPlan] = {}


static func load_all() -> EconData:
	var e: EconData = EconData.new()
	e.market = _read(MARKET_PATH)
	e.apartments = _read(APARTMENTS_PATH)
	e.bank = _read(BANK_PATH)
	e.restaurant = _read(RESTAURANT_PATH)
	e.civic = _read(CIVIC_PATH)
	e.dig = _read(DIG_PATH)
	e.home_rules = _read(FLOORPLANS_PATH)
	var raw_plans: Dictionary = e.home_rules.get("plans", {})
	for plan_id: String in raw_plans:
		e.plans[plan_id] = FloorPlan.from_dict(plan_id, raw_plans[plan_id])
	var recipes_file: Dictionary = _read(RECIPES_PATH)
	e.cook_steps = recipes_file.get("steps", {})
	for entry: Variant in recipes_file.get("recipes", []):
		if entry is Dictionary:
			var r: RecipeInfo = RecipeInfo.from_dict(entry)
			e.recipes[r.id] = r
			e.recipe_order.append(r)
	e._build_units()
	return e


## NPC 정보가 다 읽힌 뒤에 부른다 (주민 손님의 겉모습).
func build_customers(npcs: Dictionary[String, NpcInfo]) -> void:
	customers.clear()
	var tastes: Dictionary = restaurant.get("tastes", {})
	for npc: NpcInfo in npcs.values():
		var c: Customer = Customer.new()
		c.id = npc.id
		c.display_name = npc.display_name
		c.mbti = npc.mbti
		c.villager = true
		c.look = npc.look
		c.about = npc.about
		var taste: Dictionary = tastes.get(npc.id, {})
		c.likes = PackedStringArray(taste.get("likes", []))
		c.dislikes = PackedStringArray(taste.get("dislikes", []))
		customers[c.id] = c
	for entry: Variant in restaurant.get("visitors", []):
		if not entry is Dictionary:
			continue
		var v: Dictionary = entry
		var c: Customer = Customer.new()
		c.id = str(v.get("id", ""))
		c.display_name = str(v.get("name", c.id))
		c.mbti = str(v.get("mbti", ""))
		c.about = str(v.get("about", ""))
		c.likes = PackedStringArray(v.get("likes", []))
		c.dislikes = PackedStringArray(v.get("dislikes", []))
		var look_data: Variant = v.get("look", {})
		c.look = CharacterLook.from_dict(look_data, Color(str((look_data as Dictionary).get("top", "#E8B060")) if look_data is Dictionary else "#E8B060"))
		customers[c.id] = c


## 그 희귀도 이하 물고기 id (값싼 것부터 — 서버 pickIngredients 와 같은 순서).
static func fish_up_to(rarity: String) -> PackedStringArray:
	var limit: int = int(RARITY_RANK.get(rarity, 0))
	var list: Array[FishInfo] = []
	for f: FishInfo in GameData.fish.values():
		if int(RARITY_RANK.get(f.rarity, 0)) <= limit:
			list.append(f)
	list.sort_custom(func(a: FishInfo, b: FishInfo) -> bool: return GameData.item(a.id).price < GameData.item(b.id).price)
	var out: PackedStringArray = []
	for f: FishInfo in list:
		out.append(f.id)
	return out


# ---- 증권 ----

func stock(id: String) -> Dictionary:
	for s: Variant in market.get("stocks", []):
		if s is Dictionary and str(s.get("id", "")) == id:
			return s
	return {}


## 매수에 드는 돈 (수수료 포함).
func buy_cost(price: int, qty: int) -> int:
	var gross: int = price * qty
	return gross + ceili(float(gross) * float(market.get("fee_rate", 0.00015)))


## 매도로 받는 돈 (수수료·증권거래세 뺀 것).
func sell_proceeds(price: int, qty: int) -> int:
	var gross: int = price * qty
	return gross - ceili(float(gross) * float(market.get("fee_rate", 0.00015))) - ceili(float(gross) * float(market.get("sell_tax_rate", 0.0018)))


# ---- 아파트 ----

func complex_name() -> String:
	return str((apartments.get("complex", {}) as Dictionary).get("name", "아파트"))


func unit(id: String) -> Unit:
	for u: Unit in units:
		if u.id == id:
			return u
	return null


func type_info(type: String) -> Dictionary:
	return (apartments.get("types", {}) as Dictionary).get(type, {})


func buildings() -> Array:
	return apartments.get("buildings", [])


func floor_premium(floor: int) -> float:
	var p: float = 0.0
	for row: Variant in apartments.get("floor_premium", []):
		if row is Array and floor >= int(row[0]):
			p = float(row[1])
	return p


## 지금 시세 (만 원 단위).
func unit_price(u: Unit, index: float) -> int:
	var base: float = float(type_info(u.type).get("price", 0))
	var premium: float = 0.0
	for b: Variant in buildings():
		if b is Dictionary and str(b.get("id", "")) == u.building:
			premium = float(b.get("premium", 0.0))
	return roundi(base * (1.0 + floor_premium(u.floor) + premium) * index / 10000.0) * 10000


## 살 때 드는 돈 (집값 + 취득세 + 중개보수).
func purchase_total(price: int) -> int:
	return price + roundi(float(price) * float(apartments.get("acquisition_tax", 0.011))) + roundi(float(price) * float(apartments.get("broker_fee", 0.004)))


func weekly_rent(price: int) -> int:
	return roundi(float(price) * float(apartments.get("rent_yield", 0.035)) / 52.0)


func mortgage_limit(price: int) -> int:
	return floori(float(price) * float(apartments.get("ltv", 0.7)) / 10000.0) * 10000


# ---- 집 안 (v0.10) ----

## 그 호수의 평면도: 동의 plans 가 평형별로 바꿀 수 있고, 아니면 평형의 plan (서버 planIdOf 와 같다).
func plan_of(unit_id: String) -> FloorPlan:
	var u: Unit = unit(unit_id)
	if u == null:
		return null
	var plan_id: String = str(type_info(u.type).get("plan", ""))
	for b: Variant in buildings():
		if b is Dictionary and str(b.get("id", "")) == u.building:
			plan_id = str((b.get("plans", {}) as Dictionary).get(u.type, plan_id))
	return plans.get(plan_id)


## 그 호수 집 안의 월드 원점 (평면도 왼쪽 위). 서버 interiorOrigin 과 같다.
func home_origin(unit_id: String) -> Vector3:
	var g: Dictionary = home_rules.get("interiors", {})
	var index: int = -1
	for i: int in units.size():
		if units[i].id == unit_id:
			index = i
	if index < 0:
		return Vector3.ZERO
	var cols: int = int(g.get("cols", 3))
	return Vector3(float(g.get("x0", -185.0)) + (index % cols) * float(g.get("dx", 26.0)), 0.0, float(g.get("z0", -190.0)) + (index / cols) * float(g.get("dz", 19.5)))


## 동 공동 현관 앞 (집 구경을 시작하는 자리).
func lobby_of(building_id: String) -> Vector3:
	var lobby: Dictionary = home_rules.get("lobby", {})
	for b: Variant in buildings():
		if b is Dictionary and str(b.get("id", "")) == building_id:
			return Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)) + float(lobby.get("front", 4.2)))
	return Vector3.ZERO


func lobby_range() -> float:
	return float((home_rules.get("lobby", {}) as Dictionary).get("range", 2.4))


## 방 종류 정보 (이름 · 바닥 · 벽 없이 이어지는지).
func room_kind(kind: String) -> Dictionary:
	return (home_rules.get("kinds", {}) as Dictionary).get(kind, {})


# ---- 동사무소 ----

func program_def(id: String) -> Dictionary:
	for p: Variant in civic.get("programs", []):
		if p is Dictionary and str(p.get("id", "")) == id:
			return p
	return {}


func civil_service(id: String) -> Dictionary:
	for s: Variant in civic.get("civil", []):
		if s is Dictionary and str(s.get("id", "")) == id:
			return s
	return {}


func staff_of(desk: String) -> Dictionary:
	for s: Variant in civic.get("staff", []):
		if s is Dictionary and str(s.get("desk", "")) == desk:
			return s
	return {}


# ---- 식당 ----

func tier_stars() -> Array:
	return restaurant.get("tier_stars", [0, 0, 2.5, 3.3, 4.0, 4.6])


func step(step_id: String) -> Dictionary:
	return cook_steps.get(step_id, {})


func _build_units() -> void:
	units.clear()
	var line_types: Array = apartments.get("line_types", ["26"])
	var top: String = str(apartments.get("top_floor_type", ""))
	for b: Variant in buildings():
		if not b is Dictionary:
			continue
		var floors: int = int(b.get("floors", 1))
		var lines: int = int(b.get("lines", 1))
		# v0.10: 동마다 라인별 평형 (없으면 단지 공통).
		var building_types: Array = b.get("line_types", line_types)
		for fl: int in range(1, floors + 1):
			for line: int in range(1, lines + 1):
				var u: Unit = Unit.new()
				u.building = str(b.get("id", ""))
				u.floor = fl
				u.line = line
				u.type = top if fl == floors and not top.is_empty() else str(building_types[(line - 1) % building_types.size()])
				u.id = "%s-%d%02d" % [u.building, fl, line]
				units.append(u)


static func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("EconData: %s 를 읽을 수 없음" % path)
	return {}
