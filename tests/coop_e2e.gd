extends Node
## 같이 하기 종단 테스트 (v0.9, 서버 1개 + 헤드리스 Godot 2개 · tests/run_coop_e2e.sh 가 띄운다).
##   동사무소(창구 상황 버튼 → 전입신고 · 지역화폐 카드 → 혼인신고 제안·수락 → 세대 지갑 하나 → 햇살론유스)
##   → 식당 같이 일하기(재료 합치기 → 한 그릇의 동작을 나눠 맡기 → 팀 보너스)
##   → 갈대 여울(물에 들어가 걷기 → 둘이 몰아 그물질) → 바닷가 조개(같이 파면 두 배) → 삽으로 구덩이·흙길
## 두 프로세스는 --dir 의 작은 파일로 순서를 맞춘다. 인자: -- --role=a|b --server=ws://… --dir=/tmp/…

var _role: String = ""
var _server: String = ""
var _dir: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.trim_prefix("--role=")
		elif arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
		elif arg.begins_with("--dir="):
			_dir = arg.trim_prefix("--dir=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[%s] FAIL: %s" % [_role, f])
	print("[%s] %s" % [_role, "PASS" if _failures.is_empty() else "FAILED"])
	_write("%s.done" % _role, "1")
	# 상대가 끝날 때까지 접속을 유지한다 (먼저 나가면 상대 쪽 확인이 깨진다).
	await _wait_file("%s.done" % ("b" if _role == "a" else "a"), 60.0)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[%s] %s: %s" % [_role, "ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _write(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open("%s/%s" % [_dir, file], FileAccess.WRITE)
	f.store_string(text)


func _read(file: String) -> String:
	var path: String = "%s/%s" % [_dir, file]
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _wait_file(file: String, timeout_s: float) -> String:
	var waited: float = 0.0
	while _read(file).is_empty() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return _read(file)


## 두 사람이 같은 지점까지 왔다는 표시를 남기고 상대를 기다린다.
func _sync(tag: String) -> void:
	_write("%s.%s" % [_role, tag], "1")
	var other: String = await _wait_file("%s.%s" % ["b" if _role == "a" else "a", tag], 40.0)
	_check(not other.is_empty(), "상대와 맞춤: %s" % tag)


func _count(item_id: String) -> int:
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		if it != null and it.id == item_id:
			n += it.count
	return n


## 그 도구를 퀵슬롯 마지막 칸으로 옮겨(가방에 있으면) 손에 든다.
func _hold(item_id: String) -> void:
	var quick: int = Net.quick_slot_count - 1
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it != null and it.id == item_id and i != quick:
			Net.move_item(i, quick)
			await _wait_until(func() -> bool: return Net.inventory[quick] != null and Net.inventory[quick].id == item_id, 2.0)
			break
	Net.equip(quick)
	var player: Player = _village.get_node("Player")
	if not await _wait_until(func() -> bool: return player.held_item == item_id, 2.0):
		print("[%s] 들기 실패 %s: 손=%s 칸=%d 가방=%s" % [_role, item_id, player.held_item, Net.held_slot, str(Net.inventory.map(func(it: InventoryItem) -> String: return it.id if it != null else "-"))])


func _teleport(at: Vector3, yaw: float = 0.0) -> void:
	var player: Player = _village.get_node("Player")
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.body.rotation.y = yaw
	(_village.get_node("CameraRig") as FollowCamera).snap_to_target()
	await get_tree().create_timer(0.5).timeout


## 그쪽을 바로 보게 한다 (모델 정면은 -Z, 몸 돌림은 look_toward 가 붙잡는다).
func _face(direction: Vector3) -> void:
	var player: Player = _village.get_node("Player")
	player.look_toward(direction)
	player.body.rotation.y = atan2(-direction.x, -direction.z)


func _side() -> float:
	return -0.6 if _role == "a" else 0.6


func _run() -> void:
	if _role == "a":
		Net.create_room(_server)
		await Net.welcomed
		_write("code", Net.room_code)
		await _wait_until(func() -> bool: return Net.partner_present, 15.0)
	else:
		var code: String = await _wait_file("code", 15.0)
		Net.join_room(_server, code)
		await Net.welcomed
	_check(Net.partner_present, "둘이 같은 섬에 있다")
	Field.failed.connect(func(kind: String, code: String) -> void: print("[%s] %s 실패: %s" % [_role, kind, code]))
	Field.net_done.connect(func(r: Dictionary) -> void: print("[%s] 그물: %s" % [_role, str(r)]))
	Field.dig_done.connect(func(r: Dictionary) -> void: print("[%s] 삽: %s" % [_role, str(r)]))
	await get_tree().create_timer(0.5).timeout
	await _civic()
	await _kitchen()
	await _shallows()
	await _clams()
	await _terrain()


func _other_id() -> int:
	return 2 if Net.my_id == 1 else 1


# ---- 동사무소 · 혼인신고 · 세대 지갑 ----

func _civic() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var econ: EconomyController = _village.get_node("EconomyController")
	var site: CivicSite = _village.get_node("Civic")
	_check(site.staff_actor("civil") != null and site.staff_actor("welfare") != null and site.staff_actor("finance") != null, "동사무소 창구 직원 셋")
	await _teleport(site.desk_front("civil") + Vector3(_side(), 0.1, 0.0), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.ECONOMY and interaction.target_id == EconomyController.TARGET_CIVIC + "civil", 2.0), "민원 창구 앞 상황 버튼 '%s'" % interaction.target_id)
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return econ.civic.is_open(), 2.0), "동사무소 창이 열림")
	_check(await _wait_until(func() -> bool: return not Economy.civic.is_empty(), 2.0), "창구 정보(자격 · 조건)를 받음")
	var proposed: Array = []
	Economy.marry_proposed.connect(func(from_id: int) -> void: proposed.append(from_id))
	Economy.civil_service("move_in")
	_check(await _wait_until(func() -> bool: return Economy.resident, 2.0), "전입신고 → 솔바람동 주민")
	if _role == "a":
		Economy.apply_program("local_card")
		_check(await _wait_until(func() -> bool: return Economy.has_card, 2.0), "지역화폐 카드 발급 (10%% 캐시백)")
	await _sync("civic_ready")
	var sol_before: int = Net.sol
	_write("%s.sol" % _role, str(sol_before))
	if _role == "a":
		Economy.propose_marriage(_other_id())
	else:
		_check(await _wait_until(func() -> bool: return not proposed.is_empty(), 5.0), "혼인신고 제안을 받음")
		_check(econ.civic.is_open(), "제안 창이 뜬다")
		Economy.answer_marriage(true)
	_check(await _wait_until(func() -> bool: return Economy.is_married(), 5.0), "혼인신고 완료 (배우자 %d)" % Economy.partner)
	var other_before: int = int(await _wait_file("%s.sol" % ("b" if _role == "a" else "a"), 5.0))
	_check(await _wait_until(func() -> bool: return Net.sol == sol_before + other_before, 3.0), "두 사람 솔을 합쳐 세대 지갑 하나 (%s)" % Money.short(Net.sol))
	await _sync("married")
	# 한 사람이 정책대출을 받으면 둘 다 같은 지갑에서 늘어난다.
	var shared: int = Net.sol
	if not Economy.is_married():
		print("[%s] 배우자 없음: civ=%s" % [_role, str(Economy.civic.get("partner", "?"))])
	econ.civic.close()
	if _role == "a":
		await _teleport(site.desk_front("finance") + Vector3(0.0, 0.1, 0.0), PI)
		_check(await _wait_until(func() -> bool: return interaction.target_id == EconomyController.TARGET_CIVIC + "finance", 2.0), "서민금융 창구 상황 버튼")
		Economy.take_loan(5_000_000, "sunshine_youth")
		_check(await _wait_until(func() -> bool: return Economy.loans.any(func(l: Dictionary) -> bool: return str(l.get("product", "")) == "sunshine_youth"), 3.0), "햇살론유스 (고정금리) 대출")
		var loan: Dictionary = {}
		for l: Dictionary in Economy.loans:
			if str(l.get("product", "")) == "sunshine_youth":
				loan = l
		_check(bool(loan.get("fixed", false)) and float(loan.get("rate", 0.0)) <= 0.045 + 0.0001, "고정 %.1f%%" % (float(loan.get("rate", 0.0)) * 100.0))
	_check(await _wait_until(func() -> bool: return Net.sol == shared + 5_000_000, 3.0), "배우자가 받은 대출도 같은 지갑에 들어옴 (%s)" % Money.short(Net.sol))
	await _sync("civic_done")


