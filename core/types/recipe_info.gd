class_name RecipeInfo
extends RefCounted
## 식당 요리 하나 (data/restaurant/recipes.json). 판정·값은 서버가 매기고, 여기서는 메뉴판·요리 동작·모형에 쓴다.

var id: String = ""
var display_name: String = ""
## 1~5. 식당 별점이 오르면 열린다 (restaurant.json 의 tier_stars).
var tier: int = 1
var price: int = 0
var tags: PackedStringArray = []
## [{item | item_any | fish, n}] — 서버의 pickIngredients 와 같은 뜻.
var ingredients: Array[Dictionary] = []
## 요리 동작 id 목록 (EconData.cook_steps 의 열쇠).
var steps: PackedStringArray = []
var desc: String = ""
## 접시 모형 (아이템 model 과 같은 형식, PartMesh 로 빚는다).
var model: Array = []


static func from_dict(data: Dictionary) -> RecipeInfo:
	var r: RecipeInfo = RecipeInfo.new()
	r.id = str(data.get("id", ""))
	r.display_name = str(data.get("name", r.id))
	r.tier = int(data.get("tier", 1))
	r.price = int(data.get("price", 0))
	for t: Variant in data.get("tags", []):
		r.tags.append(str(t))
	for ing: Variant in data.get("ingredients", []):
		if ing is Dictionary:
			r.ingredients.append(ing)
	for s: Variant in data.get("steps", []):
		r.steps.append(str(s))
	r.desc = str(data.get("desc", ""))
	var m: Variant = data.get("model", [])
	r.model = m if m is Array else []
	return r


## 재료를 사람이 읽는 글로 ("쌀 1 · 김 1", "흔한 물고기 1").
func ingredients_text() -> String:
	var parts: PackedStringArray = []
	for ing: Dictionary in ingredients:
		var n: int = int(ing.get("n", 1))
		if ing.has("item"):
			parts.append("%s %d" % [GameData.item_name(str(ing["item"])), n])
		elif ing.has("item_any"):
			var names: PackedStringArray = []
			for id: Variant in ing["item_any"]:
				names.append(GameData.item_name(str(id)))
			parts.append("%s %d" % ["/".join(names), n])
		else:
			parts.append("%s 물고기 %d" % [EconData.RARITY_NAMES.get(str(ing.get("fish", "common")), "아무"), n])
	return " · ".join(parts)


## 지금 가방(pantry: id → 개수)으로 만들 수 있는지. 서버 판정(pickIngredients)과 같은 규칙.
func can_make(pantry: Dictionary) -> bool:
	var left: Dictionary = pantry.duplicate()
	for ing: Dictionary in ingredients:
		var need: int = int(ing.get("n", 1))
		var pool: PackedStringArray = []
		if ing.has("item"):
			pool.append(str(ing["item"]))
		elif ing.has("item_any"):
			for id: Variant in ing["item_any"]:
				pool.append(str(id))
		else:
			pool = EconData.fish_up_to(str(ing.get("fish", "common")))
		for id: String in pool:
			var take: int = mini(need, int(left.get(id, 0)))
			if take > 0:
				left[id] = int(left[id]) - take
				need -= take
			if need == 0:
				break
		if need > 0:
			return false
	return true
