extends Node
## 주방 장면 검증: 서버 없이 주방 창에 동작을 직접 띄우고, 딱 좋은 때에 누르면 서버 판정 규칙(CookRules)대로 완벽한 기록이 남는지 본다.
## 장면마다 (썰기 · 간하기 · 꼬치 · 웍 · 굽기 · 부치기 · 끓이기 · 졸이기 · 튀기기 · 담기 · 버무리기 · 반죽 · 찌기) 한 번씩.
## 사용: godot --path . res://tests/kitchen_check.tscn [-- --shots=폴더] [--only=장면,장면]

## [요리, 동작] — 장면마다 하나 (재료가 다르게 보이도록 고른다).
const CASES: Array = [
	["braised_fish", "chop"], ["trout_butter", "grill_hard"], ["samgyeopsal", "grill"], ["beef_steak", "season"], ["chicken_skewer", "skewer"],
	["bulgogi", "stir_fry"], ["mushroom_jeon", "fry_flip"], ["loach_soup", "boil"], ["braised_fish", "simmer"], ["fried_chicken", "deep_fry"],
	["herb_bibimbap", "mix_hard"], ["dumplings", "knead"], ["steamed_egg", "steam"], ["rice_ball", "plate"],
	["grilled_fish", "plate"], ["mushroom_skewer", "plate"], ["loach_soup", "plate"], ["fried_chicken", "plate"], ["bulgogi", "plate"], ["dumplings", "plate"],
]

var _failures: int = 0
var _shots: String = ""
var _only: PackedStringArray = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	var kitchen: KitchenWindow = KitchenWindow.new()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	layer.add_child(kitchen)
	await get_tree().process_frame
	kitchen.visible = true
	# 식당 일은 처음(주문 목록)부터 온 화면, 위에는 '중단하기' · '손님 그만 받기' 만.
	kitchen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var bar_panel: Control = kitchen.get("_panel")
	_check(bool(kitchen.get("_full")) and bar_panel.size.distance_to(get_viewport().get_visible_rect().size) < 2.0, "주문 목록부터 온 화면")
	var stop: Button = kitchen.find_child("StopButton", true, false) as Button
	var quit: Button = kitchen.find_child("QuitCustomersButton", true, false) as Button
	_check(stop != null and stop.is_visible_in_tree() and quit != null and quit.is_visible_in_tree(), "위에는 '중단하기' · '손님 그만 받기'")
	if _only.is_empty() or "tutorial" in _only:
		await _check_tutorial(kitchen)
	for c: Array in CASES:
		if not GameData.econ.recipes.has(str(c[0])):
			_check(false, "요리 %s 가 있다" % c[0])
			continue
		var scene: String = CookStage.scene_of(GameData.econ.step(str(c[1])))
		if not _only.is_empty() and not scene in _only:
			continue
		await _run(kitchen, str(c[0]), str(c[1]))
	if _only.is_empty() or "result" in _only:
		# 마을에서처럼 땅 휘기 기준점(내 캐릭터)이 원점에서 멀다 — 손님 얼굴 무대가 땅 밑으로 가라앉으면 안 된다.
		var far: Vector3 = Vector3(26.0, 0.0, 64.0)
		RenderingServer.global_shader_parameter_set("world_curve_origin", far)
		WorldStyle.curve_origin = far
		_check_reaction_lines()
		await _result(kitchen, "beef_steak", "v_gourmet", 5, 0.97, 0.8, false, false)
		await _result(kitchen, "samgyeopsal", "v_hiker", 2, 0.48, 0.1, false, false)
		await _result(kitchen, "rice_ball", "morak", 5, 0.95, 0.5, false, true)
	print("KITCHEN %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _run(kitchen: KitchenWindow, dish: String, step_id: String) -> void:
	kitchen.set("_recipe", GameData.econ.recipes.get(dish))
	kitchen.call("_set_panel_height", KitchenWindow.COOK_HEIGHT)
	kitchen.call("_start_cooking_view")
	var recipe: RecipeInfo = kitchen.get("_recipe")
	var index: int = recipe.steps.find(step_id)
	_check(index >= 0, "%s 에 %s 동작이 있다" % [dish, step_id])
	if index < 0:
		return
	kitchen.set("_mode", KitchenWindow.Mode.COOKING)
	kitchen.call("_begin_step", index)
	var step: Dictionary = kitchen.get("_step")
	var scene: String = CookStage.scene_of(step)
	var span: float = float(kitchen.get("_step_end_ms")) - float(kitchen.get("_step_start_ms"))
	var shot_at: Array[float] = [0.2, 0.5, 0.8]
	var shot_n: int = 0
	var t0: float = float(kitchen.get("_step_start_ms"))
	while kitchen.get("_mode") == KitchenWindow.Mode.COOKING and Time.get_ticks_msec() - t0 < 16000.0:
		var t: float = float(Time.get_ticks_msec()) - t0
		var ideal: Dictionary = kitchen.next_ideal_input()
		if t >= float(ideal["at"]):
			kitchen.call("_on_tap")
		if not _shots.is_empty() and not shot_at.is_empty() and t / span >= shot_at[0]:
			shot_at.pop_front()
			shot_n += 1
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shots.path_join("kitchen_%s_%s_%d.png" % [scene, dish, shot_n]))
		await get_tree().process_frame
	if not _shots.is_empty():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shots.path_join("kitchen_%s_%s_%d.png" % [scene, dish, shot_n + 1]))
	var taps: Array = (kitchen.get("_taps") as Array).back()
	var q: float = CookRules.step_quality(step, taps)
	print("[kitchen] %s (%s) taps=%s 솜씨 %.2f" % [step_id, scene, str(taps), q])
	_check(q >= 0.9, "%s · %s: 박자에 딱 맞춰 누르면 솜씨 %.2f ≥ 0.9" % [dish, scene, q])
	_check(taps.size() == CookRules.hits(step).size(), "%s: 박자마다 한 번씩 (%d)" % [scene, taps.size()])
	var stage: CookStage = kitchen.get("_stage")
	_check(stage != null and stage.counter != null and stage.counter.done == stage.counter.total, "%s: 조리대에서 동작을 다 했다 (%d/%d)" % [scene, stage.counter.done if stage != null else -1, stage.counter.total if stage != null else -1])


