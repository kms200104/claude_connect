extends Node
## 마을 경제(v0.8) 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). 실제 렌더러가 필요하다. tools/capture_town.sh 가 서버를 띄운다.
##   하늘에서 본 식당·아파트·성성호수 · 아파트 단지 · 영업 중인 식당과 앉은 손님 · 주방 창과 요리 동작 · 상차림과 별점
##   · 휴대폰(증권 · 부동산 · 은행 · 자산) · 들판 채집물 · 성성호수 낚시
## 인자: -- --server=ws://… --out=/tmp/shots

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


func _put(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await _wait(0.6)


func _run() -> void:
	var camera: FollowCamera = _village.get_node("CameraRig")
	var hud: CanvasLayer = _village.get_node("HUD")
	var econ: EconomyController = _village.get_node("EconomyController")
	var restaurant: RestaurantSite = _village.get_node("Restaurant")
	var player: Player = _village.get_node("Player")
	var base_distance: float = camera.distance
	var base_pitch: float = camera.pitch_degrees
	# 집 한 채를 사 두고, 친구 집처럼 보이게 하나 더 (깃발 색 확인).
	Economy.buy_home("102-801", 0)
	Economy.buy_home("101-1001", 0)
	Economy.order_stock("SBE", "buy", 30)
	Economy.order_stock("CAM", "buy", 10)
	await _wait(1.0)

	hud.visible = false
	camera.distance = 70.0
	camera.pitch_degrees = 55.0
	await _put(Vector3(52.0, 0.1, 40.0))
	await _wait(1.0)
	await _shot("t01_town_sky")
	camera.distance = 36.0
	camera.pitch_degrees = 22.0
	await _put(Vector3(63.0, 0.1, 50.0), PI)
	await _shot("t02_apartments")
	camera.distance = 16.0
	camera.pitch_degrees = 30.0
	await _put(Vector3(58.5, 0.1, 38.5), PI)
	await _shot("t03_estate_office")

	# 식당 열기 → 손님
	await _put(restaurant.counter_position() + Vector3(0.0, 0.1, 0.0), 0.0)
	Economy.open_restaurant()
	await _wait_until(func() -> bool: return Economy.orders.size() >= 3, 12.0)
	await _wait(1.5)
	camera.distance = 13.0
	camera.pitch_degrees = 38.0
	camera.yaw_degrees = 35.0
	await _put(restaurant.counter_position() + Vector3(0.0, 0.1, 4.0), 0.0)
	await _shot("t04_restaurant_guests")
	camera.yaw_degrees = 0.0
	camera.distance = 18.0
	camera.pitch_degrees = 26.0
	await _put(restaurant.counter_position() + Vector3(0.0, 0.1, 0.0), 0.0)
	await _shot("t05_restaurant_front")

	# 주방: 요리 동작 (화면 포함)
	hud.visible = true
	econ.kitchen.open()
	await _wait(0.5)
	camera.distance = base_distance
	camera.pitch_degrees = base_pitch
	camera.snap_to_target()
	await _shot("t06_kitchen_orders")
	var first: String = ""
	for id: String in Economy.orders:
		first = id
		break
	if not first.is_empty():
		econ.kitchen.call("_start_cooking", first)
		_play_minigame(econ.kitchen)
		await _wait(1.2)
		await _shot("t07_cooking")
		hud.visible = false
		camera.distance = 3.6
		camera.pitch_degrees = 18.0
		camera.yaw_degrees = 20.0
		camera.snap_to_target()
		await _wait(0.4)
		await _shot("t08_cook_closeup")
		hud.visible = true
		await _wait_until(func() -> bool: return econ.kitchen.get("_mode") != KitchenWindow.Mode.COOKING, 20.0)
		await _wait(0.6)
		camera.distance = 9.0
		camera.pitch_degrees = 34.0
		camera.yaw_degrees = 0.0
		camera.snap_to_target()
		await _wait(0.6)
		await _shot("t09_served")
	econ.kitchen.close()
	camera.yaw_degrees = 0.0
	camera.distance = base_distance
	camera.pitch_degrees = base_pitch

	# 휴대폰 네 앱
	await _put(Vector3(10.0, 0.1, 10.0))
	econ.phone.open(PhoneWindow.Tab.STOCKS)
	econ.phone.set("_stock_id", "SBE")
	econ.phone.call("_rebuild")
	await _wait(0.6)
	await _shot("t10_phone_stocks")
	econ.phone.open(PhoneWindow.Tab.HOMES)
	econ.phone.set("_unit_id", "102-801")
	econ.phone.set("_building", "102")
	econ.phone.call("_rebuild")
	await _wait(0.6)
	await _shot("t11_phone_homes")
	econ.phone.open(PhoneWindow.Tab.BANK)
	await _wait(0.8)
	await _shot("t12_phone_bank")
	econ.phone.open(PhoneWindow.Tab.ASSETS)
	await _wait(0.6)
	await _shot("t13_phone_assets")
	econ.phone.close()

	# 채집물 · 성성호수
	for d: DropInfo in Net.drops.values():
		if d.kind == DropInfo.KIND_FORAGE:
			await _put(d.position + Vector3(1.4, 0.1, 1.6))
			await _shot("t14_forage")
			break
	var spot: SpotInfo = GameData.spots.get("seongseong")
	camera.distance = base_distance + 4.0
	await _put(Vector3(spot.center.x - 2.0, 0.1, spot.center.y - spot.half_extent.y - 0.9), PI)
	await _shot("t15_seongseong")
	player.rig.set_sitting(false)


## 미니게임을 솜씨 좋게 친다 (상차림·별점 장면이 높은 별로 나오게).
func _play_minigame(kitchen: KitchenWindow) -> void:
	var tapped_step: int = -1
	var beat: int = 0
	while kitchen.get("_mode") == KitchenWindow.Mode.COOKING:
		var step: Dictionary = kitchen.get("_step")
		var index: int = kitchen.get("_step_index")
		var t: float = float(Time.get_ticks_msec()) - float(kitchen.get("_step_start_ms"))
		if index != tapped_step:
			tapped_step = index
			beat = 0
		match str(step.get("kind", "")):
			"beats":
				if beat < int(step.get("beats", 4)) and t >= float(step.get("interval_ms", 480)) * float(beat + 1):
					kitchen.call("_on_tap")
					beat += 1
			"timing":
				if beat == 0 and t >= float(step.get("ideal_ms", 2000)):
					kitchen.call("_on_tap")
					beat = 1
			_:
				if t >= float(beat) * 120.0 and beat < int(step.get("taps", 10)) + 2:
					kitchen.call("_on_tap")
					beat += 1
		await get_tree().process_frame
