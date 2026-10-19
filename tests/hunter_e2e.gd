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
	# (떨어진 것의 테두리를 보려고 저절로 줍기를 잠깐 끈다 — 아래에서 다시 켠다.)
	Prefs.set_value(Prefs.AUTO_PICKUP, false)
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
	Prefs.set_value(Prefs.AUTO_PICKUP, true)
	await _shot("hunter_drop_glow")

	# ---- 협회 출장소 ----
	var rules: HunterRules = GameData.hunter
	_check(hunter.office != null and hunter.office.is_inside_tree() and hunter.office.global_position.distance_to(rules.office_position) < 0.1, "동사무소 대피소 앞 협회 출장소")
	var sign_label: Label3D = hunter.office.get_node("Sign") as Label3D
	_check(sign_label != null and sign_label.text.contains("헌터 협회"), "간판 '%s'" % (sign_label.text if sign_label != null else ""))
	var counter: Vector3 = rules.counter_position()
	await _teleport(counter + Vector3(0.0, 0.1, 6.5), PI)
	await _shot("hunter_office")
	# v0.28.16 창구 앞 1.8m (예전엔 창이 열려도 서버가 출장소 가운데에서 재서 막혔다).
	await _teleport(counter + Vector3(0.0, 0.1, 1.8), PI)
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
	# v0.28.14 협회 상점 탭: 물건마다 줄, 등급이 모자란 물건은 꺼져 있다, 점수가 되면 산다.
	(hunter.window.find_child("TabStore", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var plate: Button = hunter.window.find_child("BuyButton_armor_plate", true, false) as Button
	_check(hunter.window.find_child("Store_first_aid_kit", true, false) != null and plate != null and plate.disabled and plate.text.contains("D급"), "협회 상점: 줄 · D급 물건은 잠김 (%s)" % (plate.text if plate != null else ""))
	# v0.28.15 헌터 마일리지 (시험 서버 START_MILEAGE=500).
	var merit: int = int(Net.hunter.get("mi", 0))
	_check(merit >= 500, "마일리지 %d" % merit)
	var bolt: Button = hunter.window.find_child("BuyButton_crossbow_bolt", true, false) as Button
	var bolts0: int = _count("crossbow_bolt")
	bolt.pressed.emit()
	_check(await _wait_until(func() -> bool: return _count("crossbow_bolt") >= bolts0 + 10 and int(Net.hunter.get("mi", 0)) == merit - 12, 3.0), "마일리지로 석궁 화살을 샀다 (%d → %d)" % [merit, int(Net.hunter.get("mi", 0))])
	# 아공간 주머니 (소): 가방이 5칸 늘고, 단추는 '샀어요', 다음 단계 (중) 는 D급부터.
	var cap0: int = Net.inventory_capacity
	await get_tree().process_frame
	(hunter.window.find_child("BuyButton_subspace_pouch_s", true, false) as Button).pressed.emit()
	_check(await _wait_until(func() -> bool: return Net.inventory_capacity == cap0 + 5 and int(Net.hunter.get("bag", 0)) == 5, 3.0), "아공간 주머니: 가방 %d → %d칸" % [cap0, Net.inventory_capacity])
	await get_tree().process_frame
	await get_tree().process_frame
	var pouch: Button = hunter.window.find_child("BuyButton_subspace_pouch_s", true, false) as Button
	_check(pouch != null and pouch.disabled and pouch.text == "샀어요", "산 주머니는 '샀어요' (%s)" % (pouch.text if pouch != null else ""))
	await _shot("hunter_store")
	hunter.window.close()
	# 가방 창에 늘어난 칸이 다 보인다.
	var bag: InventoryWindow = _village.get_node("HUD/InventoryWindow")
	bag.open()
	await get_tree().create_timer(0.4).timeout
	var grid: GridContainer = bag.find_child("BagGrid", true, false) as GridContainer
	_check(grid != null and grid.get_child_count() == Net.inventory_capacity and grid.columns == 7, "가방 창 %d칸 (한 줄 %d칸)" % [grid.get_child_count() if grid != null else -1, grid.columns if grid != null else -1])
	await _shot("hunter_bag")
	# v0.28.17 가방 정렬: 등급별 → 비싼 것이 앞 칸, 종류별 → 도구가 앞 칸.
	var first_bag: Callable = func() -> String:
		for i: int in range(Net.quick_slot_count, Net.inventory.size()):
			if Net.inventory[i] != null:
				return Net.inventory[i].id
		return ""
	(bag.find_child("SortGrade", true, false) as Button).pressed.emit()
	var top_price: Callable = func() -> int:
		var best: int = 0
		for i: int in range(Net.quick_slot_count, Net.inventory.size()):
			if Net.inventory[i] != null and GameData.item(Net.inventory[i].id) != null:
				best = maxi(best, GameData.item(Net.inventory[i].id).price)
		return best
	_check(await _wait_until(func() -> bool: return GameData.item(first_bag.call()) != null and GameData.item(first_bag.call()).price == top_price.call(), 3.0), "등급별 정렬 (맨 앞 %s)" % first_bag.call())
	(bag.find_child("SortKind", true, false) as Button).pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var kinds: PackedStringArray = []
	for i: int in range(Net.quick_slot_count, Net.inventory.size()):
		if Net.inventory[i] != null:
			kinds.append(GameData.item(Net.inventory[i].id).kind if GameData.item(Net.inventory[i].id) != null else "?")
	_check(kinds.size() >= 1 and (kinds.size() < 2 or kinds[0] != "goods" or not kinds.has("material")), "종류별 정렬 (%s)" % ",".join(kinds))
	# v0.28.17 아공간 보관함: 가방 '아공간 보관함' → 어디서든 열고 넣는다.
	(bag.find_child("VaultButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	var survival: SurvivalController = _village.get_node("Survival")
	_check(survival.stash_window.is_open() and survival.stash_window.vault, "아공간 보관함이 열렸다 (가방에서, 어디서든)")
	var vput: Button = survival.stash_window.find_child("Put_*", true, false) as Button
	_check(vput != null, "보관함 '넣기'")
	if vput != null:
		vput.pressed.emit()
		_check(await _wait_until(func() -> bool: return (Net.hunter.get("vault", []) as Array).size() == 1, 3.0), "보관함에 넣었다 (%s)" % str(Net.hunter.get("vault", [])))
	await _shot("hunter_vault")
	survival.stash_window.close()

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
		# v0.28.5 각성 (Lv.10 → 두 자리): 마력 방패 · 기척 감지를 고르고, HUD 단추로 방패를 쓴다.
		var pick: Button = app.find_child("AwakenPick_shield", true, false) as Button
		_check(pick != null and not pick.disabled, "각성 고르기 단추 (마력 방패)")
		if pick != null:
			pick.pressed.emit()
		_check(await _wait_until(func() -> bool: return Net.has_awaken("shield"), 3.0), "마력 방패 각성")
		await get_tree().create_timer(0.3).timeout
		var pick2: Button = phone.app_view().find_child("AwakenPick_sense", true, false) as Button
		if pick2 != null:
			pick2.pressed.emit()
		_check(await _wait_until(func() -> bool: return Net.has_awaken("sense"), 3.0), "기척 감지 각성")
		await get_tree().create_timer(0.3).timeout
		var pick3: Button = phone.app_view().find_child("AwakenPick_shadow", true, false) as Button
		_check(pick3 != null and pick3.disabled, "자리가 다 차면 더 고를 수 없다")
		await _shot("hunter_awaken")
		# v0.28.8 전직 (Lv.10): 직업 카드 → '전직' → 기술 나무, 첫 줄 기술을 배운다 (포인트 1).
		app.set("_tab", 1)
		app.call("_build")
		await get_tree().process_frame
		var jp_btn: Button = app.find_child("JobPick_warrior", true, false) as Button
		_check(jp_btn != null and not jp_btn.disabled and app.find_child("Job_ranger", true, false) != null, "전직 카드 (전사 · 사수 …)")
		await _shot("hunter_job_pick")
		if jp_btn != null:
			jp_btn.pressed.emit()
		_check(await _wait_until(func() -> bool: return Net.job_id() == "warrior" and int(Net.hunter.get("jp", 0)) == 1, 3.0), "전사로 전직 · 기술 포인트 1")
		# v0.28.9 직업 겉모습: 목에 전사 색 스카프 · 등에 휘장.
		var me: Player = _village.get_node("Player")
		_check(await _wait_until(func() -> bool: return me.rig.neck.get_node_or_null("JobScarf") != null and me.rig.upper.get_node_or_null("JobEmblem") != null, 3.0), "전사 스카프 · 휘장")
		# 2차 전직은 Lv.30 부터 (단추가 잠겨 있다).
		await get_tree().create_timer(0.3).timeout
		var adv_btn: Button = app.find_child("Advance", true, false) as Button
		_check(adv_btn != null and adv_btn.disabled, "2차 전직 단추 (Lv.30 전에는 잠김)")
		await get_tree().create_timer(0.3).timeout
		var tree: SkillTreeView = app.find_child("SkillTree", true, false) as SkillTreeView
		_check(tree != null and tree.node_button("w_power") != null and tree.node_button("w_whirl") != null, "기술 나무 (강타 · 회전 베기)")
		if tree != null:
			tree.node_button("w_cleave").pressed.emit()
			await get_tree().create_timer(0.2).timeout
			var locked: Button = app.find_child("SkillUp", true, false) as Button
			_check(locked != null and locked.disabled, "앞 기술이 없으면 '배우기' 를 못 누른다")
			tree = app.find_child("SkillTree", true, false) as SkillTreeView
			tree.node_button("w_power").pressed.emit()
			await get_tree().create_timer(0.2).timeout
			var up: Button = app.find_child("SkillUp", true, false) as Button
			_check(up != null and not up.disabled, "강타 '배우기'")
			if up != null:
				up.pressed.emit()
			_check(await _wait_until(func() -> bool: return int(Net.job_learned().get("w_power", 0)) == 1 and int(Net.hunter.get("jp", 0)) == 0, 3.0), "강타 1단계 · 포인트 0")
			await get_tree().create_timer(0.3).timeout
			await _shot("hunter_skill_tree")
		app.set("_tab", 2)
		app.call("_build")
		await get_tree().process_frame
		_check(app.find_child("Bounty_*", true, false) != null, "오늘의 의뢰 카드")
		# v0.28.17 협회 임무 (매일 · 매주): 마석을 팔았으니 '마석 매각' 이 1개 이상, 처치도 1.
		_check(app.find_child("Missions_daily", true, false) != null and app.find_child("Missions_weekly", true, false) != null and app.find_child("Mission_d_kill", true, false) != null, "협회 임무 (오늘 · 이번 주)")
		var dk: Array = (Net.hunter.get("missions", {}) as Dictionary).get("daily", [])
		_check(dk.any(func(m: Dictionary) -> bool: return str(m.get("id", "")) == "d_kill" and int(m.get("got", 0)) >= 1), "처치가 임무에 센다 (%s)" % str(dk))
		await _shot("hunter_missions")
		await _shot("hunter_app")
		app.set("_tab", 3)
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
	# v0.28.5 HUD 각성 단추: 누르면 방패가 몸을 감싸고, 다시 쓰기까지 단추가 잠긴다.
	var aw: AwakenHud = hunter.awaken_hud
	_check(aw.has_button("shield") and not aw.has_button("sense"), "쓰는 각성만 HUD 단추 (방패)")
	(aw.find_child("Awaken_shield", true, false) as Button).pressed.emit()
	_check(await _wait_until(func() -> bool: return aw.fx_active(Net.my_id, "shield"), 3.0), "마력 방패가 몸을 감싼다")
	_check(await _wait_until(func() -> bool: return (aw.find_child("Awaken_shield", true, false) as Button).disabled, 2.0), "다시 쓰기까지 단추가 잠긴다")
	await _shot("hunter_shield")
	_finished = true
