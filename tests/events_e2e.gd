extends Node
## 이벤트 종단 테스트 (서버 둘: 떠돌이 상인의 날 / 선물 풍선의 날, 둘 다 한낮으로 맞춤).
##   A. 떠돌이 상인: 이벤트 칩·알림판 → 광장에 노점 → 목재를 베어 누리에게 2배 값에 팔기 → 보따리 물건 사기
##   B. 선물 풍선: 선물이 내려앉음 → 가까이 가서 줍기 · 나무를 쓰러뜨리면 넘어지는 연출 ·
##      상점 문으로 걸어 들어가고 걸어 나오기 (문 밖 허공으로 빠져나가지 않음)
## tests/run_events_e2e.sh 가 서버를 띄운다. 인자: -- --server-a=ws://… --server-b=ws://…

var _servers: Dictionary[String, String] = {}
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server-a="):
			_servers["a"] = arg.trim_prefix("--server-a=")
		elif arg.begins_with("--server-b="):
			_servers["b"] = arg.trim_prefix("--server-b=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _merchant_day()
	Net.leave()
	await get_tree().create_timer(0.3).timeout
	await _gift_day()
	for f: String in _failures:
		print("[events] FAIL: %s" % f)
	print("[events] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[events] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _slot_of(item_id: String) -> int:
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == item_id:
			return i
	return -1


## 둥근 나무 하나를 n 번 찍는다.
func _chop(tree_id: String, times: int) -> void:
	var player: Player = _village.get_node("Player")
	var trees: TreeField = _village.get_node("Trees")
	var interaction: InteractionController = _village.get_node("InteractionController")
	Net.equip(1)
	await _wait_until(func() -> bool: return player.held_item == "axe", 2.0)
	player.global_position = trees.tree_position(tree_id) + Vector3(1.3, 0.1, 0.0)
	# 순간이동한 자리가 서버에 닿은 뒤 찍는다 (위치는 20Hz 로 보내므로 찍기 요청이 먼저 가면 not_near_tree).
	await get_tree().create_timer(0.2).timeout
	for i: int in times:
		await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP and interaction.target_id == tree_id, 2.0)
		interaction.action_hud.action_pressed.emit()
		await Net.chop_succeeded
		await get_tree().create_timer(0.5).timeout


func _merchant_day() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var dialogue: DialogueController = _village.get_node("DialogueController")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var shop_window: ShopWindow = _village.get_node("HUD/ShopWindow")
	var event_hud: EventHud = _village.get_node("HUD/EventHud")
	var merchant: MerchantStall = _village.get_node("Merchant")

	Net.create_room(_servers["a"])
	await Net.welcomed
	_check(Net.event_active(EventInfo.MERCHANT) != null, "서버가 정한 오늘의 이벤트: 떠돌이 상인")
	await get_tree().process_frame
	_check(event_hud.chip_text() == "떠돌이 상인 누리", "위쪽에 이벤트 칩 (%s)" % event_hud.chip_text())
	_check(event_hud.banner_text() == "떠돌이 상인 누리", "들어오면 이벤트 알림판이 내려옴")
	event_hud.toggle_card()
	_check(" ".join(event_hud.card_lines()).contains("목재"), "칩을 누르면 오늘 찾는 물건(목재 ×2)이 보임")
	event_hud.toggle_card()
	_check(merchant.is_open() and merchant.actor.global_position.distance_to(GameData.event_info(EventInfo.MERCHANT).spot) < 0.5, "광장에 누리의 노점이 섬")

	# 둥근 나무에서 나오는 것(목재·단단한 목재·가지·도토리·버섯)을 모두 찾는 날로 띄웠다.
	var wanted: PackedStringArray = Net.event_active(EventInfo.MERCHANT).wanted
	await _chop("t01", 1)
	var got: Array[String] = [""]
	_check(await _wait_until(func() -> bool:
		for id: String in wanted:
			if _count(id) > 0:
				got[0] = id
				return true
		return false, 2.0), "누리가 찾는 물건을 구함 (%s)" % got[0])
	var sol_before: int = Net.sol
	player.global_position = merchant.actor.global_position + Vector3(1.2, 0.1, 0.8)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK and interaction.target_id == merchant.npc_id(), 2.0), "누리 곁에서 '대화'")
	interaction.action_hud.action_pressed.emit()
	_check(await _advance_until_choices(box), "누리가 인사하고 메뉴를 보여 줌")
	await _choose(box, 1)  # 찾는 물건 팔래요
	_check(await _wait_until(func() -> bool: return shop_window.is_open() and shop_window.at == ShopWindow.AT_MERCHANT, 2.0), "상점 창이 떠돌이 상인 모드로 열림")
	_check(shop_window.row_count() == 1, "찾는 물건만 팔 수 있음 (%d줄)" % shop_window.row_count())
	var traded: Array = []
	Net.shop_traded.connect(func(kind: String, item: String, n: int, amount: int) -> void: traded.append([kind, item, n, amount]), CONNECT_ONE_SHOT)
	var price: int = GameData.item(got[0]).price * 2
	Net.sell_item(_slot_of(got[0]), 1, ShopWindow.AT_MERCHANT)
	_check(await _wait_until(func() -> bool: return not traded.is_empty(), 3.0) and traded[0][3] == price, "하나를 2배 값(%d솔)에 팖 %s" % [price, str(traded)])
	shop_window.set_mode(ShopWindow.MODE_BUY)
	_check(shop_window.row_count() == GameData.event_info(EventInfo.MERCHANT).stock.size(), "보따리 물건 %d가지" % shop_window.row_count())
	traded.clear()
	Net.shop_traded.connect(func(kind: String, item: String, n: int, amount: int) -> void: traded.append([kind, item, n, amount]), CONNECT_ONE_SHOT)
	Net.buy_item("toy_windmill", 1, ShopWindow.AT_MERCHANT)
	_check(await _wait_until(func() -> bool: return _count("toy_windmill") == 1, 3.0), "바람개비를 삼")
	_check(Net.sol == sol_before + price - GameData.item("toy_windmill").buy_price, "솔 계산 (%d)" % Net.sol)
	shop_window.close()
	await _advance_until_closed(box, dialogue)
	_check(not dialogue.is_active() and not player.is_input_locked(), "대화가 끝나면 다시 움직임")


