class_name HomeWindow
extends Control
## 엘리베이터 (v0.10): 그 동의 층·호수를 위층부터 보여 주고 골라 들어간다. 호수마다 평형·평면 이름과
## 내 집 / 친구 집 / 빈 집(구경만)을 보여 준다. 들어가기는 서버가 확정한다 (공동 현관 앞이어야 한다).

signal chosen(unit: String)
signal closed

const BG: Color = Color(0.98, 0.97, 0.94, 0.98)
const EDGE: Color = Color(0.36, 0.3, 0.26)
const INK: Color = Color(0.22, 0.18, 0.14)
const SOFT: Color = Color(0.46, 0.4, 0.34)
const MINE: Color = Color(0.98, 0.86, 0.5)
const FRIEND: Color = Color(0.72, 0.88, 0.96)
const EMPTY: Color = Color(1.0, 1.0, 1.0, 0.9)

var building: String = ""
var _title: Label = null
var _body: VBoxContainer = null


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.08, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 26))
	HudLayout.center_top(panel, 960.0, 200.0)
	panel.offset_bottom = 1700.0
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	_title = _label("", 40, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close_button: Button = _button("닫기", 30, EMPTY)
	close_button.pressed.connect(close)
	top.add_child(close_button)
	col.add_child(_label("엘리베이터 — 들어갈 집을 고르세요. 내 집은 '꾸미기'로 가구를 옮길 수 있고, 다른 집은 구경만 해요.", 26, SOFT))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)


func is_open() -> bool:
	return visible


func open(building_id: String) -> void:
	building = building_id
	_title.text = "%s %s동" % [GameData.econ.complex_name(), building_id]
	for c: Node in _body.get_children():
		c.queue_free()
	var floors: Dictionary[int, Array] = {}
	for u: EconData.Unit in GameData.econ.units:
		if u.building == building_id:
			if not floors.has(u.floor):
				floors[u.floor] = []
			floors[u.floor].append(u)
	var keys: Array = floors.keys()
	keys.sort()
	keys.reverse()
	for fl: int in keys:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var floor_label: Label = _label("%d층" % fl, 32, INK)
		floor_label.custom_minimum_size = Vector2(110, 0)
		row.add_child(floor_label)
		for u: EconData.Unit in floors[fl]:
			row.add_child(_unit_button(u))
		_body.add_child(row)
	visible = true


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _unit_button(u: EconData.Unit) -> Button:
	var owner_id: int = int(Economy.home_owners.get(u.id, 0))
	var plan: FloorPlan = GameData.econ.plan_of(u.id)
	var whose: String = "내 집" if owner_id == Net.my_id or (owner_id > 0 and owner_id == Economy.partner) else ("%s 님 집" % GameData.player_name(owner_id) if owner_id > 0 else "빈 집 · 구경")
	var color: Color = MINE if whose == "내 집" else (FRIEND if owner_id > 0 else EMPTY)
	var b: Button = _button("%d%02d호 · %s\n%s" % [u.floor, u.line, plan.display_name if plan != null else u.type, whose], 26, color)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 110)
	b.pressed.connect(func() -> void:
		close()
		chosen.emit(u.id))
	return b


func _button(text: String, font_size: int, color: Color) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_stylebox_override("normal", EventHud._box(color, EDGE, 20, 3, 8))
	b.add_theme_stylebox_override("hover", EventHud._box(color.lightened(0.1), EDGE, 20, 3, 8))
	b.add_theme_stylebox_override("pressed", EventHud._box(color.darkened(0.12), EDGE, 20, 3, 8))
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
