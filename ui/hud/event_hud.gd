class_name EventHud
extends Control
## 마을 이벤트 표시: 화면 위쪽(시각 줄 아래)의 이벤트 칩, 누르면 펼쳐지는 설명 카드, 새 이벤트가 열릴 때 내려오는 알림판.
## 이벤트가 언제 열리는지는 서버가 정한다 (Net.events). 오늘 고른 물건은 아이콘과 "×2" 로 보여 준다.

const ICONS: Dictionary[String, String] = {
	"coin": "res://assets/ui/icons/shop.png",
	"merchant": "res://assets/icons/items/star_lamp.png",
	"fishing": "res://assets/ui/icons/fishing.png",
	"axe": "res://assets/icons/items/axe.png",
	"gift": "res://assets/ui/icons/gift.png",
	"star": "res://assets/icons/items/star_fragment.png",
}
const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT_INK: Color = Color(0.52, 0.42, 0.32)
const ACCENT: Color = Color(0.86, 0.36, 0.3)

## 알림판을 보여 주는 시간.
@export_range(1.0, 10.0, 0.5, "suffix:s") var banner_time: float = 4.5

var _chip: Button = null
var _card: PanelContainer = null
var _card_list: VBoxContainer = null
var _banner: PanelContainer = null
var _banner_title: Label = null
var _banner_text: Label = null
var _banner_icon: TextureRect = null
var _banner_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_chip()
	_build_card()
	_build_banner()
	Net.events_changed.connect(_on_events_changed)
	Net.state_changed.connect(func(_s: int) -> void: _refresh())
	_refresh()


## 이벤트 칩에 적힌 글 (테스트용).
func chip_text() -> String:
	return _chip.text if _chip.visible else ""


func banner_text() -> String:
	return _banner_title.text if _banner.visible else ""


## 펼친 설명 카드의 줄들 (테스트용).
func card_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for label: Node in _card_list.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func toggle_card() -> void:
	_card.visible = not _card.visible and not Net.events.is_empty()
	if _card.visible:
		_fill_card()
		Audio.play_ui(Audio.SFX_OPEN)


func _on_events_changed(started: PackedStringArray) -> void:
	_refresh()
	if not started.is_empty():
		_show_banner(started[0])


func _refresh() -> void:
	var online: bool = Net.state == Net.State.ONLINE
	_chip.visible = online and not Net.events.is_empty()
	if not _chip.visible:
		_card.visible = false
		return
	var first: EventInfo = Net.events[0].info()
	_chip.text = first.display_name if Net.events.size() == 1 else "%s 외 %d" % [first.display_name, Net.events.size() - 1]
	_chip.icon = _icon(first.icon)
	if _card.visible:
		_fill_card()


func _fill_card() -> void:
	for child: Node in _card_list.get_children():
		child.queue_free()
	for e: ActiveEvent in Net.events:
		var info: EventInfo = e.info()
		if info == null:
			continue
		var head: HBoxContainer = HBoxContainer.new()
		head.add_theme_constant_override("separation", 14)
		var icon: TextureRect = TextureRect.new()
		icon.texture = _icon(info.icon)
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(icon)
		head.add_child(_label(info.display_name, 40, INK))
		_card_list.add_child(head)
		_card_list.add_child(_label(info.description, 28, SOFT_INK))
		if not e.wanted.is_empty():
			_card_list.add_child(_label("오늘 찾는 물건 (×%s)" % _format_mult(e.multiplier), 28, ACCENT))
			_card_list.add_child(_item_row(e.wanted))
		if info.id == EventInfo.FISHING_DERBY and not info.bonus.is_empty():
			_card_list.add_child(_label("상금: 흔한 물고기 %d솔 · 조금 귀한 %d솔 · 귀한 %d솔" % [info.bonus.get("common", 0), info.bonus.get("uncommon", 0), info.bonus.get("rare", 0)], 28, ACCENT))
		if not e.stock.is_empty():
			_card_list.add_child(_label("파는 물건", 28, ACCENT))
			_card_list.add_child(_item_row(e.stock))
		_card_list.add_child(HSeparator.new())


