class_name CookStage
extends Control
## 주방 창의 요리 무대: 동작마다 진짜 조리 장면을 그린다. 무엇을 요리하는지(생선 · 소고기 · 삼겹살 · 닭 …)가 그대로 보이고,
## 재료가 익어 가는 모습 · 끓는 거품 · 졸아드는 국물 · 다가오는 쟁반이 곧 신호다 (게이지 대신 눈으로 보고 누른다).
##   chop · season · skewer · wok (박자): 위쪽 박자 줄에서 동그라미가 과녁에 닿을 때 누른다. 칼 · 소금통 · 꼬치 · 웍이 박자에 맞춰 움직인다.
##   grill (굽기): 그릴팬 위 재료 — 아랫면 테두리가 노릇해지고 고소한 김이 오르면 뒤집기, 늦으면 연기.
##   flip (부치기): 거품이 올라오고 가장자리가 노릇해지면 휙 뒤집는다 (공중제비).
##   boil (끓이기): 물이 팔팔 끓어오르면 재료 넣기 (늦으면 넘친다). simmer (졸이기): 국물이 졸임 선까지 내려오면 불 끄기.
##   fry (튀기기): 기포가 잦아들고 튀김옷이 황금빛이면 건지기. plate (담기): 미끄러져 오는 쟁반 한가운데에 접시 내려놓기.
##   mix · knead (연타): 마구 눌러 골고루 버무리기 · 매끈하게 반죽하기. steam (찌기): 재료 담기 → 물 선까지 붓기 → 김이 알맞으면 뚜껑 열기.
## 누른 시각은 주방 창(KitchenWindow)이 모아 서버로 보낸다. 무대는 그림과 즉석 판정 글씨만 맡는다.

## 무대를 누르고 뗐다 (큰 단추와 같은 입력).
signal pressed(down: bool)

const INK: Color = Color(0.32, 0.2, 0.12)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const WOOD: Color = Color(0.8, 0.6, 0.4)
const STEEL: Color = Color(0.36, 0.37, 0.4)
const POPUP_MS: float = 750.0
const TOSS_MS: float = 450.0

var step: Dictionary = {}
var scene: String = ""
var kind: String = ""
var recipe: RecipeInfo = null
## 주재료 (팬 · 석쇠 · 튀김 · 꼬치 · 간하기), 이번에 썰 재료, 냄비 · 그릇에 들어가는 재료들.
var main_id: String = ""
var chop_id: String = ""
var pot_ids: Array[String] = []
## 이 동작에서 누른 시각들 (주방 창과 같은 배열).
var taps: Array[float] = []
var start_ms: float = 0.0
var pouring: bool = false

var _popups: Array[Dictionary] = []
var _grades: Array[int] = []
var _combo: int = 0
var _finish_q: float = -1.0
var _finish_at: float = 0.0
var _seed: int = 0
var _mixed_shown: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func begin(step_def: Dictionary, recipe_info: RecipeInfo, subjects: Dictionary, step_taps: Array[float], start: float) -> void:
	step = step_def
	kind = str(step.get("kind", ""))
	scene = scene_of(step)
	recipe = recipe_info
	main_id = str(subjects.get("main", ""))
	chop_id = str(subjects.get("chop", main_id))
	pot_ids = []
	for id: Variant in subjects.get("pot", []):
		pot_ids.append(str(id))
	if pot_ids.is_empty():
		pot_ids.append(main_id)
	taps = step_taps
	start_ms = start
	pouring = false
	_popups.clear()
	_grades.clear()
	_combo = 0
	_finish_q = -1.0
	_seed = randi()
	_mixed_shown = false


## 동작의 장면 이름 (데이터 scene, 없으면 종류 · 동작으로).
static func scene_of(step_def: Dictionary) -> String:
	var s: String = str(step_def.get("scene", ""))
	if not s.is_empty():
		return s
	match str(step_def.get("kind", "")):
		"beats":
			return "chop"
		"grill":
			return "grill"
		"steam":
			return "steam"
		"mash":
			return "mix"
	match str(step_def.get("anim", "")):
		"cook_flip":
			return "flip"
		"cook_plate":
			return "plate"
	return "boil" if str(step_def.get("label", "")).contains("끓") else "simmer"


## 지금 동작 시작부터 ms.
func now_t() -> float:
	return float(Time.get_ticks_msec()) - start_ms


## 주방 창이 누름을 받아 taps 에 넣은 뒤 부른다: 판정 글씨를 띄운다 (grade < 0 이면 글씨 없이).
func on_input(grade: int) -> void:
	if grade < 0:
		return
	_grades.append(grade)
	_combo = _combo + 1 if grade == CookRules.Grade.PERFECT else 0
	var text: String = CookRules.GRADE_TEXT[grade]
	if _combo >= 2:
		text += "  콤보 ×%d" % _combo
	_popup(text, CookRules.GRADE_COLOR[grade], _focus(), grade == CookRules.Grade.PERFECT)


func say(text: String, color: Color) -> void:
	_popup(text, color, _focus(), true)


## 동작을 마쳤다: 솜씨 한마디를 크게.
func finish(quality: float) -> void:
	_finish_q = quality
	_finish_at = float(Time.get_ticks_msec())


func _popup(text: String, color: Color, at: Vector2, big: bool) -> void:
	_popups.clear()
	_popups.append({"text": text, "color": color, "at": at, "big": big, "ms": float(Time.get_ticks_msec())})


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed.emit((event as InputEventMouseButton).pressed)
		accept_event()
	elif event is InputEventScreenTouch:
		pressed.emit((event as InputEventScreenTouch).pressed)
		accept_event()


# ---- 그리기 ----

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.97, 0.94, 0.88))
	for i: int in int(w / 64.0) + 1:
		draw_line(Vector2(i * 64.0, 0.0), Vector2(i * 64.0, h * 0.6), Color(0.9, 0.85, 0.76), 2.0)
	for j: int in int(h * 0.6 / 64.0) + 1:
		draw_line(Vector2(0.0, j * 64.0), Vector2(w, j * 64.0), Color(0.9, 0.85, 0.76), 2.0)
	draw_rect(Rect2(0.0, h * 0.6, w, h * 0.4), WOOD)
	draw_rect(Rect2(0.0, h * 0.6, w, 10.0), WOOD.lightened(0.15))
	if step.is_empty():
		return
	var t: float = now_t()
	match scene:
		"chop":
			_draw_chop(t)
		"season":
			_draw_season(t)
		"skewer":
			_draw_skewer(t)
		"wok":
			_draw_wok(t)
		"grill":
			_draw_grill(t)
		"flip":
			_draw_flip(t)
		"boil":
			_draw_boil(t)
		"simmer":
			_draw_simmer(t)
		"fry":
			_draw_fry(t)
		"plate":
			_draw_plate(t)
		"knead":
			_draw_knead(t)
		"steam":
			_draw_steam(t)
		_:
			_draw_mix(t)
	if kind == "beats":
		_draw_lane(t)
	_draw_popups()
	_draw_finish()


## 화면에서 동작이 일어나는 곳 (판정 글씨 자리).
func _focus() -> Vector2:
	match scene:
		"chop", "season", "skewer":
			return Vector2(size.x * 0.5, size.y * 0.42)
		"plate":
			return Vector2(size.x * 0.5, size.y * 0.5)
	return Vector2(size.x * 0.5, size.y * 0.32)


func _font() -> Font:
	return get_theme_default_font()


func _text(at: Vector2, text: String, font_size: int, color: Color, outline: int = 8) -> void:
	var font: Font = _font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p: Vector2 = at - Vector2(width * 0.5, -font_size * 0.35)
	if outline > 0:
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(1, 1, 1, color.a * 0.9))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_popups() -> void:
	var now: float = float(Time.get_ticks_msec())
	var keep: Array[Dictionary] = []
	for p: Dictionary in _popups:
		var k: float = (now - float(p["ms"])) / POPUP_MS
		if k >= 1.0:
			continue
		keep.append(p)
		var pop: float = 1.0 + 0.35 * maxf(0.0, 1.0 - k * 5.0)
		var col: Color = p["color"]
		col.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
		_text(p["at"] - Vector2(0.0, 70.0 * k), str(p["text"]), int((46.0 if bool(p["big"]) else 38.0) * pop), col)
		if bool(p["big"]) and k < 0.5:
			_sparkles(p["at"], 90.0 * (0.5 + k), int(p["ms"]), col)
	_popups = keep


