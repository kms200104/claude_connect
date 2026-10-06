class_name Prefs
extends RefCounted
## 플레이 설정 (v16, 설정 앱): 진동 · 글자 크기 · 조이스틱 위치와 크기 · 음악 앱에서 고른 곡.
## user://settings.cfg 의 "play" 칸에 기억한다 (소리 · 화질 · 화면 방향은 각자 저장). 바뀌면 Prefs.events.changed(key).

const PATH: String = "user://settings.cfg"
const SECTION: String = "play"

const VIBRATION: String = "vibration"
const FONT: String = "font"
const STICK_SIDE: String = "stick_side"
const STICK_SIZE: String = "stick_size"
## 음악 앱: "" = 자동(시각 · 날씨 · 이벤트에 맞춰), "off" = 끄기, 그 밖 = 곡 이름.
const MUSIC: String = "music"
const MUSIC_OFF: String = "off"

const FONT_SCALES: Dictionary[String, float] = {"small": 0.88, "normal": 1.0, "large": 1.14}
const FONT_NAMES: Dictionary[String, String] = {"small": "작게", "normal": "보통", "large": "크게"}
const STICK_SIDES: Dictionary[String, String] = {"left": "왼쪽 (오른손잡이)", "right": "오른쪽 (왼손잡이)"}
const STICK_SCALES: Dictionary[String, float] = {"small": 0.8, "normal": 1.0, "large": 1.22}
const STICK_NAMES: Dictionary[String, String] = {"small": "작게", "normal": "보통", "large": "크게"}

const DEFAULTS: Dictionary[String, Variant] = {
	"vibration": true,
	"font": "normal",
	"stick_side": "left",
	"stick_size": "normal",
	"music": "",
}


class Events:
	extends RefCounted
	signal changed(key: String)


static var events: Events = Events.new()
static var _values: Dictionary[String, Variant] = {}
static var _loaded: bool = false


static func get_value(key: String) -> Variant:
	_ensure()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure()
	if not DEFAULTS.has(key) or typeof(value) != typeof(DEFAULTS[key]) or _values.get(key) == value:
		return
	_values[key] = value
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)
	events.changed.emit(key)


static func vibration() -> bool:
	return bool(get_value(VIBRATION))


static func font_scale() -> float:
	return FONT_SCALES.get(str(get_value(FONT)), 1.0)


static func stick_on_right() -> bool:
	return str(get_value(STICK_SIDE)) == "right"


static func stick_scale() -> float:
	return STICK_SCALES.get(str(get_value(STICK_SIZE)), 1.0)


static func music() -> String:
	return str(get_value(MUSIC))


## 짧게 떨기 (진동을 껐으면 아무것도 안 한다).
static func vibrate(ms: int, amplitude: float = -1.0) -> void:
	if vibration():
		Input.vibrate_handheld(ms, amplitude)


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		var v: Variant = cfg.get_value(SECTION, key, DEFAULTS[key])
		if typeof(v) == typeof(DEFAULTS[key]):
			_values[key] = v
