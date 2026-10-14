class_name SurvivalRules
extends RefCounted
## v0.23 생존 규칙 (data/survival/survival.json + houses.json — 서버 server/src/survival.js 와 같은 파일).
## 빈집 · 뒤질 가구, 체력, 회복 아이템, 무기(피해 · 거리 · 불빛), 놓은 가구의 방어, 밤 크리처 종류.

class LootBox:
	var id: String = ""
	var kind: String = ""
	var house: String = ""
	var position: Vector3 = Vector3.ZERO
	## 로컬 (집 기준) 자리 · 가구 앞면 방향.
	var local: Vector2 = Vector2.ZERO
	var yaw: float = 0.0


class House:
	var id: String = ""
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var size: Vector2 = Vector2(10.0, 8.0)
	var wall: Color = Color.WHITE
	var roof: Color = Color.GRAY
	var boarded: bool = false
	var containers: Array[LootBox] = []

	## 집 안인지 (로컬 사각형).
	func contains(p: Vector3, margin: float = 0.0) -> bool:
		var q: Vector3 = Basis(Vector3.UP, yaw).inverse() * (p - position)
		return absf(q.x) <= size.x * 0.5 + margin and absf(q.z) <= size.y * 0.5 + margin


class Weapon:
	var damage: int = 1
	var range_m: float = 1.4
	var cooldown_ms: int = 650
	var light: float = 0.0


class CreatureKind:
	var id: String = ""
	var name: String = ""
	var hp: int = 5
	var speed: float = 1.5


var houses: Array[House] = []
var walls: Array[Array] = []
var containers: Dictionary[String, LootBox] = {}
var loot_range: float = 1.8
var kind_names: Dictionary[String, String] = {}
var max_hp: int = 10
var heal: Dictionary[String, int] = {}
var weapons: Dictionary[String, Weapon] = {}
var lights: Dictionary[String, float] = {}
var creature_kinds: Dictionary[String, CreatureKind] = {}
var night: Vector2i = Vector2i(20, 5)


static func from_dicts(rules: Dictionary, house_doc: Dictionary) -> SurvivalRules:
	var r: SurvivalRules = SurvivalRules.new()
	var loot: Dictionary = rules.get("loot", {})
	r.loot_range = float(loot.get("range", r.loot_range))
	var kinds: Dictionary = loot.get("kinds", {})
	for k: Variant in kinds:
		r.kind_names[str(k)] = str((kinds[k] as Dictionary).get("name", k))
	r.max_hp = int((rules.get("player", {}) as Dictionary).get("max_hp", 10))
	var heal: Dictionary = rules.get("heal", {})
	for id: Variant in heal:
		if not str(id).begins_with("_"):
			r.heal[str(id)] = int(heal[id])
	var weapons: Dictionary = rules.get("weapons", {})
	for id: Variant in weapons:
		if str(id).begins_with("_"):
			continue
		var w: Dictionary = weapons[id]
		var weapon: Weapon = Weapon.new()
		weapon.damage = int(w.get("damage", 1))
		weapon.range_m = float(w.get("range", 1.4))
		weapon.cooldown_ms = int(w.get("cooldown_ms", 650))
		weapon.light = float(w.get("light", 0.0))
		r.weapons[str(id)] = weapon
	var defense: Dictionary = rules.get("defense", {})
	for id: Variant in defense:
		if not str(id).begins_with("_") and (defense[id] as Dictionary).has("light"):
			r.lights[str(id)] = float(defense[id]["light"])
	var creatures: Dictionary = rules.get("creatures", {})
	var n: Array = creatures.get("night", [20, 5])
	r.night = Vector2i(int(n[0]), int(n[1]))
	var ck: Dictionary = creatures.get("kinds", {})
	for id: Variant in ck:
		var c: Dictionary = ck[id]
		var kind: CreatureKind = CreatureKind.new()
		kind.id = str(id)
		kind.name = str(c.get("name", id))
		kind.hp = int(c.get("hp", 5))
		kind.speed = float(c.get("speed", 1.5))
		r.creature_kinds[kind.id] = kind
	for w: Variant in house_doc.get("walls", []):
		r.walls.append(w)
	for h: Variant in house_doc.get("houses", []):
		if not h is Dictionary:
			continue
		var house: House = House.new()
		house.id = str(h.get("id", ""))
		house.position = Vector3(float(h.get("x", 0.0)), 0.0, float(h.get("z", 0.0)))
		house.yaw = float(h.get("yaw", 0.0))
		house.size = Vector2(float(h.get("w", 10.0)), float(h.get("d", 8.0)))
		house.wall = Color(str(h.get("wall", "#E8DCC6")))
		house.roof = Color(str(h.get("roof", "#4F7FA8")))
		house.boarded = bool(h.get("boarded", false))
		for c: Variant in h.get("containers", []):
			var box: LootBox = LootBox.new()
			box.id = str(c.get("id", ""))
			box.kind = str(c.get("kind", ""))
			box.house = house.id
			box.position = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
			box.local = Vector2(float(c.get("lx", 0.0)), float(c.get("lz", 0.0)))
			box.yaw = float(c.get("yaw", 0.0))
			house.containers.append(box)
			r.containers[box.id] = box
		r.houses.append(house)
	return r


func heal_of(item_id: String) -> int:
	return int(heal.get(item_id, 0))


## 손에 든 것의 무기 값 (없으면 맨손).
func weapon_of(item_id: String) -> Weapon:
	if weapons.has(item_id):
		return weapons[item_id]
	return weapons.get("hands", Weapon.new())


func is_night(hour: float) -> bool:
	return hour >= float(night.x) or hour < float(night.y) if night.x > night.y else hour >= float(night.x) and hour < float(night.y)


func kind_name(kind: String) -> String:
	return kind_names.get(kind, kind)


## 이 자리에 있는 빈집 (없으면 null).
func house_at(p: Vector3, margin: float = 0.0) -> House:
	for h: House in houses:
		if h.contains(p, margin):
			return h
	return null
