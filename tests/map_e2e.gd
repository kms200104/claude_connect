extends Node
## v0.28.1 지도 종단 테스트 (서버 1개 + Godot 1개): 휴대폰 지도가 내 자리를 가운데 두고 따라가고, ＋ · － 로 확대 · 축소,
## 끌면 옮겨지고 "내 위치"로 돌아온다. 빈 곳을 누르면 웨이포인트 → 마을에 빛기둥 · HUD 화살표 "웨이포인트 Nm" · 작은 지도 표시,
## 가까이 가면 "도착" 하고 지워진다.
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
		print("[map] FAIL: %s" % f)
	print("[map] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[map] %s: %s" % ["ok  " if ok else "FAIL", what])
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
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(shot_name + ".png"))


func _teleport(at: Vector3) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _run() -> void:
	var economy: EconomyController = _village.get_node("EconomyController")
	var marker: WaypointMarker = _village.get_node("Waypoint")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.6).timeout
	Waypoint.clear()
	var me: Vector3 = Vector3(-120.0, 0.1, 130.0)
	await _teleport(me)
	var phone: PhoneWindow = economy.phone
	phone.open(PhoneWindow.Tab.MAP)
	await get_tree().create_timer(0.6).timeout
	var map: MapApp = phone.app_view() as MapApp
	_check(map != null, "지도 앱")
	if map == null:
		return
	_check(map.view_center().distance_to(Vector2(me.x, me.z)) < 1.0, "내 자리가 가운데 (%s)" % str(map.view_center()))
	var half0: float = map.view_half()
	(map.find_child("ZoomIn", true, false) as Button).pressed.emit()
	_check(map.view_half() < half0, "＋ 로 확대 (%.0f → %.0f)" % [half0, map.view_half()])
	for i: int in 3:
		(map.find_child("ZoomOut", true, false) as Button).pressed.emit()
	_check(map.view_half() > half0, "－ 로 축소 (%.0f)" % map.view_half())
	await _shot("map_zoomed_out")
	# 끌어서 옮기기 → 내 위치.
	var canvas: Control = map.find_child("MapCanvas", true, false) as Control
	var c: Vector2 = canvas.size * 0.5
	map.call("_press", 0, c, true)
	map.call("_drag", 0, c + Vector2(120.0, 0.0))
	map.call("_press", 0, c + Vector2(120.0, 0.0), false)
	_check(map.view_center().distance_to(Vector2(me.x, me.z)) > 5.0 and not Waypoint.is_set(), "끌면 지도가 옮겨지고 웨이포인트는 놓이지 않는다")
	(map.find_child("CenterMe", true, false) as Button).pressed.emit()
	_check(map.view_center().distance_to(Vector2(me.x, me.z)) < 1.0, "'내 위치'로 돌아온다")
	# 빈 곳 누르기 → 웨이포인트 (내 자리에서 오른쪽 위, 표시가 드문 만큼 확대해서).
	for i: int in 4:
		(map.find_child("ZoomIn", true, false) as Button).pressed.emit()
	map.tap_at(c + Vector2(canvas.size.x * 0.3, -canvas.size.y * 0.2))
	_check(Waypoint.is_set(), "빈 곳을 누르면 웨이포인트 (%s, 고른 표시 '%s')" % [str(Waypoint.at), map.picked()])
	var target: Vector2 = Waypoint.at
	_check(target.x > me.x and target.y < me.z, "누른 쪽에 놓였다 (동북쪽)")
	await get_tree().create_timer(0.3).timeout
	await _shot("map_waypoint")
	phone.close()
	await get_tree().create_timer(0.6).timeout
	_check(marker.visible and Vector2(marker.global_position.x, marker.global_position.z).distance_to(target) < 0.1, "마을에 빛기둥")
	var chip: Control = marker.get("_chip")
	var text: Label = marker.get("_text")
	_check(chip.visible and text.text.begins_with("웨이포인트") and text.text.ends_with("m"), "HUD '%s'" % text.text)
	await _teleport(Vector3(target.x, 0.1, target.y) + Vector3(0.0, 0.0, 9.0))
	await _shot("waypoint_world")
	await _teleport(Vector3(target.x + 1.0, 0.1, target.y))
	_check(await _wait_until(func() -> bool: return not Waypoint.is_set(), 2.0), "가까이 가면 도착 · 지워진다")
	_check(await _wait_until(func() -> bool: return not chip.visible and not marker.visible, 1.0), "빛기둥 · 화살표가 사라졌다")
	_finished = true