# ---- 식당 같이 일하기 ----

func _kitchen() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var econ: EconomyController = _village.get_node("EconomyController")
	var restaurant: RestaurantSite = _village.get_node("Restaurant")
	var counter: Vector3 = restaurant.counter_position()
	var judged: Array = []
	Economy.cook_judged.connect(func(r: Dictionary) -> void: judged.append(r))
	if _role == "a":
		await _teleport(counter + Vector3(-0.4, 0.1, 0.0), PI)
		_check(await _wait_until(func() -> bool: return interaction.target_id == EconomyController.TARGET_OPEN, 2.0), "카운터에서 '식당 열기'")
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return Economy.is_rest_owner(), 2.0), "식당 문을 열었다")
		_write("rest_open", "1")
	else:
		await _wait_file("rest_open", 10.0)
		await _teleport(counter + Vector3(0.4, 0.1, 0.0), PI)
		_check(await _wait_until(func() -> bool: return interaction.target_id == EconomyController.TARGET_JOIN, 2.0), "열린 식당 카운터에서 '같이 일하기'")
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return Economy.is_rest_staff(), 2.0), "직원으로 들어감")
		_check(await _wait_until(func() -> bool: return econ.kitchen.is_open(), 2.0), "주방 창이 열림")
	_check(await _wait_until(func() -> bool: return Economy.is_team(), 3.0), "직원 둘 → 팀 보너스")
	# 재료는 두 가방을 합친다: 쌀 2+2, 김 2+2 → 주먹밥 네 그릇까지 주문이 들어온다.
	_check(await _wait_until(func() -> bool: return Economy.orders.size() >= 3, 12.0), "합친 재료만큼 주문이 들어옴 (%d)" % Economy.orders.size())
	var order_id: String = ""
	if _role == "a":
		order_id = str(Economy.orders.keys()[0])
		_write("order", order_id)
		await _wait_file("b.cooking", 5.0)
	else:
		order_id = await _wait_file("order", 5.0)
		econ.kitchen.call("_start_cooking", order_id)
		_write("b.cooking", "1")
	if _role == "a":
		econ.kitchen.call("_start_cooking", order_id)
	await _play_minigame(econ.kitchen)
	_check(await _wait_until(func() -> bool: return judged.any(func(r: Dictionary) -> bool: return str(r.get("order", "")) == order_id), 8.0), "한 그릇을 둘이 나눠 만들어 별점을 받음")
	for r: Dictionary in judged:
		if str(r.get("order", "")) == order_id:
			_check(bool(r.get("team", false)), "팀 보너스 · 나눠 받은 몫 %s (★%d)" % [Money.short(int(r.get("share", 0))), int(r.get("stars", 0))])
	econ.kitchen.close()
	await _sync("kitchen_done")
	if _role == "a":
		Economy.close_restaurant()
	await _wait_until(func() -> bool: return not bool(Economy.rest.get("open", true)), 3.0)


