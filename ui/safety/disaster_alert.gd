class_name DisasterAlert
extends PanelContainer
## 재난문자 창 (v0.20): 진짜 휴대폰처럼 화면 위에 뜬다 — 긴급재난문자(빨강, 날카로운 경보음 · 긴 진동) · 안전안내문자(주황, 알림음).
## "확인"을 누르거나 AUTO_CLOSE 초가 지나면 닫힌다. 여러 개가 오면 새것이 위에.

const AUTO_CLOSE: float = 20.0
const RED: Color = Color("#D93A30")
const ORANGE: Color = Color("#E88A1A")
const INK: Color = Color(0.2, 0.14, 0.1)

var alert: Dictionary = {}
var _player: AudioStreamPlayer = null


## HUD 에 띄운다 (소리 · 진동 함께).
static func pop(parent: Node, data: Dictionary) -> DisasterAlert:
	var box: DisasterAlert = DisasterAlert.new()
	box.alert = data
	box.name = "DisasterAlert"
	parent.add_child(box)
	return box


func _ready() -> void:
	var emergency: bool = str(alert.get("level", "")) == "emergency"
	var color: Color = RED if emergency else ORANGE
	add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.99, 0.97, 0.98), color, 30, 6, 22))
	add_to_group(&"blocks_joystick")
	mouse_filter = Control.MOUSE_FILTER_STOP
	HudLayout.center_top(self, 960.0, 120.0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	var badge: Label = _label("⚠ %s" % ("긴급재난문자" if emergency else "안전안내문자"), 32, color)
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(badge)
	head.add_child(_label(Time.get_time_string_from_system().left(5), 24, Color(0.5, 0.42, 0.34)))
	if not str(alert.get("sender", "")).is_empty():
		col.add_child(_label("발신: %s" % str(alert.get("sender", "")), 22, Color(0.5, 0.42, 0.34)))
	var text: Label = _label(str(alert.get("text", "")), 28, INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(880, 0)
	col.add_child(text)
	var ok: Button = Button.new()
	ok.name = "OkButton"
	ok.text = "확인"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(0, 76)
	ok.add_theme_font_size_override("font_size", 28)
	ok.pressed.connect(close)
	col.add_child(ok)
	_player = AudioStreamPlayer.new()
	_player.bus = "Sfx"
	_player.stream = AlertSounds.get_stream("emergency" if emergency else "chime")
	_player.volume_db = -2.0 if emergency else -6.0
	add_child(_player)
	_player.play()
	Prefs.vibrate(1200 if emergency else 300, 1.0 if emergency else 0.6)
	get_tree().create_timer(AUTO_CLOSE).timeout.connect(close)


func close() -> void:
	if is_queued_for_deletion():
		return
	queue_free()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
