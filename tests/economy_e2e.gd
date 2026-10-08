extends Node
## 마을 경제 종단 테스트 (v0.8, 클라이언트 1개 · 서버 1개 · tests/run_economy_e2e.sh 가 띄운다).
##   증권(시세 받기 → 휴대폰 → 매수·매도) → 은행(신용·금리 → 대출 → 상환) → 부동산(부스 '부동산' → 아파트 사기 → 발코니 깃발)
##   → 식당(카운터 '식당 열기' → 재료만큼만 주문 → 주방 요리 미니게임 → 별점·돈 → 앉은 손님) → 들판 채집 → 성성호수 낚시터
## 인자: -- --server=ws://…

var _server: String = ""
var _failures: Array[String] = []
var _village: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.trim_prefix("--server=")
	_village = load("res://game/village/village.tscn").instantiate()
	add_child(_village)
	await get_tree().create_timer(0.3).timeout
	await _run()
	for f: String in _failures:
		print("[economy] FAIL: %s" % f)
	print("[economy] %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("[economy] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited: float = 0.0
	while not cond.call() and waited < timeout_s:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _accounts() -> Array:
	return Array(Economy.bank.get("sv", {}).get("accounts", []))


func _count(item_id: String) -> int:
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		if it != null and it.id == item_id:
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
	var player: Player = _village.get_node("Player")
	var interaction: InteractionController = _village.get_node("InteractionController")
	var econ: EconomyController = _village.get_node("EconomyController")
	var apartments: ApartmentSite = _village.get_node("Apartments")
	var restaurant: RestaurantSite = _village.get_node("Restaurant")
	var fishing: FishingController = _village.get_node("FishingController")

	Net.create_room(_server)
	await Net.welcomed
	await get_tree().process_frame

	# ---- 증권 ----
	_check(Economy.stocks.size() == 10, "종목 10개 시세를 받음")
	var sbe: StockQuote = Economy.stock("SBE")
	_check(sbe != null and sbe.price > 0, "솔바람전자 %s솔" % (Money.digits(sbe.price) if sbe != null else "?"))
	var ticks: Array = [0]
	Economy.market_changed.connect(func() -> void: ticks[0] += 1)
	_check(await _wait_until(func() -> bool: return ticks[0] >= 1, 3.0), "분 단위 시세가 움직인다 (MARKET_TICK_MS)")
	var phone_button: Button = _village.get_node("HUD/PhoneButton")
	_check(phone_button != null and phone_button.visible, "HUD 에 휴대폰 단추")
	phone_button.pressed.emit()
	await get_tree().process_frame
	_check(econ.phone.is_open() and econ.phone.is_on_home(), "휴대폰이 열림 (홈 화면)")
	var me: Player = _village.get_node("Player")
	_check(me.rig.is_holding_phone() and me.is_input_locked(), "캐릭터가 휴대폰을 꺼내 든다 (멈춰 서서)")
	await get_tree().create_timer(0.6).timeout
	_check(me.rig.phone_prop() != null and me.rig.phone_prop().visible, "손에 휴대폰 모형")
	var stocks_icon: PhoneAppIcon = econ.phone.find_child("App_stocks", true, false)
	_check(stocks_icon != null, "홈 화면에 증권 앱 아이콘")
	stocks_icon.pressed.emit()
	await get_tree().process_frame
	_check(econ.phone.current_app() == PhoneWindow.Tab.STOCKS, "아이콘을 누르면 증권 앱")
	econ.phone.set("_stock_id", "SBE")
	econ.phone.go_back()
	_check(econ.phone.current_app() == PhoneWindow.Tab.STOCKS and str(econ.phone.get("_stock_id")) == "", "뒤로: 종목 화면 → 종목 목록")
	econ.phone.go_back()
	_check(econ.phone.is_on_home(), "뒤로: 앱 → 홈 화면")
	econ.phone.open_app(PhoneWindow.Tab.BANK)
	econ.phone.go_home()
	_check(econ.phone.is_on_home(), "홈 단추: 앱 → 홈 화면")
	# 설정 앱 (v0.14.2): 소리 · 화질 · 닉네임
	var settings_icon: PhoneAppIcon = econ.phone.find_child("App_settings", true, false)
	_check(settings_icon != null, "홈 화면에 설정 앱 아이콘")
	settings_icon.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var sp: SettingsPanel = econ.phone.settings_panel()
	_check(sp != null and sp.volume_slider("music") != null, "설정 앱: 닉네임 · 소리 · 화질 · 화면")
	if sp != null:
		var music0: float = Audio.volume("music")
		sp.volume_slider("music").value = 40.0
		var bus: int = AudioServer.get_bus_index("Music")
		_check(is_equal_approx(Audio.volume("music"), 0.4) and AudioServer.get_bus_volume_db(bus) < Audio.music_volume_db - 5.0, "배경음악 40%% → 버스가 작아진다 (%.1fdB)" % AudioServer.get_bus_volume_db(bus))
		sp.volume_slider("sfx").value = 0.0
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "효과음 0% = 끔")
		Audio.set_volume("music", music0)
		Audio.set_volume("sfx", 1.0)
		sp.name_edit().text = "휴대폰이름"
		sp.save_name()
		_check(await _wait_until(func() -> bool: return Net.names.get(Net.my_id, "") == "휴대폰이름", 3.0), "설정 앱에서 닉네임 저장")
		sp.name_edit().text = ""
		sp.save_name()
		# 지도 항상 보기: 켜면 휴대폰을 닫은 마을 화면 오른쪽 위에 작은 지도, 누르면 지도 앱.
		var mini: MiniMap = econ.minimap
		_check(mini != null and sp.minimap_toggle() != null and not sp.minimap_toggle().button_pressed and not mini.should_show(), "설정 앱: '지도 항상 보기' (처음엔 꺼짐)")
		sp.minimap_toggle().button_pressed = true
		econ.phone.close()
		_check(await _wait_until(func() -> bool: return mini.visible and mini.size.x > 100.0, 1.5), "지도 항상 보기를 켜면 마을 화면에 작은 지도")
		econ.phone.open(PhoneWindow.Tab.SETTINGS)
		_check(await _wait_until(func() -> bool: return not mini.visible, 1.0), "휴대폰을 연 동안은 작은 지도를 감춘다")
		econ.phone.close()
		await _wait_until(func() -> bool: return mini.visible, 1.0)
		var tap: InputEventMouseButton = InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		mini.call("_gui_input", tap)
		_check(await _wait_until(func() -> bool: return econ.phone.visible and econ.phone.app_view() is MapApp, 1.5), "작은 지도를 누르면 휴대폰 지도 앱")
		econ.phone.open(PhoneWindow.Tab.SETTINGS)
		await get_tree().process_frame
		sp = econ.phone.settings_panel()
		if sp != null:
			sp.minimap_toggle().button_pressed = false
		# 방 정보 줄의 "설정" 단추도 휴대폰 설정 앱을 연다 (설정은 휴대폰 한 곳에).
		econ.phone.close()
		var room_settings: Button = _village.get_node("HUD").find_child("QualityButton", true, false)
		_check(room_settings != null, "방 정보 줄 '설정' 단추")
		if room_settings != null:
			room_settings.pressed.emit()
			await get_tree().process_frame
			_check(econ.phone.visible and econ.phone.settings_panel() != null, "'설정' 단추 → 휴대폰 설정 앱")
			_check(_village.get_node("HUD").find_child("QualityWindow", true, false) == null, "마을에는 따로 된 설정 창이 없다")
	econ.phone.go_home()
	econ.phone.open_app(PhoneWindow.Tab.STOCKS)
	var sol0: int = Net.sol
	var trades: Array = []
	Economy.trade_done.connect(func(r: Dictionary) -> void: trades.append(r))
	Economy.order_stock("SBE", "buy", 5)
	_check(await _wait_until(func() -> bool: return trades.size() == 1, 3.0), "솔바람전자 5주 매수 체결")
	_check(await _wait_until(func() -> bool: return Economy.holding_qty("SBE") == 5, 2.0), "보유 5주")
	_check(Net.sol < sol0 and sol0 - Net.sol == int(trades[0].get("amount", 0)) if not trades.is_empty() else false, "솔에서 매수 금액(수수료 포함)이 빠짐")
	Economy.order_stock("SBE", "sell", 2)
	_check(await _wait_until(func() -> bool: return trades.size() == 2 and Economy.holding_qty("SBE") == 3, 3.0), "2주 매도 → 3주 남음")
	_check(int(trades[1].get("tax", 0)) > 0 if trades.size() > 1 else false, "매도할 때 증권거래세")
	econ.phone.open(PhoneWindow.Tab.ASSETS)
	await get_tree().process_frame
	_check(Economy.net_worth > 0, "자산 앱: 순자산 %s" % Money.short(Economy.net_worth))
	econ.phone.go_home()
	econ.phone.go_back()
	_check(not econ.phone.is_open(), "홈 화면에서 뒤로 = 휴대폰 넣기")
	_check(await _wait_until(func() -> bool: return not me.rig.is_holding_phone() and not me.is_input_locked() and not me.rig.phone_prop().visible, 2.0), "휴대폰을 넣고 다시 움직인다")

	# ---- 은행 ----
	var banked: Array = [false]
	Economy.bank_changed.connect(func() -> void: banked[0] = true)
	Economy.ask_bank()
	_check(await _wait_until(func() -> bool: return banked[0], 2.0), "은행 창구 정보")
	_check(int(Economy.bank.get("grade", 0)) >= 1 and float(Economy.bank.get("rate_credit", 0.0)) > float(Economy.bank.get("rate_mortgage", 1.0)), "신용 %d등급 · 신용대출 %s > 담보대출 %s" % [int(Economy.bank.get("grade", 0)), Money.percent(float(Economy.bank.get("rate_credit", 0.0))), Money.percent(float(Economy.bank.get("rate_mortgage", 0.0)))])
	var loans: Array = []
	Economy.loan_done.connect(func(r: Dictionary) -> void: loans.append(r))
	Economy.take_loan(1000000)
	_check(await _wait_until(func() -> bool: return loans.size() == 1, 2.0), "신용대출 100만 솔")
	_check(await _wait_until(func() -> bool: return Economy.loans.size() == 1 and Economy.debt == 1000000, 2.0), "대출 목록·빚에 반영")
	var loan_id: String = str(Economy.loans[0].get("id", "")) if not Economy.loans.is_empty() else ""
	Economy.repay_loan(loan_id, 1000000)
	_check(await _wait_until(func() -> bool: return loans.size() == 2 and Economy.loans.is_empty(), 2.0), "전액 상환")
	var sv: Dictionary = Economy.bank.get("sv", {})
	_check(Array(sv.get("institutions", [])).size() == 6 and Array(sv.get("products", [])).size() >= 10, "예적금: 금융기관 6곳 · 상품 %d개" % Array(sv.get("products", [])).size())
	var deps: Array[Dictionary] = []
	Economy.deposit_done.connect(func(r: Dictionary) -> void: deps.append(r))
	Economy.open_deposit("deundeun_deposit", 12, 5000000)
	_check(await _wait_until(func() -> bool: return deps.size() == 1 and _accounts().size() == 1, 2.0), "저축은행 정기예금 500만 가입 → 내 예적금")
	Economy.park_move(2000000)
	_check(await _wait_until(func() -> bool: return deps.size() == 2 and int(deps[1].get("balance", 0)) == 2000000, 2.0), "파킹통장 200만 넣기")
	var dep_id: String = str(deps[0].get("id", ""))
	Economy.close_deposit(dep_id)
	_check(await _wait_until(func() -> bool: return deps.size() == 3 and bool(deps[2].get("early", false)) and int(deps[2].get("net", 0)) >= 5000000, 2.0), "중도해지: 원금은 그대로")
	Economy.park_move(-2000000)
	_check(await _wait_until(func() -> bool: return deps.size() == 4 and _accounts().is_empty(), 2.0), "파킹통장 다 빼기 → 계좌 없음")
	econ.phone.set("_bank_savings", true)
	econ.phone.set("_sv_bank", "gureum")
	econ.phone.open(PhoneWindow.Tab.BANK)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(econ.phone.is_open(), "은행 앱 예적금 화면이 열림")
	econ.phone.close()

	# ---- 부동산 ----
	var office: Vector3 = apartments.office_position()
	await _teleport(office + Vector3(0.0, 0.1, 0.8), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.ECONOMY and interaction.target_id == EconomyController.TARGET_ESTATE, 2.0), "부스 곁에서 '부동산'")
	interaction.action_hud.action_pressed.emit()
	await get_tree().process_frame
	_check(econ.phone.is_open(), "부동산 앱이 열림")
	econ.phone.close()
	var apts: Array = []
	Economy.apt_done.connect(func(r: Dictionary) -> void: apts.append(r))
	Economy.buy_home("101-501", 0)
	_check(await _wait_until(func() -> bool: return apts.size() == 1, 3.0), "101동 501호를 샀다")
	_check(await _wait_until(func() -> bool: return Economy.home_owners.get("101-501", 0) == Net.my_id, 2.0), "집 주인이 나")
	await get_tree().process_frame
	_check(apartments.get_node("Flags").get_child_count() == 1, "발코니에 금빛 깃발")
	_check(apartments.unit_position("101-1001").y > apartments.unit_position("101-101").y + 10.0, "10층짜리 동")
	var sol_before_lease: int = Net.sol
	Economy.lease_home("101-501", "jeonse")
	_check(await _wait_until(func() -> bool: return apts.size() == 2 and Economy.home_leases.has("101-501"), 3.0), "전세로 놓기 → 보증금")
	_check(await _wait_until(func() -> bool: return Net.sol - sol_before_lease == int(Economy.home_leases.get("101-501", {}).get("deposit", -1)), 2.0), "보증금만큼 솔이 늘었다")
	Economy.lease_home("101-501", "rent")
	_check(await _wait_until(func() -> bool: return apts.size() == 3 and not Economy.home_leases.has("101-501"), 3.0), "보증금 돌려주고 월세로")

	# ---- 일거리: 배달 알바 ----
	var jobs: JobController = _village.get_node("Jobs")
	var job_done: Array[Dictionary] = []
	Economy.job_done.connect(func(r: Dictionary) -> void: job_done.append(r))
	Economy.take_job("parcel")
	_check(await _wait_until(func() -> bool: return not Economy.job().is_empty(), 2.0), "배달 알바를 받았다")
	_check(me.rig.is_uniformed() and me.rig.get_node("Visual/Waist/Upper/Neck/Head/UniformHelmet").visible, "배달하는 동안 파란 헬멧 · 배달 가방")
	_check(await _wait_until(func() -> bool: return jobs.chip_text().contains("받기"), 2.0), "칩: %s" % jobs.chip_text())
	var job: Dictionary = Economy.job()
	var from: Dictionary = job.get("from", {})
	# v0.13.7 방향 화살표: 멀리 있으면 캐릭터 둘레에서 받을 곳 쪽을 가리킨다.
	var walker: Player = _village.get_node("Player")
	var from_at: Vector3 = Vector3(float(from.get("x", 0.0)), 0.0, float(from.get("z", 0.0)))
	await _teleport(from_at + Vector3(0.0, 0.1, 25.0))
	await get_tree().create_timer(0.2).timeout
	var arrow: Node3D = jobs.get_node("JobArrow")
	var to_target: Vector3 = (from_at - walker.global_position) * Vector3(1, 0, 1)
	var pointing: Vector3 = -arrow.global_basis.z
	_check(arrow.visible and pointing.normalized().dot(to_target.normalized()) > 0.98, "화살표가 받을 곳을 가리킨다 (%.2f)" % pointing.normalized().dot(to_target.normalized()))
	_check(absf(Vector2(arrow.global_position.x - walker.global_position.x, arrow.global_position.z - walker.global_position.z).length() - jobs.arrow_radius) < 0.3, "화살표는 캐릭터 둘레에")
	await _teleport(Vector3(float(from.get("x", 0.0)), 0.1, float(from.get("z", 0.0)) + 0.6))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.JOB and interaction.target_id == JobController.TARGET_PICK, 2.0), "받을 곳에서 '물건 받기'")
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return Economy.carry_item() == "parcel", 2.0), "택배 상자를 들었다")
	_check(await _wait_until(func() -> bool: return (_village.get_node("Player") as Player).held_item == "parcel", 1.0), "손에 상자가 보인다")
	var to: Dictionary = Economy.job().get("to", {})
	await _teleport(Vector3(float(to.get("x", 0.0)) + 3.0, 0.1, float(to.get("z", 0.0)) + 2.5))
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.JOB and interaction.target_id == JobController.TARGET_DROP, 2.0), "주민 집 앞에서 '배달하기'")
	var sol_before_job: int = Net.sol
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return job_done.size() == 1, 3.0), "배달 완료")
	_check(int(job_done[0].get("tip", 0)) > 0 if not job_done.is_empty() else false, "빨리 와서 팁")
	_check(await _wait_until(func() -> bool: return Net.sol - sol_before_job == int(job_done[0].get("total", 0)) and Economy.job().is_empty(), 2.0), "삯이 지갑에 · 일거리 끝")
	_check(int(job_done[0].get("streak", 0)) == 1 and int(Economy.jobs.get("streak", 0)) == 1, "연속 팁 1번째 (보너스는 2번째부터)")
	_check(not jobs.get_node("JobArrow").visible, "일이 끝나면 화살표도 사라진다")
	_check(not me.rig.is_uniformed(), "일이 끝나면 헬멧 · 가방도 벗는다")
	econ.phone.open(PhoneWindow.Tab.JOBS)
	await get_tree().process_frame
	_check(econ.phone.is_open() and int(Economy.jobs.get("done", 0)) == 1, "일거리 앱: 오늘 1건")
	econ.phone.close()

	# ---- v17 테스트 도구: 설정 앱의 "테스트: 2000억 솔 받기" ----
	_check(Net.dev_tools, "테스트 도구가 켜진 서버 (DEV_TOOLS=1)")
	econ.phone.open(PhoneWindow.Tab.SETTINGS)
	await get_tree().process_frame
	var settings: SettingsPanel = econ.phone.get("_settings")
	_check(settings != null and settings.dev_button != null, "설정에 '테스트: 2000억 솔 받기' 단추")
	if settings != null and settings.dev_button != null:
		var sol_before_dev: int = Net.sol
		settings.dev_button.pressed.emit()
		_check(await _wait_until(func() -> bool: return Net.sol - sol_before_dev == 200000000000, 3.0), "누르면 2000억 솔이 들어온다 (%s)" % Money.short(Net.sol - sol_before_dev))
	econ.phone.close()

	# ---- 식당 ----
	var counter: Vector3 = restaurant.counter_position()
	await _teleport(counter + Vector3(0.0, 0.1, 0.0), PI)
	_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.ECONOMY and interaction.target_id == EconomyController.TARGET_OPEN, 2.0), "카운터에서 '식당 열기'")
	var arrived: Array = []
	Economy.order_arrived.connect(func(o: Dictionary) -> void: arrived.append(o))
	interaction.action_hud.action_pressed.emit()
	_check(await _wait_until(func() -> bool: return Economy.is_rest_owner(), 2.0), "식당 문을 열었다")
	_check(await _wait_until(func() -> bool: return econ.kitchen.is_open(), 2.0), "주방 창이 저절로 열림")
	# 가방: 쌀 2 · 김 2 → 주먹밥 2그릇만. 손님은 그만큼만 주문한다.
	_check(await _wait_until(func() -> bool: return arrived.size() >= 2, 6.0), "손님 두 명이 주문 (%d)" % arrived.size())
	await get_tree().create_timer(1.5).timeout
	_check(arrived.size() == 2 and arrived.all(func(o: Dictionary) -> bool: return str(o.get("dish", "")) == "rice_ball"), "재료만큼만, 만들 수 있는 요리만 주문: %s" % str(arrived.map(func(o: Dictionary) -> String: return str(o.get("dish", "")))))
	_check(restaurant.get_child_count() > 0 and await _wait_until(func() -> bool: return _seated(restaurant) == 2, 2.0), "손님이 의자에 앉음 (%d)" % _seated(restaurant))
	var judged: Array = []
	Economy.cook_judged.connect(func(r: Dictionary) -> void: judged.append(r))
	var order_id: String = str(arrived[0].get("order", ""))
	econ.kitchen.call("_start_cooking", order_id)
	# v9: 서버가 동작을 맡겨 주면(rest_claim) 요리 자세를 잡는다.
	_check(await _wait_until(func() -> bool: return player.rig.is_cooking() and player.is_input_locked(), 2.0), "요리 동작을 하며 멈춰 선다")
	await _play_minigame(econ.kitchen)
	_check(await _wait_until(func() -> bool: return not judged.is_empty(), 4.0), "요리를 냈다 → 별점")
	if not judged.is_empty():
		_check(int(judged[0].get("stars", 0)) >= 4, "솜씨 좋게 → ★%d (솜씨 %s · 입맛 %s)" % [int(judged[0].get("stars", 0)), str(judged[0].get("quality")), str(judged[0].get("taste"))])
		_check(int(judged[0].get("pay", 0)) > 0, "받은 돈 %s" % Money.short(int(judged[0].get("pay", 0))))
	_check(await _wait_until(func() -> bool: return _count("rice") == 1 and _count("laver") == 1, 2.0), "재료가 한 그릇 분 빠짐")
	_check(not player.rig.is_cooking(), "요리가 끝나면 원래 자세")
	econ.kitchen.close()
	Economy.close_restaurant()
	_check(await _wait_until(func() -> bool: return not bool(Economy.rest.get("open", true)), 2.0), "문을 닫았다")
	_check(await _wait_until(func() -> bool: return _seated(restaurant) == 0, 3.0), "남은 손님이 떠남")

	# ---- 채집 ----
	var forage: DropInfo = null
	for d: DropInfo in Net.drops.values():
		if d.kind == DropInfo.KIND_FORAGE:
			forage = d
	_check(forage != null, "들판에 채집물: %s" % (forage.item if forage != null else "없음"))
	if forage != null:
		await _teleport(forage.position + Vector3(0.6, 0.1, 0.0))
		_check(await _wait_until(func() -> bool: return interaction.target == InteractionController.Target.COLLECT, 2.0), "'채집' 버튼")
		var before: int = _count(forage.item)
		interaction.action_hud.action_pressed.emit()
		_check(await _wait_until(func() -> bool: return _count(forage.item) == before + 1, 2.0), "%s 을(를) 채집" % GameData.item_name(forage.item))

	# ---- 성성호수 낚시터 ----
	var spot: SpotInfo = GameData.spots.get("seongseong")
	# 실제 윤곽 호수: 바깥 사각형 위쪽이 아니라 북쪽에서 가장 가까운 물가에 선다.
	var shore: Vector2 = spot.boundary_nearest(Vector2(spot.center.x, spot.center.y - spot.half_extent.y))
	await _teleport(Vector3(shore.x, 0.1, shore.y - 1.0))
	Net.equip(0)
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	_check(fishing.spot != null and fishing.spot.spot_id == "seongseong", "성성호수 물가에서는 그 호수로 던진다")
	_check(fishing.spot.can_cast_from(player.global_position), "성성호수에서 낚시할 수 있다")

	# ---- 바다 낚시 (v0.12): 섬 둘레 바닷가 어디서나 ----
	var half: float = GameData.layout.island_half
	await _teleport(Vector3(half - 2.0, 0.1, 0.0), -PI * 0.5)
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	_check(fishing.spot != null and fishing.spot.spot_id == "sea", "바닷가에서는 바다로 던진다 (%s)" % (fishing.spot.spot_id if fishing.spot != null else "-"))
	_check(fishing.spot.can_cast_from(player.global_position), "바닷가에서 낚시할 수 있다")
	var bobber_at: Vector3 = fishing.spot.info.clamp_inside(player.global_position + Vector3(4.0, 0.0, 0.0))
	_check(GameData.layout.island_shape(Vector2(bobber_at.x, bobber_at.z)) > 1.0, "찌는 바다 위에 떨어진다")
	var started: Array = [false]
	Net.fish_started.connect(func(_shadow: float) -> void: started[0] = true, CONNECT_ONE_SHOT)
	fishing.call("_on_action_pressed")
	_check(await _wait_until(func() -> bool: return started[0], 3.0), "바다에 낚싯대를 던졌다")


