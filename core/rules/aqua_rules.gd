class_name AquaRules
extends RefCounted
## 물놀이 체험 (v21, data/aqua/aqua.json): 성성호수 선착장의 바나나 보트 · 유람선.
## 길 · 시간 계산은 서버 server/src/aqua.js (duration · distanceAt · timeAt · pointAt) 와 같다.
##   노선 path 는 닫힌 고리(2m 간격), 0 m = 선착장 곁 대기 자리. 처음 · 끝 ease_s 초는 고르게 빨라지고 느려진다.
##   바나나 보트 turns: 급회전 자리 (s m, dir +1 오른쪽 · -1 왼쪽) — prompt_s 초 앞에서 "꽉 잡아!", window_ms 안에 누르면 버틴다.
##   유람선 stops: 선장 안내 방송 자리 (s m, 말).


class Ride:
	var id: String = ""
	var name: String = ""
	var desc: String = ""
	var fee: int = 0
	var seats: int = 1
	var speed: float = 1.0
	var ease_s: float = 0.0
	## 바나나 보트: 끄는 모터보트가 바나나보다 이만큼 앞 (m).
	var tow: float = 0.0
	## 운전하는 주민 (NpcInfo id).
	var driver: String = ""
	var prompt_s: float = 1.3
	var window_ms: int = 1500
	var length: float = 1.0
	var path: PackedVector2Array = []
	## [{ s: float, dir: int }]
	var turns: Array[Dictionary] = []
	## [{ s: float, line: String }]
	var stops: Array[Dictionary] = []

	func is_banana() -> bool:
		return id == "banana"


## 선착장 (잔교 뿌리) · 매표소 · 내리는 땅 · 사장님.
var dock: Vector2 = Vector2.ZERO
var board_range: float = 6.0
var land: Vector2 = Vector2.ZERO
var pier_root: Vector2 = Vector2.ZERO
var pier_tip: Vector2 = Vector2.ZERO
var pier_width: float = 1.6
var booth: Vector2 = Vector2.ZERO
var operator: String = ""
var operator_at: Vector2 = Vector2.ZERO
var board_ms: int = 8000
var rides: Array[Ride] = []


static func from_dict(d: Dictionary) -> AquaRules:
	var a: AquaRules = AquaRules.new()
	var dk: Dictionary = d.get("dock", {})
	a.dock = Vector2(float(dk.get("x", 0.0)), float(dk.get("z", 0.0)))
	a.board_range = float(dk.get("board_range", 6.0))
	a.land = _v2(dk.get("land", []))
	var pier: Array = dk.get("pier", [])
	if pier.size() >= 2:
		a.pier_root = _v2(pier[0])
		a.pier_tip = _v2(pier[1])
	a.pier_width = float(dk.get("pier_width", 1.6))
	a.booth = _v2(dk.get("booth", []))
	a.operator = str(dk.get("operator", ""))
	a.operator_at = _v2(dk.get("operator_at", []))
	a.board_ms = int(d.get("board_ms", 8000))
	for raw: Variant in d.get("rides", []):
		if not raw is Dictionary:
			continue
		var r: Ride = Ride.new()
		r.id = str(raw.get("id", ""))
		r.name = str(raw.get("name", r.id))
		r.desc = str(raw.get("desc", ""))
		r.fee = int(raw.get("fee", 0))
		r.seats = int(raw.get("seats", 1))
		r.speed = float(raw.get("speed", 1.0))
		r.ease_s = float(raw.get("ease_s", 0.0))
		r.tow = float(raw.get("tow", 0.0))
		r.driver = str(raw.get("driver", ""))
		r.prompt_s = float(raw.get("prompt_s", 1.3))
		r.window_ms = int(raw.get("window_ms", 1500))
		r.length = float(raw.get("length", 1.0))
		for p: Variant in raw.get("path", []):
			r.path.append(_v2(p))
		for t: Variant in raw.get("turns", []):
			if t is Dictionary:
				r.turns.append({"s": float(t.get("s", 0.0)), "dir": int(t.get("dir", 1))})
		for s: Variant in raw.get("stops", []):
			if s is Dictionary:
				r.stops.append({"s": float(s.get("s", 0.0)), "line": str(s.get("line", ""))})
		a.rides.append(r)
	return a


func ride(id: String) -> Ride:
	for r: Ride in rides:
		if r.id == id:
			return r
	return null


## 한 바퀴 걸리는 시간 (초).
static func duration(r: Ride) -> float:
	return r.length / r.speed + r.ease_s


## 출발 뒤 tau 초에 간 거리 (m).
static func distance_at(r: Ride, tau: float) -> float:
	var a: float = r.ease_s
	var v: float = r.speed
	var total: float = duration(r)
	if tau <= 0.0:
		return 0.0
	if tau >= total:
		return r.length
	if a > 0.0 and tau < a:
		return v * tau * tau / (2.0 * a)
	if a > 0.0 and tau > total - a:
		return r.length - v * pow(total - tau, 2.0) / (2.0 * a)
	return v * (tau - a * 0.5)


## 그 거리에 닿는 시각 (출발 뒤 초).
static func time_at(r: Ride, s: float) -> float:
	var a: float = r.ease_s
	var v: float = r.speed
	var total: float = duration(r)
	if s <= 0.0:
		return 0.0
	if s >= r.length:
		return total
	if a > 0.0 and s < v * a * 0.5:
		return sqrt(2.0 * a * s / v)
	if a > 0.0 and s > r.length - v * a * 0.5:
		return total - sqrt(2.0 * a * (r.length - s) / v)
	return s / v + a * 0.5


## 노선 위 s m 자리 (닫힌 고리라 길이를 넘거나 모자라면 돌아 들어간다).
static func point_at(r: Ride, s: float) -> Vector2:
	var n: int = r.path.size() - 1
	if n < 1:
		return r.path[0] if n == 0 else Vector2.ZERO
	var step: float = r.length / float(n)
	var d: float = fposmod(s, r.length)
	var i: int = mini(int(d / step), n - 1)
	var t: float = d / step - float(i)
	return r.path[i].lerp(r.path[i + 1], t)


## 그 자리에서 나아가는 방향 (Node3D.rotation.y: 앞 = -z). 앞뒤 look m 를 보고 부드럽게.
static func yaw_at(r: Ride, s: float, look: float = 2.0) -> float:
	var d: Vector2 = point_at(r, s + look) - point_at(r, s - look)
	return atan2(-d.x, -d.y) if d.length() > 0.001 else 0.0


static func _v2(v: Variant) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO
