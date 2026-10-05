class_name EconomyController
extends Node
## 마을 경제 연결 (v0.8~0.9): HUD 의 휴대폰 단추와 휴대폰 창, 식당 주방 창, 동사무소 창,
## 상황 버튼(식당 열기 · 같이 일하기 · 주방 · 부동산 · 동사무소 창구 셋), 그리고 거래·주간 정산·식당·혼인신고·같이 하기 알림.
## 판정은 서버(Economy)가 하고 여기서는 화면과 연출만 맡는다.

@export var player: Player
@export var apartments: ApartmentSite
@export var restaurant: RestaurantSite
## 동사무소 (v0.9, 없어도 된다).
@export var civic_site: CivicSite
## 휴대폰 단추와 창을 붙일 곳.
@export var hud: CanvasLayer
## 결과 문구 (낚시 HUD 의 토스트).
@export var toast_hud: FishingHud

@export_group("Layout")
@export var phone_button_size: float = 118.0
@export var phone_button_y: float = 1010.0

const TARGET_OPEN: String = "rest_open"
const TARGET_KITCHEN: String = "kitchen"
const TARGET_ESTATE: String = "estate"
const TARGET_JOIN: String = "rest_join"
## 동사무소 창구: "civic:civil" · "civic:welfare" · "civic:finance"
const TARGET_CIVIC: String = "civic:"

var phone: PhoneWindow = null
var kitchen: KitchenWindow = null
var civic: CivicWindow = null
var _phone_button: Button = null
## 이번 영업에 주방 창을 저절로 한 번 열었는지.
var _kitchen_opened_for_shift: bool = false
var _join_pending: bool = false


func _ready() -> void:
	phone = PhoneWindow.new()
	phone.name = "PhoneWindow"
	kitchen = KitchenWindow.new()
	kitchen.name = "KitchenWindow"
	kitchen.player = player
	kitchen.site = restaurant
	civic = CivicWindow.new()
	civic.name = "CivicWindow"
	_phone_button = Button.new()
	_phone_button.name = "PhoneButton"
	_phone_button.tooltip_text = "휴대폰"
	_phone_button.focus_mode = Control.FOCUS_NONE
	_phone_button.add_theme_stylebox_override("normal", EventHud._box(Color(0.98, 0.95, 0.88, 0.96), Color(0.36, 0.3, 0.28), 59, 5, 8))
	_phone_button.add_theme_stylebox_override("hover", EventHud._box(Color(1.0, 0.98, 0.92), Color(0.36, 0.3, 0.28), 59, 5, 8))
	_phone_button.add_theme_stylebox_override("pressed", EventHud._box(Color(0.98, 0.84, 0.55), Color(0.36, 0.3, 0.28), 59, 5, 8))
	_phone_button.add_to_group(&"blocks_joystick")
	_phone_button.pressed.connect(func() -> void: phone.open())
	_phone_button.draw.connect(_draw_phone_icon)
	_phone_button.text = ""
	HudLayout.right_top(_phone_button, Vector2(phone_button_size, phone_button_size), 24.0, phone_button_y)
	if hud != null:
		hud.add_child.call_deferred(_phone_button)
		hud.add_child.call_deferred(kitchen)
		hud.add_child.call_deferred(civic)
		hud.add_child.call_deferred(phone)
	Talk.received.connect(_on_talk_received)
	Talk.changed.connect(func() -> void:
		if _phone_button != null:
			_phone_button.queue_redraw())
	Economy.trade_done.connect(_on_trade)
	Economy.apt_done.connect(_on_apt)
	Economy.loan_done.connect(_on_loan)
	Economy.deposit_done.connect(_on_deposit)
	Economy.week_passed.connect(_on_week)
	Economy.failed.connect(_on_failed)
	Economy.shift_closed.connect(_on_shift_closed)
	Economy.restaurant_changed.connect(_on_restaurant_changed)
	Economy.served.connect(func(info: Dictionary) -> void:
		if bool(info.get("became", false)):
			toast_hud.show_toast("%s 님이 %s 단골이 됐어요! (그 메뉴만 시켜요)" % [_customer_name(str(info.get("customer", ""))), _dish_name(str(info.get("dish", "")))], true)
		elif bool(info.get("lost", false)):
			toast_hud.show_toast("%s 님이 더는 단골이 아니에요…" % _customer_name(str(info.get("customer", ""))), false))
	Economy.marry_proposed.connect(func(from_id: int) -> void: civic.ask_proposal(from_id))
	Economy.marry_declined.connect(func(_by: int) -> void: toast_hud.show_toast("다음에 하기로 했대요.", false))
	Economy.household_formed.connect(func(info: Dictionary) -> void:
		if Net.my_id in Array(info.get("members", [])).map(func(x: Variant) -> int: return int(x)):
			Audio.play_sfx("fanfare_big", -4.0)
			toast_hud.show_toast("혼인신고 완료! 이제 솔을 같이 써요 (%s)" % Money.short(int(info.get("sol", 0))), true))
	Economy.staff_changed.connect(func(id: int, joined: bool) -> void:
		if id != Net.my_id and (Economy.is_rest_staff() or Economy.is_rest_owner()):
			toast_hud.show_toast("%s 님이 %s" % [GameData.player_name(id), "같이 일해요! 재료를 합치고 요리를 나눠요 (팀 보너스)" if joined else "일을 그만뒀어요"], joined))
	Economy.coop_bonus.connect(func(info: Dictionary) -> void:
		toast_hud.show_toast("같이 해서 %s 하나 더! (%s 님과)" % [GameData.item_name(str(info.get("item", ""))), GameData.player_name(int(info.get("with", 0)))], true))
	Net.message_received.connect(_on_coop_message)
	Economy.customer_left.connect(func(info: Dictionary) -> void:
		if Economy.is_rest_owner() or int(Economy.rest.get("owner", 0)) == Net.my_id:
			toast_hud.show_toast("%s 님이 기다리다 떠났어요 (★1)" % _customer_name(str(info.get("customer", ""))), false))


