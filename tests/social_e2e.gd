extends Node
## 주민·마을톡 종단 테스트 (v0.11): 서 있는 주민이 가까이 온 나를 돌아본다 · 친한 주민이 먼저 걸어와 말을 걸고 대화가 열린다 ·
## 마을톡: 환영 인사 · 친한 주민의 먼저 연락(알림 · 휴대폰 단추 숫자) · 내가 보내면 답장 · 읽으면 숫자가 사라진다.
## tests/run_social_e2e.sh 가 서버를 START_FRIENDSHIP=10 NPC_APPROACH_SCALE=40 MESSENGER_CHECK_MS=400 으로 띄운다.
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
		print("[social] FAIL: %s" % f)
	print("[social] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[social] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _shot(name: String) -> void:
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var npcs: NpcCrowd = _village.get_node("Npcs")
	var dialogue: DialogueController = _village.get_node("DialogueController")
	var economy: EconomyController = _village.get_node("EconomyController")
	var greeted: Array[String] = []
	Net.npc_greeted.connect(func(id: String) -> void: greeted.append(id))
	var texts: Array[String] = []
	Talk.received.connect(func(th: String, m: Dictionary) -> void:
		if str(m.get("f", "")) != "me":
			texts.append(th))

	Net.create_room(_server)
	await Net.welcomed
	_check(Talk.threads.has("sys:town") and Talk.unread("sys:town") == 1, "마을톡 환영 인사 (안 읽음 1)")

	# ---- 서 있는 주민이 가까이 온 나를 돌아본다 ----
	var near: NpcActor = npcs.actor("morak")
	_check(near != null, "주민을 찾음")
	# 주민 등 뒤 3m 에 선다 → 주민이 나를 돌아보거나(멈춰 있을 때) 다가온다.
	player.global_position = near.global_position + Vector3(0.0, 0.1, 3.0)
	_check(await _wait_until(func() -> bool: return near.is_looking_at(player.global_position, 0.6), 6.0), "%s 이(가) 나를 바라봄" % near.info.display_name)

	# ---- 친한 주민이 먼저 다가와 말을 걸고, 가만히 있으면 대화가 열린다 ----
	_check(await _wait_until(func() -> bool: return not greeted.is_empty(), 15.0), "친한 주민이 다가와 말을 걺 (%s)" % [", ".join(greeted)])
	if not greeted.is_empty():
		var who: NpcActor = npcs.actor(greeted[0])
		_check(Vector2(who.global_position.x - player.global_position.x, who.global_position.z - player.global_position.z).length() < 2.6, "내 곁까지 걸어옴")
		await get_tree().create_timer(0.6).timeout
		await _shot("s1_npc_greet")
		_check(await _wait_until(func() -> bool: return dialogue.is_active(), 4.0), "가만히 있으니 대화가 열림")
		await get_tree().create_timer(0.8).timeout
		await _shot("s2_greet_dialogue")
		dialogue.stop()
		await get_tree().create_timer(0.5).timeout

	# ---- 마을톡: 친한 주민의 먼저 연락 ----
	_check(await _wait_until(func() -> bool: return texts.any(func(th: String) -> bool: return th.begins_with("npc:")), 10.0), "친한 주민이 먼저 마을톡 연락 (%s)" % [", ".join(texts)])
	_check(Talk.unread_total() >= 2, "안 읽은 메시지 수 (%d)" % Talk.unread_total())
	var thread: String = ""
	for th: String in texts:
		if th.begins_with("npc:"):
			thread = th
			break
	economy.phone.open(PhoneWindow.Tab.TALK)
	await get_tree().create_timer(0.4).timeout
	await _shot("s3_talk_list")
	economy.phone.open_thread(thread)
	await get_tree().process_frame
	_check(Talk.unread(thread) == 0, "대화방을 열면 읽음")
	var before: int = (Talk.threads[thread]["m"] as Array).size()
	Talk.send(thread, "저도 잘 지내요! 이따 놀러 갈게요")
	_check(await _wait_until(func() -> bool: return (Talk.threads[thread]["m"] as Array).size() >= before + 2, 8.0), "보내면 주민이 답장")
	await get_tree().create_timer(0.5).timeout
	await _shot("s4_talk_room")
	economy.phone.close()
	_finished = true
