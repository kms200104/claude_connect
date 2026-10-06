class_name MusicApp
extends PhoneApp
## 음악 (v16): 마을 배경음악을 골라 듣는 플레이어. "자동"이면 예전처럼 시각 · 날씨 · 이벤트에 맞춰 흐른다.
## 고른 곡은 기억된다 (Prefs.MUSIC). 돌아가는 레코드판 · 흐른 시간 막대 · 곡 목록.

const TRACKS: Array[Array] = [
	["", "자동", "시각 · 날씨 · 이벤트에 맞춰 바뀌어요", Color("#8C97A6")],
	["village_theme", "솔바람 한낮", "햇살 좋은 마을의 낮 노래", Color("#F2B53A")],
	["night_theme", "별빛 밤", "풀벌레가 우는 조용한 밤", Color("#5A6AC8")],
	["rain_theme", "빗방울 산책", "비 오는 날 창가에서", Color("#4C8FE0")],
	["event_theme", "마을 축제", "이벤트 날의 들뜬 노래", Color("#E8594A")],
	["title_theme", "처음 만난 섬", "첫 화면의 노래", Color("#3DAA6D")],
	["off", "끄기", "배경음악 없이 마을 소리만", Color("#B8B2A8")],
]

var _disc: Control = null
var _now: Label = null
var _time: Label = null
var _bar: MeterBar = null
var _spin: float = 0.0


func _ready() -> void:
	_build()
	Prefs.events.changed.connect(func(key: String) -> void:
		if key == Prefs.MUSIC and is_inside_tree():
			_build.call_deferred())


func _process(delta: float) -> void:
	if _disc == null or not is_instance_valid(_disc):
		return
	var playing: bool = not Audio.current_music().is_empty()
	if playing:
		_spin = fmod(_spin + delta * 0.9, TAU)
		_disc.queue_redraw()
	var length: float = Audio.music_length()
	var at: float = Audio.music_position()
	if length > 0.0:
		at = fmod(at, length)
	_bar.ratio = at / length if length > 0.0 else 0.0
	_time.text = "%d:%02d / %d:%02d" % [int(at) / 60, int(at) % 60, int(length) / 60, int(length) % 60] if length > 0.0 else "—"
	_now.text = "지금 흐르는 곡: %s" % _track_name(Audio.current_music())


func _build() -> void:
	clear()
	var head: VBoxContainer = card()
	_disc = Control.new()
	_disc.custom_minimum_size = Vector2(0, 300)
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.draw.connect(_draw_disc)
	head.add_child(_disc)
	_now = label("", 30, INK)
	_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_now)
	_bar = MeterBar.make(14.0, 0.0, Color("#E8A04A"))
	head.add_child(_bar)
	_time = label("", 22, SOFT, false)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_time)
	var picked: String = Prefs.music()
	for t: Array in TRACKS:
		var id: String = str(t[0])
		var row: Button = row_button(110.0)
		row.name = "Track_%s" % (id if not id.is_empty() else "auto")
		var line: HBoxContainer = fill_row(row, 16)
		var dot: Control = Control.new()
		dot.custom_minimum_size = Vector2(64, 64)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color: Color = t[3]
		var chosen: bool = id == picked
		dot.draw.connect(func() -> void:
			var c: Vector2 = dot.size * 0.5
			dot.draw_circle(c, 30.0, color)
			if chosen:
				# ▶ 표시.
				dot.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -12), c + Vector2(13, 0), c + Vector2(-8, 12)]), Color.WHITE)
			else:
				dot.draw_circle(c, 9.0, Color(1, 1, 1, 0.85)))
		line.add_child(dot)
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(text)
		text.add_child(label(str(t[1]), 30, INK if not chosen else GOOD, false))
		text.add_child(label(str(t[2]), 22, SOFT, false))
		if chosen:
			row.add_theme_stylebox_override("normal", EventHud._box(Color(1.0, 0.95, 0.8, 0.95), color, 22, 4, 16))
		row.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Prefs.set_value(Prefs.MUSIC, id))
		add_child(row)
	add_child(label("소리 크기는 설정 앱에서 바꿔요.", 22, SOFT))


static func _track_name(id: String) -> String:
	if id.is_empty():
		return "(조용히)"
	for t: Array in TRACKS:
		if str(t[0]) == id:
			return str(t[1])
	return id


## 레코드판: 검은 판 · 홈 · 곡 색 가운데 딱지 · 바늘.
func _draw_disc() -> void:
	var c: Vector2 = _disc.size * 0.5
	var r: float = minf(_disc.size.y * 0.46, 140.0)
	var track: String = Audio.current_music()
	var color: Color = Color("#8C97A6")
	for t: Array in TRACKS:
		if str(t[0]) == track:
			color = t[3]
	_disc.draw_circle(c + Vector2(0, 6), r, Color(0, 0, 0, 0.15))
	_disc.draw_circle(c, r, Color("#2A2830"))
	for i: int in 5:
		_disc.draw_arc(c, r * (0.5 + i * 0.1), 0.0, TAU, 48, Color(1, 1, 1, 0.06), 2.0, true)
	_disc.draw_arc(c, r * 0.82, _spin, _spin + 0.9, 16, Color(1, 1, 1, 0.18), 6.0, true)
	_disc.draw_arc(c, r * 0.82, _spin + PI, _spin + PI + 0.9, 16, Color(1, 1, 1, 0.18), 6.0, true)
	_disc.draw_circle(c, r * 0.34, color)
	_disc.draw_circle(c, r * 0.05, Color("#2A2830"))
	var mark: Vector2 = c + Vector2(cos(_spin), sin(_spin)) * r * 0.22
	_disc.draw_circle(mark, r * 0.04, Color(1, 1, 1, 0.8))
	# 바늘.
	var base: Vector2 = c + Vector2(r * 1.15, -r * 0.85)
	var tip: Vector2 = c + Vector2(r * 0.62, r * 0.2) if not track.is_empty() else c + Vector2(r * 1.1, r * 0.05)
	_disc.draw_line(base, tip, Color("#D5D9DE"), 7.0, true)
	_disc.draw_circle(base, 14.0, Color("#B8BCC4"))
	_disc.draw_circle(tip, 8.0, Color("#8C97A6"))
