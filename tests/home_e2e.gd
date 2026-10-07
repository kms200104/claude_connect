extends Node
## 집 안 · 테스트 서버 종단 테스트 (v0.10, tests/run_home_e2e.sh 가 띄운다).
##   1) 서버가 없을 때: 접속 실패 → 방 패널 "테스트 서버로 하기" → 앱 안 테스트 서버로 접속 → 공동 현관 "집 구경" → 집 안 → 꾸미기
##   2) 진짜 서버: 집 사기 → 엘리베이터로 들어가기 → 평면도대로 지은 벽·바닥·기본 가구(TV·에어컨·선풍기·침대) → 위에서 본 꾸미기
##      (끌어서 옮기기 = 보이지 않는 0.25m 격자, 좌우 돌리기, 벽·다른 방에 걸치면 안 됨, 가방에 넣기 · 가방에서 놓기) → 현관문 나가기
## 인자: -- --server=ws://…

var _server: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--real="):
			_server = arg.trim_prefix("--real=")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalTestServer.SAVE_PATH))
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[home] FAIL: %s" % f)
	print("[home] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[home] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _run() -> void:
	var panel: RoomPanel = _village.get_node("HUD/RoomPanel")
	var home: HomeController = _village.get_node("Home")
	var interaction: InteractionController = _village.get_node("InteractionController")
	# ---- 1) 서버 없음 → 테스트 서버 ----
	Net.create_room("ws://127.0.0.1:9")
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.DISCONNECTED and not str(panel.get("_last_error")).is_empty(), 8.0), "서버가 없으면 접속 실패 (%s)" % str(panel.get("_last_error")))
	var test_button: Button = panel.get("_test_button")
	_check(test_button != null and test_button.visible, "'테스트 서버로 하기' 단추가 보인다")
	test_button.pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 5.0), "앱 안 테스트 서버로 접속")
	_check(Net.is_test_server() and Net.room_code == LocalTestServer.ROOM_CODE, "테스트 서버 방 %s" % Net.room_code)
	_check(GameData.trees.size() > 0 and Net.tree_stages.size() == GameData.trees.size(), "진짜 서버에서 찍어 둔 마을 (나무 %d)" % Net.tree_stages.size())
	await _visit_and_decorate(home, interaction, "102-501", "84a", true)
	# 테스트 서버에서 안 되는 요청은 알기 쉽게 거절.
	var refused: Array = []
	Net.request_failed.connect(func(kind: String, code: String) -> void: refused.append(code))
	Net.request("stock_order", {"id": "SBE", "side": "buy", "qty": 1})
	_check(await _wait_until(func() -> bool: return LocalTestServer.ERR_TEST_ONLY in refused, 2.0), "안 되는 기능은 test_server 로 거절")
	Net.leave()
	await _wait_until(func() -> bool: return Net.state == Net.State.DISCONNECTED, 2.0)

	# ---- 2) 진짜 서버 ----
	Net.create_room(_server)
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE and not Net.is_test_server(), 5.0), "진짜 서버로 접속")
	Economy.buy_home("102-502", 0)
	_check(await _wait_until(func() -> bool: return Economy.home_owners.get("102-502", 0) == Net.my_id, 3.0), "102동 502호(35평)를 샀다")
	await _visit_and_decorate(home, interaction, "102-502", "35", false)