## 미니게임을 사람처럼 친다 (economy_e2e 와 같은 방식, 동작마다 서버 확인을 기다린다).
func _play_minigame(kitchen: KitchenWindow) -> void:
	var tapped_step: int = -1
	var beat: int = 0
	var deadline: float = float(Time.get_ticks_msec()) + 30000.0
	while str(kitchen.get("_order_id")) != "" and kitchen.get("_mode") in [KitchenWindow.Mode.COOKING, KitchenWindow.Mode.RESULT] and float(Time.get_ticks_msec()) < deadline:
		if kitchen.get("_mode") != KitchenWindow.Mode.COOKING:
			await get_tree().process_frame
			continue
		var step: Dictionary = kitchen.get("_step")
		var index: int = kitchen.get("_step_index")
		var t: float = float(Time.get_ticks_msec()) - float(kitchen.get("_step_start_ms"))
		if index != tapped_step:
			tapped_step = index
			beat = 0
			print("[%s] 동작 %d (%s) 맡음" % [_role, index, str(step.get("label", ""))])
		match str(step.get("kind", "")):
			"beats":
				if beat < int(step.get("beats", 4)) and t >= float(step.get("interval_ms", 480)) * float(beat + 1):
					kitchen.call("_on_tap")
					beat += 1
			"grill", "steam":
				var ideal: Dictionary = kitchen.call("next_ideal_input")
				if t >= float(ideal["at"]):
					kitchen.call("_on_release" if bool(ideal["release"]) else "_on_tap")
			"timing":
				if beat == 0 and t >= float(step.get("ideal_ms", 2000)):
					kitchen.call("_on_tap")
					beat = 1
			_:
				if t >= float(beat) * 120.0 and beat < int(step.get("taps", 10)) + 2:
					kitchen.call("_on_tap")
					beat += 1
		await get_tree().process_frame


