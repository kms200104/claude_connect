class_name KitchenWindow
extends Control
## 식당 주방 창 (카운터에서 "주방"): 앉은 손님의 주문 목록 → 하나를 골라 요리 → 동작마다 박자 맞추기 → 서버가 별점을 매긴다.
##   썰기(beats): 똑딱 박자에 맞춰 "탁!"   굽기·끓이기·담기(timing): 눈금이 초록 칸에 왔을 때 "지금!"   섞기(mash): 시간 안에 마구 누르기
## 누른 시각(동작 시작부터 ms)만 서버로 보내고, 솜씨·맛·시간·손님 MBTI 로 별점을 매기는 건 서버다.
## 요리하는 동안 캐릭터는 칼·팬·국자를 들고 그 동작을 한다.

signal closed

const BG: Color = Color(0.99, 0.96, 0.88, 0.97)
const EDGE: Color = Color(0.45, 0.32, 0.22)
const INK: Color = Color(0.32, 0.2, 0.12)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.75)
const GOOD: Color = Color("#5AAE5A")
const WARN: Color = Color("#E8604A")

enum Mode { ORDERS, COOKING, RESULT, MENU }

var player: Player = null
var site: RestaurantSite = null

var _mode: Mode = Mode.ORDERS
var _panel: PanelContainer = null
var _col: VBoxContainer = null
var _header: Label = null
var _list: VBoxContainer = null
var _dirty: bool = false
## 요리 중인 주문과 동작 진행.
var _order_id: String = ""
var _recipe: RecipeInfo = null
var _step_index: int = -1
var _step: Dictionary = {}
var _step_start_ms: float = 0.0
var _step_end_ms: float = 0.0
var _taps: Array = []
var _step_taps: Array[float] = []
var _gauge: Control = null
var _prompt: Label = null
var _tap_button: Button = null
var _result: Dictionary = {}


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 24))
	_panel.add_to_group(&"blocks_joystick")
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	HudLayout.center_bottom(_panel, 1032.0, 820.0, 24.0)
	add_child(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	_panel.add_child(_col)
	var top: HBoxContainer = HBoxContainer.new()
	_col.add_child(top)
	_header = _label("", 30, INK)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var close_button: Button = _button("닫기", 28)
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	Economy.restaurant_changed.connect(func() -> void: _dirty = true)
	Economy.cook_judged.connect(_on_judged)
	Economy.shift_closed.connect(func(_reason: String) -> void:
		if visible:
			close())
	Economy.failed.connect(_on_failed)
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _dirty = true)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_mode = Mode.ORDERS
	_rebuild()
	Audio.play_sfx("ui_open", -6.0)


func close() -> void:
	if not visible:
		return
	_stop_cooking_pose()
	visible = false
	_order_id = ""
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var rating: float = float(Economy.rest.get("rating", 2.0))
	var shift: Dictionary = Economy.rest.get("shift", {}) if Economy.rest.get("shift") is Dictionary else {}
	_header.text = "%s ★%.1f · %d단계 메뉴 · 오늘 %d그릇 %s" % [str(GameData.econ.restaurant.get("name", "식당")), rating, int(Economy.rest.get("tier", 1)), int(shift.get("served", 0)), Money.short(int(shift.get("revenue", 0)))]
	match _mode:
		Mode.ORDERS:
			if _dirty:
				_dirty = false
				_rebuild()
			_update_patience()
		Mode.COOKING:
			_tick_step()


# ---- 주문 목록 ----

func _rebuild() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	if _mode == Mode.MENU:
		_build_menu()
		return
	if _mode != Mode.ORDERS:
		return
	var capacity: int = int(Economy.rest.get("capacity", 0))
	_list.add_child(_label("가방 재료로 %d그릇쯤 더 만들 수 있어요. 손님은 재료가 있는 요리만 주문해요 (주문이 들어오면 재료를 떼어 둬요)." % capacity, 24, SOFT))
	if Economy.orders.is_empty():
		_list.add_child(_label("손님을 기다리는 중…" if capacity > 0 else "재료가 없어요! 상점에서 사거나 들판에서 채집해 오세요.", 30, INK))
	var ids: Array[String] = []
	for id: String in Economy.orders:
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return Economy.order_left_ms(Economy.orders[a]) < Economy.order_left_ms(Economy.orders[b]))
	for id: String in ids:
		_list.add_child(_order_card(Economy.orders[id]))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_list.add_child(row)
	var menu: Button = _button("메뉴판", 28)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func() -> void:
		_mode = Mode.MENU
		_rebuild())
	row.add_child(menu)
	var shut: Button = _button("문 닫기", 28)
	shut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shut.pressed.connect(Economy.close_restaurant)
	row.add_child(shut)


