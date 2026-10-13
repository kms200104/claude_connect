class_name BeatCalibration
extends Control
## 박자 맞추기 (얼음과 불의 춤 보정 화면처럼): 불 · 얼음 두 행성이 '똑' 소리에 맞춰 번갈아 돌며 길 위 칸을 밟는다.
## 소리에 맞춰 화면을 누르면, 누른 때와 소리 난 때의 차이를 모아(처음 몇 번은 몸풀기) 가운데 값을 이 기기의 박자 보정으로 쓴다.
## 리듬 요리(KitchenWindow)는 같은 값(Prefs.BEAT_OFFSET)만큼 늦게 누른 것을 딱 맞은 것으로 본다.
## 박자 기준은 실제로 스피커에서 나는 때 (재생 위치 + 지난 믹스 뒤 시간 - 출력 지연) — 리듬 요리의 노래 시계와 같다.

signal finished(applied: bool)

const BPM: float = 100.0
const INTERVAL: float = 60.0 / BPM
const LOOP_BEATS: int = 4
const SAMPLE_RATE: int = 44100
## 처음 이만큼은 몸풀기 (재지 않는다) · 잴 누름 수.
const WARMUP: int = 4
const NEED: int = 16
## 보정 값 범위 (ms) — 리듬 요리와 같다.
const OFFSET_MIN: float = -120.0
const OFFSET_MAX: float = 250.0
## 아래 막대의 끝 (ms).
const BAR_RANGE: float = 200.0
const FIRE: Color = Color("#FF6A3D")
const ICE: Color = Color("#4AA8FF")
const BG_TOP: Color = Color("#1B1530")
const BG_BOTTOM: Color = Color("#2E2248")
const TILE: Color = Color("#EDE3CC")
const TEXT: Color = Color(1.0, 0.97, 0.9)
const SOFT_TEXT: Color = Color(0.8, 0.76, 0.9)
## 칸 사이 거리 (화면 px) = 도는 행성의 반지름.
const SPACING: float = 150.0

var _player: AudioStreamPlayer = null
var _loops: int = 0
var _start_ms: float = 0.0
var _last_pos: float = 0.0
var _offsets: Array[float] = []
var _taps: int = 0
var _hit_flash: Dictionary[int, Color] = {}
var _popup: String = ""
var _popup_color: Color = TEXT
var _popup_ms: float = -10000.0
var _result: float = INF
var _result_box: PanelContainer = null
var _info: Label = null
var _count: Label = null
var _muted: Dictionary[String, bool] = {}


## 화면 맨 위(휴대폰 · 주방 위)에 띄운다.
static func open(tree: SceneTree) -> BeatCalibration:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BeatCalibrationLayer"
	layer.layer = 90
	var c: BeatCalibration = BeatCalibration.new()
	c.name = "BeatCalibration"
	layer.add_child(c)
	# 루트가 자식을 차리는 중(장면 시작)에도 붙도록 한 박자 미뤄 붙인다.
	tree.root.add_child.call_deferred(layer)
	c.tree_exited.connect(layer.queue_free)
	return c