func _item_row(ids: PackedStringArray) -> HFlowContainer:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	for id: String in ids:
		var slot: ItemSlot = ItemSlot.new()
		slot.custom_minimum_size = Vector2(96, 96)
		slot.disabled = true
		slot.set_item(InventoryItem.new(id, 1))
		slot.tooltip_text = GameData.item_name(id)
		row.add_child(slot)
		row.add_child(_label(GameData.item_name(id), 26, INK))
	return row


func _show_banner(event_id: String) -> void:
	var info: EventInfo = GameData.event_info(event_id)
	if info == null:
		return
	_banner_title.text = info.display_name
	_banner_text.text = info.description
	_banner_icon.texture = _icon(info.icon)
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.position.y = -40.0
	Audio.play_sfx("event_start", -3.0, 1.0, 0.0)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_property(_banner, "position:y", 300.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(banner_time)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.4)
	_banner_tween.chain().tween_callback(func() -> void: _banner.visible = false)


func _build_chip() -> void:
	_chip = Button.new()
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.position = Vector2(24, 268)
	_chip.custom_minimum_size = Vector2(0, 76)
	_chip.add_theme_font_size_override("font_size", 30)
	_chip.expand_icon = true
	_chip.add_theme_constant_override("icon_max_width", 52)
	_chip.add_theme_stylebox_override("normal", _box(Color(1.0, 0.93, 0.8, 0.95), Color(0.86, 0.36, 0.3), 38, 4))
	_chip.add_theme_stylebox_override("hover", _box(Color(1.0, 0.93, 0.8, 0.95), Color(0.86, 0.36, 0.3), 38, 4))
	_chip.add_theme_stylebox_override("pressed", _box(Color(0.97, 0.86, 0.72, 0.95), Color(0.86, 0.36, 0.3), 38, 4))
	_chip.add_theme_color_override("font_color", ACCENT)
	_chip.add_theme_color_override("font_pressed_color", ACCENT)
	_chip.add_theme_color_override("font_hover_color", ACCENT)
	_chip.pressed.connect(toggle_card)
	_chip.add_to_group(&"blocks_joystick")
	add_child(_chip)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.position = Vector2(24, 356)
	_card.custom_minimum_size = Vector2(1032, 0)
	_card.add_theme_stylebox_override("panel", _box(Color(0.99, 0.96, 0.88, 0.97), Color(0.55, 0.4, 0.28), 30, 5, 28))
	_card.add_to_group(&"blocks_joystick")
	_card.visible = false
	_card.gui_input.connect(func(event: InputEvent) -> void:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse != null and mouse.pressed:
			_card.visible = false)
	_card_list = VBoxContainer.new()
	_card_list.add_theme_constant_override("separation", 10)
	_card.add_child(_card_list)
	add_child(_card)
	_card.minimum_size_changed.connect(_card.reset_size)


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2(90, 300)
	_banner.custom_minimum_size = Vector2(900, 0)
	_banner.add_theme_stylebox_override("panel", _box(Color(1.0, 0.97, 0.9, 0.97), ACCENT, 40, 8, 30))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_banner_icon = TextureRect.new()
	_banner_icon.custom_minimum_size = Vector2(130, 130)
	_banner_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_banner_icon)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(680, 0)
	text.add_child(_label("오늘의 이벤트!", 28, ACCENT))
	_banner_title = _label("", 48, INK)
	text.add_child(_banner_title)
	_banner_text = _label("", 28, SOFT_INK)
	text.add_child(_banner_text)
	row.add_child(text)
	_banner.add_child(row)
	_banner.visible = false
	add_child(_banner)
	# 줄바꿈 라벨은 폭이 정해지기 전엔 높이를 크게 잡는다. 컨테이너는 커지기만 하므로, 최소 크기가 바뀔 때마다 다시 맞춘다.
	_banner.minimum_size_changed.connect(_banner.reset_size)


func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func _icon(key: String) -> Texture2D:
	var path: String = ICONS.get(key, "")
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null


static func _format_mult(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)


static func _box(bg: Color, border: Color, radius: int, width: int, margin: float = 16.0) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.border_width_bottom = width + 3
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.5
	box.content_margin_bottom = margin * 0.5
	return box