# ---- 갈대 여울: 물에 들어가 둘이 몰기 ----

func _shallows() -> void:
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var field: FieldController = _village.get_node("Field")
	var zone: Dictionary = Field.zone_at(Vector3(-26.0, 0.0, 2.0))
	_check(not zone.is_empty(), "갈대 여울이 있다")
	await _teleport(Vector3(float(zone["x"]) + _side(), 0.1, float(zone["z"]) + _side() * 3.0))
	_check(await _wait_until(func() -> bool: return player.wading, 1.0), "얕은 물에 들어가 걷는다 (깊은 물은 못 들어감)")
	_check(player.is_on_floor() or player.global_position.y < 0.5, "물속 바닥에 선다 (y=%.2f)" % player.global_position.y)
	await _hold("fishing_net")
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.FIELD and interaction.target_id == FieldController.TARGET_NET, 2.0), "뜰채를 들면 '그물질'")
	_check(await _wait_until(func() -> bool: return Field.shoals.has(str(zone["id"])) and not (Field.shoals[str(zone["id"])]["fish"] as Dictionary).is_empty(), 3.0), "여울에 물고기 떼")
	await _sync("wading")
	_check(await _wait_until(func() -> bool: return bool(Field.shoals[str(zone["id"])].get("panic", false)), 3.0), "둘이 들어가면 물고기가 허둥댄다 (느려짐)")
	var caught: Array = []
	Field.net_done.connect(func(r: Dictionary) -> void:
		if not (r.get("fish", []) as Array).is_empty():
			caught.append(r))
	# 몰이: 둘이 나란히 서서 여울 한쪽 끝에서 반대쪽 끝으로 걸어가며 물고기를 벽으로 몬다.
	var zx: float = float(zone["x"]) + _side() * 2.5
	var z0: float = float(zone["z"]) - float(zone["half_z"]) + 0.8
	var z1: float = float(zone["z"]) + float(zone["half_z"]) - 2.2
	var z: float = z0
	while z < z1:
		player.global_position = Vector3(zx, player.global_position.y, z)
		_face(Vector3.BACK)
		z += 0.35
		await get_tree().create_timer(0.2).timeout
	var fish_now: Dictionary = Field.shoals[str(zone["id"])]["fish"]
	var cornered: int = 0
	for f: Dictionary in fish_now.values():
		if float(f["z"]) > z1 - 1.0:
			cornered += 1
	_check(cornered * 2 >= fish_now.size(), "둘이 몰아서 물고기가 끝으로 몰렸다 (%d/%d)" % [cornered, fish_now.size()])
	var deadline: float = float(Time.get_ticks_msec()) + 20000.0
	while caught.is_empty() and float(Time.get_ticks_msec()) < deadline:
		# 가장 가까운 물고기 바로 앞까지 다가가 뜬다 (도망가므로 따라간다).
		var fish: Dictionary = Field.shoals[str(zone["id"])]["fish"]
		var best: Vector3 = Vector3.INF
		for f: Dictionary in fish.values():
			var at: Vector3 = Vector3(float(f["x"]), 0.1, float(f["z"]))
			if best == Vector3.INF or at.distance_to(player.global_position) < best.distance_to(player.global_position):
				best = at
		if best != Vector3.INF:
			var dir: Vector3 = (best - player.global_position)
			dir.y = 0.0
			# 뜰채 거리(앞 0.9m · 반지름 1.1~1.45m) 끝에서 뜬다 — 너무 다가가면 도망친다.
			var stand: Vector3 = best - dir.normalized() * 1.5 if dir.length() > 0.01 else best
			player.global_position = Vector3(stand.x, player.global_position.y, stand.z)
			_face(dir)
			await get_tree().create_timer(0.12).timeout
			if interaction.target_id == FieldController.TARGET_NET:
				interaction.action_hud.action_pressed.emit()
		await get_tree().create_timer(0.55).timeout
	player.clear_look_direction()
	_check(not caught.is_empty(), "그물로 물고기를 떴다: %s" % (str((caught[0] as Dictionary).get("fish", [])) if not caught.is_empty() else "없음"))
	if not caught.is_empty():
		_check(bool((caught[0] as Dictionary).get("coop", false)), "같이 몰아서 그물이 넓다 (협동)")
	await _sync("net_done")


# ---- 바닷가 조개: 같이 파기 ----