## 지금 쓰는 보정 값 글 ("+72ms 늦게 누르는 것까지 딱", "보정 없음").
static func offset_text(ms: float) -> String:
	if absf(ms) < 5.0:
		return "보정 없음 (0ms)"
	return "%+dms (%s)" % [roundi(ms), "소리가 늦게 들리는 기기" if ms > 0.0 else "일찍 누르는 편"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	var top: VBoxContainer = VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28.0
	top.offset_right = -28.0
	top.offset_top = 24.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	var title: Label = _label("박자 맞추기", 44, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close_button: Button = _button("닫기", 30)
	close_button.name = "CloseButton"
	close_button.pressed.connect(func() -> void: _close(false))
	row.add_child(close_button)
	_info = _label("'똑' 소리에 맞춰 화면 아무 데나 누르세요. 행성보다 소리에 귀를 기울여요.\n지금 보정: %s" % offset_text(float(Prefs.get_value(Prefs.BEAT_OFFSET))), 26, SOFT_TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_info)
	_count = _label("", 30, TEXT)
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_count.offset_top = -250.0
	_count.offset_bottom = -200.0
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	# 다른 소리(음악 · 환경음)는 잠깐 끈다 — 박자 소리만 또렷하게.
	for bus: String in ["Music", "Ambient"]:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			_muted[bus] = AudioServer.is_bus_mute(index)
			AudioServer.set_bus_mute(index, true)
	_player = AudioStreamPlayer.new()
	_player.bus = "Sfx"
	_player.stream = _metronome()
	add_child(_player)
	_player.play()
	_start_ms = float(Time.get_ticks_msec())
	_update_count()


func _exit_tree() -> void:
	for bus: String in _muted:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_mute(index, _muted[bus])
	_muted.clear()


## 지금 소리 시각 (초, 첫 박자 = 0): 스피커에서 실제로 나는 때.
func song_time() -> float:
	# 소리 장치가 없는 실행(헤드리스 테스트)은 재생 위치가 멈춰 있다 — 시계로 대신한다.
	if DisplayServer.get_name() == "headless" and _start_ms > 0.0:
		return (float(Time.get_ticks_msec()) - _start_ms) / 1000.0
	if _player == null or not _player.playing:
		return -1.0
	var pos: float = _player.get_playback_position()
	if pos + 0.5 < _last_pos:
		_loops += 1
	_last_pos = pos
	return float(_loops) * INTERVAL * float(LOOP_BEATS) + pos + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


func _process(_delta: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# 손가락 한 번 = 누름 한 번 (흉내 낸 마우스 · 터치는 버린다).
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var down: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if not down:
		return
	accept_event()
	tap()


## 누름 하나: 가장 가까운 박자와의 차이를 잰다 (몸풀기 뒤부터 모은다).
func tap() -> void:
	if _result != INF:
		return
	var t: float = song_time()
	if t < 0.0:
		return
	var beat: int = roundi(t / INTERVAL)
	var off_ms: float = (t - float(beat) * INTERVAL) * 1000.0
	if beat < 1 or absf(off_ms) > INTERVAL * 1000.0 * 0.45:
		return
	_taps += 1
	var c: Color = Color("#7EE08A") if absf(off_ms) < 40.0 else (Color("#FFD866") if absf(off_ms) < 90.0 else Color("#FF8A6A"))
	_hit_flash[beat] = c
	_popup = "딱!" if absf(off_ms) < 25.0 else ("%s %+dms" % ["늦게" if off_ms > 0.0 else "빨리", roundi(off_ms)])
	_popup_color = c
	_popup_ms = float(Time.get_ticks_msec())
	if _taps > WARMUP:
		_offsets.append(off_ms)
	_update_count()
	if _offsets.size() >= NEED:
		_finish()


func _update_count() -> void:
	if _count == null:
		return
	if _taps <= WARMUP:
		_count.text = "몸풀기 %d / %d" % [_taps, WARMUP]
	else:
		_count.text = "재는 중 %d / %d" % [_offsets.size(), NEED]


## 가운데 값 (튀는 누름 몇 개에 흔들리지 않게).
static func median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	return sorted[n / 2] if n % 2 == 1 else (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5


func _finish() -> void:
	_result = clampf(median(_offsets), OFFSET_MIN, OFFSET_MAX)
	var spread: float = 0.0
	for o: float in _offsets:
		spread += absf(o - _result)
	spread /= float(_offsets.size())
	_result_box = PanelContainer.new()
	_result_box.name = "Result"
	_result_box.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.98, 0.92, 0.97), Color(0.45, 0.32, 0.22), 30, 5, 26))
	_result_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_box.custom_minimum_size = Vector2(760, 0)
	_result_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_result_box)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_result_box.add_child(col)
	var ink: Color = Color(0.32, 0.2, 0.12)
	col.add_child(_label("박자 보정 결과", 40, ink))
	var line: String = "딱 맞게 누르고 있어요!" if absf(_result) < 15.0 else ("소리보다 %dms %s 누르고 있어요." % [absi(roundi(_result)), "늦게" if _result > 0.0 else "빨리"])
	col.add_child(_label(line, 30, ink))
	var steady: String = "아주 고르게 눌렀어요." if spread < 25.0 else ("고르게 눌렀어요." if spread < 50.0 else "누름이 들쭉날쭉했어요 — 한 번 더 해 보면 더 정확해요.")
	var l: Label = _label("%s 리듬 요리에서 %s 를 딱 맞은 것으로 볼게요." % [steady, offset_text(_result)], 24, Color(0.5, 0.4, 0.3))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	var apply: Button = _button("적용하기", 32)
	apply.name = "ApplyButton"
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply.pressed.connect(func() -> void:
		Prefs.set_value(Prefs.BEAT_OFFSET, snappedf(_result, 1.0))
		Audio.play_ui(Audio.SFX_CONFIRM)
		_close(true))
	buttons.add_child(apply)
	var again: Button = _button("다시", 32)
	again.name = "AgainButton"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(restart)
	buttons.add_child(again)


## 처음부터 다시 잰다.
func restart() -> void:
	_offsets.clear()
	_taps = 0
	_hit_flash.clear()
	_result = INF
	if _result_box != null:
		_result_box.queue_free()
		_result_box = null
	_update_count()


## 잰 결과 (아직이면 INF).
func result() -> float:
	return _result


func _close(applied: bool) -> void:
	if _player != null:
		_player.stop()
	finished.emit(applied)
	queue_free()


# ---- 그리기 ----

