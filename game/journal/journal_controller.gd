class_name JournalController
extends Node
## v16 알림 띠: 업적을 이루면 화면 위에서 트로피 띠가 내려온다 ("업적 달성! · 칭호를 얻었어요").
## 친구가 우리 집에 놀러 오거나, 오늘이 내 생일이면 같은 띠로 알린다. 여러 개면 차례로.

@export var hud: CanvasLayer

const SHOW_S: float = 3.4
const BG: Color = Color(1.0, 0.97, 0.86, 0.97)
const EDGE: Color = Color("#E2A93B")
const INK: Color = Color(0.36, 0.24, 0.12)

var _queue: Array[Dictionary] = []
var _banner: PanelContainer = null
var _icon: Control = null
var _title: Label = null
var _line: Label = null
var _busy: bool = false
var _icon_kind: String = "trophy"
## 오늘 생일 띠를 이미 보였는지 (마을 날짜).
var _birthday_shown_day: int = -1
var _holder: Control = null


func _ready() -> void:
	_build()
	Journal.achieved.connect(func(ids: PackedStringArray) -> void:
		for id: String in ids:
			var a: AchievementInfo = GameData.achievement_by_id.get(id)
			if a != null:
				push("trophy", "업적 달성! %s" % a.display_name, "칭호 [%s]를 얻었어요 · 휴대폰 업적 앱에서 달 수 있어요" % a.title))
	Journal.visited.connect(func(slot: int) -> void:
		push("house", "%s 님이 놀러 왔어요!" % GameData.player_name(slot), "집 안에서 방명록을 남길 수 있어요"))
	Journal.changed.connect(_check_birthday)


## 띠 하나를 줄 세운다 (kind: trophy · house · cake).
func push(kind: String, title: String, line: String) -> void:
	_queue.append({"kind": kind, "title": title, "line": line})
	if not _busy:
		_next()


## 지금 보이는 띠의 제목 (테스트용, 없으면 빈 문자열).
func showing() -> String:
	return _title.text if _banner != null and _banner.visible else ""


