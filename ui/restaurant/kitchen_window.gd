class_name KitchenWindow
extends Control
## 식당 주방 창 (카운터에서 "주방"): 앉은 손님의 주문 목록 → 하나를 골라 요리 → 동작마다 박자 맞추기 → 서버가 별점을 매긴다.
##   썰기(beats): 똑딱 박자에 맞춰 "탁!"   끓이기·담기(timing): 눈금이 초록 칸에 왔을 때 "지금!"   섞기(mash): 시간 안에 마구 누르기
##   굽기(grill, v0.11): 팬 위 재료의 아랫면이 노릇해지면 "뒤집기!", 다른 면도 노릇해지면 "꺼내기!" (늦으면 탄다)
##   찌기(steam, v0.11): 재료를 하나씩 냄비에 담고 → 물을 꾹 눌러 선까지 붓고(떼면 뚜껑이 닫힘) → 김이 알맞게 오르면 "뚜껑 열기!"
## 누른 시각(동작 시작부터 ms)만 서버로 보내고, 솜씨·맛·시간·손님 MBTI 로 별점을 매기는 건 서버다.
## 요리하는 동안 캐릭터는 칼·팬·국자를 들고 그 동작을 한다.
## v9 같이 요리: 동작을 하나씩 맡아서(rest_cook) 한다 — 친구가 다른 동작을 맡고 있으면 그 동작은 건너뛰고 내 몫만 한다.
## 마지막 동작이 들어오면 서버가 판정해 같이 만든 사람 모두에게 결과를 준다 (팀 보너스 10%, 판정 창 15% 넓게).

signal closed

const BG: Color = Color(0.99, 0.96, 0.88, 0.97)
const EDGE: Color = Color(0.45, 0.32, 0.22)
const INK: Color = Color(0.32, 0.2, 0.12)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.75)
const GOOD: Color = Color("#5AAE5A")
const WARN: Color = Color("#E8604A")

enum Mode { ORDERS, COOKING, RESULT, MENU, WAITING }

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
## 찌기: 물을 붓는 중 (단추를 누르고 있음).
var _pouring: bool = false
var _sizzle_seed: int = 0


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
	Economy.step_claimed.connect(_on_step_claimed)
	Economy.step_done.connect(func(order_id: String, _step: int) -> void:
		if order_id == _order_id and _mode == Mode.RESULT:
			_next_step())
	Economy.served.connect(func(info: Dictionary) -> void:
		# 친구가 마지막 동작을 냈다 (내가 거든 요리면 내 결과는 cook_judged 로 따로 온다).
		if str(info.get("order", "")) == _order_id and _mode == Mode.WAITING:
			_back_to_orders())
	Economy.customer_left.connect(func(info: Dictionary) -> void:
		if str(info.get("order", "")) == _order_id and _mode in [Mode.COOKING, Mode.WAITING, Mode.RESULT]:
			_stop_cooking_pose()
			_back_to_orders()
			_list.add_child(_label("손님이 떠났어요…", 30, WARN)))
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
	var staff: int = Array(Economy.rest.get("staff", [])).size()
	_header.text = "%s ★%.1f · %d단계 · 오늘 %d그릇 %s%s" % [str(GameData.econ.restaurant.get("name", "식당")), rating, int(Economy.rest.get("tier", 1)), int(shift.get("served", 0)), Money.short(int(shift.get("revenue", 0))),
		" · 직원 %d명 팀 보너스!" % staff if Economy.is_team() else ""]
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
	_list.add_child(_label("직원 가방 재료로 %d그릇쯤 더 만들 수 있어요. 손님은 재료가 있는 요리만 주문해요 (주문이 들어오면 재료를 떼어 둬요)." % capacity, 24, SOFT))
	if not Economy.is_team():
		_list.add_child(_label("친구가 카운터에서 '같이 일하기'를 하면 재료를 합치고, 요리 동작을 나눠 동시에 해요 (손님이 더 기다려 주고 팀 보너스 +10%).", 22, SOFT))
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
	var shut: Button = _button("문 닫기" if Economy.is_rest_owner() else "일 그만하기", 28)
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
	var bar: MeterBar = MeterBar.make(20.0, 1.0, GOOD)
	bar.name = "Patience"
	bar.set_meta("order", str(o.get("id", "")))
	info.add_child(bar)
	# 동작마다 누가 맡았는지: ✓ 끝 · 이름 맡는 중 · 빈칸.
	var chips: PackedStringArray = []
	var st_list: Array = o.get("steps", [])
	for i: int in st_list.size():
		var st: Array = st_list[i]
		var label: String = str(GameData.econ.step(recipe.steps[i] if recipe != null and i < recipe.steps.size() else "").get("label", "?"))
		var by: int = int(st[0])
		if int(st[1]) == 1:
			chips.append("%s ✓" % label)
		elif by > 0:
			chips.append("%s(%s)" % [label, "나" if by == Net.my_id else GameData.player_name(by)])
		else:
			chips.append(label)
	if not chips.is_empty():
		info.add_child(_label(" → ".join(chips), 22, SOFT))
	var cook: Button = _button("요리하기" if Economy.free_step(str(o.get("id", ""))) >= 0 else "동료가 하는 중", 30)
	cook.disabled = Economy.free_step(str(o.get("id", ""))) < 0
	cook.custom_minimum_size = Vector2(200, 110)
	cook.pressed.connect(_start_cooking.bind(str(o.get("id", ""))))
	row.add_child(cook)
	return panel


