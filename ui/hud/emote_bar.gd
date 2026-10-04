class_name EmoteBar
extends Control
## 감정표현 칸: 오른쪽의 동그란 웃는 얼굴 단추를 누르면 감정표현 퀵슬롯이 옆으로 펼쳐진다.
## 퀵슬롯을 누르면 그 감정표현을 하고, 연필 단추는 감정표현 창(EmoteWindow)을 열어 퀵슬롯을 고친다.
## 처음엔 '안녕'만 있고, 주민과 친해지면 배운 감정표현이 빈 칸에 저절로 들어간다.

signal emote_chosen(emote_id: String)
signal edit_pressed

## 단추 크기와 자리 (1080×1920 화면 기준, 오른쪽 가장자리에서).
@export var button_size: float = 118.0
@export var anchor_y: float = 1150.0

const BG: Color = Color(1.0, 0.97, 0.9, 0.96)
const EDGE: Color = Color(0.55, 0.4, 0.28)

var _toggle: Button = null
var _strip: PanelContainer = null
var _row: HBoxContainer = null
var _slots: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_toggle = _round_button(EmoteInfo.icon("happy"), button_size)
	HudLayout.right_top(_toggle, Vector2(button_size, button_size), 24.0, anchor_y)
	_toggle.pressed.connect(toggle)
	add_child(_toggle)
	_strip = PanelContainer.new()
	_strip.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 4, 14))
	_strip.add_to_group(&"blocks_joystick")
	_strip.visible = false
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	_strip.add_child(_row)
	add_child(_strip)
	# 펼친 줄은 실제 크기를 재서 웃는 얼굴 단추 바로 왼쪽에 붙인다.
	_strip.minimum_size_changed.connect(_place_strip)
	resized.connect(_place_strip)
	Net.profile_updated.connect(_refresh)
	Net.state_changed.connect(func(_s: int) -> void: _refresh())
	_refresh()


func is_open() -> bool:
	return _strip.visible


func toggle() -> void:
	_strip.visible = not _strip.visible
	Audio.play_ui(Audio.SFX_OPEN if _strip.visible else Audio.SFX_CLOSE)
	_refresh()


func close() -> void:
	_strip.visible = false


## 퀵슬롯 단추 (테스트용).
func slot_button(index: int) -> Button:
	return _slots[index] if index >= 0 and index < _slots.size() else null


func _refresh() -> void:
	var online: bool = Net.state == Net.State.ONLINE
	visible = online
	for child: Node in _row.get_children():
		child.queue_free()
	_slots.clear()
	for id: String in Net.emotes_quick:
		var b: Button = _round_button(EmoteInfo.icon(id), button_size * 0.9)
		b.tooltip_text = GameData.emote_name(id)
		b.pressed.connect(func() -> void: emote_chosen.emit(id))
		_row.add_child(b)
		_slots.append(b)
	var edit: Button = _round_button(null, button_size * 0.9)
	edit.text = "✎"
	edit.add_theme_font_size_override("font_size", 46)
	edit.add_theme_color_override("font_color", EDGE)
	edit.pressed.connect(func() -> void:
		close()
		edit_pressed.emit())
	_row.add_child(edit)
	_place_strip.call_deferred()


func _place_strip() -> void:
	_strip.reset_size()
	_strip.position = Vector2(_toggle.position.x - 12.0 - _strip.size.x, anchor_y + (button_size - _strip.size.y) * 0.5)


func _round_button(icon: Texture2D, size: float) -> Button:
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.size = Vector2(size, size)
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", int(size * 0.8))
	var normal: StyleBoxFlat = EventHud._box(BG, EDGE, int(size * 0.5), 4, 6)
	var pressed: StyleBoxFlat = EventHud._box(Color(0.96, 0.88, 0.74), EDGE, int(size * 0.5), 4, 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_to_group(&"blocks_joystick")
	return b
