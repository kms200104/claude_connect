class_name ItemSlot
extends Button
## 인벤토리 한 칸. 아이템 아이콘(없으면 색 동그라미 + 짧은 이름) + 개수를 그린다.
## 퀵슬롯(화면 아래)과 가방 창이 같은 칸을 쓴다. 누르면 pressed 신호 (Button).

## 인벤토리 칸 번호 (Net.inventory 의 인덱스).
var slot_index: int = -1
## 손에 든 칸(퀵슬롯) 표시.
var held: bool = false:
	set(value):
		held = value
		queue_redraw()
## 가방 창에서 고른 칸 표시.
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
## 퀵슬롯 번호 표시 (1~5). 0이면 안 그린다.
var hotkey: int = 0

var _item: InventoryItem = null
var _info: ItemInfo = null

const BG: Color = Color(0.99, 0.96, 0.88, 0.92)
const BORDER: Color = Color(0.55, 0.4, 0.28, 1.0)
const HELD_BORDER: Color = Color(1.0, 0.72, 0.2, 1.0)
const SELECTED_BORDER: Color = Color(0.3, 0.62, 0.95, 1.0)
const TEXT: Color = Color(0.25, 0.2, 0.16, 1.0)


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(124, 124)
	add_to_group(&"blocks_joystick")


func set_item(item: InventoryItem) -> void:
	_item = item
	_info = GameData.item(item.id) if item != null else null
	tooltip_text = _info.display_name if _info != null else ""
	queue_redraw()


func get_item() -> InventoryItem:
	return _item


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2(4, 4), size - Vector2(8, 8))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = BG
	box.set_corner_radius_all(int(r.size.x * 0.22))
	box.set_border_width_all(8 if (held or selected) else 4)
	box.border_color = SELECTED_BORDER if selected else (HELD_BORDER if held else BORDER)
	draw_style_box(box, r)
	var font: Font = get_theme_default_font()
	if hotkey > 0:
		draw_string(font, r.position + Vector2(14, 30), str(hotkey), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BORDER)
	if _item == null:
		return
	var icon: Texture2D = GameData.item_icon(_item.id)
	if icon != null:
		var side: float = r.size.x * 0.78
		draw_texture_rect(icon, Rect2(r.get_center() - Vector2(side, side) * 0.5 - Vector2(0, 2), Vector2(side, side)), false)
	else:
		var center: Vector2 = r.get_center() - Vector2(0, 6)
		var radius: float = r.size.x * 0.3
		var color: Color = _info.color if _info != null else Color.GRAY
		draw_circle(center, radius, color)
		draw_arc(center, radius, 0.0, TAU, 32, color.darkened(0.35), 3.0, true)
		var label: String = _info.short_name if _info != null else _item.id.left(2)
		var font_size: int = int(r.size.x * 0.24)
		draw_string(font, center + Vector2(-radius, font_size * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color.WHITE)
	if _item.count > 1:
		var count_size: int = int(r.size.x * 0.2)
		draw_string_outline(font, r.end - Vector2(r.size.x * 0.5 + 8, 10), str(_item.count), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x * 0.5, count_size, 8, BG)
		draw_string(font, r.end - Vector2(r.size.x * 0.5 + 8, 10), str(_item.count), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x * 0.5, count_size, TEXT)
