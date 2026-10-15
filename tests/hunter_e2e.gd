extends Node
## v0.28 헌터 종단 테스트 (서버 1개 + Godot 1개, 밤 23시 · 크리처가 제자리에 선다, 가방에 마석 E 3 · D 1):
## 헌터 자격증 E급 → 둔치에서 크리처를 "공격"으로 쓰러뜨리면 HUD "헌터 점수 +n" · 처치 수 → 동사무소 대피소 앞 협회 출장소 (모형 · 간판) →
## 창구 앞 상황 버튼 "헌터 협회 창구" → 창 (자격증 · 마석 목록) → "모두 팔기" (솔이 오르고 마석이 빠진다) →
## 휴대폰 헌터넷: 오늘의 의뢰 3개 · 길드 만들기 → 길드 카드.
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
		print("[hunter] FAIL: %s" % f)
	print("[hunter] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[hunter] %s: %s" % ["ok  " if ok else "FAIL", what])
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


func _count(prefix: String) -> int:
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		if it != null and it.id.begins_with(prefix):
			n += it.count
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
	var hunter: HunterController = _village.get_node("Hunter")
	var economy: EconomyController = _village.get_node("EconomyController")
	Net.create_room(_server)
	await Net.welcomed
	await get_tree().create_timer(0.6).timeout
	_check(str(Net.hunter.get("rank", "")) == "E" and int(Net.hunter.get("next", 0)) == GameData.hunter.ranks[1].points, "헌터 자격증 E급 (다음 %d점)" % int(Net.hunter.get("next", 0)))
	_check((Net.hunter.get("bounties", []) as Array).size() == 3, "오늘의 의뢰 3개")

	# ---- 사냥 ----
	await _teleport(Vector3(-150.0, 0.1, 140.0))
	_check(await _wait_until(func() -> bool: return not Net.creatures.is_empty(), 15.0), "둔치에 크리처 (%d)" % Net.creatures.size())
	var popup: Label = hunter.get("_popup")
	var seen_popup: Array = [false]
	var kills: Array = [0]
	Net.hunter_done.connect(func(i: Dictionary) -> void:
		if str(i.get("kind", "")) == "kill":
			kills[0] += 1)
	for i: int in 120:
		if kills[0] > 0:
			break
		var cid: String = Net.creatures.keys()[0] if not Net.creatures.is_empty() else ""
		if cid.is_empty():
			await get_tree().create_timer(0.3).timeout
			continue
		var c: Dictionary = Net.creatures[cid]
		var at: Vector3 = Vector3(float(c.get("x", 0.0)), 0.1, float(c.get("z", 0.0)))
		var player: Player = _village.get_node("Player")
		if player.global_position.distance_to(at) > 1.6:
			await _teleport(at + Vector3(1.0, 0.0, 0.0), PI * 0.5)
		if interaction.target == InteractionController.Target.SURVIVE and interaction.target_id.begins_with("attack:"):
			interaction.action_hud.action_pressed.emit()
		await get_tree().create_timer(0.4).timeout
		seen_popup[0] = seen_popup[0] or popup.visible
	_check(kills[0] > 0, "크리처를 쓰러뜨렸다")
	_check(await _wait_until(func() -> bool: return seen_popup[0] or popup.visible, 1.0), "HUD '%s'" % popup.text)
	_check(popup.text.begins_with("헌터 점수 +"), "점수 안내 글자")
	_check(await _wait_until(func() -> bool: return int(Net.hunter.get("kills", 0)) >= 1 and int(Net.hunter.get("pts", 0)) > 0, 2.0), "처치 %d · 점수 %d" % [int(Net.hunter.get("kills", 0)), int(Net.hunter.get("pts", 0))])
	# v0.28.1 떨어진 것 곁이면 테두리가 빛난다.
	var drops: DropField = _village.get_node("Drops") as DropField
	_check(await _wait_until(func() -> bool:
		for id: String in Net.drops:
			if drops.is_glowing(id):
				return true
		return false, 3.0), "곁에 떨어진 것의 테두리가 빛난다")
	await _shot("hunter_drop_glow")

	# ---- 협회 출장소 ----
	var rules: HunterRules = GameData.hunter
	_check(hunter.office != null and hunter.office.is_inside_tree() and hunter.office.global_position.distance_to(rules.office_position) < 0.1, "동사무소 대피소 앞 협회 출장소")
	var sign_label: Label3D = hunter.office.get_node("Sign") as Label3D
	_check(sign_label != null and sign_label.text.contains("헌터 협회"), "간판 '%s'" % (sign_label.text if sign_label != null else ""))
	var counter: Vector3 = rules.counter_position()
	await _teleport(counter + Vector3(0.0, 0.1, 6.5), PI)
	await _shot("hunter_office")
	await _teleport(counter + Vector3(0.0, 0.1, 0.4), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.HUNTER, 2.0), "창구 앞 상황 버튼 '헌터 협회 창구' (%s)" % interaction.target_id)
	interaction.action_hud.action_pressed.emit()
	await get_tree().process_frame
	_check(hunter.window.is_open(), "창구 창이 열렸다")
	var card: Node = hunter.window.find_child("LicenseCard", true, false)
	_check(card != null, "헌터 자격증 카드")
	var letter: Label = hunter.window.find_child("RankLetter", true, false) as Label
	_check(letter != null and letter.text == "E", "등급 배지 E")
	var rank_button: Button = hunter.window.find_child("RankButton", true, false) as Button
	_check(rank_button != null and rank_button.disabled, "점수가 모자라 재심사 단추가 꺼져 있다 (%s)" % (rank_button.text if rank_button != null else ""))
	var before_mana: int = _count("mana_stone")
	_check(before_mana >= 4, "가방에 마석 %d개" % before_mana)
	_check(hunter.window.find_child("SellButton_*", true, false) != null, "마석마다 '팔기'")
	await _shot("hunter_window")
	var sol0: int = Net.sol
	var sell_all: Button = hunter.window.find_child("SellAll", true, false) as Button
	sell_all.pressed.emit()
	_check(await _wait_until(func() -> bool: return _count("mana_stone") == 0, 3.0), "마석을 모두 팔았다")
	_check(await _wait_until(func() -> bool: return Net.sol > sol0, 2.0), "솔이 올랐다 (%d → %d)" % [sol0, Net.sol])
	hunter.window.close()

	# ---- 헌터넷 ----
	var phone: PhoneWindow = economy.phone
	phone.open()
	await get_tree().create_timer(0.4).timeout
	phone.open_app(PhoneWindow.Tab.HUNTER)
	await get_tree().create_timer(0.6).timeout
	var app: HunterApp = phone.app_view() as HunterApp
	_check(app != null, "헌터넷 앱")
	if app != null:
		_check(app.find_child("LevelCard", true, false) != null and app.find_child("Stat_str", true, false) != null, "능력치 탭 (레벨 · 스탯)")
		await _shot("hunter_stats")
		app.set("_tab", 1)
		app.call("_build")
		await get_tree().process_frame
		_check(app.find_child("Bounty_*", true, false) != null, "오늘의 의뢰 카드")
		await _shot("hunter_app")
		app.set("_tab", 2)
		app.call("_build")
		await get_tree().process_frame
		var edit: LineEdit = app.find_child("GuildName", true, false) as LineEdit
		_check(edit != null, "길드 이름 칸")
		Net.guild_create("새벽길드")
		_check(await _wait_until(func() -> bool: return str(Net.guild.get("name", "")) == "새벽길드" and Net.in_guild(), 3.0), "길드를 만들었다")
		_check(await _wait_until(func() -> bool:
			var c: Node = phone.app_view().find_child("GuildCard", true, false) if phone.app_view() != null else null
			return c != null, 2.0), "길드 카드")
		await _shot("hunter_guild")
	phone.close()
	_finished = true
