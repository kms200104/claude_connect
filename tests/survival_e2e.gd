extends Node
## v0.23 생존 종단 테스트 (서버 1개 + Godot 1개, 밤 23시 · 크리처가 빨리 나온다):
## 빈집 냉장고 앞 상황 버튼 "뒤지기 · 냉장고" → 찾은 것 · 열린 냉장고, 체력 하트, 둔치에서 크리처가 나타나 다가와 때리고(하트가 준다),
## "공격"으로 쓰러뜨리면 땅에 아이템이 떨어진다, 가방에서 붕대 "쓰기" → 체력이 오른다.
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
		print("[survival] FAIL: %s" % f)
	print("[survival] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[survival] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _teleport(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _run() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var survival: SurvivalController = _village.get_node("Survival")
	var bag: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	var player: Player = _village.get_node("Player")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.6).timeout
	var rules: SurvivalRules = GameData.survival
	_check(rules.houses.size() == 16 and survival.houses.get_child_count() == 16, "빈집 16채 (%d)" % survival.houses.get_child_count())
	_check(survival.get("_hearts") != null and (survival.get("_hearts") as Control).get_child_count() == 5, "체력 하트 5개 (체력 10)")
	_check(Net.hp == 10 and GameData.survival.is_night(Net.game_hour()), "밤 · 체력 가득 (%d, %.1f시)" % [Net.hp, Net.game_hour()])

	# ---- 빈집 냉장고 뒤지기 ----
	var fridge: SurvivalRules.LootBox = rules.containers["h01_2"]
	var house: SurvivalRules.House = rules.houses[0]
	var front: Vector3 = house.position + Basis(Vector3.UP, house.yaw) * Vector3(fridge.local.x - 0.9, 0.3, fridge.local.y)
	await _teleport(front, house.yaw - PI * 0.5)
	await _shot("surv_house_inside")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.SURVIVE and interaction.target_id == "loot:h01_2", 2.0), "냉장고 앞 상황 버튼 '%s'" % survival.target_label("loot:h01_2"))
	var before: int = 0
	for it: InventoryItem in Net.inventory:
		before += it.count if it != null else 0
	var got: Array = [{}]
	Net.looted.connect(func(i: Dictionary) -> void: got[0] = i, CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not (got[0] as Dictionary).is_empty(), 3.0), "냉장고를 뒤졌다 (%s)" % str(got[0].get("items", [])))
	_check(not Net.can_loot("h01_2"), "뒤진 냉장고는 비었다 (다시 찰 때까지)")
	var open_mesh: Node3D = survival.houses.find_child("BoxOpen_h01_2", true, false) as Node3D
	_check(open_mesh != null and open_mesh.visible, "냉장고 문이 열린 모습")
	_check(await _wait_until(func() -> bool: return interaction.target_id != "loot:h01_2", 1.0), "빈 냉장고에는 '뒤지기'가 없다")
	var roof: Node3D = survival.houses.find_child("House_h01", true, false).get_node("Roof") as Node3D
	_check(not roof.visible, "집 안에 들어가면 지붕을 걷는다")

	# ---- 밤 크리처 ----
	await _teleport(Vector3(-150.0, 0.1, 140.0))
	_check(await _wait_until(func() -> bool: return not Net.creatures.is_empty() and survival.creatures.get_child_count() > 0, 5.0), "둔치에 크리처가 나타났다 (%d)" % Net.creatures.size())
	_check(await _wait_until(func() -> bool: return Net.hp < Net.max_hp, 40.0), "크리처가 다가와 때렸다 (체력 %d)" % Net.hp)
	await _shot("surv_creature")
	var dead: Array = [false]
	Net.creature_dead.connect(func(i: Dictionary) -> void:
		if int(i.get("by", 0)) == Net.my_id:
			dead[0] = true)
	var drops_before: int = Net.drops.size()
	for i: int in 40:
		if dead[0]:
			break
		# 맞는 동안 체력이 바닥나지 않게 서버 쪽이 아니라 여기서는 계속 때린다.
		if interaction.target == InteractionController.Target.SURVIVE and interaction.target_id.begins_with("attack:"):
			interaction.action_hud.action_pressed.emit()
		await get_tree().create_timer(0.35).timeout
	_check(dead[0], "'공격'으로 크리처를 쓰러뜨렸다")
	_check(await _wait_until(func() -> bool: return Net.drops.size() > drops_before, 2.0), "쓰러진 자리에 아이템이 떨어졌다")
	await _shot("surv_drop")

	# ---- 붕대 쓰기 ----
	await _teleport(Vector3(-58.0, 0.1, 68.0))
	if Net.hp >= Net.max_hp:
		_check(true, "(이미 체력 가득 — 붕대는 건너뜀)")
	else:
		var hp_before: int = Net.hp
		var slot: int = -1
		for i: int in Net.inventory.size():
			if Net.inventory[i] != null and Net.inventory[i].id == "bandage":
				slot = i
		bag.open()
		await get_tree().process_frame
		bag.press_slot(slot)
		await get_tree().process_frame
		var use: Button = bag.find_child("UseButton", true, false) as Button
		_check(use.visible and use.text.begins_with("쓰기"), "가방 붕대: '%s'" % use.text)
		use.pressed.emit()
		_check(await _wait_until(func() -> bool: return Net.hp > hp_before, 3.0), "붕대를 써서 체력이 올랐다 (%d → %d)" % [hp_before, Net.hp])
		bag.close()
	_finished = true
