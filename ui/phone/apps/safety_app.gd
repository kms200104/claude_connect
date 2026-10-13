class_name SafetyApp
extends PhoneApp
## 안전알림 (v0.20, 앱 스토어에서 받는다): 지금 상황(민방위 훈련 중인지), 가까운 대피소(거리), 다음 민방위 훈련 일정,
## 받은 재난문자 기록(AlertLog), 낙뢰 · 폭염 · 한파 · 공습경보 행동요령.

const RED: Color = Color("#D93A30")
const ORANGE: Color = Color("#E88A1A")
const TIPS: Array[Array] = [
	["낙뢰", "건물 · 자동차 안으로 피해요. 나무 · 전봇대 아래, 호숫가 · 물가는 위험해요. 낚싯대 · 우산처럼 긴 쇠붙이는 몸에서 떼어요."],
	["폭염", "낮 12~5시 야외활동을 줄이고 물을 자주 마셔요. 어지러우면 무더위쉼터(행정복지센터)에서 쉬어요."],
	["한파", "외출할 때 모자 · 장갑으로 따뜻하게, 수도 계량기 · 배관이 얼지 않게 감싸 두어요."],
	["공습경보 (훈련)", "사이렌이 울리면 하던 일을 멈추고 가까운 대피소로 가요. 경보 해제 방송이 나올 때까지 기다려요."],
]


func _ready() -> void:
	_build()
	AlertLog.events.added.connect(func() -> void: _build.call_deferred())
	Net.drill_changed.connect(func(_i: Dictionary) -> void: _build.call_deferred())


func _build() -> void:
	clear()
	var rules: SafetyRules = GameData.safety
	# 지금 상황.
	var now: VBoxContainer = card()
	now.get_parent().name = "Now"
	if not Net.drill.is_empty():
		now.add_child(label("⚠ 민방위 훈련 중", 34, RED))
		now.add_child(label("가까운 대피소로 가요." if not bool(Net.drill.get("done", false)) else "대피 완료! 경보 해제를 기다려요.", 26, INK))
	else:
		now.add_child(label("지금은 평온해요", 32, GOOD))
	# 대피소.
	var shelter: VBoxContainer = card()
	shelter.get_parent().name = "Shelter"
	shelter.add_child(label("가까운 대피소", 30, INK))
	shelter.add_child(label(rules.shelter_name, 28, INK))
	if phone != null and phone.player != null:
		var d: float = Vector2(phone.player.global_position.x, phone.player.global_position.z).distance_to(rules.shelter)
		shelter.add_child(label("여기서 %dm · 마을 지도에 초록 표지판(민방위 대피소)으로 보여요" % roundi(d), 22, SOFT))
	# 훈련 일정.
	var drill: VBoxContainer = card()
	drill.get_parent().name = "DrillSchedule"
	drill.add_child(label("민방위 훈련 일정", 30, INK))
	drill.add_child(label("매달 %d일 %d시부터 %d분 · 다음 훈련 %s" % [rules.drill_day, rules.drill_hour, rules.drill_minutes, next_drill_text()], 24, INK))
	drill.add_child(label("사이렌이 울리는 동안 대피소에 들어가면 참여 보상 %s" % Money.short(rules.drill_reward), 22, SOFT))
	# 재난문자 기록.
	add_child(label("받은 재난문자", 30, INK))
	var entries: Array[Dictionary] = AlertLog.list()
	if entries.is_empty():
		add_child(label("아직 받은 문자가 없어요.", 24, SOFT))
	for a: Dictionary in entries:
		var emergency: bool = str(a.get("level", "")) == "emergency"
		var c: VBoxContainer = card()
		c.add_child(label("%s · %s" % ["긴급재난문자" if emergency else "안전안내문자", str(a.get("time", "")).replace("T", " ").left(16)], 22, RED if emergency else ORANGE))
		c.add_child(label(str(a.get("text", "")), 24, INK))
	# 행동요령.
	add_child(label("행동요령", 30, INK))
	for t: Array in TIPS:
		var c2: VBoxContainer = card()
		c2.add_child(label(str(t[0]), 26, INK))
		c2.add_child(label(str(t[1]), 22, SOFT))


## 다음 훈련 날짜 ("10월 15일 (오늘)" …) — 마을 시계 기준.
func next_drill_text() -> String:
	var rules: SafetyRules = GameData.safety
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(Net.game_ms() / 1000.0)) if Net.game_ms() > 0.0 else Time.get_datetime_dict_from_system()
	var month: int = int(d["month"])
	var day: int = int(d["day"])
	var hour: float = float(d["hour"]) + float(d["minute"]) / 60.0
	var done_today: bool = day > rules.drill_day or (day == rules.drill_day and hour >= float(rules.drill_hour) + float(rules.drill_minutes) / 60.0)
	if done_today:
		month = month % 12 + 1
	var today: bool = not done_today and day == rules.drill_day
	return "%d월 %d일%s" % [month, rules.drill_day, " (오늘)" if today else ""]
