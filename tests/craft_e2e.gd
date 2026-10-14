extends Node
## v0.22 제작 · 세상 시각 종단 테스트 (서버 1개 + Godot 1개).
## - 세상 시각 60배: 2초 동안 마을 시각이 약 2분 흐르고, 날짜(달력)는 그대로.
## - 가방 "제작" 단추 → 제작 창(맨손): 밧줄 만들기 · 작업대 만들기, 공구가 필요한 것은 잠겨 있다.
## - 공구 창고 곁 상황 버튼 "공구 창고" → 제작 창(공용 작업대): 못 · 손전등 만들기 (서버가 재료를 빼고 넣는다).
## - 재료가 모자라면 "재료가 모자라요".
## tests/run_craft_e2e.sh 가 서버를 WORLD_TIME_SCALE=60 · START_ITEMS 로 띄운다.
## 인자: -- --server=ws://127.0.0.1:PORT [--shots=폴더]

var _server: String = ""
var _shots: String = ""
var _failures: Array[String] = []
var _village: Node = null
var _finished: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	if _failures.is_empty() and not _finished:
		_failures.append("테스트가 끝까지 돌지 않음")
	for f: String in _failures:
		print("[craft] FAIL: %s" % f)
	print("[craft] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[craft] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _shot(shot_name: String) -> void:
	if _shots.is_empty():
		return
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(shot_name + ".png"))


func _count(id: String) -> int:
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		if it != null and it.id == id:
			n += it.count
	return n


func _teleport(at: Vector3) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _press(window: Node, button_name: String) -> bool:
	var b: Button = window.find_child(button_name, true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _run() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var crafting: CraftController = _village.get_node("Crafting")
	var toast: FishingHud = _village.get_node("HUD/FishingHud")
	var bag: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.5).timeout

	# ---- 세상 시각 60배 ----
	var h0: float = Net.game_hour()
	var d0: int = Net.game_day()
	var c0: float = Net.calendar_hour()
	await get_tree().create_timer(2.0).timeout
	var dh: float = fposmod(Net.game_hour() - h0, 24.0)
	_check(dh > 1.6 / 60.0 and dh < 2.6 / 60.0, "현실 2초에 마을 시각이 약 2분 흐른다 (%.3f시간)" % dh)
	_check(fposmod(Net.calendar_hour() - c0, 24.0) < 0.01 and Net.game_day() == d0, "달력 시각 · 날짜는 실제 그대로")

	# ---- 가방 → 제작 (맨손) ----
	_check(_count("cloth") == 6 and _count("scrap_metal") == 3, "재료를 들고 시작 (천 %d · 고철 %d)" % [_count("cloth"), _count("scrap_metal")])
	await _teleport(Vector3(-43.0, 0.1, 66.0))
	bag.open()
	await get_tree().process_frame
	var craft_button: Button = bag.find_child("CraftButton", true, false) as Button
	_check(craft_button != null, "가방에 '제작' 단추")
	craft_button.pressed.emit()
	await get_tree().process_frame
	var window: CraftWindow = crafting.window
	_check(window.is_open() and window.tier == 0, "가방에서 연 제작 창은 맨손 등급 (%d)" % window.tier)
	_check(window.find_child("Recipe_nails", true, false) != null and window.find_child("Make_nails", true, false) == null, "못은 공구 창고가 필요해 잠겨 있다")
	await _shot("craft_hands")
	var made: Array = [0]
	Net.crafted.connect(func(_i: Dictionary) -> void: made[0] += 1)
	_check(_press(window, "Make_rope"), "밧줄 '만들기'")
	_check(await _wait_until(func() -> bool: return made[0] == 1 and _count("rope") == 1, 3.0), "밧줄을 만들었다 (밧줄 %d · 천 %d)" % [_count("rope"), _count("cloth")])
	_check(_count("cloth") == 4, "천 2개를 썼다")
	await get_tree().process_frame
	_check(_press(window, "Make_workbench"), "작업대 '만들기'")
	_check(await _wait_until(func() -> bool: return made[0] == 2 and _count("workbench") == 1, 3.0), "작업대를 만들었다")
	window.close()

	# ---- 공구 창고 (공용 작업대) ----
	var bench: CraftingRules.Bench = GameData.crafting.benches[0]
	var front: Vector3 = bench.position + Basis(Vector3.UP, bench.yaw) * Vector3(0.0, 0.1, 1.6)
	await _teleport(front)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CRAFT, 2.0), "공구 창고 곁 상황 버튼 '%s'" % crafting.target_label("public:x"))
	interaction.action_hud.action_pressed.emit()
	await get_tree().process_frame
	_check(window.is_open() and window.tier == 2, "공구 창고 제작 창 (등급 %d)" % window.tier)
	_check(_press(window, "MakeMax_nails"), "못 '3번 만들기'")
	_check(await _wait_until(func() -> bool: return _count("nails") == 6, 3.0), "못 6개 (%d) · 고철 %d" % [_count("nails"), _count("scrap_metal")])
	await _shot("craft_bench")
	# 손전등: 고철이 다 떨어져 재료가 모자라다 → 버튼이 꺼져 있고, 억지로 보내도 서버가 거절.
	_check(window.find_child("Make_flashlight", true, false) != null and (window.find_child("Make_flashlight", true, false) as Button).disabled, "손전등은 재료가 모자라 꺼져 있다")
	var warned: Array = [""]
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind == "craft":
			warned[0] = code)
	Net.craft("flashlight", 1)
	_check(await _wait_until(func() -> bool: return warned[0] == NetProtocol.ERR_NOT_ENOUGH_ITEMS, 3.0), "서버도 재료가 모자라면 거절 (%s)" % warned[0])
	window.close()
	_finished = true
