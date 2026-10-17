class_name HunterRules
extends RefCounted
## v0.28 헌터 규칙 (data/hunter/hunter.json — 서버 server/src/hunter.js 와 같은 파일).
## 협회 등급 (E~S · 점수 기준 · 마석 더 받는 몫) · 협회 출장소 자리 · 팔 수 있는 마석 · 길드 이름 길이와 등급.

class Rank:
	var id: String = "E"
	var name: String = "E급"
	var points: int = 0
	var sell_bonus: float = 0.0
	var color: Color = Color.WHITE
	var index: int = 0


## v0.28.2 게이트 안 던전 지도 (로컬 좌표, 가운데 기준 m). 서버 server/src/dungeon.js 와 같은 판정.
class DungeonMap:
	var id: String = ""
	var name: String = ""
	var size: Vector2 = Vector2(20.0, 30.0)
	var spawn: Vector2 = Vector2.ZERO
	var exit: Vector2 = Vector2.ZERO
	var center: Vector2 = Vector2.ZERO
	## [x, z, r]
	var pillars: Array[Vector3] = []
	## Rect2 (가운데 x · z 에서 w · d 만큼).
	var rubble: Array[Rect2] = []

	func stand_local(at: Vector2, pad: float = 0.35) -> bool:
		if absf(at.x) > size.x * 0.5 - pad or absf(at.y) > size.y * 0.5 - pad:
			return false
		for p: Vector3 in pillars:
			if Vector2(at.x - p.x, at.y - p.y).length() < p.z + pad:
				return false
		for r: Rect2 in rubble:
			if r.grow(pad).has_point(at):
				return false
		return true


