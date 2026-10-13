class_name ElevatorRide
extends PanelContainer
## 엘리베이터 타는 연출 (v0.21 리버파크 · M1): 공동현관에서 집에 들어갈 때 · 나올 때 화면 가운데에 층 표시가 올라가고(내려가고)
## "띵" 하고 문이 열린다. 순간이동은 서버가 이미 했으므로 그림만 (조작은 막지 않는다). FLOOR_S 초마다 한 층, 길어도 MAX_S 초.

const FLOOR_S: float = 0.09
const MAX_S: float = 1.4
const HOLD_S: float = 0.45

var _label: Label = null
var _arrow: Label = null


## hud 에 붙여 from → to 층으로 움직이는 표시를 띄운다.
static func play(hud: Node, from_floor: int, to_floor: int, title: String) -> ElevatorRide:
	var ride: ElevatorRide = ElevatorRide.new()
	ride.name = "ElevatorRide"
	hud.add_child(ride)
	ride._run(from_floor, to_floor, title)
	return ride


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", EventHud._box(Color(0.12, 0.13, 0.15, 0.9), Color(0.85, 0.87, 0.9, 0.9), 28, 3, 22))
	HudLayout.center_top(self, 420.0, 640.0)


func _run(from_floor: int, to_floor: int, title: String) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head: Label = _text(title, 26, Color(0.85, 0.88, 0.92))
	box.add_child(head)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	_arrow = _text("▲" if to_floor >= from_floor else "▼", 64, Color("#FF9A3C"))
	row.add_child(_arrow)
	_label = _text(_floor_text(from_floor), 84, Color("#FFB062"))
	row.add_child(_label)
	Audio.play_ui(Audio.SFX_CLICK)
	var steps: int = absi(to_floor - from_floor)
	var per: float = minf(FLOOR_S, MAX_S / maxf(float(steps), 1.0))
	var dir: int = 1 if to_floor >= from_floor else -1
	var tween: Tween = create_tween()
	for i: int in steps:
		var f: int = from_floor + dir * (i + 1)
		tween.tween_callback(func() -> void: _label.text = _floor_text(f)).set_delay(per)
	tween.tween_callback(func() -> void:
		_arrow.text = "◆"
		Audio.play_sfx("quest_done", -16.0))
	tween.tween_interval(HOLD_S)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


static func _floor_text(f: int) -> String:
	return "B%d" % -f if f < 0 else ("%dF" % f if f > 0 else "1F")


func _text(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
