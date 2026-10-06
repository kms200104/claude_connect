class_name AchievementsApp
extends PhoneApp
## 업적 · 칭호 (v16): 이룬 업적과 다음 목표까지의 막대, 칭호 달기 · 떼기.
## 판정 · 칭호 확정은 서버가 한다 (Journal.set_title → 서버가 모두에게 알린다).

const GOLD: Color = Color("#E0A020")
const SILVER: Color = Color("#B8B2A8")

var _note: String = ""


func _ready() -> void:
	_build()
	Journal.changed.connect(func() -> void:
		if is_inside_tree():
			_build.call_deferred())
	Journal.failed.connect(func(kind: String, _code: String) -> void:
		if kind == "set_title" and is_inside_tree():
			_note = "그 칭호는 아직 달 수 없어요."
			_build.call_deferred())


func _build() -> void:
	clear()
	var done: int = Journal.achieved_at.size()
	var total: int = GameData.achievements.size()
	var head: VBoxContainer = card()
	var title: String = Journal.title_text(Net.my_id)
	head.add_child(label("내 칭호: %s" % ("[%s]" % title if not title.is_empty() else "없음"), 34, INK))
	head.add_child(label("머리 위 이름 옆에 보여요 · %s" % Journal.display_name(Net.my_id), 24, SOFT))
	if not title.is_empty():
		var off: Button = button("칭호 떼기", 26)
		off.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Journal.set_title(""))
		head.add_child(off)
	head.add_child(label("업적 %d / %d" % [done, total], 28, INK))
	head.add_child(meter(float(done) / maxf(1.0, float(total)), GOLD))
	if not _note.is_empty():
		head.add_child(label(_note, 24, WARN))
		_note = ""
	# 이룬 것 먼저, 그다음 가까운 것부터.
	var list: Array[AchievementInfo] = GameData.achievements.duplicate()
	list.sort_custom(func(a: AchievementInfo, b: AchievementInfo) -> bool:
		var ha: bool = Journal.has(a.id)
		var hb: bool = Journal.has(b.id)
		if ha != hb:
			return ha
		return _ratio(a) > _ratio(b))
	for a: AchievementInfo in list:
		add_child(_row(a))


static func _ratio(a: AchievementInfo) -> float:
	return clampf(float(Journal.stat(a.stat)) / float(a.goal), 0.0, 1.0)


func _row(a: AchievementInfo) -> Control:
	var have: bool = Journal.has(a.id)
	var wearing: bool = Journal.my_title() == a.id
	var c: VBoxContainer = VBoxContainer.new()
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.97, 0.84, 0.95) if have else CARD, GOLD if wearing else Color(0.8, 0.72, 0.6), 22, 4 if wearing else 2, 16))
	panel.name = "Ach_%s" % a.id
	panel.add_child(c)
	c.add_theme_constant_override("separation", 6)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	c.add_child(top)
	var medal: Control = Control.new()
	medal.custom_minimum_size = Vector2(64, 64)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.draw.connect(func() -> void:
		var col: Color = GOLD if have else SILVER
		var m: Vector2 = medal.size * 0.5
		medal.draw_colored_polygon(PackedVector2Array([m + Vector2(-14, -30), m + Vector2(-4, -6), m + Vector2(4, -6), m + Vector2(14, -30)]), Color("#E8594A") if have else Color(0.75, 0.7, 0.66))
		medal.draw_circle(m + Vector2(0, 8), 22.0, col.darkened(0.15))
		medal.draw_circle(m + Vector2(0, 8), 18.0, col)
		var font: Font = medal.get_theme_default_font()
		var t: String = str(a.tier)
		var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		medal.draw_string(font, m + Vector2(-w * 0.5, 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE))
	top.add_child(medal)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(text)
	text.add_child(label(a.display_name, 30, INK if have else SOFT))
	text.add_child(label(a.description, 22, SOFT))
	text.add_child(label("칭호 [%s]" % a.title, 22, GOLD.darkened(0.25) if have else SOFT))
	if have:
		var when: int = int(Journal.achieved_at.get(a.id, 0))
		if when > 0:
			text.add_child(label("%s 달성" % VillageClock.format_date(when), 20, GOOD))
		var wear: Button = button("달고 있어요" if wearing else "칭호 달기", 24, GOOD if not wearing else SOFT, wearing)
		wear.custom_minimum_size = Vector2(170, 72)
		wear.disabled = wearing
		wear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wear.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CONFIRM)
			Journal.set_title(a.id))
		top.add_child(wear)
	else:
		var value: int = mini(Journal.stat(a.stat), a.goal)
		c.add_child(meter(float(value) / float(a.goal), GOLD))
		c.add_child(label("%s / %s" % [_count(value, a.stat), _count(a.goal, a.stat)], 20, SOFT))
	return panel


## 솔은 돈으로, 나머지는 숫자로.
static func _count(n: int, stat: String) -> String:
	return Money.short(n) if stat == "sol" else str(n)
