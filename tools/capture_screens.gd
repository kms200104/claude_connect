extends Node
## 기능별 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). 실제 렌더러가 필요해서 헤드리스로는 못 돌린다.
## 사용: 서버를 WEATHER_FORCE=clear QUEST_CHANCE=1 MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 으로 띄운 뒤
##   godot --path . res://tools/capture_screens.tscn -- --server=ws://127.0.0.1:8080 --out=/tmp/shots

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
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_out, file])
	print("[capture] %s/%s.png" % [_out, file])


## 연출 확인용: 서버 시계 대신 이 시각·날씨로 하늘과 위쪽 막대를 맞춘다.
func _set_scene(sky: SkyController, top_bar: TopBar, hour: float, weather: String) -> void:
	sky.debug_hour = hour
	Net.weather = weather
	Net.weather_changed.emit(weather)
	top_bar.set_process(false)
	(top_bar.get_node("%ClockLabel") as Label).text = VillageClock.format_time(hour)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var sky: SkyController = _village.get_node("SkyController")
	var trees: TreeField = _village.get_node("Trees")
	var npcs: NpcCrowd = _village.get_node("Npcs")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var window: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	var hotbar: Hotbar = _village.get_node("HUD/Hotbar")
	var top_bar: TopBar = _village.get_node("HUD/TopBar")
	Net.create_room(_server)
	await Net.welcomed

	# 1. 맑은 아침, 목수 무진과 나무들
	_set_scene(sky, top_bar, 9.5, NetProtocol.WEATHER_CLEAR)
	player.global_position = Vector3(13.5, 0.1, 1.2)
	await _wait(2.5)
	await _shot("01_morning_clear")

	# 2. 도끼 들고 나무 베기
	hotbar.slot_button(1).pressed.emit()
	player.global_position = trees.tree_position("t23") + Vector3(1.3, 0.1, 0.4)
	await _wait(1.0)
	for i: int in 2:
		interaction.action_hud.action_pressed.emit()
		await Net.chop_succeeded
		await _wait(0.5)
	interaction.action_hud.action_pressed.emit()
	await _wait(0.12)
	await _shot("02_chop")
	await _wait(1.0)

	# 3. 비 오는 오후 호숫가
	_set_scene(sky, top_bar, 15.0, NetProtocol.WEATHER_RAIN)
	hotbar.slot_button(0).pressed.emit()
	player.global_position = Vector3(-9.5, 0.1, 3.0)
	await _wait(5.0)
	await _shot("03_rain_lake")

	# 4. 뇌우 번개
	_set_scene(sky, top_bar, 15.5, NetProtocol.WEATHER_THUNDER)
	await _wait(3.0)
	sky.strike(1.0)
	await _wait(0.05)
	await _shot("04_thunder_flash")

	# 5. 저녁 노을
	_set_scene(sky, top_bar, 18.4, NetProtocol.WEATHER_CLEAR)
	player.global_position = Vector3(2.0, 0.1, 15.0)
	await _wait(9.0)
	await _shot("05_sunset")

	# 6. 밤 광장 (가로등)
	_set_scene(sky, top_bar, 21.5, NetProtocol.WEATHER_CLEAR)
	player.global_position = Vector3(3.0, 0.1, 5.8)
	await _wait(2.0)
	await _shot("06_night_plaza")

	# 7. 주민 대화와 부탁
	_set_scene(sky, top_bar, 11.0, NetProtocol.WEATHER_CLEAR)
	var morak: NpcActor = npcs.actor("morak")
	player.global_position = morak.global_position + Vector3(1.6, 0.1, 0.6)
	await _wait(1.5)
	# 주민이 걸어가 버렸을 수 있으니 누르기 직전에 다시 곁으로.
	player.global_position = morak.global_position + Vector3(1.2, 0.1, 0.5)
	await _wait(0.3)
	interaction.action_hud.action_pressed.emit()
	var choices: VBoxContainer = box.get_node("%Choices")
	for i: int in 60:
		if choices.visible:
			break
		await _wait(0.25)
		if not choices.visible:
			box.press()
	await _wait(0.6)
	await _shot("07_dialogue_offer")
	(choices.get_child(0) as Button).pressed.emit()
	await _wait(0.4)
	for i: int in 20:
		if box.is_open():
			box.press()
		await _wait(0.2)
	(_village.get_node("HUD/TopBar/%QuestButton") as Button).pressed.emit()
	await _wait(0.5)
	await _shot("08_quest_log")
	(_village.get_node("HUD/TopBar/%QuestButton") as Button).pressed.emit()

	# 9. 가방 창: 목재를 고르면 캐릭터가 그 칸을 바라본다
	hotbar.bag_pressed.emit()
	await _wait(0.4)
	var wood_slot: int = -1
	for i: int in range(Net.quick_slot_count, Net.inventory.size()):
		if Net.inventory[i] != null and not GameData.item(Net.inventory[i].id).is_tool():
			wood_slot = i
			break
	if wood_slot >= 0:
		window.press_slot(wood_slot)
	await _wait(1.0)
	await _shot("09_inventory_look_bag")
	window.press_slot(wood_slot)
	window.press_slot(0)
	await _wait(1.0)
	await _shot("10_inventory_look_quickslot")
	window.close()
