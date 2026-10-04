extends Node
## 마을 경제 상태 (v8) — 서버가 보낸 값만 들고 있다: 증권 시세와 내 주식, 아파트 주인, 은행(신용·금리·대출), 식당 영업.
## Net.message_received 로 경제 메시지를 받고, 요청은 Net.request 로 보낸다. 판정은 전부 서버가 한다.

signal market_changed
## 내 주식·거래·대출·신용·소득·순자산 (profile 메시지).
signal portfolio_changed
signal homes_changed
signal bank_changed
## 한 주가 지났다: { week, rent, interest, capitalized, missed, base, index, sol }
signal week_passed(report: Dictionary)
signal restaurant_changed
## 손님이 앉아 주문했다: { order, customer, dish, seat, regular }
signal order_arrived(order: Dictionary)
## 누가 요리를 냈다: { order, customer, dish, stars, pay, regular, became, lost, by }
signal served(info: Dictionary)
## 손님이 떠났다 (늦음 / 재료가 사라짐): { order, customer, dish, reason, lost }
signal customer_left(info: Dictionary)
signal shift_closed(reason: String)
## 내가 낸 요리의 판정: { order, stars, pay, quality, taste, sol }
signal cook_judged(result: Dictionary)
signal trade_done(result: Dictionary)
signal apt_done(result: Dictionary)
signal loan_done(result: Dictionary)
## 경제 요청이 거절됐다 (kind = 보낸 메시지 종류, code = 서버 에러 코드).
signal failed(kind: String, code: String)

const KINDS: PackedStringArray = ["stock_order", "apt_buy", "apt_sell", "loan_take", "loan_repay", "rest_open", "rest_close", "rest_serve"]

var market_open: bool = true
var market_source: String = "sim"
var market_minute: int = 0
var fee_rate: float = 0.00015
var tax_rate: float = 0.0018
var stocks: Array[StockQuote] = []
## 종목 → { q: 수량, cost: 산 돈 합계 }
var holdings: Dictionary[String, Dictionary] = {}
var trades: Array[Dictionary] = []
## [{ id, kind, principal, rate, unit, since, weekly }]
var loans: Array[Dictionary] = []
var credit_score: int = 0
var credit_grade: int = 5
var income_week: int = 0
var income_year: int = 0
var assets: int = 0
var debt: int = 0
var net_worth: int = 0

## 마을 집값 지수 (1.0 = 처음 시세).
var apt_index: float = 1.0
## 호수 → 주인 자리 번호 (0 = 다른 마을 사람이었다가 떠남).
var home_owners: Dictionary[String, int] = {}
## 호수 → 산 값.
var home_bought: Dictionary[String, int] = {}

## 은행 창구 정보 (bank_quote 의 답): base, score, grade, rate_credit, rate_mortgage, credit_limit, ltv, dsr, income_year, week, loans
var bank: Dictionary = {}

## 식당: open, owner, rating, tier, served, revenue, regulars{손님: 요리}, capacity, shift{served, revenue}
var rest: Dictionary = {"open": false, "owner": 0, "rating": 2.0, "tier": 1, "served": 0, "revenue": 0, "regulars": {}, "capacity": 0}
## 지금 앉아 있는 손님 주문 (id → { id, customer, dish, seat, deadline_ms, patience, cooking, regular }).
var orders: Dictionary[String, Dictionary] = {}


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind in KINDS:
			failed.emit(kind, code))


func stock(id: String) -> StockQuote:
	for s: StockQuote in stocks:
		if s.id == id:
			return s
	return null


func holding_qty(id: String) -> int:
	return int(holdings.get(id, {}).get("q", 0))


## 주식 평가액 합계.
func stocks_value() -> int:
	var total: int = 0
	for id: String in holdings:
		var s: StockQuote = stock(id)
		if s != null:
			total += s.price * int(holdings[id].get("q", 0))
	return total


## 내 집 목록 (호수).
func my_homes() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in home_owners:
		if home_owners[id] == Net.my_id:
			out.append(id)
	return out


func is_rest_owner() -> bool:
	return bool(rest.get("open", false)) and int(rest.get("owner", 0)) == Net.my_id


func order_left_ms(order: Dictionary) -> float:
	return maxf(0.0, float(order.get("deadline_ms", 0.0)) - float(Time.get_ticks_msec()))


# ---- 요청 ----

func order_stock(id: String, side: String, qty: int) -> void:
	Net.request("stock_order", {"id": id, "side": side, "qty": qty})


func buy_home(unit_id: String, loan: int) -> void:
	Net.request("apt_buy", {"unit": unit_id, "loan": loan})


func sell_home(unit_id: String) -> void:
	Net.request("apt_sell", {"unit": unit_id})


func ask_bank() -> void:
	Net.send_message({"t": "bank_quote"})


func take_loan(amount: int) -> void:
	Net.request("loan_take", {"amount": amount})


func repay_loan(loan_id: String, amount: int) -> void:
	Net.request("loan_repay", {"id": loan_id, "amount": amount})


func open_restaurant() -> void:
	Net.request("rest_open")


func close_restaurant() -> void:
	Net.request("rest_close")


