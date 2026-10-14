extends Node
## v0.24 쓰러짐 · 일으키기 종단 테스트 (서버 1개 + 헤드리스 Godot 2개 · tests/run_revive_e2e.sh 가 띄운다, 밤 23시 · 체력 2로 시작).
##   a: 둔치에서 크리처에게 맞아 쓰러진다 → 누운 몸 · 화면 안내 · 움직이지 못함 → b 가 일으키면 체력 4로 일어난다 (솔을 잃지 않음).
##   b: 대피소(안전)에서 구급상자로 체력을 채우고 기다리다 a 가 쓰러지면 곁으로 → 머리 위 "도와줘요!" · 누운 a → 상황 버튼 "일으키기" → a 가 일어난다.
## 두 프로세스는 --dir 의 작은 파일로 순서를 맞춘다. 인자: -- --role=a|b --server=ws://… --dir=/tmp/…

var _role: String = ""
var _server: String = ""
var _dir: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[%s] FAIL: %s" % [_role, f])
	print("[%s] %s" % [_role, "PASS" if _failures.is_empty() else "FAILED"])
	_write("%s.done" % _role, "1")
	await _wait_file("%s.done" % ("b" if _role == "a" else "a"), 60.0)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [_role, "ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _write(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open("%s/%s" % [_dir, file], FileAccess.WRITE)
	f.store_string(text)


func _read(file: String) -> String:
	var path: String = "%s/%s" % [_dir, file]
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _wait_file(file: String, timeout_s: float) -> String:
	var waited: float = 0.0
	while _read(file).is_empty() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return _read(file)


func _teleport(at: Vector3) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _run() -> void:
	if _role == "a":
		Net.create_room(_server)
		await Net.welcomed
		_write("code", Net.room_code)
		await _wait_until(func() -> bool: return Net.partner_present, 15.0)
	else:
		var code: String = await _wait_file("code", 15.0)
		Net.join_room(_server, code)
		await Net.welcomed
	_check(Net.partner_present, "둘이 같은 방")
	await get_tree().create_timer(0.5).timeout
	if _role == "a":
		await _downed_side()
	else:
		await _helper_side()


func _downed_side() -> void:
	var player: Player = _village.get_node("Player")
	var survival: SurvivalController = _village.get_node("Survival")
	var spot: Vector3 = Vector3(-150.0, 0.1, 140.0)
	await _teleport(spot)
	var sol_before: int = Net.sol
	_check(await _wait_until(func() -> bool: return Net.is_downed(Net.my_id), 60.0), "크리처에게 맞아 쓰러졌다 (기절이 아니라)")
	_write("downed", "%f,%f" % [player.global_position.x, player.global_position.z])
	await get_tree().create_timer(0.8).timeout
	var panel: Control = survival.get("_down_panel")
	_check(panel != null and panel.visible, "화면 안내 '%s'" % (survival.get("_down_label") as Label).text.replace("\n", " "))
	_check(player.is_input_locked(), "쓰러진 동안은 움직이지 못한다")
	_check(player.body.rotation.z > 1.2, "누운 몸 (%.2f)" % player.body.rotation.z)
	_check(survival.pick_target(player.global_position).is_empty(), "쓰러진 동안은 상황 버튼이 없다")
	_check(await _wait_until(func() -> bool: return not Net.is_downed(Net.my_id), 40.0), "동료가 일으켜 일어났다")
	_check(Net.hp == 4, "일어난 체력 4 (%d)" % Net.hp)
	_check(Net.sol == sol_before, "솔을 잃지 않았다")
	await get_tree().create_timer(1.0).timeout
	_check(absf(player.body.rotation.z) < 0.05 and not player.is_input_locked() and not panel.visible, "다시 선다 · 움직일 수 있다")
	_write("up", "1")


func _helper_side() -> void:
	var player: Player = _village.get_node("Player")
	var survival: SurvivalController = _village.get_node("Survival")
	var interaction: InteractionController = _village.get_node("InteractionController")
	# 대피소 (크리처가 오지 않는다). 둘 다 체력 2로 시작하니 구급상자로 채우고 간다.
	await _teleport(Vector3(-58.0, 0.1, 68.0))
	for i: int in Net.inventory.size():
		if Net.inventory[i] != null and Net.inventory[i].id == "first_aid_kit":
			Net.use_item(i)
			break
	_check(await _wait_until(func() -> bool: return Net.hp == Net.max_hp, 3.0), "구급상자로 체력을 채웠다 (%d)" % Net.hp)
	var at: String = await _wait_file("downed", 70.0)
	_check(not at.is_empty(), "a 가 쓰러졌다는 소식")
	var found: Array[int] = [0]
	_check(await _wait_until(func() -> bool:
		for id: int in Net.downed:
			if id != Net.my_id:
				found[0] = id
		return found[0] != 0, 3.0), "Net.downed 에 a")
	var other: int = found[0]
	var xy: PackedStringArray = at.split(",")
	await _teleport(Vector3(float(xy[0]) + 1.0, 0.1, float(xy[1])))
	var tag: Label3D = (survival.get("_help_tags") as Dictionary).get(other)
	_check(tag != null and tag.text.begins_with("도와줘요"), "쓰러진 동료 머리 위 '%s'" % (tag.text if tag != null else "-"))
	var remote: RemotePlayer = survival._remote_node(other)
	_check(await _wait_until(func() -> bool: return remote != null and remote.body.rotation.z > 1.2, 3.0), "동료가 누워 있다")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.SURVIVE and interaction.target_id == "revive:%d" % other, 3.0), "상황 버튼 '%s'" % survival.target_label("revive:%d" % other))
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return int(Net.downed.get(other, {}).get("by", 0)) == Net.my_id, 2.0), "일으키는 중")
	_check(await _wait_until(func() -> bool: return not Net.is_downed(other), 8.0), "a 가 일어났다")
	_check(not (await _wait_file("up", 10.0)).is_empty(), "a 쪽도 확인")
	_check(await _wait_until(func() -> bool: return remote.body.rotation.z < 0.05, 2.0), "동료가 다시 섰다")
	await _teleport(Vector3(-58.0, 0.1, 68.0))
