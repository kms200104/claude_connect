class_name Pedometer
extends Node
## 솔걸음 만보기 (v0.20): 휴대폰 가속도 센서로 실제 걸음을 센다 (게임이 켜져 있는 동안, 휴대폰을 들고 · 주머니에 넣고 걸을 때).
## 흔들림 크기(중력 포함 가속도의 길이)를 부드럽게 한 값이 천천히 따라가는 바탕보다 THRESHOLD 넘게 솟을 때를 한 걸음으로 보고,
## 걸음 사이가 MIN_GAP~MAX_GAP 초일 때만, 박자 맞춰 CONFIRM 걸음이 이어져야 세기 시작한다 (한 번 흔든 것 · 툭 친 것은 빼고).
## 오늘 걸음은 user://steps.cfg 에 날짜별로 남기고(일주일), 서버에 REPORT_EVERY 초마다 알린다 — 보상(목표 솔)은 서버가 정한다.
## 솔걸음 앱을 받아야(앱 스토어) 센다.

signal stepped(today: int)

const PATH: String = "user://steps.cfg"
const THRESHOLD: float = 1.15
const MIN_GAP: float = 0.27
const MAX_GAP: float = 2.0
const CONFIRM: int = 4
const REPORT_EVERY: float = 20.0
const KEEP_DAYS: int = 7

## 솔걸음 앱이 있는지 (없으면 세지 않는다).
var enabled: bool = false
var today: int = 0
var day_key: String = ""
## 날짜 → 그날 걸음 (일주일).
var history: Dictionary[String, int] = {}

var _smooth: float = 9.8
var _base: float = 9.8
var _above: bool = false
var _t: float = 0.0
var _last_peak: float = -10.0
var _streak: int = 0
var _report_left: float = REPORT_EVERY
var _dirty: bool = false
var _sensor_seen: bool = false


func _ready() -> void:
	add_to_group(&"pedometer")
	_load()
	_roll_day()


## 이 기기에 가속도 센서가 있는지 (값이 한 번이라도 들어왔는지).
func has_sensor() -> bool:
	return _sensor_seen


func _physics_process(delta: float) -> void:
	_t += delta
	if not enabled:
		return
	var a: Vector3 = Input.get_accelerometer()
	if a == Vector3.ZERO:
		return
	_sensor_seen = true
	feed(a.length())


## 가속도 크기 하나 (m/s², 1/60초마다). 테스트에서 걸음을 흉내 낼 때도 쓴다.
func feed(magnitude: float) -> void:
	_smooth = lerpf(_smooth, magnitude, 0.35)
	_base = lerpf(_base, magnitude, 0.02)
	var high: float = _smooth - _base
	if not _above and high > THRESHOLD:
		_above = true
		_on_peak()
	elif _above and high < THRESHOLD * 0.4:
		_above = false


func _on_peak() -> void:
	var gap: float = _t - _last_peak
	if gap < MIN_GAP:
		return
	_last_peak = _t
	if gap > MAX_GAP:
		_streak = 1
		return
	_streak += 1
	if _streak == CONFIRM:
		add(CONFIRM)
	elif _streak > CONFIRM:
		add(1)


## 시간을 흘린다 (테스트: 물리 프레임 없이 feed 할 때).
func advance(seconds: float) -> void:
	_t += seconds


func add(n: int) -> void:
	_roll_day()
	today += n
	history[day_key] = today
	_dirty = true
	stepped.emit(today)


func _process(delta: float) -> void:
	_report_left -= delta
	if _report_left > 0.0:
		return
	_report_left = REPORT_EVERY
	_roll_day()
	if _dirty:
		_dirty = false
		_save()
		report()


## 서버에 오늘 걸음을 알린다 (보상은 서버가).
func report() -> void:
	if Net.state == Net.State.ONLINE and enabled:
		Net.request("steps", {"n": today})


## 자정이 지나면 0부터.
func _roll_day() -> void:
	var key: String = Time.get_date_string_from_system()
	if key == day_key:
		return
	day_key = key
	today = int(history.get(key, 0))
	var keys: Array[String] = []
	for k: String in history:
		keys.append(k)
	keys.sort()
	while keys.size() > KEEP_DAYS:
		history.erase(keys.pop_front())


## 최근 며칠 (오래된 것부터) [날짜, 걸음].
func recent(days: int = KEEP_DAYS) -> Array[Array]:
	var out: Array[Array] = []
	var now: int = int(Time.get_unix_time_from_system())
	for i: int in range(days - 1, -1, -1):
		var key: String = Time.get_date_string_from_unix_time(now - i * 86400)
		out.append([key, int(history.get(key, 0))])
	return out


func _load() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in cfg.get_section_keys("days") if cfg.has_section("days") else PackedStringArray():
		history[k] = int(cfg.get_value("days", k, 0))


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	for k: String in history:
		cfg.set_value("days", k, history[k])
	cfg.save(PATH)
