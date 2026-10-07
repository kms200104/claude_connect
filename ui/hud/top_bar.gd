class_name TopBar
extends Control
## 화면 위: 마을 시각 · 날씨 · 솔 · 부탁 버튼. 부탁 버튼을 누르면 받은 부탁 목록을 펼친다.

const WEATHER_TEXT: Dictionary = {
	"clear": "맑음",
	"cloudy": "흐림",
	"rain": "비",
	"thunder": "뇌우",
}

@onready var _clock: Label = %ClockLabel
@onready var _weather: Label = %WeatherLabel
@onready var _sol: Label = %SolLabel
@onready var _quest_button: Button = %QuestButton
@onready var _log: PanelContainer = %QuestLog
@onready var _list: VBoxContainer = %QuestList

var _clock_accum: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_button.pressed.connect(func() -> void: _log.visible = not _log.visible)
	_quest_button.add_to_group(&"blocks_joystick")
	_log.add_to_group(&"blocks_joystick")
	_log.visible = false
	# 이벤트 알림판보다 위에 그린다 (펼치면 가려지지 않게).
	_log.z_index = 5
	ScreenFit.changed.connect(func(_wide: bool) -> void: _fit_log())
	_fit_log()
	Net.profile_updated.connect(_refresh_profile)
	Net.weather_changed.connect(func(_w: String) -> void: _refresh_weather())
	Net.state_changed.connect(func(_s: int) -> void: _refresh_visibility())
	_refresh_visibility()
	_refresh_profile()


func _process(delta: float) -> void:
	_clock_accum += delta
	if _clock_accum >= 0.5 and visible:
		_clock_accum = 0.0
		_clock.text = VillageClock.format_time(Net.game_hour())


## 부탁 목록 자리: 세로는 화면 폭 그대로, 가로는 부탁 단추 아래 오른쪽에 1000 폭으로.
func _fit_log() -> void:
	if ScreenFit.landscape:
		_log.anchor_left = 1.0
		_log.anchor_right = 1.0
		_log.offset_left = -1024.0
		_log.offset_right = -24.0
		_log.offset_top = 150.0
	else:
		_log.anchor_left = 0.0
		_log.anchor_right = 1.0
		_log.offset_left = 24.0
		_log.offset_right = -24.0
		_log.offset_top = 270.0
	_log.offset_bottom = _log.offset_top + 250.0


func quest_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for child: Node in _list.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func _refresh_visibility() -> void:
	var online: bool = Net.state == Net.State.ONLINE or Net.state == Net.State.RECONNECTING
	%Bar.visible = online
	if not online:
		_log.visible = false
	_refresh_weather()


func _refresh_weather() -> void:
	_weather.text = WEATHER_TEXT.get(Net.weather, Net.weather)


func _refresh_profile() -> void:
	# 혼인신고를 하면 지갑을 같이 쓴다 (v9).
	_sol.text = ("부부 " if Economy.is_married() else "") + Money.short(Net.sol)
	_quest_button.text = "부탁 %d" % Net.quests.size()
	for child: Node in _list.get_children():
		child.queue_free()
	if Net.quests.is_empty():
		_list.add_child(_line("받은 부탁이 없어요. 주민에게 말을 걸어 보세요!", Color(0.5, 0.42, 0.34)))
		return
	var today: int = Net.game_day()
	for q: QuestInfo in Net.quests:
		var due: String = "오늘까지" if q.expires_day <= today else "내일까지"
		var state: String = "완료 가능!" if q.is_ready() else "%d/%d" % [mini(q.have, q.count), q.count]
		var text: String = "%s · %s (%s) · %s · %s" % [GameData.npc_name(q.npc), DialogueController.describe_quest(q), state, Money.sol(q.reward), due]
		_list.add_child(_line(text, Color(0.2, 0.55, 0.3) if q.is_ready() else Color(0.3, 0.24, 0.18)))


func _line(text: String, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", color)
	return label
