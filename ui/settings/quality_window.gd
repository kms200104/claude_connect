class_name QualityWindow
extends Control
## 화질 창: 자동(기기 추천) · 절약(갤럭시 S24 기준) · 고화질(갤럭시 Z 폴드7 기준) 중 고르면 바로 바뀌고 기억된다.
## 첫 화면과 마을(방 정보 줄의 "화질" 단추)에서 연다.

signal closed

const BG: Color = Color(0.99, 0.96, 0.88, 0.98)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const PICKED: Color = Color(0.98, 0.84, 0.55)

var _rows: VBoxContainer = null
var _info: Label = null
var _buttons: Dictionary[String, Button] = {}


## parent 아래에 창을 만들어 붙이고 돌려준다 (부모가 아직 자식을 꾸미는 중일 수 있어 다음 틈에 붙인다).
static func attach(parent: Node) -> QualityWindow:
	var window: QualityWindow = QualityWindow.new()
	window.name = "QualityWindow"
	parent.add_child.call_deferred(window)
	return window


## 단추 하나 (누르면 window 를 연다).
static func make_button(window: QualityWindow, font_size: int = 30) -> Button:
	var b: Button = Button.new()
	b.text = "화질"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(window.open)
	return b


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.05, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 30))
	panel.custom_minimum_size = Vector2(900, 0)
	HudLayout.center_top(panel, 900.0, 380.0)
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)
	var title: Label = _label("화질", 48, INK)
	col.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	col.add_child(_rows)
	for id: String in [Quality.AUTO] + Array(Quality.preset_ids()):
		var b: Button = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(840, 130)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 34)
		b.add_theme_color_override("font_color", INK)
		b.pressed.connect(_pick.bind(id))
		_rows.add_child(b)
		_buttons[id] = b
	_info = _label("", 26, SOFT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(840, 0)
	col.add_child(_info)
	var done: Button = Button.new()
	done.text = "닫기"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(0, 90)
	done.add_theme_font_size_override("font_size", 34)
	done.pressed.connect(close)
	col.add_child(done)
	Quality.changed.connect(_refresh)


func is_open() -> bool:
	return visible


func open() -> void:
	if not is_inside_tree():
		return
	visible = true
	Audio.play_ui(Audio.SFX_OPEN)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play_ui(Audio.SFX_CLOSE)
	closed.emit()


func _pick(id: String) -> void:
	Audio.play_ui(Audio.SFX_CLICK)
	Quality.choose(id)
	_refresh()


func _refresh() -> void:
	for id: String in _buttons:
		var b: Button = _buttons[id]
		if id == Quality.AUTO:
			var device: String = Quality.device_name if not Quality.device_name.is_empty() else "이 기기"
			b.text = "  자동 — %s 추천: %s" % [device, Quality.preset_name(Quality.recommended)]
		else:
			b.text = "  %s\n  %s" % [Quality.preset_name(id), Quality.preset_about(id)]
		var picked: bool = Quality.choice == id
		b.add_theme_stylebox_override("normal", EventHud._box(PICKED if picked else Color(1, 1, 1, 0.92), EDGE, 26, 5 if picked else 2, 12))
		b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
	var root: Window = get_tree().root
	_info.text = "지금: %s · 3D 해상도 %d%% (%d×%d 화면) · 계단 줄이기 %s배 · 그림자 %s" % [
		Quality.preset_name(Quality.preset_id), roundi(Quality.render_scale() * 100.0), root.size.x, root.size.y,
		str(int(Quality.value("msaa", 2))), "부드럽게" if bool(Quality.value("shadow_soft", false)) else "또렷하게"]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
