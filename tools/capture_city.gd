extends Node
## v0.21 탕정 제2지구 강변도시를 PNG로 찍는다 (아트 · 성능 확인용, 테스트 아님). tools/capture_city.sh 가 서버를 띄운다.
##   하늘에서 본 시내 · 곡교천 둔치 · 보 · 강 건너 침수 구시가지 · 리버파크 단지 · 탕정역 · 산업단지 · 거리 눈높이
##   찍을 때마다 그린 삼각형 · 그리기 수를 함께 출력한다 ([capture] … tris=… draws=…).
## 인자: -- --server=ws://… --out=/tmp/shots [--only=c03]

var _server: String = "ws://127.0.0.1:8080"
var _out: String = "user://shots"
var _only: String = ""
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
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
	var tris: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[capture] %s/%s.png tris=%d draws=%d" % [_out, file, tris, draws])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _put(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await _wait(0.8)


func _view(file: String, at: Vector3, distance: float, pitch: float, yaw_deg: float = 0.0, hud: bool = false) -> void:
	if not _only.is_empty() and not file.begins_with(_only):
		return
	var camera: FollowCamera = _village.get_node("CameraRig")
	(_village.get_node("HUD") as CanvasLayer).visible = hud
	camera.distance = distance
	camera.pitch_degrees = pitch
	camera.yaw_degrees = yaw_deg
	await _put(at)
	await _shot(file)


func _run() -> void:
	var camera: FollowCamera = _village.get_node("CameraRig")
	var base: Array[float] = [camera.distance, camera.pitch_degrees, camera.yaw_degrees]
	await _view("c00_map", Vector3(0.0, 0.1, 60.0), 260.0, 89.0)
	await _view("c01_downtown_sky", Vector3(0.0, 0.1, 40.0), 120.0, 55.0)
	await _view("c02_river_sky", Vector3(-20.0, 0.1, 150.0), 110.0, 40.0)
	await _view("c03_riverbank", Vector3(-30.0, 0.1, 140.0), 40.0, 80.0)
	await _view("c04_weir", Vector3(60.0, 0.1, 150.0), 30.0, 30.0)
	await _view("c05_flooded", Vector3(-80.0, 0.1, 158.0), 14.0, 12.0, 180.0)
	await _view("c05b_flooded_sky", Vector3(-80.0, 0.1, 230.0), 90.0, 40.0, 180.0)
	await _view("c06_estate", Vector3(-150.0, 0.1, 100.0), 70.0, 35.0)
	await _view("c07_station", Vector3(300.0, 0.1, 40.0), 70.0, 35.0)
	await _view("c08_industry", Vector3(0.0, 0.1, -250.0), 90.0, 40.0)
	await _view("c09_street", Vector3(150.0, 0.1, 104.0), base[0], base[1], base[2], true)
	await _view("c10_market", Vector3(180.0, 0.1, -100.0), 30.0, 26.0)
	await _view("c11_bridge", Vector3(262.0, 0.1, 140.0), 40.0, 26.0)
	await _view("c12_plaza", Vector3(0.0, 0.1, 66.0), base[0], base[1], base[2], true)
	# v0.21 M1 리버파크: 동 앞(공동현관) · 단지 하늘 · 놀이터 · 지하주차장 입구 · 강에서 본 단지.
	await _view("c13_lobby", Vector3(-182.0, 0.1, 44.0), 16.0, 14.0)
	await _view("c14_estate_sky", Vector3(-180.0, 0.1, 10.0), 150.0, 50.0)
	await _view("c15_playground", Vector3(-230.0, 0.1, -66.0), 26.0, 62.0)
	await _view("c16_parking", Vector3(-152.0, 0.1, 10.0), 30.0, 70.0)
	await _view("c17_estate_river", Vector3(-180.0, 0.1, 150.0), 50.0, 8.0)