func _update_patience() -> void:
	for bar: Node in _list.find_children("Patience", "MeterBar", true, false):
		var pb: MeterBar = bar as MeterBar
		var o: Dictionary = Economy.orders.get(str(pb.get_meta("order", "")), {})
		if o.is_empty():
			continue
		var ratio: float = Economy.order_left_ms(o) / maxf(float(o.get("patience", 1.0)), 1.0)
		pb.ratio = ratio
		pb.fill_color = GOOD.lerp(WARN, 1.0 - ratio)


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
	if player != null:
		player.set_input_lock(&"cooking", true)
		player.look_toward(site.counter_facing() if site != null else Vector3.BACK)
	if site != null:
		site.set_steaming(true)
	_start_cooking_view()
	_next_step()


## 요리 화면 (제목 · 안내 · 그림 · 큰 단추).
func _start_cooking_view() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("%s 만들기" % _recipe.display_name, 36, INK))
	_prompt = _label("", 32, INK)
	_list.add_child(_prompt)
	var gauge: Control = Control.new()
	gauge.custom_minimum_size = Vector2(0, 150)
	# 앞 요리 화면의 (지워지는 중인) 그림판이 새 그림판에 그리지 않게 한다.
	gauge.draw.connect(func() -> void:
		if gauge == _gauge:
			_draw_gauge())
	_gauge = gauge
	_list.add_child(_gauge)
	_tap_button = _button("탁!", 48)
	_tap_button.custom_minimum_size = Vector2(0, 200)
	_tap_button.button_down.connect(_on_tap)
	_tap_button.button_up.connect(_on_release)
	_list.add_child(_tap_button)


## 아직 아무도 안 맡은 다음 동작을 맡는다. 없으면 친구가 마무리하기를 기다린다.
func _next_step() -> void:
	if _recipe == null:
		return
	var free: int = Economy.free_step(_order_id)
	if free < 0:
		_wait_for_partner()
		return
	_mode = Mode.RESULT
	_step = {}
	_prompt.text = "다음 동작 맡는 중…"
	Economy.claim_step(_order_id, free)


func _on_step_claimed(order_id: String, step: int) -> void:
	if order_id != _order_id or _recipe == null:
		return
	_mode = Mode.COOKING
	_begin_step(step)


## 내 몫은 다 했고 친구가 남은 동작을 하는 중.
func _wait_for_partner() -> void:
	_mode = Mode.WAITING
	_stop_cooking_pose()
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("내 몫은 끝! 동료가 남은 동작을 마무리하는 중…", 30, INK))
	_gauge = null


func _back_to_orders() -> void:
	_mode = Mode.ORDERS
	_order_id = ""
	_rebuild()


