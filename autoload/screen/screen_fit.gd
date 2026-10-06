extends Node
## 화면 방향 (v0.13.4, 고정하기 v0.14.2): 휴대폰을 가로로 돌리면 가로 화면으로 논다 (project: handheld orientation = sensor).
## UI 는 세로 기준(1080 × 1920)으로 만들었다. 가로일 때는 논리 높이를 LANDSCAPE_HEIGHT 로 두고 옆으로 넓혀서
## (stretch aspect = expand) 글자 크기가 세로일 때와 비슷하게 보이게 한다. 창들은 changed 를 듣고 자리를 다시 잡는다.

signal changed(landscape: bool)

## 세로 화면의 논리 크기 (project.godot 의 viewport_width/height).
const PORTRAIT_BASE: Vector2i = Vector2i(1080, 1920)
## 가로 화면의 논리 높이 (정사각형 바탕을 옆으로 넓힌다 → 20:9 휴대폰이면 2667 × 1200).
const LANDSCAPE_HEIGHT: int = 1200

var landscape: bool = false
## 화면 방향 고정 (v0.14.2, 설정 앱): auto = 돌리는 대로 · portrait = 세로 고정 · landscape = 가로 고정.
var orientation: String = ORIENT_AUTO

const ORIENT_AUTO: String = "auto"
const ORIENT_PORTRAIT: String = "portrait"
const ORIENT_LANDSCAPE: String = "landscape"
const ORIENT_NAMES: Dictionary[String, String] = {"auto": "돌리는 대로", "portrait": "세로 고정", "landscape": "가로 고정"}
const SETTINGS_PATH: String = "user://settings.cfg"


func _ready() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		orientation = str(cfg.get_value("screen", "orientation", ORIENT_AUTO))
	_apply_orientation()
	get_tree().root.size_changed.connect(_apply)
	_apply()
	# 글자 크기 설정 (v16): 화면의 글자를 고른 배율로.
	var scaler: FontScaler = FontScaler.new()
	scaler.name = "FontScaler"
	add_child(scaler)


## 화면 방향 고르기: 기억해 두고 바로 적용한다.
func set_orientation(value: String) -> void:
	if not ORIENT_NAMES.has(value):
		return
	orientation = value
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("screen", "orientation", orientation)
	cfg.save(SETTINGS_PATH)
	_apply_orientation()


func _apply_orientation() -> void:
	# 휴대폰에서만 (데스크톱 · 테스트 창은 그대로).
	if not OS.has_feature("mobile"):
		return
	match orientation:
		ORIENT_PORTRAIT:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
		ORIENT_LANDSCAPE:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		_:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


func _apply() -> void:
	var root: Window = get_tree().root
	var size: Vector2i = root.size
	var wide: bool = size.x > size.y
	root.content_scale_size = Vector2i(LANDSCAPE_HEIGHT, LANDSCAPE_HEIGHT) if wide else PORTRAIT_BASE
	if wide != landscape:
		landscape = wide
		# 크기가 바뀐 뒤(다음 프레임)에 HUD 자리를 다시 잡는다.
		HudLayout.relayout.call_deferred(get_tree())
		changed.emit(landscape)


## 지금 화면의 논리 크기 (UI 좌표).
func logical_size() -> Vector2:
	return get_tree().root.get_visible_rect().size
