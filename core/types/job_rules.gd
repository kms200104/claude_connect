class_name JobRules
extends RefCounted
## 일거리 규칙 (data/jobs/jobs.json, v0.12): 상황 버튼을 띄울 거리 (서버 판정과 같은 값)와 하루 건수.

var range: float = 3.2
var house_range: float = 5.0
var together_m: float = 8.0
var daily_max: int = 8
## 연속 팁 (v0.13.7): 2번째 연속부터 삯 × streak_per × (연속 - 1), 최대 삯 × streak_max (서버 jobs.js streakBonusOf).
var streak_per: float = 0.1
var streak_max: float = 0.5


static func from_dict(data: Dictionary) -> JobRules:
	var r: JobRules = JobRules.new()
	r.range = float(data.get("range", r.range))
	r.house_range = float(data.get("house_range", r.house_range))
	r.together_m = float(data.get("together_m", r.together_m))
	r.daily_max = int(data.get("daily_max", r.daily_max))
	var streak: Dictionary = data.get("streak", {})
	r.streak_per = float(streak.get("per", r.streak_per))
	r.streak_max = float(streak.get("max", r.streak_max))
	return r
