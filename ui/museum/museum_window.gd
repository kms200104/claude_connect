class_name MuseumWindow
extends Control
## 박물관 창 (관장과 이야기해서 연다).
##   기증하기: 가방 속 물고기 중 아직 박물관에 없는 종류만 보여 주고, 누르면 서버에 기증을 요청한다.
##   물고기 도감: 마을 호수의 물고기 전부. 기증된 물고기는 그림·이름·기증한 사람·설명, 아직이면 물음표 그림자.

signal closed
## 기증을 요청했다 (가방 칸).
signal donate_requested(slot: int)

const MODE_DONATE: String = "donate"
const MODE_BOOK: String = "book"
const BG: Color = Color(0.99, 0.96, 0.88, 0.98)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)

@export var player: Player

var mode: String = MODE_BOOK
var _title: Label = null
var _count: Label = null
var _scroll: ScrollContainer = null
var _list: Container = null
var _detail: Label = null


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 30))
	panel.custom_minimum_size = Vector2(980, 1380)
	HudLayout.center_top(panel, 980.0, 230.0)
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	_title = _label("", 46, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_button: Button = Button.new()
	close_button.text = "닫기"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 32)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_count = _label("", 30, SOFT)
	col.add_child(_count)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_detail = _label("", 30, INK)
	_detail.custom_minimum_size = Vector2(0, 150)
	col.add_child(_detail)
	Net.museum_changed.connect(func(_id: String, _by: int) -> void: _refresh())
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _refresh())
	Net.state_changed.connect(func(s: int) -> void:
		if s == Net.State.DISCONNECTED:
			close())


func is_open() -> bool:
	return visible


func open(start_mode: String) -> void:
	mode = start_mode
	visible = true
	_detail.text = ""
	if player != null:
		player.set_input_lock(&"museum", true)
	Audio.play_ui(Audio.SFX_OPEN)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.set_input_lock(&"museum", false)
	Audio.play_ui(Audio.SFX_CLOSE)
	closed.emit()


## 목록 줄/칸 수 (테스트용).
func entry_count() -> int:
	var n: int = 0
	if _list != null:
		for child: Node in _list.get_children():
			if not child.is_queued_for_deletion():
				n += 1
	return n


func _refresh() -> void:
	if not visible:
		return
	if _list != null:
		_list.queue_free()
	var donated: int = Net.museum_fish.size()
	var total: int = GameData.fish.size()
	_count.text = "기증된 물고기 %d / %d 종" % [donated, total]
	if mode == MODE_DONATE:
		_title.text = "물고기 기증하기"
		var rows: VBoxContainer = VBoxContainer.new()
		rows.add_theme_constant_override("separation", 10)
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list = rows
		var seen: Dictionary[String, bool] = {}
		for i: int in Net.inventory.size():
			var item: InventoryItem = Net.inventory[i]
			if item == null or not GameData.fish.has(item.id) or Net.museum_fish.has(item.id) or seen.has(item.id):
				continue
			seen[item.id] = true
			rows.add_child(_donate_row(i, GameData.fish[item.id]))
		if seen.is_empty():
			rows.add_child(_label("가방에 아직 기증하지 않은 물고기가 없어요. 낚시를 하러 가 볼까요?", 32, SOFT))
	else:
		_title.text = "물고기 도감"
		var grid: GridContainer = GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_list = grid
		for fish: FishInfo in GameData.fish.values():
			grid.add_child(_book_cell(fish))
	_scroll.add_child(_list)


func _donate_row(slot: int, fish: FishInfo) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var icon: TextureRect = _icon(GameData.item_icon(fish.id), 110)
	row.add_child(icon)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(_label(fish.display_name, 38, INK))
	text.add_child(_label(fish.description, 26, SOFT))
	row.add_child(text)
	var b: Button = Button.new()
	b.text = "기증"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 90)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(func() -> void:
		b.disabled = true
		donate_requested.emit(slot))
	row.add_child(b)
	return row


func _book_cell(fish: FishInfo) -> Control:
	var known: bool = Net.museum_fish.has(fish.id)
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(225, 230)
	b.icon = GameData.item_icon(fish.id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", 150)
	b.text = fish.display_name if known else "???"
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("icon_normal_color", Color.WHITE if known else Color(0.15, 0.13, 0.12, 0.85))
	b.add_theme_color_override("icon_pressed_color", Color.WHITE if known else Color(0.15, 0.13, 0.12, 0.85))
	b.add_theme_color_override("icon_hover_color", Color.WHITE if known else Color(0.15, 0.13, 0.12, 0.85))
	var box: StyleBoxFlat = EventHud._box(Color(1.0, 0.99, 0.95) if known else Color(0.93, 0.9, 0.84), EDGE, 24, 3, 10)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", box)
	b.add_theme_stylebox_override("pressed", box)
	b.pressed.connect(func() -> void:
		if known:
			_detail.text = "%s — %s\n%s 님이 기증했어요." % [fish.display_name, fish.description, GameData.player_name(Net.museum_fish[fish.id])]
		else:
			_detail.text = "아직 아무도 기증하지 않은 물고기예요. %s" % _when_hint(fish))
	return b


## 언제 잡히는지 슬쩍 알려 준다.
static func _when_hint(fish: FishInfo) -> String:
	var parts: PackedStringArray = []
	var places: PackedStringArray = GameData.fish_places(fish.id)
	if not places.is_empty():
		parts.append(" · ".join(places))
	if not fish.seasons.is_empty():
		var names: PackedStringArray = []
		for s: String in fish.seasons:
			names.append(VillageClock.season_name(s))
		parts.append(", ".join(names))
	if fish.hours.size() == 2:
		parts.append("%d시~%d시" % [fish.hours[0], fish.hours[1]])
	if not fish.weathers.is_empty():
		var names: PackedStringArray = []
		for w: String in fish.weathers:
			names.append({"clear": "맑은 날", "cloudy": "흐린 날", "rain": "비 오는 날", "thunder": "천둥 치는 날"}.get(w, w))
		parts.append(", ".join(names))
	return "힌트: %s에 나온대요." % " · ".join(parts) if not parts.is_empty() else "힌트: 언제든 호수 어딘가에 있대요."


func _icon(texture: Texture2D, size: float) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