func _clams() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var spot_id: String = ""
	if _role == "a":
		await _wait_until(func() -> bool: return Field.digspots.values().any(func(d: Dictionary) -> bool: return str(d.get("kind", "")) == "beach"), 5.0)
		for d: Dictionary in Field.digspots.values():
			if str(d.get("kind", "")) == "beach":
				spot_id = str(d["id"])
		_write("spot", spot_id)
	else:
		spot_id = await _wait_file("spot", 8.0)
	_check(Field.digspots.has(spot_id), "바닷가에 조개 숨구멍 (%s)" % spot_id)
	if not Field.digspots.has(spot_id):
		return
	var d: Dictionary = Field.digspots[spot_id]
	var at: Vector3 = Vector3(float(d["x"]), 0.1, float(d["z"]))
	await _teleport(at + Vector3(_side() * 1.6, 0.0, 0.0))
	_face(Vector3(-_side(), 0.0, 0.0))
	await _hold("shovel")
	_check(await _wait_until(func() -> bool: return interaction.target_id == FieldController.TARGET_CLAM + spot_id, 2.0), "삽을 들고 숨구멍 곁 → '조개 캐기'")
	var results: Array = []
	Field.dig_done.connect(func(r: Dictionary) -> void: results.append(r))
	var before: int = 0
	for id: String in ["clam_manila", "surf_clam", "razor_clam", "pen_shell"]:
		before += _count(id)
	await _sync("clam_ready")
	var deadline: float = float(Time.get_ticks_msec()) + 8000.0
	while Field.digspots.has(spot_id) and float(Time.get_ticks_msec()) < deadline:
		if interaction.target_id == FieldController.TARGET_CLAM + spot_id:
			interaction.action_hud.action_pressed.emit()
		await get_tree().create_timer(0.6).timeout
	_check(not Field.digspots.has(spot_id), "숨구멍을 다 팠다")
	_check(results.any(func(r: Dictionary) -> bool: return bool(r.get("coop", false))), "같이 파서 한 번에 두 번 판 셈 (협동)")
	_check(await _wait_until(func() -> bool:
		var n: int = 0
		for id: String in ["clam_manila", "surf_clam", "razor_clam", "pen_shell"]:
			n += _count(id)
		return n == before + 1, 2.0), "판 사람 모두 조개 하나씩")
	await _sync("clam_done")


# ---- 삽으로 땅 고치기 ----

func _terrain() -> void:
	var interaction: InteractionController = _village.get_node("InteractionController")
	var field: FieldController = _village.get_node("Field")
	# 마을 서쪽 풀밭 (길·건물 없는 곳).
	var at: Vector3 = Vector3(-40.0 if _role == "a" else -44.0, 0.1, 22.0)
	# 바닥에 채집물이 있으면 '줍기'가 먼저라 조금 비켜 선다.
	for i: int in 6:
		if not Net.drops.values().any(func(d: DropInfo) -> bool: return d.position.distance_to(at) < 3.5):
			break
		at.z += 3.0
	await _teleport(at)
	await _hold("shovel")
	field.shovel_mode = FieldController.ShovelMode.HOLE
	_check(await _wait_until(func() -> bool: return interaction.target_id == FieldController.TARGET_DIG, 2.0), "풀밭에서 '구덩이 파기' (%s)" % interaction.target_id)
	var tiles_before: int = Field.tiles.size()
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return Field.tiles.size() > tiles_before, 2.0), "구덩이가 생김")
	await _sync("holes")
	_check(await _wait_until(func() -> bool: return Field.tiles.values().count(Field.TILE_HOLE) == 2, 2.0), "상대가 판 구덩이도 보인다 (%d)" % Field.tiles.size())
	await get_tree().create_timer(0.5).timeout
	_check(await _wait_until(func() -> bool: return interaction.target_id == FieldController.TARGET_FILL, 2.0), "구덩이 앞 → '구덩이 메우기'")
	interaction.action_hud.action_pressed.emit()
	await get_tree().create_timer(0.6).timeout
	field.shovel_mode = FieldController.ShovelMode.PATH
	_check(await _wait_until(func() -> bool: return interaction.target_id == FieldController.TARGET_PATH, 2.0), "흙길 모드 → '흙길 깔기'")
	interaction.action_hud.action_pressed.emit()
	await _sync("paths")
	_check(await _wait_until(func() -> bool: return Field.tiles.values().count(Field.TILE_PATH) == 2 and Field.tiles.values().count(Field.TILE_HOLE) == 0, 2.0), "구덩이는 메워지고 흙길 둘 (%s)" % str(Field.tiles))
	await _sync("terrain_done")
