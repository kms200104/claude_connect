class_name MirrorWindow
extends Control
## 거울 창 (거울 앞에서 상황 버튼으로 연다): 카메라가 얼굴 앞으로 다가가고, 아래 판에서 눈·코·입·피부·머리를 고른다.
## 고르는 동안은 내 캐릭터에만 미리 입혀 보고, "완료"를 누르면 서버에 바꾼 항목만 요청한다 (닫기 = 처음대로).
## 위쪽 빈 곳을 좌우로 끌면 캐릭터가 돌아서 옆모습도 볼 수 있다. 내가 놓은 거울 가구면 "가방에 넣기"도 있다.
## v14: "이름" 탭에서 닉네임도 바꾼다 ("완료" 때 얼굴과 같이 보낸다). 글자판이 올라오면 판을 그만큼 올린다.

signal closed

const BG: Color = Color(0.99, 0.96, 0.88, 0.97)
const EDGE: Color = Color(0.45, 0.36, 0.26)
const INK: Color = Color(0.36, 0.24, 0.14)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const PICKED: Color = Color(0.98, 0.84, 0.55)
## 탭: (이름, 모양 항목, 색 항목).
const TABS: Array[Array] = [["눈", "eyes", "eye_color"], ["코", "nose", ""], ["입", "mouth", ""], ["피부", "skin", ""], ["머리", "hair", "hair_color"], ["이름", NAME_TAB, ""]]
const NAME_TAB: String = "name"
const PANEL_SIZE: Vector2 = Vector2(1032, 860)
const PANEL_BOTTOM: float = 20.0
## 가로 화면: 얼굴을 화면 왼쪽에 두려고 바라보는 점을 오른쪽으로 옮기는 만큼 (m).
const MIRROR_SIDE: float = 0.95

@export var player: Player
@export var camera_rig: FollowCamera
## 얼굴 클로즈업: 거리(m), 내려다보는 각도(°), 바라보는 높이(발 기준 m — 얼굴이 화면 위쪽에 오도록 낮게).
@export var face_distance: float = 2.1
@export var face_pitch_degrees: float = 4.0
@export var face_look_height: float = 0.72
## 끌어서 돌리는 빠르기 (화면 1px 당 라디안).
@export var drag_turn: float = 0.008

var face: Dictionary = {}
var _original: Dictionary = {}
var _tab: int = 0
var _furniture_id: String = ""
var _saving: bool = false
var _yaw: float = 0.0
var _camera_saved: Vector3 = Vector3.ZERO
var _camera_yaw_saved: float = 0.0
## 캐릭터가 바라보는 방향 (거울 반대쪽 = 카메라 쪽).
var _facing: Vector3 = Vector3.BACK
var _panel: PanelContainer = null
var _tabs_row: HBoxContainer = null
var _grid: GridContainer = null
var _colors: HBoxContainer = null
var _status: Label = null
var _pickup: Button = null
var _option_buttons: Dictionary[String, Button] = {}
var _scroll: ScrollContainer = null
var _name_box: VBoxContainer = null
var _name_edit: LineEdit = null
var _name_hint: Label = null
## 서버 답을 기다리는 것 (얼굴 · 이름). 둘 다 오면 닫는다.
var _wait_face: bool = false
var _wait_name: bool = false
## 글자판 때문에 판을 올린 만큼 (UI 좌표).
var _lift: float = 0.0


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", EventHud._box(BG, EDGE, 40, 6, 24))
	_panel.custom_minimum_size = PANEL_SIZE
	# 세로: 화면 아래 가운데 (길쭉한 S24 화면에서도 얼굴은 위에, 판은 아래에). 가로: 오른쪽 (얼굴은 왼쪽).
	_layout_panel()
	ScreenFit.changed.connect(func(_wide: bool) -> void: _layout_panel())
	add_child(_panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title: Label = _label("거울", 44, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_pickup = _button("가방에 넣기", 28)
	_pickup.pressed.connect(_on_pickup)
	head.add_child(_pickup)
	var reset: Button = _button("처음대로", 28)
	reset.pressed.connect(func() -> void: _apply(_original.duplicate()))
	head.add_child(reset)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 8)
	col.add_child(_tabs_row)
	for i: int in TABS.size():
		var tab: Button = _button(str(TABS[i][0]), 34)
		tab.custom_minimum_size = Vector2(152, 76)
		tab.pressed.connect(_select_tab.bind(i))
		_tabs_row.add_child(tab)
	_colors = HBoxContainer.new()
	_colors.add_theme_constant_override("separation", 8)
	col.add_child(_colors)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_grid)
	_build_name_box(col)
	var foot: HBoxContainer = HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_status = _label("", 28, SOFT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_status)
	var cancel: Button = _button("닫기", 34)
	cancel.custom_minimum_size = Vector2(170, 84)
	cancel.pressed.connect(close)
	foot.add_child(cancel)
	var done: Button = _button("완료", 34)
	done.custom_minimum_size = Vector2(220, 84)
	done.add_theme_stylebox_override("normal", EventHud._box(PICKED, EDGE, 26, 4, 10))
	done.pressed.connect(save)
	foot.add_child(done)
	Net.face_changed.connect(_on_face_changed)
	Net.name_changed.connect(_on_name_changed)
	Net.request_failed.connect(_on_request_failed)
	Net.state_changed.connect(func(s: int) -> void:
		if s != Net.State.ONLINE:
			close())