func _seated(site: RestaurantSite) -> int:
	return (site.get("_guests") as Dictionary).size()


## 미니게임을 사람처럼 친다: 박자에 맞춰 · 딱 좋은 때 · 빠르게 연타.
func _play_minigame(kitchen: KitchenWindow) -> void:
	var tapped_step: int = -1
	var beat: int = 0
	var deadline: float = float(Time.get_ticks_msec()) + 30000.0
	# v9: 동작마다 서버가 맡김을 확인(RESULT → COOKING)하므로 요리가 판정될 때까지 돈다.
	while str(kitchen.get("_order_id")) != "" and kitchen.get("_mode") in [KitchenWindow.Mode.COOKING, KitchenWindow.Mode.RESULT] and float(Time.get_ticks_msec()) < deadline:
		if kitchen.get("_mode") != KitchenWindow.Mode.COOKING:
			await get_tree().process_frame
			continue
		var step: Dictionary = kitchen.get("_step")
		var index: int = kitchen.get("_step_index")
		var start: float = kitchen.get("_step_start_ms")
		var t: float = float(Time.get_ticks_msec()) - start
		if index != tapped_step:
			tapped_step = index
			beat = 0
		match str(step.get("kind", "")):
			"beats":
				var next: float = float(step.get("interval_ms", 480)) * float(beat + 1)
				if beat < int(step.get("beats", 4)) and t >= next:
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
				if t >= 0.0 and beat < int(step.get("taps", 10)) + 2 and t >= float(beat) * 120.0:
					kitchen.call("_on_tap")
					beat += 1
		await get_tree().process_frame