var ranks: Array[Rank] = []
var office_name: String = "헌터 협회 출장소"
var office_position: Vector3 = Vector3.ZERO
var office_yaw: float = 0.0
var office_range: float = 2.6
var sell_items: PackedStringArray = []
var guild_name_min: int = 2
var guild_name_max: int = 12
var guild_sell_bonus: float = 0.05
var party_range: float = 20.0
var party_mult: float = 1.25
## v0.28 게이트: 진입 거리 · 공략 구역 반지름 · 등급 → 색.
var gate_enter_range: float = 4.0
var gate_arena: float = 14.0
var gate_colors: Dictionary[String, Color] = {}
## v0.28.2 던전: 게이트 자리 순서 i 마다 가운데 (x0 + i × dx, z0) · 나가는 균열 거리 · 지도들.
var gate_spots: PackedStringArray = []
var dungeon_x0: float = 0.0
var dungeon_dx: float = 100.0
var dungeon_z0: float = 0.0
var dungeon_exit_range: float = 2.2
var dungeon_maps: Dictionary[String, DungeonMap] = {}
## v0.28.1 레벨: 최대 · 다음까지 경험치 식 · 스탯 정의 (키 → {name, desc, 값들, cap}) · 기술 [{id, name, level, desc, reach}].
var level_max: int = 50
var level_stats: Dictionary[String, Dictionary] = {}
var skills: Array[Dictionary] = []
## v0.28.5 각성: 고르는 레벨들 · [{id, name, desc, active, ms, cooldown_ms, speed, hits, range}].
var awaken_slots: Array[int] = []
var awakens: Array[Dictionary] = []
## v0.28.8 전직 · 기술 나무 (hunter.json level.jobs): 전직 레벨 · 레벨마다 포인트 · 줄 조건 · 초기화 값 · 액티브 (id → {name, icon, color, cooldown_ms, …}) ·
## 직업 [{id, name, color, desc, tree: [{id, name, row, col, max, desc, req, fx, active}]}].
var job_level: int = 10
var job_per_level: int = 1
var job_row_gate: int = 2
var job_reset_sol: int = 20000
var job_actives: Dictionary[String, Dictionary] = {}
var jobs: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> HunterRules:
	var r: HunterRules = HunterRules.new()
	var list: Array = (d.get("ranks", {}) as Dictionary).get("list", [])
	for i: int in list.size():
		var e: Dictionary = list[i]
		var k: Rank = Rank.new()
		k.id = str(e.get("id", "E"))
		k.name = str(e.get("name", k.id + "급"))
		k.points = int(e.get("points", 0))
		k.sell_bonus = float(e.get("sell_bonus", 0.0))
		k.color = Color(str(e.get("color", "#FFFFFF")))
		k.index = i
		r.ranks.append(k)
	var office: Dictionary = d.get("office", {})
	r.office_name = str(office.get("name", r.office_name))
	r.office_position = Vector3(float(office.get("x", 0.0)), 0.0, float(office.get("z", 0.0)))
	r.office_yaw = float(office.get("yaw", 0.0))
	r.office_range = float(office.get("range", r.office_range))
	r.sell_items = PackedStringArray(office.get("sell_items", []))
	var guild: Dictionary = d.get("guild", {})
	r.guild_name_min = int(guild.get("name_min", r.guild_name_min))
	r.guild_name_max = int(guild.get("name_max", r.guild_name_max))
	r.guild_sell_bonus = float(guild.get("sell_bonus", r.guild_sell_bonus))
	var kill: Dictionary = d.get("kill", {})
	r.party_range = float(kill.get("party_range", r.party_range))
	r.party_mult = float(kill.get("party_mult", r.party_mult))
	var level: Dictionary = d.get("level", {})
	r.level_max = int(level.get("max", r.level_max))
	var stats: Dictionary = level.get("stats", {})
	for k: Variant in stats:
		if not str(k).begins_with("_"):
			r.level_stats[str(k)] = stats[k]
	for sk: Variant in level.get("skills", []):
		if sk is Dictionary:
			r.skills.append(sk)
	var aw: Dictionary = level.get("awaken", {})
	for l: Variant in aw.get("slots", []):
		r.awaken_slots.append(int(l))
	for e: Variant in aw.get("list", []):
		if e is Dictionary:
			r.awakens.append(e)
	var jd: Dictionary = level.get("jobs", {})
	r.job_level = int(jd.get("level", r.job_level))
	r.job_per_level = int(jd.get("per_level", r.job_per_level))
	r.job_row_gate = int(jd.get("row_gate", r.job_row_gate))
	r.job_reset_sol = int(jd.get("reset_sol", r.job_reset_sol))
	var acts: Dictionary = jd.get("actives", {})
	for k: Variant in acts:
		if acts[k] is Dictionary:
			r.job_actives[str(k)] = acts[k]
	for e: Variant in jd.get("list", []):
		if e is Dictionary:
			r.jobs.append(e)
	var gates: Dictionary = d.get("gates", {})
	r.gate_enter_range = float(gates.get("enter_range", r.gate_enter_range))
	r.gate_arena = float(gates.get("arena", r.gate_arena))
	var granks: Dictionary = gates.get("ranks", {})
	for id: Variant in granks:
		r.gate_colors[str(id)] = Color(str((granks[id] as Dictionary).get("color", "#8FB8C8")))
	for sp: Variant in gates.get("spots", []):
		if sp is Dictionary:
			r.gate_spots.append(str((sp as Dictionary).get("id", "")))
	var dg: Dictionary = gates.get("dungeon", {})
	r.dungeon_x0 = float(dg.get("x0", 0.0))
	r.dungeon_dx = float(dg.get("dx", 100.0))
	r.dungeon_z0 = float(dg.get("z0", 0.0))
	r.dungeon_exit_range = float(dg.get("exit_range", r.dungeon_exit_range))
	var maps: Dictionary = dg.get("maps", {})
	for mid: Variant in maps:
		var md: Dictionary = maps[mid]
		var m: DungeonMap = DungeonMap.new()
		m.id = str(mid)
		m.name = str(md.get("name", ""))
		m.size = Vector2(float(md.get("w", 20.0)), float(md.get("d", 30.0)))
		m.spawn = _v2(md.get("spawn", []))
		m.exit = _v2(md.get("exit", []))
		m.center = _v2(md.get("center", []))
		for p: Variant in md.get("pillars", []):
			var pa: Array = p
			m.pillars.append(Vector3(float(pa[0]), float(pa[1]), float(pa[2])))
		for b: Variant in md.get("rubble", []):
			var ba: Array = b
			m.rubble.append(Rect2(float(ba[0]) - float(ba[2]) * 0.5, float(ba[1]) - float(ba[3]) * 0.5, float(ba[2]), float(ba[3])))
		r.dungeon_maps[m.id] = m
	return r


