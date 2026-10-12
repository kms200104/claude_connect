class_name CookStage
extends Control
## 주방 창의 요리 무대 (v0.18 리듬 요리): 위에서 내려다보는 3D 조리대(KitchenCounter)에 박자 표시를 겹쳐 그린다.
##   - 손이 닿는 곳(칼날 아래 · 팬 · 냄비 …)에 과녁 동그라미가 있고, 누를 박자마다 바깥 고리가 줄어들어 과녁에 겹치는 순간이
##     요리 노래의 그 박자다 (통!). 그때 누르면 완벽 — 칼이 내려오고 · 고기를 뒤집고 · 재료가 풍덩 …
##   - 아래 박자 줄: 박자마다 눈금이 흐르고, 누를 박자는 그 일(썰기 · 뒤집기 · 넣기 …) 이름표를 달고 왼쪽 판정선으로 다가온다.
##   - 처음 하는 동작이면 show_tutorial 로 잠깐 멈춰 무엇을 언제 누르는지 보여 준다 (주방 창이 부른다).
## 누른 시각은 주방 창(KitchenWindow)이 모아 서버로 보낸다. 무대는 그림과 즉석 판정 글씨만 맡는다.

## 무대를 누르고 뗐다 (큰 단추와 같은 입력).
signal pressed(down: bool)
## 처음 하는 동작 설명을 닫았다 ("시작!").
signal tutorial_closed

const INK: Color = Color(0.32, 0.2, 0.12)
const PAPER: Color = Color(1.0, 0.98, 0.92)
const LANE_BG: Color = Color(0.12, 0.1, 0.09, 0.62)
const TARGET: Color = Color(1.0, 1.0, 1.0, 0.95)
const POPUP_MS: float = 750.0
## 고리가 보이기 시작하는 때 (박자 수 앞).
const LOOKAHEAD_BEATS: float = 2.0
## 박자 줄에서 판정선 위치 · 한 박자 폭 (px).
const JUDGE_X: float = 120.0
const BEAT_PX: float = 150.0

var step: Dictionary = {}
var scene: String = ""
var recipe: RecipeInfo = null
var taps: Array[float] = []
var start_ms: float = 0.0
var counter: KitchenCounter = null

var _view: SubViewport = null
var _popups: Array[Dictionary] = []
var _combo: int = 0
## 누를 박자마다 판정 (-1 = 아직).
var _hit_grades: PackedInt32Array = []
var _hit_flash: PackedFloat32Array = []
var _finish_q: float = -1.0
var _finish_at: float = 0.0
var _tutorial: Control = null
var _tutorial_at: float = 0.0
var _hits: PackedFloat32Array = []
## 처음 하는 동작 설명 카드를 띄울 곳 (주방 창 전체 — 스크롤 밖이라 화면이 낮아도 다 보이고 눌린다). 없으면 무대 위.
var tutorial_host: Control = null
var _verbs: PackedStringArray = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var holder: SubViewportContainer = SubViewportContainer.new()
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 3D 무대는 이 노드의 그림(박자 고리 · 박자 줄) 뒤에 그린다.
	holder.show_behind_parent = true
	add_child(holder)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	_view.positional_shadow_atlas_size = 1024
	holder.add_child(_view)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.16, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.94, 0.86)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	# 땅 휘기 기준점을 따라가는 뿌리 (마을에서 멀리 있어도 조리대가 가라앉지 않게).
	var anchor: CurveAnchor = CurveAnchor.new()
	_view.add_child(anchor)
	counter = KitchenCounter.new()
	anchor.add_child(counter)


