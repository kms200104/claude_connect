class_name QualityWindow
extends Control
## 설정 창 (v14, 예전 화질 창): 내용은 휴대폰 설정 앱과 같은 SettingsPanel (닉네임 · 소리 · 화질 · 화면 방향).
## 닉네임: 적고 "저장"을 누르면 기억해 두었다가 마을에 들어갈 때 같이 보낸다 (마을 안이면 바로 바꾼다).
## 첫 화면과 마을(방 정보 줄의 "설정" 단추)에서 연다.

signal closed

const BG: Color = Color(0.99, 0.96, 0.88, 0.98)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const PICKED: Color = Color(0.98, 0.84, 0.55)

var _scroll: ScrollContainer = null
var _panel: SettingsPanel = null


## parent 아래에 창을 만들어 붙이고 돌려준다 (부모가 아직 자식을 꾸미는 중일 수 있어 다음 틈에 붙인다).
static func attach(parent: Node) -> QualityWindow:
	var window: QualityWindow = QualityWindow.new()
	window.name = "QualityWindow"
	parent.add_child.call_deferred(window)
	return window


## 단추 하나 (누르면 window 를 연다).
static func make_button(window: QualityWindow, font_size: int = 30) -> Button:
	var b: Button = Button.new()
	b.text = "설정"
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
	# 이름 칸이 위쪽에 오게 (글자판이 올라와도 안 가린다).
	HudLayout.center_top(panel, 900.0, 200.0)
	add_child(panel)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	panel.add_child(outer)
	outer.add_child(_label("설정", 48, INK))
	# 내용은 굴려 본다 (소리 · 화질 · 화면까지 길다).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_panel = SettingsPanel.new()
	_scroll.add_child(_panel)
	var done: Button = Button.new()
	done.text = "닫기"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(0, 90)
	done.add_theme_font_size_override("font_size", 34)
	done.pressed.connect(close)
	outer.add_child(done)


func is_open() -> bool:
	return visible


func open() -> void:
	if not is_inside_tree():
		return
	visible = true
	Audio.play_ui(Audio.SFX_OPEN)
	_panel.refresh()
	# 줄바꿈 글자의 높이가 정해진 뒤(한 프레임 뒤)에 잰다.
	_scroll.custom_minimum_size = Vector2(840, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_height()


## 창 높이: 화면 안에 들어오게 (나머지는 굴려 본다).
func _fit_height() -> void:
	var room: float = get_viewport_rect().size.y - HudLayout.fit_y(200.0) - 300.0
	_scroll.custom_minimum_size = Vector2(840, minf(_panel.size.y, room))


## 닉네임 저장 (설정 내용에 맡긴다).
func save_name() -> void:
	_panel.save_name()


## 닉네임 입력 칸 (테스트용).
func name_edit() -> LineEdit:
	return _panel.name_edit()


func settings_panel() -> SettingsPanel:
	return _panel


func close() -> void:
	if not visible:
		return
	visible = false
	_panel.release_focus_all()
	Audio.play_ui(Audio.SFX_CLOSE)
	closed.emit()


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