func is_open() -> bool:
	return visible


## furniture_id: 내가 놓은 거울 가구에서 열었으면 그 id (가방에 넣기 단추가 보인다).
## mirror_at: 거울 자리. 카메라를 거울 반대쪽에 두고 캐릭터를 카메라 쪽으로 돌려 세워서, 거울이 얼굴을 가리지 않고 등 뒤에 비친다.
func open(furniture_id: String = "", mirror_at: Vector3 = Vector3.INF) -> void:
	if visible:
		return
	_furniture_id = furniture_id
	var mine: bool = not furniture_id.is_empty() and Net.placed.has(furniture_id) and Net.placed[furniture_id].owner == Net.my_id
	_pickup.visible = mine
	_original = GameData.face.sanitize(Net.faces.get(Net.my_id, {}), Net.my_id)
	face = _original.duplicate()
	_saving = false
	_wait_face = false
	_wait_name = false
	_name_edit.text = Net.names.get(Net.my_id, "")
	_name_hint.text = "비워 두면 기본 이름 \"%s\" · 글자·숫자 %d자까지" % [GameData.default_player_name(Net.my_id), NetProtocol.NAME_MAX]
	_status.text = "위쪽을 좌우로 끌면 돌아볼 수 있어요"
	visible = true
	_yaw = 0.0
	_facing = Vector3.BACK
	if player != null and mirror_at != Vector3.INF:
		var away: Vector3 = player.global_position - mirror_at
		away.y = 0.0
		if away.length() > 0.05:
			_facing = away.normalized()
	if player != null:
		player.set_input_lock(&"mirror", true)
		player.look_toward(_facing)
		# 손에 든 도구는 잠깐 내려놓는다 (얼굴을 가린다).
		if player.rig != null:
			player.rig.set_held("")
	if camera_rig != null:
		_camera_yaw_saved = camera_rig.yaw_degrees
		_turn_camera(rad_to_deg(atan2(_facing.x, _facing.z)))
		_camera_saved = Vector3(camera_rig.focus_distance, camera_rig.focus_pitch_degrees, camera_rig.focus_height)
		camera_rig.focus_distance = face_distance
		camera_rig.focus_pitch_degrees = face_pitch_degrees
		camera_rig.focus_height = face_look_height
		camera_rig.focus_side = MIRROR_SIDE if ScreenFit.landscape else 0.0
		camera_rig.set_focus(1.0, 0.6)
	# 이벤트 알림 카드가 얼굴을 가리지 않게 거울을 보는 동안 숨긴다.
	_set_popups_visible(false)
	Audio.play_ui(Audio.SFX_OPEN)
	_select_tab(0)


