class_name PhoneApp
extends VBoxContainer
## 휴대폰 앱 화면 하나의 바탕 (v16). PhoneWindow 가 앱을 열 때 만들어 앱 화면(굴려 보는 칸)에 넣는다.
## 휴대폰 창과 같은 모양(카드 · 단추 · 글자)을 쓰고, 뒤로(◁) 를 앱 안에서 먼저 처리할 수 있다 (go_back).

const BG: Color = Color(0.99, 0.96, 0.88, 0.99)
const EDGE: Color = Color(0.3, 0.26, 0.24)
const INK: Color = Color(0.3, 0.2, 0.12)
const SOFT: Color = Color(0.5, 0.42, 0.34)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.7)
const PICKED: Color = Color(0.98, 0.84, 0.55)
const GOOD: Color = Color("#3E8E4E")
const WARN: Color = Color("#D8402F")

## 이 앱을 띄운 휴대폰 (캐릭터 · 카메라에 닿을 때).
var phone: PhoneWindow = null


func _init(owner_phone: PhoneWindow = null) -> void:
	phone = owner_phone
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## 앱 안의 한 단계 뒤로 (처리했으면 true, 아니면 휴대폰이 홈으로 간다).
func go_back() -> bool:
	return false


## 휴대폰을 넣거나 다른 앱으로 갈 때 (카메라 끄기 등).
func on_close() -> void:
	pass


## 앱 화면에 쓸 수 있는 높이 (굴려 보는 칸의 높이, 아직 모르면 기본값).
func view_height() -> float:
	var scroll: ScrollContainer = get_parent().get_parent() as ScrollContainer if get_parent() != null else null
	return scroll.size.y if scroll != null and scroll.size.y > 100.0 else 980.0


## 앱 화면 폭.
func view_width() -> float:
	var scroll: ScrollContainer = get_parent().get_parent() as ScrollContainer if get_parent() != null else null
	return scroll.size.x if scroll != null and scroll.size.x > 100.0 else 790.0


func clear() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()


# ---- 모양 (PhoneWindow 와 같은 모양) ----

func card(parent: Control = self) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(CARD, Color(0.75, 0.66, 0.54), 26, 3, 20))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	return col


func button(text: String, font_size: int = 28, color: Color = INK, picked: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.35))
	if picked:
		b.add_theme_stylebox_override("normal", EventHud._box(PICKED, EDGE, 22, 3, 10))
	return b


func row_button(height: float = 104.0) -> Button:
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("normal", EventHud._box(CARD, Color(0.8, 0.72, 0.6), 22, 2, 16))
	b.add_theme_stylebox_override("hover", EventHud._box(Color(1.0, 0.97, 0.88), Color(0.8, 0.72, 0.6), 22, 2, 16))
	b.add_theme_stylebox_override("pressed", EventHud._box(PICKED, Color(0.8, 0.72, 0.6), 22, 2, 16))
	return b


## 단추 안을 가득 채우는 가로 줄 (row_button 안에 넣는다).
func fill_row(b: Button, separation: int = 16) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", separation)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 18.0
	line.offset_right = -18.0
	b.add_child(line)
	return line


## wrap = 줄바꿈 (폭이 정해지지 않은 곳은 false).
func label(text: String, font_size: int, color: Color = INK, wrap: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 탭 줄 (picked = 지금 탭 번호). 누르면 on_pick(번호).
func tabs(names: PackedStringArray, picked: int, on_pick: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i: int in names.size():
		var b: Button = button(names[i], 28, INK, i == picked)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			on_pick.call(i))
		row.add_child(b)
	add_child(row)
	return row


## 물고기 · 아이템 그림 칸 (없으면 이름 첫 글자). dim = 아직 모르는 것(그림자처럼).
func item_chip(id: String, size_px: float, dim: bool = false) -> Control:
	var tex: Texture2D = GameData.item_icon(id)
	var holder: PanelContainer = PanelContainer.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", EventHud._box(Color(1, 1, 1, 0.85) if not dim else Color(0.85, 0.82, 0.78, 0.8), Color(0.82, 0.74, 0.62), int(size_px * 0.2), 2, 6))
	if tex != null:
		var r: TextureRect = TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if dim:
			r.modulate = Color(0.12, 0.1, 0.1, 0.55)
		holder.add_child(r)
	else:
		var l: Label = label("?" if dim else GameData.item_name(id).left(1), int(size_px * 0.4), SOFT, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(l)
	return holder


## 막대 (0~1).
func meter(value: float, color: Color) -> Control:
	return MeterBar.make(20.0, clampf(value, 0.0, 1.0), color)