## 휴대폰·주방·동사무소 창이 열려 있는지 (열려 있으면 다른 상황 버튼을 숨긴다).
func is_busy() -> bool:
	return (phone != null and phone.is_open()) or (kitchen != null and kitchen.is_open()) or (civic != null and civic.is_open())


## 지금 position 에서 할 수 있는 경제 행동 (InteractionController 가 묻는다). 없으면 빈 문자열.
func pick_target(position: Vector3, max_distance: float) -> String:
	if restaurant != null and restaurant.near_counter(position, max_distance):
		if not bool(Economy.rest.get("open", false)):
			return TARGET_OPEN
		if Economy.is_rest_staff():
			return TARGET_KITCHEN
		return TARGET_JOIN
	if civic_site != null:
		var desk: String = civic_site.nearest_desk(position, max_distance)
		if not desk.is_empty():
			return TARGET_CIVIC + desk
	if apartments != null and apartments.near_office(position, max_distance):
		return TARGET_ESTATE
	return ""


func target_label(target: String) -> String:
	match target:
		TARGET_OPEN:
			return "식당 열기"
		TARGET_KITCHEN:
			return "주방"
		TARGET_ESTATE:
			return "부동산"
		TARGET_JOIN:
			return "같이 일하기"
	if target.begins_with(TARGET_CIVIC):
		return str(GameData.econ.staff_of(target.trim_prefix(TARGET_CIVIC)).get("desk_name", "창구"))
	return ""


func activate(target: String) -> void:
	match target:
		TARGET_OPEN:
			Economy.open_restaurant()
		TARGET_KITCHEN:
			kitchen.open()
		TARGET_ESTATE:
			phone.open(PhoneWindow.Tab.HOMES)
		TARGET_JOIN:
			Economy.join_restaurant()
			_join_pending = true
		_:
			if target.begins_with(TARGET_CIVIC):
				var desk: String = target.trim_prefix(TARGET_CIVIC)
				if civic_site != null and civic_site.staff_actor(desk) != null:
					civic_site.staff_actor(desk).play_emote("hello")
				civic.open(desk)


func _on_restaurant_changed() -> void:
	# 같이 일하기를 눌렀으면 주방 창을 바로 연다.
	if _join_pending and Economy.is_rest_staff() and not kitchen.is_open():
		_join_pending = false
		kitchen.open()
		toast_hud.show_toast("같이 일해요! 재료를 합치고, 요리 동작을 나눠 동시에 해요.", true)
	# 내가 문을 열었으면 주방 창을 바로 연다.
	if Economy.is_rest_owner() and not kitchen.is_open() and restaurant != null and player != null and restaurant.near_counter(player.global_position, 4.0) and not _kitchen_opened_for_shift:
		_kitchen_opened_for_shift = true
		kitchen.open()
		toast_hud.show_toast("식당 문을 열었어요! 가방 재료로 만들 수 있는 요리만 주문이 들어와요.", true)
	if not bool(Economy.rest.get("open", false)):
		_kitchen_opened_for_shift = false



