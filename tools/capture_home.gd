extends Node
## 아파트 집 안(v0.10) 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). tools/capture_home.sh 가 서버를 띄운다.
##   평면도마다(26평 A·B · 27평 · 34평 · 35평): 집을 사고 → 공동 현관 "집 구경" → 엘리베이터 → 집 안(걸어 다니는 시점) → 꾸미기(위에서 본 평면도)
##   --only=white (v0.12): 34평 거실·주방·안방을 비우고 모던 화이트 가구 세트를 놓아 찍는다 (서버 START_ITEMS 로 가구를 받는다).
## 인자: -- --srv=ws://… --out=/tmp/shots [--only=34]

const UNITS: Dictionary = {"26a": "101-501", "27": "101-502", "34": "102-501", "35": "102-502", "26b": "103-501"}

var _server: String = "ws://127.0.0.1:8080"
var _out: String = "user://shots"
var _only: String = ""
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--srv="):
			_server = arg.trim_prefix("--srv=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(_out)
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	Net.create_room(_server)
	await Net.welcomed
	await _wait(1.5)
	if _only == "white":
		await _white()
	else:
		await _run()
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


func _put(at: Vector3, face: Vector3 = Vector3.FORWARD) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = atan2(-face.x, -face.z)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await _wait(0.6)


func _run() -> void:
	var home: HomeController = _village.get_node("Home")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var player: Player = _village.get_node("Player")
	for plan_id: String in UNITS:
		if not _only.is_empty() and plan_id != _only:
			continue
		var unit: String = UNITS[plan_id]
		Economy.buy_home(unit, 0)
		await _wait_until(func() -> bool: return Economy.home_owners.get(unit, 0) == Net.my_id, 3.0)
		var building: String = unit.split("-")[0]
		await _put(GameData.econ.lobby_of(building) + Vector3(0.0, 0.1, 0.4), Vector3.FORWARD)
		await _wait_until(func() -> bool: return interaction.target_id.begins_with(HomeController.TARGET_LOBBY), 2.0)
		if plan_id == "34":
			await _shot("h00_lobby_button")
			interaction.action_hud.action_pressed.emit()
			await _wait(0.6)
			await _shot("h01_elevator")
			home.window.close()
		Home.enter(unit)
		await _wait_until(func() -> bool: return Home.unit == unit, 3.0)
		await _wait(1.2)
		await _shot("h_%s_entry" % plan_id)
		# 거실 가운데로 걸어 들어간 모습.
		var living: FloorPlan.Room = Home.plan.first_room("living")
		await _put(Home.to_world(living.main_rect().get_center()) + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
		await _wait(0.8)
		await _shot("h_%s_living" % plan_id)
		# 창밖 (v0.12): 남쪽 큰 창을 낮게 바라본다 — 마을의 그 집 자리에서 찍은 풍경이 유리 너머로 보여야 한다.
		var rig: FollowCamera = _village.get_node("CameraRig")
		var keep: Vector3 = Vector3(rig.yaw_degrees, rig.pitch_degrees, rig.distance)
		rig.yaw_degrees = 180.0
		rig.pitch_degrees = 18.0
		rig.distance = 5.0
		var south: Rect2 = living.main_rect()
		await _put(Home.to_world(Vector2(south.get_center().x, south.end.y - 1.2)) + Vector3(0.0, 0.1, 0.0), Vector3.BACK)
		rig.snap_to_target()
		await _wait(0.8)
		await _shot("h_%s_window" % plan_id)
		rig.yaw_degrees = keep.x
		rig.pitch_degrees = keep.y
		rig.distance = keep.z
		home.editor.start()
		await _wait(1.0)
		await _shot("h_%s_top" % plan_id)
		if plan_id == "34":
			# 침대 하나 고르기 → 옮기기 → 돌리기.
			var bed: Home.Furniture = null
			for f: Home.Furniture in Home.furniture:
				if f.item == "bed_single":
					bed = f
			home.editor.call("_on_press", _to_screen(home, bed.position))
			await _wait(0.3)
			await _shot("h_34_top_selected")
			home.editor.call("_rotate", 2)
			await _wait(1.0)
			await _shot("h_34_top_rotated")
		home.editor.stop()
		await _wait(0.3)
		await _put(Home.front_world() + Vector3(0.0, 0.1, 0.5), Vector3.FORWARD)
		Home.exit()
		await _wait_until(func() -> bool: return Home.unit.is_empty(), 3.0)
		await _wait(0.5)
	print("[capture] done %s" % str(player.global_position))


func _white() -> void:
	var home: HomeController = _village.get_node("Home")
	var rig: FollowCamera = _village.get_node("CameraRig")
	var unit: String = UNITS["34"]
	Economy.buy_home(unit, 0)
	await _wait_until(func() -> bool: return Economy.home_owners.get(unit, 0) == Net.my_id, 3.0)
	await _put(GameData.econ.lobby_of(unit.split("-")[0]) + Vector3(0.0, 0.1, 0.4), Vector3.FORWARD)
	Home.enter(unit)
	await _wait_until(func() -> bool: return Home.unit == unit, 3.0)
	await _wait(1.0)
	var living: Rect2 = Home.plan.first_room("living").main_rect()
	var kitchen: Rect2 = Home.plan.first_room("kitchen").main_rect()
	var master: Rect2 = Home.plan.first_room("master").main_rect()
	# 세 방의 기본 가구를 걷어 낸다.
	for f: Home.Furniture in Home.furniture.duplicate():
		if living.has_point(f.position) or kitchen.has_point(f.position) or master.has_point(f.position):
			Home.pickup(f.id)
			await _wait(0.25)
	await _wait(0.5)
	var c: Vector2 = living.get_center()
	var k: Vector2 = kitchen.get_center()
	var m: Vector2 = master.get_center()
	var layout: Array = [
		["white_rug", c, 0], ["white_tv_stand", Vector2(living.position.x + 0.35, c.y), 2],
		["white_sofa", Vector2(living.end.x - 0.6, c.y), 6], ["white_coffee_table", c + Vector2(0.2, 0.0), 0],
		["white_arc_lamp", Vector2(living.end.x - 0.45, c.y - 1.5), 4], ["white_shelf", Vector2(c.x - 1.2, living.position.y + 0.3), 0],
		["white_dining_table", k, 0], ["white_chair", k + Vector2(-0.35, -0.72), 0], ["white_chair", k + Vector2(0.35, 0.72), 4],
		["white_bed", m, 0], ["white_desk", Vector2(m.x + 1.0, master.end.y - 0.45), 4],
	]
	for row: Array in layout:
		var slot: int = -1
		for i: int in Net.inventory.size():
			if Net.inventory[i] != null and Net.inventory[i].id == str(row[0]):
				slot = i
				break
		if slot < 0:
			print("[capture] %s 이(가) 가방에 없음" % row[0])
			continue
		var before: int = Home.furniture.size()
		Home.place(slot, row[1], int(row[2]))
		var ok: bool = await _wait_until(func() -> bool: return Home.furniture.size() > before, 1.5)
		print("[capture] %s %s" % [row[0], "놓음" if ok else "못 놓음"])
	await _wait(0.8)
	rig.yaw_degrees = 225.0
	rig.pitch_degrees = 40.0
	rig.distance = 9.0
	await _put(Home.to_world(c) + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
	rig.snap_to_target()
	await _wait(0.8)
	await _shot("w01_living")
	await _put(Home.to_world(m) + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
	rig.snap_to_target()
	await _wait(0.8)
	await _shot("w02_master")
	await _put(Home.to_world(k) + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
	rig.snap_to_target()
	await _wait(0.8)
	await _shot("w03_dining")
	home.editor.start()
	await _wait(1.0)
	await _shot("w04_top")
	home.editor.stop()


func _to_screen(home: HomeController, at: Vector2) -> Vector2:
	var cam: Camera3D = home.editor.get("_camera")
	return cam.unproject_position(Home.to_world(at))
