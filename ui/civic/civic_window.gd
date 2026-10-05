class_name CivicWindow
extends Control
## 동사무소 창구 창: 민원(전입신고 · 등본 · 가족관계증명서 · 천안사랑카드 · 혼인신고) / 복지·지원금(청년월세 · 긴급복지) /
## 서민금융·주택자금(디딤돌대출 승인 · 햇살론유스). 자격과 조건은 서버(civic 메시지)가 계산해 보여 주고, 신청도 서버가 확정한다.
## 혼인신고를 하면 두 사람의 솔이 하나로 합쳐져 같이 쓴다 (서버의 세대 지갑).

signal closed

const BG: Color = Color(0.97, 0.98, 1.0, 0.98)
const EDGE: Color = Color(0.24, 0.34, 0.5)
const INK: Color = Color(0.16, 0.2, 0.3)
const SOFT: Color = Color(0.4, 0.44, 0.52)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.85)
const OK: Color = Color("#2E8E5A")
const NO: Color = Color("#C8503A")
const PICKED: Color = Color(0.72, 0.84, 0.98)
const DESKS: PackedStringArray = ["civil", "welfare", "finance"]
const DESK_NAMES: PackedStringArray = ["민원", "복지·지원금", "서민금융·주택"]

var _desk: String = "civil"
var _tabs: Array[Button] = []
var _greet: Label = null
var _body: VBoxContainer = null
var _note: Label = null
var _overlay: PanelContainer = null
var _overlay_body: VBoxContainer = null
var _dirty: bool = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.12, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 26))
	HudLayout.center_top(panel, 1000.0, 160.0)
	panel.offset_bottom = 1740.0
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	var title: Label = _label(str(GameData.econ.civic.get("name", "행정복지센터")), 40, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button: Button = _button("닫기", 30)
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	col.add_child(tabs)
	for i: int in DESKS.size():
		var b: Button = _button(DESK_NAMES[i], 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 90)
		b.pressed.connect(open.bind(DESKS[i]))
		tabs.add_child(b)
		_tabs.append(b)
	_greet = _label("", 28, SOFT)
	col.add_child(_greet)
	_note = _label("", 28, OK)
	_note.visible = false
	col.add_child(_note)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)
	_build_overlay()
	Economy.civic_changed.connect(func() -> void: _dirty = true)
	Economy.portfolio_changed.connect(func() -> void: _dirty = true)
	Economy.civic_done.connect(_on_done)
	Economy.failed.connect(_on_failed)
	Economy.loan_done.connect(func(r: Dictionary) -> void:
		if visible and str((r.get("loan", {}) as Dictionary).get("product", "")) == "sunshine_youth":
			_show_note("햇살론유스 %s 를 받았어요 (고정 연 %s)." % [Money.short(int((r["loan"] as Dictionary).get("principal", 0))), Money.percent(float((r["loan"] as Dictionary).get("rate", 0.0)))], true)
			Economy.ask_civic())


func is_open() -> bool:
	return visible


func open(desk: String = "") -> void:
	if not desk.is_empty():
		_desk = desk
	visible = true
	_note.visible = false
	for i: int in _tabs.size():
		_tabs[i].add_theme_stylebox_override("normal", EventHud._box(PICKED if DESKS[i] == _desk else CARD, EDGE, 24, 3, 10))
	var staff: Dictionary = GameData.econ.staff_of(_desk)
	_greet.text = "%s (%s): \"%s\"" % [str(staff.get("name", "")), str(staff.get("desk_name", "")), str(staff.get("greet", ""))]
	Economy.ask_civic()
	_rebuild()
	Audio.play_sfx("ui_open", -6.0)


func close() -> void:
	if not visible:
		return
	visible = false
	_overlay.visible = false
	Audio.play_sfx("ui_close", -6.0)
	closed.emit()


func _process(_delta: float) -> void:
	if visible and _dirty:
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	for c: Node in _body.get_children():
		c.queue_free()
	var c: Dictionary = Economy.civic
	match _desk:
		"civil":
			_build_civil(c)
		"welfare":
			for id: String in ["youth_rent", "emergency_living"]:
				_program_card(id)
		"finance":
			_body.add_child(_label("세대 연 소득(최근 4주 × 52, 혼인하면 부부합산) %s · 집 %d채 · 만 %d세" % [Money.short(int(c.get("income_year", 0))), int(c.get("homes", 0)), int(c.get("age", Economy.age))], 26, SOFT))
			for id: String in ["didimdol", "sunshine_youth"]:
				_program_card(id)


