extends Node
## 마을 경제 상태 (v8~v9) — 서버가 보낸 값만 들고 있다: 증권 시세와 내 주식, 아파트 주인, 은행(신용·금리·대출), 식당 영업,
## 동사무소(전입·지원금·정책대출 자격)와 혼인한 세대(지갑을 같이 쓴다).
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
## 예적금 가입 · 해지 · 파킹통장 넣고 빼기 결과 (dep_result: kind, id, product, net, gross, tax, early, got, fee, balance, sol).
signal deposit_done(result: Dictionary)
## 일거리 (v0.12): 하던 배달이 바뀜 (Economy.job) · 배달 끝 (job_result: pay, tip, bonus, total, onTime, with, helper, npc).
signal job_changed
signal job_done(result: Dictionary)
## 경제 요청이 거절됐다 (kind = 보낸 메시지 종류, code = 서버 에러 코드).
signal failed(kind: String, code: String)
## 요리 동작을 맡았다 / 다 했다 (v9 같이 요리).
signal step_claimed(order_id: String, step: int)
signal step_done(order_id: String, step: int)
## 식당 직원이 들어오고 나갔다 (id, joined).
signal staff_changed(player_id: int, joined: bool)
## 같이 해서 받은 덤 { kind, item, n, with }.
signal coop_bonus(info: Dictionary)
## 동사무소 정보가 바뀌었다 (civic 메시지).
signal civic_changed
## 동사무소 일 처리 결과 (civic_result).
signal civic_done(result: Dictionary)
## 혼인신고: 상대가 신청했다 / 거절했다 / 세대가 생겼다.
signal marry_proposed(from_id: int)
signal marry_declined(by_id: int)
signal household_formed(info: Dictionary)

const KINDS: PackedStringArray = ["stock_order", "apt_buy", "apt_sell", "apt_lease", "loan_take", "loan_repay", "dep_open", "dep_close", "park_move", "job_take", "job_pick", "job_drop", "rest_open", "rest_join", "rest_close", "rest_cook", "rest_step",
	"civic_civil", "civic_apply", "marry_propose", "marry_answer"]

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
## 호수 → 전세 { kind, deposit, until(주) } (v0.12, 없으면 월세).
var home_leases: Dictionary[String, Dictionary] = {}
## 지금 마을 주 번호와 전세 규칙 { ratio, weeks } (homes 메시지).
var home_week: int = 0
var jeonse_rules: Dictionary = {}

## 은행 창구 정보 (bank_quote 의 답): base, score, grade, rate_credit, rate_mortgage, credit_limit, ltv, dsr, income_year, week, loans
var bank: Dictionary = {}

## 일거리: { done, max, kinds[{id, name, about}], job: { kind, name, item, stage(pickup|carry), from{id,name,x,z}, to{npc,name,x,z}, pay, tip, dist, limit_s, left_ms } 또는 null }
var jobs: Dictionary = {}
## 지금 배달의 마감 (Time.get_ticks_msec 기준, 0 = 아직 물건을 안 받음).
var job_due_ms: float = 0.0

## 식당: open, owner, rating, tier, served, revenue, regulars{손님: 요리}, capacity, shift{served, revenue}
var rest: Dictionary = {"open": false, "owner": 0, "rating": 2.0, "tier": 1, "served": 0, "revenue": 0, "regulars": {}, "capacity": 0}
## 지금 앉아 있는 손님 주문 (id → { id, customer, dish, seat, deadline_ms, patience, cooking, regular, steps: [[맡은 자리, 끝났으면 1]] }).
var orders: Dictionary[String, Dictionary] = {}

## 동사무소 (civic 메시지): resident, movedIn, age, married, partner, income_year, homes, card, approvals, programs[{id, ok, reasons, terms, got}]
var civic: Dictionary = {}
## 혼인한 상대 자리 번호 (0 = 혼자), 나이, 전입, 천안사랑카드, 정책대출 승인 (profile.civ).
var partner: int = 0
var age: int = 29
var resident: bool = false
var has_card: bool = false
var approvals: Dictionary = {}


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


## 식당 직원인지 (주인 포함).
func is_rest_staff() -> bool:
	return bool(rest.get("open", false)) and Net.my_id in Array(rest.get("staff", [])).map(func(x: Variant) -> int: return int(x))


## 직원이 둘 이상이라 팀 보너스가 붙는지.
func is_team() -> bool:
	return bool(rest.get("team", false))


func is_married() -> bool:
	return partner > 0


## 정책 하나의 자격·조건 (civic.programs 에서).
func program(id: String) -> Dictionary:
	for p: Variant in civic.get("programs", []):
		if p is Dictionary and str(p.get("id", "")) == id:
			return p
	return {}


func order_left_ms(order: Dictionary) -> float:
	return maxf(0.0, float(order.get("deadline_ms", 0.0)) - float(Time.get_ticks_msec()))


# ---- 요청 ----

func order_stock(id: String, side: String, qty: int) -> void:
	Net.request("stock_order", {"id": id, "side": side, "qty": qty})


func buy_home(unit_id: String, loan: int, policy: String = "") -> void:
	var fields: Dictionary = {"unit": unit_id, "loan": loan}
	if not policy.is_empty():
		fields["policy"] = policy
	Net.request("apt_buy", fields)


func sell_home(unit_id: String) -> void:
	Net.request("apt_sell", {"unit": unit_id})


## 임대 방식: "jeonse" (보증금을 받고 전세로) · "rent" (보증금을 돌려주고 월세로).
func lease_home(unit_id: String, kind: String) -> void:
	Net.request("apt_lease", {"unit": unit_id, "kind": kind})


func ask_bank() -> void:
	Net.send_message({"t": "bank_quote"})


