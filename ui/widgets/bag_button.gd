class_name BagButton
extends Button
## 가방 모양 아이콘 버튼 (그림 파일 없이 직접 그린다: 손잡이 고리 + 둥근 몸통 + 덮개 + 단추).

@export var body_color: Color = Color(0.86, 0.6, 0.36)
@export var outline_color: Color = Color(0.48, 0.3, 0.18)
@export var flap_color: Color = Color(0.74, 0.48, 0.28)


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "가방"


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var pressed_offset: float = 4.0 if is_pressed() else 0.0
	var body: Rect2 = Rect2(Vector2(w * 0.14, h * 0.32 + pressed_offset), Vector2(w * 0.72, h * 0.6))
	# 손잡이
	draw_arc(Vector2(w * 0.5, body.position.y + 2.0), w * 0.2, PI, TAU, 24, outline_color, 9.0, true)
	# 몸통
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = body_color
	box.border_color = outline_color
	box.set_border_width_all(5)
	box.set_corner_radius_all(int(w * 0.16))
	draw_style_box(box, body)
	# 덮개와 단추
	var flap: Rect2 = Rect2(body.position + Vector2(5, 5), Vector2(body.size.x - 10, body.size.y * 0.38))
	var flap_box: StyleBoxFlat = StyleBoxFlat.new()
	flap_box.bg_color = flap_color
	flap_box.corner_radius_top_left = int(w * 0.13)
	flap_box.corner_radius_top_right = int(w * 0.13)
	flap_box.corner_radius_bottom_left = int(w * 0.2)
	flap_box.corner_radius_bottom_right = int(w * 0.2)
	draw_style_box(flap_box, flap)
	draw_circle(Vector2(w * 0.5, flap.end.y), w * 0.055, Color(1.0, 0.86, 0.45))
	draw_arc(Vector2(w * 0.5, flap.end.y), w * 0.055, 0.0, TAU, 16, outline_color, 3.0, true)
