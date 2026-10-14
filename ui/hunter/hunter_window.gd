class_name HunterWindow
extends Control
## v0.28 헌터 협회 출장소 창구 (판정은 서버 hunter_sell · hunter_rank):
## 위: 헌터 자격증 (등급 배지 · 점수 막대 · 처치 수 · 길드), 점수가 차면 "등급 재심사".
## 아래: 마석 매각 — 가방의 마석 · 마나 조각마다 값(등급 · 길드만큼 더) · "팔기", 맨 위 "모두 팔기".

signal closed

const INK: Color = Color("#22304A")
const SOFT: Color = Color("#5A6880")
const PAPER: Color = Color("#F2F4F8")
const NAVY: Color = Color("#2A3A5A")
const GOLD: Color = Color("#E8C23A")

var _license: VBoxContainer = null
var _list: VBoxContainer = null
var _rank_button: Button = null
var _sell_all: Button = null


func _ready() -> void:
	name = "HunterWindow"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", EventHud._box(PAPER, NAVY, 36, 5, 26))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40.0
	panel.offset_right = -40.0
	panel.offset_top = 170.0
	panel.offset_bottom = -200.0
	add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	var title: Label = _label(GameData.hunter.office_name, 38, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button: Button = _button("닫기", 32)
	close_button.name = "CloseButton"
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_license = VBoxContainer.new()
	_license.name = "License"
	_license.add_theme_constant_override("separation", 6)
	box.add_child(_license)
	_rank_button = _button("등급 재심사", 30)
	_rank_button.name = "RankButton"
	_rank_button.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		Net.hunter_rank_up())
	box.add_child(_rank_button)
	var sell_head: HBoxContainer = HBoxContainer.new()
	box.add_child(sell_head)
	var sell_title: Label = _label("마석 매각", 32, INK)
	sell_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_head.add_child(sell_title)
	_sell_all = _button("모두 팔기", 28)
	_sell_all.name = "SellAll"
	_sell_all.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		Net.hunter_sell(-1))
	sell_head.add_child(_sell_all)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "SellScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "SellList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	Net.hunter_changed.connect(func() -> void:
		if visible:
			_build.call_deferred())
	Net.guild_changed.connect(func(_i: Dictionary) -> void:
		if visible:
			_build.call_deferred())
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void:
		if visible:
			_build.call_deferred())


func is_open() -> bool:
	return visible


func open() -> void:
	move_to_front()
	visible = true
	_build()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## 지금 마석을 팔 때 더 받는 몫 (등급 + 길드).
static func sell_bonus() -> float:
	var r: HunterRules.Rank = GameData.hunter.rank(str(Net.hunter.get("rank", "E")))
	return r.sell_bonus + (GameData.hunter.guild_sell_bonus if Net.in_guild() else 0.0)


func _build() -> void:
	for c: Node in _license.get_children():
		c.queue_free()
	for c: Node in _list.get_children():
		c.queue_free()
	_license.add_child(HunterWindow.license_card(true))
	var pts: int = int(Net.hunter.get("pts", 0))
	var next: int = int(Net.hunter.get("next", 0))
	var ready: bool = next > 0 and pts >= next
	_rank_button.disabled = not ready
	_rank_button.text = "등급 재심사 → %s급" % str(Net.hunter.get("nextRank", "")) if ready else ("최고 등급이에요" if next <= 0 else "재심사까지 %d점" % (next - pts))
	var bonus: float = sell_bonus()
	var any: bool = false
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it == null or not GameData.hunter.sell_items.has(it.id):
			continue
		any = true
		var slot: int = i
		var info: ItemInfo = GameData.item(it.id)
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Sell_%d" % slot
		row.add_theme_constant_override("separation", 10)
		var icon: TextureRect = TextureRect.new()
		icon.texture = GameData.item_icon(it.id)
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var each: int = roundi(float(info.price if info != null else 0) * (1.0 + bonus))
		var l: Label = _label("%s × %d\n개당 %s" % [GameData.item_name(it.id), it.count, Money.short(each)], 26, INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var sell: Button = _button("팔기", 26)
		sell.name = "SellButton_%d" % slot
		sell.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.hunter_sell(slot))
		row.add_child(sell)
		_list.add_child(row)
	_sell_all.disabled = not any
	if not any:
		_list.add_child(_label("가방에 마석이 없어요. 크리처를 쓰러뜨리면 마석이 떨어져요.", 26, SOFT))
	elif bonus > 0.0:
		_list.add_child(_label("등급%s 보너스 +%d%%" % [" · 길드" if Net.in_guild() else "", roundi(bonus * 100.0)], 24, Color("#3E8E4E")))


## 헌터 자격증 (협회 창구 · 헌터넷 앱이 같이 쓴다): 등급 배지 · 이름 · 점수 막대 · 처치 · 게이트 · 길드.
static func license_card(big: bool) -> Control:
	var rules: HunterRules = GameData.hunter
	var rank: HunterRules.Rank = rules.rank(str(Net.hunter.get("rank", "E")))
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "LicenseCard"
	panel.add_theme_stylebox_override("panel", EventHud._box(NAVY, GOLD, 24, 3, 18))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var badge: PanelContainer = PanelContainer.new()
	badge.name = "RankBadge"
	badge.custom_minimum_size = Vector2(120, 120) if big else Vector2(96, 96)
	badge.add_theme_stylebox_override("panel", EventHud._box(rank.color, Color.WHITE, 60, 4, 0))
	var letter: Label = Label.new()
	letter.name = "RankLetter"
	letter.text = rank.id
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 64 if big else 52)
	letter.add_theme_color_override("font_color", Color.WHITE)
	letter.add_theme_constant_override("outline_size", 8)
	letter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	badge.add_child(letter)
	row.add_child(badge)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var who: Label = Label.new()
	who.text = "%s급 헌터 · %s" % [rank.id, GameData.player_name(Net.my_id)]
	who.add_theme_font_size_override("font_size", 32 if big else 28)
	who.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(who)
	var pts: int = int(Net.hunter.get("pts", 0))
	var next: int = int(Net.hunter.get("next", 0))
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "PointsBar"
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	bar.max_value = maxf(1.0, float(next - rank.points)) if next > 0 else 1.0
	bar.value = float(pts - rank.points) if next > 0 else 1.0
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(10)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.18)
	bg.set_corner_radius_all(10)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	col.add_child(bar)
	var info: Label = Label.new()
	info.name = "PointsLabel"
	var guild_text: String = " · 길드 %s" % str(Net.guild.get("name", "")) if Net.in_guild() else ""
	info.text = "%d점%s · 처치 %d · 게이트 %d%s" % [pts, " / %d (→ %s급)" % [next, str(Net.hunter.get("nextRank", ""))] if next > 0 else " (최고 등급)", int(Net.hunter.get("kills", 0)), int(Net.hunter.get("gates", 0)), guild_text]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 24)
	info.add_theme_color_override("font_color", Color("#D8E0F0"))
	col.add_child(info)
	return panel


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 72)
	b.add_theme_font_size_override("font_size", size)
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	return b
