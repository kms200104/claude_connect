class_name MeteorOverlay
extends Control
## 유성우: 세로 화면 카메라는 하늘을 거의 비추지 않으므로, 화면 위쪽에 별똥별 꼬리를 그린다 (HUD 맨 뒤, 터치는 통과).
## 유성우 이벤트가 열려 있고 밤이며 실내가 아닐 때만. 가끔 반짝 소리.

@export var sky: SkyController
## 별똥별 사이 간격 (초).
@export var interval: Vector2 = Vector2(0.35, 1.3)

class Streak:
	var start: Vector2
	var dir: Vector2
	var length: float
	var age: float = 0.0
	var life: float = 0.8

var _streaks: Array[Streak] = []
var _next: float = 0.0
var _twinkle_cooldown: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_showing() -> bool:
	return Net.event_active(EventInfo.METEOR_SHOWER) != null and (sky == null or (sky.daylight < 0.35 and not sky.indoor))


func _process(delta: float) -> void:
	var on: bool = Net.state == Net.State.ONLINE and is_showing()
	_next -= delta
	_twinkle_cooldown -= delta
	if on and _next <= 0.0:
		_next = randf_range(interval.x, interval.y)
		var s: Streak = Streak.new()
		s.start = Vector2(randf_range(size.x * 0.1, size.x * 1.1), randf_range(-40.0, size.y * 0.3))
		s.dir = Vector2(-1.0, randf_range(0.45, 0.75)).normalized()
		s.length = randf_range(180.0, 360.0)
		s.life = randf_range(0.6, 1.0)
		_streaks.append(s)
		if _twinkle_cooldown <= 0.0:
			_twinkle_cooldown = 4.0
			Audio.play_sfx("twinkle", -12.0, randf_range(0.9, 1.2))
	for s: Streak in _streaks:
		s.age += delta
	_streaks = _streaks.filter(func(s: Streak) -> bool: return s.age < s.life)
	queue_redraw()


func _draw() -> void:
	for s: Streak in _streaks:
		var t: float = s.age / s.life
		var head: Vector2 = s.start + s.dir * (t * 900.0)
		var fade: float = sin(t * PI)
		# 꼬리: 머리에서 멀어질수록 가늘고 흐리게, 마디 몇 개로.
		var segments: int = 8
		for i: int in segments:
			var a: float = float(i) / segments
			var b: float = float(i + 1) / segments
			var p0: Vector2 = head - s.dir * s.length * a
			var p1: Vector2 = head - s.dir * s.length * b
			var color: Color = Color(1.0, 0.95, 0.75, fade * (1.0 - a) * 0.9)
			draw_line(p0, p1, color, lerpf(6.0, 1.0, a), true)
		draw_circle(head, 5.0, Color(1.0, 1.0, 0.9, fade))