static func _v2(a: Variant) -> Vector2:
	return Vector2(float((a as Array)[0]), float((a as Array)[1])) if a is Array and (a as Array).size() >= 2 else Vector2.ZERO


## v0.28.2 그 게이트 자리의 던전 가운데 (월드). 없는 자리면 Vector3.INF.
func dungeon_origin(spot_id: String) -> Vector3:
	var i: int = gate_spots.find(spot_id)
	if i < 0 or dungeon_maps.is_empty():
		return Vector3.INF
	return Vector3(dungeon_x0 + float(i) * dungeon_dx, 0.0, dungeon_z0)


## v0.28.2 그 자리가 어느 게이트 자리의 던전 영역이면 그 자리 id, 아니면 빈 글자 (서버 dungeonAt).
func dungeon_spot_at(pos: Vector3) -> String:
	if dungeon_maps.is_empty() or absf(pos.z - dungeon_z0) > dungeon_dx * 0.5:
		return ""
	var i: int = roundi((pos.x - dungeon_x0) / dungeon_dx)
	return gate_spots[i] if i >= 0 and i < gate_spots.size() else ""


## 각성 하나 (없으면 빈 사전).
func awaken(id: String) -> Dictionary:
	for e: Dictionary in awakens:
		if str(e.get("id", "")) == id:
			return e
	return {}


## v0.28.8 직업 정의 ({} = 없음).
func job(id: String) -> Dictionary:
	for e: Dictionary in jobs:
		if str(e.get("id", "")) == id:
			return e
	return {}


## 그 직업 나무의 기술 하나 ({} = 없음).
func job_node(job_id: String, node_id: String) -> Dictionary:
	for n: Variant in job(job_id).get("tree", []):
		if n is Dictionary and str((n as Dictionary).get("id", "")) == node_id:
			return n
	return {}


## 배운 기술 (id → 단계) 이 주는 값의 합 (서버 jobFx 와 같은 셈).
func job_fx(job_id: String, learned: Dictionary, key: String) -> float:
	var sum: float = 0.0
	for id: Variant in learned:
		sum += float((job_node(job_id, str(id)).get("fx", {}) as Dictionary).get(key, 0.0)) * int(learned[id])
	return sum


## 기술을 지금 배울 수 있는지: "" = 된다, 아니면 까닭 (포인트 · 끝까지 · 앞 기술 · 줄).
func job_node_block(job_id: String, learned: Dictionary, points: int, node_id: String) -> String:
	var n: Dictionary = job_node(job_id, node_id)
	if n.is_empty():
		return "없는 기술"
	if int(learned.get(node_id, 0)) >= int(n.get("max", 1)):
		return "끝까지 배웠어요"
	var spent: int = 0
	for id: Variant in learned:
		spent += int(learned[id])
	var need: int = (int(n.get("row", 1)) - 1) * job_row_gate
	if spent < need:
		return "이 나무에 %d포인트를 더 써야 해요" % (need - spent)
	for r: Variant in n.get("req", []):
		if int(learned.get(str(r), 0)) <= 0:
			return "먼저 '%s' 를 배워야 해요" % str(job_node(job_id, str(r)).get("name", r))
	if points <= 0:
		return "기술 포인트가 없어요"
	return ""


func rank(id: String) -> Rank:
	for k: Rank in ranks:
		if k.id == id:
			return k
	return ranks[0] if not ranks.is_empty() else Rank.new()


## 내 헌터 등급으로 이 등급 게이트에 들어갈 수 있는지 (한 단계 아래까지).
func can_enter(my_rank: String, gate_rank: String) -> bool:
	return rank(my_rank).index >= rank(gate_rank).index - 1


## 창구 앞 (사람이 서는 곳): 출장소 앞면 쪽으로 1.6m.
func counter_position() -> Vector3:
	return office_position + Basis(Vector3.UP, office_yaw) * Vector3(0.0, 0.0, 1.6)
