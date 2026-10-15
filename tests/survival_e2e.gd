extends Node
## v0.23 생존 종단 테스트 (서버 1개 + Godot 1개, 밤 23시 · 크리처가 빨리 나온다):
## 빈집 냉장고 앞 상황 버튼 "뒤지기 · 냉장고" → 찾은 것 · 열린 냉장고, 체력 하트, 둔치에서 크리처가 나타나 다가와 때리고(하트가 준다),
## "공격"으로 쓰러뜨리면 땅에 아이템이 떨어진다, 가방에서 붕대 "쓰기" → 체력이 오른다.
## v0.24: 깨진 창 앞 "판자 대기" → 판자가 보이고 목재 · 못을 쓴다.
## v0.25: 판자는 망치질 막대가 찬 뒤에 붙는다 · 휘두르면 소리 · 현관 · 깨진 창을 다 막으면 거점 (알림 · 등불) →
## "거점 상자 열기" 넣기 · 꺼내기 → 침대 "자기" (누운 몸 · 체력이 오른다) → "일어나기".
## v0.26: 맞으면 피 냄새 알림 · 땅의 핏자국, 붕대를 쓰면 멈춘다.
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
	_check(rules.houses.size() == 32 and survival.houses.get_child_count() == 32, "빈집 32채 (%d)" % survival.houses.get_child_count())
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

	# ---- v0.24 깨진 창에 판자 대기 ----
	_check(house.broken.has("w4") and rules.breaches.has("h01:w4"), "h01 왼쪽 창이 깨져 있다 (%s)" % str(house.broken))
	var board_node: Node3D = survival.houses.find_child("Boards_h01_w4", true, false) as Node3D
	_check(board_node != null and not board_node.visible, "판자를 대기 전에는 판자가 없다")
	await _teleport(house.position + Basis(Vector3.UP, house.yaw) * Vector3(-4.2, 0.3, 1.6), house.yaw + PI * 0.5)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.SURVIVE and interaction.target_id == "board:h01:w4", 2.0), "깨진 창 앞 상황 버튼 '%s' (%s)" % [survival.target_label("board:h01:w4"), interaction.target_id])
	_check(survival.target_label("board:h01:w4").begins_with("판자 대기 · 창"), "판자 값이 보인다")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.board_jobs.has("h01:w4") and (survival.get("_job_panel") as Control).visible, 2.0), "망치질 막대가 보인다")
	_check(await _wait_until(func() -> bool: return int(Net.boards.get("h01:w4", 0)) == rules.breaches["h01:w4"].max_hp, 6.0), "판자를 댔다 (%d)" % int(Net.boards.get("h01:w4", 0)))
	_check(board_node.visible and _count("wood") == 4 and _count("nails") == 2, "판자가 보이고 목재 · 못을 썼다")
	var chip: Label = survival.get("_chip")
	_check(chip.visible and chip.text.contains("판자 1/3"), "집 안 알림 '%s'" % chip.text)
	_check(await _wait_until(func() -> bool: return interaction.target_id != "board:h01:w4", 1.0), "멀쩡한 판자에는 '판자 대기'가 없다")
	await _shot("surv_boarded")

	# ---- 밤 크리처 ----
	await _teleport(Vector3(-150.0, 0.1, 140.0))
	_check(await _wait_until(func() -> bool: return not Net.creatures.is_empty() and survival.creatures.get_child_count() > 0, 5.0), "둔치에 크리처가 나타났다 (%d)" % Net.creatures.size())
	# v0.28.5 불빛 밖 크리처는 몸이 어둠에 묻혀 빛나는 눈만 보인다.
	_check(await _wait_until(func() -> bool: return Net.creatures.keys().any(func(id: String) -> bool: return survival.creatures.only_eyes(id)), 4.0), "어둠 속 크리처는 눈만 보인다")
	# 화면 위쪽에 오도록 그 크리처 남쪽 7m 로 옮겨 찍는다.
	if not _shots.is_empty():
		for id: String in Net.creatures:
			if survival.creatures.only_eyes(id):
				var cp: Vector3 = survival.creatures.actor_position(id)
				await _teleport(Vector3(cp.x, 0.1, cp.z + 7.0))
				break
		await _shot("surv_eyes")
	# v0.28.2 화면 밖에서 다가오는 크리처 쪽 가장자리가 은은하게 붉다.
	_check(await _wait_until(func() -> bool: return survival.edge_hint.hint_count() > 0, 5.0), "다가오는 크리처 방향 가장자리 표시")
	await _shot("surv_edge_hint")
	_check(await _wait_until(func() -> bool: return Net.hp < Net.max_hp, 40.0), "크리처가 다가와 때렸다 (체력 %d)" % Net.hp)
	# v0.28.1 맞으면 화면 가장자리가 붉게 번지고 피가 튄다.
	var hurt: HurtOverlay = survival.get("_hurt")
	_check(hurt != null and hurt.is_showing(), "맞은 화면 (붉은 가장자리 · 튄 피)")
	# v0.28.4 저레벨(Lv.1) 공포 연출: 크리처가 다가오면 채도가 빠지고 가장자리가 조여 온다 · 심장 소리.
	var fear: FearOverlay = survival.fear
	_check(await _wait_until(func() -> bool: return fear.level > 0.25, 3.0), "공포 연출 (세기 %.2f, Lv.%d)" % [fear.level, int(Net.hunter.get("lv", 1))])
	var env: Environment = (_village.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.adjustment_enabled and env.adjustment_saturation < 0.85, "세상 채도가 빠졌다 (%.2f)" % env.adjustment_saturation)
	_check(FearOverlay.level_factor(1, 5) == 1.0 and FearOverlay.level_factor(6, 5) == 0.0 and FearOverlay.level_factor(5, 5) < 0.3, "레벨이 오르면 약해지다 Lv.6 부터 없다")
	var sky: SkyController = _village.get_node("SkyController")
	_check(sky.night_light > 0.5 and env.ambient_light_energy < 0.45, "바깥 밤은 어둡다 (주변광 %.2f)" % env.ambient_light_energy)
	await _shot("surv_hurt")
	# v0.26 피 냄새: 다치면 피를 흘린다 (알림 · 땅의 핏자국).
	_check(await _wait_until(func() -> bool: return Net.bleeding.has(Net.my_id) and (survival.get("_blood_chip") as Control).visible, 3.0), "피 냄새 알림")
	_check(await _wait_until(func() -> bool: return not (survival.get("_drops") as Array).is_empty(), 5.0), "땅에 핏자국 (%d)" % Net.scent.size())
	await _shot("surv_creature")
	var noises: Array = [0]
	Net.noise_made.connect(func(_i: Dictionary) -> void: noises[0] += 1)
	var dead: Array = [false]
	Net.creature_dead.connect(func(i: Dictionary) -> void:
		if int(i.get("by", 0)) == Net.my_id:
			dead[0] = true)
	var drops_before: int = Net.drops.size()
	# v0.28.4 범위 안에 들면 버튼을 누르지 않아도 저절로 공격한다.
	var auto_hit: Array = [false]
	Net.creature_hit.connect(func(i: Dictionary) -> void:
		if int(i.get("by", 0)) == Net.my_id:
			auto_hit[0] = true)
	_check(await _wait_until(func() -> bool: return auto_hit[0] or dead[0], 8.0), "범위 안 크리처를 자동 공격")
	# v0.28.4 크리처가 나오는 밤에는 카메라가 더 물러난다.
	var rig: FollowCamera = _village.get_node("CameraRig") as FollowCamera
	_check(rig.zoom_out > 1.2, "밤에는 더 넓게 본다 (거리 ×%.2f)" % rig.zoom_out)
	for i: int in 40:
		if dead[0]:
			break
		# 맞는 동안 체력이 바닥나지 않게 서버 쪽이 아니라 여기서는 계속 때린다.
		if interaction.target == InteractionController.Target.SURVIVE and interaction.target_id.begins_with("attack:"):
			interaction.action_hud.action_pressed.emit()
		await get_tree().create_timer(0.35).timeout
	_check(dead[0], "'공격'으로 크리처를 쓰러뜨렸다")
	_check(noises[0] > 0, "밤에 휘두르면 소리가 난다 (%d번)" % noises[0])
	_check(await _wait_until(func() -> bool: return Net.drops.size() > drops_before, 2.0), "쓰러진 자리에 아이템이 떨어졌다")
	await _shot("surv_drop")
	# v0.28.4 손전등: 바라보는 쪽으로 원뿔 빛.
	var fl: int = -1
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == "flashlight":
			fl = i
	_check(fl >= 0, "가방에 손전등")
	if fl >= 5:
		Net.move_item(fl, 4)
		_check(await _wait_until(func() -> bool: return Net.inventory[4] != null and Net.inventory[4].id == "flashlight", 2.0), "손전등을 퀵슬롯으로")
		fl = 4
	var held_before: int = Net.held_slot
	Net.equip(fl)
	var flash_spot: SpotLight3D = survival.get("_spot")
	_check(await _wait_until(func() -> bool: return flash_spot.visible, 2.0), "손전등 원뿔 빛")
	# 앞(북쪽, 화면 위)을 비추게 돌려서 찍는다.
	player.body.rotation.y = 0.0
	await _shot("surv_flashlight")
	# v0.28.4 맞으면 손전등이 지직거리며 꺼졌다 켜졌다.
	survival.call("_on_hurt", {})
	var went_dark: Array = [false]
	_check(await _wait_until(func() -> bool:
		went_dark[0] = went_dark[0] or flash_spot.light_energy < 0.5
		return went_dark[0], 1.5), "맞으면 손전등이 깜빡인다 (%.1f초)" % survival.flicker_left)
	_check(await _wait_until(func() -> bool: return survival.flicker_left <= 0.0 and flash_spot.light_energy > 9.0, 3.0), "잠시 뒤 다시 켜진다")
	Net.equip(held_before)
	_check(await _wait_until(func() -> bool: return not flash_spot.visible, 2.0), "내려놓으면 꺼진다")

	# ---- v0.25 거점: 현관 · 깨진 창 하나 더 → 상자 · 침대 ----
	var turn: Basis = Basis(Vector3.UP, house.yaw)
	for spot: Array in [["h01:door", Vector3(-3.0, 0.3, 4.8)], ["h01:w3", Vector3(2.8, 0.3, -3.3)]]:
		await _teleport(house.position + turn * spot[1])
		var key: String = spot[0]
		_check(await _wait_until(func() -> bool: return interaction.target_id == "board:" + key, 2.0), "'%s' 앞 상황 버튼 (%s)" % [key, interaction.target_id])
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return int(Net.boards.get(key, 0)) > 0, 6.0), "%s 에 판자" % key)
	await get_tree().create_timer(0.4).timeout
	var lantern: Node3D = survival.houses.find_child("Lantern_h01", true, false) as Node3D
	_check(HouseField.is_base(house) and lantern != null and lantern.visible, "거점이 됐다 (등불)")
	await _teleport(house.position + turn * Vector3(rules.stash_local.x, 0.3, rules.stash_local.y - 0.85))
	_check(await _wait_until(func() -> bool: return interaction.target_id == "stash:h01", 2.0), "상자 앞 상황 버튼 '%s' (%s)" % [survival.target_label("stash:h01"), interaction.target_id])
	_check(chip.text.begins_with("거점"), "집 안 알림 '%s'" % chip.text)
	interaction.action_hud.action_pressed.emit()
	await get_tree().process_frame
	_check(survival.stash_window.is_open(), "거점 상자 창이 열렸다")
	var band_slot: int = -1
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == "bandage":
			band_slot = i
	var put: Button = survival.stash_window.find_child("PutOne_%d" % band_slot, true, false) as Button
	_check(put != null, "가방 붕대 '1개' 넣기 단추")
	if put != null:
		put.pressed.emit()
	_check(await _wait_until(func() -> bool: return not (Net.stash.get("h01", []) as Array).is_empty(), 3.0), "상자에 붕대를 넣었다 (%s)" % str(Net.stash.get("h01", [])))
	await get_tree().process_frame
	var take: Button = survival.stash_window.find_child("Take_bandage", true, false) as Button
	_check(take != null, "상자 '꺼내기' 단추")
	if take != null:
		take.pressed.emit()
	_check(await _wait_until(func() -> bool: return (Net.stash.get("h01", []) as Array).is_empty() and _count("bandage") == 3, 3.0), "다시 꺼냈다")
	await _shot("surv_stash")
	survival.stash_window.close()
	if Net.hp < Net.max_hp:
		await _teleport(house.position + turn * Vector3(rules.bed_local.x + 1.15, 0.3, rules.bed_local.y))
		_check(await _wait_until(func() -> bool: return interaction.target_id == "bed:h01", 2.0), "침대 곁 상황 버튼 '%s' (%s)" % [survival.target_label("bed:h01"), interaction.target_id])
		var hp0: int = Net.hp
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return Net.sleeping.has(Net.my_id), 2.0), "침대에서 잔다")
		await get_tree().create_timer(0.6).timeout
		_check(player.is_input_locked() and player.body.rotation.z > 1.2 and (survival.get("_sleep_panel") as Control).visible, "누운 몸 · 자는 중 안내")
		_check(await _wait_until(func() -> bool: return Net.hp > hp0, 5.0), "자는 동안 체력이 오른다 (%d → %d)" % [hp0, Net.hp])
		await _shot("surv_sleep")
		var wake: Button = survival.find_child("WakeButton", true, false) as Button
		if wake == null:
			wake = _village.get_node("HUD").find_child("WakeButton", true, false) as Button
		wake.pressed.emit()
		_check(await _wait_until(func() -> bool: return not Net.sleeping.has(Net.my_id) and not player.is_input_locked(), 2.0), "일어났다")
	else:
		_check(true, "(체력 가득 — 침대는 건너뜀)")

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
		_check(await _wait_until(func() -> bool: return not Net.bleeding.has(Net.my_id), 2.0), "붕대로 피가 멈췄다")
		bag.close()
	_finished = true
