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
var _stage: CookStage = null
var _steps_label: Label = null
var _prompt: Label = null
var _tap_button: Button = null
var _result: Dictionary = {}
## 찌기: 물을 붓는 중 (단추를 누르고 있음).
var _pouring: bool = false
## 동작 번호 → 내가 한 솜씨 (0~1, 화면용).
var _step_scores: Dictionary[int, float] = {}
var _finish_ms: float = 0.0
var _beat_ticked: int = 0

const ORDER_HEIGHT: float = 820.0
const COOK_HEIGHT: float = 1260.0
## 동작을 마치고 솜씨 한마디를 보여 주는 시간 (ms).
const FINISH_SHOW_MS: float = 800.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 24))
	_panel.add_to_group(&"blocks_joystick")
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	HudLayout.center_bottom(_panel, 1032.0, ORDER_HEIGHT, 24.0)
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
	Economy.step_done.connect(_on_step_done)
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
	_stage = null
	_set_panel_height(ORDER_HEIGHT)
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
		var in_time: bool = r.on_menu(Net.season(), Net.game_hour())
		var can: bool = open_tier and in_time and r.can_make(pantry)
		var steps: PackedStringArray = []
		for s: String in r.steps:
			steps.append(str(GameData.econ.step(s).get("label", s)))
		var when: String = r.when_text()
		var mark: String = "●" if can else ("잠김" if not open_tier else ("쉬는 중" if not in_time else "○"))
		var text: String = "%s %s · %s%s\n  %s\n  %s" % [mark, r.display_name, Money.short(r.price), "  [%s]" % when if not when.is_empty() else "", r.ingredients_text(), " → ".join(steps)]
		var l: Label = _label("%d단계  %s" % [r.tier, text], 24, INK if open_tier and in_time else SOFT)
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
	_step_scores.clear()
	_mode = Mode.COOKING
	if player != null:
		player.set_input_lock(&"cooking", true)
		player.look_toward(site.counter_facing() if site != null else Vector3.BACK)
	if site != null:
		site.set_steaming(true)
	_set_panel_height(COOK_HEIGHT)
	_start_cooking_view()
	_next_step()


func _set_panel_height(h: float) -> void:
	HudLayout.center_bottom(_panel, 1032.0, h, 24.0)


## 요리 화면: 요리 그림 · 이름 · 동작 순서, 조리 무대(누를 수도 있다), 안내, 큰 단추.
func _start_cooking_view() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_list.add_child(top)
	var icon: TextureRect = TextureRect.new()
	icon.texture = DishArt.icon(_recipe.id)
	icon.custom_minimum_size = Vector2(92, 92)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon)
	var names: VBoxContainer = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	names.add_child(_label("%s 만들기" % _recipe.display_name, 34, INK))
	_steps_label = _label("", 24, SOFT)
	names.add_child(_steps_label)
	var stage: CookStage = CookStage.new()
	stage.custom_minimum_size = Vector2(0, 640)
	stage.pressed.connect(func(down: bool) -> void:
		if down:
			_on_tap()
		else:
			_on_release())
	_stage = stage
	_list.add_child(_stage)
	_prompt = _label("", 30, INK)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(_prompt)
	_tap_button = _button("탁!", 48)
	_tap_button.custom_minimum_size = Vector2(0, 170)
	_tap_button.button_down.connect(_on_tap)
	_tap_button.button_up.connect(_on_release)
	_list.add_child(_tap_button)


## 동작 순서 글: 끝낸 것 ✓(솜씨), 지금 하는 것 [ ].
func _update_steps_label() -> void:
	if _steps_label == null or _recipe == null:
		return
	var o: Dictionary = Economy.orders.get(_order_id, {})
	var states: Array = o.get("steps", [])
	var parts: PackedStringArray = []
	for i: int in _recipe.steps.size():
		var label: String = str(GameData.econ.step(_recipe.steps[i]).get("label", "?"))
		if _step_scores.has(i):
			parts.append("✓%s" % label)
		elif i == _step_index and _mode == Mode.COOKING:
			parts.append("[%s]" % label)
		elif i < states.size() and int((states[i] as Array)[1]) == 1:
			parts.append("✓%s" % label)
		else:
			parts.append(label)
	_steps_label.text = " → ".join(parts)


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
	_prompt.text = "다음 동작 준비 중…"
	Economy.claim_step(_order_id, free)


