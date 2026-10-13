class_name SafetyRules
extends RefCounted
## 폰다운 기능 규칙 (data/safety/safety.json, v0.20): 솔걸음 목표 · 민방위 대피소 · 훈련 시각. 판정은 서버(safety.js)가 하고,
## 클라는 화면(목표 막대 · 대피소 길 안내 · 훈련 일정)에만 쓴다.

## 하루 걸음 상한 · 목표 [걸음, 솔] (늘어나는 차례).
var daily_cap: int = 40000
var tiers: Array[Vector2i] = []
## 대피소 이름 · 자리 · 반경 (m).
var shelter_name: String = ""
var shelter: Vector2 = Vector2.ZERO
var shelter_radius: float = 10.0
## 훈련: 매달 drill_day 일 drill_hour 시부터 drill_minutes 분 · 대피 보상.
var drill_day: int = 15
var drill_hour: int = 14
var drill_minutes: int = 15
var drill_reward: int = 0


static func from_dict(d: Dictionary) -> SafetyRules:
	var r: SafetyRules = SafetyRules.new()
	var steps: Dictionary = d.get("steps", {})
	r.daily_cap = int(steps.get("daily_cap", r.daily_cap))
	for t: Variant in steps.get("tiers", []):
		if t is Array and (t as Array).size() == 2:
			r.tiers.append(Vector2i(int(t[0]), int(t[1])))
	var drill: Dictionary = d.get("drill", {})
	r.drill_day = int(drill.get("day", r.drill_day))
	r.drill_hour = int(drill.get("hour", r.drill_hour))
	r.drill_minutes = int(drill.get("minutes", r.drill_minutes))
	r.drill_reward = int(drill.get("reward", 0))
	var s: Dictionary = drill.get("shelter", {})
	r.shelter_name = str(s.get("name", ""))
	r.shelter = Vector2(float(s.get("x", 0.0)), float(s.get("z", 0.0)))
	r.shelter_radius = float(s.get("radius", r.shelter_radius))
	return r


## 이 걸음 수로 받는 목표들의 솔 합 (보기용).
func reward_upto(steps: int) -> int:
	var total: int = 0
	for t: Vector2i in tiers:
		if steps >= t.x:
			total += t.y
	return total
