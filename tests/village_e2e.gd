extends Node
## 마을 종단 테스트(클라이언트 1개): 비 오는 날 · 퀵슬롯으로 도끼 들기 · 나무 베기 → 인벤토리 ·
## 가방 창(캐릭터가 고른 칸을 바라봄, 칸 옮기기) · 주민 대화 → 부탁 수락 → 목재 모아 완료.
## tests/run_village_e2e.sh 가 서버를 WEATHER_FORCE=rain QUEST_CHANCE=1 QUEST_TEMPLATE=wood 로 띄운다.
## 인자: -- --server=ws://127.0.0.1:PORT

var _server: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[village] FAIL: %s" % f)
	print("[village] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[village] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _count(item_id: String) -> int:
	var n: int = 0
	for item: InventoryItem in Net.inventory:
		if item != null and item.id == item_id:
			n += item.count
	return n


## 도구가 아닌 아이템 개수 (나무에서 목재·가지·도토리 등이 나온다).
func _count_drops() -> int:
	var n: int = 0
	for item: InventoryItem in Net.inventory:
		if item != null and not GameData.item(item.id).is_tool():
			n += item.count
	return n


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var trees: TreeField = _village.get_node("Trees")
	var npcs: NpcCrowd = _village.get_node("Npcs")
	var sky: SkyController = _village.get_node("SkyController")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var dialogue: DialogueController = _village.get_node("DialogueController")
	var hotbar: Hotbar = _village.get_node("HUD/Hotbar")
	var window: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var top_bar: TopBar = _village.get_node("HUD/TopBar")

	Net.create_room(_server)
	await Net.welcomed

	# ---- 월드 ----
	_check(trees.get_child_count() == GameData.trees.size(), "나무 %d그루가 데이터 위치에 생김" % trees.get_child_count())
	var mujin: NpcActor = npcs.actor("mujin")
	_check(mujin != null and mujin.global_position.distance_to(GameData.npcs["mujin"].home) < 0.5, "주민이 집 앞에 서 있음 (비)")
	_check(await _wait_until(func() -> bool: return sky.rain_amount > 0.4, 4.0), "비가 내림 (%.2f)" % sky.rain_amount)
	_check(sky.rain.visible and not sky.sun.shadow_enabled, "비 판이 보이고 그림자는 꺼짐")
	_check(not top_bar.get_node("%WeatherLabel").text.is_empty() and top_bar.get_node("%WeatherLabel").text == "비", "위쪽 막대에 날씨 표시")

	# ---- 퀵슬롯으로 도끼 들기 ----
	_check(hotbar.slot_button(1).get_item().id == "axe", "퀵슬롯 2번에 도끼")
	hotbar.slot_button(1).pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.held_slot == 1 and player.held_item == "axe", 2.0), "도끼를 손에 듦")
	_check(player.rig.axe.visible and not player.rig.rod.visible, "모델에 도끼가 보임")

	# ---- 나무 베기 ----
	var tree_id: String = "t13"
	player.global_position = trees.tree_position(tree_id) + Vector3(1.3, 0.1, 0.0)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP and interaction.target_id == tree_id, 2.0), "나무 곁에서 '베기' 버튼")
	var before: int = _count_drops()
	for i: int in 3:
		await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP, 2.0)
		interaction.action_hud.action_pressed.emit()
		await Net.chop_succeeded
	_check(await _wait_until(func() -> bool: return _count_drops() - before == 3, 2.0), "도끼질 3번 → 나무에서 나온 것 3개가 인벤토리로 (%d → %d)" % [before, _count_drops()])
	_check(await _wait_until(func() -> bool: return trees.stage_of(tree_id) == NetProtocol.TREE_STUMP, 2.0), "세 번째에 나무가 쓰러져 그루터기")
	_check(interaction.target != InteractionController.Target.CHOP or interaction.target_id != tree_id, "그루터기는 더 못 벤다")

	# ---- 가방 창 ----
	hotbar.bag_pressed.emit()
	_check(window.is_open() and window.get_viewport().disable_3d, "가방 아이콘 → 창이 열리고 월드 렌더링은 멈춤")
	_check(player.is_input_locked(), "가방 창이 열려 있으면 캐릭터가 멈춤")
	var wood_slot: int = -1
	for i: int in range(Net.quick_slot_count, Net.inventory.size()):
		if Net.inventory[i] != null and not GameData.item(Net.inventory[i].id).is_tool():
			wood_slot = i
			break
	window.press_slot(wood_slot)
	var preview: CharacterPreview = window.preview()
	await get_tree().create_timer(0.8).timeout
	_check(preview.look_active and preview.yaw_offset() < -0.2, "왼쪽 칸을 고르면 캐릭터가 그쪽으로 몸을 돌림 (%.2f rad)" % preview.yaw_offset())
	_check(preview.rig.get_eye_offset().x > 0.2, "눈동자도 그 칸 쪽으로 (%.2f)" % preview.rig.get_eye_offset().x)
	var yaw_bag: float = preview.yaw_offset()
	window.press_slot(wood_slot)  # 같은 칸 다시 → 선택 해제
	window.press_slot(0)  # 퀵슬롯 1번(낚싯대): 아래쪽 칸
	await get_tree().create_timer(0.8).timeout
	_check(preview.look_active and preview.pivot.rotation.x < 0.0, "아래쪽 퀵슬롯을 고르면 고개를 숙임 (%.2f)" % preview.pivot.rotation.x)
	_check(absf(preview.yaw_offset() - yaw_bag) > 0.01, "고른 칸이 바뀌면 시선도 바뀜")
	window.press_slot(0)
	# 칸 옮기기: 목재 칸 → 가방 마지막 칸
	var last: int = Net.inventory.size() - 1
	var moved_id: String = Net.inventory[wood_slot].id
	window.press_slot(wood_slot)
	window.press_slot(last)
	_check(await _wait_until(func() -> bool: return Net.inventory[last] != null and Net.inventory[last].id == moved_id, 2.0), "고른 아이템을 다른 칸으로 옮김 (서버 확정)")
	window.close()
	_check(not window.is_open() and not window.get_viewport().disable_3d and not player.is_input_locked(), "창을 닫으면 월드가 다시 그려지고 움직일 수 있음")

	# ---- 주민 대화 → 부탁 ----
	player.global_position = mujin.global_position + Vector3(1.6, 0.1, 0.0)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK and interaction.target_id == "mujin", 2.0), "주민 곁에서 '대화' 버튼 (도끼를 들고 있어도 대화가 우선)")
	interaction.action_hud.action_pressed.emit()
	_check(dialogue.is_active() and player.is_input_locked(), "대화 시작 → 캐릭터 멈춤")
	_check(await _advance_until_choices(box), "인사 뒤 부탁 선택지가 나옴")
	await _choose(box, 0)  # 좋아, 맡겨 줘!
	_check(await _wait_until(func() -> bool: return not Net.quests.is_empty(), 3.0), "부탁을 받음")
	await _advance_until_closed(box, dialogue)
	_check(not dialogue.is_active() and not player.is_input_locked(), "대화가 끝나면 다시 움직일 수 있음")
	if Net.quests.is_empty():
		return
	var quest: QuestInfo = Net.quests[0]
	_check(quest.npc == "mujin" and quest.item == "wood" and quest.count >= 3, "무진의 부탁: 목재 %d개" % quest.count)
	_check(mujin.mark.visible, "부탁한 주민 머리 위에 표시 (%s)" % mujin.mark.text)
	_check(top_bar.quest_lines().size() == 1 and top_bar.quest_lines()[0].begins_with("무진"), "부탁 목록에 표시: %s" % str(top_bar.quest_lines()))

	# 목재가 모자라면 근처 나무를 더 벤다.
	for id: String in ["t09", "t23", "t15", "t24", "t01", "t05", "t19"]:  # 둥근 나무: 목재가 가장 잘 나온다
		if Net.quest_from("mujin").is_ready():
			break
		player.global_position = trees.tree_position(id) + Vector3(1.3, 0.1, 0.0)
		await get_tree().create_timer(0.3).timeout  # 새 위치가 서버에 닿을 때까지
		for i: int in 3:
			if not await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP, 2.0):
				break
			interaction.action_hud.action_pressed.emit()
			await Net.chop_succeeded
		await get_tree().create_timer(0.2).timeout
	_check(Net.quest_from("mujin").is_ready() and mujin.mark.text == "!", "목재를 다 모으면 완료 가능 표시 '!'")

	player.global_position = mujin.global_position + Vector3(1.6, 0.1, 0.0)
	await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK, 2.0)
	var sol_before: int = Net.sol
	var wood_before: int = _count("wood")
	interaction.action_hud.action_pressed.emit()
	_check(await _advance_until_choices(box), "완료 선택지가 나옴")
	await _choose(box, 0)  # 부탁한 거 가져왔어!
	_check(await _wait_until(func() -> bool: return Net.sol == sol_before + quest.reward, 3.0), "부탁 완료 → %d솔 받음 (지금 %d솔)" % [quest.reward, Net.sol])
	_check(_count("wood") == wood_before - quest.count, "목재 %d개를 건넴" % quest.count)
	await _advance_until_closed(box, dialogue)
	_check(Net.quests.is_empty() and not mujin.mark.visible, "부탁 목록과 머리 위 표시가 사라짐")
	_check(Net.friends.get("mujin", 0) >= 7, "무진과 친해짐 (%d)" % Net.friends.get("mujin", 0))


## 대사를 넘기다가 선택지가 나오면 true.
func _advance_until_choices(box: DialogueBox) -> bool:
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 80:
		if choices.visible and choices.get_child_count() > 0:
			return true
		if box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
	return false


func _choose(box: DialogueBox, index: int) -> void:
	var choices: VBoxContainer = box.get_node("%Choices")
	var button: Button = choices.get_child(index) as Button
	button.pressed.emit()
	await get_tree().process_frame


func _advance_until_closed(box: DialogueBox, dialogue: DialogueController) -> void:
	for i: int in 80:
		if not dialogue.is_active():
			return
		if box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