func _begin_step(i: int) -> void:
	if _recipe == null or i >= _recipe.steps.size():
		return
	_step_index = i
	_step = GameData.econ.step(_recipe.steps[i])
	_step_taps = []
	_pouring = false
	_sizzle_seed = randi()
	_step_start_ms = float(Time.get_ticks_msec()) + 350.0
	if _gauge != null:
		_gauge.custom_minimum_size = Vector2(0, 340 if str(_step.get("kind", "")) in ["grill", "steam"] else 150)
	match str(_step.get("kind", "")):
		"beats":
			_step_end_ms = _step_start_ms + float(int(_step.get("beats", 4)) + 1) * float(_step.get("interval_ms", 480))
		"timing":
			_step_end_ms = _step_start_ms + float(_step.get("ideal_ms", 2000)) + float(_step.get("window_ms", 300)) * 3.0
		"grill":
			_step_end_ms = _step_start_ms + float(_step.get("sides", 2)) * float(_step.get("side_ms", 2000)) * 1.9
		"steam":
			_step_end_ms = _step_start_ms + 3000.0 + float(_step.get("fill_ms", 1600)) * 2.5 + float(_step.get("steam_ms", 2600)) * 2.0
		_:
			_step_end_ms = _step_start_ms + float(_step.get("duration_ms", 2600))
	var tool_id: String = str(_step.get("tool", ""))
	if player != null and player.rig != null:
		player.rig.set_cooking(str(_step.get("anim", "")), tool_id)
	_tap_button.text = _button_text()
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
		"grill":
			var sides: int = int(_step.get("sides", 2))
			_prompt.text = "%s — 다 구웠어요!" % label if _step_taps.size() >= sides else "%s — %d번째 면: 아랫면이 노릇해지면 %s" % [label, _step_taps.size() + 1, "꺼내요" if _step_taps.size() == sides - 1 else "뒤집어요"]
		"steam":
			_prompt.text = "%s — %s" % [label, _steam_hint()]
		_:
			_prompt.text = "%s — 마구 눌러요! (%d/%d)" % [label, _step_taps.size(), int(_step.get("taps", 10))]
	if t < 0.0:
		_prompt.text = "준비… " + label
	# 타이밍 동작은 누른 뒤 조금 있다가 넘어간다 (너무 빨리 낸 요리는 서버가 받지 않는다).
	var done: bool = now >= _step_end_ms
	if kind == "grill" and _step_taps.size() >= int(_step.get("sides", 2)):
		done = now >= _step_start_ms + _step_taps[-1] + 450.0
	elif kind == "steam" and _step_taps.size() >= int(_step.get("items", 3)) + 3:
		done = now >= _step_start_ms + _step_taps[-1] + 600.0
	if done and _pouring:
		_on_release()
	if kind == "timing" and not _step_taps.is_empty():
		var earliest: float = _step_start_ms + float(_step.get("ideal_ms", 2000)) - float(_step.get("window_ms", 300)) * 1.5
		done = done or now >= maxf(_step_start_ms + _step_taps[0] + 350.0, earliest)
	if done:
		_finish_step()


func _on_tap() -> void:
	if _mode != Mode.COOKING:
		return
	var t: float = float(Time.get_ticks_msec()) - _step_start_ms
	if t < 0.0:
		return
	var kind: String = str(_step.get("kind", ""))
	if kind == "timing" and not _step_taps.is_empty():
		return
	if kind == "grill":
		if _step_taps.size() >= int(_step.get("sides", 2)):
			return
		_step_taps.append(roundf(t))
		Audio.play_sfx("cook_sizzle", -4.0, 1.15, 0.1)
		_tap_button.text = _button_text()
		return
	if kind == "steam":
		var n: int = int(_step.get("items", 3))
		if _pouring or _step_taps.size() == n + 1 or _step_taps.size() >= n + 3:
			return
		_step_taps.append(roundf(t))
		if _step_taps.size() == n + 1:
			_pouring = true
			Audio.play_sfx("cook_bubble", -8.0, 1.4)
		elif _step_taps.size() == n + 3:
			Audio.play_sfx("cook_bubble", -2.0, 0.8)
		else:
			Audio.play_sfx("cook_plate", -8.0, 1.3, 0.1)
		_tap_button.text = _button_text()
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


## 단추를 뗐다: 찌기에서 물 붓기를 멈추면 뚜껑이 닫히고 김이 오르기 시작한다.
func _on_release() -> void:
	if not _pouring or _mode != Mode.COOKING:
		return
	_pouring = false
	_step_taps.append(roundf(maxf(float(Time.get_ticks_msec()) - _step_start_ms, _step_taps[-1] + 1.0)))
	Audio.play_sfx("cook_plate", -6.0, 0.7)
	_tap_button.text = _button_text()


