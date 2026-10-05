class_name MeterBar
extends Control
## 가로 막대 (0~1). ProgressBar + StyleBoxFlat 채움은 둥근 모서리·아래 테두리 때문에 채움이 막대 밖으로 길게
## 그려지는 경우가 있어(은행 신용점수 막대), 자기 크기 안에서만 직접 그린다.

@export_range(0.0, 1.0) var ratio: float = 0.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var fill_color: Color = Color("#5AAE6A"):
	set(v):
		fill_color = v
		queue_redraw()
@export var back_color: Color = Color(0.85, 0.8, 0.72)
@export var edge_color: Color = Color(0.75, 0.66, 0.54)


static func make(height: float, value: float, color: Color) -> MeterBar:
	var bar: MeterBar = MeterBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.ratio = value
	bar.fill_color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)


func _draw() -> void:
	var r: float = size.y * 0.5
	var back: StyleBoxFlat = StyleBoxFlat.new()
	back.bg_color = back_color
	back.border_color = edge_color
	back.set_border_width_all(1)
	back.set_corner_radius_all(int(r))
	draw_style_box(back, Rect2(Vector2.ZERO, size))
	if ratio <= 0.0:
		return
	var inset: float = 2.0
	var w: float = maxf((size.x - inset * 2.0) * ratio, size.y - inset * 2.0)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(int(r - inset))
	draw_style_box(fill, Rect2(Vector2(inset, inset), Vector2(w, size.y - inset * 2.0)))
