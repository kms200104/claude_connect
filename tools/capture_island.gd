extends Node
## 섬 생활(v0.6) 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). 실제 렌더러가 필요하다. tools/capture_island.sh 가 서버를 띄운다.
##   --mode=places : 섬 하늘에서 · 박물관과 수조 · 공항과 이륙하는 비행기 · 바닷가 야자수
##   --mode=life   : 브레이크 미끄러짐 · 감정표현과 주민 반응 · 감정표현 창 · 대화(기분·주제) · 심고 자라는 나무와 꽃 · 박물관 도감
##   --mode=fish   : 물고기를 낚아 두 손으로 내밀고 자랑 (클로즈업 · 외침 카드)
## 인자: -- --server=ws://… --mode=… --out=/tmp/shots

var _server: String = "ws://127.0.0.1:8080"
var _mode: String = "places"
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
	await _wait(1.5)
	match _mode:
		"places":
			await _places()
		"life":
			await _life()
		"fish":
			await _fish()
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


func _camera() -> FollowCamera:
	return _village.get_node("CameraRig")


func _put(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	_camera().snap_to_target()
	await _wait(0.6)


func _slot_of(item_id: String) -> int:
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == item_id:
			return i
	return -1


## 요청을 보내고 성공 신호(인자 argc개)나 오류 중 먼저 오는 걸 기다린다 (실패해도 멈추지 않게).
func _request(send: Callable, ok: Signal, argc: int) -> void:
	var done: Array[bool] = [false]
	var finish: Callable = func() -> void: done[0] = true
	var on_ok: Callable = finish.unbind(argc)
	var on_error: Callable = func(code: String) -> void:
		print("[capture] request failed: %s" % code)
		done[0] = true
	ok.connect(on_ok)
	Net.error_received.connect(on_error)
	send.call()
	await _wait_until(func() -> bool: return done[0], 3.0)
	ok.disconnect(on_ok)
	Net.error_received.disconnect(on_error)


func _plant(at: Vector3) -> void:
	await _request(Net.plant.bind(at), Net.planted, 2)


func _places() -> void:
	var camera: FollowCamera = _camera()
	var hud: CanvasLayer = _village.get_node("HUD")
	# 섬 하늘에서: 카메라를 멀리 높이.
	hud.visible = false
	await _put(Vector3(0.0, 0.1, 6.0))
	var base_distance: float = camera.distance
	var base_pitch: float = camera.pitch_degrees
	camera.distance = 150.0
	camera.pitch_degrees = 62.0
	camera.fov = 50.0
	RenderingServer.global_shader_parameter_set("world_curve_strength", 0.0)
	camera.snap_to_target()
	await _wait(1.0)
	await _shot("v01_island_sky")
	camera.distance = 34.0
	camera.pitch_degrees = 40.0
	await _put(Vector3(50.0, 0.1, -4.0))
	await _shot("v02_museum")
	# 물고기를 기증하면 수조에서 헤엄친다.
	await _put(GameData.museum.keeper_position + Vector3(1.0, 0.1, 1.0))
	for fish: String in ["crucian", "goldfish", "loach", "carp", "catfish"]:
		var slot: int = _slot_of(fish)
		if slot >= 0:
			await _request(Net.donate.bind(slot), Net.donated, 4)
	camera.distance = base_distance + 1.5
	camera.pitch_degrees = base_pitch + 6.0
	await _put(Vector3(57.5, 0.1, -5.0))
	await _wait(2.0)
	await _shot("v03_aquarium")
	# 공항: 비행기를 이륙하는 순간에 세워 두고 찍는다.
	var airport: AirportSite = _village.get_node("Airport")
	camera.distance = 30.0
	camera.pitch_degrees = 34.0
	await _put(Vector3(8.0, 0.1, -66.0))
	await _shot("v04_airport")
	airport.set_process(false)
	var cycle: float = float(GameData.airport.extra.flight.cycle_minutes) * 60.0
	var away: float = float(GameData.airport.extra.flight.away_minutes) * 60.0
	var takeoff_at: float = cycle - away - airport.landing_time - airport.takeoff_time
	var pose: Dictionary = airport.plane_pose(takeoff_at + airport.takeoff_time * 0.74)
	airport.plane.visible = true
	airport.plane.global_position = pose["pos"]
	airport.plane.rotation = Vector3(0.0, float(pose["yaw"]), float(pose.get("pitch", 0.0)))
	camera.distance = 34.0
	await _put(Vector3(pose["pos"].x - 6.0, 0.1, -66.0))
	await _shot("v05_takeoff")
	camera.distance = 16.0
	camera.pitch_degrees = 38.0
	await _put(Vector3(-40.0, 0.1, -91.0))
	await _shot("v06_beach")
	camera.distance = base_distance
	camera.pitch_degrees = base_pitch
	camera.fov = 55.0
	hud.visible = true


func _life() -> void:
	var player: Player = _village.get_node("Player")
	var npcs: NpcCrowd = _village.get_node("Npcs")
	var emotes: EmoteController = _village.get_node("EmoteController")
	var emote_bar: EmoteBar = _village.get_node("HUD/EmoteBar")
	var emote_window: EmoteWindow = _village.get_node("HUD/EmoteWindow")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var box: DialogueBox = _village.get_node("HUD/DialogueBox")
	# 브레이크: 오른쪽으로 달리다가 왼쪽으로.
	await _put(Vector3(30.0, 0.1, -36.0))
	Input.action_press("ui_right")
	await _wait_until(func() -> bool: return player.running and player.velocity.length() > 6.5, 4.0)
	Input.action_release("ui_right")
	Input.action_press("ui_left")
	await _wait(0.12)
	await _shot("v07_brake")
	Input.action_release("ui_left")
	await _wait(1.2)
	# 감정표현: 통통이 곁에서 '안녕' → 통통이가 반응.
	var tong: NpcActor = npcs.actor("tongtong")
	await _put(tong.global_position + Vector3(0.9, 0.1, 2.2), -PI * 0.15)
	emote_bar.toggle()
	await _wait(0.3)
	emotes.perform("hello")
	await _wait(0.9)
	await _shot("v08_emote_react")
	emote_bar.close()
	await _wait(2.5)
	# 대화: 모락 — 기분 이름표 · 감정표현 배우기 · 주제 고르기.
	var morak: NpcActor = npcs.actor("morak")
	await _put(morak.global_position + Vector3(1.5, 0.1, 0.4))
	await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.TALK, 2.0)
	interaction.action_hud.action_pressed.emit()
	var choices: VBoxContainer = box.get_node("%Choices")
	var shot_teach: bool = false
	for i: int in 80:
		if choices.visible and choices.get_child_count() > 0:
			break
		if box.is_open() and not shot_teach and (box.get_node("%Text") as Label).text.contains("몸짓"):
			await _wait(1.6)
			await _shot("v09_talk_teach")
			shot_teach = true
		if box.is_open():
			box.press()
		await _wait(0.12)
	await _wait(0.5)
	await _shot("v10_talk_topics")
	(choices.get_child(0) as Button).pressed.emit()
	await _wait(2.0)
	await _shot("v11_talk_topic_line")
	for i: int in 120:
		if not (_village.get_node("DialogueController") as DialogueController).is_active():
			break
		if choices.visible and choices.get_child_count() > 0:
			(choices.get_child(choices.get_child_count() - 1) as Button).pressed.emit()
		elif box.is_open():
			box.press()
		await _wait(0.1)
	# 감정표현 창
	emote_window.open()
	await _wait(0.5)
	await _shot("v12_emote_window")
	emote_window.close()
	# 심기: 도토리 · 솔방울 · 꽃씨 여러 개 → 자라는 단계가 섞인 꽃밭.
	var spots: Array[Vector3] = [Vector3(8.0, 0.0, 12.0), Vector3(11.0, 0.0, 12.0), Vector3(9.5, 0.0, 15.0)]
	for i: int in spots.size():
		var seed: String = ["acorn", "pinecone", "acorn"][i]
		Net.move_item(_slot_of(seed), 2)
		await _wait_until(func() -> bool: return _slot_of(seed) == 2, 2.0)
		Net.equip(2)
		await _put(spots[i] + Vector3(1.2, 0.1, 0.0))
		await _plant(spots[i])
		await _wait(2.2)
	var flowers: Array = [["seed_tulip", 3], ["seed_cosmos", 3], ["seed_sunflower", 2], ["seed_hydrangea", 2]]
	var k: int = 0
	for entry: Array in flowers:
		for n: int in int(entry[1]):
			Net.move_item(_slot_of(entry[0]), 3)
			await _wait_until(func() -> bool: return _slot_of(entry[0]) == 3, 2.0)
			Net.equip(3)
			var at: Vector3 = Vector3(5.0 + float(k % 5) * 1.0, 0.0, 17.0 + float(k / 5) * 1.0)
			await _put(at + Vector3(0.0, 0.1, 1.4))
			await _plant(at)
			k += 1
	Net.equip(-1)
	await _put(Vector3(8.0, 0.1, 21.5))
	await _wait(1.5)
	await _shot("v13_garden_growing")
	await _wait_until(func() -> bool: return Net.flowers.values().all(func(f: FlowerState) -> bool: return f.stage == NetProtocol.FLOWER_BLOOM), 30.0)
	await _wait(2.0)
	await _shot("v14_garden_bloom")
	# 박물관 도감
	var museum_window: MuseumWindow = _village.get_node("HUD/MuseumWindow")
	await _put(GameData.museum.keeper_position + Vector3(1.0, 0.1, 1.0))
	for fish: String in ["crucian", "loach", "goldfish"]:
		var slot: int = _slot_of(fish)
		if slot >= 0:
			await _request(Net.donate.bind(slot), Net.donated, 4)
	museum_window.open(MuseumWindow.MODE_BOOK)
	await _wait(0.6)
	await _shot("v15_museum_book")
	museum_window.close()


func _fish() -> void:
	var player: Player = _village.get_node("Player")
	var controller: FishingController = _village.get_node("FishingController")
	var hud: FishingHud = _village.get_node("HUD/FishingHud")
	await _put(Vector3(-9.0, 0.1, 2.0), PI * 0.5)
	for attempt: int in 4:
		hud.action_pressed.emit()
		if not await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.BITE, 12.0):
			continue
		await _wait(0.12)
		hud.action_pressed.emit()
		if await _wait_until(func() -> bool: return player.rig.is_showing_off(), 3.0):
			await _wait(1.3)
			await _shot("v16_fish_show_off")
			return
		await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.IDLE, 6.0)
