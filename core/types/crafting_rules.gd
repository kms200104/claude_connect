class_name CraftingRules
extends RefCounted
## v0.22 제작 (data/crafting/crafting.json — 서버 server/src/crafting.js 와 같은 파일 · 같은 등급 규칙).
## 등급 0 = 맨손(어디서나), 1 = 작업대(마을에 놓은 작업대 곁 · 작업대를 둔 집 안), 2 = 공용 작업대(공구 창고).

class Recipe:
	var id: String = ""
	var out: String = ""
	var n: int = 1
	var tier: int = 0
	var category: String = ""
	## [[아이템 id, 개수], …]
	var needs: Array[Array] = []


class Bench:
	var id: String = ""
	var name: String = ""
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var tier: int = 2


const TIER_NAMES: PackedStringArray = ["맨손", "작업대", "공용 작업대"]

var range_m: float = 2.6
var recipes: Array[Recipe] = []
var benches: Array[Bench] = []
## 작업대가 되는 가구 → 등급.
var bench_items: Dictionary[String, int] = {}
## [[id, 이름], …] (제작 창 칸 순서).
var categories: Array[Array] = []


static func from_dict(data: Dictionary) -> CraftingRules:
	var rules: CraftingRules = CraftingRules.new()
	rules.range_m = float(data.get("range", rules.range_m))
	for entry: Variant in data.get("recipes", []):
		if entry is Dictionary:
			var r: Recipe = Recipe.new()
			r.id = str(entry.get("id", ""))
			r.out = str(entry.get("out", r.id))
			r.n = int(entry.get("n", 1))
			r.tier = int(entry.get("tier", 0))
			r.category = str(entry.get("cat", ""))
			for need: Variant in entry.get("needs", []):
				if need is Dictionary:
					r.needs.append([str(need.get("item", "")), int(need.get("n", 1))])
			rules.recipes.append(r)
	for entry: Variant in data.get("public_benches", []):
		if entry is Dictionary:
			var b: Bench = Bench.new()
			b.id = str(entry.get("id", ""))
			b.name = str(entry.get("name", "공구 창고"))
			b.position = Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
			b.yaw = float(entry.get("yaw", 0.0))
			b.tier = int(entry.get("tier", 2))
			rules.benches.append(b)
	var items: Variant = data.get("bench_items", {})
	if items is Dictionary:
		for id: Variant in items:
			rules.bench_items[str(id)] = int(items[id])
	for entry: Variant in data.get("categories", []):
		if entry is Dictionary:
			rules.categories.append([str(entry.get("id", "")), str(entry.get("name", ""))])
	return rules


func recipe(id: String) -> Recipe:
	for r: Recipe in recipes:
		if r.id == id:
			return r
	return null


## 이 자리에서 쓸 수 있는 가장 높은 등급 (서버 benchTier 와 같다). placed = 마을에 놓인 가구 [[아이템, 자리]], home_items = 집 안 가구 아이템들 (집 안이면).
func tier_at(position: Vector3, placed: Array[Array], home_items: PackedStringArray = PackedStringArray(), inside_home: bool = false) -> int:
	var tier: int = 0
	if inside_home:
		for item: String in home_items:
			tier = maxi(tier, int(bench_items.get(item, 0)))
		return tier
	for b: Bench in benches:
		if _flat(position, b.position) <= range_m:
			tier = maxi(tier, b.tier)
	for entry: Array in placed:
		if bench_items.has(str(entry[0])) and _flat(position, entry[1]) <= range_m:
			tier = maxi(tier, int(bench_items[str(entry[0])]))
	return tier


## 가방(아이템 → 개수)으로 n 번 만들 수 있는지.
static func can_make(r: Recipe, have: Dictionary, n: int = 1) -> bool:
	for need: Array in r.needs:
		if int(have.get(need[0], 0)) < int(need[1]) * n:
			return false
	return true


## 가방으로 최대 몇 번 만들 수 있는지 (한 번에 10번까지).
static func max_batches(r: Recipe, have: Dictionary) -> int:
	var best: int = 10
	for need: Array in r.needs:
		best = mini(best, int(have.get(need[0], 0)) / maxi(int(need[1]), 1))
	return maxi(best, 0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