func _button_text() -> String:
	match str(_step.get("kind", "")):
		"beats":
			return "탁!"
		"timing":
			return "지금!"
		"grill":
			return "꺼내기!" if _step_taps.size() >= int(_step.get("sides", 2)) - 1 else "뒤집기!"
		"steam":
			var n: int = int(_step.get("items", 3))
			if _step_taps.size() < n:
				return "재료 넣기 (%d/%d)" % [_step_taps.size() + 1, n]
			if _step_taps.size() == n + 1:
				return "붓는 중… 선에서 떼요"
			if _step_taps.size() == n:
				return "물 붓기 (꾹 눌러요)"
			return "뚜껑 열기!"
	return "섞기!"


func _steam_hint() -> String:
	var n: int = int(_step.get("items", 3))
	if _step_taps.size() < n:
		return "재료를 냄비에 하나씩 담아요"
	if _step_taps.size() == n:
		return "단추를 꾹 눌러 물을 붓고, 선에 닿으면 떼요"
	if _pouring:
		return "조금만 더… 선에서 떼요!"
	if _step_taps.size() == n + 2:
		return "뚜껑을 덮고 찌는 중 — 김이 초록 칸에 오면 열어요"
	return "다 쪘어요!"


## 지금 하면 딱 좋은 입력 (시연·테스트용): {"at": 동작 시작부터 ms, "release": 뗄 차례인가}. 할 게 없으면 at = INF.
func next_ideal_input() -> Dictionary:
	var taps: Array[float] = _step_taps
	match str(_step.get("kind", "")):
		"grill":
			if taps.size() < int(_step.get("sides", 2)):
				return {"at": (taps[-1] if not taps.is_empty() else 0.0) + float(_step.get("side_ms", 2000)), "release": false}
		"steam":
			var n: int = int(_step.get("items", 3))
			if taps.size() < n:
				return {"at": 150.0 * (taps.size() + 1), "release": false}
			if taps.size() == n:
				return {"at": taps[-1] + 200.0, "release": false}
			if taps.size() == n + 1:
				return {"at": taps[-1] + float(_step.get("fill_ms", 1600)), "release": true}
			if taps.size() == n + 2:
				return {"at": taps[-1] + float(_step.get("steam_ms", 2600)), "release": false}
	return {"at": INF, "release": false}