func _build_civil(c: Dictionary) -> void:
	var status: VBoxContainer = _card()
	var partner: int = int(c.get("partner", Economy.partner))
	status.add_child(_label("주소: %s · 세대: %s" % ["전입 완료" if bool(c.get("resident", false)) else "전입 전", ("%s 님과 부부 (지갑을 같이 써요)" % GameData.player_name(partner)) if partner > 0 else "혼자"], 28, INK))
	for id: String in ["move_in", "resident_copy", "family_cert"]:
		var svc: Dictionary = GameData.econ.civil_service(id)
		var card: VBoxContainer = _card()
		card.add_child(_label("%s%s" % [str(svc.get("name", id)), (" · 수수료 %s" % Money.sol(int(svc.get("fee", 0)))) if int(svc.get("fee", 0)) > 0 else " · 무료"], 30, INK))
		card.add_child(_label(str(svc.get("desc", "")), 22, SOFT))
		var b: Button = _button("신청", 28)
		b.disabled = (id == "move_in" and bool(c.get("resident", false))) or (id == "family_cert" and partner == 0)
		b.pressed.connect(Economy.civil_service.bind(id))
		card.add_child(b)
	_program_card("local_card")
	# 혼인신고
	var marry: VBoxContainer = _card()
	var svc2: Dictionary = GameData.econ.civil_service("marriage")
	marry.add_child(_label("혼인신고 · 무료", 30, INK))
	marry.add_child(_label(str(svc2.get("desc", "")), 22, SOFT))
	if partner > 0:
		marry.add_child(_label("%s 님과 혼인신고를 마쳤어요. 솔·소득·집을 함께 봐요 (신혼부부 디딤돌 우대)." % GameData.player_name(partner), 24, OK))
	else:
		var other: int = _other_player()
		var b2: Button = _button("%s 님과 함께 신고하기" % GameData.player_name(other) if other > 0 else "함께 올 사람이 없어요", 28)
		b2.disabled = other == 0
		b2.pressed.connect(func() -> void:
			Economy.propose_marriage(other)
			_show_note("%s 님에게 물어보는 중… (두 사람 모두 민원 창구 곁에 있어야 해요)" % GameData.player_name(other), true))
		marry.add_child(b2)


func _program_card(id: String) -> void:
	var def: Dictionary = GameData.econ.program_def(id)
	var state: Dictionary = Economy.program(id)
	var card: VBoxContainer = _card()
	var ok: bool = bool(state.get("ok", false))
	card.add_child(_label(str(def.get("name", id)), 32, INK))
	card.add_child(_label(str(def.get("desc", "")), 24, INK))
	var terms: Dictionary = state.get("terms", {}) if state.get("terms") is Dictionary else {}
	if id == "didimdol" and not terms.is_empty():
		card.add_child(_label("지금 조건: 고정 연 %s · 한도 %s · 집값 %s 이하 · LTV %d%%" % [Money.percent(float(terms.get("rate", 0.0))), Money.short(int(terms.get("limit", 0))), Money.short(int(terms.get("priceMax", 0))), roundi(float(terms.get("ltv", 0.7)) * 100.0)], 26, OK if ok else SOFT))
		var approval: Dictionary = (Economy.civic.get("approvals", {}) as Dictionary).get("didimdol", {}) if Economy.civic.get("approvals") is Dictionary else {}
		if not approval.is_empty():
			card.add_child(_label("승인됨 — %d주차까지 휴대폰 부동산 앱에서 '디딤돌'로 아파트를 살 수 있어요." % int(approval.get("until", 0)), 24, OK))
	if id == "sunshine_youth" and not terms.is_empty():
		card.add_child(_label("고정 연 %s · 남은 한도 %s" % [Money.percent(float(terms.get("rate", 0.0))), Money.short(int(terms.get("left", 0)))], 26, OK if ok else SOFT))
	var got: Dictionary = state.get("got", {}) if state.get("got") is Dictionary else {}
	if id == "youth_rent" and int(got.get("weeksLeft", 0)) > 0:
		card.add_child(_label("받는 중: 남은 %d주 (주마다 %s)" % [int(got.get("weeksLeft", 0)), Money.short(int(def.get("amount", 0)))], 24, OK))
	var reasons: Array = state.get("reasons", [])
	if not ok and not reasons.is_empty():
		card.add_child(_label("자격: " + " · ".join(PackedStringArray(reasons.map(func(r: Variant) -> String: return str(r)))), 24, NO))
	var real: Label = _label("실제 제도: " + str(def.get("real", "")), 20, SOFT)
	card.add_child(real)
	if id == "sunshine_youth":
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var left: int = int(terms.get("left", 0))
		for amount: int in [3000000, 6000000, 12000000]:
			var b: Button = _button(Money.short(amount), 26)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = not ok or amount > left
			b.pressed.connect(Economy.take_loan.bind(amount, "sunshine_youth"))
			row.add_child(b)
		return
	var apply: Button = _button({"local_card": "발급 신청", "didimdol": "대출 승인 받기"}.get(id, "신청"), 28)
	apply.disabled = not ok
	apply.pressed.connect(Economy.apply_program.bind(id))
	card.add_child(apply)


## 혼인신고를 같이 할 다른 사람 (마을에 있는 상대 자리 번호, 없으면 0).
func _other_player() -> int:
	if not Net.partner_present or not Net.partner_online:
		return 0
	return 2 if Net.my_id == 1 else 1