## 동작을 시작한다 (주방 창이 박자 격자에 맞춘 start_ms — 첫 박자 = start_ms + interval_ms).
func begin(step_def: Dictionary, recipe_info: RecipeInfo, subjects: Dictionary, step_taps: Array[float], start: float) -> void:
	step = step_def
	scene = scene_of(step)
	recipe = recipe_info
	taps = step_taps
	start_ms = start
	_hits = CookRules.hits(step)
	_verbs = PackedStringArray()
	for v: Variant in step.get("verbs", []):
		_verbs.append(str(v))
	_hit_grades = PackedInt32Array()
	_hit_flash = PackedFloat32Array()
	_hit_grades.resize(_hits.size())
	_hit_flash.resize(_hits.size())
	_hit_grades.fill(-1)
	_hit_flash.fill(-1.0)
	_popups.clear()
	_combo = 0
	_finish_q = -1.0
	if counter != null:
		counter.begin(step, recipe, subjects)


## 처음 하는 동작이면 맡기 전에 장면만 먼저 보여 준다 (설명 뒤에서).
func preview(step_def: Dictionary, recipe_info: RecipeInfo, subjects: Dictionary) -> void:
	begin(step_def, recipe_info, subjects, [] as Array[float], INF)


## 동작의 장면 이름 (데이터 scene, 없으면 동작 종류 · 몸짓으로).
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


## 주방 창이 누름을 받아 taps 에 넣은 뒤 부른다: 동작 한 번 + 판정 글씨. hit = 맞춘 박자 번호 (-1 = 헛누름).
func on_input(grade: int, hit: int = -1) -> void:
	if counter != null:
		counter.act(grade)
	if grade < 0:
		return
	if hit >= 0 and hit < _hit_grades.size():
		_hit_grades[hit] = grade
		_hit_flash[hit] = float(Time.get_ticks_msec())
	_combo = _combo + 1 if grade == CookRules.Grade.PERFECT else 0
	var text: String = CookRules.GRADE_TEXT[grade]
	if _combo >= 2:
		text += "  콤보 ×%d" % _combo
	_popup(text, CookRules.GRADE_COLOR[grade], _focus() + Vector2(0.0, -70.0), grade == CookRules.Grade.PERFECT)


func say(text: String, color: Color) -> void:
	_popup(text, color, _focus() + Vector2(0.0, -70.0), true)


## 동작을 마쳤다: 못 다 한 동작은 마저 하고, 솜씨 한마디를 크게.
func finish(quality: float) -> void:
	if counter != null:
		counter.finish_rest()
	_finish_q = quality
	_finish_at = float(Time.get_ticks_msec())


func _popup(text: String, color: Color, at: Vector2, big: bool) -> void:
	_popups.clear()
	_popups.append({"text": text, "color": color, "at": at, "big": big, "ms": float(Time.get_ticks_msec())})


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _tutorial != null:
		return
	var down: bool = false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		down = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		down = (event as InputEventScreenTouch).pressed
	else:
		return
	pressed.emit(down)
	accept_event()


# ---- 처음 하는 동작 설명 ----

## 무엇을 · 언제 누르는지 보여 주는 카드 (박자 줄 견본이 노래에 맞춰 돈다). "시작!" 을 누르면 tutorial_closed.
func show_tutorial(step_def: Dictionary) -> void:
	hide_tutorial()
	_tutorial_at = float(Time.get_ticks_msec())
	var card: PanelContainer = PanelContainer.new()
	card.name = "Tutorial"
	card.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.98, 0.92, 0.97), Color(0.45, 0.32, 0.22), 30, 5, 22))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var host: Control = tutorial_host if tutorial_host != null and is_instance_valid(tutorial_host) else self
	if not host is Container:
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 40.0
		card.offset_right = -40.0
		card.offset_top = 26.0
		card.offset_bottom = -26.0
	host.add_child(card)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var top_gap: Control = Control.new()
	top_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(top_gap)
	col.add_child(_label("처음 하는 동작 · %s" % str(step_def.get("label", "")), 38, INK))
	var text: Label = _label(str(step_def.get("tutorial", step_def.get("hint", ""))), 27, Color(0.36, 0.26, 0.18))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var window: float = float(step_def.get("window_ms", 160))
	var how: Label = _label("완벽: 고리가 과녁에 딱 겹칠 때 (앞뒤 %d ms 안) · 좋아요: %d ms 안 · 박자에 없는 누름은 깎여요" % [roundi(window * 0.4), roundi(window)], 23, Color(0.5, 0.4, 0.3))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(how)
	var demo: Control = Control.new()
	demo.custom_minimum_size = Vector2(0, 170)
	demo.draw.connect(_draw_tutorial_demo.bind(demo, step_def))
	col.add_child(demo)
	var go: Button = Button.new()
	go.text = "알겠어요, 시작!"
	go.add_theme_font_size_override("font_size", 34)
	go.custom_minimum_size = Vector2(0, 92)
	# 누르는 순간 닫는다: 떼는 순간(pressed)이면 휴대폰에서 손가락이 조금만 움직여도 주방 창 스크롤이 누름을 취소해 닫히지 않았다.
	go.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	go.pressed.connect(close_tutorial)
	col.add_child(go)
	var gap: Control = Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap)
	# 카드 아무 데나 눌러도 시작.
	card.gui_input.connect(func(event: InputEvent) -> void:
		var down: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if down and float(Time.get_ticks_msec()) - _tutorial_at > 400.0:
			card.accept_event()
			close_tutorial())
	_tutorial = card