## 굽기 장면: 팬, 재료(윗면 = 앞서 구운 면, 아래 테두리 = 지금 굽는 면), 익힘 막대(노릇한 칸), 지글지글·탄 연기.
func _draw_grill(area: Rect2, t: float) -> void:
	var side_ms: float = float(_step.get("side_ms", 2000))
	var window: float = float(_step.get("window_ms", 300))
	var sides: int = int(_step.get("sides", 2))
	var flips: int = _step_taps.size()
	var since: float = t - (_step_taps[-1] if flips > 0 else 0.0)
	var cooking: bool = flips < sides and t >= 0.0
	var doneness: float = since / side_ms if cooking else 0.0
	var center: Vector2 = Vector2(area.position.x + area.size.x * 0.42, area.position.y + 120.0)
	# 팬 (손잡이 + 테두리 + 바닥)
	_gauge.draw_line(center + Vector2(150.0, 0.0), center + Vector2(300.0, 20.0), Color(0.25, 0.18, 0.12), 22.0)
	_draw_ellipse(center, Vector2(160.0, 92.0), Color(0.18, 0.18, 0.2))
	_draw_ellipse(center + Vector2(0.0, -4.0), Vector2(146.0, 80.0), Color(0.3, 0.3, 0.33))
	# 재료: 뒤집는 순간 납작해졌다가 돌아온다.
	var flip_t: float = clampf(since / 220.0, 0.0, 1.0) if flips > 0 else 1.0
	var squash: float = absf(cos(flip_t * PI)) * 0.85 + 0.15 if flip_t < 1.0 else 1.0
	var top_color: Color = _doneness_color(1.0 if flips > 0 else 0.0, window / side_ms) if flips < sides else _doneness_color(1.0, 0.1)
	var under_color: Color = _doneness_color(doneness, window / side_ms)
	var lift: float = -sin(flip_t * PI) * 40.0 if flip_t < 1.0 else 0.0
	var food: Vector2 = center + Vector2(0.0, -8.0 + lift)
	_draw_ellipse(food + Vector2(0.0, 8.0), Vector2(96.0, 40.0 * squash), under_color)
	_draw_ellipse(food, Vector2(92.0, 36.0 * squash), top_color)
	_draw_ellipse(food + Vector2(-20.0, -10.0 * squash), Vector2(30.0, 8.0 * squash), Color(1.0, 1.0, 1.0, 0.25))
	# 지글지글 (익는 중) · 탄 연기 (너무 오래)
	if cooking:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = _sizzle_seed
		for i: int in 10:
			var phase: float = fmod(t / 600.0 + rng.randf(), 1.0)
			var x: float = center.x + rng.randf_range(-120.0, 120.0)
			var col: Color = Color(1, 1, 1, 0.6 * (1.0 - phase)) if doneness < 1.0 + 2.0 * window / side_ms else Color(0.3, 0.3, 0.3, 0.7 * (1.0 - phase))
			_gauge.draw_circle(Vector2(x, center.y - 30.0 - phase * 90.0), 4.0 + phase * (6.0 if col.r < 0.5 else 2.0), col)
	# 익힘 막대: 0 ~ 2배 시간, 노릇한 칸(초록)
	var bar: Rect2 = Rect2(Vector2(area.position.x + 20.0, area.end.y - 64.0), Vector2(area.size.x - 40.0, 36.0))
	_gauge.draw_rect(bar, Color(0.92, 0.86, 0.74), true)
	var to_x: Callable = func(r: float) -> float: return bar.position.x + bar.size.x * clampf(r / 2.0, 0.0, 1.0)
	var z0: float = to_x.call(1.0 - window / side_ms)
	var z1: float = to_x.call(1.0 + window / side_ms)
	_gauge.draw_rect(Rect2(z0, bar.position.y, z1 - z0, bar.size.y), Color(GOOD, 0.6), true)
	_gauge.draw_rect(Rect2(to_x.call(1.0 + 2.0 * window / side_ms), bar.position.y, bar.end.x - to_x.call(1.0 + 2.0 * window / side_ms), bar.size.y), Color(0.35, 0.2, 0.12, 0.45), true)
	if cooking:
		var cx: float = to_x.call(doneness)
		_gauge.draw_line(Vector2(cx, bar.position.y - 10.0), Vector2(cx, bar.end.y + 10.0), INK, 5.0)
	_gauge.draw_string(_gauge.get_theme_default_font(), Vector2(bar.position.x, bar.end.y + 26.0), "날것", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, SOFT)
	_gauge.draw_string(_gauge.get_theme_default_font(), Vector2(z0, bar.end.y + 26.0), "노릇노릇", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GOOD.darkened(0.3))
	_gauge.draw_string(_gauge.get_theme_default_font(), Vector2(bar.end.x - 50.0, bar.end.y + 26.0), "탐", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, WARN)


## 날것(분홍빛) → 노릇(황금) → 탐(갈색·검정). r = 익힌 시간 / 알맞은 시간.
func _doneness_color(r: float, tolerance: float) -> Color:
	var raw: Color = Color(0.93, 0.8, 0.74)
	var golden: Color = Color(0.86, 0.6, 0.24)
	var burnt: Color = Color(0.25, 0.15, 0.1)
	if r <= 1.0:
		return raw.lerp(golden, clampf(r, 0.0, 1.0))
	return golden.lerp(burnt, clampf((r - 1.0) / maxf(tolerance * 3.0, 0.05), 0.0, 1.0))