func _check_birthday() -> void:
	if Journal.birthday == Vector2i.ZERO or Net.state != Net.State.ONLINE:
		return
	var today: int = Net.game_day()
	var date: Dictionary = VillageClock.date_of_day(today)
	if Journal.birthday == Vector2i(int(date["month"]), int(date["day"])) and _birthday_shown_day != today:
		_birthday_shown_day = today
		push("cake", "생일 축하해요, %s 님!" % GameData.player_name(Net.my_id), "주민들이 마을톡으로 축하 인사와 선물을 보냈어요")


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var item: Dictionary = _queue.pop_front()
	_icon_kind = str(item["kind"])
	_icon.queue_redraw()
	_title.text = str(item["title"])
	_line.text = str(item["line"])
	Audio.play_sfx("level_up" if _icon_kind == "trophy" else "quest_done", -3.0, 1.0, 0.0)
	# 휴대폰을 보는 중이면 휴대폰 화면을 가리지 않게 아래쪽(캐릭터 자리)에.
	var phone: CanvasItem = hud.get_node_or_null("PhoneWindow") as CanvasItem if hud != null else null
	var phone_open: bool = phone != null and phone.visible
	var low: bool = phone_open and not ScreenFit.landscape
	# 가로 화면이면 휴대폰은 오른쪽 — 띠는 왼쪽(캐릭터 위)에.
	_holder.anchor_right = 0.42 if phone_open and ScreenFit.landscape else 1.0
	_holder.offset_top = HudLayout.fit_y(1440.0) if low else 150.0
	_holder.offset_bottom = _holder.offset_top + 180.0
	_banner.visible = true
	# 글이 바뀌면 높이를 다시 (Control 은 커지기만 하고 저절로 줄지 않는다).
	_banner.reset_size()
	_banner.set_deferred("size", Vector2(_banner.size.x, 0.0))
	_banner.modulate.a = 0.0
	_banner.position.y = -40.0
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(_banner, "modulate:a", 1.0, 0.25)
	t.tween_property(_banner, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(SHOW_S)
	t.chain().tween_property(_banner, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(func() -> void:
		_banner.visible = false
		_next())


func _build() -> void:
	var holder: Control = Control.new()
	_holder = holder
	holder.name = "JournalBanner"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 150.0
	holder.offset_bottom = 330.0
	holder.z_index = 20
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 5, 22))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.custom_minimum_size = Vector2(860, 0)
	_banner.offset_left = -430.0
	_banner.offset_right = 430.0
	_banner.visible = false
	holder.add_child(_banner)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(row)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(110, 110)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	row.add_child(_icon)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 줄바꿈 글자는 폭이 정해져야 높이가 맞는다 (안 정하면 글자마다 줄이 바뀌어 띠가 화면만큼 길어진다).
	col.custom_minimum_size = Vector2(680, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_title = Label.new()
	_title.custom_minimum_size = Vector2(680, 0)
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_color_override("font_color", INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_line = Label.new()
	_line.custom_minimum_size = Vector2(680, 0)
	_line.add_theme_font_size_override("font_size", 26)
	_line.add_theme_color_override("font_color", INK.lightened(0.25))
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_line)
	if hud != null:
		hud.add_child.call_deferred(holder)
	else:
		add_child(holder)


## 띠 왼쪽 그림: 트로피 · 집 · 케이크.
func _draw_icon() -> void:
	var s: float = _icon.size.x
	var c: Vector2 = _icon.size * 0.5
	_icon.draw_circle(c, s * 0.48, Color("#FFE7A8"))
	match _icon_kind:
		"house":
			_icon.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.02), c + Vector2(0, -s * 0.3), c + Vector2(s * 0.3, -s * 0.02)]), Color("#E8594A"))
			_icon.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.02), Vector2(s * 0.44, s * 0.3)), Color("#F7E2C0"))
			_icon.draw_rect(Rect2(c + Vector2(-s * 0.06, s * 0.1), Vector2(s * 0.12, s * 0.18)), Color("#8A5A3A"))
		"cake":
			_icon.draw_rect(Rect2(c + Vector2(-s * 0.28, -s * 0.02), Vector2(s * 0.56, s * 0.28)), Color("#F7C6D2"))
			_icon.draw_rect(Rect2(c + Vector2(-s * 0.28, -s * 0.06), Vector2(s * 0.56, s * 0.08)), Color.WHITE)
			for x: float in [-0.14, 0.0, 0.14]:
				_icon.draw_rect(Rect2(c + Vector2(s * x - s * 0.02, -s * 0.24), Vector2(s * 0.04, s * 0.18)), Color("#7FB6E8"))
				_icon.draw_circle(c + Vector2(s * x, -s * 0.28), s * 0.04, Color("#FFB23A"))
		_:
			# 트로피: 잔 · 손잡이 · 받침.
			var gold: Color = Color("#F2B53A")
			_icon.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.22, -s * 0.28), c + Vector2(s * 0.22, -s * 0.28), c + Vector2(s * 0.14, s * 0.02), c + Vector2(-s * 0.14, s * 0.02)]), gold)
			_icon.draw_arc(c + Vector2(-s * 0.22, -s * 0.16), s * 0.09, PI * 0.5, PI * 1.5, 12, gold, s * 0.045)
			_icon.draw_arc(c + Vector2(s * 0.22, -s * 0.16), s * 0.09, -PI * 0.5, PI * 0.5, 12, gold, s * 0.045)
			_icon.draw_rect(Rect2(c + Vector2(-s * 0.04, s * 0.02), Vector2(s * 0.08, s * 0.14)), gold.darkened(0.1))
			_icon.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.16), Vector2(s * 0.36, s * 0.08)), gold.darkened(0.2))
			_icon.draw_circle(c + Vector2(-s * 0.08, -s * 0.2), s * 0.035, Color(1, 1, 1, 0.7))