## 처음 하는 동작 설명 (v0.18): 카드가 뜨고, "시작!" 을 누르면 닫히며 알린다.
func _check_tutorial(kitchen: KitchenWindow) -> void:
	kitchen.set("_recipe", GameData.econ.recipes.get("samgyeopsal"))
	kitchen.call("_set_panel_height", KitchenWindow.COOK_HEIGHT)
	kitchen.call("_start_cooking_view")
	var stage: CookStage = kitchen.get("_stage")
	var step: Dictionary = GameData.econ.step("grill")
	stage.preview(step, kitchen.get("_recipe"), {"main": "pork_belly", "chop": "pork_belly", "pot": ["pork_belly"]})
	stage.show_tutorial(step)
	_check(stage.is_tutorial_open(), "처음 하는 동작: 설명 카드가 뜬다")
	var closed: Array[bool] = [false]
	stage.tutorial_closed.connect(func() -> void: closed[0] = true)
	await get_tree().create_timer(0.6).timeout
	if not _shots.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shots.path_join("kitchen_tutorial.png"))
	var go: Button = null
	var card: Control = stage.get("_tutorial")
	for b: Node in card.find_children("*", "Button", true, false):
		go = b as Button
	if go != null:
		# 실제 손가락처럼 단추 가운데를 눌렀다 뗀다 (신호를 직접 쏘면 입력이 막혀도 모른다).
		var at: Vector2 = go.get_global_rect().get_center()
		for down: bool in [true, false]:
			if not down:
				# 손가락은 누르는 동안 몇 px 흔들린다.
				var drag: InputEventScreenDrag = InputEventScreenDrag.new()
				drag.position = at + Vector2(0.0, -4.0)
				drag.relative = Vector2(0.0, -4.0)
				get_viewport().push_input(drag, true)
				var move: InputEventMouseMotion = InputEventMouseMotion.new()
				move.position = at + Vector2(0.0, -4.0)
				move.global_position = move.position
				move.relative = Vector2(0.0, -4.0)
				move.button_mask = MOUSE_BUTTON_MASK_LEFT
				get_viewport().push_input(move, true)
				await get_tree().process_frame
				at += Vector2(0.0, -4.0)
			var touch: InputEventScreenTouch = InputEventScreenTouch.new()
			touch.position = at
			touch.pressed = down
			get_viewport().push_input(touch, true)
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.position = at
			click.global_position = at
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = down
			get_viewport().push_input(click, true)
			await get_tree().process_frame
		await get_tree().process_frame
	_check(closed[0] and not stage.is_tutorial_open(), "\"시작!\" 을 누르면 설명이 닫히고 동작을 시작한다")
	# 큰 단추(탁!)를 눌러도 설명이 닫힌다.
	closed[0] = false
	stage.show_tutorial(step)
	kitchen.call("_on_tap")
	_check(closed[0] and not stage.is_tutorial_open(), "큰 단추를 눌러도 설명이 닫힌다")
	# 요리 중에는 주방 창이 화면 전체를 덮는다 (게임 HUD 위, 조리대가 대부분).
	await get_tree().process_frame
	var panel: Control = kitchen.get("_panel")
	var view: Vector2 = get_viewport().get_visible_rect().size
	_check(bool(kitchen.get("_full")) and panel.size.distance_to(view) < 2.0, "요리는 온 화면 (창 %s / 화면 %s)" % [str(panel.size), str(view)])
	_check(stage.size.y > view.y * 0.7, "조리대가 화면 대부분 (%.0f / %.0f)" % [stage.size.y, view.y])


