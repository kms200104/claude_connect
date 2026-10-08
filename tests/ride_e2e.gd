extends Node
## 킥보드 종단 테스트 (v0.16, 앱 안 테스트 서버 · tests/run_ride_e2e.sh).
##   가방에서 "꺼내 타기" → 펼치고 올라탐 → 앞으로 밀면 땅을 차며 빨라짐(최고 속도 안) → 손을 떼면 미끄러지다 섬
##   → 돌면 몸이 안쪽으로 기울고 핸들이 꺾임 → 반대로 밀면 뒷발 브레이크 → 상황 버튼 "내리기" → 접어 넣음 → 순간이동하면 바로 내림

var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalTestServer.SAVE_PATH))
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[ride] FAIL: %s" % f)
	print("[ride] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[ride] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _slot_of(id: String) -> int:
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == id:
			return i
	return -1


func _hold(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(seconds).timeout
	Input.action_release(action)


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var rider: KickboardRider = _village.get_node("Ride")
	var inventory: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	var interaction: InteractionController = _village.get_node("InteractionController")
	Net.play_on_test_server()
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 5.0), "앱 안 테스트 서버로 접속")
	_check(_slot_of("kickboard") >= 0, "가방에 접이식 킥보드")
	_check(rider.player == player and player.vehicle == rider, "킥보드 타기가 캐릭터에 붙음")
	# 넓은 풀밭 (상점 문에서 멀리 — 문으로 밀고 들어가면 상점 안으로 옮겨지며 내린다).
	player.global_position = Vector3(-44.0, 0.1, 66.0)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.8).timeout

	# ---- 꺼내 타기 ----
	inventory.open()
	inventory.press_slot(_slot_of("kickboard"))
	var use: Button = inventory.get_node("%UseButton")
	_check(use.visible and use.text == "꺼내 타기", "킥보드를 고르면 '꺼내 타기' (%s)" % use.text)
	use.pressed.emit()
	_check(not inventory.is_open() and rider.state == KickboardRider.State.MOUNTING and player.is_input_locked(), "가방 창이 닫히고 꺼내는 동안 못 움직임")
	var board: Kickboard = rider.board
	_check(board != null and board.get_parent() == player.rig and board.fold > 0.99, "접힌 킥보드가 나옴")
	_check(await _wait_until(func() -> bool: return rider.is_riding(), 3.0), "펼쳐서 올라탐")
	_check(board.fold < 0.01 and player.rig.riding_kind() == "kick" and not player.is_input_locked(), "다 펼쳐지고 발판 위에 선 자세")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.RIDE_OFF, 2.0), "탄 동안 상황 버튼은 '내리기'")

	# ---- 차면서 빨라지기 ----
	var start: Vector3 = player.global_position
	var top: Array[float] = [0.0]
	var watch: Callable = func() -> void: top[0] = maxf(top[0], rider.speed)
	get_tree().process_frame.connect(watch)
	Input.action_press(&"ui_up")
	await get_tree().create_timer(0.35).timeout
	var early: float = rider.speed
	await get_tree().create_timer(2.6).timeout
	_check(early > 0.3 and early < 2.5, "처음 한 번 차면 조금 빨라짐 (%.2f m/s)" % early)
	_check(rider.kicks >= 3, "앞으로 미는 동안 여러 번 땅을 참 (%d번)" % rider.kicks)
	_check(rider.speed > 4.0 and top[0] <= rider.info.max_speed + 0.01, "점점 빨라지고 최고 속도 안 (%.2f / 최고 %.2f)" % [rider.speed, top[0]])
	_check(player.global_position.distance_to(start) > 6.0, "앞으로 나아감 (%.1fm)" % player.global_position.distance_to(start))
	_check(absf(player.velocity.length() - rider.speed) < 0.6, "캐릭터가 킥보드 속도로 감")
	Input.action_release(&"ui_up")
	var kicks_before: int = rider.kicks
	var coast_from: float = rider.speed
	await get_tree().create_timer(0.8).timeout
	_check(rider.speed < coast_from and rider.speed > coast_from - 2.0 and rider.kicks <= kicks_before + 1, "손을 떼면 차지 않고 천천히 느려짐 (%.2f → %.2f)" % [coast_from, rider.speed])
	_check(await _wait_until(func() -> bool: return rider.speed < 0.05, 6.0), "미끄러지다 멈춤")

	# ---- 돌기: 기울기 · 핸들 ----
	Input.action_press(&"ui_up")
	await get_tree().create_timer(1.6).timeout
	var yaw0: float = rider.yaw
	Input.action_press(&"ui_right")
	await get_tree().create_timer(0.5).timeout
	_check(rider.lean < -0.05 and board.steer < -0.05, "오른쪽으로 돌면 몸이 오른쪽으로 기울고 핸들이 꺾임 (기울기 %.2f, 핸들 %.2f)" % [rider.lean, board.steer])
	_check(absf(wrapf(rider.yaw - yaw0, -PI, PI)) > 0.3, "방향이 돎 (%.2f rad)" % wrapf(rider.yaw - yaw0, -PI, PI))
	var leaned_body: float = player.body.global_basis.y.dot(Vector3.UP)
	_check(leaned_body < 0.995, "몸(Body)이 실제로 기울어 보임")
	Input.action_release(&"ui_right")
	await get_tree().create_timer(1.2).timeout

	# ---- 브레이크 ----
	var fast: float = rider.speed
	Input.action_release(&"ui_up")
	var heading: Vector3 = Vector3(-sin(rider.yaw), 0.0, -cos(rider.yaw))
	var cam: Camera3D = get_viewport().get_camera_3d()
	# 진행 방향 반대가 되는 조이스틱 방향 (카메라 기준).
	var back: Vector3 = -heading
	var right: Vector3 = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	var fwd: Vector3 = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	var stick: Vector2 = Vector2(back.dot(right), -back.dot(fwd)).normalized()
	player.joystick.output = stick
	await get_tree().create_timer(0.3).timeout
	_check(rider.braking and player.rig.riding_kind() == "kick_brake", "반대로 밀면 뒷발 브레이크 자세")
	_check(await _wait_until(func() -> bool: return rider.speed < 0.3, 1.6), "브레이크로 빨리 섬 (%.2f m/s 에서)" % fast)
	player.joystick.output = Vector2.ZERO
	await get_tree().create_timer(0.3).timeout
	_check(player.body.global_basis.y.dot(Vector3.UP) > 0.995, "서면 몸이 똑바로")
	get_tree().process_frame.disconnect(watch)

	# ---- 내리기 ----
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.RIDE_OFF, 2.0), "'내리기' 버튼")
	interaction.action_hud.action_pressed.emit()
	_check(rider.state == KickboardRider.State.DISMOUNTING and player.is_input_locked(), "내려서 접는 동안 못 움직임")
	_check(await _wait_until(func() -> bool: return rider.state == KickboardRider.State.OFF, 3.0), "접어서 가방에 넣음")
	_check(not is_instance_valid(board) or board.is_queued_for_deletion(), "킥보드 모형이 사라짐")
	_check(player.rig.riding_kind() == "" and not player.is_input_locked() and _slot_of("kickboard") >= 0, "다시 걷고, 킥보드는 가방에 그대로")

	# ---- 순간이동하면 바로 내린다 ----
	rider.mount("kickboard")
	_check(await _wait_until(func() -> bool: return rider.is_riding(), 3.0), "다시 탐 (바로 꺼내기)")
	player.global_position += Vector3(0.0, 0.0, -20.0)
	_check(await _wait_until(func() -> bool: return rider.state == KickboardRider.State.OFF, 1.0), "순간이동하면 바로 내려 접힘")
	_check(player.body.global_basis.y.dot(Vector3.UP) > 0.999 and absf(player.body.position.y - player.body_rest_height()) < 0.01, "몸 자리가 원래대로")
