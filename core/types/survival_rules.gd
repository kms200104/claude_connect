class_name SurvivalRules
extends RefCounted
## v0.23 생존 규칙 (data/survival/survival.json + houses.json — 서버 server/src/survival.js 와 같은 파일).
## 빈집 · 뒤질 가구, 체력, 회복 아이템, 무기(피해 · 거리 · 불빛), 놓은 가구의 방어, 밤 크리처 종류.
## v0.24: 판자를 댈 수 있는 곳 (현관 · 깨진 창) · 판자 값 · 쓰러짐/일으키기.
## v0.25: 판자 대는 시간 · 거점 상자 · 침대 자리.

class LootBox:
	var id: String = ""
	var kind: String = ""
	var house: String = ""
	var position: Vector3 = Vector3.ZERO
	## 로컬 (집 기준) 자리 · 가구 앞면 방향.
	var local: Vector2 = Vector2.ZERO
	var yaw: float = 0.0


## 판자를 댈 수 있는 곳 (현관 · 깨진 창). key = "집:자리".
class Breach:
	var key: String = ""
	var house: String = ""
	var id: String = ""
	var kind: String = "window"
	## 로컬 가운데 · 바깥쪽.
	var local: Vector2 = Vector2.ZERO
	var normal: Vector2 = Vector2.ZERO
	var position: Vector3 = Vector3.ZERO
	var max_hp: int = 10


class House:
	var id: String = ""
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var size: Vector2 = Vector2(10.0, 8.0)
	var wall: Color = Color.WHITE
	var roof: Color = Color.GRAY
	var containers: Array[LootBox] = []
	## 깨진 창 id (현관과 함께 크리처가 들어오는 곳).
	var broken: PackedStringArray = []
	var breaches: Array[Breach] = []
	## 거점 상자 · 침대 (월드).
	var stash_position: Vector3 = Vector3.ZERO
	var bed_position: Vector3 = Vector3.ZERO

	## 집 안인지 (로컬 사각형).
	func contains(p: Vector3, margin: float = 0.0) -> bool:
		var q: Vector3 = Basis(Vector3.UP, yaw).inverse() * (p - position)
		return absf(q.x) <= size.x * 0.5 + margin and absf(q.z) <= size.y * 0.5 + margin


class Weapon:
	var damage: int = 1
	var range_m: float = 1.4
	var cooldown_ms: int = 650
	var light: float = 0.0
	## v0.28.5 쏠 때마다 쓰는 것 (석궁 화살, 없으면 빈 글자) · 비틀거리게 하는 시간 · 한 번에 베는 수.
	var ammo: String = ""
	var stun_ms: int = 0
	var cleave: int = 1
	## v0.28.9 직업 전용 (그 직업만, 아니면 맨손) · 치명타 확률 +.
	var job: String = ""
	var crit: float = 0.0


class CreatureKind:
	var id: String = ""
	var name: String = ""
	var hp: int = 5
	var speed: float = 1.5
	## v0.26 무게 (kg) — 탈것에 들이받힐 때.
	var mass: float = 70.0


var houses: Array[House] = []
var walls: Array[Array] = []
var containers: Dictionary[String, LootBox] = {}
var loot_range: float = 1.8
var kind_names: Dictionary[String, String] = {}
var max_hp: int = 10
var heal: Dictionary[String, int] = {}
## v0.28.7 배고픔 · 목마름: 최대 · 알림 기준 · 먹고 마실 것 (id → {food, water}).
var needs_max: int = 100
var needs_warn: int = 25
var nourish: Dictionary[String, Dictionary] = {}
## v0.28.7 회피 구르기 (ms · dist · iframe_ms · cooldown_ms).
var dodge_ms: int = 380
var dodge_cooldown_ms: int = 1800
var weapons: Dictionary[String, Weapon] = {}
## v0.28.9 들고 있지 않을 때 등에 메는 무기 (가방 앞 칸부터 처음 것).
var back_items: PackedStringArray = []
var lights: Dictionary[String, float] = {}
var creature_kinds: Dictionary[String, CreatureKind] = {}
var night: Vector2i = Vector2i(20, 5)
## 창 · 현관 자리 (로컬, houses.json openings): id → {kind, lx, lz, nx, nz}.
var openings: Array[Dictionary] = []
var breaches: Dictionary[String, Breach] = {}
var fortify_range: float = 1.7
## 판자 값 [{id, n}].
var fortify_cost: Array[Dictionary] = []
var downed_ms: int = 45000
var revive_range: float = 1.8
var revive_ms: int = 3000
var board_ms: int = 2500
## 거점 상자 · 침대 (로컬) · 곁 거리 · 상자 칸 수.
var stash_local: Vector2 = Vector2(2.9, 3.45)
var bed_local: Vector2 = Vector2(-3.2, -2.5)
var base_range: float = 1.6
var stash_slots: int = 12
## v0.28.2 배리어 [{id, name, x, z, r}] (크리처가 못 들어오는 보호막).
var barriers: Array[Dictionary] = []
## v0.28.4 공포 연출: 이 헌터 레벨까지 · 크리처 거리 (m) · 섬뜩한 소리 간격 (초).
var fear_max_level: int = 5
var fear_range: float = 16.0
var fear_sting_cooldown: float = 25.0
## v0.26 들이받기 { fast, restitution, slow_keep, contact_top, reach, … } (서버 survival.json ram 과 같은 값).
var ram: Dictionary = {}
## v0.27 보급 상자를 열 수 있는 거리.
var supply_range: float = 2.2


