extends Node
## v0.26 차량 · 들이받기 · 보급 낙하 종단 테스트 (서버 1개 + Godot 1개, 밤 23시 · 크리처가 빨리 나온다 · tests/run_ram_e2e.sh):
##   미니트럭을 사서 "헬기 보급"으로 부른다 → 헬기 그림자가 지나가고 낙하산 상자가 떨어져 열린다 → 올라탄다 →
##   크리처에게 빠르게 달려들면 쾅 날아가고 (트럭은 조금 느려지고 내구도가 준다) → 천천히 닿으면 털썩 넘어지고 트럭이 확 느려진다.
## 인자: -- --server=ws://127.0.0.1:PORT [--shots=폴더]

var _server: String = ""
var _shots: String = ""
var _failures: Array[String] = []
var _village: Node = null
var _finished: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	if _failures.is_empty() and not _finished:
		_failures.append("테스트가 끝까지 돌지 않음")
	for f: String in _failures:
		print("[ram] FAIL: %s" % f)
	print("[ram] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[ram] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _shot(shot_name: String) -> void:
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(shot_name + ".png"))


func _stick_toward(dir: Vector3) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	var fwd: Vector3 = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	return Vector2(dir.dot(right), -dir.dot(fwd)).normalized()


## 20m 앞이 트인 방향 (8방향 가운데, 크리처에서 먼 쪽 먼저).
func _open_yaw(player: Player) -> float:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var best: float = 0.0
	var best_score: float = -INF
	for i: int in 8:
		var yaw: float = TAU * float(i) / 8.0
		var dir: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var from: Vector3 = player.global_position + Vector3(0, 0.7, 0)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * 22.0)
		q.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		var free: float = 22.0 if hit.is_empty() else from.distance_to(hit["position"])
		var away: float = 0.0
		for id: String in Net.creatures:
			var c: Dictionary = Net.creatures[id]
			away -= dir.dot(Vector3(float(c["x"]), 0, float(c["z"])) - player.global_position)
		var score: float = free * 10.0 + away * 0.1
		if score > best_score:
			best_score = score
			best = yaw
	return best


func _nearest_creature(at: Vector3, skip: Dictionary) -> String:
	var best: String = ""
	var best_d: float = INF
	for id: String in Net.creatures:
		if skip.has(id) or int(Net.creatures[id].get("f", 0)) != 0:
			continue
		var c: Dictionary = Net.creatures[id]
		var d: float = Vector2(float(c["x"]) - at.x, float(c["z"]) - at.z).length()
		if d < best_d:
			best_d = d
			best = id
	return best


