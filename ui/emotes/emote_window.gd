class_name EmoteWindow
extends Control
## 감정표현 창: 위에는 감정표현 퀵슬롯 칸, 아래에는 모든 감정표현 (아직 못 배운 건 물음표).
## 퀵슬롯 칸을 하나 고르고 아래에서 감정표현을 누르면 그 칸에 들어간다 (빈 칸을 고르면 덧붙인다). 서버에 저장된다.
## 못 배운 감정표현을 누르면 누가 가르쳐 주는지 힌트를 보여 준다.

signal closed

@export var player: Player

const BG: Color = Color(0.99, 0.96, 0.88, 0.98)
const EDGE: Color = Color(0.55, 0.4, 0.28)
const INK: Color = Color(0.36, 0.24, 0.14)

var selected_quick: int = 0
var _quick_row: HBoxContainer = null
var _grid: GridContainer = null
var _hint: Label = null


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 32))
	panel.custom_minimum_size = Vector2(960, 0)
	HudLayout.center_top(panel, 960.0, 420.0)
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("감정표현", 46, INK, true))
	var close_button: Button = Button.new()
	close_button.text = "닫기"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 32)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	col.add_child(_label("퀵슬롯 칸을 고르고, 아래에서 넣을 감정표현을 눌러요", 28, Color(0.52, 0.42, 0.32)))
	_quick_row = HBoxContainer.new()
	_quick_row.add_theme_constant_override("separation", 14)
	col.add_child(_quick_row)
	col.add_child(HSeparator.new())
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	col.add_child(_grid)
	_hint = _label("", 28, Color(0.86, 0.36, 0.3))
	col.add_child(_hint)
	Net.profile_updated.connect(func() -> void:
		if visible:
			_refresh())


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	selected_quick = mini(Net.emotes_quick.size(), GameData.emote_quick_slots - 1)
	_hint.text = ""
	if player != null:
		player.set_input_lock(&"emote_window", true)
	Audio.play_ui(Audio.SFX_OPEN)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.set_input_lock(&"emote_window", false)
	Audio.play_ui(Audio.SFX_CLOSE)
	closed.emit()


## 고른 퀵슬롯 칸에 감정표현을 넣는다 (이미 다른 칸에 있으면 그 칸과 맞바꾼다).
func assign(emote_id: String) -> void:
	if not emote_id in Net.emotes_known:
		return
	var quick: PackedStringArray = Net.emotes_quick.duplicate()
	var existing: int = quick.find(emote_id)
	if selected_quick >= quick.size():
		if existing >= 0:
			return
		quick.append(emote_id)
	else:
		if existing >= 0:
			quick[existing] = quick[selected_quick]
		quick[selected_quick] = emote_id
	Net.set_emote_quick(quick)
	Audio.play_ui(Audio.SFX_CONFIRM)
	selected_quick = mini(selected_quick + 1, GameData.emote_quick_slots - 1)
	_refresh()


func _refresh() -> void:
	for child: Node in _quick_row.get_children():
		child.queue_free()
	for i: int in GameData.emote_quick_slots:
		var id: String = Net.emotes_quick[i] if i < Net.emotes_quick.size() else ""
		var b: Button = _card(id, true, i == selected_quick, 120.0)
		b.pressed.connect(func() -> void:
			selected_quick = i
			Audio.play_ui(Audio.SFX_CLICK)
			_refresh())
		_quick_row.add_child(b)
	for child: Node in _grid.get_children():
		child.queue_free()
	for e: EmoteInfo in GameData.emotes:
		var known: bool = e.id in Net.emotes_known
		var b: Button = _card(e.id, known, false, 210.0)
		b.text = e.display_name if known else "???"
		b.pressed.connect(func() -> void:
			if known:
				assign(e.id)
			else:
				_hint.text = "%s — 마을 주민과 친해지면 배울 수 있어요" % _teacher_hint(e.id))
		_grid.add_child(b)


## 누가 가르쳐 주는지 슬쩍 알려 준다.
func _teacher_hint(emote_id: String) -> String:
	for npc: NpcInfo in GameData.npcs.values():
		if emote_id in npc.teaches:
			return "%s이(가) 잘 하는 몸짓" % npc.display_name
	return "아직 아무도 모르는 몸짓"


func _card(emote_id: String, known: bool, selected: bool, width: float) -> Button:
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 120.0)
	b.icon = EmoteInfo.icon(emote_id) if not emote_id.is_empty() else null
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 92)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", INK)
	b.modulate = Color.WHITE if known else Color(0.6, 0.6, 0.6, 0.8)
	var fill: Color = Color(1.0, 0.92, 0.7) if selected else Color(1.0, 0.99, 0.95)
	var box: StyleBoxFlat = EventHud._box(fill, Color(0.86, 0.36, 0.3) if selected else EDGE, 28, 5 if selected else 3, 10)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", box)
	b.add_theme_stylebox_override("pressed", box)
	return b


func _label(text: String, size: int, color: Color, expand: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