## 찌기 장면: 냄비(물 선 표시), 담긴 재료, 붓는 물, 뚜껑, 오르는 김과 김 막대.
func _draw_steam(area: Rect2, t: float) -> void:
	var n: int = int(_step.get("items", 3))
	var fill_ms: float = float(_step.get("fill_ms", 1600))
	var steam_ms: float = float(_step.get("steam_ms", 2600))
	var window: float = float(_step.get("window_ms", 300))
	var taps: Array[float] = _step_taps
	var pot: Rect2 = Rect2(Vector2(area.position.x + area.size.x * 0.5 - 150.0, area.position.y + 70.0), Vector2(300.0, 170.0))
	# 물 높이: 1.0 = 선 (냄비 높이의 70%)
	var level: float = 0.0
	if taps.size() == n + 1:
		level = (t - taps[n]) / fill_ms
	elif taps.size() >= n + 2:
		level = (taps[n + 1] - taps[n]) / fill_ms
	var line_y: float = pot.end.y - pot.size.y * 0.7
	var water_top: float = pot.end.y - pot.size.y * 0.7 * clampf(level, 0.0, 1.35)
	# 냄비 몸통 · 물 · 재료
	_gauge.draw_rect(pot, Color(0.55, 0.57, 0.6), true)
	_gauge.draw_rect(Rect2(pot.position + Vector2(10.0, 0.0), pot.size - Vector2(20.0, 10.0)), Color(0.82, 0.84, 0.86), true)
	if level > 0.0:
		_gauge.draw_rect(Rect2(Vector2(pot.position.x + 10.0, water_top), Vector2(pot.size.x - 20.0, pot.end.y - 10.0 - water_top)), Color(0.45, 0.7, 0.95, 0.7), true)
	var colors: Array[Color] = []
	if _recipe != null:
		for ing: Dictionary in _recipe.ingredients:
			var info: ItemInfo = GameData.item(str(ing.get("item", (ing.get("item_any", [""]) as Array)[0] if ing.has("item_any") else "")))
			colors.append(info.color if info != null else Color(0.95, 0.85, 0.5))
	if colors.is_empty():
		colors = [Color(0.95, 0.85, 0.5)]
	for i: int in mini(taps.size(), n):
		var drop: float = clampf((t - taps[i]) / 250.0, 0.0, 1.0)
		var x: float = pot.position.x + 50.0 + (pot.size.x - 100.0) * (float(i) / maxf(n - 1, 1))
		var y: float = lerpf(pot.position.y - 60.0, pot.end.y - 40.0, drop * drop)
		_gauge.draw_circle(Vector2(x, y), 26.0, colors[i % colors.size()])
		_gauge.draw_circle(Vector2(x - 8.0, y - 8.0), 7.0, Color(1, 1, 1, 0.35))
	# 물 선 (점선)
	var dash: float = pot.position.x + 4.0
	while dash < pot.end.x - 4.0:
		_gauge.draw_line(Vector2(dash, line_y), Vector2(minf(dash + 14.0, pot.end.x - 4.0), line_y), Color(0.15, 0.35, 0.75), 4.0)
		dash += 24.0
	_gauge.draw_string(_gauge.get_theme_default_font(), Vector2(pot.end.x + 10.0, line_y + 8.0), "물 선", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.15, 0.35, 0.75))
	# 붓는 물줄기
	if _pouring:
		_gauge.draw_rect(Rect2(Vector2(pot.position.x + 60.0, pot.position.y - 70.0), Vector2(14.0, water_top - pot.position.y + 70.0)), Color(0.45, 0.7, 0.95, 0.8), true)
	# 뚜껑: 물을 다 붓고 나면 덮이고, 열면 옆으로 비킨다.
	var lid_on: bool = taps.size() == n + 2
	var lid_x: float = pot.position.x - 10.0 + (180.0 if taps.size() >= n + 3 else 0.0)
	if taps.size() >= n + 2:
		var lid: Rect2 = Rect2(Vector2(lid_x, pot.position.y - 22.0 - (30.0 if not lid_on else 0.0)), Vector2(pot.size.x + 20.0, 22.0))
		_gauge.draw_rect(lid, Color(0.4, 0.42, 0.46), true)
		_gauge.draw_rect(Rect2(lid.get_center() - Vector2(20.0, 22.0), Vector2(40.0, 12.0)), Color(0.25, 0.25, 0.28), true)
	# 김: 덮고 찌는 동안 점점 많이, 너무 오래면 뿌옇게
	var steamed: float = 0.0
	if lid_on:
		steamed = (t - taps[n + 1]) / steam_ms
		for i: int in int(4 + steamed * 8.0):
			var ph: float = fmod(t / 900.0 + i * 0.17, 1.0)
			var sx: float = pot.position.x + fmod(i * 73.0, pot.size.x)
			_gauge.draw_circle(Vector2(sx, pot.position.y - 30.0 - ph * 60.0), 6.0 + ph * 12.0, Color(1, 1, 1, 0.55 * (1.0 - ph)))
	elif taps.size() >= n + 3:
		var ph2: float = clampf((t - taps[n + 2]) / 600.0, 0.0, 1.0)
		_gauge.draw_circle(pot.get_center() - Vector2(0.0, 110.0 + ph2 * 30.0), 40.0 + ph2 * 30.0, Color(1, 1, 1, 0.6 * (1.0 - ph2)))
	# 김 막대 (뚜껑을 덮은 뒤)
	if taps.size() >= n + 2:
		var bar: Rect2 = Rect2(Vector2(area.position.x + 20.0, area.end.y - 52.0), Vector2(area.size.x - 40.0, 30.0))
		_gauge.draw_rect(bar, Color(0.92, 0.86, 0.74), true)
		var to_x: Callable = func(ms: float) -> float: return bar.position.x + bar.size.x * clampf(ms / (steam_ms * 2.0), 0.0, 1.0)
		var z0: float = to_x.call(steam_ms - window)
		_gauge.draw_rect(Rect2(z0, bar.position.y, to_x.call(steam_ms + window) - z0, bar.size.y), Color(GOOD, 0.6), true)
		var cur: float = (t - taps[n + 1]) if lid_on else (taps[n + 2] - taps[n + 1])
		var cx: float = to_x.call(cur)
		_gauge.draw_line(Vector2(cx, bar.position.y - 10.0), Vector2(cx, bar.end.y + 10.0), INK, 5.0)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 32:
		var a: float = TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	_gauge.draw_colored_polygon(pts, color)


