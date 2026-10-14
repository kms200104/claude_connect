extends Node
## v0.27 동승 종단 테스트 (서버 1개 + 헤드리스 Godot 2개 · tests/run_passenger_e2e.sh, 낮):
##   a: 미니트럭을 사서 불러 운전석에 탄다 → b 가 짐칸에 타면 앞으로 달린다 → 내 화면의 b 가 짐칸 자리에 붙어 따라온다 → 세운다.
##   b: 트럭 곁에서 상황 버튼 "같이 타기 · 이름" → 짐칸에 앉아 따라간다 (앉은 자세) → "내리기"로 내린다 → 다시 타면 a 가 세울 때 같이 내린다.
## 인자: -- --role=a|b --server=ws://… --dir=/tmp/…

var _role: String = ""
var _server: String = ""
var _dir: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[%s] FAIL: %s" % [_role, f])
	print("[%s] %s" % [_role, "PASS" if _failures.is_empty() else "FAILED"])
	_write("%s.done" % _role, "1")
	await _wait_file("%s.done" % ("b" if _role == "a" else "a"), 60.0)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [_role, "ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _write(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open("%s/%s" % [_dir, file], FileAccess.WRITE)
	f.store_string(text)


func _read(file: String) -> String:
	var path: String = "%s/%s" % [_dir, file]
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _wait_file(file: String, timeout_s: float) -> String:
	var waited: float = 0.0
	while _read(file).is_empty() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return _read(file)


func _stick_toward(dir: Vector3) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	var fwd: Vector3 = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	return Vector2(dir.dot(right), -dir.dot(fwd)).normalized()


## 20m 앞이 트인 방향 (8방향 가운데).
func _open_yaw(player: Player) -> float:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var best: float = 0.0
	var best_free: float = -1.0
	for i: int in 8:
		var yaw: float = TAU * float(i) / 8.0
		var from: Vector3 = player.global_position + Vector3(0, 0.7, 0)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 22.0)
		q.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		var free: float = 22.0 if hit.is_empty() else from.distance_to(hit["position"])
		if free > best_free:
			best_free = free
			best = yaw
	return best


func _teleport(at: Vector3) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.4).timeout


func _run() -> void:
	if _role == "a":
		Net.create_room(_server)
		await Net.welcomed
		_write("code", Net.room_code)
		await _wait_until(func() -> bool: return Net.partner_present, 15.0)
	else:
		var code: String = await _wait_file("code", 15.0)
		Net.join_room(_server, code)
		await Net.welcomed
	_check(Net.partner_present, "둘이 같은 방")
	await get_tree().create_timer(0.5).timeout
	if _role == "a":
		await _driver()
	else:
		await _rider()


func _driver() -> void:
	var player: Player = _village.get_node("Player")
	var rider: GarageRider = player.garage_ride
	await _teleport(Vector3(-150.0, 0.1, 140.0))
	Net.request("veh_buy", {"model": "car_truck"})
	await _wait_until(func() -> bool: return not Net.vehicles.is_empty(), 3.0)
	var id: String = str(Net.vehicles[0].get("id", ""))
	rider.call_vehicle(id)
	_check(await _wait_until(func() -> bool: return bool(_village.get_node("InteractionController").parked.spot_of(id).get("arrived", false)), 6.0), "트럭이 왔다")
	_check(rider.mount(id) and await _wait_until(func() -> bool: return rider.is_riding(), 4.0), "운전석에 탔다")
	_write("driving", "1")
	_check(await _wait_until(func() -> bool:
		for sid: int in Net.seats:
			if int(Net.seats[sid].get("d", 0)) == Net.my_id:
				return true
		return false, 20.0), "친구가 짐칸에 탔다")
	await get_tree().create_timer(0.5).timeout
	# 앞으로 달린다.
	var start: Vector3 = player.global_position
	rider.drive_state.yaw = _open_yaw(player)
	player.joystick.output = _stick_toward(rider.drive_state.forward())
	await get_tree().create_timer(5.0).timeout
	player.joystick.output = Vector2.ZERO
	_check(player.global_position.distance_to(start) > 6.0, "트럭이 달렸다 (%.1fm, %.2f m/s)" % [player.global_position.distance_to(start), rider.drive_state.speed])
	# 내 화면의 친구가 짐칸 자리에 붙어 있다.
	var friend: RemotePlayer = null
	for r: RemotePlayer in (get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator).remote_nodes():
		friend = r
	_check(friend != null and friend.is_pinned() and friend.global_position.distance_to(player.global_position) < 2.0, "친구가 짐칸에 붙어 따라온다 (%.2fm)" % (friend.global_position.distance_to(player.global_position) if friend != null else -1.0))
	# 브레이크로 선다 (손만 떼면 한참 굴러간다).
	player.joystick.output = _stick_toward(-rider.drive_state.forward())
	await _wait_until(func() -> bool: return absf(rider.drive_state.speed) < 0.3, 6.0)
	player.joystick.output = Vector2.ZERO
	_write("drove", "1")
	_check(not (await _wait_file("reboarded", 20.0)).is_empty(), "친구가 다시 탔다")
	await get_tree().create_timer(0.5).timeout
	rider.dismount()
	_check(await _wait_until(func() -> bool: return not rider.is_active(), 3.0), "트럭을 세웠다")
	await _wait_file("b.done", 20.0)


func _rider() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	await _wait_file("driving", 20.0)
	await get_tree().create_timer(0.8).timeout
	await _teleport(Vector3(-148.6, 0.1, 140.0))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.PASSENGER, 4.0), "트럭 곁 상황 버튼 '%s'" % interaction.action_hud.current_text())
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return player.passenger.is_active(), 3.0), "짐칸에 탔다")
	await get_tree().create_timer(0.4).timeout
	_check(player.rig.riding_kind() == "boat", "앉은 자세")
	var start: Vector3 = player.global_position
	await _wait_file("drove", 20.0)
	_check(player.global_position.distance_to(start) > 6.0, "트럭을 따라 왔다 (%.1fm)" % player.global_position.distance_to(start))
	var off: Button = _village.get_node("HUD").find_child("PassengerOffButton", true, false) as Button
	_check(off != null and off.visible, "'내리기' 단추")
	await get_tree().create_timer(1.0).timeout
	off.pressed.emit()
	_check(await _wait_until(func() -> bool: return not player.passenger.is_active() and player.rig.riding_kind() == "", 3.0), "내렸다")
	await get_tree().create_timer(0.8).timeout
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.PASSENGER, 4.0), "다시 '같이 타기' (%s · %s · %d)" % [str(interaction.target), interaction.action_hud.current_text(), player.passenger.pick_target(player.global_position)])
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return player.passenger.is_active(), 3.0), "다시 탔다")
	_write("reboarded", "1")
	_check(await _wait_until(func() -> bool: return not player.passenger.is_active(), 10.0), "운전자가 세우면 같이 내린다")