func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	# 밤하늘 바탕 (위아래 두 색).
	var bands: int = 12
	for i: int in bands:
		var y0: float = r.size.y * float(i) / float(bands)
		draw_rect(Rect2(0.0, y0, r.size.x, r.size.y / float(bands) + 1.0), BG_TOP.lerp(BG_BOTTOM, float(i) / float(bands - 1)))
	var t: float = song_time()
	if t < -1.0:
		return
	var beats: float = t / INTERVAL
	var b: int = floori(beats)
	var u: float = clampf(beats - float(b), 0.0, 1.0)
	var center: Vector2 = Vector2(r.size.x * 0.5, r.size.y * 0.52)
	# 길 따라 화면이 흘러간다 (지금 축이 되는 칸이 가운데 근처).
	var cam: float = (float(b) + u * u * (3.0 - 2.0 * u)) * SPACING
	for k: int in range(b - 4, b + 8):
		if k < 0:
			continue
		var at: Vector2 = center + Vector2(float(k) * SPACING - cam, 0.0)
		if at.x < -SPACING or at.x > r.size.x + SPACING:
			continue
		var col: Color = TILE if k >= b else TILE.darkened(0.45)
		if _hit_flash.has(k):
			col = _hit_flash[k]
		draw_rect(Rect2(at - Vector2(SPACING * 0.46, 34.0), Vector2(SPACING * 0.92, 68.0)), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(at - Vector2(SPACING * 0.46, 30.0), Vector2(SPACING * 0.92, 60.0)), col)
		if k % LOOP_BEATS == 0:
			draw_circle(at, 6.0, Color(0.3, 0.22, 0.4, 0.6))
	# 두 행성: 박자마다 번갈아 축이 되고, 다른 하나가 반 바퀴 돌아 다음 칸에 내려앉는다.
	var pivot_fire: bool = b % 2 == 0
	var pivot: Vector2 = center + Vector2(float(b) * SPACING - cam, 0.0)
	var angle: float = PI - PI * u
	var mover: Vector2 = pivot + Vector2(cos(angle), -sin(angle)) * SPACING
	var pulse: float = maxf(0.0, 1.0 - u * 5.0)
	draw_arc(pivot, SPACING, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 3.0)
	_planet(pivot, FIRE if pivot_fire else ICE, 34.0 + 8.0 * pulse)
	_planet(mover, ICE if pivot_fire else FIRE, 30.0)
	# 누른 결과 한마디.
	var age: float = float(Time.get_ticks_msec()) - _popup_ms
	if age < 700.0:
		var c: Color = _popup_color
		c.a = 1.0 - age / 700.0
		_text(center + Vector2(0.0, -150.0 - age * 0.05), _popup, 46, c)
	# 아래 막대: 빨리 ← 0 → 늦게, 잰 누름마다 눈금.
	var bar_w: float = minf(r.size.x - 80.0, 900.0)
	var bar: Rect2 = Rect2(Vector2((r.size.x - bar_w) * 0.5, r.size.y - 150.0), Vector2(bar_w, 22.0))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var mid: float = bar.position.x + bar_w * 0.5
	draw_line(Vector2(mid, bar.position.y - 16.0), Vector2(mid, bar.end.y + 16.0), Color(1, 1, 1, 0.6), 3.0)
	for o: float in _offsets:
		var x: float = mid + clampf(o / BAR_RANGE, -1.0, 1.0) * bar_w * 0.5
		draw_line(Vector2(x, bar.position.y - 6.0), Vector2(x, bar.end.y + 6.0), Color(1.0, 0.85, 0.4, 0.85), 4.0)
	if not _offsets.is_empty():
		var m: float = median(_offsets)
		var mx: float = mid + clampf(m / BAR_RANGE, -1.0, 1.0) * bar_w * 0.5
		draw_circle(Vector2(mx, bar.position.y + 11.0), 12.0, Color("#FF6A3D"))
	_text(Vector2(bar.position.x + 60.0, bar.end.y + 44.0), "빨리", 24, SOFT_TEXT)
	_text(Vector2(bar.end.x - 60.0, bar.end.y + 44.0), "늦게", 24, SOFT_TEXT)


func _planet(at: Vector2, color: Color, radius: float) -> void:
	draw_circle(at, radius * 1.6, Color(color, 0.18))
	draw_circle(at, radius, color)
	draw_circle(at + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.35, Color(1, 1, 1, 0.45))


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var f: Font = ThemeDB.fallback_font
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p: Vector2 = at - Vector2(w * 0.5, -font_size * 0.35)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color(0.08, 0.05, 0.12, color.a))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ---- 박자 소리 ----

## 네 박자 한 마디 '똑 딱 딱 딱' (첫 박은 높게), 이음매 없이 돈다 — 소리가 박자 첫 샘플에서 시작해 재생 위치가 곧 박자 시계.
static func _metronome() -> AudioStreamWAV:
	var per_beat: int = roundi(INTERVAL * float(SAMPLE_RATE))
	var total: int = per_beat * LOOP_BEATS
	var data: PackedByteArray = PackedByteArray()
	data.resize(total * 2)
	for beat: int in LOOP_BEATS:
		var freq: float = 1568.0 if beat == 0 else 1046.5
		var length: int = roundi(0.06 * float(SAMPLE_RATE))
		for i: int in length:
			var tt: float = float(i) / float(SAMPLE_RATE)
			var env: float = exp(-tt * 70.0)
			var v: float = (sin(TAU * freq * tt) + 0.35 * sin(TAU * freq * 2.0 * tt)) * env * 0.55
			data.encode_s16((beat * per_beat + i) * 2, clampi(roundi(v * 32767.0), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total
	return wav


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(160, 84)
	b.add_theme_font_size_override("font_size", font_size)
	return b
