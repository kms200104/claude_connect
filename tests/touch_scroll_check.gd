extends Node
## 손가락으로 굴리기 검사 (TouchScroll): 단추가 빽빽한 목록에서 단추 위를 끌어도 목록이 굴러가고 그 단추는 눌리지 않는다.
## 그냥 톡 누르면 단추가 눌린다. 사용: godot --headless --path . res://tests/touch_scroll_check.tscn

var _failed: int = 0
var _pressed: int = 0


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(100, 100)
	scroll.size = Vector2(600, 800)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var first: Button = null
	for i: int in 30:
		var b: Button = Button.new()
		b.text = "단추 %d" % i
		b.custom_minimum_size = Vector2(0, 100)
		b.pressed.connect(func() -> void: _pressed += 1)
		col.add_child(b)
		if first == null:
			first = b
	for i: int in 3:
		await get_tree().process_frame
	var at: Vector2 = first.get_global_rect().get_center()
	# 끌기: 단추 위에서 눌러 위로 300px 끌고 뗀다.
	await _touch(at, true)
	for k: int in 10:
		await _drag(at - Vector2(0.0, 30.0 * float(k + 1)), Vector2(0.0, -30.0))
	await _touch(at - Vector2(0.0, 300.0), false)
	for i: int in 3:
		await get_tree().process_frame
	_check(scroll.scroll_vertical >= 250, "단추 위를 끌면 목록이 굴러간다 (%d)" % scroll.scroll_vertical)
	_check(_pressed == 0, "끌던 단추는 눌리지 않는다 (%d)" % _pressed)
	# 끌었다가 같은 단추 위로 돌아와 떼도 눌리지 않는다 (굴리기가 누름을 취소했다).
	await get_tree().create_timer(1.2).timeout
	var back_target: Button = _visible_button(scroll, col)
	var start: Vector2 = back_target.get_global_rect().get_center()
	await _touch(start, true)
	for k: int in 6:
		await _drag(start + Vector2(0.0, 20.0 * float(k + 1)), Vector2(0.0, 20.0))
	for k: int in 6:
		await _drag(start + Vector2(0.0, 120.0 - 20.0 * float(k + 1)), Vector2(0.0, -20.0))
	await _touch(start, false)
	await get_tree().process_frame
	_check(_pressed == 0, "끌다가 제자리로 돌아와 떼도 단추는 눌리지 않는다 (%d)" % _pressed)
	await get_tree().create_timer(1.2).timeout
	# 톡: 그냥 누르고 떼면 단추가 눌린다.
	await get_tree().create_timer(0.8).timeout
	# 놓은 뒤 미끄러져 멈춘 목록에서 지금 보이는 단추를 누른다.
	var target: Button = _visible_button(scroll, col)
	var tap: Vector2 = target.get_global_rect().get_center()
	await _touch(tap, true)
	await _touch(tap, false)
	await get_tree().process_frame
	_check(_pressed == 1, "톡 누르면 단추가 눌린다 (%d)" % _pressed)
	print("TOUCHSCROLL %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)


func _visible_button(scroll: ScrollContainer, col: VBoxContainer) -> Button:
	var view: Rect2 = scroll.get_global_rect().grow(-60.0)
	for c: Node in col.get_children():
		if view.has_point((c as Button).get_global_rect().get_center()):
			return c as Button
	return null


## 화면(창) 좌표로 바꿔 진짜 손가락처럼 Input 으로 넣는다 (마우스 흉내도 함께 생긴다).
func _window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(p: Vector2, down: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = 0
	e.position = _window(p)
	e.pressed = down
	Input.parse_input_event(e)
	await get_tree().process_frame


func _drag(p: Vector2, rel: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = 0
	e.position = _window(p)
	e.relative = rel * get_viewport().get_final_transform().get_scale()
	Input.parse_input_event(e)
	await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("[touch] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1
