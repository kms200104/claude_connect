extends Node
## v0.20 폰다운 기능 종단 테스트 (서버 1개 + Godot 1개): 앱 스토어(받기 → 홈 화면) · 솔걸음(가속도 흉내 → 서버 인정 걸음) ·
## 재난문자(뇌우 → 긴급재난문자 창 · 기록) · 민방위 훈련(사이렌 · 안내 띠 · 빛기둥 → 대피소에 들어가면 보상).
## tests/run_phone_safety_e2e.sh 가 서버를 WEATHER_FORCE=thunder · DRILL_FORCE=1 로 띄운다.
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
	Prefs.set_value(Prefs.APPS, "")
	AlertLog.clear_for_test()
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	if _failures.is_empty() and not _finished:
		_failures.append("테스트가 끝까지 돌지 않음")
	for f: String in _failures:
		print("[safety] FAIL: %s" % f)
	print("[safety] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	Prefs.set_value(Prefs.APPS, "")
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[safety] %s: %s" % ["ok  " if ok else "FAIL", what])
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


## 떠 있는 재난문자를 다 확인한다 (한 장씩 차례로 뜬다).
func _dismiss_alerts(hud: Node) -> void:
	for i: int in 6:
		var a: Node = hud.find_child("DisasterAlert", true, false)
		if a == null:
			return
		var ok_button: Button = a.find_child("OkButton", true, false) as Button
		ok_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame


func _run() -> void:
	var player: Player = _village.get_node("Player")
	var economy: EconomyController = _village.get_node("EconomyController")
	var phone: PhoneWindow = economy.phone
	var hud: Node = _village.get_node("HUD")
	Net.create_room(_server)
	await Net.welcomed
	player.global_position = Vector3(2.0, 0.1, 3.0)
	await get_tree().create_timer(0.3).timeout
	var safety: SafetyController = economy.safety
	_check(safety != null and safety.pedometer != null, "폰다운 기능이 마을에 붙었다")

	# ---- 재난문자: 뇌우 → 긴급재난문자 창 ----
	_check(await _wait_until(func() -> bool: return hud.find_child("DisasterAlert", true, false) != null, 4.0), "뇌우에 긴급재난문자 창이 뜬다")
	_check(AlertLog.list().any(func(a: Dictionary) -> bool: return str(a.get("id", "")) == "thunder" and str(a.get("level", "")) == "emergency"), "재난문자 기록에 남는다")
	await _shot("s1_alert")
	_check(hud.find_children("DisasterAlert", "", true, false).size() == 1, "재난문자 창은 한 장씩")
	await _dismiss_alerts(hud)

	# ---- 민방위 훈련: 사이렌 · 안내 띠 · 빛기둥 ----
	_check(await _wait_until(func() -> bool: return not Net.drill.is_empty(), 4.0), "민방위 훈련이 시작된다")
	var banner: Label = hud.find_child("DrillBanner", true, false) as Label
	await get_tree().process_frame
	_check(banner != null and banner.is_visible_in_tree() and banner.text.contains("대피소"), "화면 위 훈련 안내: %s" % (banner.text if banner != null else "-"))
	var beam: Node3D = _village.find_child("ShelterBeam", true, false) as Node3D
	_check(beam != null and beam.visible, "대피소에 빛기둥")
	_check(_village.find_child("ShelterSign", true, false) != null, "대피소 표지판")
	await get_tree().create_timer(0.5).timeout
	_check(AlertLog.list().any(func(a: Dictionary) -> bool: return str(a.get("id", "")) == "drill_start"), "훈련 경보 문자")
	await _dismiss_alerts(hud)
	await _shot("s2_drill")

	# ---- 앱 스토어 ----
	phone.open()
	await get_tree().create_timer(0.3).timeout
	var steps_cell: Control = phone.find_child("Cell_steps", true, false) as Control
	_check(steps_cell != null and not steps_cell.visible, "솔걸음은 받기 전엔 홈 화면에 없다")
	phone.open_app(PhoneWindow.Tab.STORE)
	await get_tree().create_timer(0.3).timeout
	var store: StoreApp = phone.app_view() as StoreApp
	_check(store != null, "앱 스토어가 열린다")
	if store == null:
		return
	var get_steps: Button = store.find_child("Get_steps", true, false) as Button
	_check(get_steps != null, "솔걸음 '받기'")
	get_steps.pressed.emit()
	await get_tree().process_frame
	_check(store.find_child("Progress_steps", true, false) != null, "내려받는 막대")
	await _shot("s3_store")
	store.finish_downloads()
	await get_tree().process_frame
	(store.find_child("Get_safety", true, false) as Button).pressed.emit()
	store.finish_downloads()
	await get_tree().process_frame
	_check(phone.is_installed("steps") and phone.is_installed("safety") and steps_cell.visible, "받으면 홈 화면에 생긴다")

	# ---- 솔걸음: 가속도 흉내 (0.5초마다 한 걸음, 24걸음) ----
	var ped: Pedometer = safety.pedometer
	_check(ped.enabled, "솔걸음을 받으면 걸음을 센다")
	var before: int = ped.today
	for s: int in 24:
		for f: int in 30:
			ped.advance(1.0 / 60.0)
			ped.feed(13.5 if f < 4 else 9.8)
	_check(ped.today - before >= 20, "걷는 흔들림으로 걸음을 센다 (%d)" % (ped.today - before))
	var shake: int = ped.today
	ped.advance(3.0)
	for f: int in 6:
		ped.advance(1.0 / 60.0)
		ped.feed(16.0 if f < 3 else 9.8)
	_check(ped.today == shake, "한 번 흔든 것은 세지 않는다")
	ped.report()
	_check(await _wait_until(func() -> bool: return Net.steps_today > 0, 3.0), "서버가 걸음을 인정 (%d)" % Net.steps_today)
	phone.open_app(PhoneWindow.Tab.STEPS)
	await get_tree().create_timer(0.3).timeout
	_check(phone.app_view() is StepsApp and phone.app_view().find_child("Tier_0", true, false) != null, "솔걸음 앱: 오늘 걸음 · 목표")
	await _shot("s4_steps")
	phone.open_app(PhoneWindow.Tab.SAFETY)
	await get_tree().create_timer(0.3).timeout
	var app: PhoneApp = phone.app_view()
	_check(app is SafetyApp and app.find_child("Shelter", true, false) != null and app.find_child("DrillSchedule", true, false) != null, "안전알림 앱: 대피소 · 훈련 일정 · 문자 기록")
	await _shot("s5_safety")
	phone.close()
	await get_tree().create_timer(0.3).timeout

	# ---- 대피소로 → 보상 ----
	var sol0: int = Net.sol
	var shelter: Vector2 = GameData.safety.shelter
	player.global_position = Vector3(shelter.x, 0.2, shelter.y)
	_check(await _wait_until(func() -> bool: return bool(Net.drill.get("done", false)), 4.0), "대피소에 들어가면 훈련 참여")
	_check(Net.sol == sol0 + GameData.safety.drill_reward, "참여 보상 %s" % Money.short(GameData.safety.drill_reward))
	await get_tree().process_frame
	_check(not banner.is_visible_in_tree(), "대피하면 안내 띠가 사라진다")
	_finished = true
