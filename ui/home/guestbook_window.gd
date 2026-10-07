class_name GuestbookWindow
extends Control
## 방명록 (v16): 집 안에서 "방명록" 단추를 누르면 열린다. 다녀간 사람들이 남긴 글(최근 것 위)과 쓰는 칸.
## 글은 서버가 확정해 그 집 안의 모두에게 보내고(Journal.guestbook), 집 주인에게는 마을톡으로 알린다.

signal closed

const BG: Color = Color(1.0, 0.98, 0.92, 0.98)
const PAPER: Color = Color(1.0, 0.99, 0.95)
const EDGE: Color = Color(0.5, 0.38, 0.26)
const INK: Color = Color(0.28, 0.2, 0.14)
const SOFT: Color = Color(0.5, 0.42, 0.34)
const LINE: Color = Color(0.86, 0.8, 0.7)

var _panel: PanelContainer = null
var _title: Label = null
var _list: VBoxContainer = null
var _edit: LineEdit = null
var _note: Label = null
var _lift: float = 0.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.08, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 28))
	HudLayout.center_top(_panel, 920.0, 220.0)
	HudLayout.fit_bottom(_panel, 1640.0)
	add_child(_panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_panel.add_child(col)
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	_title = _label("방명록", 40, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close_button: Button = _button("닫기", 30)
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var input: HBoxContainer = HBoxContainer.new()
	input.add_theme_constant_override("separation", 10)
	col.add_child(input)
	_edit = LineEdit.new()
	_edit.name = "GuestbookEdit"
	_edit.placeholder_text = "한마디 남기기 (100자까지)"
	_edit.max_length = 100
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 90)
	_edit.add_theme_font_size_override("font_size", 30)
	_edit.text_submitted.connect(func(_t: String) -> void: submit())
	input.add_child(_edit)
	var send: Button = _button("남기기", 30)
	send.name = "GuestbookSend"
	send.pressed.connect(submit)
	input.add_child(send)
	_note = _label("", 24, SOFT)
	col.add_child(_note)
	Journal.guestbook_changed.connect(_refresh)
	Journal.failed.connect(func(kind: String, code: String) -> void:
		if kind == "gb_write" and visible:
			_note.text = "조금 있다가 다시 써요." if code == NetProtocol.ERR_TOO_FAST else "남기지 못했어요 (%s)" % code)
	Home.door_passed.connect(func(unit: String, _p: Vector3) -> void:
		if unit.is_empty():
			close())


func is_open() -> bool:
	return visible


func open() -> void:
	var whose: String = "우리 집" if Home.editable else "%s 님 집" % GameData.player_name(Home.owner_slot)
	_title.text = "%s 방명록" % whose
	_note.text = "집 주인에게 마을톡으로 알려요." if not Home.editable else "다녀간 친구들이 남긴 글이에요."
	_refresh()
	visible = true
	Audio.play_sfx("ui_open", -6.0)


func close() -> void:
	if not visible:
		return
	visible = false
	_edit.release_focus()
	closed.emit()


func submit() -> void:
	var t: String = _edit.text.strip_edges()
	if t.is_empty():
		return
	Journal.write_guestbook(t)
	_edit.text = ""
	_edit.release_focus()
	_note.text = "남겼어요!"
	Audio.play_ui(Audio.SFX_CONFIRM)


func _process(_delta: float) -> void:
	if not visible:
		return
	var want: float = KeyboardLift.lift_for(_panel, _lift)
	if absf(want - _lift) > 1.0:
		_panel.position.y += _lift - want
		_lift = want


func _refresh() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	if Journal.guestbook.is_empty():
		_list.add_child(_label("아직 남긴 글이 없어요. 첫 글을 남겨 보세요!", 28, SOFT))
		return
	var entries: Array[Dictionary] = Journal.guestbook.duplicate()
	entries.reverse()
	for e: Dictionary in entries:
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", EventHud._box(PAPER, LINE, 18, 2, 16))
		_list.add_child(card)
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var head: HBoxContainer = HBoxContainer.new()
		col.add_child(head)
		var who: Label = _label(Journal.display_name(int(e.get("by", 0))), 26, Color("#9A6A10"))
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(who)
		head.add_child(_label(_when(float(e.get("at", 0.0))), 22, SOFT, false))
		col.add_child(_label(str(e.get("tx", "")), 30, INK))


static func _when(at_ms: float) -> String:
	if at_ms <= 0.0:
		return ""
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(int(at_ms / 1000.0) + PhoneWindow._tz_offset_s())
	var h: int = int(t["hour"])
	return "%d/%d %s %d:%02d" % [int(t["month"]), int(t["day"]), "오전" if h < 12 else "오후", (h + 11) % 12 + 1, int(t["minute"])]


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 88)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	return b


func _label(text: String, font_size: int, color: Color, wrap: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
