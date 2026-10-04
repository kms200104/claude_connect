extends Node
## 첫 화면 종단 테스트: 서버 주소를 적고 "새 마을 만들기" → 마을로 들어감 → 나갔다가 앱을 다시 켠 것처럼 첫 화면을 새로 띄우면
## 서버 주소와 마지막 방이 채워져 있고 "시작하기" 한 번으로 같은 방에 다시 들어간다.
## 인자: -- --title-server=ws://127.0.0.1:PORT --profile=9 (실제 앱 설정과 섞이지 않게 다른 저장 슬롯)

var _server: String = ""
var _failures: Array[String] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--title-server="):
			_server = arg.trim_prefix("--title-server=")
	# 이 슬롯의 이전 기록을 지우고 처음 켠 것처럼 시작한다.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Net._settings_path()))
	await _run()
	for f: String in _failures:
		print("[title] FAIL: %s" % f)
	print("[title] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[title] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _open_title() -> TitleScreen:
	var title: TitleScreen = load("res://ui/title/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	return title


func _run() -> void:
	# 1. 처음 켬: 서버 주소를 적고 새 마을 만들기.
	var title: TitleScreen = await _open_title()
	var hud: CanvasLayer = title.get_child(0).get_node("HUD")
	_check(not hud.visible, "첫 화면에서는 게임 HUD 를 숨김")
	_check(title.get_node("%StartDetail").text == "새 마을 만들기", "기록이 없으면 '새 마을 만들기' 안내 (%s)" % title.get_node("%StartDetail").text)
	(title.get_node("%ServerEdit") as LineEdit).text = _server
	(title.get_node("%CreateButton") as Button).pressed.emit()
	var online: bool = await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 8.0)
	_check(online, "새 마을로 접속")
	await _wait_until(func() -> bool: return not is_instance_valid(title.get_node_or_null("Overlay")), 2.0)
	_check(title.get_node_or_null("Overlay") == null and hud.visible, "들어가면 첫 화면이 사라지고 HUD 가 보임")
	var code: String = Net.room_code
	_check(code.length() == NetProtocol.ROOM_CODE_LENGTH, "방 코드 받음 (%s)" % code)

	# 2. 방을 나가고 앱을 다시 켠 것처럼 첫 화면을 새로 띄운다.
	Net.leave()
	title.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	title = await _open_title()
	_check((title.get_node("%ServerEdit") as LineEdit).text == _server, "서버 주소를 기억함 (%s)" % (title.get_node("%ServerEdit") as LineEdit).text)
	_check((title.get_node("%CodeEdit") as LineEdit).text == code, "마지막 방 코드를 기억함")
	_check(title.get_node("%StartDetail").text == "방 %s 들어가기" % code, "시작 버튼 안내: %s" % title.get_node("%StartDetail").text)
	(title.get_node("%StartButton") as Button).pressed.emit()
	online = await _wait_until(func() -> bool: return Net.state == Net.State.ONLINE, 8.0)
	_check(online and Net.room_code == code, "시작하기 한 번으로 같은 방에 다시 들어감 (%s)" % Net.room_code)
	Net.leave()
