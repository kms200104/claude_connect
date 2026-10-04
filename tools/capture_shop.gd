extends Node
## 상점·옷·가구 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). 실제 렌더러가 필요하다.
## 사용: 서버를 WEATHER_FORCE=clear START_SOL=4000000 MOVE_SLACK_M=200 DOOR_GRACE_MS=0 으로 띄운 뒤
##   godot --path . res://tools/capture_shop.tscn -- --server=ws://127.0.0.1:8080 --out=/tmp/shots

var _server: String = "ws://127.0.0.1:8080"
var _out: String = "user://shots"
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await _run()
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, file])
	print("[capture] %s/%s.png" % [_out, file])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## 서버 응답을 기다린다. 거부되거나 3초가 지나면 그만 기다린다.
func _reply(sig: Signal) -> void:
	var state: Dictionary = {"done": false}
	var finish: Callable = func(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void: state["done"] = true
	sig.connect(finish, CONNECT_ONE_SHOT)
	Net.request_failed.connect(finish, CONNECT_ONE_SHOT)
	var waited: float = 0.0
	while not state["done"] and waited < 3.0:
		await _wait(0.05)
		waited += 0.05
	if sig.is_connected(finish):
		sig.disconnect(finish)
	if Net.request_failed.is_connected(finish):
		Net.request_failed.disconnect(finish)


func _buy(item_id: String, times: int = 1) -> void:
	for i: int in times:
		Net.buy_item(item_id, 1)
		await _reply(Net.shop_traded)


func _slot_of(item_id: String) -> int:
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == item_id:
			return i
	return -1


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var sky: SkyController = _village.get_node("SkyController")
	var shop: ShopController = _village.get_node("Shop")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var window: ShopWindow = _village.get_node("HUD/ShopWindow")
	var inventory: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	sky.debug_hour = 11.0
	Net.create_room(_server)
	await Net.welcomed

	# 1. 구멍가게 겉모습 (건물 전체가 들어오게 카메라를 잠깐 뒤로 뺀다)
	var camera_rig: FollowCamera = _village.get_node("CameraRig")
	var normal_distance: float = camera_rig.distance
	camera_rig.distance = 13.0
	player.global_position = GameData.shop.door + Vector3(1.2, 0.1, 3.0)
	player.body.rotation.y = 0.0
	await _wait(2.0)
	await _shot("s01_shop_lv1_outside")
	camera_rig.distance = normal_distance

	# 2. 실내 + 주인
	player.global_position = GameData.shop.door + Vector3(0.0, 0.1, 1.0)
	await _wait(0.6)
	interaction.action_hud.action_pressed.emit()
	await _reply(Net.shop_door_passed)
	player.global_position = shop.keeper.global_position + Vector3(0.6, 0.1, 2.6)
	await _wait(1.0)
	await _shot("s02_shop_lv1_inside")

	# 3. 주인과 대화 → 사기 창
	player.global_position = shop.keeper.global_position + Vector3(0.0, 0.1, 1.9)
	await _wait(0.5)
	interaction.action_hud.action_pressed.emit()
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 60:
		if choices.visible:
			break
		box.press()
		await _wait(0.15)
	await _wait(0.4)
	await _shot("s03_keeper_menu")
	(choices.get_child(0) as Button).pressed.emit()
	await _wait(0.5)
	await _shot("s04_shop_window_buy_lv1")

	# 4. 사면 포인트가 쌓여 잡화점으로
	await _buy("wood_chair", 3)
	await _wait(0.6)
	await _shot("s05_shop_level_up")

	# 5. 더 사서 백화점으로
	await _buy("bookshelf", 2)
	await _buy("bench", 1)
	await _wait(0.4)
	await _buy("formal_vest", 1)
	await _buy("flower_hat", 1)
	await _buy("fountain", 1)
	await _buy("flower_pot", 2)
	window.set_mode(ShopWindow.MODE_BUY)
	await _wait(0.5)
	await _shot("s06_shop_window_buy_lv3")
	window.close()
	for i: int in 30:
		if choices.visible:
			break
		box.press()
		await _wait(0.15)
	(choices.get_child(3) as Button).pressed.emit()
	for i: int in 20:
		if box.is_open():
			box.press()
		await _wait(0.15)
	player.global_position = shop.keeper.global_position + Vector3(1.5, 0.1, 3.8)
	await _wait(1.0)
	await _shot("s07_shop_lv3_inside")

	# 6. 백화점 겉모습
	player.global_position = GameData.shop.exit + Vector3(0.0, 0.1, -0.4)
	await _wait(0.5)
	interaction.action_hud.action_pressed.emit()
	await _reply(Net.shop_door_passed)
	camera_rig.distance = 15.0
	player.global_position = GameData.shop.door + Vector3(0.5, 0.1, 3.5)
	player.body.rotation.y = 0.0
	await _wait(1.5)
	await _shot("s08_shop_lv3_outside")
	camera_rig.distance = normal_distance

	# 7. 옷 입고 가구 놓기
	Net.wear(_slot_of("flower_hat"))
	await _reply(Net.profile_updated)
	Net.wear(_slot_of("formal_vest"))
	await _reply(Net.profile_updated)
	player.global_position = Vector3(10.0, 0.1, 15.0)
	await _wait(0.5)
	for spec: Array in [["fountain", Vector3(10.0, 0.0, 12.5)], ["bench", Vector3(12.5, 0.0, 14.0)], ["flower_pot", Vector3(8.0, 0.0, 14.0)], ["flower_pot", Vector3(11.5, 0.0, 13.0)], ["bookshelf", Vector3(8.0, 0.0, 16.5)]]:
		Net.place_furniture(_slot_of(spec[0]), spec[1], 0)
		await _reply(Net.furniture_placed)
	player.body.rotation.y = PI
	await _wait(1.5)
	await _shot("s09_outfit_and_furniture")

	# 8. 가방 창: 옷 칸
	inventory.open()
	inventory.press_slot(_slot_of("wood_chair"))
	await _wait(1.0)
	await _shot("s10_inventory_outfit")
	inventory.close()
