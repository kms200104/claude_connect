class_name HudLayout
extends RefCounted
## 화면 비율이 달라도(갤럭시 S24 길쭉한 화면 · Z 폴드7 거의 정사각형 안쪽 화면) 창과 단추가 제자리에 오도록 앵커로 붙인다.
## UI 기준 해상도는 1080×1920 (stretch = canvas_items · expand): 폭이 넓어지거나 높이가 길어져도 가운데·오른쪽·아래에 맞춘다.
## v0.13.4 가로 화면: 논리 높이가 1200 으로 줄어든다(ScreenFit). 세로 기준으로 정한 위쪽 거리(top)·아래 끝(bottom)은
## 화면 높이 비율로 줄여 놓고, 방향이 바뀌면 relayout() 이 다시 맞춘다 (그래서 오른쪽 단추 줄이 화면 밖으로 안 나간다).

const PORTRAIT_HEIGHT: float = 1920.0
const GROUP: StringName = &"hud_layout"


## 세로 기준 y 를 지금 화면 높이에 맞춘다 (세로면 그대로).
static func fit_y(y: float) -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return y
	var h: float = tree.root.get_visible_rect().size.y
	return y if h >= PORTRAIT_HEIGHT - 1.0 else y * h / PORTRAIT_HEIGHT


## 오른쪽 단추 줄의 y: 위쪽(640 위)은 그대로 두고, 아래쪽 단추들(휴대폰 · 감정표현 · 채집 모드)은 서로 간격을 지키며 함께 올린다
## (비율로만 줄이면 단추끼리 겹친다).
static func column_y(y: float) -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return y
	var h: float = tree.root.get_visible_rect().size.y
	if h >= PORTRAIT_HEIGHT - 1.0 or y < 640.0:
		return y
	return maxf(640.0, y - (PORTRAIT_HEIGHT - h) * 0.5)


## 가로 화면일 때만 옆으로 dx 만큼 비킨다 (오른쪽 아래 상황 버튼이 오른쪽 단추 줄과 겹치지 않게). 세로면 처음 자리.
static func landscape_shift(c: Control, dx: float) -> void:
	if not c.has_meta("hud_base_x"):
		c.set_meta("hud_base_x", Vector2(c.offset_left, c.offset_right))
	_remember(c, ["landscape_shift", dx])
	var base: Vector2 = c.get_meta("hud_base_x")
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var wide: bool = tree != null and tree.root != null and tree.root.get_visible_rect().size.x > tree.root.get_visible_rect().size.y
	c.offset_left = base.x + (dx if wide else 0.0)
	c.offset_right = base.y + (dx if wide else 0.0)


## 방향이 바뀌었을 때: 이 도우미로 자리 잡은 컨트롤을 모두 다시 맞춘다.
static func relayout(tree: SceneTree) -> void:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var c: Control = node as Control
		if c == null:
			continue
		var how: Array = c.get_meta("hud_layout", [])
		match str(how[0]) if not how.is_empty() else "":
			"center_top":
				center_top(c, how[1], how[2])
			"center_bottom":
				center_bottom(c, how[1], how[2], how[3])
			"right_top":
				right_top(c, how[1], how[2], how[3])
			"landscape_shift":
				landscape_shift(c, how[1])
		if c.has_meta("hud_bottom"):
			fit_bottom(c, float(c.get_meta("hud_bottom")))


static func _remember(c: Control, how: Array) -> void:
	c.set_meta("hud_layout", how)
	if not c.is_in_group(GROUP):
		c.add_to_group(GROUP)


## 위쪽에 붙인 창의 아래 끝 (세로 기준 y). 가로 화면이면 비율로 줄인다.
static func fit_bottom(c: Control, bottom: float) -> void:
	c.set_meta("hud_bottom", bottom)
	if not c.is_in_group(GROUP):
		c.add_to_group(GROUP)
	c.offset_bottom = fit_y(bottom)


## 위에서 top 만큼, 가로 가운데 (width 폭).
static func center_top(c: Control, width: float, top: float) -> void:
	_remember(c, ["center_top", width, top])
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -width * 0.5
	c.offset_right = width * 0.5
	c.offset_top = fit_y(top)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH


## 아래에서 bottom 만큼 띄워 가로 가운데 (width × height).
static func center_bottom(c: Control, width: float, height: float, bottom: float) -> void:
	_remember(c, ["center_bottom", width, height, bottom])
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -width * 0.5
	c.offset_right = width * 0.5
	# 가로 화면에서 창이 화면보다 높으면 위쪽 여유를 남기고 줄인다.
	var room: float = fit_y(PORTRAIT_HEIGHT) - bottom - 140.0
	c.offset_top = -bottom - minf(height, room)
	c.offset_bottom = -bottom
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 오른쪽 가장자리에서 right 만큼, 위에서 top 만큼 (size 크기).
static func right_top(c: Control, size: Vector2, right: float, top: float) -> void:
	_remember(c, ["right_top", size, right, top])
	top = column_y(top)
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -right - size.x
	c.offset_right = -right
	c.offset_top = top
	c.offset_bottom = top + size.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
