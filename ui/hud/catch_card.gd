class_name CatchCard
extends Control
## 물고기를 낚았을 때 화면 위쪽에 뜨는 자랑 카드: 희귀도별 외침("와---!! 대어를 낚았어!"), 물고기 아이콘·이름·별,
## 물고기마다 다른 재미있는 한마디(fish.json 의 catch). 귀할수록 카드가 크게 튀고 반짝인다. 누르면 바로 닫힌다.

signal dismissed

const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const RARITY_COLOR: Dictionary[String, Color] = {
	"common": Color(0.36, 0.55, 0.32), "uncommon": Color(0.26, 0.5, 0.78), "rare": Color(0.86, 0.5, 0.12),
}
const RARITY_NAME: Dictionary[String, String] = {"common": "흔함", "uncommon": "조금 귀함", "rare": "귀함"}

var _panel: PanelContainer = null
var _shout: Label = null
var _icon: TextureRect = null
var _name: Label = null
var _stars: Label = null
var _line: Label = null
var _tween: Tween = null
var _hiding: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.position = Vector2(70, 250)
	_panel.custom_minimum_size = Vector2(940, 0)
	_panel.minimum_size_changed.connect(func() -> void: _panel.reset_size())
	_panel.add_to_group(&"blocks_joystick")
	_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			hide_card())
	add_child(_panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	_shout = _label("", 50, Color(0.86, 0.36, 0.3))
	_shout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_shout)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(150, 150)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(700, 0)
	row.add_child(text)
	_name = _label("", 46, INK)
	text.add_child(_name)
	_stars = _label("", 28, SOFT)
	text.add_child(_stars)
	_line = _label("", 32, INK)
	text.add_child(_line)
	_panel.visible = false


func is_showing() -> bool:
	return _panel.visible and not _hiding


## 테스트용: 지금 보이는 외침과 한마디.
func shout_text() -> String:
	return _shout.text if is_showing() else ""


func line_text() -> String:
	return _line.text if is_showing() else ""


func show_catch(fish_id: String, shout: String) -> void:
	var fish: FishInfo = GameData.fish.get(fish_id)
	if fish == null:
		return
	var color: Color = RARITY_COLOR.get(fish.rarity, INK)
	_panel.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.97, 0.9, 0.97), color, 40, 8 if fish.rarity == "rare" else 5, 28))
	_shout.text = shout
	_shout.add_theme_color_override("font_color", color)
	_shout.add_theme_font_size_override("font_size", 64 if fish.rarity == "rare" else (54 if fish.rarity == "uncommon" else 46))
	_icon.texture = GameData.item_icon(fish_id)
	_name.text = fish.display_name
	var stars: int = {"common": 1, "uncommon": 2, "rare": 3}.get(fish.rarity, 1)
	_stars.text = "%s  %s · %s" % ["★".repeat(stars) + "☆".repeat(3 - stars), RARITY_NAME.get(fish.rarity, ""), {"S": "작은 몸집", "M": "보통 몸집", "L": "큰 몸집"}.get(fish.size, "")]
	_line.text = fish.catch_line if not fish.catch_line.is_empty() else "%s을(를) 낚았다!" % fish.display_name
	_hiding = false
	_panel.visible = true
	_panel.reset_size()
	_panel.pivot_offset = Vector2(470, 120)
	_panel.scale = Vector2(0.3, 0.3)
	_panel.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.45 if fish.rarity == "rare" else 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	if fish.rarity == "rare":
		# 귀한 물고기: 외침이 두근두근 커졌다 작아진다.
		var pulse: Tween = create_tween().set_loops(3)
		pulse.tween_property(_shout, "scale", Vector2(1.08, 1.08), 0.18)
		pulse.tween_property(_shout, "scale", Vector2.ONE, 0.18)
		_shout.pivot_offset = Vector2(440, 36)


func hide_card() -> void:
	if not _panel.visible or _hiding:
		return
	_hiding = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(func() -> void:
		_panel.visible = false
		_hiding = false)
	dismissed.emit()


func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
