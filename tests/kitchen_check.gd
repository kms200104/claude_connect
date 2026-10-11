extends Node
## 주방 장면 검증: 서버 없이 주방 창에 동작을 직접 띄우고, 딱 좋은 때에 누르면 서버 판정 규칙(CookRules)대로 완벽한 기록이 남는지 본다.
## 장면마다 (썰기 · 간하기 · 꼬치 · 웍 · 굽기 · 부치기 · 끓이기 · 졸이기 · 튀기기 · 담기 · 버무리기 · 반죽 · 찌기) 한 번씩.
## 사용: godot --path . res://tests/kitchen_check.tscn [-- --shots=폴더] [--only=장면,장면]

## [요리, 동작] — 장면마다 하나 (재료가 다르게 보이도록 고른다).
const CASES: Array = [
	["braised_fish", "chop"], ["trout_butter", "grill_hard"], ["samgyeopsal", "grill"], ["beef_steak", "season"], ["chicken_skewer", "skewer"],
	["bulgogi", "stir_fry"], ["mushroom_jeon", "fry_flip"], ["loach_soup", "boil"], ["braised_fish", "simmer"], ["fried_chicken", "deep_fry"],
	["herb_bibimbap", "mix_hard"], ["dumplings", "knead"], ["steamed_egg", "steam"], ["rice_ball", "plate"],
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
	match str(step.get("kind", "")):
		"grill":
			span = float(step["side_ms"]) * float(step["sides"]) + 700.0
		"timing":
			span = float(step["ideal_ms"]) + 600.0
		"steam":
			span = 300.0 + float(step["fill_ms"]) + float(step["steam_ms"]) + 700.0
		"mash":
			span = float(step["duration_ms"]) * 0.7
	var shot_at: Array[float] = [0.3, 0.62, 0.9]
	if str(step.get("kind", "")) == "timing":
		shot_at = [0.45, float(step["ideal_ms"]) / span - 0.02, 0.95]
	var shot_n: int = 0
	var t0: float = float(kitchen.get("_step_start_ms"))
	while kitchen.get("_mode") == KitchenWindow.Mode.COOKING and Time.get_ticks_msec() - t0 < 16000.0:
		var t: float = float(Time.get_ticks_msec()) - t0
		var ideal: Dictionary = kitchen.next_ideal_input()
		if t >= float(ideal["at"]):
			kitchen.call("_on_release" if bool(ideal["release"]) else "_on_tap")
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
	_check(q >= 0.9, "%s · %s: 딱 좋은 때 누르면 솜씨 %.2f ≥ 0.9" % [dish, scene, q])
	match str(step.get("kind", "")):
		"grill":
			var side: float = float(step["side_ms"])
			_check(taps.size() == int(step["sides"]) and absf(float(taps[0]) - side) < 80.0 and absf(float(taps[1]) - float(taps[0]) - side) < 80.0,
				"굽기: 면마다 노릇할 때 뒤집고 꺼냄")
		"steam":
			var n: int = int(step["items"])
			_check(taps.size() == n + 3, "찌기: 재료 %d개 + 물 붓기 시작·끝 + 뚜껑 열기" % n)


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