func _draw_gauge() -> void:
	var size: Vector2 = _gauge.size
	var kind0: String = str(_step.get("kind", ""))
	if kind0 in ["grill", "steam"]:
		var now_t: float = float(Time.get_ticks_msec()) - _step_start_ms
		_gauge.draw_rect(Rect2(Vector2.ZERO, size), Color(0.96, 0.92, 0.84), true)
		if kind0 == "grill":
			_draw_grill(Rect2(Vector2.ZERO, size), now_t)
		else:
			_draw_steam(Rect2(Vector2.ZERO, size), now_t)
		_gauge.draw_string(_gauge.get_theme_default_font(), Vector2(10.0, 30.0), "%d / %d" % [_step_index + 1, _recipe.steps.size() if _recipe != null else 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, SOFT)
		return
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


## 맡은 동작을 끝냈다: 서버로 보내고 (rest_stepped → 다음 동작, 마지막이면 rest_result) 기다린다.
func _finish_step() -> void:
	_mode = Mode.RESULT
	_taps.append(_step_taps.duplicate())
	Economy.finish_step(_order_id, _step_index, _step_taps.duplicate())
	if _prompt != null:
		_prompt.text = "좋아요! 다음은…"
	if Economy.free_step(_order_id) < 0 and _is_last_step():
		Audio.play_sfx("order_bell", -4.0)


## 이 동작이 남은 마지막 동작인지 (다른 동작은 다 끝났다).
func _is_last_step() -> bool:
	var o: Dictionary = Economy.orders.get(_order_id, {})
	var list: Array = o.get("steps", [])
	for i: int in list.size():
		if i != _step_index and int((list[i] as Array)[1]) == 0:
			return false
	return true


func _on_judged(result: Dictionary) -> void:
	if str(result.get("order", "")) != _order_id:
		return
	_stop_cooking_pose()
	var stars: int = int(result.get("stars", 0))
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("★".repeat(stars) + "☆".repeat(5 - stars), 72, Color("#E8A820")))
	var team: bool = bool(result.get("team", false))
	_list.add_child(_label("솜씨 %d%% · 입맛 %d%% · 받은 돈 %s%s" % [roundi(float(result.get("quality", 0.0)) * 100.0), roundi(float(result.get("taste", 0.0)) * 100.0),
		Money.delta(int(result.get("share", result.get("pay", 0)))), " (같이 만들어 팀 보너스, 나눠 받음)" if team else ""], 30, INK))
	Audio.play_sfx("cash_in", -2.0)
	_order_id = ""
	await get_tree().create_timer(1.6).timeout
	if visible and _mode in [Mode.RESULT, Mode.WAITING]:
		_back_to_orders()


func _on_failed(kind: String, code: String) -> void:
	if not visible:
		return
	if kind == "rest_cook" and code == NetProtocol.ERR_STEP_TAKEN and _mode == Mode.RESULT:
		# 그새 친구가 맡았다: 다른 동작을 찾는다 (식당 상태가 갱신되길 잠깐 기다린다).
		await get_tree().create_timer(0.25).timeout
		_next_step()
		return
	if kind in ["rest_step", "rest_cook"]:
		_stop_cooking_pose()
		_back_to_orders()
		var msg: String = {"cook_too_fast": "너무 서둘렀어요!", "order_gone": "손님이 떠났어요…", "missing_ingredient": "떼어 둔 재료가 가방에 없어요!", "step_taken": "친구가 이미 맡은 동작이에요."}.get(code, code)
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
