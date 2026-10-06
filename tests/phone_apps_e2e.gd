extends Node
## v16 휴대폰 앱 · 설정 · 놀거리 종단 테스트 (서버 1개 + Godot 1개 + 테스트 안의 친구 봇 1명).
##   홈 화면 앱 15개 · 카메라(찍으면 앨범에) · 앨범(친구에게 사진 보내기) · 지도(친구 표시 · 놀러 가기) · 도감 · 날씨 · 음악(곡 고르기)
##   · 업적(가구 10가지 → 업적 · 칭호 달기, 친구 화면에 칭호) · 설정(글자 크기 · 조이스틱 오른쪽 · 진동) · 생일(주민 축하 마을톡)
##   · 친구 집 놀러 가기 · 방명록 · 친구가 보낸 사진 받기.
## tests/run_phone_apps_e2e.sh 가 서버를 START_ITEMS(가구 10가지) · START_FRIENDSHIP=10 · START_SOL 넉넉히로 띄운다.
## 인자: -- --server=ws://127.0.0.1:PORT [--shots=폴더]

var _server: String = ""
var _shots: String = ""
var _failures: Array[String] = []
var _village: Node = null
var _finished: bool = false
var _bot: FriendBot = null


## 같은 마을의 친구 (진짜 클라이언트처럼 서버에 붙는 작은 WebSocket).
class FriendBot:
	extends Node
	var ws: WebSocketPeer = WebSocketPeer.new()
	var inbox: Array[Dictionary] = []
	var id: int = 0
	var rid: int = 0

	func open(url: String) -> void:
		ws.outbound_buffer_size = 1 << 18
		ws.inbound_buffer_size = 1 << 18
		ws.connect_to_url(url)

	func _process(_delta: float) -> void:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if parsed is Dictionary:
				inbox.append(parsed)
				if str(parsed.get("t", "")) == "welcome":
					id = int(parsed.get("id", 0))

	func send(msg: Dictionary) -> void:
		if not msg.has("rid") and msg.get("t") not in ["move", "cal_info", "photo_get"]:
			rid += 1
			msg["rid"] = "b%d" % rid
		ws.send_text(JSON.stringify(msg))

	func ready_state() -> int:
		return ws.get_ready_state()

	func find(pred: Callable) -> Dictionary:
		for m: Dictionary in inbox:
			if pred.call(m):
				return m
		return {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	# 앨범 · 설정은 이 기기의 것 — 테스트는 깨끗한 상태에서.
	for f: String in ["user://album", "user://photo_cache"]:
		var dir: DirAccess = DirAccess.open(f)
		if dir != null:
			for x: String in dir.get_files():
				dir.remove(x)
	for key: String in [Prefs.FONT, Prefs.STICK_SIDE, Prefs.STICK_SIZE, Prefs.MUSIC]:
		Prefs.set_value(key, Prefs.DEFAULTS[key])
	Prefs.set_value(Prefs.VIBRATION, true)
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	if _failures.is_empty() and not _finished:
		_failures.append("테스트가 끝까지 돌지 않음")
	for f: String in _failures:
		print("[apps] FAIL: %s" % f)
	print("[apps] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	for key: String in [Prefs.FONT, Prefs.STICK_SIDE, Prefs.STICK_SIZE, Prefs.MUSIC]:
		Prefs.set_value(key, Prefs.DEFAULTS[key])
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[apps] %s: %s" % ["ok  " if ok else "FAIL", what])
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
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var economy: EconomyController = _village.get_node("EconomyController")
	var phone: PhoneWindow = economy.phone
	var hud: Node = _village.get_node("HUD")
	var achieved: Array[String] = []
	Journal.achieved.connect(func(ids: PackedStringArray) -> void: achieved.append_array(ids))

	Net.create_room(_server)
	await Net.welcomed
	player.global_position = Vector3(2.0, 0.1, 3.0)
	_bot = FriendBot.new()
	add_child(_bot)
	_bot.open(_server)
	_check(await _wait_until(func() -> bool: return _bot.ready_state() == WebSocketPeer.STATE_OPEN, 4.0), "친구 봇 접속")
	_bot.send({"t": "join", "v": NetProtocol.VERSION, "uid": "friendbot%06d" % (randi() % 1000000), "code": Net.room_code, "name": "새미"})
	_check(await _wait_until(func() -> bool: return _bot.id > 0, 4.0), "친구가 같은 마을에 들어옴")
	_bot.send({"t": "move", "x": 6.0, "y": 0.1, "z": 2.0, "yaw": 0.0})

	# ---- 업적: 가구 10가지를 가방에 → 업적 · 띠 ----
	_check(await _wait_until(func() -> bool: return Journal.dex_items.size() >= 10, 4.0), "도감에 가구 10가지 (%d)" % Journal.dex_items.size())
	_check(await _wait_until(func() -> bool: return "items_1" in achieved, 4.0), "업적 '꾸미기 시작' 달성 알림")
	var notices: JournalController = _village.get_node("JournalNotices")
	_check(await _wait_until(func() -> bool: return notices.showing().contains("업적"), 2.0), "업적 띠가 보임")
	await _shot("a01_achievement_banner")

	# ---- 홈 화면 앱 15개 ----
	phone.open()
	await get_tree().create_timer(0.5).timeout
	var icons: int = 0
	for kind: String in PhoneWindow.APP_KINDS:
		if _find(phone, "App_%s" % kind) != null:
			icons += 1
	_check(icons == 15, "홈 화면 앱 아이콘 15개 (%d)" % icons)
	await _shot("a02_home")

	# ---- 업적 앱: 칭호 달기 → 친구 화면에도 ----
	phone.open_app(PhoneWindow.Tab.ACHIEVE)
	await get_tree().create_timer(0.5).timeout
	_check(phone.app_view() is AchievementsApp, "업적 앱")
	await _shot("a03_achievements")
	Journal.set_title("items_1")
	_check(await _wait_until(func() -> bool: return Journal.my_title() == "items_1", 3.0), "칭호를 달았다")
	_check(await _wait_until(func() -> bool: return not _bot.find(func(m: Dictionary) -> bool: return m.get("t") == "title" and int(m.get("id", 0)) == Net.my_id).is_empty(), 3.0), "친구에게 칭호가 알려짐")
	_check(Journal.display_name(Net.my_id).begins_with("「꾸미기 새싹」"), "이름 옆 칭호 (%s)" % Journal.display_name(Net.my_id))

	# ---- 도감 ----
	phone.open_app(PhoneWindow.Tab.DEX)
	await get_tree().create_timer(0.4).timeout
	var dex: DexApp = phone.app_view() as DexApp
	_check(dex != null and _find(dex, "Dex_crucian") != null, "도감 물고기 칸")
	await _shot("a04_dex_fish")

	# ---- 날씨 · 달력 ----
	phone.open_app(PhoneWindow.Tab.WEATHER)
	_check(await _wait_until(func() -> bool: return Journal.calendar.size() == 7, 3.0), "이레치 날씨 · 달력")
	await get_tree().create_timer(0.3).timeout
	await _shot("a05_weather")

	# ---- 음악: 곡 고르기 ----
	phone.open_app(PhoneWindow.Tab.MUSIC)
	await get_tree().create_timer(0.3).timeout
	Prefs.set_value(Prefs.MUSIC, "night_theme")
	_check(await _wait_until(func() -> bool: return Audio.current_music() == "night_theme", 3.0), "고른 곡이 흐른다 (%s)" % Audio.current_music())
	await _shot("a06_music")
	Prefs.set_value(Prefs.MUSIC, "")

	# ---- 카메라: 셀카 찍기 → 앨범 ----
	phone.open_app(PhoneWindow.Tab.CAMERA)
	await get_tree().create_timer(0.8).timeout
	var cam: CameraApp = phone.app_view() as CameraApp
	_check(cam != null, "카메라 앱")
	await _shot("a07_camera_selfie")
	if cam != null and DisplayServer.get_name() != "headless":
		await cam.shoot()
		_check(not cam.last_shot().is_empty() and PhotoAlbum.list().size() == 1, "찍은 사진이 앨범에 (%d장)" % PhotoAlbum.list().size())
	elif cam != null:
		# 화면 없는 실행: 그림을 찍을 수 없어(그리기 신호가 오지 않는다) 작은 사진 한 장을 앨범에 넣고 이어 간다.
		var img: Image = Image.create(PhotoAlbum.SIZE.x, PhotoAlbum.SIZE.y, false, Image.FORMAT_RGB8)
		img.fill(Color("#8FD0EC"))
		_check(not PhotoAlbum.save(img).is_empty(), "앨범에 사진 (화면 없음)")

	# ---- 앨범: 친구에게 보내기 ----
	phone.open_album(PhotoAlbum.list()[0] if not PhotoAlbum.list().is_empty() else "")
	await get_tree().create_timer(0.5).timeout
	await _shot("a08_album_viewer")
	var send: Button = _find(phone, "SendTo_%d" % _bot.id) as Button
	_check(send != null, "친구에게 보내기 단추")
	if send != null:
		send.pressed.emit()
		_check(await _wait_until(func() -> bool: return not _bot.find(func(m: Dictionary) -> bool: return m.get("t") == "msg" and m.get("m", {}).has("ph")).is_empty(), 4.0), "친구가 사진 메시지를 받음")

	# ---- 친구가 보낸 사진을 마을톡에서 받아 본다 ----
	var jpeg: PackedByteArray = PhotoAlbum.bytes_of(PhotoAlbum.list()[0]) if not PhotoAlbum.list().is_empty() else PackedByteArray()
	_bot.send({"t": "photo_up", "th": "pl:%d" % Net.my_id, "img": Marshalls.raw_to_base64(jpeg), "tx": "나도 찍었어!"})
	var th: String = "pl:%d" % _bot.id
	_check(await _wait_until(func() -> bool: return (Talk.threads.get(th, {}).get("m", []) as Array).any(func(m: Dictionary) -> bool: return m.has("ph")), 4.0), "친구 사진이 마을톡으로")
	phone.open_thread(th)
	_check(await _wait_until(func() -> bool:
		for m: Dictionary in Talk.threads.get(th, {}).get("m", []):
			if m.has("ph") and str(m.get("f", "")) != "me" and Journal.photo(str(m["ph"])) != null:
				return true
		return false, 4.0), "사진을 받아 와서 보여 줌")
	await get_tree().create_timer(0.4).timeout
	await _shot("a09_talk_photo")

	# ---- 설정: 글자 크기 · 조이스틱 · 진동 ----
	phone.open_app(PhoneWindow.Tab.SETTINGS)
	await get_tree().create_timer(0.4).timeout
	var probe: Label = Label.new()
	probe.add_theme_font_size_override("font_size", 40)
	hud.add_child(probe)
	await get_tree().process_frame
	await get_tree().process_frame
	Prefs.set_value(Prefs.FONT, "large")
	await get_tree().process_frame
	_check(probe.get_theme_font_size("font_size") == roundi(40 * Prefs.FONT_SCALES["large"]), "글자 크게 (%d)" % probe.get_theme_font_size("font_size"))
	await _shot("a10_settings_large")
	Prefs.set_value(Prefs.FONT, "normal")
	await get_tree().process_frame
	_check(probe.get_theme_font_size("font_size") == 40, "글자 보통으로 돌아옴")
	probe.queue_free()
	var stick: TouchJoystick = hud.get_node("Joystick")
	Prefs.set_value(Prefs.STICK_SIDE, "right")
	Prefs.set_value(Prefs.STICK_SIZE, "large")
	await get_tree().process_frame
	await get_tree().process_frame
	var action_button: Control = hud.get_node("ActionHud").get_node("%ActionButton")
	_check(stick.idle_center().x > get_viewport().get_visible_rect().size.x * 0.5, "조이스틱이 오른쪽")
	_check(action_button.anchor_left < 0.5, "상황 버튼은 왼쪽 아래로")
	_check(is_equal_approx(stick.radius, 140.0 * Prefs.STICK_SCALES["large"]), "조이스틱 크게 (%.0f)" % stick.radius)
	Prefs.set_value(Prefs.STICK_SIDE, "left")
	Prefs.set_value(Prefs.STICK_SIZE, "normal")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(action_button.anchor_left > 0.5 and stick.idle_center().x < get_viewport().get_visible_rect().size.x * 0.5, "다시 왼쪽")
	Prefs.set_value(Prefs.VIBRATION, false)
	_check(not Prefs.vibration(), "진동 끄기")
	Prefs.set_value(Prefs.VIBRATION, true)

	# ---- 생일: 오늘로 → 주민 축하 마을톡 · 띠 ----
	var today: Dictionary = VillageClock.date_of_day(Net.game_day())
	var before: int = Talk.unread_total()
	Journal.set_birthday(int(today["month"]), int(today["day"]))
	_check(await _wait_until(func() -> bool: return Talk.unread_total() >= before + 3, 4.0), "주민들이 생일 축하 마을톡 (%d통)" % (Talk.unread_total() - before))
	_check(await _wait_until(func() -> bool: return Journal.birthday == Vector2i(int(today["month"]), int(today["day"])), 2.0), "생일이 저장됨")
	phone.close()
	_check(await _wait_until(func() -> bool: return notices.showing().contains("생일"), 6.0), "생일 띠")
	await _shot("a11_birthday_banner")

	# ---- 지도 · 친구 집 놀러 가기 · 방명록 ----
	var unit: String = GameData.econ.units[0].id
	_bot.send({"t": "apt_buy", "unit": unit, "loan": 0})
	_check(await _wait_until(func() -> bool: return int(Economy.home_owners.get(unit, 0)) == _bot.id, 4.0), "친구가 집을 샀다 (%s)" % unit)
	phone.open(PhoneWindow.Tab.MAP)
	await get_tree().create_timer(0.6).timeout
	var map: MapApp = phone.app_view() as MapApp
	_check(map != null and _find(map, "Visit_%s" % unit) != null, "지도에 친구 집 놀러 가기")
	await _shot("a12_map")
	Journal.visit(unit)
	phone.close()
	_check(await _wait_until(func() -> bool: return Home.unit == unit and Home.owner_slot == _bot.id, 4.0), "친구 집 안으로")
	_check(await _wait_until(func() -> bool: return not _bot.find(func(m: Dictionary) -> bool: return m.get("t") == "visit").is_empty(), 3.0), "친구에게 놀러 왔다고 알림")
	await get_tree().create_timer(0.6).timeout
	var home_ctl: HomeController = _village.get_node("Home")
	_check(home_ctl._guestbook_button != null and home_ctl._guestbook_button.visible, "방명록 단추")
	home_ctl.guestbook.open()
	Journal.write_guestbook("집이 정말 예뻐요! 또 놀러 올게요")
	_check(await _wait_until(func() -> bool: return Journal.guestbook.size() == 1, 3.0), "방명록에 글이 남음")
	await get_tree().create_timer(0.4).timeout
	await _shot("a13_guestbook")
	_check(await _wait_until(func() -> bool: return not _bot.find(func(m: Dictionary) -> bool: return m.get("t") == "msg" and str(m.get("m", {}).get("tx", "")).contains("방명록")).is_empty(), 3.0), "집 주인에게 방명록 알림")
	home_ctl.guestbook.close()
	_finished = true
