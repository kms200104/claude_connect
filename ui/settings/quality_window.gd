class_name QualityWindow
extends Control
## 설정 창 (v14, 예전 화질 창): 닉네임 + 화질.
## 닉네임: 적고 "저장"을 누르면 기억해 두었다가 마을에 들어갈 때 같이 보낸다 (마을 안이면 바로 바꾼다).
## 화질: 자동(기기 추천) · 절약(갤럭시 S24 기준) · 고화질(갤럭시 Z 폴드7 기준) 중 고르면 바로 바뀌고 기억된다.
## 첫 화면과 마을(방 정보 줄의 "설정" 단추)에서 연다.

signal closed

const BG: Color = Color(0.99, 0.96, 0.88, 0.98)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const PICKED: Color = Color(0.98, 0.84, 0.55)

var _rows: VBoxContainer = null
var _info: Label = null
var _buttons: Dictionary[String, Button] = {}
var _name_edit: LineEdit = null
var _scroll: ScrollContainer = null
var _col: VBoxContainer = null
var _name_note: Label = null


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
	# 가로 화면처럼 낮은 화면에서는 내용을 굴려 본다.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(col)
	_col = col
	var title: Label = _label("설정", 48, INK)
	col.add_child(title)
	col.add_child(_label("닉네임", 34, INK))
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	col.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(0, 96)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = NetProtocol.NAME_MAX
	_name_edit.placeholder_text = "비워 두면 기본 이름"
	_name_edit.add_theme_font_size_override("font_size", 40)
	_name_edit.text_submitted.connect(func(_t: String) -> void: save_name())
	name_row.add_child(_name_edit)
	var save_button: Button = Button.new()
	save_button.text = "저장"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.custom_minimum_size = Vector2(170, 96)
	save_button.add_theme_font_size_override("font_size", 34)
	save_button.pressed.connect(save_name)
	name_row.add_child(save_button)
	_name_note = _label("", 26, SOFT)
	col.add_child(_name_note)
	col.add_child(_label("화질", 34, INK))
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
	_name_edit.text = Net.names.get(Net.my_id, Net.nickname()) if Net.state == Net.State.ONLINE else Net.nickname()
	_fit_height.call_deferred()
	_name_note.text = "글자·숫자 %d자까지 · 마을 사람들 머리 위와 대화에 나와요 (거울에서도 바꿀 수 있어요)" % NetProtocol.NAME_MAX
	_refresh()


## 창 높이: 내용만큼, 화면보다 길면 화면 안까지만 (굴려 본다).
func _fit_height() -> void:
	var room: float = get_viewport_rect().size.y - HudLayout.fit_y(200.0) - 100.0
	_scroll.custom_minimum_size = Vector2(840, minf(_col.get_combined_minimum_size().y, room))


## 닉네임 저장: 기억해 두고, 마을 안이면 바로 바꾼다.
func save_name() -> void:
	var clean: String = NetProtocol.clean_name(_name_edit.text)
	_name_edit.text = clean
	_name_edit.release_focus()
	Net.set_nickname(clean)
	_name_note.text = ("\"%s\" 로 저장했어요" % clean) if not clean.is_empty() else "기본 이름을 써요"
	Audio.play_ui(Audio.SFX_CONFIRM)


## 닉네임 입력 칸 (테스트용).
func name_edit() -> LineEdit:
	return _name_edit


func close() -> void:
	if not visible:
		return
	visible = false
	_name_edit.release_focus()
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
