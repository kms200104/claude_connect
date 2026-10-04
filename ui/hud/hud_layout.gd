class_name HudLayout
extends RefCounted
## 화면 비율이 달라도(갤럭시 S24 길쭉한 화면 · Z 폴드7 거의 정사각형 안쪽 화면) 창과 단추가 제자리에 오도록 앵커로 붙인다.
## UI 기준 해상도는 1080×1920 (stretch = canvas_items · expand): 폭이 넓어지거나 높이가 길어져도 가운데·오른쪽·아래에 맞춘다.


## 위에서 top 만큼, 가로 가운데 (width 폭).
static func center_top(c: Control, width: float, top: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -width * 0.5
	c.offset_right = width * 0.5
	c.offset_top = top
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH


## 아래에서 bottom 만큼 띄워 가로 가운데 (width × height).
static func center_bottom(c: Control, width: float, height: float, bottom: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -width * 0.5
	c.offset_right = width * 0.5
	c.offset_top = -bottom - height
	c.offset_bottom = -bottom
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 오른쪽 가장자리에서 right 만큼, 위에서 top 만큼 (size 크기).
static func right_top(c: Control, size: Vector2, right: float, top: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -right - size.x
	c.offset_right = -right
	c.offset_top = top
	c.offset_bottom = top + size.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