## 닫기: 저장하지 않은 바꿈은 되돌린다.
func close() -> void:
	if not visible:
		return
	visible = false
	_name_edit.release_focus()
	_set_lift(0.0)
	_preview(_saved_face())
	if player != null:
		player.set_input_lock(&"mirror", false)
		player.clear_look_direction()
		if player.rig != null:
			player.rig.set_held(player.held_item)
	if camera_rig != null:
		camera_rig.set_focus(0.0, 0.5)
		_turn_camera(_camera_yaw_saved)
		var saved: Vector3 = _camera_saved
		get_tree().create_timer(0.55).timeout.connect(func() -> void:
			if not visible and camera_rig.focus <= 0.0:
				camera_rig.focus_distance = saved.x
				camera_rig.focus_pitch_degrees = saved.y
				camera_rig.focus_height = saved.z
				camera_rig.focus_side = 0.0)
	_set_popups_visible(true)
	Audio.play_ui(Audio.SFX_CLOSE)
	closed.emit()


func _set_popups_visible(shown: bool) -> void:
	var events: CanvasItem = get_parent().get_node_or_null("EventHud") as CanvasItem
	if events != null:
		events.visible = shown


## 완료: 바뀐 항목만 서버에 보낸다 (얼굴 · 이름, 바뀐 게 없으면 그냥 닫는다).
func save() -> void:
	var changes: Dictionary = {}
	for key: String in FaceCatalog.KEYS:
		if str(face.get(key, "")) != str(_original.get(key, "")):
			changes[key] = face[key]
	var new_name: String = NetProtocol.clean_name(_name_edit.text)
	var renamed: bool = new_name != str(Net.names.get(Net.my_id, ""))
	if changes.is_empty() and not renamed:
		close()
		return
	_saving = true
	_wait_face = not changes.is_empty()
	_wait_name = renamed
	_status.text = "거울에 비춰 보는 중…"
	if _wait_face:
		Net.set_face(changes)
	if _wait_name:
		Net.set_nickname(new_name)


## 이름 탭의 입력 칸 (테스트용).
func name_edit() -> LineEdit:
	return _name_edit


func _build_name_box(col: VBoxContainer) -> void:
	_name_box = VBoxContainer.new()
	_name_box.add_theme_constant_override("separation", 14)
	_name_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name_box.visible = false
	col.add_child(_name_box)
	_name_box.add_child(_label("닉네임 — 마을 사람들 머리 위와 대화에 나와요", 30, INK))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(0, 104)
	_name_edit.max_length = NetProtocol.NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.placeholder_text = "닉네임"
	_name_edit.add_theme_font_size_override("font_size", 46)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _name_edit.release_focus())
	_name_box.add_child(_name_edit)
	_name_hint = _label("", 26, SOFT)
	_name_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_box.add_child(_name_hint)


func _process(_delta: float) -> void:
	if not visible:
		return
	# 글자판이 올라와 있으면 이름 칸이 가려지지 않게 판을 올린다.
	var want: float = 0.0
	if _name_edit.has_focus():
		var kb: float = float(DisplayServer.virtual_keyboard_get_height())
		var window_h: float = float(DisplayServer.window_get_size().y)
		if kb > 0.0 and window_h > 0.0:
			want = kb * get_viewport_rect().size.y / window_h
	if absf(want - _lift) > 1.0:
		_set_lift(want)


func _set_lift(value: float) -> void:
	_lift = value
	_layout_panel()