## 같이 베기 · 같이 낚시 같은 덤을 알린다.
func _on_coop_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"chop_result":
			if bool(msg.get("coop", false)):
				toast_hud.show_toast("같이 베니까 두 배로 찍혀요!" + (" 쓰러뜨려서 하나씩 더!" if bool(msg.get("felled", false)) else ""), true)
		"fish_started":
			if bool(msg.get("coop", false)):
				toast_hud.show_toast("같이 낚시: 입질이 빨라지고 귀한 물고기가 잘 와요.", true)


func _on_shift_closed(reason: String) -> void:
	if int(Economy.rest.get("owner", 0)) != Net.my_id and not kitchen.is_open():
		return
	var text: String = {"closed": "식당 문을 닫았어요.", "owner_left": "주인이 떠나 식당 문을 닫았어요.", "idle": "손님이 없어 식당 문을 닫았어요.", "no_ingredients": "재료가 다 떨어져 문을 닫았어요."}.get(reason, "식당 문을 닫았어요.")
	toast_hud.show_toast(text, reason == "closed")


func _on_trade(r: Dictionary) -> void:
	var s: StockQuote = Economy.stock(str(r.get("id", "")))
	var buy: bool = str(r.get("side", "")) == "buy"
	Audio.play_sfx("cash_in" if not buy else "coin", -4.0)
	toast_hud.show_toast("%s %d주 %s 체결 · %s" % [s.display_name if s != null else str(r.get("id", "")), int(r.get("qty", 0)), "매수" if buy else "매도", Money.short(int(r.get("amount", 0)))], true)


func _on_apt(r: Dictionary) -> void:
	Audio.play_sfx("fanfare_small" if str(r.get("kind", "")) == "buy" else "cash_in", -4.0)
	if str(r.get("kind", "")) == "buy":
		toast_hud.show_toast("%s 를 샀어요! 세를 놓아 매주 월세가 들어와요." % str(r.get("unit", "")), true)
	else:
		toast_hud.show_toast("%s 를 팔았어요 (대출 상환 %s)" % [str(r.get("unit", "")), Money.short(int(r.get("repaid", 0)))], true)


func _on_loan(r: Dictionary) -> void:
	Audio.play_sfx("coin", -4.0)
	if str(r.get("kind", "")) == "take":
		var loan: Dictionary = r.get("loan", {})
		toast_hud.show_toast("%s 빌렸어요 · 연 %s · 주 이자 %s" % [Money.short(int(loan.get("principal", 0))), Money.percent(float(loan.get("rate", 0.0))), Money.short(int(loan.get("weekly", 0)))], true)
	else:
		toast_hud.show_toast("%s 갚았어요 · 남은 빚 %s" % [Money.short(int(r.get("paid", 0))), Money.short(int(r.get("left", 0)))], true)


func _on_deposit(r: Dictionary) -> void:
	Audio.play_sfx("coin", -4.0)
	match str(r.get("kind", "")):
		"dep_open":
			var fee: int = int(r.get("fee", 0))
			toast_hud.show_toast("가입했어요!" + (" (출자금 %s · 이제 조합원)" % Money.short(fee) if fee > 0 else ""), true)
		"dep_close":
			var gain: int = int(r.get("gross", 0)) - int(r.get("tax", 0))
			toast_hud.show_toast("%s · %s 받았어요 (이자 %s, 세금 %s 뺌)" % ["중도해지" if bool(r.get("early", false)) else "만기 해지", Money.short(int(r.get("net", 0))), Money.short(gain), Money.short(int(r.get("tax", 0)))], not bool(r.get("early", false)))
		_:
			toast_hud.show_toast("파킹통장 잔액 %s" % Money.short(int(r.get("balance", 0))), true)


func _on_week(r: Dictionary) -> void:
	var parts: PackedStringArray = []
	if int(r.get("rent", 0)) > 0:
		parts.append("월세 +%s" % Money.short(int(r.get("rent", 0))))
	if int(r.get("interest", 0)) > 0:
		parts.append("이자 -%s" % Money.short(int(r.get("interest", 0))))
	if bool(r.get("missed", false)):
		parts.append("연체! 남은 이자 %s 가 원금에 붙었어요" % Money.short(int(r.get("capitalized", 0))))
	for m: Dictionary in r.get("matured", []):
		parts.append("%s 만기 +%s" % [str(m.get("name", "")), Money.short(int(m.get("net", 0)))])
	parts.append("기준금리 %s" % Money.percent(float(r.get("base", 0.0))))
	toast_hud.show_toast("한 주 정산 · " + " · ".join(parts), not bool(r.get("missed", false)))


