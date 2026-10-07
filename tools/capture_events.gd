extends Node
## 이벤트 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). 실제 렌더러가 필요하다. tools/capture_events.sh 가 서버를 띄운다.
##   --mode=merchant : 이벤트 알림판 · 이벤트 카드 · 누리의 노점 · 누리와 대화 · 떠돌이 상인 창
##   --mode=bargain  : 특가 매입의 날 상점 팔기 창 (×2 표시)
##   --mode=gift     : 선물 풍선 · 넘어지는 나무 · 낚싯대를 던져 날아가는 찌
##   --mode=meteor   : 유성우 밤 · 별 조각
## 인자: -- --server=ws://… --mode=… --out=/tmp/shots

var _server: String = "ws://127.0.0.1:8080"
var _mode: String = "merchant"
var _out: String = "user://shots"
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	Net.create_room(_server)
	await Net.welcomed
	match _mode:
		"merchant":
			await _merchant()
		"bargain":
			await _bargain()
		"gift":
			await _gift()
		"meteor":
			await _meteor()
		"visitor":
			await _visitor()
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, file])
	print("[capture] %s/%s.png" % [_out, file])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await _wait(0.05)
		waited += 0.05
	return cond.call()


func _snap_camera() -> void:
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()


func _chop(tree_id: String, times: int) -> void:
	var player: Player = _village.get_node("Player")
	var trees: TreeField = _village.get_node("Trees")
	var interaction: InteractionController = _village.get_node("InteractionController")
	Net.equip(1)
	await _wait_until(func() -> bool: return player.held_item == "axe", 2.0)
	player.global_position = trees.tree_position(tree_id) + Vector3(1.3, 0.1, 0.4)
	_snap_camera()
	for i: int in times:
		await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.CHOP and interaction.target_id == tree_id, 2.0)
		var done: Array = [false]
		Net.chop_succeeded.connect(func(_t: String, _i: String, _f: bool) -> void: done[0] = true, CONNECT_ONE_SHOT)
		interaction.action_hud.action_pressed.emit()
		if not await _wait_until(func() -> bool: return done[0], 3.0):
			print("[capture] chop %s failed (target=%s)" % [tree_id, interaction.target_id])
		if i < times - 1:
			await _wait(0.5)


func _advance_until_choices(box: DialogueBox) -> void:
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 80:
		if choices.visible and choices.get_child_count() > 0:
			return
		if box.is_open():
			box.press()
		await _wait(0.1)


## v0.12 광장 손님: 중고 가구상 바우 (노점에 선 모습 · 이벤트 카드 · 30% 싸게 파는 보따리).
func _visitor() -> void:
	var player: Player = _village.get_node("Player")
	var merchant: MerchantStall = _village.get_node("Merchant")
	var event_hud: EventHud = _village.get_node("HUD/EventHud")
	var shop_window: ShopWindow = _village.get_node("HUD/ShopWindow")
	await _wait_until(func() -> bool: return merchant.is_open() and merchant.npc_id() == "bau", 5.0)
	player.global_position = merchant.actor.global_position + Vector3(1.0, 0.1, 1.2)
	Net.equip(-1)
	_snap_camera()
	await _wait(1.2)
	await _shot("e21_visitor_stall")
	event_hud.toggle_card()
	await _wait(0.4)
	await _shot("e22_visitor_card")
	event_hud.toggle_card()
	shop_window.open(ShopWindow.MODE_BUY, ShopWindow.AT_MERCHANT)
	await _wait(0.6)
	await _shot("e23_visitor_shop")
	shop_window.close()