func take_loan(amount: int, product: String = "") -> void:
	var fields: Dictionary = {"amount": amount}
	if not product.is_empty():
		fields["product"] = product
	Net.request("loan_take", fields)


func repay_loan(loan_id: String, amount: int) -> void:
	Net.request("loan_repay", {"id": loan_id, "amount": amount})


## 예적금 가입 (적금은 amount 가 한 주에 넣는 돈).
func open_deposit(product: String, weeks: int, amount: int) -> void:
	Net.request("dep_open", {"product": product, "weeks": weeks, "amount": amount})


func close_deposit(account_id: String) -> void:
	Net.request("dep_close", {"id": account_id})


## 파킹통장: amount > 0 넣기, < 0 빼기.
func park_move(amount: int) -> void:
	Net.request("park_move", {"amount": amount})


func ask_jobs() -> void:
	Net.send_message({"t": "job_info"})


## kind = "" 이면 서버가 골라 준다.
func take_job(kind: String = "") -> void:
	Net.request("job_take", {"kind": kind} if not kind.is_empty() else {})


func pick_job() -> void:
	Net.request("job_pick")


func drop_job() -> void:
	Net.request("job_drop")


func quit_job() -> void:
	Net.send_message({"t": "job_quit"})


## 하던 배달 (없으면 빈 Dictionary).
func job() -> Dictionary:
	var j: Variant = jobs.get("job")
	return j if j is Dictionary else {}


## 배달 물건을 들고 있으면 그 물건 id (손에 든 것으로 보인다).
func carry_item() -> String:
	var j: Dictionary = job()
	return str(j.get("item", "")) if str(j.get("stage", "")) == "carry" else ""


func open_restaurant() -> void:
	Net.request("rest_open")


func close_restaurant() -> void:
	Net.request("rest_close")


## 열린 식당에 직원으로 들어간다 (같이 일하기).
func join_restaurant() -> void:
	Net.request("rest_join")


## 요리 동작 하나를 맡는다 (서버가 시작 시각을 잰다 — 너무 빨리 끝낸 동작은 받지 않는다).
func claim_step(order_id: String, step: int) -> void:
	Net.request("rest_cook", {"order": order_id, "step": step})


## 맡은 동작을 끝냈다. taps = 동작을 시작하고 누른 시각들 (ms). 마지막 동작이 들어오면 서버가 판정한다.
func finish_step(order_id: String, step: int, taps: Array) -> void:
	Net.request("rest_step", {"order": order_id, "step": step, "taps": taps})


## 아직 아무도 안 맡은 첫 동작 (없으면 -1).
func free_step(order_id: String) -> int:
	var o: Dictionary = orders.get(order_id, {})
	var list: Array = o.get("steps", [])
	for i: int in list.size():
		var st: Array = list[i]
		if int(st[0]) == 0 and int(st[1]) == 0:
			return i
	return -1


# ---- 동사무소 ----

func ask_civic() -> void:
	Net.send_message({"t": "civic_info"})


func civil_service(service: String) -> void:
	Net.request("civic_civil", {"service": service})


func apply_program(program_id: String) -> void:
	Net.request("civic_apply", {"program": program_id})


func propose_marriage(to_id: int) -> void:
	Net.request("marry_propose", {"to": to_id})


func answer_marriage(accept: bool) -> void:
	Net.request("marry_answer", {"accept": accept})


# ---- 받기 ----

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			_apply_market(msg.get("market", {}))
			_apply_profile(msg.get("prof", {}))
			_apply_homes(msg.get("homes", {}))
			_apply_rest(msg.get("rest", {}))
			if msg.get("civic") is Dictionary:
				civic = msg["civic"]
				civic_changed.emit()
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
		"dep_result":
			deposit_done.emit(msg)
		"job":
			jobs = msg
			var j: Dictionary = job()
			job_due_ms = Time.get_ticks_msec() + float(j.get("left_ms", 0)) if str(j.get("stage", "")) == "carry" else 0.0
			job_changed.emit()
		"job_result":
			job_done.emit(msg)
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
		"rest_claim":
			step_claimed.emit(str(msg.get("order", "")), int(msg.get("step", 0)))
		"rest_stepped":
			step_done.emit(str(msg.get("order", "")), int(msg.get("step", 0)))
		"rest_staff":
			staff_changed.emit(int(msg.get("id", 0)), bool(msg.get("joined", false)))
		"coop_bonus":
			coop_bonus.emit(msg)
		"civic":
			civic = msg
			civic_changed.emit()
		"civic_result":
			civic_done.emit(msg)
		"marry_proposal":
			marry_proposed.emit(int(msg.get("from", 0)))
		"marry_declined":
			marry_declined.emit(int(msg.get("by", 0)))
		"household":
			household_formed.emit(msg)


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
	var civ: Dictionary = data.get("civ", {})
	partner = int(civ.get("partner", 0))
	age = int(civ.get("age", age))
	resident = bool(civ.get("resident", false))
	has_card = bool(civ.get("card", false))
	approvals = civ.get("approvals", {}) if civ.get("approvals") is Dictionary else {}
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
	home_leases.clear()
	var ls: Variant = data.get("leases", {})
	if ls is Dictionary:
		for id: Variant in ls:
			if ls[id] is Dictionary:
				home_leases[str(id)] = ls[id]
	home_week = int(data.get("week", home_week))
	var jr: Variant = data.get("jeonse")
	if jr is Dictionary:
		jeonse_rules = jr
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
		o["steps"] = entry.get("steps", [])
		orders[id] = o
	for id: String in orders.keys():
		if not seen.has(id):
			orders.erase(id)
	restaurant_changed.emit()