func _on_step_claimed(order_id: String, step: int) -> void:
	if order_id != _order_id or _recipe == null:
		return
	_mode = Mode.COOKING
	_begin_step(step)


## 동작 하나를 서버가 받았다: 솜씨 한마디를 잠깐 보여 준 뒤 다음 동작으로.
func _on_step_done(order_id: String, _step_i: int) -> void:
	if order_id != _order_id or _mode != Mode.RESULT:
		return
	await _finish_pause()
	if order_id == _order_id and _mode == Mode.RESULT:
		_next_step()


func _finish_pause() -> void:
	var wait_ms: float = FINISH_SHOW_MS - (float(Time.get_ticks_msec()) - _finish_ms)
	if wait_ms > 0.0:
		await get_tree().create_timer(wait_ms / 1000.0).timeout


## 내 몫은 다 했고 친구가 남은 동작을 하는 중.
func _wait_for_partner() -> void:
	_mode = Mode.WAITING
	_stop_cooking_pose()
	for c: Node in _list.get_children():
		c.queue_free()
	_list.add_child(_label("내 몫은 끝! 동료가 남은 동작을 마무리하는 중…", 30, INK))
	_stage = null


func _back_to_orders() -> void:
	_mode = Mode.ORDERS
	_order_id = ""
	_stage = null
	_set_panel_height(ORDER_HEIGHT)
	_rebuild()


## 요리 재료 중 이 동작에서 다룰 것: main(팬 · 석쇠 · 튀김 · 꼬치), chop(이번에 썰 것), pot(냄비 · 그릇 · 웍에 들어가는 것).
## 물고기는 주문 때 서버가 떼어 둔 바로 그 물고기(used)로 그린다.
func _subjects(index: int) -> Dictionary:
	var used: Dictionary = Economy.orders.get(_order_id, {}).get("used", {}) as Dictionary
	var ids: Array[String] = []
	for ing: Dictionary in _recipe.ingredients:
		if ing.has("item"):
			ids.append(str(ing["item"]))
			continue
		var pool: Array = ing.get("item_any", [])
		var pick: String = ""
		for u: Variant in used.keys():
			if (pool.is_empty() and GameData.fish.has(str(u))) or str(u) in pool:
				pick = str(u)
				break
		if pick.is_empty():
			pick = str(pool[0]) if not pool.is_empty() else ("crucian" if GameData.fish.has("crucian") else str(GameData.fish.keys()[0]))
		ids.append(pick)
	var protein: String = ""
	for id: String in ids:
		if not id in FoodArt.SEASONING and not id in FoodArt.VEG:
			protein = id
			break
	var main: String = protein
	if main.is_empty():
		for id: String in ids:
			if id in FoodArt.VEG:
				main = id
				break
	if main.is_empty() and not ids.is_empty():
		main = ids[0]
	var step_def: Dictionary = GameData.econ.step(_recipe.steps[index])
	if CookStage.scene_of(step_def) == "flip":
		if "flour" in ids and protein.is_empty():
			main = "jeon"
		elif "egg" in ids and protein.is_empty():
			main = "egg"
	var choppable: Array[String] = []
	if not protein.is_empty() and GameData.fish.has(protein) and _recipe.tags.has("fresh"):
		choppable.append(protein)
	for id: String in ids:
		if id in FoodArt.VEG and not id in choppable:
			choppable.append(id)
	if choppable.is_empty():
		choppable.append(main)
	var nth: int = 0
	for i: int in index:
		if CookStage.scene_of(GameData.econ.step(_recipe.steps[i])) == "chop":
			nth += 1
	var pot: Array[String] = []
	for id: String in ids:
		if not id in ["soy_sauce", "doenjang", "sesame_oil", "sugar", "flour", "butter"]:
			pot.append(id)
	return {"main": main, "chop": choppable[nth % choppable.size()], "pot": pot if not pot.is_empty() else ids}


