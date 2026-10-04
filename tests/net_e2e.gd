extends Node
## 종단 테스트: 서버 1개 + 헤드리스 Godot 2개(host, guest). tests/run_net_e2e.sh 로 실행한다 (net_e2e.tscn 이 메인 씬).
## 인자: -- --role=host|guest --server=ws://127.0.0.1:PORT --dir=/tmp/xxx

var _role: String = ""
var _server: String = ""
var _dir: String = ""
var _failures: Array[String] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	var village: Node = load("res://game/village/village.tscn").instantiate()
	add_child(village)
	await get_tree().create_timer(0.3).timeout
	if _role == "host":
		await _run_host(village)
	else:
		await _run_guest(village)
	for f: String in _failures:
		print("[%s] FAIL: %s" % [_role, f])
	if _failures.is_empty():
		print("[%s] PASS" % _role)
	_write("%s.result" % _role, "FAIL" if not _failures.is_empty() else "PASS")
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [_role, "ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _write(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open("%s/%s" % [_dir, file], FileAccess.WRITE)
	f.store_string(text)


func _read(file: String) -> String:
	var path: String = "%s/%s" % [_dir, file]
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _wait_file(file: String, timeout_s: float) -> String:
	var waited: float = 0.0
	while _read(file).is_empty() and waited < timeout_s:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return _read(file)


func _run_host(village: Node) -> void:
	var player: Player = village.get_node("Player")
	var status_events: Array[String] = []
	Net.peer_status_changed.connect(func(id: int, online: bool) -> void: status_events.append("%d:%s" % [id, online]))
	Net.create_room(_server)
	await Net.welcomed
	_check(Net.my_id == 1 and Net.room_code.length() == 6, "방 생성, id=1, 코드 6자리 (%s)" % Net.room_code)
	_write("code", Net.room_code)
	await Net.peer_joined
	_check(Net.partner_present, "게스트 입장 알림")
	await get_tree().create_timer(1.0).timeout
	var start_x: float = player.global_position.x
	Input.action_press("ui_right")
	await get_tree().create_timer(2.0).timeout
	Input.action_release("ui_right")
	_check(player.global_position.x - start_x > 3.0, "호스트가 오른쪽으로 이동 (%.2fm)" % (player.global_position.x - start_x))
	await get_tree().create_timer(1.0).timeout
	_write("host_x", str(player.global_position.x))
	# 게스트가 끊겼다 돌아오는 동안 대기
	await _wait_file("guest.result", 30.0)
	_check(status_events.has("2:false") and status_events.has("2:true"), "상대 끊김→복귀 알림 %s" % str(status_events))


func _run_guest(village: Node) -> void:
	var code: String = await _wait_file("code", 10.0)
	_check(not code.is_empty(), "방 코드 수신")
	Net.join_room(_server, code)
	await Net.welcomed
	_check(Net.my_id == 2, "게스트 id=2")
	var remote: RemotePlayer = null
	var frames: int = 0
	var samples: Array[Vector3] = []
	var times: Array[float] = []
	var max_walk: float = 0.0
	var t_end: float = Time.get_ticks_msec() + 5000.0
	# 호스트가 움직이는 동안 매 프레임 원격 캐릭터 위치를 기록
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		if remote == null:
			for child: Node in village.get_children():
				if child is RemotePlayer:
					remote = child
		if remote != null:
			samples.append(remote.global_position)
			times.append(Time.get_ticks_usec() / 1000.0)
			max_walk = maxf(max_walk, remote.rig._move_target)
		frames += 1
	_check(remote != null, "원격 캐릭터 생성")
	var max_step: float = 0.0
	var max_back: float = 0.0
	var moving_frames: int = 0
	for i: int in range(1, samples.size()):
		var dx: float = samples[i].x - samples[i - 1].x
		# 헤드리스에서 프레임이 늦어질 수 있어 거리가 아니라 속도(m/s)로 튐을 판정한다.
		var dt_s: float = maxf((times[i] - times[i - 1]) / 1000.0, 0.001)
		max_step = maxf(max_step, absf(dx) / dt_s)
		max_back = maxf(max_back, -dx)
		if dx > 0.0005:
			moving_frames += 1
	var final_x: float = samples[-1].x if not samples.is_empty() else 0.0
	_check(final_x > 5.0, "원격 캐릭터가 호스트 위치로 도달 (x=%.2f)" % final_x)
	# 방향키를 끝까지 누르고 있으면 0.7초 뒤 달리기(7m/s)가 된다. 걷기→달리기로 넘어갈 때 따라잡는 몫까지 1.3배 여유.
	var run_limit: float = (village.get_node("Player") as Player).run_speed * 1.3
	_check(max_step < run_limit, "프레임 간 최대 속도 %.2fm/s (호스트 달리기 7, 튐 없음, %d프레임)" % [max_step, frames])
	_check(max_back < 0.02, "되돌아감 없음 (%.4f)" % max_back)
	_check(max_walk > 0.5, "원격 캐릭터가 걷는 동안 walk 애니메이션 가중치가 올라감 (%.2f)" % max_walk)
	_check(remote != null and remote.rig._move_target < 0.2, "멈추면 idle로 돌아감 (%.2f)" % remote.rig._move_target)
	_check(moving_frames > 20, "연속 프레임에서 부드럽게 이동 (%d프레임)" % moving_frames)

	# 재접속: 소켓을 갑자기 끊는다
	var resumed_flags: Array[bool] = []
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], resumed: bool) -> void: resumed_flags.append(resumed))
	var states: Array[int] = []
	Net.state_changed.connect(func(s: int) -> void: states.append(s))
	var my_id_before: int = Net.my_id
	Net.debug_drop_connection()
	_check(Net.state == Net.State.RECONNECTING, "끊기면 RECONNECTING")
	var waited: float = 0.0
	while Net.state != Net.State.ONLINE and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(Net.state == Net.State.ONLINE, "자동 재접속 성공 (%.1fs)" % waited)
	_check(Net.my_id == my_id_before and resumed_flags == [true], "같은 id로 resume (id=%d, resumed=%s)" % [Net.my_id, str(resumed_flags)])
	_check(remote != null and is_instance_valid(remote), "재접속 후 원격 캐릭터 유지")
	await get_tree().create_timer(0.5).timeout
	_check(is_equal_approx(remote.global_position.x, float(_read("host_x"))) or absf(remote.global_position.x - float(_read("host_x"))) < 0.1, "재접속 후에도 호스트 위치 일치")
