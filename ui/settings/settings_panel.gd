class_name SettingsPanel
extends VBoxContainer
## 설정 내용 (v0.14.2): 휴대폰의 설정 앱과 첫 화면 · 마을의 설정 창이 같이 쓴다.
##   닉네임 — 적고 저장 (마을 안이면 바로 바뀌고, 아니면 들어갈 때 같이 보낸다)
##   소리   — 전체 · 배경음악 · 효과음 · 환경음 0~100% (손을 떼면 효과음으로 들려준다)
##   화질   — 자동(기기 추천) · 절약 · 고화질
##   화면   — 돌리는 대로 · 세로 고정 · 가로 고정
## v16: 생일(마을에 들어와 있을 때) · 진동 켜기/끄기(물고기가 물 때) · 글자 크기 · 조이스틱 위치(왼손/오른손)와 크기.
## 지도 항상 보기 (화면 오른쪽 위 작은 지도). 마을에서는 이 내용이 휴대폰 설정 앱에만 있다 (방 정보 줄 "설정" 단추도 그 앱을 연다).
## 바꾸면 바로 적용되고 기억된다.

const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const PICKED: Color = Color(0.98, 0.84, 0.55)
const CARD: Color = Color(1.0, 1.0, 1.0, 0.72)
const ACCENT: Color = Color("#F2A14A")

## v17 테스트 도구 단추 (테스트 서버일 때만, 테스트에서 누른다).
var dev_button: Button = null
var _name_edit: LineEdit = null
var _name_note: Label = null
var _sliders: Dictionary[String, HSlider] = {}
var _percent: Dictionary[String, Label] = {}
var _quality_buttons: Dictionary[String, Button] = {}
var _quality_info: Label = null
var _orient_buttons: Dictionary[String, Button] = {}
var _pref_buttons: Dictionary[String, Dictionary] = {}
var _vibration: CheckButton = null
var _minimap: CheckButton = null
var _bday_month: int = 1
var _bday_day: int = 1
var _bday_label: Label = null
var _bday_day_label: Label = null
var _bday_note: Label = null

static var _grabber: Texture2D = null


func _init() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_build_name()
	if Net.state == Net.State.ONLINE:
		_build_birthday()
	_build_sound()
	_build_play()
	_build_quality()
	_build_screen()
	if Net.state == Net.State.ONLINE and Net.dev_tools:
		_build_dev()
	Quality.changed.connect(refresh)
	Prefs.events.changed.connect(func(_k: String) -> void: refresh())
	Journal.changed.connect(_refresh_birthday)
	Journal.failed.connect(func(kind: String, _code: String) -> void:
		if kind == "set_birthday" and _bday_note != null and is_instance_valid(_bday_note):
			_bday_note.text = "생일을 저장하지 못했어요. 마을(서버)에 들어와 있을 때 다시 해 보세요.")
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
	for key: String in _pref_buttons:
		for id: String in _pref_buttons[key]:
			_mark(_pref_buttons[key][id], str(Prefs.get_value(key)) == id)
	if _vibration != null:
		_vibration.set_pressed_no_signal(Prefs.vibration())
	if _minimap != null:
		_minimap.set_pressed_no_signal(Prefs.minimap())


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


# ---- 생일 (v16) ----

## 생일: 달 · 날을 ◀ ▶ 로 고르고 저장. 그날 친한 주민들이 마을톡으로 축하해 준다 (한 해에 한 번).
func _build_birthday() -> void:
	var col: VBoxContainer = _section("생일")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_bday_label = _label("", 36, INK, false)
	_bday_day_label = _label("", 36, INK, false)
	for part: Array in [[_bday_label, 1, 0], [_bday_day_label, 0, 1]]:
		var minus: Button = _button("-", 34)
		minus.custom_minimum_size = Vector2(84, 88)
		minus.pressed.connect(_step_birthday.bind(-int(part[1]), -int(part[2])))
		row.add_child(minus)
		var shown: Label = part[0]
		shown.custom_minimum_size = Vector2(130, 0)
		shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(shown)
		var plus: Button = _button("+", 34)
		plus.custom_minimum_size = Vector2(84, 88)
		plus.pressed.connect(_step_birthday.bind(int(part[1]), int(part[2])))
		row.add_child(plus)
	var save_button: Button = _button("생일 저장", 30)
	save_button.name = "SaveBirthday"
	save_button.pressed.connect(func() -> void:
		Journal.set_birthday(_bday_month, _bday_day)
		_bday_note.text = "%d월 %d일로 저장했어요. 그날 친한 주민들이 마을톡으로 축하해 줘요 🎂" % [_bday_month, _bday_day]
		Audio.play_ui(Audio.SFX_CONFIRM))
	col.add_child(save_button)
	_bday_note = _label("그날 친한 주민들이 축하 인사와 선물을 보내요 (한 해에 한 번). 친구 달력에도 보여요.", 24, SOFT)
	col.add_child(_bday_note)
	_refresh_birthday()