func _begin_step(i: int) -> void:
	if _recipe == null or i >= _recipe.steps.size():
		return
	_step_index = i
	_step = GameData.econ.step(_recipe.steps[i])
	_step_taps = []
	_pouring = false
	_beat_ticked = 0
	_step_start_ms = float(Time.get_ticks_msec()) + 600.0
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
	if _stage != null:
		_stage.begin(_step, _recipe, _subjects(i), _step_taps, _step_start_ms)
	var tool_id: String = str(_step.get("tool", ""))
	if player != null and player.rig != null:
		player.rig.set_cooking(str(_step.get("anim", "")), tool_id)
	_tap_button.text = _button_text()
	_update_steps_label()
	match str(_step.get("anim", "")):
		"cook_stir", "cook_flip":
			Audio.play_sfx("cook_sizzle" if tool_id == "pan" else "cook_bubble", -6.0)
	Audio.play_sfx("ui_click", -10.0)


## 장면별 안내 (지금 무엇을 보고 언제 누르는지).
func _guide(t: float) -> String:
	var n: int = _step_taps.size()
	match _scene():
		"chop":
			return "동그라미가 과녁에 닿을 때 탁! 칼이 박자에 맞춰 내려와요"
		"season":
			return "박자에 맞춰 톡톡! 소금을 골고루 뿌려요"
		"skewer":
			return "박자에 맞춰 쏙! 꼬치에 하나씩 꿰어요"
		"wok":
			return "박자에 맞춰 웍을 휙! 잘 맞으면 불맛이 올라요"
		"grill":
			var sides: int = int(_step.get("sides", 2))
			if n >= sides:
				return "다 구웠어요!"
			return "아랫면 테두리가 노릇해지고 고소한 김이 오르면 %s" % ("꺼내요" if n == sides - 1 else "뒤집어요")
		"flip":
			return "거품이 송송, 가장자리가 노릇해지면 휙 뒤집어요" if n == 0 else "휙!"
		"boil":
			return "물이 팔팔 끓어오르면 재료를 넣어요 (늦으면 넘쳐요)" if n == 0 else "풍덩!"
		"simmer":
			return "국물이 졸임 선까지 내려오면 불을 꺼요" if n == 0 else "불을 껐어요"
		"fry":
			return "기포가 잦아들고 튀김옷이 황금빛이 되면 건져요" if n == 0 else "바삭!"
		"plate":
			return "쟁반이 한가운데 오면 접시를 내려놓아요" if n == 0 else "짠!"
		"knead":
			return "마구 눌러 매끈하게 반죽해요! (%d/%d)" % [n, int(_step.get("taps", 10))]
		"steam":
			return _steam_hint()
	return "마구 눌러 골고루 버무려요! (%d/%d)" % [n, int(_step.get("taps", 10))] if t >= 0.0 else ""


func _scene() -> String:
	return CookStage.scene_of(_step)


