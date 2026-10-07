class_name TouchJoystick
extends Control
## 터치 조이스틱. 화면 왼쪽 아래 영역을 누르면 반응하고, `output`에 방향(0~1)을 담는다.
## v16 설정: 오른쪽(왼손잡이)으로 옮기고 크기를 바꿀 수 있다 (Prefs.STICK_SIDE · STICK_SIZE) — 그러면 상황 버튼은 왼쪽 아래로 간다.
## x: 오른쪽 +, y: 아래 + (위로 밀면 y < 0). 마우스는 emulate_touch_from_mouse로 터치처럼 동작한다.

@export_group("Shape")
@export_range(40.0, 300.0, 1.0, "suffix:px") var radius: float = 140.0
@export_range(20.0, 200.0, 1.0, "suffix:px") var knob_radius: float = 60.0

@export_group("Response")
## 이 비율(0~1) 이하의 입력은 무시한다.
@export_range(0.0, 0.9, 0.01) var dead_zone: float = 0.12
## 1 = 선형, 1보다 크면 약하게 밀 때 더 느리게(섬세한 조작).
@export_range(0.5, 3.0, 0.05) var response_power: float = 1.4

@export_group("Placement")
## true: 터치한 지점에 조이스틱이 생긴다. false: 아래 대기 위치에 고정.
@export var floating: bool = true
## 대기(고정) 위치. 화면 크기 대비 비율.
@export var idle_position_ratio: Vector2 = Vector2(0.25, 0.80)
## 터치를 받는 영역. 화면 크기 대비 (가로 최대, 세로 최소) 비율 — 왼쪽 아래 사각형.
@export var activation_max_x_ratio: float = 0.6
@export var activation_min_y_ratio: float = 0.45

@export_group("Look")
@export var base_color: Color = Color(1, 1, 1, 0.18)
@export var rim_color: Color = Color(1, 1, 1, 0.45)
@export var knob_color: Color = Color(1, 1, 1, 0.65)
@export var idle_alpha_scale: float = 0.6

var output: Vector2 = Vector2.ZERO
## 달리는 중이면 테두리를 주황빛으로 (Player 가 켠다).
var boost: bool = false:
	set(value):
		if boost != value:
			boost = value
			queue_redraw()

@export var boost_color: Color = Color(1.0, 0.65, 0.25, 0.9)

var _touch_index: int = -1
var _center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
## 설정 전의 크기 (설정 배율을 곱한다).
var _base_radius: float = 0.0
var _base_knob: float = 0.0
## 오른쪽에 둘지 (설정).
var _right: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base_radius = radius
	_base_knob = knob_radius
	get_viewport().size_changed.connect(_reset_to_idle)
	Prefs.events.changed.connect(func(key: String) -> void:
		if key == Prefs.STICK_SIDE or key == Prefs.STICK_SIZE:
			apply_prefs())
	apply_prefs()


## 설정(왼쪽/오른쪽 · 크기)을 적용한다. 오른쪽이면 상황 버튼(ActionHud)을 왼쪽 아래로 옮긴다.
func apply_prefs() -> void:
	_right = Prefs.stick_on_right()
	radius = _base_radius * Prefs.stick_scale()
	knob_radius = _base_knob * Prefs.stick_scale()
	# 형제(상황 · 낚시 버튼)가 아직 준비 전일 수 있어 다음 프레임에.
	_move_buttons.call_deferred()
	_release()


func _move_buttons() -> void:
	var hud: Node = get_parent()
	var action: ActionHud = hud.get_node_or_null("ActionHud") as ActionHud if hud != null else null
	if action != null:
		action.set_left_side(_right)
	var fishing: FishingHud = hud.get_node_or_null("FishingHud") as FishingHud if hud != null else null
	if fishing != null:
		fishing.set_left_side(_right)


## 지금 대기 자리 (테스트용, 화면 좌표).
func idle_center() -> Vector2:
	return _center


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _touch_index == -1 and _in_activation_area(touch.position):
				_touch_index = touch.index
				if floating:
					_center = touch.position
				_update_stick(touch.position)
		elif touch.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_index:
			_update_stick(drag.position)


## 이 터치(index)를 조이스틱이 쓰고 있는지 (1인칭 둘러보기가 조이스틱 손가락은 건너뛴다).
func owns_touch(index: int) -> bool:
	return _touch_index != -1 and _touch_index == index


func _in_activation_area(pos: Vector2) -> bool:
	# 퀵슬롯·가방·대화 창·상황 버튼 위를 누른 건 조이스틱이 아니다 (그 컨트롤들은 "blocks_joystick" 그룹).
	for node: Node in get_tree().get_nodes_in_group(&"blocks_joystick"):
		var control: Control = node as Control
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return false
	var size_px: Vector2 = get_viewport_rect().size
	if not floating:
		return pos.distance_to(_center) <= radius * 1.5
	var x_ok: bool = pos.x >= size_px.x * (1.0 - activation_max_x_ratio) if _right else pos.x <= size_px.x * activation_max_x_ratio
	return x_ok and pos.y >= size_px.y * activation_min_y_ratio


func _update_stick(pos: Vector2) -> void:
	var offset: Vector2 = (pos - _center).limit_length(radius)
	_knob_offset = offset
	var amount: float = offset.length() / radius
	if amount < dead_zone:
		output = Vector2.ZERO
	else:
		var strength: float = pow((amount - dead_zone) / (1.0 - dead_zone), response_power)
		output = offset.normalized() * strength
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	output = Vector2.ZERO
	_reset_to_idle()


func _reset_to_idle() -> void:
	_knob_offset = Vector2.ZERO
	var ratio: Vector2 = Vector2(1.0 - idle_position_ratio.x, idle_position_ratio.y) if _right else idle_position_ratio
	_center = get_viewport_rect().size * ratio
	queue_redraw()


func _draw() -> void:
	var scale_a: float = 1.0 if _touch_index != -1 else idle_alpha_scale
	var base: Color = Color(base_color, base_color.a * scale_a)
	var rim: Color = Color(rim_color, rim_color.a * scale_a)
	var knob: Color = Color(knob_color, knob_color.a * scale_a)
	draw_circle(_center, radius, base)
	draw_arc(_center, radius, 0.0, TAU, 64, boost_color if boost else rim, 8.0 if boost else 4.0, true)
	draw_circle(_center + _knob_offset, knob_radius, knob)
