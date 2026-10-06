class_name AlbumApp
extends PhoneApp
## 앨범 (v16): 찍은 사진(이 기기의 PhotoAlbum)을 칸으로 보고, 눌러 크게 본다. 크게 볼 때 ← → 로 넘기고,
## 같은 마을 친구에게 마을톡으로 보내거나(서버가 확정) 지운다(두 번 눌러야).

const COLUMNS: int = 3

var _names: PackedStringArray = []
## 크게 보는 사진 ("" = 칸 보기).
var _open: String = ""
var _confirm_delete: bool = false
var _caption: String = ""
var _note: String = ""
var _note_color: Color = SOFT


func _init(owner_phone: PhoneWindow = null, open_name: String = "") -> void:
	super(owner_phone)
	_open = open_name


func _ready() -> void:
	Journal.photo_sent.connect(func(_id: String, thread: String) -> void:
		_note = "%s 님에게 보냈어요! 마을톡에서 볼 수 있어요." % GameData.player_name(int(thread.trim_prefix("pl:")))
		_note_color = GOOD
		_build.call_deferred())
	Journal.failed.connect(func(kind: String, code: String) -> void:
		if kind != "photo_up":
			return
		_note = {"too_fast": "조금 있다가 다시 보내요.", "bad_photo": "사진이 너무 커서 보낼 수 없어요."}.get(code, "보내지 못했어요 (%s)" % code)
		_note_color = WARN
		_build.call_deferred())
	_build()


func go_back() -> bool:
	if _open.is_empty():
		return false
	_open = ""
	_build()
	return true


func _build() -> void:
	if not is_inside_tree():
		return
	clear()
	_names = PhotoAlbum.list()
	if not _open.is_empty() and _open in _names:
		_build_viewer()
	else:
		_open = ""
		_build_grid()


func _build_grid() -> void:
	add_child(label("앨범 · %d장" % _names.size(), 32, INK))
	if _names.is_empty():
		add_child(label("아직 사진이 없어요. 카메라 앱으로 찍어 보세요! 셀카 · 풍경 · 포즈를 고를 수 있어요.", 26, SOFT))
		if phone != null:
			var go: Button = button("카메라 열기", 28, GOOD)
			go.pressed.connect(phone.open_app.bind(PhoneWindow.Tab.CAMERA))
			add_child(go)
		return
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	var cell_w: float = (view_width() - 8.0 * (COLUMNS - 1)) / COLUMNS - 4.0
	for n: String in _names:
		var b: Button = Button.new()
		b.name = "Photo_%s" % n
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.custom_minimum_size = Vector2(cell_w, cell_w * 1.25)
		b.icon = PhotoAlbum.thumb(n)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_stylebox_override("normal", EventHud._box(Color(1, 1, 1, 0.9), Color(0.82, 0.74, 0.62), 12, 2, 4))
		b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
		b.add_theme_stylebox_override("pressed", EventHud._box(PICKED, Color(0.82, 0.74, 0.62), 12, 2, 4))
		b.pressed.connect(func() -> void:
			_open = n
			_confirm_delete = false
			Audio.play_ui(Audio.SFX_CLICK)
			_build()
			if phone != null:
				phone.scroll_to_top())
		grid.add_child(b)


func _build_viewer() -> void:
	var index: int = _names.find(_open)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	var back: Button = button("‹ 앨범", 26)
	back.pressed.connect(func() -> void: go_back())
	top.add_child(back)
	var when: Label = label(PhotoAlbum.taken_text(_open), 24, SOFT, false)
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	when.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(when)
	var w: float = minf(view_width(), (view_height() - 360.0) * 0.8)
	var frame: PanelContainer = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", EventHud._box(Color.WHITE, Color(0.82, 0.74, 0.62), 10, 2, 14))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(frame)
	var pic: TextureRect = TextureRect.new()
	pic.name = "Photo"
	pic.texture = PhotoAlbum.texture(_open)
	pic.custom_minimum_size = Vector2(w, w * 1.25)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(pic)
	var nav: HBoxContainer = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	add_child(nav)
	for step: int in [-1, 1]:
		var b: Button = button("← 이전" if step < 0 else "다음 →", 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var to: int = index - step
		b.disabled = to < 0 or to >= _names.size()
		b.pressed.connect(func() -> void:
			_open = _names[to]
			_confirm_delete = false
			_build())
		nav.add_child(b)
	if not _note.is_empty():
		add_child(label(_note, 26, _note_color))
		_note = ""
	# 친구에게 보내기.
	var friends: Array[int] = []
	for slot: int in Net.faces:
		if slot != Net.my_id and not friends.has(slot):
			friends.append(slot)
	var send_card: VBoxContainer = card()
	send_card.add_child(label("마을톡으로 보내기", 28, INK))
	if Net.state != Net.State.ONLINE or friends.is_empty():
		send_card.add_child(label("같은 마을 친구가 있으면 사진을 보낼 수 있어요.", 24, SOFT))
	else:
		var edit: LineEdit = LineEdit.new()
		edit.placeholder_text = "한마디 (없어도 돼요)"
		edit.max_length = 60
		edit.text = _caption
		edit.custom_minimum_size = Vector2(0, 80)
		edit.add_theme_font_size_override("font_size", 28)
		edit.text_changed.connect(func(t: String) -> void: _caption = t)
		send_card.add_child(edit)
		for slot: int in friends:
			var b: Button = button("%s 님에게 보내기" % GameData.player_name(slot), 28, GOOD)
			b.name = "SendTo_%d" % slot
			b.pressed.connect(func() -> void:
				var bytes: PackedByteArray = PhotoAlbum.bytes_of(_open)
				if bytes.is_empty():
					return
				Journal.send_photo("pl:%d" % slot, bytes, _caption)
				_caption = ""
				_note = "보내는 중…"
				_note_color = SOFT
				Audio.play_ui(Audio.SFX_CONFIRM)
				_build())
			send_card.add_child(b)
	var del: Button = button("정말 지울까요? (한 번 더)" if _confirm_delete else "지우기", 26, WARN)
	del.pressed.connect(func() -> void:
		if not _confirm_delete:
			_confirm_delete = true
			_build()
			return
		PhotoAlbum.delete(_open)
		var left: PackedStringArray = PhotoAlbum.list()
		_open = left[mini(index, left.size() - 1)] if not left.is_empty() else ""
		_confirm_delete = false
		Audio.play_ui(Audio.SFX_CANCEL)
		_build())
	add_child(del)
