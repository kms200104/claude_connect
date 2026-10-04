extends Node
## 상점·달리기·옷·가구 종단 테스트(클라이언트 1개). tests/run_shop_e2e.sh 가 서버를
## WEATHER_FORCE=rain SHOP_POINTS_SCALE=20 START_SOL=2000 MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0 으로 띄운다.
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
		print("[shop] FAIL: %s" % f)
	print("[shop] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[shop] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var joystick: TouchJoystick = _village.get_node("HUD/Joystick")
	var shop: ShopController = _village.get_node("Shop")
	var sky: SkyController = _village.get_node("SkyController")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var dialogue: DialogueController = _village.get_node("DialogueController")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var window: ShopWindow = _village.get_node("HUD/ShopWindow")
	var inventory: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	var furniture: FurnitureField = _village.get_node("Furniture")

	Net.create_room(_server)
	await Net.welcomed
	_check(Net.sol == 2000 and Net.shop_level == 1, "솔 2000, 상점 1단계(구멍가게)로 시작")
	_check(shop.level == 1 and shop.level_name() == "솔바람 구멍가게", "광장에 구멍가게")

	# ---- 달리기: 조이스틱을 끝까지 0.7초 ----
	player.global_position = Vector3(20.0, 0.1, -40.0)
	await get_tree().create_timer(0.3).timeout
	joystick.output = Vector2(0.0, -1.0)
	await get_tree().create_timer(0.45).timeout
	_check(not player.running, "0.45초 동안은 걷는다")
	var walk_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	await get_tree().create_timer(0.6).timeout
	var run_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	_check(player.running and run_speed > 6.0, "0.7초가 지나면 달린다 (걷기 %.1f → 달리기 %.1fm/s)" % [walk_speed, run_speed])
	_check(joystick.boost, "달리는 동안 조이스틱 테두리가 주황빛")
	_check(await _wait_until(func() -> bool: return player.rig._move_value > 1.4, 1.0), "run 애니메이션으로 블렌드 (%.2f)" % player.rig._move_value)
	joystick.output = Vector2(0.0, -0.5)
	await get_tree().create_timer(0.3).timeout
	_check(not player.running, "덜 밀면 다시 걷는다")
	joystick.output = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	_check(Net.state == Net.State.ONLINE, "달려도 서버가 위치를 되돌리지 않음")

	# 팔 물건 마련: 둥근 나무 두 그루
	_village.get_node("HUD/Hotbar").slot_button(1).pressed.emit()
	for tree_id: String in ["t13", "t15"]:
		player.global_position = GameData.trees[tree_id].position + Vector3(1.3, 0.1, 0.0)
		await get_tree().create_timer(0.3).timeout  # 새 위치가 서버에 닿을 때까지
		for i: int in 3:
			await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP, 2.0)
			interaction.action_hud.action_pressed.emit()
			await _reply(Net.chop_succeeded)
	await get_tree().create_timer(0.3).timeout

	# ---- 상점 들어가기 ----
	player.global_position = GameData.shop.door + Vector3(0.0, 0.1, 1.0)
	await get_tree().create_timer(0.3).timeout
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.ENTER_SHOP, 2.0), "상점 문 앞에서 '들어가기' 버튼")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return shop.is_inside(player.global_position), 3.0), "서버가 실내로 옮겨 줌 (z=%.1f)" % player.global_position.z)
	await get_tree().create_timer(0.3).timeout
	_check(sky.indoor and not sky.rain.visible, "실내에서는 비가 안 보임 (밖은 비)")
	var camera: Camera3D = _village.get_node("CameraRig/Camera3D")
	_check(camera.global_position.distance_to(player.global_position) < 15.0, "카메라가 마을을 가로지르지 않고 바로 따라옴")

	# ---- 상점 주인과 대화 → 팔기 ----
	player.global_position = shop.keeper.global_position + Vector3(0.0, 0.1, 1.9)
	await get_tree().create_timer(0.3).timeout
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK and interaction.target_id == GameData.shop.keeper.id, 2.0), "상점 주인 앞에서 '대화'")
	interaction.action_hud.action_pressed.emit()
	_check(await _advance_until_choices(box) and _choice_count(box) == 4, "인사 뒤 사기·팔기·가게 이야기·그만 선택지")
	await _choose(box, 1)
	_check(window.is_open() and window.mode == ShopWindow.MODE_SELL and window.row_count() > 0, "상점 창이 '팔기'로 열림 (%d줄)" % window.row_count())
	var sol_before: int = Net.sol
	# 팔 수 있는 줄마다 "모두" 또는 "1개" 버튼을 누른다
	for guard: int in 10:
		var button: Button = _first_sell_button(window)
		if button == null:
			break
		button.pressed.emit()
		await _reply(Net.shop_traded)
		await get_tree().create_timer(0.1).timeout
	_check(Net.sol > sol_before, "팔아서 솔이 늘어남 (%d → %d)" % [sol_before, Net.sol])
	_check(await _wait_until(func() -> bool: return Net.shop_level >= 2, 2.0), "상점 포인트가 차서 상점이 커짐 (Lv.%d, %d포인트)" % [Net.shop_level, Net.shop_points])
	_check(await _wait_until(func() -> bool: return shop.level == Net.shop_level, 1.0), "건물·실내가 새 단계로 다시 지어짐 (%s)" % shop.level_name())

	# ---- 사기 ----
	window.set_mode(ShopWindow.MODE_BUY)
	await get_tree().process_frame
	_check(window.row_count() == GameData.shop.stock_for(Net.shop_level).size(), "사기 목록 = 지금 단계까지 진열품 %d개" % window.row_count())
	for item_id: String in ["straw_hat", "log_stool"]:
		var sol_now: int = Net.sol
		var buy: Button = _buy_button(window, item_id)
		_check(buy != null and not buy.disabled, "%s '사기' 버튼" % GameData.item_name(item_id))
		if buy != null:
			buy.pressed.emit()
		await _reply(Net.shop_traded)
		_check(await _wait_until(func() -> bool: return _slot_of(item_id) >= 0, 2.0) and Net.sol == sol_now - GameData.item(item_id).buy_price, "%s 구매 (%d솔)" % [GameData.item_name(item_id), GameData.item(item_id).buy_price])
	window.close()
	await _advance_until_choices(box)
	await _choose(box, 3)
	await _advance_until_closed(box, dialogue)
	_check(not dialogue.is_active() and not player.is_input_locked(), "대화가 끝나면 움직일 수 있음")

	# ---- 나가기 ----
	player.global_position = GameData.shop.exit + Vector3(0.0, 0.1, -0.5)
	await get_tree().create_timer(0.3).timeout
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.EXIT_SHOP, 2.0), "출구에서 '나가기'")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not shop.is_inside(player.global_position), 3.0) and not sky.indoor, "밖으로 나옴 (다시 비가 보임)")

	# ---- 옷 입기 ----
	inventory.open()
	inventory.press_slot(_slot_of("straw_hat"))
	var use: Button = inventory.get_node("%UseButton")
	_check(use.visible and use.text == "입기", "모자를 고르면 '입기' 버튼")
	use.pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.outfit_hat == "straw_hat", 2.0), "밀짚모자를 씀 (서버 확정)")
	_check(player.rig.outfit_item("hat") == "straw_hat" and inventory.preview().rig.outfit_item("hat") == "straw_hat", "내 캐릭터와 가방 창 미리보기에 모자가 보임")
	_check(_slot_of("straw_hat") < 0, "입은 모자는 가방에서 빠짐")

	# ---- 가구 설치 · 줍기 ----
	inventory.close()
	player.global_position = Vector3(16.0, 0.1, 8.0)
	player.body.rotation.y = 0.0
	await get_tree().create_timer(0.3).timeout
	inventory.open()
	inventory.press_slot(_slot_of("log_stool"))
	_check(use.visible and use.text == "설치하기", "가구를 고르면 '설치하기' 버튼")
	use.pressed.emit()
	_check(await _wait_until(func() -> bool: return not Net.placed.is_empty(), 2.0), "통나무 스툴을 앞에 놓음")
	var placed: PlacedInfo = Net.placed.values()[0] if not Net.placed.is_empty() else null
	_check(placed != null and placed.position.distance_to(Vector3(16.0, 0.0, 6.5)) < 0.6 and furniture.has_furniture(placed.id), "캐릭터 앞 1.5m, 0.5m 격자에 생김")
	_check(not inventory.is_open() and _slot_of("log_stool") < 0, "설치하면 가방 창이 닫히고 가방에서 빠짐")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.PICKUP, 2.0), "내 가구 곁에서 '줍기'")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.placed.is_empty() and _slot_of("log_stool") >= 0, 2.0), "주우면 다시 가방으로")