func _on_failed(kind: String, code: String) -> void:
	var text: String = {
		NetProtocol.ERR_NOT_ENOUGH_SOL: "솔이 모자라요.",
		NetProtocol.ERR_MARKET_CLOSED: "장이 닫혔어요 (평일 9:00~15:30).",
		NetProtocol.ERR_NOT_ENOUGH_SHARES: "가진 주식보다 많이 팔 수 없어요.",
		NetProtocol.ERR_BAD_ORDER: "주문이 이상해요.",
		NetProtocol.ERR_UNIT_TAKEN: "이미 누가 산 집이에요.",
		NetProtocol.ERR_NOT_YOUR_UNIT: "내 집이 아니에요.",
		NetProtocol.ERR_LOAN_LIMIT: "대출 한도를 넘어요 (LTV·DSR·신용 한도).",
		NetProtocol.ERR_BAD_LOAN: "대출 금액이 이상해요.",
		NetProtocol.ERR_BAD_PRODUCT: "상품·기간·금액을 다시 골라요.",
		NetProtocol.ERR_BAD_ACCOUNT: "없는 계좌예요.",
		NetProtocol.ERR_ACCOUNT_LIMIT: "예적금은 8개까지 들 수 있어요.",
		NetProtocol.ERR_NOT_ELIGIBLE: "가입 조건이 안 돼요.",
		NetProtocol.ERR_REST_BUSY: "다른 사람이 식당을 열었어요.",
		NetProtocol.ERR_NOT_AT_RESTAURANT: "식당 카운터에서 열 수 있어요.",
		NetProtocol.ERR_REST_CLOSED: "식당이 닫혀 있어요.",
	}.get(code, "")
	if kind == "rest_serve" or text.is_empty():
		return
	toast_hud.show_toast(text, false)


func _customer_name(id: String) -> String:
	var c: EconData.Customer = GameData.econ.customers.get(id)
	return c.display_name if c != null else id


func _dish_name(id: String) -> String:
	var r: RecipeInfo = GameData.econ.recipes.get(id)
	return r.display_name if r != null else id


## 휴대폰 그림 (그림 파일 없이): 둥근 몸체 + 화면 + 작은 그래프.
## 마을톡 새 메시지: 짧은 진동 + 알림 (그 대화방을 보고 있으면 조용히).
func _on_talk_received(thread: String, message: Dictionary) -> void:
	if str(message.get("f", "")) == "me":
		return
	if phone.showing_thread() == thread:
		return
	Input.vibrate_handheld(60, 0.4)
	Audio.play_sfx("emote_pop", -6.0, 1.2)
	var text: String = Talk.fill(str(message.get("tx", "")))
	toast_hud.show_toast("[마을톡] %s: %s" % [Talk.sender_name(str(message.get("f", ""))), text.left(28) + ("…" if text.length() > 28 else "")], true)


func _draw_phone_icon() -> void:
	var s: Vector2 = _phone_button.size
	var body: Rect2 = Rect2(s * Vector2(0.3, 0.16), s * Vector2(0.4, 0.68))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("#3E4650")
	box.set_corner_radius_all(int(s.x * 0.08))
	_phone_button.draw_style_box(box, body)
	var screen: Rect2 = body.grow(-s.x * 0.04)
	screen.size.y -= s.y * 0.06
	_phone_button.draw_rect(screen, Color("#BFE6F2"))
	var pts: PackedVector2Array = []
	for i: int in 5:
		pts.append(screen.position + Vector2(screen.size.x * (0.1 + 0.2 * i), screen.size.y * [0.75, 0.55, 0.62, 0.35, 0.25][i]))
	_phone_button.draw_polyline(pts, Color("#E0483A"), 3.0, true)
	_phone_button.draw_circle(Vector2(body.get_center().x, body.end.y - s.y * 0.045), s.x * 0.025, Color("#8A96A2"))
	# 마을톡 안 읽은 메시지 수 (빨간 동그라미).
	var unread: int = Talk.unread_total()
	if unread > 0:
		var at: Vector2 = Vector2(s.x * 0.8, s.y * 0.2)
		_phone_button.draw_circle(at, s.x * 0.17, Color("#E0483A"))
		var font: Font = _phone_button.get_theme_default_font()
		var label: String = str(unread) if unread < 10 else "9+"
		var fs: int = int(s.x * 0.2)
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_phone_button.draw_string(font, at + Vector2(-w * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