func _order_card(o: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(CARD, Color(0.8, 0.7, 0.58), 24, 3, 14))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var dish: String = str(o.get("dish", ""))
	var icon: TextureRect = TextureRect.new()
	icon.texture = DishArt.icon(dish)
	icon.custom_minimum_size = Vector2(110, 110)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var recipe: RecipeInfo = GameData.econ.recipes.get(dish)
	var customer: EconData.Customer = GameData.econ.customers.get(str(o.get("customer", "")))
	var who: String = customer.display_name if customer != null else "손님"
	var style: String = ""
	if customer != null and customer.mbti.length() == 4:
		style = " · %s %s" % [customer.mbti, "늦어도 너그러움" if customer.mbti[2] == "F" else "솜씨에 깐깐함"]
	info.add_child(_label("%s%s%s" % [who, "  ♥단골" if bool(o.get("regular", false)) else "", style], 26, SOFT))
	info.add_child(_label("%s · %s" % [recipe.display_name if recipe != null else dish, Money.short(recipe.price if recipe != null else 0)], 32, INK))
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "Patience"
	bar.set_meta("order", str(o.get("id", "")))
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 20)
	bar.add_theme_stylebox_override("background", EventHud._box(Color(0.85, 0.8, 0.72), Color(0.75, 0.66, 0.54), 10, 1, 0))
	bar.add_theme_stylebox_override("fill", EventHud._box(Color.WHITE, Color.WHITE, 10, 0, 0))
	info.add_child(bar)
	var cook: Button = _button("요리하기", 30)
	cook.custom_minimum_size = Vector2(200, 110)
	cook.pressed.connect(_start_cooking.bind(str(o.get("id", ""))))
	row.add_child(cook)
	return panel


func _update_patience() -> void:
	for bar: Node in _list.find_children("Patience", "ProgressBar", true, false):
		var pb: ProgressBar = bar as ProgressBar
		var o: Dictionary = Economy.orders.get(str(pb.get_meta("order", "")), {})
		if o.is_empty():
			continue
		var ratio: float = Economy.order_left_ms(o) / maxf(float(o.get("patience", 1.0)), 1.0)
		pb.value = ratio
		pb.modulate = GOOD.lerp(WARN, 1.0 - ratio)


func _build_menu() -> void:
	var tier: int = int(Economy.rest.get("tier", 1))
	var pantry: Dictionary = {}
	for it: InventoryItem in Net.inventory:
		if it != null:
			pantry[it.id] = int(pantry.get(it.id, 0)) + it.count
	_list.add_child(_label("별점이 오르면 까다롭지만 남는 게 많은 요리가 열려요. (단계 기준 ★ %s)" % ", ".join(PackedStringArray(GameData.econ.tier_stars().slice(1).map(func(x: Variant) -> String: return "%.1f" % float(x)))), 24, SOFT))
	for r: RecipeInfo in GameData.econ.recipe_order:
		var open_tier: bool = r.tier <= tier
		var can: bool = open_tier and r.can_make(pantry)
		var steps: PackedStringArray = []
		for s: String in r.steps:
			steps.append(str(GameData.econ.step(s).get("label", s)))
		var text: String = "%s %s · %s\n  %s\n  %s" % ["●" if can else ("○" if open_tier else "잠김"), r.display_name, Money.short(r.price), r.ingredients_text(), " → ".join(steps)]
		var l: Label = _label("%d단계  %s" % [r.tier, text], 24, INK if open_tier else SOFT)
		_list.add_child(l)
	var back: Button = _button("주문 보기", 28)
	back.pressed.connect(func() -> void:
		_mode = Mode.ORDERS
		_rebuild())
	_list.add_child(back)


# ---- 요리 ----