## 서버 응답 신호를 기다린다. 요청이 거부되거나 3초가 지나면 그만 기다린다 (테스트가 멈추지 않게).
func _reply(sig: Signal) -> void:
	var state: Dictionary = {"done": false}
	var finish: Callable = func(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void: state["done"] = true
	sig.connect(finish, CONNECT_ONE_SHOT)
	Net.request_failed.connect(finish, CONNECT_ONE_SHOT)
	await _wait_until(func() -> bool: return state["done"], 3.0)
	if sig.is_connected(finish):
		sig.disconnect(finish)
	if Net.request_failed.is_connected(finish):
		Net.request_failed.disconnect(finish)


func _first_sell_button(window: ShopWindow) -> Button:
	for row: Node in window.get_node("%List").get_children():
		for child: Node in row.get_children():
			if child is Button and (child as Button).text in ["모두", "1개"]:
				return child
	return null


func _buy_button(window: ShopWindow, item_id: String) -> Button:
	var name_text: String = GameData.item_name(item_id)
	for row: Node in window.get_node("%List").get_children():
		var has_name: bool = false
		for label: Node in row.find_children("*", "Label", true, false):
			if (label as Label).text == name_text:
				has_name = true
		if has_name:
			for child: Node in row.get_children():
				if child is Button and (child as Button).text == "사기":
					return child
	return null


func _choice_count(box: DialogueBox) -> int:
	return box.get_node("%Choices").get_child_count()


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
	var button: Button = box.get_node("%Choices").get_child(index) as Button
	button.pressed.emit()
	await get_tree().process_frame


func _advance_until_closed(box: DialogueBox, dialogue: DialogueController) -> void:
	for i: int in 80:
		if not dialogue.is_active():
			return
		if box.is_open():
			box.press()
		await get_tree().create_timer(0.1).timeout
