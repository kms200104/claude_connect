class_name PriceChart
extends Control
## 분 단위 시세 선 그래프 (증권 앱). 기준가(어제 종가) 점선 위면 빨강, 아래면 파랑 — 한국 증권 앱 색.

const UP: Color = Color("#E0483A")
const DOWN: Color = Color("#3A6FD8")
const GRID: Color = Color(0.45, 0.36, 0.26, 0.25)
const INK: Color = Color(0.36, 0.24, 0.14)

var prices: PackedInt64Array = []
var ref: int = 0


func set_data(new_prices: PackedInt64Array, new_ref: int) -> void:
	prices = new_prices
	ref = new_ref
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2(8.0, 8.0), size - Vector2(16.0, 40.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, 0.55), true)
	if prices.size() < 2:
		draw_string(get_theme_default_font(), Vector2(20.0, size.y * 0.5), "시세를 모으는 중…", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
		return
	var lo: int = prices[0]
	var hi: int = prices[0]
	for p: int in prices:
		lo = mini(lo, p)
		hi = maxi(hi, p)
	if ref > 0:
		lo = mini(lo, ref)
		hi = maxi(hi, ref)
	var span: float = maxf(float(hi - lo), 1.0)
	var to_y: Callable = func(p: int) -> float: return rect.end.y - (float(p - lo) / span) * rect.size.y
	for i: int in 4:
		var y: float = rect.position.y + rect.size.y * float(i) / 3.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID, 1.0)
	if ref > 0:
		var ry: float = to_y.call(ref)
		var x: float = rect.position.x
		while x < rect.end.x:
			draw_line(Vector2(x, ry), Vector2(minf(x + 10.0, rect.end.x), ry), Color(0.4, 0.4, 0.4, 0.6), 2.0)
			x += 18.0
	var points: PackedVector2Array = []
	for i: int in prices.size():
		points.append(Vector2(rect.position.x + rect.size.x * float(i) / float(prices.size() - 1), to_y.call(prices[i])))
	var last: int = prices[prices.size() - 1]
	var color: Color = UP if last >= ref else DOWN
	var fill: PackedVector2Array = points.duplicate()
	fill.append(Vector2(rect.end.x, rect.end.y))
	fill.append(Vector2(rect.position.x, rect.end.y))
	draw_colored_polygon(fill, Color(color, 0.12))
	draw_polyline(points, color, 3.0, true)
	draw_circle(points[points.size() - 1], 6.0, color)
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(rect.position.x, size.y - 8.0), "%d분 전" % (prices.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(font, Vector2(rect.end.x - 80.0, size.y - 8.0), "지금", HORIZONTAL_ALIGNMENT_RIGHT, 80, 22, INK)
	draw_string(font, Vector2(rect.end.x - 260.0, rect.position.y + 24.0), "고가 %s" % Money.digits(hi), HORIZONTAL_ALIGNMENT_RIGHT, 250, 22, INK)
	draw_string(font, Vector2(rect.end.x - 260.0, rect.end.y - 6.0), "저가 %s" % Money.digits(lo), HORIZONTAL_ALIGNMENT_RIGHT, 250, 22, INK)
