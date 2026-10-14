class_name StashWindow
extends Control
## 거점 상자 창 (v0.25): 다 막은 빈집 앞방 상자 — 그 집을 함께 쓰는 사람 모두의 보관함.
## 위: 상자에 든 것 (그림 · 이름 × 개수 · "1개" · "다 꺼내기"), 아래: 가방 (칸마다 "넣기" · 여러 개면 "1개").
## 판정은 서버 (Net.stash_put · Net.stash_take → stash), 열린 채로 다른 사람이 넣고 빼도 바로 바뀐다.

signal closed

const INK: Color = Color("#4A3020")
const SOFT: Color = Color("#8A7058")
const CREAM: Color = Color("#FFF8EC")

var house_id: String = ""
var _title: Label = null
var _stash_list: VBoxContainer = null
var _bag_list: VBoxContainer = null


func _ready() -> void:
	name = "StashWindow"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", EventHud._box(CREAM, Color("#C9A57A"), 36, 4, 26))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40.0
	panel.offset_right = -40.0
	panel.offset_top = 200.0
	panel.offset_bottom = -220.0
	add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	_title = _label("거점 상자", 44, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_button: Button = _button("닫기", 34)
	close_button.name = "CloseButton"
	close_button.pressed.connect(close)
	head.add_child(close_button)
	box.add_child(_label("함께 쓰는 상자예요. 판자가 부서져도 넣어 둔 것은 남아요.", 26, SOFT))
	for part: Array in [["StashScroll", "상자"], ["BagScroll", "가방"]]:
		box.add_child(_label(str(part[1]), 32, INK))
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.name = str(part[0])
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = 0.7 if part[0] == "StashScroll" else 1.3
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var list: VBoxContainer = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		if part[0] == "StashScroll":
			_stash_list = list
			list.name = "StashList"
		else:
			_bag_list = list
			list.name = "BagList"
	Net.stash_changed.connect(func(h: String) -> void:
		if visible and h == house_id:
			_build.call_deferred())
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void:
		if visible:
			_build.call_deferred())


func is_open() -> bool:
	return visible


func open(house: String) -> void:
	house_id = house
	move_to_front()
	visible = true
	_build()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _build() -> void:
	var items: Array = Net.stash.get(house_id, [])
	_title.text = "거점 상자 · %d/%d칸" % [items.size(), GameData.survival.stash_slots]
	for list: VBoxContainer in [_stash_list, _bag_list]:
		for c: Node in list.get_children():
			c.queue_free()
	if items.is_empty():
		_stash_list.add_child(_label("비어 있어요", 28, SOFT))
	for e: Variant in items:
		var id: String = str(e.get("id", ""))
		var n: int = int(e.get("n", 0))
		var row: HBoxContainer = _row(id, n)
		row.name = "Stash_%s" % id
		if n > 1:
			var one: Button = _button("1개", 26)
			one.name = "TakeOne_%s" % id
			one.pressed.connect(func() -> void: Net.stash_take(house_id, id, 1))
			row.add_child(one)
		var all: Button = _button("꺼내기", 26)
		all.name = "Take_%s" % id
		all.pressed.connect(func() -> void: Net.stash_take(house_id, id, 0))
		row.add_child(all)
		_stash_list.add_child(row)
	var any: bool = false
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it == null or it.id.is_empty():
			continue
		any = true
		var slot: int = i
		var row: HBoxContainer = _row(it.id, it.count)
		row.name = "Bag_%d" % slot
		if it.count > 1:
			var one: Button = _button("1개", 26)
			one.name = "PutOne_%d" % slot
			one.pressed.connect(func() -> void: Net.stash_put(house_id, slot, 1))
			row.add_child(one)
		var put: Button = _button("넣기", 26)
		put.name = "Put_%d" % slot
		put.pressed.connect(func() -> void: Net.stash_put(house_id, slot, 0))
		row.add_child(put)
		_bag_list.add_child(row)
	if not any:
		_bag_list.add_child(_label("가방이 비었어요", 28, SOFT))


func _row(item_id: String, n: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon: TextureRect = TextureRect.new()
	icon.texture = GameData.item_icon(item_id)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var l: Label = _label("%s × %d" % [GameData.item_name(item_id), n], 30, INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 72)
	b.add_theme_font_size_override("font_size", size)
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	return b