func _start_cooking(order_id: String) -> void:
	var o: Dictionary = Economy.orders.get(order_id, {})
	_recipe = GameData.econ.recipes.get(str(o.get("dish", "")))
	if _recipe == null:
		return
	_order_id = order_id
	_taps = []
	_mode = Mode.COOKING
	Economy.start_cooking(order_id)
	if player != null:
		player.set_input_lock(&"cooking", true)
		player.look_toward(site.counter_facing() if site != null else Vector3.BACK)
	if site != null:
		site.set_steaming(true)
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("%s 만들기" % _recipe.display_name, 36, INK))
	_prompt = _label("", 32, INK)
	_list.add_child(_prompt)
	_gauge = Control.new()
	_gauge.custom_minimum_size = Vector2(0, 150)
	_gauge.draw.connect(_draw_gauge)
	_list.add_child(_gauge)
	_tap_button = _button("탁!", 48)
	_tap_button.custom_minimum_size = Vector2(0, 200)
	_tap_button.button_down.connect(_on_tap)
	_list.add_child(_tap_button)
	_begin_step(0)


func _begin_step(i: int) -> void:
	if _recipe == null:
		return
	if i >= _recipe.steps.size():
		_finish()
		return
	_step_index = i
	_step = GameData.econ.step(_recipe.steps[i])
	_step_taps = []
	_step_start_ms = float(Time.get_ticks_msec()) + 350.0
	match str(_step.get("kind", "")):
		"beats":
			_step_end_ms = _step_start_ms + float(int(_step.get("beats", 4)) + 1) * float(_step.get("interval_ms", 480))
		"timing":
			_step_end_ms = _step_start_ms + float(_step.get("ideal_ms", 2000)) + float(_step.get("window_ms", 300)) * 3.0
		_:
			_step_end_ms = _step_start_ms + float(_step.get("duration_ms", 2600))
	var tool_id: String = str(_step.get("tool", ""))
	if player != null and player.rig != null:
		player.rig.set_cooking(str(_step.get("anim", "")), tool_id)
	_tap_button.text = {"beats": "탁!", "timing": "지금!", "mash": "섞기!"}.get(str(_step.get("kind", "")), "탁!")
	match str(_step.get("anim", "")):
		"cook_stir", "cook_flip":
			Audio.play_sfx("cook_sizzle" if tool_id == "pan" else "cook_bubble", -6.0)
	Audio.play_sfx("ui_click", -10.0)


func _tick_step() -> void:
	if _gauge != null:
		_gauge.queue_redraw()
	var now: float = float(Time.get_ticks_msec())
	var t: float = now - _step_start_ms
	var kind: String = str(_step.get("kind", ""))
	var label: String = str(_step.get("label", ""))
	match kind:
		"beats":
			_prompt.text = "%s — 박자에 맞춰 탁! (%d/%d)" % [label, _step_taps.size(), int(_step.get("beats", 4))]
			# 박자마다 칼 소리 (다음 박자 표시).
		"timing":
			_prompt.text = "%s — 눈금이 초록 칸에 오면 지금!" % label if _step_taps.is_empty() else "%s — 좋아요, 기다려요…" % label
		_:
			_prompt.text = "%s — 마구 눌러요! (%d/%d)" % [label, _step_taps.size(), int(_step.get("taps", 10))]
	if t < 0.0:
		_prompt.text = "준비… " + label
	# 타이밍 동작은 누른 뒤 조금 있다가 넘어간다 (너무 빨리 낸 요리는 서버가 받지 않는다).
	var done: bool = now >= _step_end_ms
	if kind == "timing" and not _step_taps.is_empty():
		var earliest: float = _step_start_ms + float(_step.get("ideal_ms", 2000)) - float(_step.get("window_ms", 300)) * 1.5
		done = done or now >= maxf(_step_start_ms + _step_taps[0] + 350.0, earliest)
	if done:
		_taps.append(_step_taps.duplicate())
		_begin_step(_step_index + 1)


func _on_tap() -> void:
	if _mode != Mode.COOKING:
		return
	var t: float = float(Time.get_ticks_msec()) - _step_start_ms
	if t < 0.0:
		return
	var kind: String = str(_step.get("kind", ""))
	if kind == "timing" and not _step_taps.is_empty():
		return
	_step_taps.append(roundf(t))
	match str(_step.get("anim", "")):
		"cook_chop":
			Audio.play_sfx("cook_chop", -2.0, 1.0, 0.12)
		"cook_plate":
			Audio.play_sfx("cook_plate", -4.0)
		"cook_mix":
			Audio.play_sfx("dig", -12.0, 1.6, 0.2)
		_:
			Audio.play_sfx("ui_click", -6.0, 1.2)


