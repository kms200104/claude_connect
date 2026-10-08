extends Node
## 낚시 종단 테스트(클라이언트 1개). tests/run_fishing_e2e.sh 가 서버를 띄우고 재시작한다.
## 인자: -- --server=ws://127.0.0.1:PORT --dir=/tmp/xxx --profile=1

var _server: String = ""
var _dir: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[fishing] FAIL: %s" % f)
	print("[fishing] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[fishing] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _write(file: String, text: String) -> void:
	FileAccess.open("%s/%s" % [_dir, file], FileAccess.WRITE).store_string(text)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var controller: FishingController = _village.get_node("FishingController")
	var hud: FishingHud = _village.get_node("HUD/FishingHud")
	var hotbar: Hotbar = _village.get_node("HUD/Hotbar")
	var pond: FishingSpot = _village.get_node("Terrain/Lake")

	_check(pond.info != null and pond.global_position.is_equal_approx(Vector3(-51.8, 0, 35.68)), "서쪽 연못이 spots.json 위치에 놓임")
	Net.fish_result.connect(func(ok: bool, fish_id: String, reason: String) -> void: print("[fishing] result ok=%s fish=%s reason=%s" % [ok, fish_id, reason]))
	Net.fish_bite.connect(func(window_ms: int) -> void: print("[fishing] bite window=%d" % window_ms))
	Net.create_room(_server)
	await Net.welcomed
	var code: String = Net.room_code
	_check(_count_fish() == 0, "새 방의 가방에는 물고기가 없음")
	_check(Net.held_item_id() == "rod" and player.held_item == "rod", "낚싯대를 손에 들고 시작")

	# 물에서 멀면 던질 수 없다
	await get_tree().create_timer(0.2).timeout
	_check(not pond.can_cast_from(player.global_position), "스폰 지점은 낚시터와 멀다")
	_check(controller.phase == FishingController.Phase.IDLE, "처음엔 IDLE")

	# 물가로 이동 (서버 이동 검사를 통과하도록 서버를 MOVE_SLACK_M 크게 띄워 둠)
	player.global_position = Vector3(-42.6, 0.1, 35.4)
	await get_tree().create_timer(0.6).timeout
	_check(await _wait_until(func() -> bool: return pond.can_cast_from(player.global_position), 1.0), "물가에서는 던질 수 있음")

	# 던지기 → 대기
	hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.WAITING or controller.phase == FishingController.Phase.BITE, 2.0), "서버가 낚시를 시작시킴")
	_check(player.is_input_locked(), "낚시 중에는 이동 입력이 잠김")
	_check(player.rig._fishing_target == 1.0, "낚시 자세로 전환 요청")
	# 첫 입질은 서버 시간 배율상 0.5초 이후라서, 그 전에 낚시 자세가 완전히 들어가야 한다.
	_check(await _wait_until(func() -> bool: return player.rig._fishing_value > 0.9, 1.5), "AnimationTree 낚시 가중치가 올라감 (%.2f)" % player.rig._fishing_value)
	_check(controller.phase == FishingController.Phase.WAITING, "아직 입질 전")
	var shadow: FishShadow = controller.get_node("FishShadow")
	_check(await _wait_until(func() -> bool: return shadow.visible and shadow.mode != FishShadow.Mode.HIDDEN, 10.0), "찌 주변에 물고기 그림자가 나타남 (크기 %.2f)" % shadow.scale.x)

	# v13: 물 밑의 물고기 그림자들 · 겨눠 던지기 · 찌를 같이 비추는 카메라
	var school: FishSchool = _village.get_node("FishSchool")
	var cam_rig: FollowCamera = _village.get_node("CameraRig")
	_check(school.count("lake") >= 3, "호수 물 밑에 물고기 그림자들이 보임 (%d마리)" % school.count("lake"))
	_check(shadow.is_line() and not school.hidden_id.is_empty(), "알아챈 물고기가 찌 쪽으로 곧장 다가옴 (보이던 그 물고기: %s)" % school.hidden_id)
	_check(await _wait_until(func() -> bool: return cam_rig.point_weight > 0.5, 2.0), "카메라가 찌를 같이 비춤 (%.2f)" % cam_rig.point_weight)

	# 진짜 입질을 기다렸다가 사람처럼 150ms 뒤에 챔질
	_check(await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.BITE, 15.0), "진짜 입질이 옴")
	await _hook_and_reel(hud, controller)
	_check(await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.RESULT, 3.0), "결과가 확정됨")
	var first_bag: InventoryItem = Net.inventory[Net.quick_slot_count]
	_check(_count_fish() == 1 and first_bag != null and first_bag.count == 1, "가방 첫 칸에 물고기 1마리: %s" % (GameData.fish_name(first_bag.id) if first_bag != null else "없음"))
	_check(hotbar.slot_button(0).held and hotbar.slot_button(0).get_item().id == "rod", "퀵슬롯 1번(낚싯대)이 손에 든 칸으로 표시")
	# 자랑: 물고기를 머리 위로 들고, 카메라가 다가가고, 희귀도 외침과 물고기 한마디 카드가 뜬다.
	var card: CatchCard = _village.get_node("HUD/CatchCard")
	var camera: FollowCamera = _village.get_node("CameraRig")
	_check(player.rig.is_showing_off() and not player.rig.rod.visible, "잡은 물고기를 머리 위로 들고 자랑 (낚싯대는 숨김)")
	_check(not card.shout_text().is_empty() and not card.line_text().is_empty(), "자랑 카드: %s / %s" % [card.shout_text(), card.line_text()])
	var caught: FishInfo = GameData.fish.get(first_bag.id) if first_bag != null else null
	_check(caught != null and card.line_text() == caught.catch_line, "물고기마다 다른 한마디")
	await get_tree().create_timer(0.8).timeout
	_check(camera.focus > 0.8, "카메라가 클로즈업 (%.2f)" % camera.focus)
	_check(await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.IDLE, 6.0) and not player.is_input_locked(), "자랑이 끝나면 IDLE로 돌아오고 다시 움직일 수 있음")
	_check(not player.rig.is_showing_off() and player.rig.rod.visible and not card.is_showing(), "물고기를 내리고 낚싯대를 다시 듦")
	await get_tree().create_timer(0.7).timeout
	_check(camera.focus < 0.1, "카메라가 제자리로")
	_check(player.rig._fishing_target == 0.0, "낚시 자세 해제")

	# 놓아주기는 서버가 확정한다
	Net.discard_item(Net.quick_slot_count, 1)
	_check(await _wait_until(func() -> bool: return _count_fish() == 0, 2.0), "놓아주기 → 가방에서 빠짐")

	# 한 마리 더 잡고, 서버를 재시작해도 남는지 본다
	# 자랑하며 카메라 쪽(뒤)을 봤으니 다시 연못을 보고 던진다 (겨눌 물고기가 없으면 앞쪽 물가에 떨어져 bad_cast).
	player.look_toward(pond.global_position - player.global_position)
	await get_tree().process_frame
	hud.action_pressed.emit()
	await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.BITE, 15.0)
	await _hook_and_reel(hud, controller)
	await _wait_until(func() -> bool: return _count_fish() == 1, 3.0)
	await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.IDLE, 6.0)
	var kept: String = Net.inventory[Net.quick_slot_count].id
	var my_id: int = Net.my_id
	var pos_before: Vector3 = player.global_position
	_write("caught", "%s %s" % [code, kept])
	var restarted: bool = await _wait_until(func() -> bool: return FileAccess.file_exists("%s/restarted" % _dir), 20.0)
	_check(restarted, "서버 재시작 신호")
	# 클라이언트는 자동으로 재접속 → 세션이 사라졌으니 방 코드+uid 로 다시 들어간다
	var back: bool = await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE and Net.room_code == code, 20.0)
	_check(back, "서버 재시작 뒤 자동 재입장")
	_check(Net.my_id == my_id, "같은 자리(id=%d)로 복귀" % Net.my_id)
	_check(_count_fish() == 1 and Net.inventory[Net.quick_slot_count].id == kept, "재시작 뒤에도 인벤토리 유지 (%s)" % kept)
	await get_tree().create_timer(0.3).timeout
	_check(player.global_position.distance_to(pos_before) < 0.5, "저장된 위치로 복귀 (%.2fm 차이)" % player.global_position.distance_to(pos_before))
	_check(controller.phase == FishingController.Phase.IDLE, "낚시 상태는 초기화됨")


func _count_fish() -> int:
	var n: int = 0
	for item: InventoryItem in Net.inventory:
		if item != null and GameData.fish.has(item.id):
			n += item.count
	return n


## 사람처럼: 찌가 잠기는 걸 보고 150ms 뒤 챔질 → 끌어올리기 연타(80ms 간격)로 끝까지.
func _hook_and_reel(h: FishingHud, c: FishingController) -> void:
	await _wait_until(func() -> bool: return c.is_bite_visible(), 3.0)
	await get_tree().create_timer(0.15).timeout
	h.action_pressed.emit()
	if not await _wait_until(func() -> bool: return c.phase == FishingController.Phase.REEL, 3.0):
		return
	var pressed: int = 0
	while c.phase == FishingController.Phase.REEL and pressed < 40:
		h.action_pressed.emit()
		pressed += 1
		await get_tree().create_timer(0.08).timeout