## v0.13.6 3인칭 집 안: 벽 너머는 가린다 (현관에서 안방 가운데는 안 보이고, 바로 앞은 보인다). 1인칭에서는 끈다.
func _sight(home: HomeController, player: Player, tag: String) -> void:
	_check(home.sight.active() and float(home.sight.material.get_shader_parameter("sight_on")) > 0.5, "[%s] 3인칭: 벽 너머 가리기 켜짐" % tag)
	_check(home.sight.can_see(player.global_position + Vector3(0.6, 0.0, 0.0)), "[%s] 3인칭: 바로 곁은 보인다" % tag)
	var master: FloorPlan.Room = Home.plan.first_room("master")
	var hidden_spot: Vector3 = Home.to_world(master.main_rect().get_center())
	_check(not home.sight.can_see(hidden_spot), "[%s] 3인칭: 현관에서 벽 너머 안방은 가려진다" % tag)
	var mesh: MeshInstance3D = home.interior.get_child(0) as MeshInstance3D
	_check(mesh != null and mesh.material_overlay == home.sight.material, "[%s] 3인칭: 집 안 메시에 가림 덮개" % tag)
	home.first_person.enter()
	await get_tree().create_timer(0.1).timeout
	_check(float(home.sight.material.get_shader_parameter("sight_on")) < 0.5, "[%s] 1인칭에서는 가리지 않는다" % tag)
	home.first_person.exit()
	await get_tree().create_timer(0.1).timeout


## v0.13.5 1인칭: 눈높이 카메라 · 캐릭터 숨김 · 창유리는 실시간 창밖 풍경 → 돌아가면 그대로.
func _first_person(home: HomeController, player: Player, tag: String) -> void:
	var button: Button = home.get("_first_person_button")
	_check(button != null and button.visible, "[%s] '1인칭' 단추" % tag)
	var cam: Camera3D = _village.get_node("CameraRig/Camera3D")
	var before: Vector3 = cam.global_position
	button.pressed.emit()
	await get_tree().create_timer(0.2).timeout
	var glass: ShaderMaterial = home.interior.get("_view_material")
	_check(home.first_person.active and absf(cam.global_position.y - (player.global_position.y + HomeFirstPerson.EYE_HEIGHT)) < 0.05, "[%s] 1인칭: 눈높이 카메라" % tag)
	_check(not player.body.visible, "[%s] 1인칭: 내 캐릭터는 안 보인다" % tag)
	var ceiling: MeshInstance3D = home.interior.first_person_shell()
	_check(ceiling != null and ceiling.visible and absf(ceiling.get_aabb().end.y - HomeInterior.CEILING_HEIGHT - 0.06) < 0.05, "[%s] 1인칭: 천장이 막혀 있다 (%.1fm)" % [tag, HomeInterior.CEILING_HEIGHT])
	_check(glass != null and float(glass.get_shader_parameter("use_live")) > 0.5 and glass.get_shader_parameter("live_view") is ViewportTexture, "[%s] 1인칭: 창유리에 실시간 창밖 풍경" % tag)
	_check(button.text == "돌아가기", "[%s] 1인칭: '돌아가기' 단추" % tag)
	# 위아래로 둘러봐도 창밖 카메라가 찌그러지지 않는다 (방향 행렬이 직교 · 단위 길이 = 회전만).
	home.first_person.set("_pitch", deg_to_rad(40.0))
	await get_tree().process_frame
	var live: Camera3D = home.first_person.get("_live_cam")
	var b: Basis = live.global_basis if live != null else Basis()
	var skew: float = absf(b.x.dot(b.y)) + absf(b.y.dot(b.z)) + absf(b.z.dot(b.x)) + absf(b.x.length() - 1.0) + absf(b.y.length() - 1.0) + absf(b.z.length() - 1.0)
	_check(live != null and skew < 0.001, "[%s] 1인칭: 위를 봐도 창밖 카메라가 찌그러지지 않음 (%.4f)" % [tag, skew])
	_check(live != null and absf(live.global_basis.z.y - cam.global_basis.z.y) < 0.001, "[%s] 1인칭: 창밖 카메라도 같은 높낮이로 본다" % tag)
	button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	_check(not home.first_person.active and player.body.visible and float(glass.get_shader_parameter("use_live")) < 0.5, "[%s] 돌아가기: 캐릭터 · 찍어 둔 창밖 사진으로" % tag)
	_check(not home.interior.first_person_shell().visible, "[%s] 돌아가기: 3인칭은 천장 없이 (위에서 내려다봄)" % tag)
	_check(cam.global_position.distance_to(before) < 0.5, "[%s] 돌아가기: 카메라가 제자리 (%.2fm)" % [tag, cam.global_position.distance_to(before)])


