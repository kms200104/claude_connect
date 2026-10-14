extends Node
## v0.27 보급 상자 종단 테스트 (서버 1개 + Godot 1개, 밤 23시 · 첫 상자가 곧 떨어진다, 떨어지는 데 4초):
## 헬기가 상자를 떨어뜨리면 안내 · HUD 화살표 "보급 상자 Nm · 떨어지는 중" · 하늘에서 낙하산 상자가 내려온다 →
## 땅에 닿으면 붉은 신호탄 → 곁에 가면 지키던 크리처 · 상황 버튼 "보급 상자 열기" → 연 것을 가방에 받고 상자가 사라진다.
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
		print("[supply] FAIL: %s" % f)
	print("[supply] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[supply] %s: %s" % ["ok  " if ok else "FAIL", what])
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
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(shot_name + ".png"))


func _bag_total() -> int:
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		n += it.count if it != null else 0
	return n


func _teleport(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _run() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var survival: SurvivalController = _village.get_node("Survival")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.4).timeout
	_check(GameData.survival.is_night(Net.game_hour()), "밤 (%.1f시)" % Net.game_hour())
	await _teleport(Vector3(-150.0, 0.1, 140.0))

	# ---- 헬기가 상자를 떨어뜨린다 ----
	_check(await _wait_until(func() -> bool: return not Net.supply.is_empty(), 8.0), "보급 상자가 떨어진다 (%d)" % Net.supply.size())
	if Net.supply.is_empty():
		return
	var sid: String = Net.supply.keys()[0]
	var chip: Control = survival.get("_supply_chip")
	var label: Label = survival.get("_supply_label")
	await get_tree().create_timer(0.2).timeout
	_check(chip.visible and label.text.contains("떨어지는 중"), "HUD '%s'" % label.text)
	var crate: Node3D = survival.supply.find_child("Crate_%s" % sid, true, false) as Node3D
	_check(crate != null, "상자 모형")
	var at: Vector3 = survival.supply.crate_position(sid)
	# 상자 쪽을 보고 선다 (떨어지는 상자가 화면에 들어오게).
	var cam: Camera3D = get_viewport().get_camera_3d()
	var away: Vector3 = cam.global_basis.z if cam != null else Vector3.BACK
	away.y = 0.0
	away = away.normalized() * 7.0
	await _teleport(at + away + Vector3(0.0, 0.1, 0.0), atan2(-away.x, -away.z))
	var box: Node3D = crate.get_node("Box") as Node3D
	_check(await _wait_until(func() -> bool: return box.visible and box.global_position.y > at.y + 3.0, 4.0), "낙하산 상자가 하늘에서 내려온다 (높이 %.1f)" % (box.global_position.y - at.y))
	_check(survival.target_label("supply:" + sid) == "보급 상자 열기", "상황 버튼 글자")
	await _shot("supply_falling")
	_check(await _wait_until(func() -> bool: return Time.get_ticks_msec() >= int(Net.supply[sid]["land"]) + 300, 7.0), "땅에 닿았다")
	_check(absf(box.global_position.y - at.y) < 0.05, "상자가 땅 위에 (%.2f)" % (box.global_position.y - at.y))
	var lights: Array[Node] = crate.find_children("*", "OmniLight3D", true, false)
	var light: OmniLight3D = lights[0] as OmniLight3D if not lights.is_empty() else null
	_check(light != null and light.visible, "붉은 신호탄 불빛")
	_check(await _wait_until(func() -> bool: return not label.text.contains("떨어지는 중"), 1.0), "HUD '%s'" % label.text)
	await get_tree().create_timer(0.8).timeout
	await _shot("supply_landed")

	# ---- 곁에 가면 지키던 크리처 · 열기 ----
	var near: Vector3 = at + away.normalized() * 1.2 + Vector3(0.0, 0.1, 0.0)
	await _teleport(near, atan2(-away.x, -away.z))
	_check(await _wait_until(func() -> bool: return Net.creatures.values().any(func(c: Dictionary) -> bool: return Vector2(float(c.get("x", 0.0)) - at.x, float(c.get("z", 0.0)) - at.z).length() < 10.0), 3.0), "지키던 크리처가 나타났다 (%d)" % Net.creatures.size())
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.SURVIVE and interaction.target_id == "supply:" + sid, 2.0), "상황 버튼 '보급 상자 열기' (%s)" % interaction.target_id)
	var before: int = _bag_total()
	var got: Array = [{}]
	Net.supply_got.connect(func(i: Dictionary) -> void: got[0] = i, CONNECT_ONE_SHOT)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not (got[0] as Dictionary).is_empty(), 3.0), "상자를 열었다 (%s)" % str(got[0].get("items", [])))
	_check(await _wait_until(func() -> bool: return _bag_total() > before, 2.0), "가방에 들어왔다 (%d → %d)" % [before, _bag_total()])
	_check(not Net.supply.has(sid), "상자가 목록에서 빠졌다")
	_check(await _wait_until(func() -> bool: return not chip.visible, 1.0), "HUD 화살표가 사라졌다")
	var ref: WeakRef = weakref(crate)
	crate = null
	box = null
	_check(await _wait_until(func() -> bool: return ref.get_ref() == null, 3.0), "상자 모형이 사라졌다")
	_finished = true
