extends Node
## v0.28.2 가디언 종단 테스트 (서버 1개 + Godot 1개, 밤 23시 · 크리처가 빨리 나온다):
## 시내 둘레 초소 6곳에 가디언 (헬멧 · 조끼 · 소총, 모래주머니 초소) → 초소 곁에 서 있으면 다가오는 크리처를 가디언이 쏜다
## (총구 번쩍 · 탄 자국) · 배리어 돔이 광장 둘레에 있다.
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
		print("[guard] FAIL: %s" % f)
	print("[guard] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[guard] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _run() -> void:
	var survival: SurvivalController = _village.get_node("Survival")
	var player: Player = _village.get_node("Player")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.6).timeout
	_check(Net.guards.size() == GameData.survival.barriers.size() + 1 or Net.guards.size() >= 6, "가디언 %d명 (welcome)" % Net.guards.size())
	_check(await _wait_until(func() -> bool: return survival.guards.guard_count() == Net.guards.size(), 2.0), "초소마다 가디언 모형")
	_check(survival.barriers.count() == GameData.survival.barriers.size(), "배리어 %d곳" % survival.barriers.count())
	var post: Dictionary = Net.guards["gd1"]
	player.global_position = Vector3(float(post["x"]) + 0.5, 0.1, float(post["z"]) + 5.0)
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	var shots: Array = [0]
	Net.guard_shot.connect(func(_i: Dictionary) -> void:
		shots[0] += 1)
	var shot_taken: Array = [false]
	for i: int in 900:
		if shots[0] > 0:
			if not shot_taken[0]:
				shot_taken[0] = true
				await get_tree().process_frame
				await _shot("guard_fire")
			break
		await get_tree().create_timer(0.05).timeout
	_check(shots[0] > 0, "다가오는 크리처를 가디언이 쐈다 (%d발)" % shots[0])
	_finished = true