func _tick_step() -> void:
	var now: float = float(Time.get_ticks_msec())
	var t: float = now - _step_start_ms
	var kind: String = str(_step.get("kind", ""))
	var label: String = str(_step.get("label", ""))
	_prompt.text = "준비… %s" % label if t < 0.0 else "%s — %s" % [label, _guide(t)]
	# 박자 동작: 박자마다 똑딱 (칼 · 소금통이 내려오는 때).
	if kind == "beats" and t >= 0.0:
		var b: int = int(floor(t / float(_step.get("interval_ms", 480))))
		if b > _beat_ticked and b <= int(_step.get("beats", 4)):
			_beat_ticked = b
			Audio.play_sfx("ui_click", -18.0, 1.7, 0.0)
	# 타이밍 동작은 누른 뒤 조금 있다가 넘어간다 (너무 빨리 낸 요리는 서버가 받지 않는다).
	var done: bool = now >= _step_end_ms
	if kind == "grill" and _step_taps.size() >= int(_step.get("sides", 2)):
		done = now >= _step_start_ms + _step_taps[-1] + 700.0
	elif kind == "steam" and _step_taps.size() >= int(_step.get("items", 3)) + 3:
		done = now >= _step_start_ms + _step_taps[-1] + 600.0
	elif kind == "mash" and _step_taps.size() >= int(_step.get("taps", 10)) and t >= float(_step.get("duration_ms", 2600)) * 0.5:
		done = done or now >= _step_start_ms + _step_taps[-1] + 300.0
	if done and _pouring:
		_on_release()
	if kind == "timing" and not _step_taps.is_empty():
		var earliest: float = _step_start_ms + float(_step.get("ideal_ms", 2000)) - float(_step.get("window_ms", 300)) * 1.5
		done = done or now >= maxf(_step_start_ms + _step_taps[0] + 550.0, earliest)
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
		var prev: float = _step_taps[-1] if not _step_taps.is_empty() else 0.0
		_step_taps.append(roundf(t))
		Audio.play_sfx("cook_sizzle", -4.0, 1.15, 0.1)
		_judged(CookRules.grade(absf(t - prev - float(_step.get("side_ms", 2000))), float(_step.get("window_ms", 300))))
		_tap_button.text = _button_text()
		return
	if kind == "steam":
		var n: int = int(_step.get("items", 3))
		if _pouring or _step_taps.size() == n + 1 or _step_taps.size() >= n + 3:
			return
		_step_taps.append(roundf(t))
		if _step_taps.size() == n + 1:
			_pouring = true
			if _stage != null:
				_stage.pouring = true
			Audio.play_sfx("cook_bubble", -8.0, 1.4)
		elif _step_taps.size() == n + 3:
			Audio.play_sfx("cook_bubble", -2.0, 0.8)
			_judged(CookRules.grade(absf(t - _step_taps[n + 1] - float(_step.get("steam_ms", 2600))), float(_step.get("window_ms", 300))))
		else:
			Audio.play_sfx("fish_plop", -8.0, 1.3, 0.1)
		_tap_button.text = _button_text()
		return
	var grade: int = -1
	if kind == "beats":
		var b: int = CookRules.nearest_beat(_step, t)
		var again: bool = _step_taps.any(func(x: float) -> bool: return CookRules.nearest_beat(_step, x) == b)
		grade = CookRules.Grade.MISS if again or _step_taps.size() >= int(_step.get("beats", 4)) else CookRules.beat_grade(_step, t)
	elif kind == "timing":
		grade = CookRules.grade(absf(t - float(_step.get("ideal_ms", 2000))), float(_step.get("window_ms", 300)))
	_step_taps.append(roundf(t))
	match _scene():
		"chop":
			Audio.play_sfx("cook_chop", -2.0, 1.0, 0.12)
		"season":
			Audio.play_sfx("cook_plate", -12.0, 1.8, 0.15)
		"skewer":
			Audio.play_sfx("emote_pop", -8.0, 1.2, 0.15)
		"wok":
			Audio.play_sfx("cook_sizzle", -4.0, 1.3, 0.1)
		"flip":
			Audio.play_sfx("line_zip", -8.0, 1.6)
			Audio.play_sfx("cook_sizzle", -6.0, 1.2)
		"boil":
			Audio.play_sfx("fish_plop", -2.0, 0.8)
		"simmer":
			Audio.play_sfx("ui_confirm", -6.0, 0.8)
		"fry":
			Audio.play_sfx("cook_plate", -6.0, 0.8)
		"plate":
			Audio.play_sfx("cook_plate", -4.0)
		"knead":
			Audio.play_sfx("emote_pop", -12.0, 0.6, 0.2)
		_:
			Audio.play_sfx("dig", -12.0, 1.6, 0.2)
	_judged(grade)


## 누름 판정을 무대에 띄우고, 완벽하면 반짝 소리.
func _judged(grade: int) -> void:
	if _stage != null:
		_stage.on_input(grade)
	if grade == CookRules.Grade.PERFECT:
		Audio.play_sfx("twinkle", -10.0, 1.2, 0.05)


## 단추를 뗐다: 찌기에서 물 붓기를 멈추면 뚜껑이 닫히고 김이 오르기 시작한다.
func _on_release() -> void:
	if not _pouring or _mode != Mode.COOKING:
		return
	_pouring = false
	if _stage != null:
		_stage.pouring = false
	var n: int = int(_step.get("items", 3))
	_step_taps.append(roundf(maxf(float(Time.get_ticks_msec()) - _step_start_ms, _step_taps[-1] + 1.0)))
	Audio.play_sfx("cook_plate", -6.0, 0.7)
	_judged(CookRules.grade(absf((_step_taps[n + 1] - _step_taps[n]) / float(_step.get("fill_ms", 1600)) - 1.0), float(_step.get("water_window", 0.16))))
	_tap_button.text = _button_text()


const SCENE_BUTTON: Dictionary[String, String] = {"chop": "탁!", "season": "톡톡!", "skewer": "꿰기!", "wok": "휙!", "flip": "뒤집기!", "boil": "재료 넣기!",
	"simmer": "불 끄기!", "fry": "건지기!", "plate": "내려놓기!", "mix": "버무리기!", "knead": "주무르기!"}