## 생일 달 · 날 한 칸씩 (그 달의 마지막 날을 넘지 않게).
func _step_birthday(dm: int, dd: int) -> void:
	_bday_month = posmod(_bday_month - 1 + dm, 12) + 1
	var last: int = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][_bday_month - 1]
	_bday_day = posmod(_bday_day - 1 + dd, last) + 1 if dd != 0 else mini(_bday_day, last)
	_show_birthday()
	Audio.play_ui(Audio.SFX_CLICK)


func _refresh_birthday() -> void:
	if _bday_label == null or not is_instance_valid(_bday_label):
		return
	if Journal.birthday != Vector2i.ZERO:
		_bday_month = Journal.birthday.x
		_bday_day = Journal.birthday.y
	_show_birthday()


func _show_birthday() -> void:
	_bday_label.text = "%d월" % _bday_month
	_bday_day_label.text = "%d일" % _bday_day


# ---- 조작 (v16) ----

## 진동 · 글자 크기 · 조이스틱 위치와 크기.
func _build_play() -> void:
	var col: VBoxContainer = _section("조작 · 글자")
	_vibration = CheckButton.new()
	_vibration.text = "진동 (물고기가 물 때 휴대폰이 떨려요)"
	_vibration.focus_mode = Control.FOCUS_NONE
	_vibration.custom_minimum_size = Vector2(0, 88)
	_vibration.add_theme_font_size_override("font_size", 28)
	_vibration.add_theme_color_override("font_color", INK)
	_vibration.add_theme_color_override("font_pressed_color", INK)
	_vibration.add_theme_color_override("font_hover_color", INK)
	_vibration.toggled.connect(func(on: bool) -> void:
		Prefs.set_value(Prefs.VIBRATION, on)
		if on:
			Prefs.vibrate(60, 0.6)
		Audio.play_ui(Audio.SFX_CLICK))
	col.add_child(_vibration)
	_minimap = _check("지도 항상 보기 (화면 오른쪽 위 작은 지도, 누르면 지도 앱)")
	_minimap.name = "MinimapToggle"
	_minimap.toggled.connect(func(on: bool) -> void:
		Prefs.set_value(Prefs.MINIMAP, on)
		Audio.play_ui(Audio.SFX_CLICK))
	col.add_child(_minimap)
	_choice_row(col, "글자 크기", Prefs.FONT, Prefs.FONT_NAMES)
	_choice_row(col, "조이스틱 자리", Prefs.STICK_SIDE, Prefs.STICK_SIDES)
	_choice_row(col, "조이스틱 크기", Prefs.STICK_SIZE, Prefs.STICK_NAMES)
	col.add_child(_label("조이스틱을 오른쪽에 두면 상황 버튼(대화 · 베기 · 낚시)은 왼쪽 아래로 옮겨져요.", 22, SOFT))


## 켜기/끄기 줄.
func _check(text: String) -> CheckButton:
	var c: CheckButton = CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(0, 88)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_theme_font_size_override("font_size", 28)
	c.add_theme_color_override("font_color", INK)
	c.add_theme_color_override("font_pressed_color", INK)
	c.add_theme_color_override("font_hover_color", INK)
	return c


## 지도 항상 보기 켜기/끄기 (테스트용).
func minimap_toggle() -> CheckButton:
	return _minimap


## 이름 + 고르기 단추 줄 (설정 key 의 값 하나).
func _choice_row(col: VBoxContainer, title: String, key: String, names: Dictionary[String, String]) -> void:
	col.add_child(_label(title, 28, INK, false))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var buttons: Dictionary[String, Button] = {}
	for id: String in names:
		var b: Button = _button(names[id], 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.name = "%s_%s" % [key, id]
		b.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Prefs.set_value(key, id))
		row.add_child(b)
		buttons[id] = b
	_pref_buttons[key] = buttons


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
## 테스트 도구 (v17): 테스트 도구를 켠 서버(서버 실행 파일 · 앱 안 테스트 서버)에서만 보인다. 누르면 서버가 2000억 솔을 준다.
func _build_dev() -> void:
	var col: VBoxContainer = _section("테스트 도구")
	col.add_child(_label("여러 기능(아파트 · 증권 · 은행 · 가구)을 바로 시험해 볼 수 있게 솔을 받아요. 테스트 서버에서만 보이는 단추예요.", 24, SOFT))
	dev_button = _button("테스트: 2000억 솔 받기", 30)
	dev_button.name = "DevGrantButton"
	col.add_child(dev_button)
	var note: Label = _label("", 24, SOFT)
	col.add_child(note)
	dev_button.pressed.connect(func() -> void:
		dev_button.disabled = true
		note.text = "받는 중…"
		Net.request("dev_grant"))
	Net.message_received.connect(func(msg: Dictionary) -> void:
		if str(msg.get("t", "")) == "dev_granted" and is_instance_valid(note):
			Audio.play_sfx("coin", -4.0)
			note.text = "%s 을 받았어요! 지금 %s" % [Money.short(int(msg.get("amount", 0))), Money.short(int(msg.get("sol", 0)))]
			dev_button.disabled = false)
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind == "dev_grant" and is_instance_valid(note):
			note.text = "이 서버는 테스트 도구가 꺼져 있어요 (DEV_TOOLS=1 로 켜기)." if code == NetProtocol.ERR_DEV_OFF else "받지 못했어요 (%s)" % code
			dev_button.disabled = false)


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