func _draw_finish() -> void:
	if _finish_q < 0.0:
		return
	var k: float = clampf((float(Time.get_ticks_msec()) - _finish_at) / 220.0, 0.0, 1.0)
	var c: Color = CookRules.step_color(_finish_q)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.98, 0.92, 0.45 * k))
	_text(size * 0.5 - Vector2(0.0, 20.0), CookRules.step_word(_finish_q), int(64.0 * (0.6 + 0.4 * k)), c, 10)
	_text(size * 0.5 + Vector2(0.0, 50.0), "솜씨 %d%%" % roundi(_finish_q * 100.0), 32, SOFT, 6)
	if _finish_q >= 0.9:
		_sparkles(size * 0.5, 160.0 + 40.0 * k, int(_finish_at), c)


func _sparkles(at: Vector2, radius: float, seed_n: int, color: Color) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_n
	for i: int in 8:
		var p: Vector2 = at + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.5, 1.0)
		var r: float = rng.randf_range(6.0, 12.0)
		draw_line(p - Vector2(r, 0.0), p + Vector2(r, 0.0), Color(color, 0.8), 3.0)
		draw_line(p - Vector2(0.0, r), p + Vector2(0.0, r), Color(color, 0.8), 3.0)


# ---- 박자 줄 (썰기 · 간하기 · 꼬치 · 웍) ----

func _lane_rect() -> Rect2:
	return Rect2(Vector2(24.0, 18.0), Vector2(size.x - 48.0, 76.0))


func _draw_lane(t: float) -> void:
	var lane: Rect2 = _lane_rect()
	var interval: float = float(step.get("interval_ms", 480))
	var window: float = float(step.get("window_ms", 170))
	var beats: int = int(step.get("beats", 4))
	var target: float = lane.position.x + 70.0
	var speed: float = (lane.size.x - 110.0) / (interval * 2.6)
	FoodArt.round_rect(self, lane, 30.0, Color(0.36, 0.26, 0.2, 0.85))
	var cy: float = lane.get_center().y
	draw_circle(Vector2(target, cy), maxf(window * speed, 16.0) + 6.0, Color(1, 1, 1, 0.18))
	draw_arc(Vector2(target, cy), 30.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.8), 4.0)
	var hit: Dictionary = _beat_hits()
	for i: int in range(1, beats + 1):
		var bt: float = interval * i
		var x: float = target + (bt - t) * speed
		if x > lane.end.x - 10.0:
			continue
		if hit.has(i):
			var since: float = t - float(hit[i][0])
			if since < 260.0:
				var g: int = int(hit[i][1])
				draw_arc(Vector2(target, cy), 30.0 + since * 0.12, 0.0, TAU, 24, Color(CookRules.GRADE_COLOR[g], 1.0 - since / 260.0), 6.0)
			continue
		if x < lane.position.x + 10.0:
			continue
		var missed: bool = t > bt + window * 2.0
		var col: Color = Color(0.7, 0.66, 0.6, 0.5) if missed else Color(1.0, 0.8, 0.3)
		draw_circle(Vector2(x, cy), 22.0, col)
		draw_circle(Vector2(x, cy), 12.0, Color(1, 1, 1, 0.7 if not missed else 0.3))
	_text(Vector2(lane.end.x - 70.0, cy), "%d/%d" % [mini(taps.size(), beats), beats], 26, Color(1.0, 0.95, 0.85), 0)


## 박자 번호 → [누른 시각, 판정] (박자마다 가장 가까운 첫 누름).
func _beat_hits() -> Dictionary:
	var out: Dictionary = {}
	for x: float in taps:
		var b: int = CookRules.nearest_beat(step, x)
		if not out.has(b):
			out[b] = [x, CookRules.beat_grade(step, x)]
	return out


## 다음 박자까지 남은 비율 (0 = 지금 박자, 1 = 막 지남).
func _beat_phase(t: float) -> float:
	var interval: float = float(step.get("interval_ms", 480))
	var next_b: float = ceilf(maxf(t, 0.0) / interval) * interval
	return clampf((next_b - t) / interval, 0.0, 1.0)


func _since_last_tap(t: float) -> float:
	return t - taps[-1] if not taps.is_empty() else INF


# ---- 불 · 팬 · 냄비 ----

func _flame(center: Vector2, width: float, power: float, t: float) -> void:
	if power <= 0.01:
		return
	draw_rect(Rect2(center.x - width * 0.6, center.y, width * 1.2, 18.0), Color(0.25, 0.25, 0.28))
	for i: int in 9:
		var x: float = center.x - width * 0.5 + width * float(i) / 8.0
		var fl: float = (26.0 + 12.0 * sin(t * 0.02 + i * 1.9)) * power
		var tongue: PackedVector2Array = [Vector2(x - 10.0, center.y), Vector2(x, center.y - fl), Vector2(x + 10.0, center.y)]
		draw_colored_polygon(tongue, Color(1.0, 0.55, 0.15, 0.85))
		var inner: PackedVector2Array = [Vector2(x - 5.0, center.y), Vector2(x, center.y - fl * 0.55), Vector2(x + 5.0, center.y)]
		draw_colored_polygon(inner, Color(0.45, 0.65, 1.0, 0.9))


func _pan(center: Vector2, r: Vector2, ridges: bool) -> void:
	draw_line(center + Vector2(r.x * 0.9, 0.0), center + Vector2(r.x * 1.75, r.y * 0.2), Color(0.22, 0.15, 0.1), 24.0)
	FoodArt.ellipse(self, center + Vector2(0.0, 8.0), r * 1.02, Color(0.12, 0.12, 0.14))
	FoodArt.ellipse(self, center, r, Color(0.2, 0.2, 0.23))
	FoodArt.ellipse(self, center + Vector2(0.0, 4.0), r * 0.88, Color(0.3, 0.3, 0.34))
	if ridges:
		for k: int in 7:
			var y: float = center.y - r.y * 0.6 + r.y * 0.2 * k
			var half: float = r.x * 0.86 * sqrt(maxf(0.0, 1.0 - pow((y - center.y) / (r.y * 0.88), 2.0)))
			draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), Color(0.22, 0.22, 0.25), 6.0)


## 냄비 (옆에서): 몸통 사각 + 위 테두리 타원. 돌려주는 값 = 안쪽 수면 타원 중심 높이를 정할 몸통 사각형.
func _pot(body: Rect2, color: Color) -> void:
	draw_rect(Rect2(body.position.x - 26.0, body.position.y + 26.0, 30.0, 14.0), color.darkened(0.3))
	draw_rect(Rect2(body.end.x - 4.0, body.position.y + 26.0, 30.0, 14.0), color.darkened(0.3))
	draw_rect(body, color)
	draw_rect(Rect2(body.position.x, body.position.y, 14.0, body.size.y), color.lightened(0.15))
	FoodArt.ellipse(self, Vector2(body.get_center().x, body.end.y), Vector2(body.size.x * 0.5, 14.0), color.darkened(0.2))


func _steam_puffs(base: Vector2, width: float, amount: float, t: float, color: Color = Color(1, 1, 1, 0.55)) -> void:
	for i: int in int(3.0 + amount * 9.0):
		var ph: float = fmod(t / 1100.0 + float(i) * 0.137, 1.0)
		var x: float = base.x - width * 0.5 + fmod(float(i) * 71.0, width) + sin(t * 0.003 + i) * 10.0
		draw_circle(Vector2(x, base.y - ph * 110.0), 8.0 + ph * 18.0, Color(color, color.a * (1.0 - ph)))


