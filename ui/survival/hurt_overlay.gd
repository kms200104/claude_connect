class_name HurtOverlay
extends Control
## v0.28.1 맞았을 때 화면 (SurvivalController 가 hit 를 부른다): 화면 가장자리가 붉게 번지고 (가운데는 맑다),
## 모서리에 피가 튀어 흘러내리다 마른다, 전체가 잠깐 붉게 번쩍. 체력이 30% 이하이면 가장자리가 심장 박동처럼 붉게 맥동한다.
## 피 흘림(Net.bleeding)이 없을 때도 같은 붉은 번쩍 · 가장자리로 맞은 걸 알린다. 터치는 통과.

const RED: Color = Color(0.62, 0.02, 0.02)
## 튄 피가 사라지는 시간 (초).
const SPLAT_LIFE: float = 1.4
## 한꺼번에 화면에 남는 튄 피 수 (여러 번 맞아도 화면을 가리지 않게).
const MAX_SPLATS: int = 5

var _edge: TextureRect = null
var _flash: float = 0.0
var _edge_hit: float = 0.0
var _time: float = 0.0
## 튄 피 [{at, r, seed, t, drips: [[x, len]]}].
var _splats: Array[Dictionary] = []


func _ready() -> void:
	name = "HurtOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge = TextureRect.new()
	_edge.name = "Edge"
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	var g: Gradient = Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(RED, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(RED, 1.0))
	g.add_point(0.55, Color(RED, 0.0))
	g.add_point(0.8, Color(RED, 0.45))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 128
	tex.height = 128
	_edge.texture = tex
	_edge.modulate.a = 0.0
	add_child(_edge)


## 맞았다: strength 0~1 (피해 · 남은 체력에 따라).
func hit(strength: float = 0.6) -> void:
	var k: float = clampf(strength, 0.2, 1.0)
	_flash = maxf(_flash, 0.22 + 0.2 * k)
	_edge_hit = maxf(_edge_hit, 0.7 + 0.3 * k)
	var s: Vector2 = size
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i: int in 1 + roundi(k * 2.0):
		# 가장자리 · 모서리 쪽에.
		var side: int = rng.randi() % 4
		var at: Vector2 = Vector2(rng.randf() * s.x, rng.randf() * s.y)
		match side:
			0:
				at.x = rng.randf_range(-20.0, s.x * 0.14)
			1:
				at.x = s.x - rng.randf_range(-20.0, s.x * 0.14)
			2:
				at.y = rng.randf_range(-20.0, s.y * 0.1)
			_:
				at.y = s.y - rng.randf_range(-20.0, s.y * 0.1)
		var drips: Array = []
		for d: int in rng.randi_range(1, 3):
			drips.append([rng.randf_range(-0.6, 0.6), rng.randf_range(0.8, 2.4)])
		_splats.append({"at": at, "r": rng.randf_range(30.0, 60.0) * (0.7 + k * 0.5), "seed": rng.randi(), "t": 0.0, "drips": drips})
	while _splats.size() > MAX_SPLATS:
		_splats.pop_front()
	queue_redraw()


func is_showing() -> bool:
	return _edge.modulate.a > 0.01 or not _splats.is_empty()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 1.6)
	_edge_hit = maxf(0.0, _edge_hit - delta * 0.9)
	# 체력이 얼마 안 남으면 심장 박동처럼.
	var low: float = 0.0
	if Net.state == Net.State.ONLINE and Net.max_hp > 0 and Net.hp > 0 and float(Net.hp) / float(Net.max_hp) <= 0.3:
		var beat: float = fmod(_time, 1.0)
		low = 0.35 + 0.35 * (exp(-beat * 9.0) + 0.6 * exp(-absf(beat - 0.22) * 12.0))
	_edge.modulate.a = clampf(maxf(_edge_hit, low), 0.0, 1.0)
	for i: int in range(_splats.size() - 1, -1, -1):
		_splats[i]["t"] = float(_splats[i]["t"]) + delta
		if float(_splats[i]["t"]) > SPLAT_LIFE:
			_splats.remove_at(i)
	if _flash > 0.0 or not _splats.is_empty():
		queue_redraw()


func _draw() -> void:
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(RED, _flash))
	for sp: Dictionary in _splats:
		var t: float = float(sp["t"])
		var fade: float = clampf(1.0 - (t - SPLAT_LIFE * 0.5) / (SPLAT_LIFE * 0.5), 0.0, 1.0)
		var r: float = float(sp["r"])
		var at: Vector2 = sp["at"]
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(sp["seed"])
		var dark: Color = Color(0.38, 0.0, 0.0, 0.85 * fade)
		var wet: Color = Color(0.62, 0.03, 0.03, 0.75 * fade)
		# 울퉁불퉁한 덩어리 (가운데가 더 짙다).
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in 18:
			var a: float = TAU * float(k) / 18.0
			pts.append(at + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.65, 1.15))
		draw_colored_polygon(pts, wet)
		draw_circle(at, r * 0.45, dark)
		# 둘레에 튄 방울.
		for k: int in 7:
			var a2: float = rng.randf() * TAU
			var dist: float = r * rng.randf_range(1.1, 1.9)
			draw_circle(at + Vector2(cos(a2), sin(a2)) * dist, rng.randf_range(4.0, 11.0), wet)
		# 흘러내리는 줄기.
		for d: Array in sp["drips"]:
			var x0: Vector2 = at + Vector2(float(d[0]) * r, r * 0.4)
			var length: float = r * float(d[1]) * clampf(t / 0.9, 0.0, 1.0)
			draw_line(x0, x0 + Vector2(0.0, length), wet, 7.0, true)
			draw_circle(x0 + Vector2(0.0, length), 6.0, wet)