func _gift_day() -> void:
	var player: Player = _village.get_node("Player")
	var trees: TreeField = _village.get_node("Trees")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var drops: DropField = _village.get_node("Drops")
	var shop: ShopController = _village.get_node("Shop")
	var merchant: MerchantStall = _village.get_node("Merchant")

	Net.create_room(_servers["b"])
	await Net.welcomed
	_check(Net.event_active(EventInfo.GIFT_DAY) != null and not merchant.is_open(), "다른 마을: 선물 풍선의 날 (상인은 없음)")
	_check(await _wait_until(func() -> bool: return not Net.drops.is_empty(), 5.0), "선물 풍선이 내려앉음")
	var drop: DropInfo = Net.drops.values()[0]
	_check(drops.has_drop(drop.id), "선물 상자가 보임")
	player.global_position = drop.position + Vector3(0.8, 0.1, 0.0)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.COLLECT and interaction.target_id == drop.id, 2.0), "선물 곁에서 '선물 줍기'")
	var got: Array = []
	Net.collected.connect(func(kind: String, item: String) -> void: got.append([kind, item]), CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not got.is_empty(), 3.0), "선물을 주움: %s" % str(got))
	_check(not got.is_empty() and _count(got[0][1]) >= 1, "선물 속 물건이 가방에")
	_check(await _wait_until(func() -> bool: return not drops.has_drop(drop.id), 2.0), "주운 선물은 사라짐")

	# 나무를 쓰러뜨리면 넘어지는 연출이 나온다.
	var tree_id: String = "t24"
	var fell_seen: Array = [false]
	trees.child_entered_tree.connect(func(node: Node) -> void:
		if node.name == "Falling_%s" % tree_id:
			fell_seen[0] = true)
	await _chop(tree_id, 3)
	_check(await _wait_until(func() -> bool: return fell_seen[0], 2.0), "세 번째 도끼질에 나무가 넘어지는 연출")
	_check(trees.stage_of(tree_id) == NetProtocol.TREE_STUMP, "제자리엔 그루터기")
	Net.equip(0)

	# 상점: 문 쪽으로 걸어가면 들어가고, 안에서 문 쪽으로 걸어가면 밖으로 나온다.
	player.global_position = GameData.shop.outside_spawn + Vector3(0.0, 0.1, 0.0)
	await get_tree().create_timer(0.4).timeout
	var passed: Array = []
	Net.shop_door_passed.connect(func(inside: bool, _p: Vector3) -> void: passed.append(inside))
	Input.action_press("ui_up")
	_check(await _wait_until(func() -> bool: return passed.has(true), 4.0), "문 쪽으로 걸어가면 상점 안으로")
	Input.action_release("ui_up")
	await get_tree().create_timer(0.5).timeout
	_check(shop.is_inside(player.global_position), "상점 안에 있음")
	Input.action_press("ui_down")
	_check(await _wait_until(func() -> bool: return passed.has(false), 4.0), "안에서 문 쪽으로 걸어가면 밖으로")
	Input.action_release("ui_down")
	await get_tree().create_timer(0.3).timeout
	var out: Vector3 = player.global_position
	_check(not shop.is_inside(out) and out.distance_to(GameData.shop.outside_spawn) < 2.5, "문 밖 광장으로 나옴 (허공이 아님): %s" % str(out))


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
	(choices.get_child(index) as Button).pressed.emit()
	await get_tree().process_frame


func _advance_until_closed(box: DialogueBox, dialogue: DialogueController) -> void:
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 120:
		if not dialogue.is_active():
			return
		if choices.visible and choices.get_child_count() > 0:
			(choices.get_child(choices.get_child_count() - 1) as Button).pressed.emit()
		elif box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
