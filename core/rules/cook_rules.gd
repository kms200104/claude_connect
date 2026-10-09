class_name CookRules
extends RefCounted
## 요리 동작 솜씨 (서버 server/src/restaurant.js 의 stepQuality · timingScore 와 같은 계산).
## 판정과 돈은 서버가 정한다. 여기서는 누를 때마다 "완벽!" · 동작이 끝날 때 등급을 바로 보여 주는 데만 쓴다.

## 누름 한 번의 판정: 완벽 · 좋아요 · 아쉬워요 · 놓침.
enum Grade { MISS, OK, GOOD, PERFECT }

const GRADE_TEXT: PackedStringArray = ["놓쳤어요", "아쉬워요", "좋아요!", "완벽!"]
const GRADE_COLOR: Array[Color] = [Color("#9A8A7A"), Color("#E8904A"), Color("#5AAE5A"), Color("#E8A820")]


static func timing_score(off: float, window: float) -> float:
	if off <= window:
		return 1.0 - 0.3 * (off / window)
	return maxf(0.0, 0.7 - 0.7 * ((off - window) / (window * 2.0)))


## 딱 좋은 때와의 차이(off) → 판정. 판정 창(window) 안쪽 40% 면 완벽.
static func grade(off: float, window: float) -> Grade:
	if off <= window * 0.4:
		return Grade.PERFECT
	if off <= window:
		return Grade.GOOD
	if off <= window * 2.0:
		return Grade.OK
	return Grade.MISS


## 박자 동작에서 t 에 누른 것이 몇 번째 박자에 가장 가까운지 (1부터, 박자 밖이면 가장 가까운 끝).
static func nearest_beat(step: Dictionary, t: float) -> int:
	var interval: float = float(step.get("interval_ms", 480))
	return clampi(roundi(t / interval), 1, int(step.get("beats", 4)))


static func beat_grade(step: Dictionary, t: float) -> Grade:
	var interval: float = float(step.get("interval_ms", 480))
	return grade(absf(t - float(nearest_beat(step, t)) * interval), float(step.get("window_ms", 170)))


## 동작 하나의 솜씨 0~1 (서버 stepQuality 와 같다).
static func step_quality(step: Dictionary, raw_taps: Array) -> float:
	var t: Array[float] = []
	for x: Variant in raw_taps:
		var v: float = float(x)
		if v >= 0.0 and v < 20000.0:
			t.append(v)
	t.sort()
	match str(step.get("kind", "")):
		"beats":
			var beats: int = int(step.get("beats", 4))
			var interval: float = float(step.get("interval_ms", 480))
			var window: float = float(step.get("window_ms", 170))
			var total: float = 0.0
			for i: int in range(1, beats + 1):
				var off: float = INF
				for x: float in t:
					off = minf(off, absf(x - interval * i))
				total += maxf(0.0, 1.0 - off / (window * 2.0))
			return maxf(0.0, total / beats - maxf(0, t.size() - beats) * 0.05)
		"timing":
			if t.is_empty():
				return 0.0
			return timing_score(absf(t[0] - float(step.get("ideal_ms", 2000))), float(step.get("window_ms", 300)))
		"grill":
			var sides: int = int(step.get("sides", 2))
			var side_ms: float = float(step.get("side_ms", 2000))
			var gw: float = float(step.get("window_ms", 300))
			var sum: float = 0.0
			for k: int in mini(sides, t.size()):
				sum += timing_score(absf(t[k] - (0.0 if k == 0 else t[k - 1]) - side_ms), gw)
			return maxf(0.0, sum / sides - maxf(0, t.size() - sides) * 0.1)
		"steam":
			var n: int = int(step.get("items", 3))
			var items: float = float(mini(t.size(), n)) / n
			if t.size() < n + 3:
				return items / 3.0
			var level: float = (t[n + 1] - t[n]) / float(step.get("fill_ms", 1600))
			var water: float = timing_score(absf(level - 1.0), float(step.get("water_window", 0.16)))
			var steamed: float = timing_score(absf(t[n + 2] - t[n + 1] - float(step.get("steam_ms", 2600))), float(step.get("window_ms", 300)))
			return (items + water + steamed) / 3.0
	var count: int = 0
	var last: float = -INF
	for x: float in t:
		if x > float(step.get("duration_ms", 2600)):
			break
		if x - last >= 50.0:
			count += 1
			last = x
	return minf(1.0, float(count) / float(step.get("taps", 10)))


## 동작 솜씨 → 한마디.
static func step_word(q: float) -> String:
	if q >= 0.9:
		return "완벽해요!"
	if q >= 0.72:
		return "잘했어요!"
	if q >= 0.45:
		return "괜찮아요"
	return "아쉬워요…"


static func step_color(q: float) -> Color:
	if q >= 0.9:
		return GRADE_COLOR[Grade.PERFECT]
	if q >= 0.72:
		return GRADE_COLOR[Grade.GOOD]
	if q >= 0.45:
		return GRADE_COLOR[Grade.OK]
	return GRADE_COLOR[Grade.MISS]
