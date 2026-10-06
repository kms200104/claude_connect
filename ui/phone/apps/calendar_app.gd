class_name CalendarApp
extends PhoneApp
## 날씨 · 달력 (v16): 오늘과 내일 날씨(3시간 칸), 이번 주(이레) 마을 이벤트(낚시 대회 · 나무꾼의 날 …) · 유성우 · 생일.
## 앞날 날씨와 이벤트는 마을 시드로 정해지는 값이라 서버가 미리 계산해 보내 준다 (cal_info).

const BLOCK_HOURS: PackedInt32Array = [0, 3, 6, 9, 12, 15, 18, 21]
const SKY: Color = Color("#DDEFFB")
const SKY_NIGHT: Color = Color("#2E3A5C")


func _ready() -> void:
	Journal.calendar_changed.connect(func() -> void:
		if is_inside_tree():
			_build.call_deferred())
	Journal.ask_calendar()
	_build()


func _build() -> void:
	clear()
	if Journal.calendar.is_empty():
		add_child(label("날씨를 불러오는 중…", 30, SOFT))
		return
	var days: Array[Dictionary] = Journal.calendar
	_today_card(days[0])
	if days.size() > 1:
		_tomorrow_card(days[1])
	_econ_card()
	add_child(label("이번 주", 34, INK))
	for i: int in days.size():
		add_child(_week_row(days[i], i))
	add_child(label("날씨와 이벤트는 마을 하늘이 정해요. 예보는 서버가 계산한 그대로라 틀리지 않아요!", 22, SOFT))


## 오늘: 큰 날씨 그림 · 지금 시각 · 3시간 칸 여덟 개 · 오늘 이벤트 · 생일.
func _today_card(d: Dictionary) -> void:
	var hour: float = Net.game_hour()
	var night: bool = hour >= 19.0 or hour < 5.5
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(SKY_NIGHT if night else SKY, Color(0.7, 0.8, 0.9), 30, 3, 22))
	add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var ink: Color = Color.WHITE if night else INK
	var soft: Color = Color(0.85, 0.88, 1.0) if night else SOFT
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	col.add_child(top)
	top.add_child(WeatherGlyph.make(Net.weather, 150.0, night))
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(text)
	text.add_child(label("오늘 · %s" % _date_text(d), 30, ink))
	text.add_child(label("지금 %s · %s" % [WeatherGlyph.name_of(Net.weather), VillageClock.format_time(hour)], 40, ink))
	text.add_child(label(VillageClock.season_name(str(d["season"])), 24, soft))
	col.add_child(_blocks(d, true, ink, soft))
	_day_events(col, d, ink, soft, true)


func _tomorrow_card(d: Dictionary) -> void:
	var c: VBoxContainer = card()
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	c.add_child(top)
	top.add_child(WeatherGlyph.make(_main_weather(d), 96.0))
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(text)
	text.add_child(label("내일 · %s" % _date_text(d), 28, INK))
	text.add_child(label(_summary(d), 32, INK))
	c.add_child(_blocks(d, false, INK, SOFT))
	_day_events(c, d, INK, SOFT, false)


func _econ_card() -> void:
	var ev: EventInfo = GameData.event_info(Journal.calendar_econ)
	if ev == null:
		return
	var c: VBoxContainer = card()
	c.add_child(label("이번 주 경제 소식 · %s" % ev.display_name, 28, WARN))
	c.add_child(label(ev.description, 22, SOFT))


## 3시간 칸 여덟 개 (오늘이면 지금 칸을 표시).
func _blocks(d: Dictionary, today: bool, ink: Color, soft: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var weather: PackedStringArray = d["weather"]
	var now_block: int = floori(Net.game_hour() / 3.0) if today else -1
	for i: int in mini(weather.size(), BLOCK_HOURS.size()):
		var cell: VBoxContainer = VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		var h: int = BLOCK_HOURS[i]
		var tag: Label = label("지금" if i == now_block else "%d시" % h, 20, ink if i == now_block else soft, false)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(tag)
		var g: WeatherGlyph = WeatherGlyph.make(weather[i], 64.0, h >= 18 or h < 6)
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(g)
		if i == now_block:
			var box: PanelContainer = PanelContainer.new()
			box.add_theme_stylebox_override("panel", EventHud._box(Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.7), 14, 2, 2))
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(cell)
			row.add_child(box)
		else:
			row.add_child(cell)
	return row