## 이 주문을 요리하기 시작했다 (서버가 시작 시각을 잰다 — 너무 빨리 낸 요리는 받지 않는다).
func start_cooking(order_id: String) -> void:
	Net.send_message({"t": "rest_cook", "order": order_id})


## 요리를 낸다. taps[i] = i 번째 동작을 시작하고 누른 시각들 (ms).
func serve(order_id: String, taps: Array) -> void:
	Net.request("rest_serve", {"order": order_id, "taps": taps})


# ---- 받기 ----

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			_apply_market(msg.get("market", {}))
			_apply_profile(msg.get("prof", {}))
			_apply_homes(msg.get("homes", {}))
			_apply_rest(msg.get("rest", {}))
		"profile":
			_apply_profile(msg)
		"market_tick":
			market_open = bool(msg.get("open", market_open))
			market_source = str(msg.get("source", market_source))
			market_minute = int(msg.get("minute", market_minute))
			var q: Variant = msg.get("q", {})
			if q is Dictionary:
				for id: Variant in q:
					var s: StockQuote = stock(str(id))
					if s != null:
						s.price = int(q[id])
						s.hist.append(s.price)
						if s.hist.size() > 240:
							s.hist = s.hist.slice(s.hist.size() - 240)
			market_changed.emit()
		"stock_result":
			trade_done.emit(msg)
		"homes":
			_apply_homes(msg)
		"apt_result":
			apt_done.emit(msg)
		"bank":
			bank = msg
			bank_changed.emit()
		"loan_result":
			loan_done.emit(msg)
		"week":
			apt_index = float(msg.get("index", apt_index))
			week_passed.emit(msg)
		"rest":
			_apply_rest(msg)
		"rest_order":
			order_arrived.emit(msg)
		"rest_served":
			served.emit(msg)
		"rest_left":
			customer_left.emit(msg)
		"rest_closed":
			shift_closed.emit(str(msg.get("reason", "")))
		"rest_result":
			cook_judged.emit(msg)


func _apply_market(data: Variant) -> void:
	if not data is Dictionary:
		return
	market_open = bool(data.get("open", true))
	market_source = str(data.get("source", "sim"))
	market_minute = int(data.get("minute", 0))
	fee_rate = float(data.get("fee", fee_rate))
	tax_rate = float(data.get("tax", tax_rate))
	stocks.clear()
	for entry: Variant in data.get("stocks", []):
		if not entry is Dictionary:
			continue
		var s: StockQuote = StockQuote.new()
		s.id = str(entry.get("id", ""))
		s.display_name = str(entry.get("name", s.id))
		s.sector = str(entry.get("sector", ""))
		s.about = str(entry.get("about", ""))
		s.price = int(entry.get("price", 0))
		s.ref = int(entry.get("ref", s.price))
		for p: Variant in entry.get("hist", []):
			s.hist.append(int(p))
		stocks.append(s)
	market_changed.emit()


func _apply_profile(data: Variant) -> void:
	if not data is Dictionary or not data.has("stocks"):
		return
	holdings.clear()
	var h: Variant = data.get("stocks", {})
	if h is Dictionary:
		for id: Variant in h:
			holdings[str(id)] = h[id]
	trades.clear()
	for t: Variant in data.get("trades", []):
		if t is Dictionary:
			trades.append(t)
	loans.clear()
	for l: Variant in data.get("loans", []):
		if l is Dictionary:
			loans.append(l)
	var c: Dictionary = data.get("credit", {})
	credit_score = int(c.get("score", credit_score))
	credit_grade = int(c.get("grade", credit_grade))
	var inc: Dictionary = data.get("income", {})
	income_week = int(inc.get("week", 0))
	income_year = int(inc.get("year", 0))
	var w: Dictionary = data.get("worth", {})
	assets = int(w.get("assets", 0))
	debt = int(w.get("debt", 0))
	net_worth = int(w.get("net", 0))
	portfolio_changed.emit()


func _apply_homes(data: Variant) -> void:
	if not data is Dictionary or not data.has("index"):
		return
	apt_index = float(data.get("index", apt_index))
	home_owners.clear()
	home_bought.clear()
	var o: Variant = data.get("owners", {})
	if o is Dictionary:
		for id: Variant in o:
			home_owners[str(id)] = int(o[id])
	var b: Variant = data.get("bought", {})
	if b is Dictionary:
		for id: Variant in b:
			home_bought[str(id)] = int(b[id])
	homes_changed.emit()


func _apply_rest(data: Variant) -> void:
	if not data is Dictionary or not data.has("open"):
		return
	rest = data
	var now: float = float(Time.get_ticks_msec())
	var seen: Dictionary[String, bool] = {}
	for entry: Variant in data.get("orders", []):
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		seen[id] = true
		var o: Dictionary = orders.get(id, {})
		o["id"] = id
		o["customer"] = str(entry.get("customer", ""))
		o["dish"] = str(entry.get("dish", ""))
		o["seat"] = int(entry.get("seat", 0))
		o["patience"] = float(entry.get("patience", 1.0))
		o["deadline_ms"] = now + float(entry.get("left", 0.0))
		o["cooking"] = bool(entry.get("cooking", false))
		o["regular"] = bool(entry.get("regular", false))
		orders[id] = o
	for id: String in orders.keys():
		if not seen.has(id):
			orders.erase(id)
	restaurant_changed.emit()
