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
	var gates: Dictionary = d.get("gates", {})
	r.gate_enter_range = float(gates.get("enter_range", r.gate_enter_range))
	r.gate_arena = float(gates.get("arena", r.gate_arena))
	var granks: Dictionary = gates.get("ranks", {})
	for id: Variant in granks:
		r.gate_colors[str(id)] = Color(str((granks[id] as Dictionary).get("color", "#8FB8C8")))
	return r


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
