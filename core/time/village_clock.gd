class_name VillageClock
extends RefCounted
## 마을 시계 계산. 서버(server/src/clock.js)와 같은 식을 쓴다.
## 게임 시각(ms)은 "마을 시간대의 벽시계"를 epoch ms로 나타낸 값이고, 하루는 새벽 5시에 바뀐다.

const HOUR_MS: float = 3600000.0
const DAY_MS: float = 24.0 * HOUR_MS
const DAY_START_HOUR: float = 5.0

const BAND_MORNING: String = "morning"
const BAND_DAY: String = "day"
const BAND_EVENING: String = "evening"
const BAND_NIGHT: String = "night"


## 0 이상 24 미만의 시(소수 포함).
static func hour_of(game_ms: float) -> float:
	return fposmod(game_ms, DAY_MS) / HOUR_MS


## 새벽 5시 기준 날짜 번호 (부탁 기한 비교용).
static func day_index(game_ms: float) -> int:
	return floori((game_ms - DAY_START_HOUR * HOUR_MS) / DAY_MS)


## morning(5–10) day(10–17) evening(17–20) night(20–5)
static func time_band(hour: float) -> String:
	if hour >= 5.0 and hour < 10.0:
		return BAND_MORNING
	if hour >= 10.0 and hour < 17.0:
		return BAND_DAY
	if hour >= 17.0 and hour < 20.0:
		return BAND_EVENING
	return BAND_NIGHT


## "오후 3:20" 같은 표시용 문자열.
static func format_time(hour: float) -> String:
	var h: int = floori(hour)
	var m: int = floori((hour - h) * 60.0)
	var half: String = "오전" if h < 12 else "오후"
	var h12: int = h % 12
	if h12 == 0:
		h12 = 12
	return "%s %d:%02d" % [half, h12, m]