## 그날 이벤트 · 유성우 · 생일 줄.
func _day_events(col: VBoxContainer, d: Dictionary, ink: Color, soft: Color, detailed: bool) -> void:
	var ev: EventInfo = GameData.event_info(str(d["event"]))
	if ev != null:
		col.add_child(label("★ %s · %s" % [ev.display_name, _hours_text(ev.hours)], 28, ink))
		if detailed and not ev.description.is_empty():
			col.add_child(label(ev.description, 22, soft))
	if bool(d["meteor"]):
		var weather: PackedStringArray = d["weather"]
		var clear_night: bool = weather.size() >= 8 and weather[7] == "clear"
		col.add_child(label("☆ 유성우가 올지도 몰라요%s" % (" (밤에 맑음!)" if clear_night else " (밤에 맑아야 보여요)"), 26, ink))
	for name_text: String in _birthday_names(d):
		col.add_child(label("♥ %s 생일" % name_text, 26, ink))


func _week_row(d: Dictionary, index: int) -> Control:
	var row: Button = row_button(112.0)
	var line: HBoxContainer = fill_row(row, 14)
	var date_col: VBoxContainer = VBoxContainer.new()
	date_col.custom_minimum_size = Vector2(118, 0)
	date_col.alignment = BoxContainer.ALIGNMENT_CENTER
	date_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(date_col)
	var weekday: int = int(d["weekday"])
	var day_color: Color = WARN if weekday == 0 else (Color("#2F62C8") if weekday == 6 else INK)
	date_col.add_child(label(["오늘", "내일"][index] if index < 2 else VillageClock.WEEKDAYS[weekday] + "요일", 26, day_color, false))
	date_col.add_child(label("%d/%d" % [int(d["month"]), int(d["date"])], 22, SOFT, false))
	line.add_child(WeatherGlyph.make(_main_weather(d), 76.0))
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var ev: EventInfo = GameData.event_info(str(d["event"]))
	var title: Label = label(ev.display_name if ev != null else _summary(d), 26, INK, false)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var extras: PackedStringArray = []
	if ev != null:
		extras.append(_hours_text(ev.hours))
	if bool(d["meteor"]):
		extras.append("☆ 유성우")
	for n: String in _birthday_names(d):
		extras.append("♥ %s" % n)
	if not extras.is_empty():
		var sub: Label = label(" · ".join(extras), 20, SOFT, false)
		sub.clip_text = true
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(sub)
	return row


func _birthday_names(d: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in d["npcs"]:
		out.append(GameData.npc_name(id))
	for slot: int in d["players"]:
		out.append("나" if slot == Net.my_id else "%s 님" % GameData.player_name(slot))
	return out


## 그날 낮(6시 ~ 18시)에 가장 많은 날씨.
static func _main_weather(d: Dictionary) -> String:
	var weather: PackedStringArray = d["weather"]
	var count: Dictionary[String, int] = {}
	for i: int in range(2, mini(7, weather.size())):
		count[weather[i]] = count.get(weather[i], 0) + 1
	var best: String = weather[0] if not weather.is_empty() else "clear"
	for w: String in count:
		if count[w] > count.get(best, 0):
			best = w
	return best


## "맑다가 오후에 비" 같은 한 줄.
static func _summary(d: Dictionary) -> String:
	var weather: PackedStringArray = d["weather"]
	if weather.size() < 8:
		return WeatherGlyph.name_of(_main_weather(d))
	var morning: String = weather[3]
	var afternoon: String = weather[5]
	if morning == afternoon:
		return "하루 종일 %s" % WeatherGlyph.name_of(morning) if weather.count(morning) >= 6 else WeatherGlyph.name_of(morning)
	return "오전 %s → 오후 %s" % [WeatherGlyph.name_of(morning), WeatherGlyph.name_of(afternoon)]


static func _date_text(d: Dictionary) -> String:
	return "%d월 %d일 (%s)" % [int(d["month"]), int(d["date"]), VillageClock.WEEKDAYS[int(d["weekday"]) % 7]]


static func _hours_text(hours: PackedInt32Array) -> String:
	return "하루 종일" if hours.size() != 2 else "%d시 ~ %d시" % [hours[0], hours[1]]
