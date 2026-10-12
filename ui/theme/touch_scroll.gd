class_name TouchScroll
extends Node
## 손가락으로 굴리기: 단추 · 카드 위에서 끌어도 그 목록(ScrollContainer)이 굴러간다.
## 휴대폰 앱 · 주방 · 상점 … 어느 창이든 단추가 빽빽해서 빈 곳을 찾아 끌어야 하던 것을 고친다.
## 손가락이 START_PX 넘게 움직이면 그때부터 굴리기로 보고, 누르던 단추의 누름은 취소한다(떼어도 눌리지 않는다).
## 놓으면 빠르기만큼 조금 더 미끄러진다. ScreenFit 이 루트에 하나 붙인다.

## 이만큼(화면 논리 px) 움직여야 굴리기로 본다 (그 전엔 단추 누름).
const START_PX: float = 18.0
## 놓은 뒤 미끄러짐이 줄어드는 빠르기 (1 / 초).
const FLING_DECAY: float = 5.0
const GROUP: StringName = &"touch_scroll"

var _down: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _scroll: ScrollContainer = null
var _dragging: bool = false
var _vertical: bool = true
var _velocity: float = 0.0
var _last_ms: float = 0.0
var _fling: ScrollContainer = null
var _fling_pos: float = 0.0


func _ready() -> void:
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is ScrollContainer:
			node.add_to_group(GROUP))
	for node: Node in get_tree().root.find_children("*", "ScrollContainer", true, false):
		node.add_to_group(GROUP)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).index == 0:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_down = true
			_dragging = false
			_press_at = touch.position
			_scroll = _scroll_at(touch.position)
			_fling = null
		else:
			if _dragging and _scroll != null and is_instance_valid(_scroll):
				_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
				# 놓은 빠르기만큼 더 미끄러진다.
				if absf(_velocity) > 120.0:
					_fling = _scroll
					_fling_pos = float(_scroll.scroll_vertical if _vertical else _scroll.scroll_horizontal)
			_down = false
			_dragging = false
		return
	if event is InputEventScreenDrag and (event as InputEventScreenDrag).index == 0 and _down:
		var drag: InputEventScreenDrag = event
		if _scroll == null or not is_instance_valid(_scroll) or not _scroll.is_visible_in_tree():
			return
		if not _dragging:
			var moved: Vector2 = drag.position - _press_at
			if moved.length() < START_PX or _blocked():
				return
			# 목록이 굴러가는 방향으로 끌 때만 (옆으로 끌어 돌리는 거울 · 밀대 같은 것은 그대로 둔다).
			var v_ok: bool = _can_scroll(_scroll, true) and absf(moved.y) >= absf(moved.x)
			var h_ok: bool = _can_scroll(_scroll, false) and absf(moved.x) > absf(moved.y)
			if not v_ok and not h_ok:
				_scroll = null
				return
			_vertical = v_ok
			_dragging = true
			_velocity = 0.0
			_last_ms = float(Time.get_ticks_msec())
			# 누르던 단추 · 카드의 누름을 취소한다 (떼어도 눌리지 않게).
			_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		var step: float = drag.relative.y if _vertical else drag.relative.x
		if _vertical:
			_scroll.scroll_vertical -= roundi(step)
		else:
			_scroll.scroll_horizontal -= roundi(step)
		var now: float = float(Time.get_ticks_msec())
		var dt: float = maxf((now - _last_ms) / 1000.0, 0.001)
		_velocity = lerpf(_velocity, -step / dt, 0.4)
		_last_ms = now
		get_viewport().set_input_as_handled()
		return
	# 굴리는 동안 마우스로 흉내 낸 움직임은 목록 · 단추에 넘기지 않는다 (두 번 굴러가지 않게).
	if _dragging and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _fling == null:
		return
	if not is_instance_valid(_fling) or not _fling.is_visible_in_tree() or absf(_velocity) < 30.0:
		_fling = null
		return
	_fling_pos += _velocity * delta
	_velocity *= exp(-FLING_DECAY * delta)
	if _vertical:
		_fling.scroll_vertical = roundi(_fling_pos)
	else:
		_fling.scroll_horizontal = roundi(_fling_pos)


## 손가락 아래에서 굴릴 수 있는 가장 안쪽 목록.
func _scroll_at(at: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	var best_depth: int = -1
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var sc: ScrollContainer = node as ScrollContainer
		if sc == null or not sc.is_visible_in_tree():
			continue
		if not (_can_scroll(sc, true) or _can_scroll(sc, false)):
			continue
		var rect: Rect2 = sc.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, sc.size)
		if not rect.has_point(at):
			continue
		var depth: int = sc.get_path().get_name_count()
		if depth > best_depth:
			best = sc
			best_depth = depth
	return best


static func _can_scroll(sc: ScrollContainer, vertical: bool) -> bool:
	if vertical:
		if sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			return false
		var bar: VScrollBar = sc.get_v_scroll_bar()
		return bar.max_value - bar.page > 1.0
	if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return false
	var hbar: HScrollBar = sc.get_h_scroll_bar()
	return hbar.max_value - hbar.page > 1.0


## 끌어서 쓰는 컨트롤(밀대 · 글 상자 · 스크롤 막대) 위에서 시작했으면 굴리지 않는다.
func _blocked() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	return hovered is Range or hovered is TextEdit or hovered is LineEdit or hovered is ItemList or hovered is Tree
