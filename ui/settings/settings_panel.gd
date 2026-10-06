class_name SettingsPanel
extends VBoxContainer
## 설정 내용 (v0.14.2): 휴대폰의 설정 앱과 첫 화면 · 마을의 설정 창이 같이 쓴다.
##   닉네임 — 적고 저장 (마을 안이면 바로 바뀌고, 아니면 들어갈 때 같이 보낸다)
##   소리   — 전체 · 배경음악 · 효과음 · 환경음 0~100% (손을 떼면 효과음으로 들려준다)
##   화질   — 자동(기기 추천) · 절약 · 고화질
##   화면   — 돌리는 대로 · 세로 고정 · 가로 고정
## 바꾸면 바로 적용되고 기억된다.

const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const PICKED: Color = Color(0.98, 0.84, 0.55)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.72)
const ACCENT: Color = Color("#F2A14A")

var _name_edit: LineEdit = null
var _name_note: Label = null
var _sliders: Dictionary[String, HSlider] = {}
var _percent: Dictionary[String, Label] = {}
var _quality_buttons: Dictionary[String, Button] = {}
var _quality_info: Label = null
var _orient_buttons: Dictionary[String, Button] = {}

static var _grabber: Texture2D = null


func _init() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_build_name()
	_build_sound()
	_build_quality()
	_build_screen()
	Quality.changed.connect(refresh)
	Audio.volume_changed.connect(refresh)
	Net.name_changed.connect(func(id: int, _n: String) -> void:
		if id == Net.my_id and not _name_edit.has_focus():
			_name_edit.text = Net.names.get(Net.my_id, ""))
	refresh()


## 지금 값으로 다시 맞춘다 (창을 열 때).
func refresh() -> void:
	if _name_edit == null:
		return
	if not _name_edit.has_focus():
		_name_edit.text = Net.names.get(Net.my_id, Net.nickname()) if Net.state == Net.State.ONLINE else Net.nickname()
	for kind: String in _sliders:
		_sliders[kind].set_value_no_signal(Audio.volume(kind) * 100.0)
		_percent[kind].text = "%d%%" % roundi(Audio.volume(kind) * 100.0)
	for id: String in _quality_buttons:
		var b: Button = _quality_buttons[id]
		if id == Quality.AUTO:
			var device: String = Quality.device_name if not Quality.device_name.is_empty() else "이 기기"
			b.text = "  자동 — %s 추천: %s" % [device, Quality.preset_name(Quality.recommended)]
		else:
			b.text = "  %s\n  %s" % [Quality.preset_name(id), Quality.preset_about(id)]
		_mark(b, Quality.choice == id)
	if is_inside_tree():
		var root: Window = get_tree().root
		_quality_info.text = "지금: %s · 3D 해상도 %d%% (%d×%d 화면) · 계단 줄이기 %s배 · 그림자 %s" % [
			Quality.preset_name(Quality.preset_id), roundi(Quality.render_scale() * 100.0), root.size.x, root.size.y,
			str(int(Quality.value("msaa", 2))), "부드럽게" if bool(Quality.value("shadow_soft", false)) else "또렷하게"]
	for id: String in _orient_buttons:
		_mark(_orient_buttons[id], ScreenFit.orientation == id)


## 닉네임 입력 칸 (테스트용).
func name_edit() -> LineEdit:
	return _name_edit


## 볼륨 막대 (테스트용).
func volume_slider(kind: String) -> HSlider:
	return _sliders.get(kind)


## 닉네임 저장: 기억해 두고, 마을 안이면 바로 바꾼다.
func save_name() -> void:
	var clean: String = NetProtocol.clean_name(_name_edit.text)
	_name_edit.text = clean
	_name_edit.release_focus()
	Net.set_nickname(clean)
	_name_note.text = ("\"%s\" 로 저장했어요" % clean) if not clean.is_empty() else "기본 이름을 써요"
	Audio.play_ui(Audio.SFX_CONFIRM)


func release_focus_all() -> void:
	if _name_edit != null:
		_name_edit.release_focus()


# ---- 닉네임 ----

