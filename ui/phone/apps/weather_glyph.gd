class_name WeatherGlyph
extends Control
## 날씨 그림 (v16 날씨 · 달력 앱): 해 · 구름 · 비 · 천둥번개 (밤이면 해 대신 달). 크기에 맞춰 그린다.

var kind: String = "clear":
	set(v):
		kind = v
		queue_redraw()
var night: bool = false:
	set(v):
		night = v
		queue_redraw()

const SUN: Color = Color("#F6B73C")
const MOON: Color = Color("#F3E6A8")
const CLOUD: Color = Color("#FFFFFF")
const CLOUD_DARK: Color = Color("#A9B3C2")
const RAIN: Color = Color("#4C8FE0")
const BOLT: Color = Color("#FFD23A")


static func make(weather: String, size_px: float, is_night: bool = false) -> WeatherGlyph:
	var g: WeatherGlyph = WeatherGlyph.new()
	g.kind = weather
	g.night = is_night
	g.custom_minimum_size = Vector2(size_px, size_px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## 날씨 이름.
static func name_of(weather: String) -> String:
	return {"clear": "맑음", "cloudy": "흐림", "rain": "비", "thunder": "천둥번개"}.get(weather, weather)


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var o: Vector2 = (size - Vector2(s, s)) * 0.5
	var p: Callable = func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match kind:
		"clear":
			_sun_or_moon(p.call(0.5, 0.5), s * 0.24, s)
		"cloudy":
			_sun_or_moon(p.call(0.36, 0.36), s * 0.17, s)
			_cloud(p.call(0.56, 0.6), s * 0.62, CLOUD)
		"rain":
			_cloud(p.call(0.5, 0.42), s * 0.7, CLOUD_DARK.lightened(0.25))
			for i: int in 3:
				var x: float = 0.32 + i * 0.18
				draw_line(p.call(x, 0.66), p.call(x - 0.05, 0.84), RAIN, maxf(2.0, s * 0.05), true)
		"thunder":
			_cloud(p.call(0.5, 0.4), s * 0.72, CLOUD_DARK)
			draw_colored_polygon(PackedVector2Array([p.call(0.52, 0.52), p.call(0.4, 0.74), p.call(0.5, 0.74), p.call(0.44, 0.94), p.call(0.64, 0.66), p.call(0.53, 0.66), p.call(0.6, 0.52)]), BOLT)
		_:
			_cloud(p.call(0.5, 0.5), s * 0.6, CLOUD)


func _sun_or_moon(c: Vector2, r: float, s: float) -> void:
	if night:
		draw_circle(c, r, MOON)
		# 초승달: 겹친 원을 살짝 어둡게.
		draw_circle(c + Vector2(r * 0.42, -r * 0.28), r * 0.78, Color(0.25, 0.28, 0.42, 0.55))
		return
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		draw_line(c + Vector2(cos(a), sin(a)) * r * 1.3, c + Vector2(cos(a), sin(a)) * r * 1.65, SUN, maxf(2.0, s * 0.045), true)
	draw_circle(c, r, SUN)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.35))


func _cloud(c: Vector2, w: float, color: Color) -> void:
	var edge: Color = color.darkened(0.12)
	for pass_i: int in 2:
		var col: Color = edge if pass_i == 0 else color
		var grow: float = 2.0 if pass_i == 0 else 0.0
		draw_circle(c + Vector2(-w * 0.24, w * 0.06), w * 0.2 + grow, col)
		draw_circle(c + Vector2(0.0, -w * 0.08), w * 0.27 + grow, col)
		draw_circle(c + Vector2(w * 0.25, w * 0.07), w * 0.19 + grow, col)
		draw_rect(Rect2(c + Vector2(-w * 0.24, w * 0.02), Vector2(w * 0.5, w * 0.24 + grow)), col)