func _button_text() -> String:
	match str(_step.get("kind", "")):
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
	return SCENE_BUTTON.get(_scene(), "탁!")


func _steam_hint() -> String:
	var n: int = int(_step.get("items", 3))
	if _step_taps.size() < n:
		return "재료를 냄비에 하나씩 담아요"
	if _step_taps.size() == n:
		return "단추를 꾹 눌러 물을 붓고, 선에 닿으면 떼요"
	if _pouring:
		return "조금만 더… 선에서 떼요!"
	if _step_taps.size() == n + 2:
		return "뚜껑을 덮고 찌는 중 — 김이 폴폴 오르면 열어요"
	return "다 쪘어요!"


## 지금 하면 딱 좋은 입력 (시연·테스트용): {"at": 동작 시작부터 ms, "release": 뗄 차례인가}. 할 게 없으면 at = INF.
func next_ideal_input() -> Dictionary:
	var taps: Array[float] = _step_taps
	match str(_step.get("kind", "")):
		"beats":
			if taps.size() < int(_step.get("beats", 4)):
				return {"at": float(_step.get("interval_ms", 480)) * (taps.size() + 1), "release": false}
		"timing":
			if taps.is_empty():
				return {"at": float(_step.get("ideal_ms", 2000)), "release": false}
		"mash":
			if taps.size() < int(_step.get("taps", 10)):
				return {"at": 60.0 + 120.0 * taps.size(), "release": false}
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


## 맡은 동작을 끝냈다: 솜씨 한마디를 띄우고 서버로 보낸다 (rest_stepped → 다음 동작, 마지막이면 rest_result).
func _finish_step() -> void:
	_mode = Mode.RESULT
	var q: float = CookRules.step_quality(_step, _step_taps)
	_step_scores[_step_index] = q
	_finish_ms = float(Time.get_ticks_msec())
	if _stage != null:
		_stage.finish(q)
	Audio.play_sfx("quest_done" if q >= 0.9 else ("ui_confirm" if q >= 0.45 else "emote_down"), -8.0)
	_taps.append(_step_taps.duplicate())
	Economy.finish_step(_order_id, _step_index, _step_taps.duplicate())
	if _prompt != null:
		_prompt.text = "%s — %s" % [str(_step.get("label", "")), CookRules.step_word(q)]
	_update_steps_label()
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
	var order_id: String = str(result.get("order", ""))
	if order_id != _order_id:
		return
	_stop_cooking_pose()
	if _stage != null:
		await _finish_pause()
		if order_id != _order_id:
			return
	_stage = null
	var stars: int = int(result.get("stars", 0))
	for c: Node in _list.get_children():
		c.queue_free()
	var icon: TextureRect = TextureRect.new()
	icon.texture = DishArt.icon(_recipe.id) if _recipe != null else null
	icon.custom_minimum_size = Vector2(0, 300)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_list.add_child(icon)
	var title: Label = _label("%s 완성!" % (_recipe.display_name if _recipe != null else "요리"), 40, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	var star_label: Label = _label("★".repeat(stars) + "☆".repeat(5 - stars), 72, Color("#E8A820"))
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(star_label)
	if _recipe != null and not _step_scores.is_empty():
		var parts: PackedStringArray = []
		for i: int in _recipe.steps.size():
			if _step_scores.has(i):
				parts.append("%s %s" % [str(GameData.econ.step(_recipe.steps[i]).get("label", "")), CookRules.step_word(float(_step_scores[i]))])
		var steps_label: Label = _label(" · ".join(parts), 26, SOFT)
		steps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(steps_label)
	var team: bool = bool(result.get("team", false))
	var money: Label = _label("솜씨 %d%% · 입맛 %d%% · 받은 돈 %s%s" % [roundi(float(result.get("quality", 0.0)) * 100.0), roundi(float(result.get("taste", 0.0)) * 100.0),
		Money.delta(int(result.get("share", result.get("pay", 0)))), " (같이 만들어 팀 보너스, 나눠 받음)" if team else ""], 30, INK)
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(money)
	Audio.play_sfx("cash_in", -2.0)
	if stars >= 5:
		Audio.play_sfx("fanfare_small", -6.0)
	_order_id = ""
	await get_tree().create_timer(2.2).timeout
	if visible and _mode in [Mode.RESULT, Mode.WAITING] and _order_id.is_empty():
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