## 크리처 쪽으로 몬다 (amount = 조이스틱 세기). 들이받으면 그 결과, 시간이 다 되면 빈 사전.
## max_speed 를 넘으면 손을 뗀다 (천천히 닿기).
func _drive_into(player: Player, amount: float, timeout_s: float, skip: Dictionary, max_speed: float = INF) -> Dictionary:
	var got: Array = [{}]
	var on_ram: Callable = func(info: Dictionary) -> void: got[0] = info
	Net.rammed.connect(on_ram)
	var waited: float = 0.0
	var stuck: float = 0.0
	var field: CreatureField = _village.get_node("Survival").creatures
	while (got[0] as Dictionary).is_empty() and waited < timeout_s:
		# 벽에 막혀 못 나아가면 조금 물러선다.
		var ds: VehicleDrive = player.garage_ride.drive_state
		stuck = stuck + get_process_delta_time() if absf(ds.speed) < 0.6 and player.joystick.output.length() > 0.3 else 0.0
		if stuck > 1.5:
			player.joystick.output = _stick_toward(-ds.forward())
			await get_tree().create_timer(1.2).timeout
			ds.yaw = _open_yaw(player)
			stuck = 0.0
		var id: String = _nearest_creature(player.global_position, skip)
		if not id.is_empty():
			var at: Vector3 = field.actor_position(id)
			var dir: Vector3 = ((at if at != Vector3.INF else player.global_position) - player.global_position) * Vector3(1, 0, 1)
			if dir.length() > 0.1:
				var drive: VehicleDrive = player.garage_ride.drive_state
				var too_fast: bool = absf(drive.speed) > max_speed
				# 빠르게 들이받기: 가까운데 아직 느리면 곧장 앞으로 달려 빠르기를 붙인 뒤 돌아 달려든다.
				var build_up: bool = max_speed == INF and drive.speed < float(GameData.survival.ram.get("fast", 4.2)) + 1.0 and dir.length() < 9.0
				if too_fast:
					player.joystick.output = Vector2.ZERO
				elif build_up:
					player.joystick.output = _stick_toward(drive.forward())
				else:
					player.joystick.output = _stick_toward(dir.normalized()) * amount
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not OS.get_environment("RAM_DEBUG").is_empty() and Engine.get_process_frames() % 30 == 0:
			var nid: String = _nearest_creature(player.global_position, skip)
			print("[dbg] speed=%.2f n=%d near=%s d=%.2f" % [_village.get_node("Player").garage_ride.drive_state.speed, Net.creatures.size(), nid, field.actor_position(nid).distance_to(player.global_position) if not nid.is_empty() else -1.0])
	player.joystick.output = Vector2.ZERO
	Net.rammed.disconnect(on_ram)
	return got[0]


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var parked: ParkedVehicles = interaction.parked
	var rider: GarageRider = player.garage_ride
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.5).timeout
	player.global_position = Vector3(-150.0, 0.1, 140.0)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.3).timeout
	_check(GameData.garage.model("car_truck") != null and GameData.garage.model("car_truck").kind == "car", "차량(미니트럭)이 매장에 있다")
	Net.request("veh_buy", {"model": "car_truck"})
	_check(await _wait_until(func() -> bool: return not Net.vehicles.is_empty(), 3.0), "미니트럭을 샀다")
	var id: String = str(Net.vehicles[0].get("id", ""))
	_check(is_equal_approx(Net.vehicle_health(id), 1.0), "내구도 가득")


	# ---- 헬기 보급 낙하 ----
	var sol0: int = Net.sol
	_check(rider.call_vehicle(id, true), "헬기 보급으로 부른다")
	_check(await _wait_until(func() -> bool: return parked.find_child("AirDrop", true, false) != null, 3.0), "보급 낙하가 시작됐다")
	var shadow_seen: Array = [false]
	var crate_seen: Array = [false]
	var watch: Callable = func() -> void:
		var now_drop: Node = parked.find_child("AirDrop", true, false)
		if now_drop != null:
			shadow_seen[0] = shadow_seen[0] or (now_drop.get_node("HeliShadow") as Node3D).visible
			crate_seen[0] = crate_seen[0] or (now_drop.get_node("Crate") as Node3D).visible
	get_tree().process_frame.connect(watch)
	_check(await _wait_until(func() -> bool: return crate_seen[0], 8.0), "헬기 그림자가 지나가며 낙하산 상자를 떨어뜨린다")
	await _shot("ram_airdrop_shadow")
	await get_tree().create_timer(2.6).timeout
	await _shot("ram_airdrop_falling")
	_check(await _wait_until(func() -> bool: return bool(parked.spot_of(id).get("arrived", false)), 10.0), "상자가 땅에 닿아 열리고 트럭이 나왔다")
	get_tree().process_frame.disconnect(watch)
	_check(shadow_seen[0], "헬기 그림자가 보였다")
	_check(Net.sol == sol0 - int(GameData.garage.delivery.get("air_cost", 0)), "보급 비용 (%s)" % Money.short(sol0 - Net.sol))
	await _shot("ram_airdrop_landed")

	# ---- 올라타기 ----
	# 크리처가 바로 곁이면 "공격"이 먼저라 (의도) 그때는 바로 올라탄다.
	var ride_button: bool = await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.VEHICLE, 3.0)
	_check(ride_button or interaction.target_id.begins_with("attack:"), "트럭 곁 상황 버튼 '타기' (%s)" % ("타기" if ride_button else "크리처가 곁이라 공격이 먼저"))
	if ride_button:
		interaction.action_hud.action_pressed.emit()
	else:
		rider.mount(id)
	_check(await _wait_until(func() -> bool: return rider.is_riding(), 4.0), "트럭에 올라탔다")
	_check(rider.info != null and rider.info.kind == "car" and rider.model != null, "차량 모형")
	# 기다리는 동안 맞았으면 구급상자로 채운다.
	for i: int in Net.inventory.size():
		if Net.hp < 7 and Net.inventory[i] != null and Net.inventory[i].id == "first_aid_kit":
			Net.use_item(i)
			break

	# ---- 빠르게 들이받기 ----
	_check(await _wait_until(func() -> bool: return not Net.creatures.is_empty(), 15.0), "크리처가 나타났다 (%d)" % Net.creatures.size())
	# 먼저 크리처 떼에서 빠져나간다 (달리는 동안은 붙잡히지 않는다) → 멀리서 돌아 달려든다.
	rider.drive_state.yaw = _open_yaw(player)
	player.joystick.output = _stick_toward(rider.drive_state.forward())
	await get_tree().create_timer(3.0).timeout
	player.joystick.output = Vector2.ZERO
	var skip: Dictionary = {}
	var hard: Dictionary = {}
	var before_speed: float = 0.0
	for attempt: int in 6:
		hard = await _drive_into(player, 1.0, 10.0, skip)
		if not hard.is_empty() and bool(hard.get("hard", false)):
			break
		if not hard.is_empty():
			skip[str(hard.get("c", ""))] = true
	_check(not hard.is_empty() and bool(hard.get("hard", false)), "빠르게 들이받았다 (날아가는 빠르기 %.1f m/s, 피해 %d)" % [float(hard.get("u", 0.0)), int(hard.get("dmg", 0))])
	var victim: String = str(hard.get("c", ""))
	_check(float(hard.get("slow", 1.0)) < 0.2, "무거운 트럭은 조금만 느려진다 (%.2f)" % float(hard.get("slow", 1.0)))
	var flew_from: Vector3 = Vector3(float(Net.creatures.get(victim, {}).get("x", 0.0)), 0.0, float(Net.creatures.get(victim, {}).get("z", 0.0)))
	await get_tree().create_timer(0.25).timeout
	await _shot("ram_hit")
	_check(await _wait_until(func() -> bool: return Net.vehicle_health(id) < 1.0, 2.0), "트럭 내구도가 조금 줄었다 (%d%%)" % roundi(Net.vehicle_health(id) * 100.0))
	var health_label: Label = _village.get_node("HUD").find_child("VehicleHealth", true, false) as Label
	_check(health_label != null and health_label.visible and health_label.text.begins_with("내구도"), "속도계 아래 내구도 '%s'" % (health_label.text if health_label != null else "-"))
	var landed: Array = [Vector3.INF]
	await _wait_until(func() -> bool:
		if not Net.creatures.has(victim):
			return true
		var c: Dictionary = Net.creatures[victim]
		if int(c.get("f", 0)) != 1:
			landed[0] = Vector3(float(c["x"]), 0.0, float(c["z"]))
			return true
		return false, 4.0)
	if landed[0] != Vector3.INF:
		_check(flew_from.distance_to(landed[0]) > 2.0, "멀리 날아갔다 (%.1fm)" % flew_from.distance_to(landed[0]))
	else:
		_check(true, "날아가 쓰러졌다 (한 방에)")

	# ---- 천천히 닿기 ----
	player.joystick.output = _stick_toward(-rider.drive_state.forward())
	await _wait_until(func() -> bool: return absf(rider.drive_state.speed) < 0.3, 3.0)
	player.joystick.output = Vector2.ZERO
	skip[victim] = true
	var soft: Dictionary = {}
	for attempt: int in 4:
		soft = await _drive_into(player, 0.4, 14.0, skip, 2.4)
		if not soft.is_empty() and not bool(soft.get("hard", true)):
			break
		if not soft.is_empty():
			skip[str(soft.get("c", ""))] = true
	_check(not soft.is_empty() and not bool(soft.get("hard", true)), "천천히 닿으면 털썩 넘어진다 (%s)" % str(soft))
	var fallen: String = str(soft.get("c", ""))
	_check(await _wait_until(func() -> bool: return int(Net.creatures.get(fallen, {}).get("f", 0)) == 2, 1.5), "넘어져 누워 있다")
	_check(absf(rider.drive_state.speed) <= float(GameData.survival.ram.get("contact_top", 1.6)) + 0.6, "트럭이 확 느려졌다 (%.2f m/s)" % rider.drive_state.speed)
	await _shot("ram_soft")
	player.joystick.output = Vector2.ZERO
	rider.dismount()
	_check(await _wait_until(func() -> bool: return not rider.is_active(), 3.0), "내렸다")
	_finished = true