func _smoke(base: Vector2, amount: float, t: float) -> void:
	if amount <= 0.0:
		return
	_steam_puffs(base, 160.0, clampf(amount, 0.0, 1.0), t * 0.8, Color(0.3, 0.3, 0.32, 0.55 * clampf(amount, 0.2, 1.0)))


func _ripple_bubbles(center: Vector2, r: Vector2, count: int, big: float, t: float, color: Color) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in count:
		var life: float = rng.randf_range(300.0, 700.0)
		var ph: float = fmod(t / life + rng.randf(), 1.0)
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * 0.85
		var p: Vector2 = center + Vector2(cos(a) * r.x, sin(a) * r.y) * d
		draw_arc(p, (3.0 + big * 9.0) * (0.4 + ph), 0.0, TAU, 12, Color(color, 0.8 * (1.0 - ph)), 2.5)


## 동그란 진행 고리 (남은 시간 등).
func _ring(center: Vector2, radius: float, ratio: float, color: Color) -> void:
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.0, 0.0, 0.0, 0.12), 10.0)
	if ratio > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(ratio, 0.0, 1.0), 48, color, 10.0)


## 작은 계기판 (보조): 날것 → 알맞음(초록) → 지나침. value 1 = 알맞음.
func _dial(center: Vector2, value: float, tolerance: float, label: String) -> void:
	var r: float = 44.0
	draw_circle(center, r + 8.0, Color(1, 1, 1, 0.85))
	var from: float = PI
	var span: float = PI
	var to_a: Callable = func(v: float) -> float: return from + span * clampf(v / 2.0, 0.0, 1.0)
	draw_arc(center, r, from, from + span, 24, Color(0.85, 0.8, 0.7), 10.0)
	draw_arc(center, r, to_a.call(1.0 - tolerance), to_a.call(1.0 + tolerance), 12, Color("#5AAE5A"), 10.0)
	draw_arc(center, r, to_a.call(1.0 + tolerance * 2.0), from + span, 12, Color(0.4, 0.25, 0.15), 10.0)
	var a: float = to_a.call(value)
	draw_line(center, center + Vector2.from_angle(a) * (r - 4.0), INK, 4.0)
	draw_circle(center, 6.0, INK)
	_text(center + Vector2(0.0, 26.0), label, 22, SOFT, 0)


# ---- 썰기 ----

