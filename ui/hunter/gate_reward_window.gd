class_name GateRewardWindow
extends Control
## v0.28.12 게이트 공략 보상 창 (gate_clear): 가운데 카드 — 게이트 이름 · 등급 · 공략 시간, 그리고 세 칸
## ① 처치 보상 (던전 안에서 내가 쓰러뜨린 수 · 경험치 · 헌터 점수 · 떨어진 마석)
## ② 공략 보상 (우두머리를 쓰러뜨리면 열리는 상자 — 아이템 · 솔 · 점수 · 경험치)
## ③ 협회 지급 보상 (게이트 등급 × 내 헌터 등급 배율, 빠른 공략 · 우두머리 처치 덤 — 솔 · 경험치 · 점수 · 아이템).
## 받는 것은 이미 서버가 넣어 두었다 (그림만). '확인' 으로 닫는다.

const NAVY: Color = Color("#1E2A44")
const GOLD: Color = Color("#E8B830")
const INK: Color = Color("#F4EEDC")
const SOFT: Color = Color("#AEB8CC")

var _panel: PanelContainer = null
var _body: VBoxContainer = null


func _ready() -> void:
	name = "GateRewardWindow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(900, 0)
	_panel.add_theme_stylebox_override("panel", EventHud._box(Color(NAVY, 0.97), GOLD, 32, 5, 30))
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	_panel.add_child(_body)


func is_open() -> bool:
	return visible


func show_reward(info: Dictionary) -> void:
	for c: Node in _body.get_children():
		c.queue_free()
	var rank: String = str(info.get("rank", "E"))
	var rc: Color = GameData.hunter.gate_colors.get(rank, GOLD)
	_body.add_child(_label("%s급 게이트 공략 완료" % rank, 46, rc))
	var secs: int = int(info.get("time", 0)) / 1000
	var assoc: Dictionary = info.get("assoc", {}) if info.get("assoc") is Dictionary else {}
	_body.add_child(_label("%s · 공략 시간 %d:%02d%s" % [str(info.get("name", "")), secs / 60, secs % 60, "  ⚡ 빠른 공략!" if bool(assoc.get("fast", false)) else ""], 26, SOFT))
	# ① 처치 보상.
	var kills: Dictionary = info.get("kills", {}) if info.get("kills") is Dictionary else {}
	var k: VBoxContainer = _section("처치 보상", "Kills")
	k.add_child(_label("쓰러뜨린 크리처 %d마리 · 경험치 +%d · 헌터 점수 +%d" % [int(kills.get("n", 0)), int(kills.get("xp", 0)), int(kills.get("pts", 0))], 28, INK))
	_items(k, kills.get("mana", []), "떨어뜨린 마석")
	# ② 공략 보상.
	var c2: VBoxContainer = _section("공략 보상 (우두머리 상자)", "Clear")
	c2.add_child(_label("%s · 헌터 점수 +%d · 경험치 +%d" % [Money.delta(int(info.get("sol", 0))), int(info.get("pts", 0)), int(info.get("xp", 0))], 28, INK))
	_items(c2, info.get("items", []), "")
	# ③ 협회 지급 보상.
	if not assoc.is_empty():
		var a: VBoxContainer = _section("헌터 협회 지급 보상", "Assoc")
		var why: PackedStringArray = ["%s급 헌터 ×%.2f" % [str(assoc.get("hr", "E")), float(assoc.get("mult", 1.0))]]
		if bool(assoc.get("fast", false)):
			why.append("빠른 공략 덤")
		if bool(assoc.get("mvp", false)):
			why.append("우두머리 처치 덤")
		a.add_child(_label(" · ".join(why), 24, GOLD))
		a.add_child(_label("%s · 경험치 +%d · 헌터 점수 +%d" % [Money.delta(int(assoc.get("sol", 0))), int(assoc.get("xp", 0)), int(assoc.get("pts", 0))], 28, INK))
		_items(a, assoc.get("items", []), "")
	var total: int = int(info.get("sol", 0)) + int(assoc.get("sol", 0))
	_body.add_child(_label("합계 %s" % Money.delta(total), 34, GOLD))
	if int(info.get("back", 0)) > 0:
		_body.add_child(_label("떨어진 것을 줍고 나면 곧 게이트 밖으로 나가요", 22, SOFT))
	var ok: Button = Button.new()
	ok.name = "Confirm"
	ok.text = "확인"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(260, 88)
	ok.add_theme_font_size_override("font_size", 34)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close)
	_body.add_child(ok)
	visible = true
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * 0.6
	_panel.modulate.a = 0.0
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	# 크기가 정해진 뒤 가운데에.
	(func() -> void:
		_panel.reset_size()
		_panel.position = (size - _panel.size) * 0.5
		_panel.pivot_offset = _panel.size * 0.5).call_deferred()


func close() -> void:
	Audio.play_ui(Audio.SFX_CLICK)
	visible = false


func _section(title: String, node_name: String) -> VBoxContainer:
	var p: PanelContainer = PanelContainer.new()
	p.name = "Section%s" % node_name
	p.add_theme_stylebox_override("panel", EventHud._box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.18), 20, 2, 18))
	_body.add_child(p)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_label(title, 30, GOLD))
	return v


## 아이템 그림 줄 (그림 + ×개수).
func _items(parent: VBoxContainer, list: Variant, caption: String) -> void:
	if not (list is Array) or (list as Array).is_empty():
		return
	if not caption.is_empty():
		parent.add_child(_label(caption, 22, SOFT))
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	parent.add_child(row)
	for it: Variant in list:
		if not (it is Dictionary):
			continue
		var cell: HBoxContainer = HBoxContainer.new()
		var icon: TextureRect = TextureRect.new()
		icon.texture = GameData.item_icon(str(it.get("id", "")))
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(icon)
		var name_l: Label = _label("%s ×%d" % [GameData.item_name(str(it.get("id", ""))), int(it.get("n", 1))], 24, INK)
		name_l.custom_minimum_size = Vector2.ZERO
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(name_l)
		row.add_child(cell)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(820, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
