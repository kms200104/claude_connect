extends Node
## 물놀이 체험 종단 테스트 (v21, 앱 안 테스트 서버 · tests/run_aqua_e2e.sh).
##   매표소 곁 상황 버튼 "물놀이" → 표 사는 창 → 바나나 보트 타기 (튜브 자리에 앉음 · 곧 출발 · 내리기 단추)
##   → 출발하면 모터보트가 끄는 튜브를 따라 움직임 → 급회전 "꽉 잡아!" 제때 누르면 버팀, 놓치면 첨벙 빠졌다가 다시 오름
##   → 한 바퀴 끝나면 선착장 땅에 내려섬 → 유람선: 의자에 앉아 선장님 안내 → 출발 전 내리기는 요금 환불.
## 시간을 줄이려고 놀이배를 빠르게 돌린다 (GameData.aqua — 앱 안 테스트 서버도 같은 값을 쓴다).

var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalTestServer.SAVE_PATH))
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[aqua] FAIL: %s" % f)
	print("[aqua] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[aqua] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _press(root: Node, node_name: String) -> bool:
	var b: Button = root.find_child(node_name, true, false) as Button
	if b == null or b.disabled or not b.is_visible_in_tree():
		return false
	b.pressed.emit()
	return true


func _shot(shot_name: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [arg.trim_prefix("--shots="), shot_name])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var marina: AquaMarina = _village.get_node("AquaMarina")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var hud: CanvasLayer = _village.get_node("HUD")
	var rules: AquaRules = GameData.aqua
	Net.play_on_test_server()
	_check(await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 5.0), "앱 안 테스트 서버로 접속")
	_check(player.aqua == marina, "물놀이 선착장이 캐릭터에 붙음")
	Net.request("dev_grant")
	_check(await _wait_until(func() -> bool: return Net.sol > 100000000, 3.0), "테스트 솔 받기")
	rules.board_ms = 2500
	# --real-speed: 화면 확인용 (놀이배를 원래 빠르기로).
	if not "--real-speed" in OS.get_cmdline_user_args():
		for r: AquaRules.Ride in rules.rides:
			r.speed *= 3.5 if r.is_banana() else 5.0
			r.ease_s /= 3.0
	# ---- 매표소 ----
	var stand: Vector2 = rules.land
	player.global_position = Vector3(stand.x, 0.1, stand.y)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.AQUA and interaction.action_hud.current_text() == "물놀이", 2.0), "매표소 곁에서 상황 버튼 '물놀이'")
	await _shot("1_booth")
	interaction.action_hud.action_pressed.emit()
	var window: Control = hud.find_child("AquaWindow", true, false) as Control
	_check(window != null and window.visible, "표 사는 창이 열림")
	await get_tree().create_timer(0.2).timeout
	_check(window.find_child("AquaJoin_banana", true, false) != null and window.find_child("AquaJoin_cruise", true, false) != null, "바나나 보트 · 유람선 표")
	await _shot("2_window")
	# ---- 바나나 보트 ----
	var sol0: int = Net.sol
	_check(_press(window, "AquaJoin_banana"), "바나나 보트 타기")
	_check(await _wait_until(func() -> bool: return marina.is_riding(), 3.0), "튜브에 올라탐")
	_check(Net.sol == sol0 - rules.ride("banana").fee, "요금 %s" % Money.sol(rules.ride("banana").fee))
	_check(not window.visible, "창이 닫힘")
	await get_tree().create_timer(0.8).timeout
	_check(player.rig.riding_kind() == "moto" and player.is_input_locked(), "튜브에 걸터앉은 자세 · 걷지 않음")
	var leave: Button = hud.find_child("AquaLeave", true, false) as Button
	_check(leave != null and leave.is_visible_in_tree(), "출발 전 '내리기' 단추")
	var banana: Node3D = marina.get_node("Aqua_banana")
	_check(_flat(player.global_position, banana.global_position) < 2.5, "튜브 위 (%.1fm)" % _flat(player.global_position, banana.global_position))
	await _shot("3_boarding")
	var start: Vector3 = banana.global_position
	_check(await _wait_until(func() -> bool: return _flat(banana.global_position, start) > 3.0, 5.0), "출발: 튜브가 움직인다")
	_check(_flat(player.global_position, banana.global_position) < 2.5, "나도 같이 간다")
	var tug: Node3D = marina.get_node("Aqua_tug")
	_check(_flat(tug.global_position, banana.global_position) > 6.0, "모터보트가 앞에서 끈다 (%.1fm)" % _flat(tug.global_position, banana.global_position))
	await _shot("4_banana")
	# 급회전 1: 제때 누른다 → 버팀.
	var fx: Array[Dictionary] = []
	Net.aqua_fx.connect(func(_t: String, id: int, turn: int, fell: bool) -> void: fx.append({"id": id, "turn": turn, "fell": fell}))
	var prompt: Button = hud.find_child("AquaHold", true, false) as Button
	_check(await _wait_until(func() -> bool: return prompt.visible, 30.0), "급회전 앞에서 '꽉 잡아!'")
	prompt.button_down.emit()
	_check(await _wait_until(func() -> bool: return fx.size() >= 1, 2.0) and not bool(fx[0]["fell"]), "제때 눌러 버팀")
	# 급회전 2: 안 누른다 → 첨벙.
	_check(await _wait_until(func() -> bool: return prompt.visible, 30.0), "다음 급회전")
	await _shot("5_hold")
	_check(await _wait_until(func() -> bool: return fx.size() >= 2, 3.0) and bool(fx[1]["fell"]), "놓치면 물에 빠짐")
	await get_tree().create_timer(0.4).timeout
	_check(player.global_position.y < WaterRules.LAKE_LEVEL - 0.4 and player.rig.riding_kind() == "", "물에 첨벙 (%.2f)" % player.global_position.y)
	await _shot("6_fall")
	_check(await _wait_until(func() -> bool: return player.rig.riding_kind() == "moto" and _flat(player.global_position, banana.global_position) < 2.5, 5.0), "다시 튜브로 올라옴")
	var ended: Array[Dictionary] = []
	Net.aqua_ended.connect(func(m: Dictionary) -> void: ended.append(m))
	_check(await _wait_until(func() -> bool: return not ended.is_empty(), 60.0), "한 바퀴 끝")
	_check(not ended.is_empty() and int(ended[0].get("held", -1)) >= 1, "버틴 횟수 (%s)" % [ended[0] if not ended.is_empty() else {}])
	_check(await _wait_until(func() -> bool: return not marina.is_riding() and not player.is_input_locked(), 2.0), "내려서 다시 걷는다")
	_check(WaterRules.is_land(Vector2(player.global_position.x, player.global_position.z)) and player.rig.riding_kind() == "", "선착장 땅에 섬")
	_check(await _wait_until(func() -> bool: return _flat(banana.global_position, Vector3(rules.ride("banana").path[0].x, 0.0, rules.ride("banana").path[0].y)) < 0.5, 2.0), "튜브는 선착장 자리로 돌아옴")
	# ---- 출발 전 내리기 (환불) ----
	await get_tree().create_timer(0.3).timeout
	var sol1: int = Net.sol
	marina.join("banana")
	_check(await _wait_until(func() -> bool: return marina.is_riding(), 3.0), "다시 탐")
	await get_tree().create_timer(0.3).timeout
	_check(_press(hud, "AquaLeave"), "'내리기'")
	_check(await _wait_until(func() -> bool: return not marina.is_riding(), 3.0) and Net.sol == sol1, "출발 전 내리면 요금을 돌려받음")
	# ---- 유람선 ----
	await get_tree().create_timer(0.3).timeout
	marina.join("cruise")
	_check(await _wait_until(func() -> bool: return marina.is_riding(), 3.0), "유람선 타기")
	await get_tree().create_timer(0.8).timeout
	var ship: Node3D = marina.get_node("Aqua_cruise")
	_check(player.rig.riding_kind() == "" and _flat(player.global_position, ship.global_position) < 4.0, "갑판 의자에 앉음")
	await _shot("7_cruise_board")
	var caption: Label = hud.find_child("AquaCaption", true, false) as Label
	_check(await _wait_until(func() -> bool: return caption.visible and caption.text.begins_with("선장님"), 6.0), "선장님 안내 방송")
	await get_tree().create_timer(1.5).timeout
	await _shot("8_cruise")
	ended.clear()
	_check(await _wait_until(func() -> bool: return not ended.is_empty(), 100.0), "유람선 한 바퀴")
	_check(await _wait_until(func() -> bool: return not marina.is_riding(), 2.0), "유람선에서 내림")