## 판 자리: 세로는 아래 가운데, 가로는 오른쪽 (위 정보 줄 아래부터). 글자판이 올라오면 그만큼 올린다.
func _layout_panel() -> void:
	if ScreenFit.landscape:
		_panel.anchor_left = 1.0
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
		# 오른쪽 단추 줄(휴대폰 · 감정표현) 왼쪽에.
		_panel.offset_left = -170.0 - PANEL_SIZE.x
		_panel.offset_right = -170.0
		_panel.offset_top = 150.0 - _lift
		_panel.offset_bottom = -PANEL_BOTTOM - _lift
		_panel.custom_minimum_size = Vector2(PANEL_SIZE.x, 0.0)
	else:
		_panel.custom_minimum_size = PANEL_SIZE
		HudLayout.center_bottom(_panel, PANEL_SIZE.x, PANEL_SIZE.y, PANEL_BOTTOM + _lift)
	# 방향이 바뀔 때는 HudLayout 이 아니라 여기서 다시 맞춘다.
	if _panel.is_in_group(HudLayout.GROUP):
		_panel.remove_from_group(HudLayout.GROUP)
	if camera_rig != null and visible:
		camera_rig.focus_side = MIRROR_SIDE if ScreenFit.landscape else 0.0


## 지금 탭에서 고를 수 있는 모양 단추 (테스트용).
func option_button(part_id: String) -> Button:
	return _option_buttons.get(part_id)


func current_tab() -> String:
	return str(TABS[_tab][1])


func select_tab_key(key: String) -> void:
	for i: int in TABS.size():
		if TABS[i][1] == key:
			_select_tab(i)


## key 항목을 part_id 로 (미리 보기).
func pick(key: String, part_id: String) -> void:
	if GameData.face.part(key, part_id) == null:
		return
	face[key] = part_id
	_apply(face)


func _apply(new_face: Dictionary) -> void:
	face = new_face
	_preview(face)
	_refresh_marks()
	Audio.play_ui(Audio.SFX_CLICK)


func _preview(f: Dictionary) -> void:
	if player != null and player.rig != null:
		player.rig.set_look(GameData.player_look(Net.my_id, f))


func _saved_face() -> Dictionary:
	return GameData.face.sanitize(Net.faces.get(Net.my_id, {}), Net.my_id)


func _select_tab(index: int) -> void:
	_tab = index
	for i: int in _tabs_row.get_child_count():
		var b: Button = _tabs_row.get_child(i)
		b.add_theme_stylebox_override("normal", EventHud._box(PICKED if i == index else Color(1, 1, 1, 0.9), EDGE, 26, 4, 8))
	for child: Node in _grid.get_children():
		child.queue_free()
	for child: Node in _colors.get_children():
		child.queue_free()
	_option_buttons.clear()
	var key: String = TABS[index][1]
	var color_key: String = TABS[index][2]
	_scroll.visible = key != NAME_TAB
	_name_box.visible = key == NAME_TAB
	if key == NAME_TAB:
		_colors.visible = false
		return
	_name_edit.release_focus()
	var look: CharacterLook = GameData.player_look(Net.my_id, face)
	for part: FaceCatalog.Part in GameData.face.list(key):
		var b: Button = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(236, 200)
		var box: VBoxContainer = VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(box)
		var icon: FacePartIcon = FacePartIcon.new()
		icon.custom_minimum_size = Vector2(236, 140)
		icon.setup(key, part.id, look)
		box.add_child(icon)
		var name_label: Label = _label(part.display_name, 26, INK)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name_label)
		b.pressed.connect(pick.bind(key, part.id))
		_grid.add_child(b)
		_option_buttons[part.id] = b
	if not color_key.is_empty():
		for part: FaceCatalog.Part in GameData.face.list(color_key):
			var sw: Button = Button.new()
			sw.focus_mode = Control.FOCUS_NONE
			sw.custom_minimum_size = Vector2(92, 92)
			sw.tooltip_text = part.display_name
			var dot: FacePartIcon = FacePartIcon.new()
			dot.set_anchors_preset(Control.PRESET_FULL_RECT)
			dot.setup(color_key, part.id, look)
			sw.add_child(dot)
			sw.pressed.connect(pick.bind(color_key, part.id))
			_colors.add_child(sw)
			_option_buttons["%s:%s" % [color_key, part.id]] = sw
	_colors.visible = not color_key.is_empty()
	_refresh_marks()


