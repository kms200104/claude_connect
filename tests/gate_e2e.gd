extends Node
## v0.28 게이트 종단 테스트 (서버 1개 + Godot 1개, 한낮 · 서쪽 둔치에 E급 게이트가 곧 열린다 · 크리처가 제자리에 선다):
## 게이트가 열리면 재난문자(헌터 협회) · 둔치에 빛나는 고리(GateField) · HUD 화살표 "E급 게이트 Nm · 브레이크까지" →
## 곁에서 "게이트 진입 · E급" → 공략 구역 고리 · 웨이브 크리처(한낮에도) → 다 쓰러뜨리면 우두머리(크고 금빛 이름표) →
## 우두머리를 쓰러뜨리면 공략 보상(가방 · 솔 · 헌터 점수 · 게이트 수) · 게이트가 사라진다.
## v0.28.2 던전: 진입하면 게이트 안 공간(GATE_MAP 지하철역 · 동굴)으로 옮겨 가 지도 · 어두운 지하 · HUD 던전 이름,
## "나가는 균열" 곁에서 "던전 나가기" → 게이트 앞 (공략이 풀린다) → 다시 진입해 공략 → 잠시 뒤 게이트 앞으로.
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
		print("[gate] FAIL: %s" % f)
	print("[gate] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[gate] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _teleport(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


func _run() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var hunter: HunterController = _village.get_node("Hunter")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.6).timeout
	_check(not GameData.survival.is_night(Net.game_hour()), "한낮 (%.1f시)" % Net.game_hour())
	for i: int in Net.inventory.size():
		if i < 5 and Net.inventory[i] != null and Net.inventory[i].id == "pipe_spear":
			Net.equip(i)
	var spot: Vector3 = Vector3(-100.0, 0.1, 100.0)
	await _teleport(spot + Vector3(0.0, 0.0, 24.0), PI)

	# ---- 게이트가 열린다 ----
	_check(await _wait_until(func() -> bool: return not Net.gates.is_empty(), 6.0), "게이트가 열렸다")
	if Net.gates.is_empty():
		return
	var gid: String = Net.gates.keys()[0]
	_check(str(Net.gates[gid]["rank"]) == "E" and str(Net.gates[gid]["st"]) == "open", "E급 · 열림")
	_check(await _wait_until(func() -> bool: return AlertLog.list().any(func(a: Dictionary) -> bool: return str(a.get("id", "")) == "gate_" + gid), 2.0), "재난문자 (헌터 협회)")
	var portal: Node3D = hunter.gates.find_child("Gate_%s" % gid, true, false) as Node3D
	_check(portal != null, "게이트 고리 모형")
	var glabel: Label3D = portal.find_child("GateLabel", true, false) as Label3D if portal != null else null
	await get_tree().create_timer(0.3).timeout
	_check(glabel != null and glabel.text.begins_with("E급 게이트"), "머리 위 글자 '%s'" % (glabel.text.replace("\n", " / ") if glabel != null else ""))
	var chip: Control = hunter.get("_gate_chip")
	var chip_label: Label = hunter.get("_gate_label")
	_check(chip.visible and chip_label.text.contains("브레이크까지"), "HUD '%s'" % chip_label.text)
	if not _shots.is_empty():
		var alert_box: Node = _village.find_child("DisasterAlert*", true, false)
		if alert_box != null:
			alert_box.queue_free()
		await _teleport(spot + Vector3(0.0, 0.0, 9.0), PI)
	await _shot("gate_open")

	# ---- 진입 ----
	await _teleport(spot + Vector3(0.0, 0.0, 2.5), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.HUNTER and interaction.target_id == "gate:" + gid, 2.0), "상황 버튼 '%s' (%s)" % [hunter.target_label("gate:" + gid), interaction.target_id])
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.gates.has(gid) and str(Net.gates[gid]["st"]) == "raid", 3.0), "공략이 시작됐다")
	var arena: Node3D = portal.get_node("Arena") as Node3D
	_check(arena.visible, "공략 구역 고리")
	_check(await _wait_until(func() -> bool: return Net.creatures.values().any(func(c: Dictionary) -> bool: return c.has("g")), 3.0), "한낮에 게이트 크리처 (%d)" % Net.creatures.size())
	_check(await _wait_until(func() -> bool: return chip_label.text.contains("웨이브 1/"), 2.0), "HUD '%s'" % chip_label.text)

	# ---- v0.28.2 던전 안 ----
	var dungeon: DungeonField = hunter.dungeon
	var player: Player = _village.get_node("Player")
	_check(await _wait_until(func() -> bool: return dungeon.inside(), 3.0), "던전 안으로 옮겨 왔다 (%s)" % str(player.global_position))
	var dmap: HunterRules.DungeonMap = dungeon.map()
	_check(dmap != null and dungeon.built_map == str(Net.gates[gid].get("map", "")), "지도 '%s'" % (dmap.name if dmap != null else ""))
	_check(dungeon.find_child("Solid", true, false) != null and dungeon.find_child("Exit", true, false) != null, "바닥 · 벽 · 나가는 균열")
	var sky: SkyController = _village.get_node("SkyController")
	_check(sky.underground, "지하처럼 어둡다")
	_check(await _wait_until(func() -> bool: return chip_label.text.begins_with(dmap.name if dmap != null else "?"), 1.0), "HUD '%s'" % chip_label.text)
	await get_tree().create_timer(0.6).timeout
	_check(player.global_position.y > -0.5, "바닥에 서 있다 (y %.2f)" % player.global_position.y)
	await _shot("dungeon_" + dungeon.built_map)
	var exit: Vector3 = dungeon.exit_position()
	await _teleport(exit + Vector3(0.0, 0.1, -0.6), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.HUNTER and interaction.target_id == "gate_out:" + gid, 2.0), "상황 버튼 '%s' (%s)" % [hunter.target_label("gate_out:" + gid), interaction.target_id])
	await _shot("dungeon_exit")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return not dungeon.inside() and Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length() < 5.0, 3.0), "게이트 앞으로 나왔다")
	_check(await _wait_until(func() -> bool: return str(Net.gates[gid]["st"]) == "open" and not sky.underground, 2.0), "혼자 나오면 공략이 풀린다 · 하늘이 돌아온다")
	# 다시 진입.
	await _teleport(spot + Vector3(0.0, 0.0, 2.5), PI)
	_check(await _wait_until(func() -> bool: return interaction.target_id == "gate:" + gid, 2.0), "다시 '게이트 진입'")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return dungeon.inside() and str(Net.gates[gid]["st"]) == "raid", 3.0), "다시 던전 안")
	await get_tree().create_timer(1.6).timeout
	await _shot("gate_raid")

	# ---- 웨이브 → 우두머리 ----
	var cleared: Array = [{}]
	Net.gate_cleared.connect(func(i: Dictionary) -> void: cleared[0] = i, CONNECT_ONE_SHOT)
	var boss_seen: Array = [false]
	var boss_shot: Array = [false]
	var sol0: int = Net.sol
	for i: int in 400:
		if not (cleared[0] as Dictionary).is_empty():
			break
		var target: String = ""
		for id: String in Net.creatures:
			if Net.creatures[id].has("g"):
				target = id
				if Net.creatures[id].has("b"):
					boss_seen[0] = true
				break
		if target.is_empty():
			await get_tree().create_timer(0.2).timeout
			continue
		if boss_seen[0] and not boss_shot[0]:
			boss_shot[0] = true
			var bc: Dictionary = Net.creatures[target]
			await _teleport(Vector3(float(bc.get("x", 0.0)), 0.1, float(bc.get("z", 0.0)) + 5.0), PI)
			await _shot("gate_boss")
		var c: Dictionary = Net.creatures[target]
		var at: Vector3 = Vector3(float(c.get("x", 0.0)), 0.1, float(c.get("z", 0.0)))
		if Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() > 1.4:
			await _teleport(at + Vector3(1.0, 0.0, 0.0), PI * 0.5)
		if interaction.target == InteractionController.Target.SURVIVE and interaction.target_id.begins_with("attack:"):
			interaction.action_hud.action_pressed.emit()
		await get_tree().create_timer(0.35).timeout
	_check(boss_seen[0], "우두머리가 나왔다")
	_check(not (cleared[0] as Dictionary).is_empty(), "게이트 공략 (%s)" % str(cleared[0].get("items", [])))
	_check(await _wait_until(func() -> bool: return not Net.gates.has(gid), 2.0), "게이트가 닫혔다")
	_check(await _wait_until(func() -> bool: return Net.sol >= sol0 + int(cleared[0].get("sol", 0)), 2.0), "보상 솔 (%d → %d)" % [sol0, Net.sol])
	_check(await _wait_until(func() -> bool: return int(Net.hunter.get("gates", 0)) == 1, 2.0), "헌터 기록: 게이트 1")
	_check(dungeon.inside() and chip.visible and chip_label.text.contains("공략 완료"), "공략 뒤 잠시 던전에 남는다 (HUD '%s')" % chip_label.text)
	_check(await _wait_until(func() -> bool: return not dungeon.inside() and Vector2(player.global_position.x - spot.x, player.global_position.z - spot.z).length() < 5.0, 6.0), "잠시 뒤 게이트 앞으로 돌아왔다")
	_check(await _wait_until(func() -> bool: return not chip.visible, 1.0), "HUD 게이트 안내가 사라졌다")
	_finished = true
