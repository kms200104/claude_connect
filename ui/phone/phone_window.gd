class_name PhoneWindow
extends Control
## 휴대폰: 증권 · 부동산 · 은행 · 자산 네 가지 앱. 값은 서버가 보낸 것(Economy)만 보여 주고, 사고팔기·대출은 서버가 확정한다.
## 증권은 1분마다 시세가 움직이고(모의 거래소 또는 MARKET_FEED_URL 시세 서버), 부동산은 성성호수 아파트 60호,
## 은행은 신용점수에 따라 금리가 바뀌는 신용대출·주택담보대출, 자산은 순자산과 이번 주 소득을 한눈에.

signal closed

enum Tab { STOCKS, HOMES, BANK, ASSETS, TALK }

const BG: Color = Color(0.99, 0.96, 0.88, 0.99)
const EDGE: Color = Color(0.3, 0.26, 0.24)
const INK: Color = Color(0.3, 0.2, 0.12)
const SOFT: Color = Color(0.5, 0.42, 0.34)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.7)
const PICKED: Color = Color(0.98, 0.84, 0.55)
const UP: Color = Color("#D8402F")
const DOWN: Color = Color("#2F62C8")
const GOOD: Color = Color("#3E8E4E")
const TAB_NAMES: PackedStringArray = ["증권", "부동산", "은행", "자산", "마을톡"]
## 마을톡 말풍선: 내 것(노랑) · 받은 것(흰색).
const MINE: Color = Color("#FFE27A")
const THEIRS: Color = Color(1.0, 1.0, 1.0, 0.95)
const WIDTH: float = 1000.0

