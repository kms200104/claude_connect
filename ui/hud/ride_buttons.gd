class_name RideButtons
extends Control
## 탈것 버튼 조작 (설정 "탈것 조작: 버튼", Prefs.RIDE_CONTROL): 타는 동안 조이스틱 대신
## 왼쪽 ▲ 가속 · ▼ 브레이크, 오른쪽 ◀ ▶ 핸들 (조이스틱을 오른쪽에 두는 설정이면 좌우가 바뀐다).
## 손가락마다(터치 index) 따로 잡아 ▲ 를 누른 채 ◀ 도 누를 수 있다. 마우스는 터치로 흉내 낸다 (emulate_touch_from_mouse).
## 버튼 입력은 조이스틱과 같은 (가고 싶은 방향, 세기)로 바꿔 탈것에 넘긴다 (drive_input) — 탈것마다 따로 고칠 필요가 없다.

const PAD: Color = Color(0.2, 0.16, 0.14, 0.32)
const PAD_ON: Color = Color(1.0, 0.72, 0.35, 0.75)
const RIM: Color = Color(1, 1, 1, 0.6)
const INK: Color = Color(1, 1, 1, 0.95)
## ◀ ▶ 를 누르면 지금 방향에서 이만큼 옆을 가고 싶은 방향으로 준다 (탈것이 낼 수 있는 만큼 꺾는다).
const STEER_ANGLE: float = 0.7
## 가속 없이 핸들만 꺾을 때의 세기 (천천히 돌며 나아간다).
const CREEP: float = 0.3

enum Pad { UP, DOWN, LEFT, RIGHT }

## -1 · 0 · 1 (▼ · 없음 · ▲).
var throttle: int = 0
## -1 · 0 · 1 (◀ · 없음 · ▶).
var steer: int = 0

## 터치 index → 누르고 있는 패드.
var _touches: Dictionary[int, Pad] = {}


func _ready() -> void:
	name = "RideButtons"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## 보이기 · 감추기 (감추면 누르던 것을 모두 놓는다).
func set_shown(on: bool) -> void:
	if visible == on:
		return
	visible = on
	_touches.clear()
	_refresh()


## 패드 자리 (화면 좌표). 왼쪽 = 가속 · 브레이크, 오른쪽 = 핸들 (조이스틱을 오른쪽에 두면 반대).
func pad_rect(pad: Pad) -> Rect2:
	var s: Vector2 = get_viewport_rect().size
	var swap: bool = Prefs.stick_on_right()
	var pedal_x: float = 70.0 if not swap else s.x - 270.0
	# 핸들은 감정표현 단추 아래 · 상황 버튼(세우기) 위 사이에.
	var wheel_x: float = s.x - 470.0 if not swap else 70.0
	match pad:
		Pad.UP:
			return Rect2(pedal_x, s.y - 630.0, 200.0, 180.0)
		Pad.DOWN:
			return Rect2(pedal_x, s.y - 430.0, 200.0, 160.0)
		Pad.LEFT:
			return Rect2(wheel_x, s.y - 646.0, 190.0, 140.0)
	return Rect2(wheel_x + 210.0, s.y - 646.0, 190.0, 140.0)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			var pad: int = _pad_at(touch.position)
			if pad >= 0:
				_touches[touch.index] = pad as Pad
				get_viewport().set_input_as_handled()
				Prefs.vibrate(12, 0.3)
		elif _touches.has(touch.index):
			_touches.erase(touch.index)
			get_viewport().set_input_as_handled()
		_refresh()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _touches.has(drag.index):
			# 손가락을 옆 패드로 미끄러뜨리면 그 패드로 (◀ → ▶ 를 떼지 않고 바꾸기).
			var pad2: int = _pad_at(drag.position)
			if pad2 >= 0:
				_touches[drag.index] = pad2 as Pad
			get_viewport().set_input_as_handled()
			_refresh()


func _pad_at(pos: Vector2) -> int:
	for pad: Pad in [Pad.UP, Pad.DOWN, Pad.LEFT, Pad.RIGHT]:
		if pad_rect(pad).grow(4.0).has_point(pos):
			return pad
	return -1


func _refresh() -> void:
	var held: Array = _touches.values()
	throttle = (1 if Pad.UP in held else 0) - (1 if Pad.DOWN in held else 0)
	steer = (1 if Pad.RIGHT in held else 0) - (1 if Pad.LEFT in held else 0)
	queue_redraw()


## 버튼 → 탈것이 받는 (가고 싶은 방향, 세기). yaw = 지금 탈것 방향 (Node3D.rotation.y), speed = 지금 빠르기.
## ▲ = 앞으로 (◀ ▶ 면 그쪽으로 꺾으며), ▼ = 달리는 중이면 브레이크, 핸들만 = 천천히 돌며 나아감.
static func drive_input(yaw: float, speed: float, throttle_in: int, steer_in: int) -> Array:
	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	# + yaw = 왼쪽으로 돈다. ◀(steer -1) 이면 yaw + STEER_ANGLE.
	var aim: float = yaw - float(steer_in) * STEER_ANGLE
	var aimed: Vector3 = Vector3(-sin(aim), 0.0, -cos(aim))
	if throttle_in > 0:
		return [aimed, 1.0]
	if throttle_in < 0:
		return [-forward, 1.0] if speed > 0.3 else [Vector3.ZERO, 0.0]
	if steer_in != 0:
		return [aimed, CREEP]
	return [Vector3.ZERO, 0.0]


func _draw() -> void:
	var held: Array = _touches.values()
	var font: Font = get_theme_default_font()
	var words: Dictionary[Pad, String] = {Pad.UP: "가속", Pad.DOWN: "브레이크", Pad.LEFT: "왼쪽", Pad.RIGHT: "오른쪽"}
	for pad: Pad in [Pad.UP, Pad.DOWN, Pad.LEFT, Pad.RIGHT]:
		var r: Rect2 = pad_rect(pad)
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = PAD_ON if pad in held else PAD
		box.border_color = RIM
		box.set_border_width_all(4)
		box.set_corner_radius_all(40)
		draw_style_box(box, r)
		# 화살표는 글꼴(이모지로 바뀌는 ◀▶) 대신 삼각형으로 그린다.
		var c: Vector2 = r.get_center() - Vector2(0.0, 12.0)
		var dir: Vector2 = {Pad.UP: Vector2.UP, Pad.DOWN: Vector2.DOWN, Pad.LEFT: Vector2.LEFT, Pad.RIGHT: Vector2.RIGHT}[pad]
		var side_v: Vector2 = dir.orthogonal()
		var tri: PackedVector2Array = [c + dir * 30.0, c - dir * 20.0 + side_v * 30.0, c - dir * 20.0 - side_v * 30.0]
		draw_colored_polygon(tri, INK)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.2, 0.16, 0.14, 0.5), 3.0, true)
		var w: String = words[pad]
		var ww: float = font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string_outline(font, Vector2(r.get_center().x - ww * 0.5, r.end.y - 16.0), w, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color(0.2, 0.16, 0.14, 0.6))
		draw_string(font, Vector2(r.get_center().x - ww * 0.5, r.end.y - 16.0), w, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
