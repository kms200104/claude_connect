extends Node
## 앱 안 테스트 서버 종단 테스트 (v0.10.1, Node 서버 없이 · tests/run_test_server_e2e.sh).
##   "서버 없이 테스트하기" → 주민과 대화(상황 버튼 → 대화창 → 친밀도) → 도끼로 나무 세 번 → 그루터기 → 낚시(입질 → 챔질 → 가방)
##   → 들판 채집 → 거울 얼굴 바꾸기 → 꺼졌다 켜도 가방이 그대로

var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalTestServer.SAVE_PATH))
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[testserver] FAIL: %s" % f)
	print("[testserver] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[testserver] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _teleport(at: Vector3) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _count(id: String) -> int:
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		if it != null and it.id == id:
			n += it.count
	return n


func _bag_total() -> int:
	var n: int = 0
	for i: int in range(Net.quick_slot_count, Net.inventory.size()):
		if Net.inventory[i] != null:
			n += Net.inventory[i].count
	return n


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var dialogue: DialogueController = _village.get_node("DialogueController")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var fishing: FishingController = _village.get_node("FishingController")
	var trees: TreeField = _village.get_node("Trees")
	var fishing_hud: FishingHud = _village.get_node("HUD/FishingHud")
	Net.play_on_test_server()
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 5.0), "서버 없이 앱 안 테스트 서버로 접속")

	# ---- 주민 대화 ----
	var npc: NetNpcState = Net.npc_states[0]
	await _teleport(npc.position + Vector3(1.2, 0.1, 0.0))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK, 3.0), "주민 곁에서 '대화' (%s)" % interaction.target_id)
	var opened: Array = []
	Net.talk_opened.connect(func(r: TalkReply) -> void: opened.append(r), CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not opened.is_empty(), 3.0), "대화가 열림 (테스트 서버가 talk_open)")
	_check(await _wait_until(func() -> bool: return dialogue.is_active() and box.is_open(), 2.0), "대화창이 뜸")
	_check(int(Net.friends.get(npc.id, 0)) > 0, "오늘 처음 말 걸어 친밀도가 오름 (%d)" % int(Net.friends.get(npc.id, 0)))
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 150:
		if not dialogue.is_active():
			break
		if choices.visible and choices.get_child_count() > 0:
			(choices.get_child(choices.get_child_count() - 1) as Button).pressed.emit()
		elif box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
	_check(not dialogue.is_active() and not player.is_input_locked(), "대화를 마치고 다시 움직일 수 있다")

	# ---- 나무 베기 ----
	Net.equip(1)
	_check(await _wait_until(func() -> bool: return player.held_item == "axe", 2.0), "도끼를 듦")
	var before: int = _bag_total()
	await _teleport(trees.tree_position("t01") + Vector3(1.3, 0.1, 0.0))
	for i: int in 3:
		_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP and interaction.target_id == "t01", 3.0), "나무 곁 '베기' %d" % (i + 1))
		var chopped: Array = []
		Net.chop_succeeded.connect(func(_t: String, item: String, _f: bool) -> void: chopped.append(item), CONNECT_ONE_SHOT)
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return not chopped.is_empty(), 3.0), "도끼질 %d → %s" % [i + 1, GameData.item_name(str(chopped[0])) if not chopped.is_empty() else "없음"])
		await get_tree().create_timer(0.6).timeout
	_check(_bag_total() == before + 3, "나무에서 나온 것 3개가 가방에 (%d → %d)" % [before, _bag_total()])
	_check(Net.tree_stages.get("t01", "") == NetProtocol.TREE_STUMP, "세 번째에 쓰러져 그루터기")

	# ---- 낚시 ----
	Net.equip(0)
	await _wait_until(func() -> bool: return player.held_item == "rod", 2.0)
	await _teleport(Vector3(-42.6, 0.1, 35.4))
	var fish_before: int = _bag_total()
	var pond: FishingSpot = _village.get_node("Terrain/Lake")
	_check(await _wait_until(func() -> bool: return pond.can_cast_from(player.global_position), 2.0), "물가에 섬")
	fishing_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return fishing.phase == FishingController.Phase.WAITING or fishing.phase == FishingController.Phase.BITE, 3.0), "낚싯대를 던짐 (fish_started)")
	_check(await _wait_until(func() -> bool: return fishing.phase == FishingController.Phase.BITE, 12.0), "입질이 옴")
	await _hook_and_reel(fishing_hud, fishing)
	_check(await _wait_until(func() -> bool: return _bag_total() == fish_before + 1, 4.0), "챔질해서 물고기를 낚음")
	await _wait_until(func() -> bool: return fishing.phase == FishingController.Phase.IDLE, 8.0)

	# ---- 들판 채집 ----
	_check(await _wait_until(func() -> bool: return not Net.drops.is_empty(), 3.0), "들판에 채집물이 돋음 (%d)" % Net.drops.size())
	if not Net.drops.is_empty():
		var drop: DropInfo = Net.drops.values()[0]
		var item_before: int = _count(drop.item)
		await _teleport(drop.position + Vector3(0.6, 0.1, 0.0))
		_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.COLLECT, 3.0), "'채집' 단추")
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return _count(drop.item) == item_before + 1, 3.0), "%s 을(를) 채집" % GameData.item_name(drop.item))

	# ---- 거울 얼굴 ----
	var changed: Array = []
	Net.face_changed.connect(func(id: int, face: Dictionary) -> void: changed.append(face), CONNECT_ONE_SHOT)
	Net.set_face({"hair_color": "black"})
	_check(await _wait_until(func() -> bool: return not changed.is_empty() and str((changed[0] as Dictionary).get("hair_color", "")) == "black", 2.0), "거울에서 머리 색 바꾸기")

	# ---- 다시 접속해도 그대로 ----
	var bag: int = _bag_total()
	Net.leave()
	await _wait_until(func() -> bool: return Net.state == Net.State.DISCONNECTED, 2.0)
	Net.play_on_test_server()
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 5.0), "다시 테스트 서버로")
	_check(_bag_total() == bag, "가방이 그대로 (%d)" % _bag_total())


## 사람처럼: 찌가 잠기는 걸 보고 150ms 뒤 챔질 → 끌어올리기 연타(80ms 간격)로 끝까지.
func _hook_and_reel(h: FishingHud, c: FishingController) -> void:
	await _wait_until(func() -> bool: return c.is_bite_visible(), 3.0)
	await get_tree().create_timer(0.15).timeout
	h.action_pressed.emit()
	if not await _wait_until(func() -> bool: return c.phase == FishingController.Phase.REEL, 3.0):
		return
	var pressed: int = 0
	while c.phase == FishingController.Phase.REEL and pressed < 40:
		h.action_pressed.emit()
		pressed += 1
		await get_tree().create_timer(0.08).timeout
