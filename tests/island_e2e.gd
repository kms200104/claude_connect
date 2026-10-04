extends Node
## 섬 생활 종단 테스트 (클라이언트 1개, 서버 1개 · tests/run_island_e2e.sh 가 띄운다).
##   섬 지형·박물관·공항 → 달리다 반대로 꺾으면 브레이크 → 감정표현과 주민 반응 → 대화(기분·주제·감정표현 배우기)
##   → 도토리 심기 → 나무로 자람 → 튤립 심기 → 피면 따기 → 박물관 기증(수조에 물고기) → 공항 기념품 사기
## 인자: -- --server=ws://…

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
		print("[island] FAIL: %s" % f)
	print("[island] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[island] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _slot_of(item_id: String) -> int:
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == item_id:
			return i
	return -1


func _teleport(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.4).timeout


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var dialogue: DialogueController = _village.get_node("DialogueController")
	var emotes: EmoteController = _village.get_node("EmoteController")
	var emote_bar: EmoteBar = _village.get_node("HUD/EmoteBar")
	var npcs: NpcCrowd = _village.get_node("Npcs")
	var trees: TreeField = _village.get_node("Trees")
	var flowers: FlowerField = _village.get_node("Flowers")
	var museum: MuseumSite = _village.get_node("Museum")
	var airport: AirportSite = _village.get_node("Airport")
	var museum_window: MuseumWindow = _village.get_node("HUD/MuseumWindow")
	var shop_window: ShopWindow = _village.get_node("HUD/ShopWindow")

	Net.create_room(_server)
	await Net.welcomed
	await get_tree().process_frame

	# 섬
	_check(_village.get_node("Terrain/Island").get_node_or_null("Ocean") != null, "섬을 둘러싼 바다")
	_check(museum.actor != null and museum.actor.info.display_name == "부엉", "박물관 앞에 관장 부엉")
	_check(airport.actor != null and airport.plane != null, "공항 앞에 조종사, 활주로에 비행기")
	_check(npcs.actor("rara") != null and npcs.actor("danchu") != null, "새 주민 라라·단추")
	_check(Net.npc_moods.size() >= 6, "주민 기분을 받음: %s" % str(Net.npc_moods))

	# 브레이크: 오른쪽으로 달리다가 왼쪽으로 확 꺾는다.
	await _teleport(Vector3(30.0, 0.1, -36.0))
	var braked: Array = [false]
	player.braked.connect(func() -> void: braked[0] = true, CONNECT_ONE_SHOT)
	Input.action_press("ui_right")
	_check(await _wait_until(func() -> bool: return player.running and Vector2(player.velocity.x, player.velocity.z).length() > 6.0, 3.0), "끝까지 밀면 달린다 (%.1fm/s)" % player.velocity.length())
	Input.action_release("ui_right")
	Input.action_press("ui_left")
	_check(await _wait_until(func() -> bool: return braked[0], 0.5) and player.braking and player.rig.is_braking(), "반대로 꺾으면 브레이크 자세로 미끄러진다")
	var slide_from: Vector3 = player.global_position
	_check(await _wait_until(func() -> bool: return not player.braking, 2.0), "미끄러지다 멈춘다")
	_check(player.global_position.x - slide_from.x > 0.8, "앞으로 미끄러진 거리 %.2fm" % (player.global_position.x - slide_from.x))
	await get_tree().create_timer(0.5).timeout
	_check(player.velocity.x < -1.0, "멈춘 뒤 반대쪽으로 걸어간다")
	Input.action_release("ui_left")
	await get_tree().create_timer(0.3).timeout

	# 감정표현: 통통이 곁에서 '안녕'
	var tong: NpcActor = npcs.actor("tongtong")
	await _teleport(tong.global_position + Vector3(2.0, 0.1, 0.5))
	var reacted: Array = []
	Net.npc_emoted.connect(func(npc_id: String, e: String, to: int, _m: String) -> void: reacted.append([npc_id, e, to]))
	_check(emote_bar.visible and not emote_bar.is_open(), "감정표현 칸은 접혀 있다")
	emote_bar.toggle()
	_check(emote_bar.is_open() and emote_bar.slot_button(0) != null, "펼치면 '안녕' 칸")
	emote_bar.slot_button(0).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(player.get_node_or_null(EmoteBubble.ICON_NAME) != null and player.rig.is_emoting(), "내 머리 위에 말풍선, 손을 흔든다")
	_check(await _wait_until(func() -> bool: return reacted.any(func(r: Array) -> bool: return r[0] == "tongtong" and r[2] == Net.my_id), 2.0), "통통이가 반응: %s" % str(reacted))
	_check(await _wait_until(func() -> bool: return tong.get_node_or_null(EmoteBubble.ICON_NAME) != null, 1.0), "통통이 머리 위에도 말풍선")
	emote_bar.close()
	await get_tree().create_timer(1.0).timeout

	# 대화: 모락 (친밀도 30으로 시작) — 감정표현을 가르쳐 주고, 주제를 골라 수다
	var morak: NpcActor = npcs.actor("morak")
	await _teleport(morak.global_position + Vector3(1.5, 0.1, 0.0))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK and interaction.target_id == "morak", 2.0), "모락 곁에서 '대화'")
	var topics: Array = []
	Net.topic_answered.connect(func(npc_id: String, topic: String, gain: int) -> void: topics.append([npc_id, topic, gain]))
	interaction.action_hud.action_pressed.emit()
	_check(await _advance_until_choices(box), "인사 뒤 대화 주제를 고른다")
	_check((box.get_node("%NameTag") as Label).text.contains("·"), "이름 옆에 기분이 보인다: %s" % (box.get_node("%NameTag") as Label).text)
	_check("love" in Net.emotes_known and "love" in Net.emotes_quick, "모락에게 '좋아해'를 배움: %s" % str(Net.emotes_known))
	await _choose(box, 0)
	_check(await _wait_until(func() -> bool: return not topics.is_empty(), 2.0) and topics[0][2] == 1, "주제 수다로 친밀도 +1: %s" % str(topics))
	await _advance_until_closed(box, dialogue)
	_check(not dialogue.is_active() and not player.is_input_locked(), "대화가 끝나면 다시 움직임")

	# 도토리 심기 → 나무
	Net.move_item(_slot_of("acorn"), 2)
	await _wait_until(func() -> bool: return _slot_of("acorn") == 2, 2.0)
	Net.equip(2)
	await _teleport(Vector3(6.0, 0.1, 13.0), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.PLANT, 2.0), "도토리를 들면 '심기' (%s)" % str(interaction.plant_spot))
	var planted: Array = []
	Net.planted.connect(func(kind: String, id: String) -> void: planted.append([kind, id]), CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not planted.is_empty(), 3.0) and planted[0][0] == "tree", "심었다: %s" % str(planted))
	var tree_id: String = planted[0][1] if not planted.is_empty() else ""
	_check(await _wait_until(func() -> bool: return trees.stage_of(tree_id) == NetProtocol.TREE_SPROUT or trees.stage_of(tree_id) == NetProtocol.TREE_SAPLING, 2.0), "새싹이 돋는다")
	_check(await _wait_until(func() -> bool: return trees.stage_of(tree_id) == NetProtocol.TREE_YOUNG, 15.0), "어린 나무로 자람")
	_check(await _wait_until(func() -> bool: return trees.stage_of(tree_id) == NetProtocol.TREE_GROWN, 15.0), "다 자란 나무")

	# 튤립 심기 → 피면 따기
	Net.move_item(_slot_of("seed_tulip"), 3)
	await _wait_until(func() -> bool: return _slot_of("seed_tulip") == 3, 2.0)
	Net.equip(3)
	await _teleport(Vector3(9.5, 0.1, 13.0), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.PLANT, 2.0), "알뿌리를 들면 '심기'")
	planted.clear()
	Net.planted.connect(func(kind: String, id: String) -> void: planted.append([kind, id]), CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not planted.is_empty(), 3.0) and planted[0][0] == "flower", "꽃을 심었다")
	var flower_id: String = planted[0][1] if not planted.is_empty() else ""
	_check(await _wait_until(func() -> bool: return flowers.has_flower(flower_id), 2.0), "새싹이 보인다")
	Net.equip(-1)
	_check(await _wait_until(func() -> bool: return Net.flowers.has(flower_id) and Net.flowers[flower_id].stage == NetProtocol.FLOWER_BLOOM, 15.0), "튤립이 활짝 핀다")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.PICK, 2.0), "핀 꽃 곁에서 '꽃 따기'")
	var picked: Array = []
	Net.flower_picked.connect(func(item_id: String) -> void: picked.append(item_id), CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not picked.is_empty(), 3.0) and picked[0] == "tulip", "튤립을 땄다")
	await get_tree().create_timer(0.9).timeout

	# 박물관: 붕어 기증 → 수조에서 헤엄
	await _teleport(GameData.museum.keeper_position + Vector3(1.2, 0.1, 1.2))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK and interaction.target_id == "curator", 2.0), "관장 곁에서 '대화'")
	interaction.action_hud.action_pressed.emit()
	_check(await _advance_until_choices(box), "관장이 메뉴를 보여 줌")
	await _choose(box, 0)
	_check(await _wait_until(func() -> bool: return museum_window.is_open() and museum_window.mode == MuseumWindow.MODE_DONATE, 2.0), "기증 창이 열림")
	_check(museum_window.entry_count() >= 1, "가방 속 기증할 물고기 %d종" % museum_window.entry_count())
	var donated: Array = []
	Net.donated.connect(func(fish_id: String, reward: int, _c: int, _g: PackedStringArray) -> void: donated.append([fish_id, reward]), CONNECT_ONE_SHOT)
	museum_window.donate_requested.emit(_slot_of("crucian"))
	_check(await _wait_until(func() -> bool: return not donated.is_empty(), 3.0) and donated[0][0] == "crucian", "붕어를 기증했다: %s" % str(donated))
	_check(await _wait_until(func() -> bool: return museum._swimmers.has("crucian"), 2.0), "박물관 수조에서 붕어가 헤엄친다")
	museum_window.close()
	await _advance_until_closed(box, dialogue)

	# 공항: 해바라기 씨앗 사기
	await _teleport(GameData.airport.keeper_position + Vector3(1.2, 0.1, 1.2))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK and interaction.target_id == "pilot", 2.0), "조종사 곁에서 '대화'")
	interaction.action_hud.action_pressed.emit()
	_check(await _advance_until_choices(box), "조종사가 메뉴를 보여 줌")
	await _choose(box, 0)
	_check(await _wait_until(func() -> bool: return shop_window.is_open() and shop_window.at == ShopWindow.AT_AIRPORT, 2.0), "공항 기념품 가게 창")
	_check(shop_window.row_count() == GameData.airport.stock.size(), "기념품 %d가지" % shop_window.row_count())
	Net.buy_item("seed_sunflower", 1, ShopWindow.AT_AIRPORT)
	_check(await _wait_until(func() -> bool: return _slot_of("seed_sunflower") >= 0, 3.0), "해바라기 씨앗을 샀다")
	shop_window.close()
	await _advance_until_closed(box, dialogue)
	_check(airport.seconds_until_takeoff(Net.game_ms() / 1000.0) > 0.0, "다음 비행기 시각을 알려 줄 수 있다")


func _advance_until_choices(box: DialogueBox) -> bool:
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 100:
		if choices.visible and choices.get_child_count() > 0:
			return true
		if box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
	return false


func _choose(box: DialogueBox, index: int) -> void:
	var choices: VBoxContainer = box.get_node("%Choices")
	(choices.get_child(index) as Button).pressed.emit()
	await get_tree().process_frame


func _advance_until_closed(box: DialogueBox, dialogue: DialogueController) -> void:
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 150:
		if not dialogue.is_active():
			return
		if choices.visible and choices.get_child_count() > 0:
			(choices.get_child(choices.get_child_count() - 1) as Button).pressed.emit()
		elif box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
