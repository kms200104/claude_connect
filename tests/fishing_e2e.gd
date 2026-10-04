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
	var panel: InventoryPanel = _village.get_node("HUD/InventoryPanel")
	var pond: FishingSpot = _village.get_node("Terrain/Pond")

	_check(pond.info != null and pond.global_position.is_equal_approx(Vector3(-14, 0, 2)), "낚시터가 spots.json 위치에 놓임")
	Net.fish_result.connect(func(ok: bool, fish_id: String, reason: String) -> void: print("[fishing] result ok=%s fish=%s reason=%s" % [ok, fish_id, reason]))
	Net.fish_bite.connect(func(window_ms: int) -> void: print("[fishing] bite window=%d" % window_ms))
	Net.create_room(_server)
	await Net.welcomed
	var code: String = Net.room_code
	_check(Net.inventory.is_empty(), "새 방의 인벤토리는 비어 있음")

	# 물에서 멀면 던질 수 없다
	await get_tree().create_timer(0.2).timeout
	_check(not pond.can_cast_from(player.global_position), "스폰 지점은 낚시터와 멀다")
	_check(controller.phase == FishingController.Phase.IDLE, "처음엔 IDLE")

	# 물가로 이동 (서버 이동 검사를 통과하도록 서버를 MOVE_SLACK_M 크게 띄워 둠)
	player.global_position = Vector3(-9.0, 0.1, 2.0)
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

	# 진짜 입질을 기다렸다가 사람처럼 150ms 뒤에 챔질
	_check(await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.BITE, 8.0), "진짜 입질이 옴")
	await get_tree().create_timer(0.15).timeout
	hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.RESULT, 3.0), "결과가 확정됨")
	_check(Net.inventory.size() == 1 and Net.inventory[0].count == 1, "인벤토리에 물고기 1마리: %s" % (GameData.fish_name(Net.inventory[0].id) if not Net.inventory.is_empty() else "없음"))
	_check(panel._bag_button.text == "가방 1/20", "가방 버튼 표시 갱신 (%s)" % panel._bag_button.text)
	await get_tree().create_timer(2.0).timeout
	_check(controller.phase == FishingController.Phase.IDLE and not player.is_input_locked(), "잠시 뒤 IDLE로 돌아오고 다시 움직일 수 있음")
	_check(player.rig._fishing_target == 0.0, "낚시 자세 해제")

	# 놓아주기는 서버가 확정한다
	var species: String = Net.inventory[0].id
	Net.discard_item(species, 1)
	_check(await _wait_until(func() -> bool: return Net.inventory.is_empty(), 2.0), "놓아주기 → 인벤토리 비워짐")

	# 한 마리 더 잡고, 서버를 재시작해도 남는지 본다
	hud.action_pressed.emit()
	await _wait_until(func() -> bool: return controller.phase == FishingController.Phase.BITE, 8.0)
	await get_tree().create_timer(0.15).timeout
	hud.action_pressed.emit()
	await _wait_until(func() -> bool: return Net.inventory.size() == 1, 3.0)
	var kept: String = Net.inventory[0].id
	var my_id: int = Net.my_id
	var pos_before: Vector3 = player.global_position
	_write("caught", "%s %s" % [code, kept])
	var restarted: bool = await _wait_until(func() -> bool: return FileAccess.file_exists("%s/restarted" % _dir), 20.0)
	_check(restarted, "서버 재시작 신호")
	# 클라이언트는 자동으로 재접속 → 세션이 사라졌으니 방 코드+uid 로 다시 들어간다
	var back: bool = await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE and Net.room_code == code, 20.0)
	_check(back, "서버 재시작 뒤 자동 재입장")
	_check(Net.my_id == my_id, "같은 자리(id=%d)로 복귀" % Net.my_id)
	_check(Net.inventory.size() == 1 and Net.inventory[0].id == kept, "재시작 뒤에도 인벤토리 유지 (%s)" % kept)
	await get_tree().create_timer(0.3).timeout
	_check(player.global_position.distance_to(pos_before) < 0.5, "저장된 위치로 복귀 (%.2fm 차이)" % player.global_position.distance_to(pos_before))
	_check(controller.phase == FishingController.Phase.IDLE, "낚시 상태는 초기화됨")