var _tab: Tab = Tab.STOCKS
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _clock: Label = null
## 증권: 고른 종목과 주문 수량.
var _stock_id: String = ""
var _qty: int = 1
## 부동산: 고른 호수와 대출 비율.
var _unit_id: String = ""
var _building: String = ""
var _loan_ratio: float = 0.0
## 동사무소에서 승인받은 디딤돌대출로 살지 (v9).
var _use_didimdol: bool = false
var _dirty: bool = false
var _week_reports: Array[Dictionary] = []
## 마을톡: 열어 둔 대화방 ("" = 목록)과 쓰다 만 글.
var _thread: String = ""
var _draft: String = ""
var _talk_badge: Label = null
## 글을 쓰는 중이었는지 (새 메시지로 화면을 다시 그려도 자판을 닫지 않는다).
var _typing: bool = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.05, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var phone: PanelContainer = PanelContainer.new()
	phone.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 56, 10, 26))
	HudLayout.center_top(phone, WIDTH, 120.0)
	phone.offset_bottom = 1780.0
	add_child(phone)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	phone.add_child(col)
	# 위: 시계 · 제목 · 닫기
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	_clock = _label("", 28, SOFT)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_clock)
	var close_button: Button = _button("닫기", 30)
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	col.add_child(tabs)
	for i: int in TAB_NAMES.size():
		var b: Button = _button(TAB_NAMES[i], 34)
		b.custom_minimum_size = Vector2(0, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(open.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	for sig: Signal in [Economy.market_changed, Economy.portfolio_changed, Economy.homes_changed, Economy.bank_changed]:
		sig.connect(func() -> void: _dirty = true)
	Talk.changed.connect(func() -> void:
		_update_talk_badge()
		if visible and _tab == Tab.TALK:
			_dirty = true)
	_talk_badge = _label("", 22, Color.WHITE, false)
	_talk_badge.add_theme_stylebox_override("normal", EventHud._box(Color("#E0483A"), Color("#B03028"), 18, 0, 6))
	_talk_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_talk_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_talk_badge.position = Vector2(-44.0, -6.0)
	_tab_buttons[Tab.TALK].add_child(_talk_badge)
	_update_talk_badge()
	Economy.week_passed.connect(func(r: Dictionary) -> void:
		_week_reports.push_front(r)
		if _week_reports.size() > 6:
			_week_reports.pop_back()
		_dirty = true)


func is_open() -> bool:
	return visible


func open(tab: int = -1) -> void:
	if tab >= 0:
		_tab = tab as Tab
	visible = true
	if _tab == Tab.BANK:
		Economy.ask_bank()
	for i: int in _tab_buttons.size():
		_tab_buttons[i].add_theme_stylebox_override("normal", EventHud._box(PICKED if i == _tab else CARD, EDGE, 26, 3, 10))
	_rebuild()
	Audio.play_sfx("ui_open", -6.0)


func close() -> void:
	if not visible:
		return
	visible = false
	_typing = false
	Audio.play_sfx("ui_close", -6.0)
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var h: float = Net.game_hour()
	_clock.text = "%02d:%02d · 솔 %s" % [int(h), int(fmod(h, 1.0) * 60.0), Money.short(Net.sol)]
	if _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	var keep: int = _scroll.scroll_vertical
	for c: Node in _body.get_children():
		c.queue_free()
	match _tab:
		Tab.STOCKS:
			_build_stocks()
		Tab.HOMES:
			_build_homes()
		Tab.BANK:
			_build_bank()
		Tab.ASSETS:
			_build_assets()
		Tab.TALK:
			_build_talk()
			if not _thread.is_empty():
				# 대화방은 늘 맨 아래(최근 메시지)를 보여 준다.
				_scroll.set_deferred("scroll_vertical", 1 << 20)
				return
	_scroll.set_deferred("scroll_vertical", keep)


# ---- 증권 ----

func _build_stocks() -> void:
	var source: String = "시세 서버 연동" if Economy.market_source == "feed" else "모의 거래소"
	_body.add_child(_label("솔바람 증권 · %s · 1분마다 갱신 · %s" % [source, "장 열림" if Economy.market_open else "장 마감"], 26, SOFT))
	var s: StockQuote = Economy.stock(_stock_id)
	if s != null:
		_build_stock_detail(s)
	for st: StockQuote in Economy.stocks:
		var row: Button = _row_button()
		var line: HBoxContainer = HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
		_fill(line)
		var name_box: VBoxContainer = VBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(name_box)
		name_box.add_child(_label(st.display_name + ("  ★%d주" % Economy.holding_qty(st.id) if Economy.holding_qty(st.id) > 0 else ""), 32, INK))
		name_box.add_child(_label("%s · %s" % [st.id, st.sector], 22, SOFT))
		var price_box: VBoxContainer = VBoxContainer.new()
		price_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(price_box)
		var rate: float = st.change_rate()
		var color: Color = UP if rate > 0.0 else (DOWN if rate < 0.0 else INK)
		var price: Label = _label(Money.digits(st.price), 32, color, false)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_box.add_child(price)
		var change: Label = _label(("▲ " if rate > 0.0 else ("▼ " if rate < 0.0 else "")) + Money.percent(absf(rate)), 24, color, false)
		change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_box.add_child(change)
		row.pressed.connect(func() -> void:
			_stock_id = "" if _stock_id == st.id else st.id
			_qty = 1
			_rebuild()
			_scroll.set_deferred("scroll_vertical", 0))
		_body.add_child(row)


func _build_stock_detail(s: StockQuote) -> void:
	var card: VBoxContainer = _card()
	var rate: float = s.change_rate()
	card.add_child(_label("%s (%s)" % [s.display_name, s.id], 38, INK))
	card.add_child(_label(s.about, 24, SOFT))
	card.add_child(_label("%s솔  %s%s" % [Money.digits(s.price), "▲" if rate > 0.0 else ("▼" if rate < 0.0 else ""), Money.percent(absf(rate))], 34, UP if rate > 0.0 else (DOWN if rate < 0.0 else INK)))
	var chart: PriceChart = PriceChart.new()
	chart.custom_minimum_size = Vector2(0, 300)
	chart.set_data(s.hist, s.ref)
	card.add_child(chart)
	var held: Dictionary = Economy.holdings.get(s.id, {})
	var q: int = int(held.get("q", 0))
	if q > 0:
		var cost: int = int(held.get("cost", 0))
		var value: int = s.price * q
		var avg: int = cost / q
		var pl: int = GameData.econ.sell_proceeds(s.price, q) - cost
		card.add_child(_label("보유 %d주 · 평균 %s솔 · 평가 %s" % [q, Money.digits(avg), Money.short(value)], 26, INK))
		card.add_child(_label("팔면 손익 %s (수수료·거래세 뺀 값)" % Money.delta(pl), 26, UP if pl > 0 else DOWN))
	# 수량 고르기
	var qty_row: HBoxContainer = HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)
	card.add_child(qty_row)
	for step: int in [-10, -1, 1, 10]:
		var b: Button = _button(("%+d" % step), 28)
		b.custom_minimum_size = Vector2(110, 80)
		b.pressed.connect(func() -> void:
			_qty = maxi(1, _qty + step)
			_rebuild())
		qty_row.add_child(b)
	var max_buy: int = maxi(1, int(float(Net.sol) / (float(s.price) * (1.0 + Economy.fee_rate))))
	var all_buy: Button = _button("최대", 28)
	all_buy.custom_minimum_size = Vector2(110, 80)
	all_buy.pressed.connect(func() -> void:
		_qty = max_buy
		_rebuild())
	qty_row.add_child(all_buy)
	var qty_label: Label = _label("%d주" % _qty, 34, INK, false)
	qty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_row.add_child(qty_label)
	var buy_cost: int = GameData.econ.buy_cost(s.price, _qty)
	var sell_get: int = GameData.econ.sell_proceeds(s.price, _qty)
	var trade_row: HBoxContainer = HBoxContainer.new()
	trade_row.add_theme_constant_override("separation", 12)
	card.add_child(trade_row)
	var buy: Button = _button("매수 %s" % Money.short(buy_cost), 30, UP)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = buy_cost > Net.sol or not Economy.market_open
	buy.pressed.connect(Economy.order_stock.bind(s.id, "buy", _qty))
	trade_row.add_child(buy)
	var sell: Button = _button("매도 %s" % Money.short(sell_get), 30, DOWN)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.disabled = _qty > q or not Economy.market_open
	sell.pressed.connect(Economy.order_stock.bind(s.id, "sell", _qty))
	trade_row.add_child(sell)
	card.add_child(_label("수수료 %s · 매도 시 증권거래세 %s · 하루 ±30%% 가격 제한" % [Money.percent(Economy.fee_rate, 3), Money.percent(Economy.tax_rate, 2)], 22, SOFT))


# ---- 부동산 ----

func _build_homes() -> void:
	var econ: EconData = GameData.econ
	_body.add_child(_label("%s · 집값 지수 %.3f" % [econ.complex_name(), Economy.apt_index], 30, INK))
	_body.add_child(_label("취득세 %s · 중개보수 %s · 주택담보대출 LTV %s · 세를 놓으면 주마다 월세(연 %s)" % [
		Money.percent(float(econ.apartments.get("acquisition_tax", 0.011)), 1), Money.percent(float(econ.apartments.get("broker_fee", 0.004)), 1),
		Money.percent(float(econ.apartments.get("ltv", 0.7)), 0), Money.percent(float(econ.apartments.get("rent_yield", 0.035)), 1)], 22, SOFT))
	var u: EconData.Unit = econ.unit(_unit_id)
	if u != null:
		_build_unit_detail(u)
	if _building.is_empty() and not econ.buildings().is_empty():
		_building = str((econ.buildings()[0] as Dictionary).get("id", ""))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	for b: Variant in econ.buildings():
		var bid: String = str((b as Dictionary).get("id", ""))
		var bb: Button = _button("%s동" % bid, 30, INK, bid == _building)
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.pressed.connect(func() -> void:
			_building = bid
			_rebuild())
		row.add_child(bb)
	# 층 × 호 표 (위층부터).
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	var list: Array[EconData.Unit] = []
	for unit: EconData.Unit in econ.units:
		if unit.building == _building:
			list.append(unit)
	list.sort_custom(func(a: EconData.Unit, b: EconData.Unit) -> bool: return a.floor > b.floor or (a.floor == b.floor and a.line < b.line))
	for unit: EconData.Unit in list:
		var owner_slot: int = Economy.home_owners.get(unit.id, -1)
		var tag: String = "" if owner_slot < 0 else ("내 집" if owner_slot == Net.my_id else "%s 집" % GameData.player_name(owner_slot))
		var b: Button = _button("%s · %s㎡\n%s%s" % [unit.id, str(int(econ.type_info(unit.type).get("area", 0))), Money.short(econ.unit_price(unit, Economy.apt_index)), ("  [%s]" % tag) if not tag.is_empty() else ""], 26, INK, unit.id == _unit_id)
		b.custom_minimum_size = Vector2(470, 100)
		if owner_slot == Net.my_id:
			b.add_theme_color_override("font_color", Color("#9A6A10"))
		b.pressed.connect(func() -> void:
			_unit_id = "" if _unit_id == unit.id else unit.id
			_rebuild()
			_scroll.set_deferred("scroll_vertical", 0))
		grid.add_child(b)


func _build_unit_detail(u: EconData.Unit) -> void:
	var econ: EconData = GameData.econ
	var card: VBoxContainer = _card()
	var type: Dictionary = econ.type_info(u.type)
	var price: int = econ.unit_price(u, Economy.apt_index)
	card.add_child(_label("%s동 %d층 %d호 · %s · 방 %d" % [u.building, u.floor, u.line, str(type.get("name", u.type)), int(type.get("rooms", 3))], 32, INK))
	card.add_child(_label("시세 %s · 월세 수입 주 %s" % [Money.short(price), Money.short(econ.weekly_rent(price))], 30, INK))
	var owner_slot: int = Economy.home_owners.get(u.id, -1)
	if owner_slot == Net.my_id:
		var bought: int = Economy.home_bought.get(u.id, price)
		var fee: int = roundi(float(price) * float(econ.apartments.get("broker_fee", 0.004)))
		var mortgage: int = 0
		for l: Dictionary in Economy.loans:
			if str(l.get("unit", "")) == u.id:
				mortgage += int(l.get("principal", 0))
		card.add_child(_label("산 값 %s → 지금 %s (%s)" % [Money.short(bought), Money.short(price), Money.delta(price - bought)], 28, UP if price >= bought else DOWN))
		card.add_child(_label("팔면 %s 받고, 이 집 담보대출 %s 부터 갚는다" % [Money.short(price - fee), Money.short(mortgage)], 26, SOFT))
		var sell: Button = _button("팔기", 32, DOWN)
		sell.pressed.connect(Economy.sell_home.bind(u.id))
		card.add_child(sell)
		return
	if owner_slot >= 0:
		card.add_child(_label("%s 님의 집이에요." % GameData.player_name(owner_slot), 28, SOFT))
		return
	var total: int = econ.purchase_total(price)
	var max_loan: int = econ.mortgage_limit(price)
	var loan: int = floori(float(max_loan) * _loan_ratio / 10000.0) * 10000
	var rate: float = float(Economy.bank.get("rate_mortgage", 0.0))
	card.add_child(_label("필요한 돈 %s (취득세·중개보수 포함)" % Money.short(total), 28, INK))
	var ratio_row: HBoxContainer = HBoxContainer.new()
	ratio_row.add_theme_constant_override("separation", 8)
	card.add_child(ratio_row)
	ratio_row.add_child(_label("대출", 28, INK))
	for r: float in [0.0, 0.3, 0.5, 0.7]:
		var b: Button = _button("없음" if r == 0.0 else "LTV %d%%" % roundi(r * 100.0), 26, INK, is_equal_approx(_loan_ratio, r / maxf(float(econ.apartments.get("ltv", 0.7)), 0.01)) or (r == 0.0 and _loan_ratio == 0.0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_loan_ratio = r / maxf(float(econ.apartments.get("ltv", 0.7)), 0.01)
			if r > 0.0:
				Economy.ask_bank()
			_rebuild())
		ratio_row.add_child(b)
	# 디딤돌대출 (동사무소 승인을 받았을 때): 고정금리, 승인 한도·LTV 안에서.
	var didim: Dictionary = Economy.approvals.get("didimdol", {}) if Economy.approvals.get("didimdol") is Dictionary else {}
	if not didim.is_empty():
		var d_btn: Button = _button("디딤돌대출로 (고정 연 %s · 한도 %s)" % [Money.percent(float(didim.get("rate", 0.0))), Money.short(int(didim.get("limit", 0)))], 26, GOOD, _use_didimdol)
		d_btn.disabled = price > int(didim.get("priceMax", 0))
		d_btn.pressed.connect(func() -> void:
			_use_didimdol = not _use_didimdol
			_rebuild())
		card.add_child(d_btn)
	var policy: String = ""
	if _use_didimdol and not didim.is_empty() and loan > 0:
		var cap: int = mini(int(didim.get("limit", 0)), floori(float(price) * float(didim.get("ltv", 0.7)) / 10000.0) * 10000)
		# 고른 비율(최대 대비)만큼 디딤돌 한도에서 빌린다.
		loan = floori(float(cap) * clampf(_loan_ratio, 0.0, 1.0) / 10000.0) * 10000
		rate = float(didim.get("rate", 0.0))
		policy = "didimdol"
	if loan > 0:
		card.add_child(_label("담보대출 %s · 금리 연 %s (%s) · 주 이자 약 %s" % [Money.short(loan), Money.percent(rate) if rate > 0.0 else "?", "고정, 디딤돌" if policy == "didimdol" else "변동", Money.short(ceili(float(loan) * rate / 52.0))], 26, SOFT))
		if policy.is_empty():
			card.add_child(_label("소득이 없으면 은행이 빌려주지 않아요 (DSR 40%). 무주택이면 동사무소에서 디딤돌대출 승인을 받아 보세요.", 22, SOFT))
	var need: int = total - loan
	var buy: Button = _button("사기 (내 돈 %s)" % Money.short(need), 32, UP)
	buy.disabled = need > Net.sol
	buy.pressed.connect(Economy.buy_home.bind(u.id, loan, policy))
	card.add_child(buy)


# ---- 은행 ----

func _build_bank() -> void:
	var b: Dictionary = Economy.bank
	_body.add_child(_label("솔바람은행 · 금리는 주마다 다시 매겨요 (기준금리 + 신용 가산)", 26, SOFT))
	var card: VBoxContainer = _card()
	var score: int = int(b.get("score", Economy.credit_score))
	var grade: int = int(b.get("grade", Economy.credit_grade))
	card.add_child(_label("신용점수 %d점 · %d등급" % [score, grade], 38, INK))
	var bar: MeterBar = MeterBar.make(26.0, score / 1000.0, GOOD if grade <= 4 else (Color("#E8A820") if grade <= 6 else UP))
	card.add_child(bar)
	card.add_child(_label("기준금리 %s · 신용대출 %s · 주택담보 %s" % [Money.percent(float(b.get("base", 0.0))), Money.percent(float(b.get("rate_credit", 0.0))), Money.percent(float(b.get("rate_mortgage", 0.0)))], 28, INK))
	card.add_child(_label("연 소득(최근 4주 × 52) %s · 이번 주 번 돈 %s" % [Money.short(int(b.get("income_year", Economy.income_year))), Money.short(int(b.get("income_week", Economy.income_week)))], 26, SOFT))
	card.add_child(_label("신용대출 남은 한도 %s · DSR %s 이하" % [Money.short(int(b.get("credit_limit", 0))), Money.percent(float(b.get("dsr", 0.4)), 0)], 26, SOFT))
	card.add_child(_label("이자를 꼬박꼬박 내고 소득이 늘면 점수가 오르고, 연체하거나 빚이 자산의 절반을 넘으면 깎여요.", 22, SOFT))
	var take_row: HBoxContainer = HBoxContainer.new()
	take_row.add_theme_constant_override("separation", 8)
	card.add_child(take_row)
	var limit: int = int(b.get("credit_limit", 0))
	for amount: int in [1000000, 5000000, 10000000, -1]:
		var a: int = limit if amount < 0 else amount
		var tb: Button = _button("한도까지" if amount < 0 else Money.short(amount), 26)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.disabled = a <= 0 or a > limit
		tb.pressed.connect(Economy.take_loan.bind(a))
		take_row.add_child(tb)
	_body.add_child(_label("내 대출", 32, INK))
	if Economy.loans.is_empty():
		_body.add_child(_label("빌린 돈이 없어요.", 26, SOFT))
	for l: Dictionary in Economy.loans:
		var lc: VBoxContainer = _card()
		var product: String = str(l.get("product", ""))
		var kind: String = "주택담보 (%s)" % str(l.get("unit", "")) if str(l.get("kind", "")) == "mortgage" else "신용대출"
		if product == "didimdol":
			kind = "디딤돌대출 (%s)" % str(l.get("unit", ""))
		elif product == "sunshine_youth":
			kind = "햇살론유스"
		var principal: int = int(l.get("principal", 0))
		lc.add_child(_label("%s · %s" % [kind, Money.short(principal)], 30, INK))
		lc.add_child(_label("금리 연 %s (%s) · 주 이자 %s (매주 솔에서 빠져나가요)" % [Money.percent(float(l.get("rate", 0.0))), "고정" if bool(l.get("fixed", false)) else "변동", Money.short(int(l.get("weekly", 0)))], 24, SOFT))
		var rr: HBoxContainer = HBoxContainer.new()
		rr.add_theme_constant_override("separation", 8)
		lc.add_child(rr)
		for part: float in [0.1, 0.5, 1.0]:
			var pay: int = maxi(1, ceili(float(principal) * part))
			var pb: Button = _button("전액 상환" if part >= 1.0 else "%d%% 상환" % roundi(part * 100.0), 26)
			pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pb.disabled = pay > Net.sol
			pb.pressed.connect(Economy.repay_loan.bind(str(l.get("id", "")), pay))
			rr.add_child(pb)


# ---- 자산 ----

func _build_assets() -> void:
	var card: VBoxContainer = _card()
	card.add_child(_label("순자산 %s%s" % [Money.short(Economy.net_worth), (" (%s 님과 한 세대)" % GameData.player_name(Economy.partner)) if Economy.is_married() else ""], 42, INK))
	var homes_value: int = 0
	for id: String in Economy.my_homes():
		var u: EconData.Unit = GameData.econ.unit(id)
		if u != null:
			homes_value += GameData.econ.unit_price(u, Economy.apt_index)
	for row: Array in [["현금(솔)" + (" · 같이 쓰는 지갑" if Economy.is_married() else ""), Net.sol], ["주식 평가액 (내 것)", Economy.stocks_value()], ["아파트 시세", homes_value], ["빚 (세대)", -Economy.debt]]:
		var line: HBoxContainer = HBoxContainer.new()
		card.add_child(line)
		var name_label: Label = _label(str(row[0]), 30, INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(_label(Money.short(int(row[1])), 30, DOWN if int(row[1]) < 0 else INK, false))
	card.add_child(_label("이번 주 번 돈 %s · 연 소득 추정 %s · 신용 %d등급" % [Money.short(Economy.income_week), Money.short(Economy.income_year), Economy.credit_grade], 24, SOFT))
	var homes: PackedStringArray = Economy.my_homes()
	if not homes.is_empty():
		_body.add_child(_label("내 집: %s" % ", ".join(homes), 28, INK))
	if not _week_reports.is_empty():
		_body.add_child(_label("주간 정산", 32, INK))
		for r: Dictionary in _week_reports:
			_body.add_child(_label("%d주차 · 월세 +%s · 이자 -%s%s" % [int(r.get("week", 0)), Money.short(int(r.get("rent", 0))), Money.short(int(r.get("interest", 0))), " · 연체!" if bool(r.get("missed", false)) else ""], 26, DOWN if bool(r.get("missed", false)) else SOFT))
	if not Economy.trades.is_empty():
		_body.add_child(_label("최근 거래", 32, INK))
		var list: Array[Dictionary] = Economy.trades.duplicate()
		list.reverse()
		for t: Dictionary in list:
			var s: StockQuote = Economy.stock(str(t.get("id", "")))
			var buy: bool = str(t.get("side", "")) == "buy"
			_body.add_child(_label("%s %s %d주 @ %s · %s" % [s.display_name if s != null else str(t.get("id", "")), "매수" if buy else "매도", int(t.get("qty", 0)), Money.digits(int(t.get("price", 0))), Money.short(int(t.get("amount", 0)))], 24, UP if buy else DOWN))


# ---- 도우미 ----

# ---- 마을톡 ----

## 지금 화면에 열려 있는 마을톡 대화방 ("" = 마을톡을 보고 있지 않음).
func showing_thread() -> String:
	return _thread if visible and _tab == Tab.TALK else ""

## 대화방 하나를 바로 연다 (알림을 눌렀을 때).
func open_thread(thread: String) -> void:
	_thread = thread
	open(Tab.TALK)


func _update_talk_badge() -> void:
	if _talk_badge == null:
		return
	var n: int = Talk.unread_total()
	_talk_badge.visible = n > 0
	_talk_badge.text = " %d " % n if n < 100 else " 99+ "


func _build_talk() -> void:
	if _thread.is_empty():
		_build_talk_list()
	else:
		_build_talk_room(_thread)


func _build_talk_list() -> void:
	_body.add_child(_label("마을톡 · 친한 주민·은행·친구가 보낸 연락", 26, SOFT))
	var ids: PackedStringArray = Talk.sorted_threads()
	if ids.is_empty():
		_body.add_child(_label("아직 대화가 없어요. 주민과 친해지면 먼저 연락이 와요.", 28, SOFT))
	for th: String in ids:
		var row: Button = _row_button()
		row.custom_minimum_size = Vector2(0, 124)
		var line: HBoxContainer = HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 18)
		row.add_child(line)
		_fill(line)
		line.add_child(_avatar(th, 84.0))
		var text_box: VBoxContainer = VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.alignment = BoxContainer.ALIGNMENT_CENTER
		text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(text_box)
		text_box.add_child(_label(Talk.title(th), 32, INK, false))
		var last: Label = _label(Talk.last_text(th) if not Talk.last_text(th).is_empty() else "대화를 시작해 보세요", 24, SOFT, false)
		last.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		last.clip_text = true
		text_box.add_child(last)
		var side: VBoxContainer = VBoxContainer.new()
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(side)
		side.add_child(_label(_time_text(Talk.last_at(th)), 22, SOFT, false))
		var unread: int = Talk.unread(th)
		if unread > 0:
			var badge: Label = _label(" %d " % unread, 22, Color.WHITE, false)
			badge.add_theme_stylebox_override("normal", EventHud._box(Color("#E0483A"), Color("#B03028"), 16, 0, 6))
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			side.add_child(badge)
		row.pressed.connect(func() -> void:
			_thread = th
			_rebuild())
		_body.add_child(row)


func _build_talk_room(th: String) -> void:
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_body.add_child(top)
	var back: Button = _button("‹ 목록", 28)
	back.pressed.connect(func() -> void:
		_thread = ""
		_rebuild())
	top.add_child(back)
	top.add_child(_avatar(th, 64.0))
	var title: Label = _label(Talk.title(th), 32, INK, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	var list: Array = Talk.threads.get(th, {}).get("m", [])
	if list.is_empty():
		_body.add_child(_label("첫 메시지를 보내 보세요.", 26, SOFT))
	var prev_from: String = ""
	for m: Variant in list:
		var msg: Dictionary = m
		var from: String = str(msg.get("f", ""))
		_body.add_child(_bubble(th, msg, from != prev_from))
		prev_from = from
	if Talk.can_reply(th):
		var input: HBoxContainer = HBoxContainer.new()
		input.add_theme_constant_override("separation", 10)
		_body.add_child(input)
		var edit: LineEdit = LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.custom_minimum_size = Vector2(0, 88)
		edit.placeholder_text = "메시지 보내기"
		edit.max_length = 200
		edit.text = _draft
		edit.add_theme_font_size_override("font_size", 30)
		edit.text_changed.connect(func(t: String) -> void: _draft = t)
		edit.focus_entered.connect(func() -> void: _typing = true)
		edit.focus_exited.connect(func() -> void:
			if edit.is_inside_tree() and not edit.is_queued_for_deletion():
				_typing = false)
		input.add_child(edit)
		if _typing:
			edit.call_deferred("grab_focus")
			edit.caret_column = _draft.length()
		var send: Button = _button("보내기", 30, INK, true)
		var do_send: Callable = func(_t: String = "") -> void:
			if _draft.strip_edges().is_empty():
				return
			Talk.send(th, _draft)
			_draft = ""
			Audio.play_sfx("ui_click", -6.0, 1.3)
		send.pressed.connect(do_send)
		edit.text_submitted.connect(do_send)
		input.add_child(send)
	Talk.mark_read(th)


## 말풍선: 내 것은 오른쪽 노랑, 받은 것은 왼쪽 흰색 (보낸 쪽이 바뀔 때만 이름을 붙인다).
func _bubble(th: String, msg: Dictionary, show_name: bool) -> Control:
	var mine: bool = str(msg.get("f", "")) == "me"
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(140, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN
	if not mine and show_name:
		col.add_child(_label(Talk.sender_name(str(msg.get("f", ""))), 22, SOFT, false))
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", EventHud._box(MINE if mine else THEIRS, Color(0.8, 0.72, 0.6), 22, 1, 16))
	var text: Label = _label(Talk.fill(str(msg.get("tx", ""))), 28, INK)
	text.custom_minimum_size = Vector2(0, 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(text)
	# 긴 글은 화면 폭의 70% 에서 줄바꿈.
	var longest: float = text.get_theme_font("font").get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	panel.custom_minimum_size = Vector2(minf(longest + 40.0, WIDTH * 0.62), 0)
	col.add_child(panel)
	var time: Label = _label(_time_text(float(msg.get("at", 0.0))), 18, SOFT, false)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(time)
	if mine:
		row.add_child(spacer)
		row.add_child(col)
	else:
		row.add_child(_avatar(th if str(msg.get("f", "")) != "me" else "", 56.0))
		row.add_child(col)
		row.add_child(spacer)
	return row


## 동그란 프로필: 대화방 색 + 이름 첫 글자.
func _avatar(th: String, d: float) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(d, d)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var initial: String = Talk.title(th).left(1) if not th.is_empty() else ""
	var color: Color = Talk.color_of(th)
	c.draw.connect(func() -> void:
		c.draw_circle(c.size * 0.5, d * 0.5, color.darkened(0.15))
		c.draw_circle(c.size * 0.5, d * 0.5 - 3.0, color)
		var font: Font = c.get_theme_default_font()
		var fs: int = int(d * 0.45)
		var w: float = font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font, Vector2((d - w) * 0.5, d * 0.5 + fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	return c


## 받은 시각: 오늘이면 "오후 3:05", 아니면 "10/4".
func _time_text(at_ms: float) -> String:
	if at_ms <= 0.0:
		return ""
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(int(at_ms / 1000.0) + _tz_offset_s())
	var today: Dictionary = Time.get_datetime_dict_from_system()
	if int(t["day"]) != int(today["day"]) or int(t["month"]) != int(today["month"]):
		return "%d/%d" % [int(t["month"]), int(t["day"])]
	var h: int = int(t["hour"])
	return "%s %d:%02d" % ["오전" if h < 12 else "오후", (h + 11) % 12 + 1, int(t["minute"])]


static func _tz_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _card() -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(CARD, Color(0.75, 0.66, 0.54), 26, 3, 20))
	_body.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	return col


func _row_button() -> Button:
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 104)
	b.add_theme_stylebox_override("normal", EventHud._box(CARD, Color(0.8, 0.72, 0.6), 22, 2, 16))
	b.add_theme_stylebox_override("hover", EventHud._box(Color(1.0, 0.97, 0.88), Color(0.8, 0.72, 0.6), 22, 2, 16))
	b.add_theme_stylebox_override("pressed", EventHud._box(PICKED, Color(0.8, 0.72, 0.6), 22, 2, 16))
	return b


func _fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 18.0
	c.offset_right = -18.0


func _button(text: String, font_size: int, color: Color = INK, picked: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.35))
	if picked:
		b.add_theme_stylebox_override("normal", EventHud._box(PICKED, EDGE, 22, 3, 10))
	return b


## wrap = 줄바꿈 (오른쪽 숫자 칸처럼 폭이 정해지지 않은 곳은 false — 켜면 글자마다 줄이 바뀐다).
func _label(text: String, font_size: int, color: Color, wrap: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
