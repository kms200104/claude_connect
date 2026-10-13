class_name StepsApp
extends PhoneApp
## 솔걸음 만보기 (v0.20, 앱 스토어에서 받는다): 오늘 걸음 · 다음 목표 고리 · 목표별 보상(서버가 인정한 걸음 기준) · 이레치 막대 · 거리 · 칼로리.
## 걸음은 Pedometer(가속도 센서)가 세고, 서버가 사람이 걸을 수 있는 빠르기로 걸러 인정한다.

const GREEN: Color = Color("#36B37E")
## 한 걸음 길이 (m) · 한 걸음 칼로리 (kcal).
const STRIDE_M: float = 0.7
const KCAL: float = 0.04

var _ring: Control = null


func _ready() -> void:
	_build()
	Net.steps_updated.connect(func(_i: Dictionary) -> void: _build.call_deferred())
	var p: Pedometer = _pedometer()
	if p != null:
		p.stepped.connect(func(_n: int) -> void:
			if _ring != null and is_instance_valid(_ring):
				_ring.queue_redraw())


func _pedometer() -> Pedometer:
	return get_tree().get_first_node_in_group(&"pedometer") as Pedometer if is_inside_tree() else null


func _today() -> int:
	var p: Pedometer = _pedometer()
	return p.today if p != null else Net.steps_today


func _build() -> void:
	clear()
	var rules: SafetyRules = GameData.safety
	var head: VBoxContainer = card()
	_ring = Control.new()
	_ring.name = "StepsRing"
	_ring.custom_minimum_size = Vector2(0, 330)
	_ring.draw.connect(_draw_ring)
	head.add_child(_ring)
	var today: int = _today()
	head.add_child(label("%.2f km · %d kcal · 서버 인정 %s걸음" % [today * STRIDE_M / 1000.0, roundi(today * KCAL), SafetyController._comma(Net.steps_today)], 24, SOFT))
	var p: Pedometer = _pedometer()
	if p != null and not p.has_sensor() and today == 0:
		head.add_child(label("휴대폰을 들고 걸으면 세기 시작해요. (걸음 센서가 없는 기기 · PC 에서는 세지 않아요)", 22, WARN))
	# 목표별 보상.
	add_child(label("오늘의 목표", 30, INK))
	for i: int in rules.tiers.size():
		var t: Vector2i = rules.tiers[i]
		var got: bool = i in Net.steps_got
		var c: VBoxContainer = card()
		c.get_parent().name = "Tier_%d" % i
		var row: HBoxContainer = HBoxContainer.new()
		c.add_child(row)
		var name_label: Label = label("%s %s걸음" % ["✔" if got else "○", SafetyController._comma(t.x)], 28, INK, false)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(label("받음" if got else "+%s" % Money.short(t.y), 26, GOOD if got else INK, false))
		c.add_child(meter(clampf(float(Net.steps_today) / float(t.x), 0.0, 1.0), GREEN))
	# 이레치.
	add_child(label("최근 7일", 30, INK))
	var chart: Control = Control.new()
	chart.custom_minimum_size = Vector2(0, 240)
	chart.draw.connect(_draw_week.bind(chart))
	add_child(chart)
	add_child(label("하루 상한 %s걸음 · 자정에 0부터 다시 세요. 게임이 켜져 있을 때 센 걸음만 들어가요." % SafetyController._comma(rules.daily_cap), 22, SOFT))


func _draw_ring() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, _ring.size)
	var c: Vector2 = r.size * 0.5
	var radius: float = minf(r.size.x, r.size.y) * 0.42
	var today: int = _today()
	var goal: int = GameData.safety.tiers[GameData.safety.tiers.size() - 1].x if not GameData.safety.tiers.is_empty() else 10000
	for t: Vector2i in GameData.safety.tiers:
		if today < t.x:
			goal = t.x
			break
	var k: float = clampf(float(today) / float(goal), 0.0, 1.0)
	_ring.draw_arc(c, radius, 0.0, TAU, 96, Color(GREEN, 0.18), 30.0, true)
	_ring.draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * k, 96, GREEN, 30.0, true)
	var font: Font = ThemeDB.fallback_font
	var big: String = SafetyController._comma(today)
	var w: float = font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
	_ring.draw_string(font, c + Vector2(-w * 0.5, 10.0), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 72, INK)
	var sub: String = "다음 목표 %s걸음" % SafetyController._comma(goal)
	var w2: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	_ring.draw_string(font, c + Vector2(-w2 * 0.5, 58.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, SOFT)


func _draw_week(chart: Control) -> void:
	var p: Pedometer = _pedometer()
	var days: Array[Array] = p.recent(7) if p != null else []
	if days.is_empty():
		return
	var top: int = 1000
	for d: Array in days:
		top = maxi(top, int(d[1]))
	var w: float = chart.size.x / float(days.size())
	var font: Font = ThemeDB.fallback_font
	for i: int in days.size():
		var n: int = int(days[i][1])
		var h: float = (chart.size.y - 50.0) * float(n) / float(top)
		var x: float = w * float(i) + w * 0.2
		chart.draw_rect(Rect2(Vector2(x, chart.size.y - 34.0 - h), Vector2(w * 0.6, h)), GREEN if i == days.size() - 1 else Color(GREEN, 0.45))
		var day: String = str(days[i][0]).right(2)
		chart.draw_string(font, Vector2(x, chart.size.y - 8.0), "%s일" % day, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, SOFT)