## 설명을 닫고 동작을 시작한다 (시작 단추 · 카드 · 큰 단추 어느 것으로든). 이미 닫혔으면 아무것도 안 한다.
func close_tutorial() -> void:
	if _tutorial == null:
		return
	hide_tutorial()
	tutorial_closed.emit()


func hide_tutorial() -> void:
	if _tutorial != null:
		if is_instance_valid(_tutorial):
			_tutorial.queue_free()
		_tutorial = null


func _exit_tree() -> void:
	# 무대가 사라지면(주문 목록으로 · 손님이 떠남) 창에 띄운 설명 카드도 함께 치운다.
	hide_tutorial()


func is_tutorial_open() -> bool:
	return _tutorial != null


## 견본: 박자 줄이 노래 박자로 흐르고, 누를 박자가 판정선에 닿을 때 "지금!" 이 깜빡인다 (자동 반복).
func _draw_tutorial_demo(demo: Control, step_def: Dictionary) -> void:
	demo.queue_redraw()
	var hits: PackedFloat32Array = CookRules.hits(step_def)
	var verbs: Array = step_def.get("verbs", [])
	var interval: float = float(step_def.get("interval_ms", 536))
	var last: float = hits[hits.size() - 1] if not hits.is_empty() else 4.0
	var cycle: float = (last + 3.0) * interval
	var t: float = fmod(float(Time.get_ticks_msec()) - _tutorial_at, cycle) - interval
	var r: Rect2 = Rect2(Vector2.ZERO, demo.size)
	demo.draw_rect(r, LANE_BG)
	var y: float = r.size.y * 0.55
	var judge: float = 110.0
	var font: Font = _font()
	for b: int in range(-1, int(last) + 4):
		var x: float = judge + (float(b) * interval - t) / interval * 130.0
		if x < 0.0 or x > r.size.x:
			continue
		demo.draw_line(Vector2(x, y - 34.0), Vector2(x, y + 34.0), Color(1, 1, 1, 0.18), 2.0)
		if b >= 1:
			demo.draw_string(font, Vector2(x - 6.0, y + 58.0), str(b), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.45))
	demo.draw_line(Vector2(judge, y - 46.0), Vector2(judge, y + 46.0), Color(1.0, 0.85, 0.3), 5.0)
	for i: int in hits.size():
		var at: float = hits[i] * interval
		var x2: float = judge + (at - t) / interval * 130.0
		if x2 < -40.0 or x2 > r.size.x + 40.0:
			continue
		var near: float = absf(at - t)
		var col: Color = Color(1.0, 0.85, 0.3) if near < 120.0 else Color(1, 1, 1, 0.9)
		demo.draw_circle(Vector2(x2, y), 22.0, col)
		demo.draw_arc(Vector2(x2, y), 22.0, 0.0, TAU, 32, Color(0.2, 0.12, 0.06), 3.0)
		var verb: String = str(verbs[i]) if i < verbs.size() else ""
		demo.draw_string(font, Vector2(x2 - 30.0, y - 34.0), verb, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, Color(1, 1, 1, 0.95))
		if near < 90.0:
			demo.draw_string(font, Vector2(judge + 30.0, y - 50.0), "지금! 통!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.85, 0.3))
	# 박자마다 판정선이 통통 뛴다.
	var phase: float = fposmod(t, interval) / interval
	var pulse: float = maxf(0.0, 1.0 - phase * 4.0)
	demo.draw_circle(Vector2(judge, y), 26.0 + 8.0 * pulse, Color(1.0, 0.85, 0.3, 0.25 + 0.35 * pulse))


# ---- 그리기 ----

func _draw() -> void:
	var t: float = now_t()
	if _hits.is_empty() or _tutorial != null:
		_draw_popups()
		return
	var interval: float = float(step.get("interval_ms", 536))
	_draw_rings(t, interval)
	_draw_lane(t, interval)
	if t < interval * 0.6:
		var beats_left: int = int(ceil((interval - t) / interval))
		_text(Vector2(size.x * 0.5, size.y * 0.32), "준비… %s" % ("●".repeat(clampi(beats_left, 1, 4))), 52, Color(1, 1, 1), 10)
	_draw_popups()
	_draw_finish()


## 손이 닿는 곳: 과녁 동그라미 + 다가오는 박자의 고리 (가까워질수록 작아져 과녁에 겹친다).
func _draw_rings(t: float, interval: float) -> void:
	var at: Vector2 = _focus()
	var next: int = _next_hit()
	var phase: float = fposmod(t, interval) / interval
	var pulse: float = maxf(0.0, 1.0 - phase * 4.0) if t > 0.0 else 0.0
	draw_arc(at, 44.0 + 4.0 * pulse, 0.0, TAU, 48, Color(0, 0, 0, 0.35), 9.0)
	draw_arc(at, 44.0 + 4.0 * pulse, 0.0, TAU, 48, TARGET, 4.0)
	for i: int in _hits.size():
		if _hit_grades[i] >= 0:
			continue
		var dt: float = _hits[i] * interval - t
		if dt < -float(step.get("window_ms", 160)) * 2.0 or dt > LOOKAHEAD_BEATS * interval:
			continue
		var k: float = clampf(dt / (LOOKAHEAD_BEATS * interval), 0.0, 1.0)
		var r: float = 44.0 + 150.0 * k
		var a: float = 0.95 - 0.55 * k
		var c: Color = Color(1.0, 0.82, 0.25, a) if i == next else Color(1, 1, 1, a * 0.6)
		draw_arc(at, r, 0.0, TAU, 64, c, 6.0 if i == next else 3.0)
	if next >= 0 and next < _verbs.size():
		_text(at + Vector2(0.0, 76.0), _verbs[next], 34, Color(1.0, 0.9, 0.5), 9)
	# 방금 맞춘 박자: 과녁에서 빛이 퍼진다.
	var now: float = float(Time.get_ticks_msec())
	for i: int in _hits.size():
		if _hit_flash[i] < 0.0:
			continue
		var since: float = now - _hit_flash[i]
		if since > 320.0:
			continue
		var g: int = _hit_grades[i]
		draw_arc(at, 44.0 + since * 0.18, 0.0, TAU, 48, Color(CookRules.GRADE_COLOR[g], 1.0 - since / 320.0), 7.0)


## 아래 박자 줄: 박자 눈금이 흐르고, 누를 박자가 일 이름을 달고 판정선으로 다가온다.
func _draw_lane(t: float, interval: float) -> void:
	var lane: Rect2 = Rect2(Vector2(0.0, size.y - 118.0), Vector2(size.x, 118.0))
	draw_rect(lane, LANE_BG)
	var y: float = lane.position.y + 64.0
	var last: float = _hits[_hits.size() - 1]
	for b: int in range(0, int(last) + 4):
		var x: float = JUDGE_X + (float(b) * interval - t) / interval * BEAT_PX
		if x < 0.0 or x > size.x:
			continue
		draw_line(Vector2(x, y - 30.0), Vector2(x, y + 30.0), Color(1, 1, 1, 0.2), 2.0)
	var phase: float = fposmod(t, interval) / interval
	var pulse: float = maxf(0.0, 1.0 - phase * 4.0) if t > 0.0 else 0.0
	draw_circle(Vector2(JUDGE_X, y), 30.0 + 8.0 * pulse, Color(1.0, 0.85, 0.3, 0.2 + 0.3 * pulse))
	draw_line(Vector2(JUDGE_X, y - 44.0), Vector2(JUDGE_X, y + 44.0), Color(1.0, 0.85, 0.3), 5.0)
	var next: int = _next_hit()
	for i: int in _hits.size():
		var x: float = JUDGE_X + (_hits[i] * interval - t) / interval * BEAT_PX
		if x < -40.0 or x > size.x + 40.0:
			continue
		var g: int = _hit_grades[i]
		var fill: Color = Color(1, 1, 1, 0.92) if g < 0 else CookRules.GRADE_COLOR[g]
		if g < 0 and i == next:
			fill = Color(1.0, 0.85, 0.3)
		draw_circle(Vector2(x, y), 20.0, fill)
		draw_arc(Vector2(x, y), 20.0, 0.0, TAU, 32, Color(0.2, 0.12, 0.06), 3.0)
		if i < _verbs.size():
			draw_string(_font(), Vector2(x - 40.0, y - 32.0), _verbs[i], HORIZONTAL_ALIGNMENT_CENTER, 80, 20, Color(1, 1, 1, 0.95 if g < 0 else 0.5))


## 아직 판정하지 않은 가장 이른 박자 (없으면 -1).
func _next_hit() -> int:
	for i: int in _hit_grades.size():
		if _hit_grades[i] < 0:
			var interval: float = float(step.get("interval_ms", 536))
			if _hits[i] * interval - now_t() > -float(step.get("window_ms", 160)) * 2.0:
				return i
	return -1


## 박자 고리를 띄울 화면 자리 (3D 손 닿는 곳을 투영, 없으면 무대 가운데).
func _focus() -> Vector2:
	if counter != null and counter.camera() != null and counter.is_inside_tree():
		var cam: Camera3D = counter.camera()
		var p: Vector3 = counter.focus_point()
		if not cam.is_position_behind(p):
			var v: Vector2 = cam.unproject_position(p)
			return Vector2(clampf(v.x, 60.0, size.x - 60.0), clampf(v.y, 60.0, size.y - 180.0))
	return Vector2(size.x * 0.5, size.y * 0.42)


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(at: Vector2, text: String, font_size: int, color: Color, outline: int = 8) -> void:
	var f: Font = _font()
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p: Vector2 = at - Vector2(w * 0.5, -font_size * 0.35)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0.18, 0.1, 0.05, color.a))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_popups() -> void:
	var now: float = float(Time.get_ticks_msec())
	for p: Dictionary in _popups:
		var age: float = now - float(p["ms"])
		if age > POPUP_MS:
			continue
		var k: float = age / POPUP_MS
		var c: Color = p["color"]
		c.a = 1.0 - k * k
		var font_size: int = 50 if bool(p["big"]) else 40
		var pop: float = 1.0 + 0.25 * maxf(0.0, 1.0 - age / 120.0)
		_text((p["at"] as Vector2) - Vector2(0.0, 40.0 * k), str(p["text"]), int(font_size * pop), c, 10)


func _draw_finish() -> void:
	if _finish_q < 0.0:
		return
	var age: float = float(Time.get_ticks_msec()) - _finish_at
	var k: float = clampf(age / 220.0, 0.0, 1.0)
	var c: Color = CookRules.step_color(_finish_q)
	draw_rect(Rect2(Vector2(0.0, size.y * 0.5 - 70.0), Vector2(size.x, 120.0)), Color(0, 0, 0, 0.3 * k))
	_text(size * 0.5 - Vector2(0.0, 10.0), CookRules.step_word(_finish_q), int(64.0 * (0.6 + 0.4 * k)), c, 10)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