func _build_name() -> void:
	var col: VBoxContainer = _section("닉네임")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(0, 96)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = NetProtocol.NAME_MAX
	_name_edit.placeholder_text = "비워 두면 기본 이름"
	_name_edit.add_theme_font_size_override("font_size", 40)
	_name_edit.text_submitted.connect(func(_t: String) -> void: save_name())
	row.add_child(_name_edit)
	var save_button: Button = _button("저장", 34)
	save_button.custom_minimum_size = Vector2(170, 96)
	save_button.pressed.connect(save_name)
	row.add_child(save_button)
	_name_note = _label("글자·숫자 %d자까지 · 마을 사람들 머리 위와 대화에 나와요 (거울에서도 바꿀 수 있어요)" % NetProtocol.NAME_MAX, 24, SOFT)
	col.add_child(_name_note)


# ---- 소리 ----

func _build_sound() -> void:
	var col: VBoxContainer = _section("소리")
	for kind: String in Audio.VOLUME_KINDS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		col.add_child(row)
		var name_label: Label = _label(Audio.VOLUME_NAMES[kind], 28, INK, false)
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_label)
		var slider: HSlider = _slider()
		slider.name = "Volume_%s" % kind
		slider.value_changed.connect(func(v: float) -> void:
			Audio.set_volume(kind, v / 100.0)
			_percent[kind].text = "%d%%" % roundi(v))
		slider.drag_ended.connect(func(_changed: bool) -> void:
			# 효과음 쪽은 손을 떼면 들려준다 (음악은 지금 흐르는 곡으로 바로 들린다).
			if kind == "master" or kind == "sfx":
				Audio.play_ui(Audio.SFX_CONFIRM))
		row.add_child(slider)
		_sliders[kind] = slider
		var pct: Label = _label("", 28, SOFT, false)
		pct.custom_minimum_size = Vector2(90, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pct)
		_percent[kind] = pct


func _slider() -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 72)
	# 손가락으로 잡기 쉬운 굵은 막대 + 큰 손잡이.
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.85, 0.78, 0.68)
	track.set_corner_radius_all(10)
	track.content_margin_top = 8.0
	track.content_margin_bottom = 8.0
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = ACCENT
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _grabber_icon())
	s.add_theme_icon_override("grabber_highlight", _grabber_icon())
	return s


static func _grabber_icon() -> Texture2D:
	if _grabber != null:
		return _grabber
	var d: int = 52
	var img: Image = Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(d, d) * 0.5
	for y: int in d:
		for x: int in d:
			var r: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a: float = clampf(d * 0.5 - r, 0.0, 1.0)
			var col: Color = Color.WHITE if r < d * 0.5 - 5.0 else ACCENT.darkened(0.15)
			img.set_pixel(x, y, Color(col, a))
	_grabber = ImageTexture.create_from_image(img)
	return _grabber


# ---- 화질 ----

func _build_quality() -> void:
	var col: VBoxContainer = _section("화질")
	for id: String in [Quality.AUTO] + Array(Quality.preset_ids()):
		var b: Button = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 116)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 30)
		b.add_theme_color_override("font_color", INK)
		b.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Quality.choose(id)
			refresh())
		col.add_child(b)
		_quality_buttons[id] = b
	_quality_info = _label("", 22, SOFT)
	col.add_child(_quality_info)


# ---- 화면 ----

func _build_screen() -> void:
	var col: VBoxContainer = _section("화면 방향")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	for id: String in ScreenFit.ORIENT_NAMES:
		var b: Button = _button(ScreenFit.ORIENT_NAMES[id], 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			ScreenFit.set_orientation(id)
			refresh())
		row.add_child(b)
		_orient_buttons[id] = b


# ---- 모양 ----

## 제목 + 흰 카드. 카드 안 줄을 돌려준다.
func _section(title: String) -> VBoxContainer:
	add_child(_label(title, 34, INK, false))
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", EventHud._box(CARD, Color(0.8, 0.72, 0.6), 26, 2, 20))
	add_child(card)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	return col


func _mark(b: Button, picked: bool) -> void:
	b.add_theme_stylebox_override("normal", EventHud._box(PICKED if picked else Color(1, 1, 1, 0.92), EDGE, 22, 5 if picked else 2, 12))
	b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	return b


func _label(text: String, font_size: int, color: Color, wrap: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
