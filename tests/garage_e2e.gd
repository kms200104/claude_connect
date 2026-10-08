extends Node
## 차고 탈것 종단 테스트 (v19, 앱 안 테스트 서버 · tests/run_garage_e2e.sh).
##   휴대폰 "탈것" 앱: 매장에서 자전거 사기(한 번 더 눌러 확인) → 꾸미기(도색 · 전조등, 산 색은 공짜로 다시) → 성능 막대
##   → HUD 탈것 단추(휴대폰 단추와 안 겹침)로 부르기 → 주민이 타고 와서 곁에 세우고 떠남 → "타기"
##   → 페달(리그 위상 = 크랭크) · 빨라짐 · 미끄러짐 · 기울기 · 브레이크 → "세우기" (그 자리에 남음)
##   → 앱에서 오토바이 부르기 → 스로틀이 부드럽게 열리고(가속도가 덜컥이지 않음) 최고 속도 안, 놓으면 회생 제동
##   → 탄 채 자전거 불러 바꿔 타기 → 순간이동하면 떠나기 전 자리에 세움 → 팔기

var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalTestServer.SAVE_PATH))
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[garage] FAIL: %s" % f)
	print("[garage] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[garage] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _press(app: Node, node_name: String) -> bool:
	var b: Button = app.find_child(node_name, true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _find_app(root: Node) -> VehicleApp:
	for c: Node in root.get_children():
		if c is VehicleApp:
			return c
		var found: VehicleApp = _find_app(c)
		if found != null:
			return found
	return null


## --shots=폴더 를 주고 화면이 있는 채로 돌리면 (xvfb) 그 장면을 PNG 로 남긴다.
func _shot(shot_name: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [arg.trim_prefix("--shots="), shot_name])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _find_courier(root: Node) -> VehicleCourier:
	for c: Node in root.get_children():
		if c is VehicleCourier and not c.is_queued_for_deletion():
			return c
	return null


## 그 월드 방향으로 미는 조이스틱 값 (카메라 기준).
func _stick_toward(dir: Vector3) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z).normalized()
	var fwd: Vector3 = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z).normalized()
	return Vector2(dir.dot(right), -dir.dot(fwd)).normalized()


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var rider: GarageRider = _village.get_node("GarageRide")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var phone: PhoneWindow = _village.get_node("HUD/PhoneWindow")
	Net.play_on_test_server()
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 5.0), "앱 안 테스트 서버로 접속")
	_check(rider.player == player and player.garage_ride == rider, "차고 탈것 타기가 캐릭터에 붙음")
	Net.request("dev_grant")
	_check(await _wait_until(func() -> bool: return Net.sol > 100000000, 3.0), "테스트 솔 받기")
	player.global_position = Vector3(-44.0, 0.1, 66.0)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout
	var button: Button = _village.get_node("HUD").find_child("GarageButton", true, false) as Button
	_check(button != null and not button.visible, "탈것이 없으면 HUD 탈것 단추는 숨김")

	# ---- 매장에서 사기 ----
	phone.open(PhoneWindow.Tab.VEHICLE)
	await get_tree().create_timer(0.3).timeout
	var app: VehicleApp = _find_app(phone)
	_check(app != null, "휴대폰 탈것 앱이 열림")
	var models: int = 0
	for m: VehicleCatalog.Model in GameData.garage.models:
		if app.find_child("Model_%s" % m.id, true, false) != null:
			models += 1
	_check(models == 7, "매장에 자전거 4 · 전기오토바이 3 (%d)" % models)
	_check(_press(app, "Model_bike_city"), "생활 자전거 고르기")
	await get_tree().create_timer(0.1).timeout
	_check(app.find_child("Preview", true, false) is SubViewportContainer, "3D 미리보기가 돈다")
	var sol0: int = Net.sol
	_press(app, "BuyButton")
	await get_tree().create_timer(0.1).timeout
	_check(Net.vehicles.is_empty() and (app.find_child("BuyButton", true, false) as Button).text.begins_with("정말"), "한 번 누르면 확인을 묻는다")
	_press(app, "BuyButton")
	_check(await _wait_until(func() -> bool: return Net.vehicles.size() == 1, 3.0), "두 번 누르면 산다")
	_check(Net.sol == sol0 - 239000, "값 239,000솔을 냈다 (%d)" % (sol0 - Net.sol))
	var bike: String = str(Net.vehicles[0].get("id", ""))

	# ---- 꾸미기 ----
	await get_tree().create_timer(0.2).timeout
	_check(app.find_child("Slot_paint", true, false) != null and app.find_child("Slot_glow", true, false) != null, "산 뒤 바로 꾸미기 화면 (칸 고르기)")
	var sol1: int = Net.sol
	_check(_press(app, "Part_paint_mint"), "민트 도색 고르기")
	_check(await _wait_until(func() -> bool: return str((Net.vehicle(bike).get("fit", {}) as Dictionary).get("paint", "")) == "paint_mint", 3.0), "민트로 칠했다")
	_check(Net.sol == sol1 - 39000, "도색 값 39,000솔")
	await get_tree().create_timer(0.1).timeout
	_press(app, "Part_paint_cherry")
	await _wait_until(func() -> bool: return str((Net.vehicle(bike).get("fit", {}) as Dictionary).get("paint", "")) == "paint_cherry", 3.0)
	var sol2: int = Net.sol
	await get_tree().create_timer(0.1).timeout
	_press(app, "Part_paint_mint")
	_check(await _wait_until(func() -> bool: return str((Net.vehicle(bike).get("fit", {}) as Dictionary).get("paint", "")) == "paint_mint", 3.0) and Net.sol == sol2, "산 적 있는 색은 공짜로 다시 칠한다")
	await get_tree().create_timer(0.1).timeout
	_press(app, "Slot_light")
	await get_tree().create_timer(0.1).timeout
	_check(_press(app, "Part_light_hi"), "고휘도 전조등 고르기")
	_check(await _wait_until(func() -> bool: return str((Net.vehicle(bike).get("fit", {}) as Dictionary).get("light", "")) == "light_hi", 3.0), "전조등을 끼웠다")
	await get_tree().create_timer(0.1).timeout
	_press(app, "Slot_drive")
	await get_tree().create_timer(0.1).timeout
	_press(app, "Part_drive_gear11")
	_check(await _wait_until(func() -> bool: return str((Net.vehicle(bike).get("fit", {}) as Dictionary).get("drive", "")) == "drive_gear11", 3.0), "11단 구동계 (성능 업그레이드)")
	var stats: VehicleCatalog.Stats = GameData.garage.stats("bike_city", Net.vehicle(bike).get("fit", {}) as Dictionary)
	_check(absf(stats.top - 6.2 * 1.13) < 0.001, "최고 속도가 13%% 올랐다 (%.2f m/s)" % stats.top)
	phone.close()
	await get_tree().create_timer(0.4).timeout
	_check(button.visible, "탈것이 생기면 HUD 탈것 단추가 보인다")
	var phone_button: Button = _village.get_node("HUD").find_child("PhoneButton", true, false) as Button
	_check(phone_button != null and not button.get_global_rect().intersects(phone_button.get_global_rect()), "탈것 단추가 휴대폰 단추에 가리지 않는다")
	var parked: ParkedVehicles = _village.get_node("ParkedVehicles")

	# ---- 부르기: 동네 주민이 타고 와서 곁에 세워 두고 간다 ----
	_check(interaction.target != InteractionController.Target.VEHICLE, "부르기 전에는 곁에 탈것이 없다")
	button.pressed.emit()
	_check(await _wait_until(func() -> bool: return parked.courier_count() == 1, 3.0), "탈것 단추를 누르면 주민이 탈것을 타고 온다")
	var courier: VehicleCourier = _find_courier(parked)
	_check(courier != null and not courier.npc_id.is_empty() and courier.rig.riding_kind() == "bike", "주민이 자전거를 타고 온다 (%s)" % (courier.npc_id if courier != null else "-"))
	var spot: Dictionary = parked.spot_of(bike)
	_check(not spot.is_empty() and _flat(spot["at"], player.global_position) <= 4.0, "내 곁에 세울 자리")
	var far0: float = _flat(courier.global_position, spot["at"]) if courier != null else 0.0
	await get_tree().create_timer(1.5).timeout
	await _shot("1_courier")
	var far1: float = _flat(courier.global_position, spot["at"]) if is_instance_valid(courier) else 0.0
	_check(far0 > 3.0 and far1 < far0 - 0.5, "멀리서 다가온다 (%.1fm → %.1fm)" % [far0, far1])
	_check(interaction.target != InteractionController.Target.VEHICLE, "오는 중에는 아직 탈 수 없다")
	_check(await _wait_until(func() -> bool: return parked.courier_count() == 0, 9.0), "세워 두고 내린다")
	_check(parked.nearest_own(player.global_position, GarageRider.RIDE_RANGE) == bike, "탈것이 곁에 세워져 있다")
	await get_tree().create_timer(0.3).timeout
	await _shot("2_wave")
	_check(await _wait_until(func() -> bool: return _find_courier(parked) == null, 6.0), "손을 흔들고 걸어서 떠난다")

	# ---- 타기 ----
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.VEHICLE, 2.0) and interaction.action_hud.current_text() == "타기", "곁에 가면 상황 버튼 '타기'")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return rider.is_riding(), 3.0), "세워 둔 자전거에 올라탐")
	_check(rider.model != null and rider.model.get_parent() == player.rig and str(rider.model.fit.get("paint", "")) == "paint_mint", "꾸민 자전거 모형 (민트)")
	_check(player.rig.riding_kind() == "bike" and not player.is_input_locked(), "안장에 앉은 자세")
	_check(parked.spot_of(bike).is_empty(), "탄 자전거는 세워 둔 목록에서 빠짐")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.RIDE_OFF and interaction.action_hud.current_text() == "세우기", 2.0), "탄 동안 상황 버튼은 '세우기'")
	var start: Vector3 = player.global_position
	var top: Array[float] = [0.0]
	var phase_ok: Array[bool] = [true]
	var watch: Callable = func() -> void:
		top[0] = maxf(top[0], rider.drive_state.speed)
		if rider.model != null and absf(rider.model.pedal_phase - player.rig.pedal_phase()) > 0.001:
			phase_ok[0] = false
	get_tree().process_frame.connect(watch)
	# 카메라 앞쪽을 보고 출발 (반대쪽이면 먼저 제자리에서 돈다).
	var cam: Camera3D = get_viewport().get_camera_3d()
	rider.drive_state.yaw = atan2(cam.global_basis.z.x, cam.global_basis.z.z)
	var phase0: float = player.rig.pedal_phase()
	Input.action_press(&"ui_up")
	await get_tree().create_timer(0.5).timeout
	var early: float = rider.drive_state.speed
	await get_tree().create_timer(2.5).timeout
	_check(early > 0.3 and rider.drive_state.speed > early + 1.5, "페달을 밟으면 점점 빨라짐 (%.2f → %.2f m/s)" % [early, rider.drive_state.speed])
	_check(top[0] <= stats.top + 0.01, "최고 속도 안 (%.2f / %.2f)" % [top[0], stats.top])
	_check(player.global_position.distance_to(start) > 8.0, "앞으로 나아감 (%.1fm)" % player.global_position.distance_to(start))
	_check(absf(player.rig.pedal_phase() - phase0) > 0.01 and phase_ok[0], "페달이 돌고 크랭크가 발(리그 위상)과 같이 돈다")
	Input.action_release(&"ui_up")
	var coast: float = rider.drive_state.speed
	await get_tree().create_timer(0.8).timeout
	_check(rider.drive_state.speed < coast and rider.drive_state.speed > coast - 1.5, "손을 떼면 천천히 미끄러짐 (%.2f → %.2f)" % [coast, rider.drive_state.speed])
	Input.action_press(&"ui_up")
	await get_tree().create_timer(1.0).timeout
	Input.action_press(&"ui_right")
	await get_tree().create_timer(0.5).timeout
	_check(rider.drive_state.lean < -0.05 and player.body.global_basis.y.dot(Vector3.UP) < 0.998, "오른쪽으로 돌면 안쪽(오른쪽)으로 기운다 (%.2f)" % rider.drive_state.lean)
	Input.action_release(&"ui_right")
	Input.action_release(&"ui_up")
	await get_tree().create_timer(0.2).timeout
	var fast: float = rider.drive_state.speed
	player.joystick.output = _stick_toward(-rider.drive_state.forward())
	_check(await _wait_until(func() -> bool: return rider.drive_state.speed < 0.4, 2.0), "반대로 밀면 브레이크로 선다 (%.2f m/s 에서)" % fast)
	player.joystick.output = Vector2.ZERO
	get_tree().process_frame.disconnect(watch)
	await get_tree().create_timer(0.4).timeout
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.RIDE_OFF, 2.0), "'세우기' 버튼 (%s · %s)" % [InteractionController.Target.keys()[interaction.target], interaction.action_hud.current_text()])
	var stop_at: Vector3 = player.global_position
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return rider.state == GarageRider.State.OFF, 3.0), "내려섬")
	_check(player.rig.riding_kind() == "" and absf(player.body.position.y - player.body_rest_height()) < 0.01, "다시 걷는 자세 · 몸 높이 원래대로")
	var stood: Dictionary = parked.spot_of(bike)
	_check(not stood.is_empty() and _flat(stood["at"], stop_at) < 0.3 and _flat(player.global_position, stop_at) > 0.5, "자전거는 사라지지 않고 그 자리에 세워 둠 · 사람은 옆으로 내려섬")
	_check(await _wait_until(func() -> bool: return not Net.parked_of(bike).is_empty(), 2.0), "서버에도 세워 둔 자리가 남는다")
	await _shot("3_parked")

	# ---- 전기오토바이: 부드러운 가감속 ----
	Net.request("veh_buy", {"model": "moto_sport"})
	_check(await _wait_until(func() -> bool: return Net.vehicles.size() == 2, 3.0), "전기오토바이도 산다")
	var moto: String = str(Net.vehicles[1].get("id", ""))
	# 광장 북쪽 길에서 동쪽으로 (가로막는 건물 없이 40m 넘게 달릴 수 있다). 휴대폰 앱에서 부른다.
	player.global_position = Vector3(-18.0, 0.1, 74.0)
	await get_tree().create_timer(0.3).timeout
	phone.open(PhoneWindow.Tab.VEHICLE)
	await get_tree().create_timer(0.3).timeout
	app = _find_app(phone)
	_check(app != null and _press(app, "Call_%s" % moto), "휴대폰 앱에서 오토바이 부르기")
	_check(await _wait_until(func() -> bool: return not phone.visible and parked.courier_count() == 1, 3.0), "휴대폰을 닫고 주민이 오토바이를 타고 온다")
	_check(await _wait_until(func() -> bool: return parked.nearest_own(player.global_position, GarageRider.RIDE_RANGE) == moto, 9.0), "오토바이가 곁에 세워짐")
	button.pressed.emit()
	await _wait_until(func() -> bool: return rider.is_riding(), 3.0)
	rider.drive_state.yaw = -PI * 0.5
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.2).timeout
	var east: Vector2 = _stick_toward(Vector3.RIGHT)
	_check(await _wait_until(func() -> bool: return rider.is_riding(), 3.0) and player.rig.riding_kind() == "moto", "오토바이에 올라탐")
	var info_top: float = rider.drive_state.stats.top
	var samples: Array[float] = []
	var sample: Callable = func() -> void: samples.append(rider.drive_state.accel)
	get_tree().physics_frame.connect(sample)
	player.joystick.output = east
	await get_tree().create_timer(0.25).timeout
	var launch: float = rider.drive_state.speed
	await get_tree().create_timer(3.0).timeout
	var cruise: float = rider.drive_state.speed
	player.joystick.output = Vector2.ZERO
	await get_tree().create_timer(1.0).timeout
	get_tree().physics_frame.disconnect(sample)
	var jump: float = 0.0
	for i: int in range(1, samples.size()):
		jump = maxf(jump, absf(samples[i] - samples[i - 1]))
	_check(launch < 1.0, "스로틀은 천천히 열려 출발이 부드럽다 (0.25초에 %.2f m/s)" % launch)
	_check(cruise > info_top * 0.6 and cruise <= info_top + 0.01, "힘차게 가속해 최고 속도 안 (%.1f / %.1f m/s)" % [cruise, info_top])
	_check(jump < 0.35, "가속도가 덜컥이지 않는다 (한 프레임 최대 변화 %.2f m/s²)" % jump)
	_check(rider.drive_state.speed < cruise - 0.5 and rider.drive_state.speed > cruise - 4.0, "스로틀을 놓으면 회생 제동으로 부드럽게 준다 (%.1f → %.1f)" % [cruise, rider.drive_state.speed])
	_check(rider.speed_kmh() > 1.0, "속도계 (%d km/h)" % roundi(rider.speed_kmh()))

	# ---- 바꿔 타기: 오토바이를 탄 채 자전거를 불러 옮겨 탄다 (오토바이는 그 자리에 세워 둔다) ----
	await _wait_until(func() -> bool: return rider.drive_state.speed < 0.2, 6.0)
	rider.call_vehicle(bike)
	_check(await _wait_until(func() -> bool: return parked.nearest_own(player.global_position, GarageRider.RIDE_RANGE) == bike, 10.0), "타는 중에도 다른 탈것을 부를 수 있다")
	_check(rider.mount(bike), "곁에 온 자전거로 바꿔 타기")
	_check(await _wait_until(func() -> bool: return rider.is_riding() and rider.vehicle_id == bike and player.rig.riding_kind() == "bike", 3.0), "자전거로 바꿔 탔다")
	_check(not parked.spot_of(moto).is_empty() and parked.spot_of(bike).is_empty(), "오토바이는 그 자리에 세워 둠")
	_check(rider.model != null and rider.model.model_id == "bike_city" and rider.model.get_parent() == player.rig, "자전거 모형으로 바뀜")

	# ---- 순간이동하면 떠나기 전 자리에 세운다 · 팔기 ----
	var before_tp: Vector3 = player.global_position
	player.global_position += Vector3(0.0, 0.0, 20.0)
	_check(await _wait_until(func() -> bool: return rider.state == GarageRider.State.OFF, 1.0), "순간이동하면 바로 내림")
	_check(not parked.spot_of(bike).is_empty() and _flat(parked.spot_of(bike)["at"], before_tp) < 1.0, "떠나기 전 자리에 세워 둠")
	var sol3: int = Net.sol
	Net.request("veh_sell", {"v": bike})
	_check(await _wait_until(func() -> bool: return Net.vehicles.size() == 1, 3.0), "자전거를 팔았다")
	var spent: int = 239000 + 39000 + 39000 + 59000 + 389000
	_check(Net.sol - sol3 == roundi(spent * GameData.garage.resale / 100.0) * 100, "산 값의 %d%% 를 돌려받음 (+%d)" % [roundi(GameData.garage.resale * 100.0), Net.sol - sol3])
