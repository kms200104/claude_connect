extends Node
## 굽기·찌기 (v0.11) 화면 검증: 서버 없이 주방 창에 동작을 직접 띄우고, 딱 좋은 때에 누르면 서버 판정 규칙대로 완벽한 기록이 남는지 본다.
## 사용: godot --path . res://tests/kitchen_check.tscn [-- --shots=폴더]

var _failures: int = 0
var _shots: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	var kitchen: KitchenWindow = KitchenWindow.new()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	layer.add_child(kitchen)
	await get_tree().process_frame
	kitchen.visible = true
	await _run(kitchen, "trout_butter", "grill_hard")
	await _run(kitchen, "steamed_egg", "steam")
	print("KITCHEN %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _run(kitchen: KitchenWindow, dish: String, step_id: String) -> void:
	kitchen.set("_recipe", GameData.econ.recipes.get(dish))
	kitchen.call("_start_cooking_view")
	var recipe: RecipeInfo = kitchen.get("_recipe")
	var index: int = recipe.steps.find(step_id)
	_check(index >= 0, "%s 에 %s 동작이 있다" % [dish, step_id])
	kitchen.set("_mode", KitchenWindow.Mode.COOKING)
	kitchen.call("_begin_step", index)
	var step: Dictionary = kitchen.get("_step")
	var shot_at: Array[float] = [0.55, 1.2, 2.0]
	if step_id.begins_with("steam"):
		shot_at = [0.6, 1.7, 2.6]
	var t0: float = Time.get_ticks_msec()
	while kitchen.get("_mode") == KitchenWindow.Mode.COOKING and Time.get_ticks_msec() - t0 < 15000.0:
		var t: float = float(Time.get_ticks_msec()) - float(kitchen.get("_step_start_ms"))
		var ideal: Dictionary = kitchen.next_ideal_input()
		if t >= float(ideal["at"]):
			kitchen.call("_on_release" if bool(ideal["release"]) else "_on_tap")
		if not _shots.is_empty() and not shot_at.is_empty() and (Time.get_ticks_msec() - t0) / 1000.0 >= shot_at[0]:
			shot_at.pop_front()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shots.path_join("kitchen_%s_%d.png" % [step_id, 3 - shot_at.size()]))
		await get_tree().process_frame
	var taps: Array = (kitchen.get("_taps") as Array).back()
	print("[kitchen] %s taps=%s" % [step_id, str(taps)])
	match str(step.get("kind", "")):
		"grill":
			var side: float = float(step["side_ms"])
			_check(taps.size() == int(step["sides"]) and absf(float(taps[0]) - side) < 80.0 and absf(float(taps[1]) - float(taps[0]) - side) < 80.0,
				"굽기: 면마다 노릇할 때 뒤집고 꺼냄")
		"steam":
			var n: int = int(step["items"])
			_check(taps.size() == n + 3, "찌기: 재료 %d개 + 물 붓기 시작·끝 + 뚜껑 열기" % n)
			if taps.size() == n + 3:
				_check(absf(float(taps[n + 1]) - float(taps[n]) - float(step["fill_ms"])) < 80.0, "물을 선까지 부음")
				_check(absf(float(taps[n + 2]) - float(taps[n + 1]) - float(step["steam_ms"])) < 80.0, "김이 알맞을 때 뚜껑을 엶")


func _check(ok: bool, what: String) -> void:
	print("[kitchen] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
