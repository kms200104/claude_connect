extends Node
## v0.9 화면을 PNG로 찍는다 (아트·연출 확인용, 테스트 아님). 실제 렌더러가 필요하다. tools/capture_coop.sh 가 서버를 띄운다.
##   첫 화면 항공뷰 · 동사무소(하늘 · 창구 · 창) · 갈대 여울(얕은 물 · 깊은 물 · 물고기 떼 · 뜰채) · 바닷가 조개 숨구멍 · 삽 구덩이/흙길
## 인자: -- --srv=ws://… --out=/tmp/shots

var _server: String = "ws://127.0.0.1:8080"
var _out: String = "user://shots"
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		# --server= 를 쓰면 첫 화면이 건너뛰어지므로(TitleScreen) 다른 이름으로 받는다.
		if arg.begins_with("--srv="):
			_server = arg.trim_prefix("--srv=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	# 첫 화면: 비행기에서 내려다보듯.
	var title: TitleScreen = load("res://ui/title/title_screen.tscn").instantiate()
	add_child(title)
	await _wait(2.5)
	await _shot("v01_title_aerial")
	await _wait(6.0)
	await _shot("v02_title_aerial_later")
	title.queue_free()
	await _wait(0.3)
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


func _put(at: Vector3, face: Vector3 = Vector3.FORWARD) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.look_toward(face)
	player.body.rotation.y = atan2(-face.x, -face.z)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await _wait(0.6)


func _hold(item_id: String) -> void:
	var quick: int = Net.quick_slot_count - 1
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it != null and it.id == item_id and i != quick:
			Net.move_item(i, quick)
			await _wait(0.4)
			break
	Net.equip(quick)
	await _wait(0.4)


func _run() -> void:
	var camera: FollowCamera = _village.get_node("CameraRig")
	var hud: CanvasLayer = _village.get_node("HUD")
	var econ: EconomyController = _village.get_node("EconomyController")
	var site: CivicSite = _village.get_node("Civic")
	var field: FieldController = _village.get_node("Field")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var base_distance: float = camera.distance
	var base_pitch: float = camera.pitch_degrees

	# ---- 동사무소 ----
	hud.visible = false
	camera.distance = 30.0
	camera.pitch_degrees = 30.0
	await _put(site.desk_front("welfare") + Vector3(0.0, 0.1, 6.0))
	await _wait(0.8)
	await _shot("v03_civic_center")
	camera.distance = 9.0
	camera.pitch_degrees = 20.0
	await _put(site.desk_front("civil") + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
	await _shot("v04_civic_desk")
	hud.visible = true
	camera.distance = base_distance
	camera.pitch_degrees = base_pitch
	Economy.civil_service("move_in")
	await _wait(0.6)
	econ.civic.open("civil")
	await _wait(0.8)
	await _shot("v05_civic_window_civil")
	econ.civic.close()
	await _put(site.desk_front("welfare") + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
	econ.civic.open("welfare")
	await _wait(0.8)
	await _shot("v06_civic_window_welfare")
	econ.civic.close()
	await _put(site.desk_front("finance") + Vector3(0.0, 0.1, 0.0), Vector3.FORWARD)
	econ.civic.open("finance")
	await _wait(0.8)
	await _shot("v07_civic_window_finance")
	econ.civic.close()

	# ---- 갈대 여울 ----
	var zone: Dictionary = Field.zone_at(Vector3(-26.0, 0.0, 2.0))
	await _hold("fishing_net")
	hud.visible = false
	camera.distance = 24.0
	camera.pitch_degrees = 48.0
	await _put(Vector3(float(zone["x"]) + 6.0, 0.1, float(zone["z"]) + 9.0), Vector3(-1.0, 0.0, -1.0))
	await _wait(1.0)
	await _shot("v08_shallows_sky")
	camera.distance = 8.0
	camera.pitch_degrees = 34.0
	await _put(Vector3(float(zone["x"]), 0.1, float(zone["z"]) - 4.0), Vector3.BACK)
	await _wait(1.2)
	await _shot("v09_wading")
	hud.visible = true
	camera.distance = base_distance
	camera.pitch_degrees = base_pitch
	if interaction.target_id == FieldController.TARGET_NET:
		interaction.action_hud.action_pressed.emit()
	await _wait(0.25)
	await _shot("v10_net_swing")
	await _wait(1.2)

	# ---- 바닷가 조개 ----
	var spot: Dictionary = {}
	for d: Dictionary in Field.digspots.values():
		if str(d.get("kind", "")) == "beach":
			spot = d
	if not spot.is_empty():
		await _hold("shovel")
		var at: Vector3 = Vector3(float(spot["x"]), 0.1, float(spot["z"]))
		var inward: Vector3 = -Vector3(at.x, 0.0, at.z).normalized()
		await _put(at + inward * 1.1, -inward)
		await _wait(0.6)
		await _shot("v11_beach_clam_spot")
		if interaction.target_id.begins_with(FieldController.TARGET_CLAM):
			interaction.action_hud.action_pressed.emit()
		await _wait(0.2)
		await _shot("v12_digging")
		await _wait(1.0)

	# ---- 삽으로 구덩이 · 흙길 ----
	await _hold("shovel")
	field.shovel_mode = FieldController.ShovelMode.PATH
	for i: int in 6:
		await _put(Vector3(-46.0 + float(i), 0.1, 22.0), Vector3.FORWARD)
		if interaction.target_id == FieldController.TARGET_PATH:
			interaction.action_hud.action_pressed.emit()
		await _wait(0.5)
	field.shovel_mode = FieldController.ShovelMode.HOLE
	for i: int in 3:
		await _put(Vector3(-45.0 + float(i) * 1.0, 0.1, 19.0), Vector3.FORWARD)
		if interaction.target_id == FieldController.TARGET_DIG:
			interaction.action_hud.action_pressed.emit()
		await _wait(0.5)
	camera.distance = 10.0
	camera.pitch_degrees = 40.0
	await _put(Vector3(-43.0, 0.1, 18.0), Vector3.BACK)
	await _wait(0.8)
	await _shot("v13_shovel_tiles")