static func from_dicts(rules: Dictionary, house_doc: Dictionary) -> SurvivalRules:
	var r: SurvivalRules = SurvivalRules.new()
	var loot: Dictionary = rules.get("loot", {})
	r.loot_range = float(loot.get("range", r.loot_range))
	r.supply_range = float((rules.get("supply", {}) as Dictionary).get("range", r.supply_range))
	var kinds: Dictionary = loot.get("kinds", {})
	for k: Variant in kinds:
		r.kind_names[str(k)] = str((kinds[k] as Dictionary).get("name", k))
	r.max_hp = int((rules.get("player", {}) as Dictionary).get("max_hp", 10))
	var needs: Dictionary = rules.get("needs", {})
	r.needs_max = int(needs.get("max", r.needs_max))
	r.needs_warn = int(needs.get("warn", r.needs_warn))
	var dodge: Dictionary = rules.get("dodge", {})
	r.dodge_ms = int(dodge.get("ms", r.dodge_ms))
	r.dodge_cooldown_ms = int(dodge.get("cooldown_ms", r.dodge_cooldown_ms))
	var nour: Dictionary = needs.get("nourish", {})
	for nid: Variant in nour:
		if nour[nid] is Dictionary:
			r.nourish[str(nid)] = nour[nid]
	var heal: Dictionary = rules.get("heal", {})
	for id: Variant in heal:
		if not str(id).begins_with("_"):
			r.heal[str(id)] = int(heal[id])
	r.back_items = PackedStringArray(rules.get("back_items", []))
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
		weapon.ammo = str(w.get("ammo", ""))
		weapon.stun_ms = int(w.get("stun_ms", 0))
		weapon.cleave = int(w.get("cleave", 1))
		weapon.job = str(w.get("job", ""))
		weapon.crit = float(w.get("crit", 0.0))
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
		kind.mass = float(c.get("mass", 70.0))
		r.creature_kinds[kind.id] = kind
	var fortify: Dictionary = rules.get("fortify", {})
	r.fortify_range = float(fortify.get("range", r.fortify_range))
	for c: Variant in fortify.get("cost", []):
		if c is Dictionary:
			r.fortify_cost.append({"id": str(c.get("id", "")), "n": int(c.get("n", 1))})
	var hp_of: Dictionary = fortify.get("hp", {})
	r.board_ms = int(fortify.get("board_ms", r.board_ms))
	var ram_rules: Variant = rules.get("ram", {})
	if ram_rules is Dictionary:
		r.ram = ram_rules
	var base: Dictionary = rules.get("base", {})
	var st: Array = base.get("stash", [r.stash_local.x, r.stash_local.y])
	var bd: Array = base.get("bed", [r.bed_local.x, r.bed_local.y])
	r.stash_local = Vector2(float(st[0]), float(st[1]))
	r.bed_local = Vector2(float(bd[0]), float(bd[1]))
	r.base_range = float(base.get("range", r.base_range))
	r.stash_slots = int(base.get("slots", r.stash_slots))
	var fear: Dictionary = rules.get("fear", {})
	r.fear_max_level = int(fear.get("max_level", r.fear_max_level))
	r.fear_range = float(fear.get("range", r.fear_range))
	r.fear_sting_cooldown = float(fear.get("sting_cooldown_s", r.fear_sting_cooldown))
	for b: Variant in (rules.get("barriers", {}) as Dictionary).get("list", []):
		if b is Dictionary:
			r.barriers.append(b)
	var downed: Dictionary = rules.get("downed", {})
	r.downed_ms = int(downed.get("ms", r.downed_ms))
	r.revive_range = float(downed.get("revive_range", r.revive_range))
	r.revive_ms = int(downed.get("revive_ms", r.revive_ms))
	for w: Variant in house_doc.get("walls", []):
		r.walls.append(w)
	for o: Variant in house_doc.get("openings", []):
		if o is Dictionary:
			r.openings.append(o)
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
		for b: Variant in h.get("broken", []):
			house.broken.append(str(b))
		var turn: Basis = Basis(Vector3.UP, house.yaw)
		house.stash_position = house.position + turn * Vector3(r.stash_local.x, 0.0, r.stash_local.y)
		house.bed_position = house.position + turn * Vector3(r.bed_local.x, 0.0, r.bed_local.y)
		for o: Dictionary in r.openings:
			var kind: String = str(o.get("kind", "window"))
			if kind != "door" and not house.broken.has(str(o.get("id", ""))):
				continue
			var br: Breach = Breach.new()
			br.house = house.id
			br.id = str(o.get("id", ""))
			br.key = "%s:%s" % [house.id, br.id]
			br.kind = kind
			br.local = Vector2(float(o.get("lx", 0.0)), float(o.get("lz", 0.0)))
			br.normal = Vector2(float(o.get("nx", 0.0)), float(o.get("nz", 0.0)))
			br.position = house.position + turn * Vector3(br.local.x, 0.0, br.local.y)
			br.max_hp = int(hp_of.get(kind, 10))
			house.breaches.append(br)
			r.breaches[br.key] = br
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


## v0.28.7 먹거나 마실 수 있는지 (배고픔 · 목마름을 채운다).
func is_nourishing(item_id: String) -> bool:
	return nourish.has(item_id)


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
