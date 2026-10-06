class_name PhoneAppIcon
extends Button
## 휴대폰 홈 화면의 앱 아이콘 (v0.14): 둥근 네모 바탕(위가 밝은 광택) 위에 앱마다 그린 흰 그림.
## 누르면 톡 눌렸다가 돌아온다. 같은 그림 그리기로 아래 막대의 뒤로 · 홈 · 닫기 단추도 그린다 (kind = "nav_*").

## stocks · homes · bank · assets · talk · jobs · delivery · nav_back · nav_home · nav_close
var kind: String = ""
var tint: Color = Color.WHITE
var _press: Tween = null


func _init(icon_kind: String = "", color: Color = Color.WHITE, size_px: float = 150.0) -> void:
	kind = icon_kind
	tint = color
	focus_mode = Control.FOCUS_NONE
	flat = true
	custom_minimum_size = Vector2(size_px, size_px)
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)
	button_down.connect(func() -> void: _squash(0.88))
	button_up.connect(func() -> void: _squash(1.0))
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _squash(to: float) -> void:
	if _press != null:
		_press.kill()
	_press = create_tween()
	_press.tween_property(self, "scale", Vector2.ONE * to, 0.08 if to < 1.0 else 0.18).set_trans(Tween.TRANS_BACK if to >= 1.0 else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var o: Vector2 = (size - Vector2(s, s)) * 0.5
	if kind.begins_with("nav_"):
		_draw_nav(o, s)
		return
	# 그림자 · 바탕 · 위쪽 광택.
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = tint
	bg.set_corner_radius_all(int(s * 0.26))
	bg.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	bg.shadow_size = int(s * 0.05)
	bg.shadow_offset = Vector2(0.0, s * 0.03)
	bg.border_color = tint.darkened(0.12)
	bg.set_border_width_all(int(maxf(2.0, s * 0.015)))
	draw_style_box(bg, Rect2(o, Vector2(s, s)))
	var gloss: StyleBoxFlat = StyleBoxFlat.new()
	gloss.bg_color = Color(1.0, 1.0, 1.0, 0.22)
	gloss.corner_radius_top_left = int(s * 0.24)
	gloss.corner_radius_top_right = int(s * 0.24)
	gloss.corner_radius_bottom_left = int(s * 0.5)
	gloss.corner_radius_bottom_right = int(s * 0.5)
	draw_style_box(gloss, Rect2(o + Vector2(s * 0.06, s * 0.04), Vector2(s * 0.88, s * 0.42)))
	var ink: Color = Color("#5A3A18") if kind == "talk" else Color.WHITE
	_glyph(o, s, ink)


## 앱 그림 (흰 선 · 면). 좌표는 아이콘 크기 s 에 대한 비율.
func _glyph(o: Vector2, s: float, ink: Color) -> void:
	var p: Callable = func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w: float = maxf(2.0, s * 0.045)
	match kind:
		"stocks":
			# 촛대 셋 + 오르는 꺾은선 화살표.
			for c: Array in [[0.28, 0.58, 0.72], [0.45, 0.5, 0.66], [0.62, 0.38, 0.56]]:
				draw_line(p.call(c[0], c[1] - 0.06), p.call(c[0], c[2] + 0.06), Color(ink, 0.7), w * 0.6, true)
				draw_rect(Rect2(p.call(c[0] - 0.045, c[1]), Vector2(0.09, c[2] - c[1]) * s), Color(ink, 0.75))
			var line: PackedVector2Array = PackedVector2Array([p.call(0.2, 0.74), p.call(0.4, 0.56), p.call(0.54, 0.62), p.call(0.78, 0.3)])
			draw_polyline(line, ink, w * 1.3, true)
			draw_colored_polygon(PackedVector2Array([p.call(0.84, 0.22), p.call(0.82, 0.4), p.call(0.66, 0.28)]), ink)
		"homes":
			# 아파트 두 동 + 창문.
			draw_rect(Rect2(p.call(0.2, 0.32), Vector2(0.3, 0.5) * s), ink)
			draw_rect(Rect2(p.call(0.52, 0.44), Vector2(0.28, 0.38) * s), Color(ink, 0.85))
			for r: int in 4:
				for c: int in 2:
					draw_rect(Rect2(p.call(0.25 + c * 0.12, 0.37 + r * 0.1), Vector2(0.07, 0.06) * s), tint)
			for r: int in 3:
				draw_rect(Rect2(p.call(0.58, 0.5 + r * 0.1), Vector2(0.16, 0.05) * s), tint)
			draw_rect(Rect2(p.call(0.14, 0.82), Vector2(0.72, 0.04) * s), ink)
		"bank":
			# 지붕 삼각형 · 기둥 셋 · 받침 + 동전.
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.18), p.call(0.84, 0.36), p.call(0.16, 0.36)]), ink)
			for x: float in [0.27, 0.45, 0.63]:
				draw_rect(Rect2(p.call(x, 0.42), Vector2(0.1, 0.3) * s), ink)
			draw_rect(Rect2(p.call(0.16, 0.74), Vector2(0.68, 0.08) * s), ink)
			draw_circle(p.call(0.5, 0.3), s * 0.045, tint)
		"assets":
			# 원그래프: 한 조각이 빠져나와 있다.
			draw_circle(p.call(0.47, 0.54), s * 0.27, ink)
			var c: Vector2 = p.call(0.47, 0.54)
			var wedge: PackedVector2Array = PackedVector2Array([c])
			for i: int in 9:
				var a: float = -PI * 0.5 + (PI * 0.5) * float(i) / 8.0
				wedge.append(c + Vector2(cos(a), sin(a)) * s * 0.285)
			draw_colored_polygon(wedge, tint)
			var off: Vector2 = Vector2(0.06, -0.06) * s
			var piece: PackedVector2Array = PackedVector2Array([c + off])
			for i: int in 9:
				var a: float = -PI * 0.5 + (PI * 0.5) * float(i) / 8.0
				piece.append(c + off + Vector2(cos(a), sin(a)) * s * 0.25)
			draw_colored_polygon(piece, Color(ink, 0.85))
		"talk":
			# 말풍선 + TALK.
			var bubble: PackedVector2Array = PackedVector2Array()
			for i: int in 28:
				var a: float = TAU * float(i) / 28.0
				bubble.append(p.call(0.5 + cos(a) * 0.33, 0.47 + sin(a) * 0.26))
			draw_colored_polygon(bubble, ink)
			draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.64), p.call(0.4, 0.68), p.call(0.24, 0.82)]), ink)
			var font: Font = get_theme_default_font()
			var fs: int = int(s * 0.17)
			var text_w: float = font.get_string_size("TALK", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, p.call(0.5, 0.53) - Vector2(text_w * 0.5, 0.0), "TALK", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
		"jobs":
			# 서류 가방.
			var bag: StyleBoxFlat = StyleBoxFlat.new()
			bag.bg_color = ink
			bag.set_corner_radius_all(int(s * 0.07))
			draw_style_box(bag, Rect2(p.call(0.18, 0.36), Vector2(0.64, 0.42) * s))
			draw_arc(p.call(0.5, 0.36), s * 0.1, PI, TAU, 12, ink, w * 1.2, true)
			draw_rect(Rect2(p.call(0.18, 0.52), Vector2(0.64, 0.05) * s), tint)
			draw_rect(Rect2(p.call(0.45, 0.49), Vector2(0.1, 0.1) * s), Color(ink, 0.9))
		"delivery":
			# 상자 + 달리는 선.
			draw_colored_polygon(PackedVector2Array([p.call(0.38, 0.36), p.call(0.82, 0.36), p.call(0.82, 0.76), p.call(0.38, 0.76)]), ink)
			draw_colored_polygon(PackedVector2Array([p.call(0.38, 0.36), p.call(0.48, 0.24), p.call(0.9, 0.24), p.call(0.82, 0.36)]), Color(ink, 0.8))
			draw_rect(Rect2(p.call(0.56, 0.36), Vector2(0.08, 0.4) * s), tint)
			for i: int in 3:
				draw_line(p.call(0.12 + i * 0.03, 0.44 + i * 0.1), p.call(0.3, 0.44 + i * 0.1), ink, w, true)


## 아래 막대 단추: 뒤로(◁) · 홈(○) · 닫기(✕).
func _draw_nav(o: Vector2, s: float) -> void:
	var c: Vector2 = o + Vector2(s, s) * 0.5
	var ink: Color = tint
	var w: float = maxf(3.0, s * 0.07)
	if is_hovered() or button_pressed:
		draw_circle(c, s * 0.42, Color(ink, 0.12))
	match kind:
		"nav_back":
			var r: float = s * 0.2
			draw_polyline(PackedVector2Array([c + Vector2(r * 0.6, -r), c + Vector2(-r * 0.7, 0.0), c + Vector2(r * 0.6, r), c + Vector2(r * 0.6, -r)]), ink, w, true)
		"nav_home":
			draw_arc(c, s * 0.19, 0.0, TAU, 32, ink, w, true)
		"nav_close":
			var r: float = s * 0.15
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), ink, w, true)
			draw_line(c + Vector2(r, -r), c + Vector2(-r, r), ink, w, true)