## 손님 반응 글 (v20): 별점 첫마디 + 까닭 — 좋아하는 맛, T 손님의 깐깐한 솜씨 평, 늦은 요리.
func _check_reaction_lines() -> void:
	var r: Dictionary = GameData.econ.restaurant.get("reactions", {})
	var gourmet: EconData.Customer = GameData.econ.customers.get("v_gourmet")
	var hiker: EconData.Customer = GameData.econ.customers.get("v_hiker")
	var steak: RecipeInfo = GameData.econ.recipes.get("beef_steak")
	var good: PackedStringArray = GuestReaction.lines(gourmet, steak, 5, 0.97, 0.8, false, 1)
	print("[kitchen] 쉐린 5★: %s" % " / ".join(good))
	_check(good.size() >= 2 and good[1] == str(r["like"]).replace("{tag}", str(r["tag"]["fancy"])), "좋아하는 맛(고급)을 말한다")
	_check(not str(r["dislike"]).replace("{tag}", str(r["tag"]["hearty"])) in good, "5★ 에는 싫은 맛(든든) 투정이 없다")
	var bad: PackedStringArray = GuestReaction.lines(hiker, GameData.econ.recipes.get("samgyeopsal"), 2, 0.48, 0.1, false, 2)
	print("[kitchen] 하늘 2★: %s" % " / ".join(bad))
	_check(str(r["skill_bad_t"]) in bad and str(r["late_t"]) in bad, "T 손님: 서툰 솜씨 · 오래 기다림을 말한다")
	_check(GuestReaction.emote_for(1, false) == "angry" and GuestReaction.emote_for(5, false) == "clap" and GuestReaction.emote_for(3, true) == "love", "별점 → 감정표현")


## 결과 화면을 서버 없이 띄운다 (주문 · 판정을 흉내 내고 손님 반응을 찍는다).
func _result(kitchen: KitchenWindow, dish: String, customer: String, stars: int, quality: float, time_left: float, regular: bool, became: bool) -> void:
	var order_id: String = "check_%s" % dish
	var patience: float = 100000.0
	Economy.orders[order_id] = {"id": order_id, "customer": customer, "dish": dish, "patience": patience, "deadline_ms": float(Time.get_ticks_msec()) + patience * time_left, "regular": regular, "steps": [], "used": {}}
	var recipe: RecipeInfo = GameData.econ.recipes.get(dish)
	kitchen.set("_recipe", recipe)
	kitchen.call("_set_panel_height", KitchenWindow.COOK_HEIGHT)
	kitchen.set("_order_id", order_id)
	kitchen.set("_mode", KitchenWindow.Mode.RESULT)
	kitchen.set("_stage", null)
	var scores: Dictionary[int, float] = {}
	for i: int in recipe.steps.size():
		scores[i] = quality
	kitchen.set("_step_scores", scores)
	kitchen.call("_on_judged", {"order": order_id, "stars": stars, "quality": quality, "taste": 0.7, "pay": recipe.price, "share": recipe.price})
	if became:
		kitchen.call("_on_served_info", {"order": order_id, "became": true, "lost": false})
	await get_tree().create_timer(1.1).timeout
	var reaction: GuestReaction = kitchen.get("_reaction")
	_check(reaction != null and is_instance_valid(reaction), "%s ★%d: 결과 화면에 손님 반응" % [dish, stars])
	if reaction != null and is_instance_valid(reaction):
		var stages: Array[Node] = reaction.find_children("*", "CurveAnchor", true, false)
		var at: Vector3 = (stages[0] as Node3D).global_position if not stages.is_empty() else Vector3.INF
		_check(Vector2(at.x - WorldStyle.curve_origin.x, at.z - WorldStyle.curve_origin.z).length() < 0.01,
			"손님 얼굴 무대가 땅 휘기 기준점을 따라감 (가라앉지 않음) %s" % str(at))
	if not _shots.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shots.path_join("kitchen_result_%s_%d.png" % [customer, stars]))
	Economy.orders.erase(order_id)
	kitchen.call("_back_to_orders")


func _check(ok: bool, what: String) -> void:
	print("[kitchen] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