func _draw_chop(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var board: Rect2 = Rect2(w * 0.08, h * 0.5, w * 0.84, h * 0.36)
	FoodArt.round_rect(self, board.grow(4.0), 18.0, Color(0.55, 0.38, 0.22))
	FoodArt.round_rect(self, board, 16.0, Color(0.9, 0.74, 0.5))
	var spec: Dictionary = FoodArt.bar_spec(chop_id)
	var th: float = clampf(float(spec.get("thick", 0.5)) * h * 0.26, 34.0, 110.0)
	var cy: float = board.get_center().y - 6.0
	var x0: float = w * 0.16
	var x1: float = w * 0.74
	var beats: int = int(step.get("beats", 4))
	var cuts: int = mini(taps.size(), beats)
	var seg: float = (x1 - x0) / (float(beats) + 1.6)
	var cut_x: Callable = func(k: int) -> float: return x1 - seg * float(k)
	var rest_end: float = cut_x.call(cuts)
	_bar(spec, x0, rest_end, cy, th, true, false, true)
	for k: int in range(1, cuts + 1):
		var age: float = t - taps[k - 1]
		var slide: float = 16.0 + 10.0 * float(cuts - k) + 22.0 * clampf(age / 140.0, 0.0, 1.0)
		var px0: float = cut_x.call(k) + slide
		var px1: float = cut_x.call(k - 1) + slide - 4.0
		var tilt: float = -0.06 * clampf(age / 140.0, 0.0, 1.0) * (1.0 if k % 2 == 0 else -0.6)
		draw_set_transform(Vector2((px0 + px1) * 0.5, cy), tilt, Vector2.ONE)
		_bar(spec, (px0 - px1) * 0.5, (px1 - px0) * 0.5, 0.0, th, true, true, false)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	var next_x: float = cut_x.call(mini(cuts + 1, beats)) if cuts < beats else rest_end
	var since: float = _since_last_tap(t)
	var down: bool = since < 110.0
	var lift: float = 0.0 if down else (24.0 + 80.0 * _beat_phase(t)) * (1.0 if cuts < beats else 1.6)
	var knife_x: float = rest_end if down else next_x
	_knife(Vector2(knife_x, cy + th * 0.5 - (th * 0.15 if down else th + lift)))


## 썰 재료 막대 (x0..x1 가로). left_face / right_face = 자른 면을 보인다, whole = 아직 안 썬 쪽 (꼭지 · 뿌리가 붙어 있다).
func _bar(spec: Dictionary, x0: float, x1: float, cy: float, th: float, right_face: bool, left_face: bool, whole: bool) -> void:
	if x1 - x0 < 2.0:
		return
	var skin: Color = spec["skin"]
	var flesh: Color = spec["flesh"]
	FoodArt.round_rect(self, Rect2(x0, cy - th * 0.5, x1 - x0, th), th * 0.35, skin)
	var band: float = float(spec.get("skin_band", 0.0))
	if band > 0.0:
		draw_rect(Rect2(x0 + 4.0, cy - th * 0.5 + th * band, x1 - x0 - 8.0, th * (1.0 - band) - 4.0), flesh)
	if bool(spec.get("layers", false)):
		for k: int in 3:
			draw_rect(Rect2(x0 + 4.0, cy - th * 0.3 + th * 0.24 * k, x1 - x0 - 8.0, th * 0.08), Color(0.98, 0.94, 0.9))
	if bool(spec.get("marble", false)):
		var xx: float = x0 + 10.0
		while xx < x1 - 14.0:
			draw_line(Vector2(xx, cy - th * 0.1), Vector2(xx + 12.0, cy + th * 0.15), Color(1, 0.95, 0.9, 0.6), 3.0)
			xx += 26.0
	if spec.has("root") and whole:
		FoodArt.round_rect(self, Rect2(x0, cy - th * 0.5, minf(60.0, x1 - x0), th), th * 0.35, spec["root"])
		for k2: int in 4:
			draw_line(Vector2(x0 + 2.0, cy - th * 0.3 + k2 * th * 0.2), Vector2(x0 - 14.0, cy - th * 0.4 + k2 * th * 0.26), Color(0.85, 0.82, 0.7), 2.0)
	if spec.has("tip") and whole:
		FoodArt.ellipse(self, Vector2(x0 + 4.0, cy), Vector2(14.0, th * 0.4), spec["tip"])
	draw_rect(Rect2(x0 + th * 0.3, cy - th * 0.38, (x1 - x0) * 0.5, 5.0), Color(1, 1, 1, 0.25))
	if right_face:
		_cross(spec, Vector2(x1 - 2.0, cy), th)
	if left_face:
		_cross(spec, Vector2(x0 + 2.0, cy), th)


func _cross(spec: Dictionary, at: Vector2, th: float) -> void:
	FoodArt.ellipse(self, at, Vector2(maxf(th * 0.16, 6.0), th * 0.5), spec["cross"])
	if spec.has("ring"):
		draw_arc(at, th * 0.38, 0.0, TAU, 20, spec["ring"], 4.0)


func _knife(edge: Vector2) -> void:
	var blade: PackedVector2Array = [edge + Vector2(-12.0, 0.0), edge + Vector2(14.0, 0.0), edge + Vector2(18.0, -120.0), edge + Vector2(-14.0, -128.0)]
	draw_colored_polygon(blade, Color(0.82, 0.84, 0.88))
	draw_line(edge + Vector2(-12.0, 0.0), edge + Vector2(14.0, 0.0), Color(0.95, 0.97, 1.0), 4.0)
	draw_line(edge + Vector2(-4.0, -8.0), edge + Vector2(-2.0, -118.0), Color(1, 1, 1, 0.4), 4.0)
	FoodArt.round_rect(self, Rect2(edge + Vector2(-10.0, -196.0), Vector2(24.0, 72.0)), 8.0, Color(0.32, 0.2, 0.12))
	draw_circle(edge + Vector2(2.0, -150.0), 3.0, Color(0.85, 0.8, 0.7))
	draw_circle(edge + Vector2(2.0, -176.0), 3.0, Color(0.85, 0.8, 0.7))


# ---- 간하기 ----

func _draw_season(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var board: Rect2 = Rect2(w * 0.1, h * 0.52, w * 0.8, h * 0.34)
	FoodArt.round_rect(self, board, 16.0, Color(0.9, 0.74, 0.5))
	var food_at: Vector2 = Vector2(w * 0.5, board.get_center().y)
	var fsize: float = w * (0.46 if FoodArt.kind_of(main_id) == "fish" else 0.34)
	FoodArt.draw_food(self, main_id, food_at, fsize, 0.0)
	var beats: int = int(step.get("beats", 4))
	var interval: float = float(step.get("interval_ms", 480))
	var spot_x: Callable = func(i: int) -> float: return food_at.x - fsize * 0.35 + fsize * 0.7 * (float(i) - 0.5) / float(beats)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for k: int in mini(taps.size(), beats + 4):
		rng.seed = _seed + k
		var age: float = t - taps[k]
		var sx: float = spot_x.call(clampi(k + 1, 1, beats))
		for g: int in 14:
			var gx: float = sx + rng.randf_range(-34.0, 34.0)
			var gy: float = food_at.y + rng.randf_range(-30.0, 26.0)
			var fall: float = clampf(age / 220.0, 0.0, 1.0)
			var y: float = lerpf(h * 0.3, gy, fall)
			draw_circle(Vector2(gx, y), 3.0, Color(1, 1, 1, 0.95))
	var beat_now: float = clampf(t / interval, 0.5, float(beats) + 0.5)
	var shaker_x: float = lerpf(spot_x.call(1), spot_x.call(beats), clampf((beat_now - 1.0) / maxf(float(beats - 1), 1.0), 0.0, 1.0))
	var shake: float = sin(clampf(_since_last_tap(t) / 160.0, 0.0, 1.0) * PI * 2.0) * 0.35
	draw_set_transform(Vector2(shaker_x, h * 0.26), PI + 0.5 + shake, Vector2.ONE)
	FoodArt.round_rect(self, Rect2(-26.0, -50.0, 52.0, 92.0), 14.0, Color(0.96, 0.96, 0.98))
	FoodArt.round_rect(self, Rect2(-26.0, -60.0, 52.0, 26.0), 8.0, Color(0.7, 0.72, 0.76))
	for d: int in 3:
		draw_circle(Vector2(-12.0 + d * 12.0, -52.0), 3.0, Color(0.3, 0.3, 0.32))
	_text(Vector2(0.0, 0.0), "소금", 22, SOFT, 0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# ---- 꼬치 ----

func _draw_skewer(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var board: Rect2 = Rect2(w * 0.06, h * 0.5, w * 0.88, h * 0.36)
	FoodArt.round_rect(self, board, 16.0, Color(0.9, 0.74, 0.5))
	var cy: float = board.get_center().y
	var beats: int = int(step.get("beats", 4))
	var gap: float = (w * 0.62) / float(beats)
	var done: int = mini(taps.size(), beats)
	var base_x: float = w * 0.1
	var threaded_end: float = base_x + 70.0 + gap * float(done)
	var approach: float = gap * 0.55 * _beat_phase(t) if done < beats else 0.0
	var tip_x: float = threaded_end + 30.0 - approach
	if _since_last_tap(t) < 110.0:
		tip_x = threaded_end + 30.0
	draw_line(Vector2(base_x, cy), Vector2(tip_x, cy), Color(0.86, 0.72, 0.48), 9.0)
	draw_colored_polygon(PackedVector2Array([Vector2(tip_x, cy - 5.0), Vector2(tip_x + 16.0, cy), Vector2(tip_x, cy + 5.0)]), Color(0.86, 0.72, 0.48))
	for i: int in beats:
		var id: String = _skewer_piece(i)
		var on: bool = i < done
		var x: float = base_x + 70.0 + gap * (float(i) + 0.5) if on else w * 0.1 + 70.0 + gap * (float(i) + 0.5) + 60.0
		var y: float = cy if on else cy + 6.0
		if on:
			var age: float = t - taps[i]
			x -= 40.0 * (1.0 - clampf(age / 120.0, 0.0, 1.0))
		FoodArt.draw_piece(self, id, Vector2(x, y), gap * 0.78, 0.0, 0.0, i)
	draw_line(Vector2(base_x - 30.0, cy), Vector2(base_x + 20.0, cy), Color(0.7, 0.55, 0.35), 12.0)


func _skewer_piece(i: int) -> String:
	var others: Array[String] = []
	for id: String in pot_ids:
		if id != main_id:
			others.append(id)
	if i % 2 == 0 or others.is_empty():
		return main_id
	return others[(i / 2) % others.size()]


# ---- 웍 볶기 ----

func _draw_wok(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var center: Vector2 = Vector2(w * 0.5, h * 0.62)
	var good: int = 0
	for g: int in _grades:
		if g >= CookRules.Grade.GOOD:
			good += 1
	var beats: int = int(step.get("beats", 4))
	var cook: float = clampf(float(good) / float(beats), 0.0, 1.0) * 0.9 + 0.1
	var since: float = _since_last_tap(t)
	var tilt: float = -0.18 * sin(clampf(since / 260.0, 0.0, 1.0) * PI)
	var flare: float = clampf(1.0 - since / 380.0, 0.0, 1.0) if not _grades.is_empty() and _grades[-1] >= CookRules.Grade.GOOD else 0.0
	_flame(Vector2(center.x, h * 0.86), w * 0.4, 1.3, t)
	draw_set_transform(center, tilt, Vector2.ONE)
	var bowl: PackedVector2Array = []
	for i: int in 25:
		var a: float = PI * float(i) / 24.0
		bowl.append(Vector2(cos(a) * w * 0.3, sin(a) * h * 0.2))
	draw_colored_polygon(bowl, Color(0.18, 0.18, 0.2))
	FoodArt.ellipse(self, Vector2.ZERO, Vector2(w * 0.3, h * 0.05), Color(0.26, 0.26, 0.3))
	draw_line(Vector2(w * 0.28, 0.0), Vector2(w * 0.45, -h * 0.06), Color(0.22, 0.15, 0.1), 18.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in 12:
		var id: String = pot_ids[i % pot_ids.size()]
		var home: Vector2 = center + Vector2(rng.randf_range(-w * 0.2, w * 0.2), rng.randf_range(-h * 0.02, h * 0.05))
		var up: float = rng.randf_range(0.6, 1.0)
		var k: float = clampf(since / 420.0, 0.0, 1.0)
		var air: float = sin(k * PI) * h * 0.32 * up if since < 420.0 else 0.0
		var spin: float = k * TAU * rng.randf_range(-1.0, 1.0) if since < 420.0 else rng.randf() * TAU
		FoodArt.draw_piece(self, id, home - Vector2(0.0, air), 46.0, spin, cook, i)
	if flare > 0.0:
		for i2: int in 7:
			var x: float = center.x - w * 0.22 + w * 0.44 * float(i2) / 6.0
			var fh: float = h * (0.18 + 0.12 * sin(i2 * 2.1)) * flare
			draw_colored_polygon(PackedVector2Array([Vector2(x - 26.0, center.y - 10.0), Vector2(x, center.y - 10.0 - fh), Vector2(x + 26.0, center.y - 10.0)]), Color(1.0, 0.5, 0.1, 0.75 * flare))
		_text(center - Vector2(0.0, h * 0.42), "불맛!", 34, Color(0.95, 0.4, 0.1, flare), 6)
	_steam_puffs(center - Vector2(0.0, h * 0.06), w * 0.4, 0.5, t)


# ---- 굽기 ----

## k 번째 면을 구운 시간 / 알맞은 시간 (뒤집기 사이 간격).
func _side_cook(k: int) -> float:
	if k < 0 or k >= taps.size():
		return 0.0
	return (taps[k] - (taps[k - 1] if k > 0 else 0.0)) / float(step.get("side_ms", 2000))


func _grill_state(t: float) -> Dictionary:
	var flips: int = taps.size()
	var prev: float = taps[-1] if flips > 0 else 0.0
	var done: bool = flips >= int(step.get("sides", 2))
	return {"flips": flips, "top": _side_cook(flips - 1), "under": 0.0 if done else (t - prev) / float(step.get("side_ms", 2000)), "since": t - prev, "done": done}


func _draw_grill(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var center: Vector2 = Vector2(w * 0.44, h * 0.6)
	var side_ms: float = float(step.get("side_ms", 2000))
	var window: float = float(step.get("window_ms", 300))
	var tol: float = window / side_ms
	var st: Dictionary = _grill_state(t)
	var done: bool = bool(st["done"])
	_flame(Vector2(center.x, h * 0.84), w * 0.34, 1.0 if not done else 0.0, t)
	_pan(center, Vector2(w * 0.3, h * 0.2), true)
	var fsize: float = w * (0.42 if FoodArt.kind_of(main_id) == "fish" else 0.34)
	var since: float = float(st["since"])
	var flips: int = int(st["flips"])
	var top: float = float(st["top"])
	var under: float = float(st["under"])
	var pos: Vector2 = center + Vector2(0.0, -10.0)
	var squash: float = 1.0
	if flips > 0 and since < 380.0 and t >= 0.0:
		var p: float = since / 380.0
		pos.y -= sin(p * PI) * h * 0.28
		squash = absf(cos(p * PI)) * 0.88 + 0.12
		if p < 0.5:
			FoodArt.draw_food(self, main_id, pos, fsize, _side_cook(flips - 2), _side_cook(flips - 1), 0.0, squash)
			return
	if done:
		var slide: float = clampf((since - 380.0) / 300.0, 0.0, 1.0)
		var plate_at: Vector2 = Vector2(w * 0.8, h * 0.72)
		FoodArt.ellipse(self, plate_at, Vector2(w * 0.17, h * 0.07), Color(0.97, 0.96, 0.92))
		FoodArt.ellipse(self, plate_at, Vector2(w * 0.12, h * 0.045), Color(0.9, 0.88, 0.84))
		FoodArt.draw_food(self, main_id, pos.lerp(plate_at - Vector2(0.0, 10.0), slide), fsize * lerpf(1.0, 0.7, slide), _side_cook(flips - 1), -1.0, 0.0, squash)
		return
	FoodArt.draw_food(self, main_id, pos, fsize, top, under, 0.0, squash)
	if t < 0.0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in 12:
		var ph: float = fmod(t / 520.0 + rng.randf(), 1.0)
		var x: float = center.x + rng.randf_range(-fsize * 0.55, fsize * 0.55)
		draw_circle(Vector2(x, center.y - 10.0 - ph * 60.0), 3.0 + 2.0 * ph, Color(1, 1, 1, 0.75 * (1.0 - ph)))
	if absf(under - 1.0) <= tol * 1.4:
		for i2: int in 3:
			var ph2: float = fmod(t / 900.0 + i2 * 0.33, 1.0)
			var base: Vector2 = pos + Vector2(-fsize * 0.25 + fsize * 0.25 * i2, -30.0 - ph2 * 100.0)
			var wave: PackedVector2Array = []
			for k: int in 8:
				wave.append(base + Vector2(sin(k * 0.9 + t * 0.008) * 10.0, -k * 8.0))
			draw_polyline(wave, Color(0.95, 0.72, 0.3, 0.8 * (1.0 - ph2)), 4.0)
		_text(pos - Vector2(0.0, fsize * 0.45 + 30.0), "노릇노릇!", 30, Color(0.9, 0.6, 0.15), 6)
	_smoke(pos - Vector2(0.0, 30.0), (under - 1.0 - tol) / (tol * 3.0), t)
	_dial(Vector2(w - 70.0, 70.0), under, tol, "익힘")


# ---- 부치기 (뒤집기 한 번) ----

func _draw_flip(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var center: Vector2 = Vector2(w * 0.45, h * 0.62)
	var ideal: float = float(step.get("ideal_ms", 1700))
	var tol: float = float(step.get("window_ms", 300)) / ideal
	var tapped: bool = not taps.is_empty()
	var cook: float = (taps[0] if tapped else t) / ideal
	var since: float = t - taps[0] if tapped else 0.0
	_flame(Vector2(center.x, h * 0.86), w * 0.3, 1.0 if not tapped else 0.5, t)
	var tilt: float = -0.25 * sin(clampf(since / TOSS_MS, 0.0, 1.0) * PI) if tapped else 0.0
	draw_set_transform(center, tilt, Vector2.ONE)
	_pan(Vector2.ZERO, Vector2(w * 0.28, h * 0.18), false)
	FoodArt.ellipse(self, Vector2(0.0, 4.0), Vector2(w * 0.24, h * 0.15), Color(0.9, 0.75, 0.3, 0.25))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var subject: String = main_id
	var fsize: float = w * 0.32
	var pos: Vector2 = center + Vector2(0.0, -8.0)
	if tapped and since < TOSS_MS:
		var p: float = since / TOSS_MS
		pos.y -= sin(p * PI) * h * 0.42
		var squash: float = absf(cos(p * PI)) * 0.88 + 0.12
		var rot: float = p * 0.6
		if p < 0.5:
			FoodArt.draw_food(self, subject, pos, fsize, 0.15, cook, rot, squash)
		else:
			FoodArt.draw_food(self, subject, pos, fsize, cook, 0.1, rot, squash)
		return
	if tapped:
		FoodArt.draw_food(self, subject, pos, fsize, cook, 0.1)
		return
	FoodArt.draw_food(self, subject, pos, fsize, minf(cook * 0.35, 0.35), cook)
	if t < 0.0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in int(clampf(cook, 0.0, 1.2) * 12.0):
		var ph: float = fmod(t / 600.0 + rng.randf(), 1.0)
		var p2: Vector2 = pos + Vector2(rng.randf_range(-fsize * 0.3, fsize * 0.3), rng.randf_range(-fsize * 0.18, fsize * 0.18))
		draw_arc(p2, 3.0 + 5.0 * ph, 0.0, TAU, 10, Color(1, 1, 1, 0.7 * (1.0 - ph)), 2.0)
	if absf(cook - 1.0) <= tol * 1.4:
		_text(pos - Vector2(0.0, fsize * 0.4 + 30.0), "지금 뒤집어요!", 30, Color(0.9, 0.6, 0.15), 6)
	_smoke(pos - Vector2(0.0, 20.0), (cook - 1.0 - tol) / (tol * 3.0), t)


# ---- 끓이기 ----

func _broth_color() -> Color:
	if recipe != null:
		var ids: Array[String] = []
		for ing: Dictionary in recipe.ingredients:
			ids.append(str(ing.get("item", "")))
		if "chili" in ids and recipe.tags.has("spicy"):
			return Color(0.86, 0.32, 0.16)
		if "doenjang" in ids:
			return Color(0.68, 0.48, 0.24)
		if "soy_sauce" in ids:
			return Color(0.5, 0.3, 0.16)
	return Color(0.96, 0.9, 0.74)


func _draw_boil(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var ideal: float = float(step.get("ideal_ms", 3000))
	var tol: float = float(step.get("window_ms", 400)) / ideal
	var tapped: bool = not taps.is_empty()
	var heat: float = (taps[0] if tapped else t) / ideal
	var since: float = t - taps[0] if tapped else 0.0
	var body: Rect2 = Rect2(w * 0.28, h * 0.42, w * 0.44, h * 0.4)
	_flame(Vector2(body.get_center().x, body.end.y + 46.0), body.size.x * 0.8, 1.0, t)
	_pot(body, Color(0.62, 0.64, 0.68))
	var surface: Vector2 = Vector2(body.get_center().x, body.position.y)
	var rim: Vector2 = Vector2(body.size.x * 0.5, 30.0)
	FoodArt.ellipse(self, surface, rim, Color(0.5, 0.52, 0.56))
	var water: Color = Color(0.7, 0.85, 0.95).lerp(_broth_color(), clampf(since / 400.0, 0.0, 1.0) if tapped else 0.0)
	var wobble: float = sin(t * 0.03) * 3.0 * clampf(heat, 0.0, 1.5)
	FoodArt.ellipse(self, surface + Vector2(0.0, 6.0 + wobble), rim * 0.9, water)
	var hot: float = clampf(heat, 0.0, 1.6)
	_ripple_bubbles(surface + Vector2(0.0, 6.0), rim * 0.85, int(2.0 + hot * 18.0), hot, t, Color(1, 1, 1))
	_steam_puffs(surface - Vector2(0.0, 20.0), body.size.x * 0.8, clampf(hot, 0.0, 1.0), t)
	if heat > 1.0 + tol * 2.0 and not tapped:
		var over: float = clampf((heat - 1.0 - tol * 2.0) / (tol * 2.0), 0.0, 1.0)
		for k: int in 6:
			FoodArt.ellipse(self, Vector2(body.position.x + body.size.x * (0.1 + 0.16 * k), body.position.y + 6.0), Vector2(30.0, 18.0 + 30.0 * over), Color(1, 1, 1, 0.9))
		draw_rect(Rect2(body.position.x + 10.0, body.position.y, 22.0, 60.0 * over), Color(1, 1, 1, 0.8))
		_text(surface - Vector2(0.0, 100.0), "넘쳐요!", 30, Color("#E8604A"), 6)
	elif absf(heat - 1.0) <= tol * 1.4 and not tapped:
		_text(surface - Vector2(0.0, 110.0), "팔팔!", 34, Color(0.9, 0.5, 0.15), 6)
	if tapped:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = _seed
		for i: int in 8:
			var id: String = pot_ids[i % pot_ids.size()]
			var k2: float = clampf((since - i * 40.0) / 260.0, 0.0, 1.0)
			var home: Vector2 = surface + Vector2(rng.randf_range(-rim.x * 0.6, rim.x * 0.6), rng.randf_range(-rim.y * 0.3, rim.y * 0.5))
			var bob: float = sin(t * 0.006 + i) * 3.0
			FoodArt.draw_piece(self, id, home - Vector2(0.0, (1.0 - k2) * h * 0.4) + Vector2(0.0, bob), 44.0, i * 0.7, clampf(since / 1500.0, 0.0, 0.6), i)
		if since < 300.0:
			for d: int in 10:
				var a: float = PI + PI * float(d) / 9.0
				draw_circle(surface + Vector2(cos(a), sin(a)) * (30.0 + since * 0.3), 6.0, Color(0.8, 0.9, 1.0, 1.0 - since / 300.0))
	_thermo(Vector2(body.end.x + 90.0, body.position.y - 10.0), heat, tol)


func _thermo(top: Vector2, value: float, tol: float) -> void:
	var hgt: float = 200.0
	FoodArt.round_rect(self, Rect2(top - Vector2(16.0, 0.0), Vector2(32.0, hgt)), 14.0, Color(1, 1, 1, 0.9))
	var to_y: Callable = func(v: float) -> float: return top.y + hgt - 10.0 - (hgt - 20.0) * clampf(v / 1.8, 0.0, 1.0)
	draw_rect(Rect2(top.x - 12.0, to_y.call(1.0 + tol), 24.0, to_y.call(1.0 - tol) - to_y.call(1.0 + tol)), Color("#5AAE5A"))
	draw_rect(Rect2(top.x - 6.0, to_y.call(value), 12.0, top.y + hgt - 10.0 - to_y.call(value)), Color(0.9, 0.25, 0.2))
	draw_circle(top + Vector2(0.0, hgt + 8.0), 20.0, Color(0.9, 0.25, 0.2))


# ---- 졸이기 ----

func _draw_simmer(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var ideal: float = float(step.get("ideal_ms", 3400))
	var tol: float = float(step.get("window_ms", 380)) / ideal
	var tapped: bool = not taps.is_empty()
	var r: float = (taps[0] if tapped else t) / ideal
	var body: Rect2 = Rect2(w * 0.24, h * 0.3, w * 0.52, h * 0.52)
	_flame(Vector2(body.get_center().x, body.end.y + 46.0), body.size.x * 0.7, 0.0 if tapped else 0.8, t)
	_pot(body, Color(0.45, 0.32, 0.26))
	var inner: Rect2 = Rect2(body.position + Vector2(26.0, 20.0), body.size - Vector2(52.0, 40.0))
	draw_rect(inner, Color(0.95, 0.92, 0.86))
	var start_l: float = 0.85
	var line_l: float = 0.42
	var level: float = start_l - (start_l - line_l) * maxf(r, 0.0)
	var level_y: float = inner.end.y - inner.size.y * clampf(level, 0.04, 1.0)
	var broth: Color = _broth_color()
	if r > 1.0 + tol * 2.0:
		broth = broth.lerp(Color(0.25, 0.14, 0.08), clampf((r - 1.0 - tol * 2.0) / (tol * 3.0), 0.0, 0.7))
	draw_rect(Rect2(inner.position.x, level_y, inner.size.x, inner.end.y - level_y), broth)
	for i: int in 6:
		var id: String = pot_ids[i % pot_ids.size()]
		var x: float = inner.position.x + inner.size.x * (0.12 + 0.15 * i)
		FoodArt.draw_piece(self, id, Vector2(x, level_y + 12.0 + sin(t * 0.004 + i) * 3.0), 40.0, i * 0.8, 0.6, i)
	if not tapped:
		_ripple_bubbles(Vector2(inner.get_center().x, level_y), Vector2(inner.size.x * 0.45, 6.0), 10, 0.6, t, broth.lightened(0.4))
	var line_y: float = inner.end.y - inner.size.y * line_l
	var dash: float = inner.position.x
	while dash < inner.end.x:
		draw_line(Vector2(dash, line_y), Vector2(minf(dash + 16.0, inner.end.x), line_y), Color(0.15, 0.35, 0.75), 4.0)
		dash += 26.0
	_text(Vector2(inner.end.x + 70.0, line_y), "졸임 선", 24, Color(0.15, 0.35, 0.75), 4)
	if not tapped and absf(r - 1.0) <= tol * 1.4:
		_text(Vector2(inner.get_center().x, body.position.y - 40.0), "딱 좋아요!", 32, Color(0.9, 0.5, 0.15), 6)
	if r > 1.0 + tol * 2.0:
		_smoke(Vector2(inner.get_center().x, body.position.y), (r - 1.0 - tol * 2.0) / (tol * 2.0), t)
	elif not tapped:
		_steam_puffs(Vector2(inner.get_center().x, body.position.y), inner.size.x, 0.4, t)


# ---- 튀기기 ----

func _draw_fry(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var ideal: float = float(step.get("ideal_ms", 2600))
	var tol: float = float(step.get("window_ms", 320)) / ideal
	var tapped: bool = not taps.is_empty()
	var r: float = (taps[0] if tapped else t) / ideal
	var since: float = t - taps[0] if tapped else 0.0
	var body: Rect2 = Rect2(w * 0.22, h * 0.46, w * 0.56, h * 0.36)
	_flame(Vector2(body.get_center().x, body.end.y + 46.0), body.size.x * 0.8, 1.0, t)
	_pot(body, Color(0.3, 0.3, 0.33))
	var surface: Vector2 = Vector2(body.get_center().x, body.position.y + 8.0)
	var rim: Vector2 = Vector2(body.size.x * 0.48, 28.0)
	FoodArt.ellipse(self, surface, rim, Color(0.95, 0.72, 0.28))
	var batter: Color = FoodArt.cooked(Color(0.97, 0.92, 0.74), Color(0.9, 0.6, 0.24), r)
	var lift: float = clampf(since / 320.0, 0.0, 1.0) if tapped else 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in 5:
		var home: Vector2 = surface + Vector2(-rim.x * 0.6 + rim.x * 0.3 * i, rng.randf_range(-6.0, 10.0))
		var p: Vector2 = home - Vector2(0.0, lift * (h * 0.3 - 26.0)) + Vector2(0.0, sin(t * 0.01 + i) * 2.0 * (1.0 - lift))
		FoodArt.draw_piece(self, main_id, p, 58.0, rng.randf_range(-0.4, 0.4), 0.3, i)
		FoodArt.ellipse(self, p, Vector2(34.0, 22.0), Color(batter, 0.92))
		for c: int in 5:
			draw_circle(p + Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-14.0, 14.0)), 4.0, batter.darkened(0.12))
	if not tapped:
		var fizz: float = clampf(1.0 - 0.8 * clampf(r, 0.0, 1.0), 0.15, 1.0)
		_ripple_bubbles(surface, rim * 0.95, int(6.0 + fizz * 26.0), fizz, t, Color(1.0, 0.95, 0.8))
		if absf(r - 1.0) <= tol * 1.4:
			_text(surface - Vector2(0.0, 90.0), "황금빛!", 32, Color(0.9, 0.55, 0.12), 6)
		_smoke(surface - Vector2(0.0, 20.0), (r - 1.0 - tol) / (tol * 3.0), t)
	else:
		var net_y: float = surface.y + 10.0 - lift * h * 0.3
		draw_arc(Vector2(surface.x - rim.x * 0.0, net_y), rim.x * 0.75, 0.1, PI - 0.1, 20, Color(0.75, 0.76, 0.8), 5.0)
		draw_line(Vector2(surface.x + rim.x * 0.75, net_y), Vector2(surface.x + rim.x * 1.3, net_y - 70.0), Color(0.45, 0.32, 0.2), 10.0)
		for d: int in 6:
			var dy: float = fmod(since * 0.3 + d * 23.0, 80.0)
			draw_circle(Vector2(surface.x - 60.0 + d * 24.0, net_y + 20.0 + dy), 3.0, Color(0.95, 0.75, 0.3, 0.8))


# ---- 담기 ----

func _draw_plate(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var ideal: float = float(step.get("ideal_ms", 1300))
	var cx: float = w * 0.5
	var v: float = minf((cx + 220.0) / ideal, 0.62)
	var tapped: bool = not taps.is_empty()
	var tray_t: float = taps[0] if tapped else t
	var tray_x: float = cx + (tray_t - ideal) * v
	var tray_y: float = h * 0.74
	var since: float = t - taps[0] if tapped else 0.0
	FoodArt.round_rect(self, Rect2(tray_x - 200.0, tray_y - 18.0, 400.0, 50.0), 22.0, Color(0.55, 0.36, 0.2))
	FoodArt.round_rect(self, Rect2(tray_x - 190.0, tray_y - 26.0, 380.0, 44.0), 20.0, Color(0.72, 0.5, 0.3))
	FoodArt.ellipse(self, Vector2(tray_x, tray_y - 6.0), Vector2(70.0, 12.0), Color(1, 1, 1, 0.25))
	draw_line(Vector2(tray_x, tray_y - 16.0), Vector2(tray_x, tray_y + 4.0), Color(1, 1, 1, 0.6), 4.0)
	draw_line(Vector2(cx, h * 0.16), Vector2(cx, h * 0.68), Color(1, 1, 1, 0.0 if tapped else 0.35), 3.0)
	var icon: Texture2D = DishArt.icon(recipe.id) if recipe != null else null
	var dish_size: Vector2 = Vector2(280.0, 280.0)
	var hover: Vector2 = Vector2(cx, h * 0.26 + sin(t * 0.006) * 6.0)
	var land: Vector2 = Vector2(cx, tray_y - 80.0)
	var off: float = cx - tray_x
	var on_tray: bool = absf(off) <= 190.0
	if not on_tray:
		land.y = h * 0.66
	var at: Vector2 = hover
	if tapped:
		var k: float = clampf(since / 240.0, 0.0, 1.0)
		at = hover.lerp(land, k * k)
	FoodArt.ellipse(self, Vector2(at.x, tray_y + 4.0), Vector2(90.0, 14.0), Color(0.0, 0.0, 0.0, 0.15))
	if icon != null:
		draw_texture_rect(icon, Rect2(at - dish_size * 0.5, dish_size), false)
	else:
		FoodArt.ellipse(self, at + Vector2(0.0, 30.0), Vector2(100.0, 34.0), Color(0.97, 0.96, 0.92))
		FoodArt.draw_food(self, main_id, at + Vector2(0.0, 14.0), 160.0, 1.0)
	if not tapped:
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 14.0, h * 0.06), Vector2(cx + 14.0, h * 0.06), Vector2(cx, h * 0.1)]), Color(0.9, 0.5, 0.2))


# ---- 버무리기 · 반죽 ----

func _sauce_color() -> Color:
	if recipe != null and recipe.tags.has("spicy"):
		return Color(0.84, 0.26, 0.14)
	if recipe != null and recipe.tags.has("sweet"):
		return Color(0.55, 0.32, 0.16)
	return Color(0.82, 0.62, 0.3)


func _stir_angle(t: float) -> float:
	var a: float = 0.0
	for x: float in taps:
		a += 0.9 * clampf((t - x) / 200.0, 0.0, 1.0)
	return a


func _draw_mix(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var center: Vector2 = Vector2(w * 0.5, h * 0.56)
	var r: Vector2 = Vector2(w * 0.3, h * 0.26)
	var need: float = float(step.get("taps", 10))
	var dur: float = float(step.get("duration_ms", 2600))
	var p: float = clampf(float(taps.size()) / need, 0.0, 1.0)
	FoodArt.ellipse(self, center + Vector2(0.0, 14.0), r * 1.06, Color(0.0, 0.0, 0.0, 0.12))
	FoodArt.ellipse(self, center, r * 1.04, Color(0.86, 0.9, 0.95))
	FoodArt.ellipse(self, center, r * 0.92, Color(0.94, 0.96, 0.98))
	FoodArt.ellipse(self, center, r * 0.86, Color(_sauce_color(), 0.55 * p))
	var ang: float = _stir_angle(t)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in 16:
		var id: String = pot_ids[i % pot_ids.size()]
		var d: float = sqrt(rng.randf()) * 0.75
		var a: float = rng.randf() * TAU
		var sorted_a: float = TAU * float(i) / 16.0
		var base_a: float = lerpf(a, sorted_a + d, p * 0.5)
		var pa: float = base_a + ang * (1.3 - d)
		var pos: Vector2 = center + Vector2(cos(pa) * r.x, sin(pa) * r.y) * d * 0.95
		FoodArt.draw_piece(self, id, pos, 62.0, pa + rng.randf() * TAU, 0.0, i)
		if p > 0.2:
			draw_circle(pos, 10.0, Color(_sauce_color(), 0.5 * p))
	var spoon: Vector2 = center + Vector2(cos(ang * 1.4), sin(ang * 1.4)) * r * 0.55
	draw_line(spoon, spoon + Vector2(60.0, -150.0), Color(0.72, 0.52, 0.3), 14.0)
	FoodArt.ellipse(self, spoon, Vector2(30.0, 20.0), Color(0.78, 0.58, 0.34))
	_ring(Vector2(w - 70.0, 70.0), 40.0, 1.0 - clampf(t / dur, 0.0, 1.0), Color("#E8604A") if t > dur * 0.7 else Color("#5AAE5A"))
	_text(Vector2(w - 70.0, 70.0), "%d" % mini(taps.size(), int(need)), 30, INK, 0)
	if p >= 1.0:
		_sparkles(center, r.x * 0.8, _seed, Color(1.0, 0.85, 0.3))
		if not _mixed_shown:
			_mixed_shown = true
			say("골고루!", CookRules.GRADE_COLOR[CookRules.Grade.PERFECT])


func _draw_knead(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var board: Rect2 = Rect2(w * 0.12, h * 0.5, w * 0.76, h * 0.38)
	FoodArt.round_rect(self, board, 16.0, Color(0.9, 0.74, 0.5))
	for i: int in 30:
		draw_circle(board.position + Vector2(fmod(i * 97.0, board.size.x), fmod(i * 53.0, board.size.y)), 4.0, Color(1, 1, 1, 0.5))
	var need: float = float(step.get("taps", 10))
	var dur: float = float(step.get("duration_ms", 2600))
	var p: float = clampf(float(taps.size()) / need, 0.0, 1.0)
	var since: float = _since_last_tap(t)
	var press: float = sin(clampf(since / 200.0, 0.0, 1.0) * PI) if since < 200.0 else 0.0
	var center: Vector2 = Vector2(w * 0.5, board.get_center().y - 10.0)
	var r: Vector2 = Vector2(150.0 * (1.0 + 0.25 * press), 95.0 * (1.0 - 0.3 * press))
	var dough: Color = Color(0.96, 0.9, 0.76).lerp(Color(0.99, 0.96, 0.88), p)
	FoodArt.ellipse(self, center + Vector2(0.0, r.y * 0.8), Vector2(r.x, 16.0), Color(0, 0, 0, 0.12))
	FoodArt.ellipse(self, center, r, dough)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i: int in int(14.0 * (1.0 - p)):
		draw_circle(center + Vector2(rng.randf_range(-r.x * 0.7, r.x * 0.7), rng.randf_range(-r.y * 0.6, r.y * 0.6)), rng.randf_range(5.0, 10.0), dough.darkened(0.08))
	FoodArt.ellipse(self, center + Vector2(-r.x * 0.3, -r.y * 0.45), Vector2(r.x * 0.3, r.y * 0.15), Color(1, 1, 1, 0.2 + 0.4 * p))
	for side: float in [-1.0, 1.0]:
		var hand: Vector2 = center + Vector2(side * 70.0, -r.y - 40.0 + press * 50.0)
		FoodArt.ellipse(self, hand, Vector2(56.0, 40.0), Color(0.98, 0.84, 0.72))
	if since < 300.0:
		for k: int in 6:
			var a: float = PI + PI * k / 5.0
			draw_circle(center + Vector2(cos(a) * (r.x + since * 0.2), sin(a) * 30.0 - since * 0.1), 8.0, Color(1, 1, 1, 0.7 * (1.0 - since / 300.0)))
	_ring(Vector2(w - 70.0, 70.0), 40.0, 1.0 - clampf(t / dur, 0.0, 1.0), Color("#E8604A") if t > dur * 0.7 else Color("#5AAE5A"))
	_text(Vector2(w - 70.0, 70.0), "%d" % mini(taps.size(), int(need)), 30, INK, 0)
	if p >= 1.0:
		_sparkles(center, r.x, _seed, Color(1.0, 0.85, 0.3))
		if not _mixed_shown:
			_mixed_shown = true
			say("매끈매끈!", CookRules.GRADE_COLOR[CookRules.Grade.PERFECT])


# ---- 찌기 ----

func _draw_steam(t: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var n: int = int(step.get("items", 3))
	var fill_ms: float = float(step.get("fill_ms", 1600))
	var steam_ms: float = float(step.get("steam_ms", 2600))
	var window: float = float(step.get("window_ms", 300))
	var pot: Rect2 = Rect2(Vector2(w * 0.5 - 170.0, h * 0.38), Vector2(340.0, h * 0.42))
	var lid_on: bool = taps.size() == n + 2
	_flame(Vector2(pot.get_center().x, pot.end.y + 46.0), pot.size.x * 0.7, 1.0 if taps.size() >= n + 1 else 0.4, t)
	_pot(pot, Color(0.62, 0.64, 0.68))
	var inner: Rect2 = Rect2(pot.position + Vector2(14.0, 10.0), pot.size - Vector2(28.0, 20.0))
	draw_rect(inner, Color(0.88, 0.9, 0.92))
	var level: float = 0.0
	if taps.size() == n + 1:
		level = (t - taps[n]) / fill_ms
	elif taps.size() >= n + 2:
		level = (taps[n + 1] - taps[n]) / fill_ms
	var line_y: float = inner.end.y - inner.size.y * 0.6
	var water_top: float = inner.end.y - inner.size.y * 0.6 * clampf(level, 0.0, 1.5)
	if level > 0.0:
		draw_rect(Rect2(inner.position.x, water_top, inner.size.x, inner.end.y - water_top), Color(0.45, 0.7, 0.95, 0.75))
	draw_line(Vector2(inner.position.x, line_y - 30.0), Vector2(inner.end.x, line_y - 30.0), Color(0.55, 0.45, 0.32), 6.0)
	for i: int in mini(taps.size(), n):
		var drop: float = clampf((t - taps[i]) / 250.0, 0.0, 1.0)
		var x: float = inner.position.x + 50.0 + (inner.size.x - 100.0) * (float(i) / maxf(n - 1, 1))
		var y: float = lerpf(pot.position.y - 100.0, line_y - 52.0, drop * drop)
		FoodArt.draw_piece(self, pot_ids[i % pot_ids.size()], Vector2(x, y), 64.0, i * 0.6, clampf((t - taps[n + 1]) / steam_ms, 0.0, 1.0) * 0.8 if taps.size() >= n + 2 else 0.0, i)
	var dash: float = inner.position.x
	while dash < inner.end.x:
		draw_line(Vector2(dash, line_y), Vector2(minf(dash + 14.0, inner.end.x), line_y), Color(0.15, 0.35, 0.75), 4.0)
		dash += 24.0
	_text(Vector2(pot.end.x + 70.0, line_y), "물 선", 24, Color(0.15, 0.35, 0.75), 4)
	if pouring:
		draw_rect(Rect2(Vector2(inner.position.x + 30.0, pot.position.y - 120.0), Vector2(16.0, water_top - pot.position.y + 120.0)), Color(0.45, 0.7, 0.95, 0.85))
		FoodArt.round_rect(self, Rect2(inner.position.x - 10.0, pot.position.y - 170.0, 90.0, 60.0), 12.0, Color(0.85, 0.7, 0.4))
	if taps.size() >= n + 2:
		var lid_x: float = pot.position.x - 10.0 + (220.0 if taps.size() >= n + 3 else 0.0)
		var lid: Rect2 = Rect2(Vector2(lid_x, pot.position.y - 24.0 - (40.0 if not lid_on else 0.0)), Vector2(pot.size.x + 20.0, 24.0))
		FoodArt.round_rect(self, lid, 10.0, Color(0.42, 0.44, 0.48))
		FoodArt.round_rect(self, Rect2(lid.get_center() - Vector2(24.0, 26.0), Vector2(48.0, 16.0)), 6.0, Color(0.25, 0.25, 0.28))
	if lid_on:
		var steamed: float = (t - taps[n + 1]) / steam_ms
		_steam_puffs(Vector2(pot.get_center().x, pot.position.y - 30.0), pot.size.x, clampf(steamed, 0.0, 1.5), t)
		if lid_on and absf(steamed - 1.0) <= window / steam_ms * 1.4:
			_text(Vector2(pot.get_center().x, pot.position.y - 150.0), "김이 폴폴!", 32, Color(0.9, 0.5, 0.15), 6)
		_dial(Vector2(w - 70.0, 70.0), steamed, window / steam_ms, "찌기")
	elif taps.size() >= n + 3:
		var ph2: float = clampf((t - taps[n + 2]) / 600.0, 0.0, 1.0)
		draw_circle(pot.get_center() - Vector2(0.0, 160.0 + ph2 * 30.0), 50.0 + ph2 * 30.0, Color(1, 1, 1, 0.6 * (1.0 - ph2)))
