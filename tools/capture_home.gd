extends Node
## 아파트 집 안(v0.10) 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). tools/capture_home.sh 가 서버를 띄운다.
##   평면도마다(26평 A·B · 27평 · 34평 · 35평): 집을 사고 → 공동 현관 "집 구경" → 엘리베이터 → 집 안(걸어 다니는 시점) → 꾸미기(위에서 본 평면도)
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


func _to_screen(home: HomeController, at: Vector2) -> Vector2:
	var cam: Camera3D = home.editor.get("_camera")
	return cam.unproject_position(Home.to_world(at))
