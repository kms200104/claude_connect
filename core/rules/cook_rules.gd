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
	if off <= window * 0.5:
		return Grade.PERFECT
	if off <= window:
		return Grade.GOOD
	if off <= window * 2.0:
		return Grade.OK
	return Grade.MISS


## 박자 동작에서 누를 박자들 (v0.18 hits: 1 = 첫 박자, 0.5 = 반 박자). 없으면 1 … beats (서버 beatHits 와 같다).
static func hits(step: Dictionary) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var raw: Variant = step.get("hits", null)
	if raw is Array and not (raw as Array).is_empty():
		for h: Variant in raw:
			out.append(float(h))
		return out
	for i: int in int(step.get("beats", 4)):
		out.append(float(i + 1))
	return out


## i 번째(0부터) 누를 때 (동작 시작부터 ms).
static func hit_ms(step: Dictionary, i: int) -> float:
	var h: PackedFloat32Array = hits(step)
	return h[clampi(i, 0, h.size() - 1)] * float(step.get("interval_ms", 536))


## 동작이 끝나는 때: 마지막 박자 (ms).
static func last_hit_ms(step: Dictionary) -> float:
	var h: PackedFloat32Array = hits(step)
	return h[h.size() - 1] * float(step.get("interval_ms", 536)) if not h.is_empty() else 0.0


## t 에 누른 것이 몇 번째 박자에 가장 가까운지 (0부터).
static func nearest_hit(step: Dictionary, t: float) -> int:
	var h: PackedFloat32Array = hits(step)
	var interval: float = float(step.get("interval_ms", 536))
	var best: int = 0
	for i: int in h.size():
		if absf(t - h[i] * interval) < absf(t - h[best] * interval):
			best = i
	return best


## 예전 이름 (1부터).
static func nearest_beat(step: Dictionary, t: float) -> int:
	return nearest_hit(step, t) + 1


static func beat_grade(step: Dictionary, t: float) -> Grade:
	return grade(absf(t - hit_ms(step, nearest_hit(step, t))), float(step.get("window_ms", 170)))


## 박자 하나의 점수 (서버 hitCredit 와 같다): 완벽(창의 절반 안)은 만점, 그 밖은 창 두 배까지 서서히 줄어든다.
static func hit_credit(off: float, window: float) -> float:
	var perfect: float = window * 0.5
	if off <= perfect:
		return 1.0
	return maxf(0.0, 1.0 - (off - perfect) / (window * 2.0 - perfect))


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
			# 누름 하나는 박자 하나에만, 차례대로 짝짓는다 (서버 stepQuality 와 같다).
			var h: PackedFloat32Array = hits(step)
			var interval: float = float(step.get("interval_ms", 536))
			var window: float = float(step.get("window_ms", 170))
			var total: float = 0.0
			var j: int = 0
			for hit: float in h:
				var ideal: float = hit * interval
				var best: float = INF
				var at: int = -1
				for k: int in range(j, t.size()):
					var off: float = absf(t[k] - ideal)
					if off < best:
						best = off
						at = k
					elif t[k] > ideal:
						break
				if at < 0 or best >= window * 2.0:
					continue
				total += hit_credit(best, window)
				j = at + 1
			return maxf(0.0, total / float(h.size()) - maxf(0, t.size() - h.size()) * 0.05)
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