func _merchant() -> void:
	var player: Player = _village.get_node("Player")
	var merchant: MerchantStall = _village.get_node("Merchant")
	var event_hud: EventHud = _village.get_node("HUD/EventHud")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var shop_window: ShopWindow = _village.get_node("HUD/ShopWindow")
	player.global_position = merchant.actor.global_position + Vector3(2.0, 0.1, 2.4)
	_snap_camera()
	await _wait(0.9)
	await _shot("e01_event_banner")
	await _wait(5.0)
	event_hud.toggle_card()
	await _wait(0.4)
	await _shot("e02_event_card")
	event_hud.toggle_card()
	await _chop("t01", 2)
	player.global_position = merchant.actor.global_position + Vector3(1.0, 0.1, 1.2)
	_snap_camera()
	Net.equip(-1)
	await _wait(1.0)
	await _shot("e03_merchant_stall")
	await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK, 2.0)
	interaction.action_hud.action_pressed.emit()
	await _advance_until_choices(box)
	await _wait(0.5)
	await _shot("e04_merchant_talk")
	((box.get_node("%Choices") as VBoxContainer).get_child(1) as Button).pressed.emit()
	await _wait(0.8)
	await _shot("e05_merchant_sell")
	shop_window.set_mode(ShopWindow.MODE_BUY)
	await _wait(0.5)
	await _shot("e06_merchant_buy")


func _bargain() -> void:
	var player: Player = _village.get_node("Player")
	var shop_window: ShopWindow = _village.get_node("HUD/ShopWindow")
	await _chop("t01", 2)
	player.global_position = GameData.shop.outside_spawn + Vector3(0.0, 0.1, 0.0)
	await _wait(0.4)
	var inside: Array = [false]
	Net.shop_door_passed.connect(func(now_inside: bool, _p: Vector3) -> void: inside[0] = now_inside)
	Net.enter_shop()
	if not await _wait_until(func() -> bool: return inside[0], 3.0):
		print("[capture] shop enter failed")
	await _wait(0.5)
	shop_window.open(ShopWindow.MODE_SELL)
	await _wait(0.6)
	await _shot("e07_bargain_sell")


func _gift() -> void:
	var player: Player = _village.get_node("Player")
	var trees: TreeField = _village.get_node("Trees")
	await _wait_until(func() -> bool: return Net.drops.size() >= 3, 15.0)
	var drop: DropInfo = Net.drops.values()[0]
	player.global_position = drop.position + Vector3(1.6, 0.1, 1.8)
	_snap_camera()
	await _wait(6.0)
	await _shot("e08_gift_balloon")
	# 나무가 넘어지는 중간
	var falling: Array = [false]
	trees.child_entered_tree.connect(func(node: Node) -> void:
		if node.name.begins_with("Falling_"):
			falling[0] = true)
	await _chop("t24", 3)
	await _wait_until(func() -> bool: return falling[0], 2.0)
	await _wait(0.62)
	await _shot("e09_tree_falling")
	await _wait(0.4)
	await _shot("e10_tree_landed")
	# 낚싯대를 던져 찌가 날아가는 중
	Net.equip(0)
	await _wait_until(func() -> bool: return player.held_item == "rod", 2.0)
	player.global_position = Vector3(-10.6, 0.1, 5.5)
	player.body.rotation.y = PI * 0.25
	_snap_camera()
	await _wait(0.8)
	var fishing: FishingController = _village.get_node("FishingController")
	fishing.hud.action_pressed.emit()
	await Net.fish_started
	await _wait(0.45)
	await _shot("e11_cast_flight")
	await _wait(0.5)
	await _shot("e12_bobber_landed")
	# v0.11: 물 밑 그림자가 다가옴 → 물고 들어감 → 끌어올리기 연타
	await _wait(2.5)
	await _shot("e13_fish_shadow")
	await _wait_until(func() -> bool: return fishing.is_bite_visible(), 40.0)
	await _wait(0.12)
	await _shot("e14_bite_sink")
	fishing.hud.action_pressed.emit()
	await _wait_until(func() -> bool: return fishing.phase == FishingController.Phase.REEL, 3.0)
	for i: int in 3:
		fishing.hud.action_pressed.emit()
		await _wait(0.12)
	await _shot("e15_reel_mash")


func _meteor() -> void:
	var player: Player = _village.get_node("Player")
	await _wait_until(func() -> bool: return Net.drops.size() >= 2, 15.0)
	var drop: DropInfo = Net.drops.values()[0]
	player.global_position = drop.position + Vector3(1.4, 0.1, 1.6)
	_snap_camera()
	await _wait(6.0)
	await _shot("e13_meteor_night")