func _visit_and_decorate(home: HomeController, interaction: InteractionController, unit: String, plan_id: String, test_server: bool) -> void:
	var tag: String = "테스트 서버" if test_server else "진짜 서버"
	var player: Player = _village.get_node("Player")
	await _teleport(GameData.econ.lobby_of(unit.split("-")[0]) + Vector3(0.0, 0.1, 0.3))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.HOME and interaction.target_id.begins_with(HomeController.TARGET_LOBBY), 2.0), "[%s] 공동 현관 앞 '%s'" % [tag, home.target_label(interaction.target_id)])
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return home.window.is_open(), 1.0), "[%s] 엘리베이터 창" % tag)
	var buttons: Array = home.window.find_children("*", "Button", true, false)
	_check(buttons.size() >= 21, "[%s] 층마다 호수 단추 (%d)" % [tag, buttons.size()])
	home.window.close()
	Home.enter(unit)
	_check(await _wait_until(func() -> bool: return Home.unit == unit, 3.0), "[%s] %s 집 안으로" % [tag, unit])
	_check(Home.plan != null and Home.plan.id == plan_id, "[%s] 평면도 %s (%s)" % [tag, plan_id, Home.plan.display_name if Home.plan != null else "?"])
	await get_tree().process_frame
	var walls: StaticBody3D = home.interior.get_node_or_null("Walls")
	_check(walls != null and walls.get_child_count() > 20, "[%s] 평면도대로 벽 (%d)" % [tag, walls.get_child_count() if walls != null else 0])
	_check(player.global_position.distance_to(Home.to_world(Home.plan.spawn)) < 0.6, "[%s] 현관에서 시작" % tag)
	_check(not player.is_on_floor() or player.global_position.y > -0.5, "[%s] 바닥 위에 선다" % tag)
	var items: Array = Home.furniture.map(func(f: Home.Furniture) -> String: return f.item)
	for need: String in ["tv", "air_conditioner", "electric_fan", "bed_double", "bed_single"]:
		_check(need in items, "[%s] 기본 가구 %s" % [tag, GameData.item_name(need)])
	_check(Home.editable, "[%s] 내 집이라 꾸밀 수 있다" % tag)
	await get_tree().create_timer(0.3).timeout
	await _sight(home, player, tag)
	await _first_person(home, player, tag)
	_check(home.get("_decor_button").visible, "[%s] '꾸미기' 단추" % tag)
	home.editor.start()
	_check(home.editor.active and home.editor.get("_camera").current, "[%s] 위에서 본 평면도 (직교 카메라)" % tag)
	await get_tree().create_timer(0.1).timeout
	_check(float(home.sight.material.get_shader_parameter("sight_on")) < 0.5, "[%s] 꾸미기에서는 벽 너머도 다 보인다" % tag)
	var cam: Camera3D = home.editor.get("_camera")
	_check(absf(cam.global_basis.z.y - 1.0) < 0.01, "[%s] 바로 위에서 내려다봄" % tag)
	# 안방 더블 침대를 끌어 옮긴다: 손가락 위치는 격자에 저절로 맞는다.
	var bed: Home.Furniture = null
	for f: Home.Furniture in Home.furniture:
		if f.item == "bed_double":
			bed = f
	var start: Vector2 = bed.position
	var room: FloorPlan.Room = Home.plan.room_at(start)
	var target: Vector2 = Vector2.ZERO
	var found: bool = false
	for dx: float in [0.37, -0.37, 0.61, -0.61]:
		for dz: float in [0.29, -0.29, 0.55, -0.55]:
			var c: Vector2 = (start + Vector2(dx, dz)).snapped(Vector2.ONE * Home.grid())
			if not found and home.editor.fits(bed.item, c, bed.rot) and Home.plan.room_at(c) == room:
				target = start + Vector2(dx, dz)
				found = true
	_check(found, "[%s] 같은 방 안에 옮길 자리" % tag)
	home.editor.call("_on_press", cam.unproject_position(Home.to_world(start)))
	home.editor.call("_on_drag", cam.unproject_position(Home.to_world(target)))
	home.editor.call("_on_release")
	var id: String = bed.id
	_check(await _wait_until(func() -> bool:
		var f: Home.Furniture = Home.find(id)
		return f != null and f.position.distance_to(start) > 0.2, 3.0), "[%s] 침대를 끌어 옮겼다 (서버 확정)" % tag)
	var moved: Home.Furniture = Home.find(id)
	_check(is_zero_approx(fmod(moved.position.x, Home.grid())) and is_zero_approx(fmod(moved.position.y, Home.grid())), "[%s] 보이지 않는 격자에 맞춤 (%s)" % [tag, str(moved.position)])
	# 벽 밖으로 끌면 놓이지 않고 제자리.
	var before: Vector2 = moved.position
	home.editor.call("_on_press", cam.unproject_position(Home.to_world(before)))
	home.editor.call("_on_drag", cam.unproject_position(Home.to_world(Vector2(-3.0, before.y))))
	home.editor.call("_on_release")
	await get_tree().create_timer(0.6).timeout
	_check(Home.find(id).position == before, "[%s] 벽 밖으로는 안 옮겨짐" % tag)
	# 오른쪽으로 두 번 (90°).
	home.editor.call("_on_press", cam.unproject_position(Home.to_world(before)))
	home.editor.call("_on_release")
	home.editor.call("_rotate", 1)
	await get_tree().create_timer(0.4).timeout
	home.editor.call("_rotate", 1)
	_check(await _wait_until(func() -> bool: return Home.find(id) != null and Home.find(id).rot == 2, 3.0), "[%s] 오른쪽으로 두 번 돌림 → 90° (rot %d)" % [tag, Home.find(id).rot if Home.find(id) != null else -1])
	var node: StaticBody3D = home.interior.furniture_node(id)
	_check(node != null and is_equal_approx(node.rotation.y, PI * 0.5), "[%s] 모형도 돌아감" % tag)
	# 가방에 넣기 → 가방에서 놓기.
	var fan_id: String = ""
	for f: Home.Furniture in Home.furniture:
		if f.item == "electric_fan":
			fan_id = f.id
	home.editor.set("_selected", fan_id)
	home.editor.call("_pickup")
	_check(await _wait_until(func() -> bool: return Home.find(fan_id) == null and Net.inventory.any(func(it: InventoryItem) -> bool: return it != null and it.id == "electric_fan"), 3.0), "[%s] 선풍기를 가방에 넣음" % tag)
	var slot: int = -1
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == "electric_fan":
			slot = i
	var count: int = Home.furniture.size()
	home.editor.call("_place_from_bag", slot, "electric_fan")
	_check(await _wait_until(func() -> bool: return Home.furniture.size() == count + 1, 3.0), "[%s] 가방에서 꺼내 다시 놓음" % tag)
	_check(Home.find(str(home.editor.get("_selected"))) != null and Home.find(str(home.editor.get("_selected"))).item == "electric_fan", "[%s] 새로 놓은 가구가 골라져 있음" % tag)
	home.editor.stop()
	_check(not home.editor.active and (_village.get_node("CameraRig") as FollowCamera).camera.current, "[%s] 꾸미기 끝 → 원래 카메라" % tag)
	# 현관문 곁에서 나가기.
	await _teleport(Home.front_world() + Vector3(0.0, 0.1, 0.5))
	_check(await _wait_until(func() -> bool: return interaction.target_id == HomeController.TARGET_EXIT, 2.0), "[%s] 현관문 곁 '나가기'" % tag)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not Home.is_inside(), 3.0), "[%s] 공동 현관 앞으로 나왔다" % tag)
	_check(player.global_position.distance_to(GameData.econ.lobby_of(unit.split("-")[0])) < 1.5, "[%s] 동 앞" % tag)