func _draw_gauge() -> void:
	var size: Vector2 = _gauge.size
	var r: Rect2 = Rect2(Vector2(10.0, 40.0), Vector2(size.x - 20.0, 70.0))
	_gauge.draw_rect(r, Color(0.92, 0.86, 0.74), true)
	var t: float = float(Time.get_ticks_msec()) - _step_start_ms
	var kind: String = str(_step.get("kind", ""))
	var total: float = _step_end_ms - _step_start_ms
	var to_x: Callable = func(ms: float) -> float: return r.position.x + r.size.x * clampf(ms / total, 0.0, 1.0)
	match kind:
		"beats":
			var interval: float = float(_step.get("interval_ms", 480))
			var window: float = float(_step.get("window_ms", 150))
			for i: int in range(1, int(_step.get("beats", 4)) + 1):
				var x: float = to_x.call(interval * i)
				var w: float = to_x.call(interval * i + window) - x
				_gauge.draw_rect(Rect2(x - w, r.position.y, w * 2.0, r.size.y), Color(GOOD, 0.45), true)
				_gauge.draw_line(Vector2(x, r.position.y - 8.0), Vector2(x, r.end.y + 8.0), Color(0.2, 0.5, 0.2), 3.0)
		"timing":
			var ideal: float = float(_step.get("ideal_ms", 2000))
			var window2: float = float(_step.get("window_ms", 300))
			var x0: float = to_x.call(ideal - window2)
			var x1: float = to_x.call(ideal + window2)
			_gauge.draw_rect(Rect2(x0, r.position.y, x1 - x0, r.size.y), Color(GOOD, 0.6), true)
			_gauge.draw_rect(Rect2(r.position, Vector2(to_x.call(minf(t, total)) - r.position.x, r.size.y)), Color(WARN, 0.35), true)
		_:
			var need: float = float(_step.get("taps", 10))
			_gauge.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(float(_step_taps.size()) / need, 0.0, 1.0), r.size.y)), Color(GOOD, 0.7), true)
	for tap: float in _step_taps:
		var tx: float = to_x.call(tap)
		_gauge.draw_circle(Vector2(tx, r.get_center().y), 10.0, Color(0.95, 0.75, 0.25))
	if t >= 0.0:
		var cx: float = to_x.call(t)
		_gauge.draw_line(Vector2(cx, r.position.y - 16.0), Vector2(cx, r.end.y + 16.0), INK, 5.0)
	_gauge.draw_string(_gauge.get_theme_default_font(), Vector2(10.0, 30.0), "%d / %d" % [_step_index + 1, _recipe.steps.size() if _recipe != null else 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, SOFT)


func _finish() -> void:
	_mode = Mode.RESULT
	_stop_cooking_pose()
	if player != null and player.rig != null:
		player.rig.set_cooking("cook_plate", "")
	Audio.play_sfx("order_bell", -4.0)
	Economy.serve(_order_id, _taps)
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("요리를 냈어요! 손님이 맛보는 중…", 32, INK))


func _on_judged(result: Dictionary) -> void:
	if str(result.get("order", "")) != _order_id:
		return
	_stop_cooking_pose()
	var stars: int = int(result.get("stars", 0))
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("★".repeat(stars) + "☆".repeat(5 - stars), 72, Color("#E8A820")))
	_list.add_child(_label("솜씨 %d%% · 입맛 %d%% · 받은 돈 %s" % [roundi(float(result.get("quality", 0.0)) * 100.0), roundi(float(result.get("taste", 0.0)) * 100.0), Money.delta(int(result.get("pay", 0)))], 30, INK))
	Audio.play_sfx("cash_in", -2.0)
	_order_id = ""
	await get_tree().create_timer(1.6).timeout
	if visible and _mode == Mode.RESULT:
		_mode = Mode.ORDERS
		_rebuild()


func _on_failed(kind: String, code: String) -> void:
	if not visible:
		return
	if kind == "rest_serve":
		_stop_cooking_pose()
		_mode = Mode.ORDERS
		_order_id = ""
		_rebuild()
		var msg: String = {"cook_too_fast": "너무 서둘렀어요!", "order_gone": "손님이 떠났어요…", "missing_ingredient": "떼어 둔 재료가 가방에 없어요!"}.get(code, code)
		_list.add_child(_label(msg, 30, WARN))


func _stop_cooking_pose() -> void:
	if player != null:
		player.set_input_lock(&"cooking", false)
		if player.rig != null:
			player.rig.set_cooking("")
		player.clear_look_direction()
	if site != null:
		site.set_steaming(false)


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