func _on_done(r: Dictionary) -> void:
	if not visible and str(r.get("service", "")) != "marriage":
		return
	var service: String = str(r.get("service", ""))
	var program: String = str(r.get("program", ""))
	if r.get("doc") is Dictionary:
		_show_document(r["doc"])
	match service:
		"move_in":
			_show_note("전입신고를 마쳤어요. 이제 천안시 지원 정책을 신청할 수 있어요.", true)
		"marriage":
			_show_note("혼인신고 완료! %s 님과 한 세대가 되어 솔을 같이 써요 (합친 솔 %s)." % [GameData.player_name(int(r.get("partner", 0))), Money.short(int(r.get("sol", 0)))], true)
		"marriage_declined":
			_show_note("다음에 하기로 했어요.", false)
	match program:
		"youth_rent":
			_show_note("청년월세 지원이 결정됐어요: 매주 %s × %d주." % [Money.short(int(r.get("weekly", 0))), int(r.get("weeks", 0))], true)
		"emergency_living":
			_show_note("긴급 생계비 %s 를 받았어요." % Money.short(int(r.get("amount", 0))), true)
		"local_card":
			_show_note("천안사랑카드를 발급했어요. 마을에서 사면 10%% 를 돌려받아요.", true)
		"didimdol":
			var a: Dictionary = r.get("approval", {})
			_show_note("디딤돌대출 승인: 고정 연 %s · 한도 %s (%d주차까지)" % [Money.percent(float(a.get("rate", 0.0))), Money.short(int(a.get("limit", 0))), int(a.get("until", 0))], true)
	Audio.play_sfx("quest_done", -6.0)


func _on_failed(kind: String, code: String) -> void:
	if not visible or not kind in ["civic_civil", "civic_apply", "marry_propose", "marry_answer", "loan_take"]:
		return
	var text: String = {
		NetProtocol.ERR_NOT_AT_CIVIC: "그 창구 곁에서 신청해 주세요.",
		NetProtocol.ERR_NOT_ELIGIBLE: "자격이 안 돼요.",
		NetProtocol.ERR_NO_PARTNER: "함께 신고할 사람이 곁에 없어요.",
		NetProtocol.ERR_ALREADY_MARRIED: "이미 혼인신고를 했어요.",
		NetProtocol.ERR_NOT_ENOUGH_SOL: "수수료가 모자라요.",
		NetProtocol.ERR_LOAN_LIMIT: "한도를 넘어요.",
	}.get(code, code)
	_show_note(text, false)


func _show_note(text: String, good: bool) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", OK if good else NO)
	_note.visible = true


## 혼인신고 물음 (상대가 신청했을 때, EconomyController 가 부른다).
func ask_proposal(from_id: int) -> void:
	if not visible:
		open("civil")
	for c: Node in _overlay_body.get_children():
		c.queue_free()
	_overlay_body.add_child(_label("혼인신고", 40, INK))
	_overlay_body.add_child(_label("%s 님이 함께 혼인신고를 하자고 해요.\n신고하면 두 사람의 솔이 하나로 합쳐져 같이 쓰고, 소득을 합산하며 신혼부부 정책을 받을 수 있어요." % GameData.player_name(from_id), 28, INK))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_overlay_body.add_child(row)
	var yes: Button = _button("함께 신고하기", 32)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func() -> void:
		Economy.answer_marriage(true)
		_overlay.visible = false)
	row.add_child(yes)
	var no: Button = _button("다음에", 32)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void:
		Economy.answer_marriage(false)
		_overlay.visible = false)
	row.add_child(no)
	_overlay.visible = true


func _show_document(doc: Dictionary) -> void:
	for c: Node in _overlay_body.get_children():
		c.queue_free()
	_overlay_body.add_child(_label(str(doc.get("title", "서류")), 40, INK))
	if str(doc.get("kind", "")) == "resident_copy":
		_overlay_body.add_child(_label("주소: %s" % str(doc.get("address", "")), 28, INK))
		for m: Variant in doc.get("members", []):
			if m is Dictionary:
				_overlay_body.add_child(_label("· %s  %s  (만 %d세)" % [str(m.get("relation", "")), GameData.player_name(int(m.get("slot", 0))), int(m.get("age", 0))], 28, INK))
	else:
		_overlay_body.add_child(_label("본인: %s" % GameData.player_name(int(doc.get("self", 0))), 28, INK))
		_overlay_body.add_child(_label("배우자: %s (%d일째부터)" % [GameData.player_name(int(doc.get("spouse", 0))), int(doc.get("since", 0))], 28, INK))
	_overlay_body.add_child(_label("솔바람동 행정복지센터장 (인)", 24, SOFT))
	var ok: Button = _button("확인", 30)
	ok.pressed.connect(func() -> void: _overlay.visible = false)
	_overlay_body.add_child(ok)
	_overlay.visible = true


func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.99, 0.96, 1.0), Color(0.6, 0.5, 0.3), 30, 6, 30))
	HudLayout.center_top(_overlay, 860.0, 560.0)
	_overlay.visible = false
	add_child(_overlay)
	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 14)
	_overlay.add_child(_overlay_body)


func _card() -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(CARD, Color(0.7, 0.76, 0.86), 24, 3, 20))
	_body.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	return col


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