## 고른 것에 노란 바탕 (그림도 지금 피부·눈동자 색으로 다시 그린다).
func _refresh_marks() -> void:
	var key: String = TABS[_tab][1]
	if key == NAME_TAB:
		return
	var color_key: String = TABS[_tab][2]
	var look: CharacterLook = GameData.player_look(Net.my_id, face)
	for id: String in _option_buttons:
		var b: Button = _option_buttons[id]
		var picked: bool = false
		if id.contains(":"):
			picked = id == "%s:%s" % [color_key, face.get(color_key, "")]
		else:
			picked = id == str(face.get(key, ""))
			for child: Node in b.get_child(0).get_children():
				if child is FacePartIcon:
					(child as FacePartIcon).setup(key, id, look)
		var bg: Color = PICKED if picked else Color(1, 1, 1, 0.92)
		b.add_theme_stylebox_override("normal", EventHud._box(bg, EDGE if picked else Color(0.8, 0.72, 0.62), 22, 5 if picked else 2, 6))
		b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
		b.add_theme_stylebox_override("pressed", EventHud._box(PICKED.darkened(0.08), EDGE, 22, 5, 6))


func _on_face_changed(player_id: int, _face: Dictionary) -> void:
	if player_id != Net.my_id or not _saving or not _wait_face:
		return
	_wait_face = false
	_original = _saved_face()
	_finish_save()


func _on_name_changed(player_id: int, _name: String) -> void:
	if player_id != Net.my_id or not _saving or not _wait_name:
		return
	_wait_name = false
	_finish_save()


func _finish_save() -> void:
	if _wait_face or _wait_name:
		return
	_saving = false
	Audio.play_sfx("emote_up", -4.0)
	if player != null:
		player.play_emote("happy")
	close()


func _on_request_failed(kind: String, code: String) -> void:
	if kind not in ["set_face", "set_name"] or not visible:
		return
	_saving = false
	_wait_face = false
	_wait_name = false
	if kind == "set_name":
		_status.text = "그 이름은 쓸 수 없어요 (글자·숫자 %d자까지)" % NetProtocol.NAME_MAX
		return
	_status.text = "거울에서 너무 멀어요" if code == NetProtocol.ERR_NOT_NEAR_MIRROR else "그 모양은 고를 수 없어요"


func _on_pickup() -> void:
	if _furniture_id.is_empty():
		return
	var id: String = _furniture_id
	close()
	Net.pickup_furniture(id)


## 위쪽(판 바깥)을 좌우로 끌면 캐릭터를 돌린다.
func _gui_input(event: InputEvent) -> void:
	if player == null:
		return
	var dx: float = 0.0
	if event is InputEventScreenDrag:
		dx = (event as InputEventScreenDrag).relative.x
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		dx = (event as InputEventMouseMotion).relative.x
	if dx != 0.0:
		_yaw = clampf(_yaw + dx * drag_turn, -PI * 0.8, PI * 0.8)
		player.look_toward(_facing.rotated(Vector3.UP, _yaw))
		accept_event()


## 카메라를 가까운 쪽으로 부드럽게 돌린다.
func _turn_camera(target_degrees: float) -> void:
	var from: float = camera_rig.yaw_degrees
	var goal: float = from + wrapf(target_degrees - from, -180.0, 180.0)
	var tween: Tween = camera_rig.create_tween()
	tween.tween_property(camera_rig, "yaw_degrees", goal, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: camera_rig.yaw_degrees = wrapf(goal, -180.0, 180.0))


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_stylebox_override("normal", EventHud._box(Color(1, 1, 1, 0.9), EDGE, 26, 4, 8))
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
