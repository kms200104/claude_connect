class_name CraftWindow
extends Control
## 제작 창 (v0.22): 작업대 등급(맨손 · 작업대 · 공용 작업대)에 맞춰 만들 수 있는 생존용품을 보여 준다.
## 칸(전체 · 기본 재료 · 치료 · 식량 · 물 · 도구 · 무기 · 방어 · 설치) → 카드마다 그림 · 이름 × 개수 · 재료(가진 수 / 필요 수, 모자라면 빨강) · 설명 ·
## "만들기" / "최대 n개". 등급이 모자란 것은 흐리게 "작업대 필요" · "공구 창고 필요". 판정은 서버 (Net.craft → crafted).

signal closed

const INK: Color = Color("#4A3020")
const SOFT: Color = Color("#8A7058")
const OK: Color = Color("#2E8B57")
const WARN: Color = Color("#C0392B")
const CREAM: Color = Color("#FFF8EC")

var tier: int = 0
## 내가 놓은 작업대 곁이면 그 가구 id (창에서 "작업대 치우기").
var own_bench: String = ""
var _category: String = ""
var _list: VBoxContainer = null
var _title: Label = null
var _tabs: HBoxContainer = null
var _pending: bool = false


func _ready() -> void:
	name = "CraftWindow"
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
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	_title = _label("제작", 44, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_button: Button = _button("닫기", 34)
	close_button.name = "CloseButton"
	close_button.pressed.connect(close)
	head.add_child(close_button)
	var tab_scroll: ScrollContainer = ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size = Vector2(0, 86)
	box.add_child(tab_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 10)
	tab_scroll.add_child(_tabs)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "RecipeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "RecipeList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void:
		if visible:
			_pending = false
			_build.call_deferred())


func is_open() -> bool:
	return visible


func open(bench_tier: int, bench_id: String = "") -> void:
	tier = bench_tier
	own_bench = bench_id
	move_to_front()
	visible = true
	_pending = false
	_build()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## 가방 아이템 → 개수.
static func have() -> Dictionary:
	var out: Dictionary = {}
	for it: InventoryItem in Net.inventory:
		if it != null and not it.id.is_empty():
			out[it.id] = int(out.get(it.id, 0)) + it.count
	return out


func _build() -> void:
	var rules: CraftingRules = GameData.crafting
	_title.text = "제작 · %s" % CraftingRules.TIER_NAMES[clampi(tier, 0, 2)]
	for c: Node in _tabs.get_children():
		c.queue_free()
	var tabs: Array[Array] = [["", "전체"]]
	tabs.append_array(rules.categories)
	for t: Array in tabs:
		var b: Button = _button(str(t[1]), 28)
		b.name = "Tab_%s" % (str(t[0]) if not str(t[0]).is_empty() else "all")
		if str(t[0]) == _category:
			b.add_theme_stylebox_override("normal", EventHud._box(Color("#F2C14E"), Color("#C9A23A"), 24, 3, 12))
		b.pressed.connect(func() -> void:
			_category = str(t[0])
			Audio.play_ui(Audio.SFX_CLICK)
			_build())
		_tabs.add_child(b)
	for c: Node in _list.get_children():
		c.queue_free()
	if not own_bench.is_empty():
		var take: Button = _button("작업대 치우기 (가방으로)", 26)
		take.name = "PickupBenchButton"
		take.pressed.connect(func() -> void:
			Net.pickup_furniture(own_bench)
			close())
		_list.add_child(take)
	var bag: Dictionary = have()
	var shown: int = 0
	# 지금 만들 수 있는 것 → 재료가 모자란 것 → 작업대가 모자란 것 순서.
	var order: Array[CraftingRules.Recipe] = []
	for r: CraftingRules.Recipe in rules.recipes:
		if _category.is_empty() or r.category == _category:
			order.append(r)
	order.sort_custom(func(a: CraftingRules.Recipe, b: CraftingRules.Recipe) -> bool: return _rank(a, bag) < _rank(b, bag))
	for r: CraftingRules.Recipe in order:
		_list.add_child(_card(r, bag))
		shown += 1
	if shown == 0:
		_list.add_child(_label("이 칸에는 아직 만들 것이 없어요.", 26, SOFT))
	_list.add_child(_label("재료: 나무는 도끼로 베고, 천 · 건전지는 상점에서, 고철 · 플라스틱은 삽으로 땅을 파면 가끔 나와요 (장마에 쓸려 온 것).", 22, SOFT))


func _rank(r: CraftingRules.Recipe, bag: Dictionary) -> int:
	if r.tier > tier:
		return 2
	return 0 if CraftingRules.can_make(r, bag) else 1


func _card(r: CraftingRules.Recipe, bag: Dictionary) -> PanelContainer:
	var locked: bool = r.tier > tier
	var ok: bool = not locked and CraftingRules.can_make(r, bag)
	var card: PanelContainer = PanelContainer.new()
	card.name = "Recipe_%s" % r.id
	card.add_theme_stylebox_override("panel", EventHud._box(Color.WHITE if not locked else Color("#EEE6DA"), Color("#E0CDB0"), 24, 2, 16))
	if locked:
		card.modulate = Color(1, 1, 1, 0.6)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.texture = GameData.item_icon(r.out)
	icon.custom_minimum_size = Vector2(110, 110)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_text: String = GameData.item_name(r.out) + (" × %d" % r.n if r.n > 1 else "")
	info.add_child(_label(name_text, 32, INK))
	var parts: PackedStringArray = []
	for need: Array in r.needs:
		var got: int = int(bag.get(need[0], 0))
		parts.append("%s %d/%d" % [GameData.item_name(str(need[0])), got, int(need[1])])
	var needs_label: Label = _label(" · ".join(parts), 24, OK if CraftingRules.can_make(r, bag) else WARN)
	needs_label.name = "Needs"
	info.add_child(needs_label)
	var item_info: ItemInfo = GameData.item(r.out)
	if item_info != null and not item_info.description.is_empty():
		info.add_child(_label(item_info.description, 21, SOFT))
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	info.add_child(buttons)
	if locked:
		buttons.add_child(_label("%s 곁에서 만들어요" % ["", "작업대", "공구 창고(공용 작업대)"][r.tier], 24, WARN))
		return card
	var make: Button = _button("만들기", 28)
	make.name = "Make_%s" % r.id
	make.disabled = not ok
	make.pressed.connect(func() -> void: _make(r, 1))
	buttons.add_child(make)
	var most: int = CraftingRules.max_batches(r, bag)
	if most >= 2:
		var many: Button = _button("%d번 만들기" % most, 28)
		many.name = "MakeMax_%s" % r.id
		many.pressed.connect(func() -> void: _make(r, most))
		buttons.add_child(many)
	return card


func _make(r: CraftingRules.Recipe, n: int) -> void:
	if _pending:
		return
	_pending = true
	Audio.play_sfx("chop", -8.0)
	Net.craft(r.id, n)


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
	b.custom_minimum_size = Vector2(120, 76)
	b.add_theme_font_size_override("font_size", size)
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	return b
