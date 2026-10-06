extends Node
## 거울 종단 테스트 (클라이언트 1개, 서버 1개 · tests/run_mirror_e2e.sh 가 띄운다).
##   광장 거울 앞 → "거울 보기" → 얼굴 클로즈업 · 거울 창 → 눈·코·입·피부·머리 고르기(미리 보기) → 닫으면 되돌림
##   → 다시 골라 완료 → 서버가 저장, 내 캐릭터·가방 미리보기에 반영 → 거울에서 멀면 거절
##   → 거울 가구를 놓고 그 앞에서도 열림, 가방에 다시 넣기
## 인자: -- --server=ws://…

var _server: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[mirror] FAIL: %s" % f)
	print("[mirror] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[mirror] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _teleport(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.4).timeout


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var window: MirrorWindow = _village.get_node("HUD/MirrorWindow")
	var camera: FollowCamera = _village.get_node("CameraRig")
	var mirrors: MirrorSite = _village.get_node("Mirrors")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.5).timeout

	_check(Net.faces.get(Net.my_id, {}).get("hair", "") == "bob", "처음엔 자리 기본 얼굴 (단발): %s" % str(Net.faces.get(Net.my_id)))
	_check(player.rig.look.eyes == "round" and player.rig.look.hair_style == "bob", "내 캐릭터도 기본 얼굴")
	_check(mirrors.get_child_count() == GameData.layout.mirrors.size() and GameData.layout.mirrors.size() >= 1, "광장에 거울이 있다")

	# 광장 거울 앞
	var spot: Vector3 = mirrors.spot_position(0)
	await _teleport(mirrors.stand_position(0, 1.1) + Vector3(0.0, 0.1, 0.0))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.MIRROR, 2.0), "거울 앞에서 '거울 보기'")
	interaction.action_hud.action_pressed.emit()
	_check(window.is_open() and player.is_input_locked(), "거울 창이 열리고 캐릭터는 멈춘다")
	_check(await _wait_until(func() -> bool: return camera.focus > 0.95, 2.0), "카메라가 얼굴 앞으로 다가간다")
	_check(window.current_tab() == "eyes" and window.option_button("star") != null and window.option_button("eye_color:sky") != null, "눈 탭: 눈 모양 12가지와 눈동자 색")

	# 고르면 바로 내 캐릭터에 비춰 본다
	window.option_button("star").pressed.emit()
	window.option_button("eye_color:sky").pressed.emit()
	_check(player.rig.look.eyes == "star" and player.rig.look.eye_color == GameData.face.part("eye_color", "sky").colors["color"], "별눈 · 하늘색 눈동자 미리 보기")
	for pick: Array in [["nose", "pig"], ["mouth", "cat"], ["skin", "cocoa"], ["hair", "curly"], ["hair_color", "mint"]]:
		window.select_tab_key("hair" if pick[0] == "hair_color" else pick[0])
		await get_tree().process_frame
		var key: String = ("hair_color:%s" % pick[1]) if pick[0] == "hair_color" else pick[1]
		var b: Button = window.option_button(key)
		_check(b != null, "%s 탭에 %s" % [pick[0], pick[1]])
		if b != null:
			b.pressed.emit()
	var look: CharacterLook = player.rig.look
	_check(look.nose == "pig" and look.mouth == "cat" and look.hair_style == "curly" and look.skin == GameData.face.part("skin", "cocoa").colors["skin"], "코·입·피부·머리 미리 보기")
	# 닫으면 되돌린다
	window.close()
	await get_tree().process_frame
	_check(not window.is_open() and player.rig.look.eyes == "round" and player.rig.look.hair_style == "bob", "완료 없이 닫으면 처음 얼굴로")
	_check(await _wait_until(func() -> bool: return camera.focus < 0.05 and not player.is_input_locked(), 2.0), "카메라·조작이 돌아온다")

	# 다시 열어 골라서 완료
	await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.MIRROR, 2.0)
	interaction.action_hud.action_pressed.emit()
	window.pick("eyes", "sparkle")
	window.pick("mouth", "open")
	window.pick("hair", "pigtails")
	window.pick("hair_color", "pink")
	window.save()
	_check(await _wait_until(func() -> bool: return Net.faces.get(Net.my_id, {}).get("hair", "") == "pigtails", 3.0), "완료하면 서버가 저장: %s" % str(Net.faces.get(Net.my_id)))
	_check(await _wait_until(func() -> bool: return not window.is_open(), 2.0), "저장되면 창이 닫힌다")
	_check(player.rig.look.eyes == "sparkle" and player.rig.look.hair_style == "pigtails" and player.rig.look.mouth == "open", "내 캐릭터에 새 얼굴")
	var bag: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	bag.open()
	await get_tree().create_timer(0.3).timeout
	var preview: CharacterPreview = bag.get_node("%CharacterPreview")
	_check(preview.rig.look.hair_style == "pigtails", "가방 창 미리보기도 새 얼굴")
	bag.close()

	# 거울에서 멀면 서버가 거절
	await _teleport(Vector3(-44.0, 0.1, 64.0))
	var failed: Array[String] = []
	Net.request_failed.connect(func(kind: String, code: String) -> void: failed.append("%s:%s" % [kind, code]))
	Net.set_face({"eyes": "dot"})
	_check(await _wait_until(func() -> bool: return failed.has("set_face:not_near_mirror"), 2.0), "거울에서 멀면 거절: %s" % str(failed))

	# 거울 가구
	var slot: int = -1
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == "standing_mirror":
			slot = i
	_check(slot >= 0, "가방에 전신 거울")
	Net.place_furniture(slot, Vector3(-43.0, 0.0, 65.0), 0)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.MIRROR and not interaction.target_id.is_empty(), 3.0), "놓은 거울 가구 앞에서도 '거울 보기'")
	interaction.action_hud.action_pressed.emit()
	_check(window.is_open() and window.get_node_or_null(".") != null, "거울 가구로 거울 창")
	window.pick("nose", "long")
	window.save()
	_check(await _wait_until(func() -> bool: return Net.faces.get(Net.my_id, {}).get("nose", "") == "long", 3.0), "거울 가구 앞에서 바꾼 얼굴도 저장")
	await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.MIRROR, 2.0)
	var mirror_id: String = interaction.target_id
	interaction.action_hud.action_pressed.emit()
	window._on_pickup()
	_check(await _wait_until(func() -> bool: return not Net.placed.has(mirror_id), 3.0), "내 거울은 '가방에 넣기'로 다시 줍는다")
