extends Node
## 차고 탈것 종단 테스트 (v19, 앱 안 테스트 서버 · tests/run_garage_e2e.sh).
##   휴대폰 "탈것" 앱: 매장에서 자전거 사기(한 번 더 눌러 확인) → 꾸미기(도색 · 전조등, 산 색은 공짜로 다시) → 성능 막대
##   → HUD 탈것 단추로 올라탐 → 페달(리그 위상 = 크랭크) · 빨라짐 · 미끄러짐 · 기울기 · 브레이크 → "내리기"
##   → 전기오토바이: 스로틀이 부드럽게 열리고(가속도가 덜컥이지 않음) 최고 속도 안, 놓으면 회생 제동 → 순간이동하면 내림 → 팔기

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

	# ---- 자전거 타기 ----
	button.pressed.emit()
	_check(await _wait_until(func() -> bool: return rider.is_riding(), 3.0), "탈것 단추로 올라탐")
	_check(rider.model != null and rider.model.get_parent() == player.rig and str(rider.model.fit.get("paint", "")) == "paint_mint", "꾸민 자전거 모형 (민트)")
	_check(player.rig.riding_kind() == "bike" and not player.is_input_locked(), "안장에 앉은 자세")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.RIDE_OFF, 2.0), "탄 동안 상황 버튼은 '내리기'")
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
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.RIDE_OFF, 2.0), "'내리기' 버튼 (%s · %s)" % [InteractionController.Target.keys()[interaction.target], interaction.action_hud.current_text()])
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return rider.state == GarageRider.State.OFF, 3.0), "내려서 탈것이 사라짐")
	_check(player.rig.riding_kind() == "" and absf(player.body.position.y - player.body_rest_height()) < 0.01, "다시 걷는 자세 · 몸 높이 원래대로")

	# ---- 전기오토바이: 부드러운 가감속 ----
	Net.request("veh_buy", {"model": "moto_sport"})
	_check(await _wait_until(func() -> bool: return Net.vehicles.size() == 2, 3.0), "전기오토바이도 산다")
	var moto: String = str(Net.vehicles[1].get("id", ""))
	# 광장 북쪽 길에서 동쪽으로 (가로막는 건물 없이 40m 넘게 달릴 수 있다).
	player.global_position = Vector3(-18.0, 0.1, 74.0)
	await get_tree().create_timer(0.3).timeout
	rider.toggle(moto)
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

	# ---- 순간이동하면 내린다 · 팔기 ----
	player.global_position += Vector3(0.0, 0.0, 20.0)
	_check(await _wait_until(func() -> bool: return rider.state == GarageRider.State.OFF, 1.0), "순간이동하면 바로 내림")
	var sol3: int = Net.sol
	Net.request("veh_sell", {"v": bike})
	_check(await _wait_until(func() -> bool: return Net.vehicles.size() == 1, 3.0), "자전거를 팔았다")
	var spent: int = 239000 + 39000 + 39000 + 59000 + 389000
	_check(Net.sol - sol3 == roundi(spent * GameData.garage.resale / 100.0) * 100, "산 값의 %d%% 를 돌려받음 (+%d)" % [roundi(GameData.garage.resale * 100.0), Net.sol - sol3])
