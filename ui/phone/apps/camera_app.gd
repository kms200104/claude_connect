class_name CameraApp
extends PhoneApp
## 카메라 (v16): 휴대폰 화면이 뷰파인더. 같은 마을(World3D)을 작은 SubViewport 의 카메라로 따로 찍는다.
##   셀카 — 캐릭터 앞에서 얼굴 쪽을 (캐릭터가 렌즈를 바라본다) · 풍경 — 캐릭터 눈높이에서 앞을.
##   ← → 로 찍는 방향을 돌리고, 줌 · 색(그대로 · 선명 · 포근 · 흑백) · 포즈(배운 감정표현)를 고른다.
## 셔터를 누르면 찰칵 + 번쩍, 사진은 앨범(PhotoAlbum, 이 기기)에 저장된다. 친구에게 보내기는 앨범에서.

const MODES: PackedStringArray = ["셀카", "풍경"]
## 색 고르기: 이름 · 밝기 · 대비 · 채도 (카메라 환경의 adjustment).
const FILTERS: Array[Array] = [["그대로", 1.0, 1.0, 1.0], ["선명", 1.02, 1.12, 1.3], ["포근", 1.08, 0.92, 0.85], ["흑백", 1.04, 1.1, 0.0]]
const TURN_STEP: float = PI / 6.0

var _mode: int = 0
var _filter: int = 0
## 0 = 가까이 · 1 = 멀리.
var _zoom: float = 0.45
## 찍는 방향 (월드 yaw, 셀카면 캐릭터 앞에서 캐릭터를 보는 방향의 반대).
var _yaw: float = 0.0
var _sub: SubViewport = null
var _cam: Camera3D = null
var _view: TextureRect = null
var _flash: ColorRect = null
var _last_name: String = ""
var _last_thumb: TextureRect = null
var _busy: bool = false


func _ready() -> void:
	_yaw = _start_yaw()
	_build()


func on_close() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED


## 처음 방향: 지금 보고 있는 화면(마을 카메라) 쪽에서 캐릭터를 본다.
func _start_yaw() -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var p: Node3D = phone.player if phone != null else null
	if cam == null or p == null:
		return 0.0
	var d: Vector3 = cam.global_position - p.global_position
	return atan2(d.x, d.z)


func _build() -> void:
	clear()
	tabs(MODES, _mode, func(i: int) -> void:
		_mode = i
		_build())
	_sub = SubViewport.new()
	_sub.name = "Lens"
	_sub.size = PhotoAlbum.SIZE if Quality.preset_id != "low" else Vector2i(384, 480)
	_sub.world_3d = get_viewport().find_world_3d()
	_sub.msaa_3d = get_viewport().msaa_3d
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	_cam = Camera3D.new()
	_cam.near = 0.12
	_cam.current = true
	_sub.add_child(_cam)
	_apply_filter()
	# 뷰파인더: 4:5, 화면 높이에 맞춰.
	var w: float = minf(view_width() - 8.0, (view_height() - 250.0) * 0.8)
	var holder: PanelContainer = PanelContainer.new()
	holder.add_theme_stylebox_override("panel", EventHud._box(Color("#2A2830"), Color("#2A2830"), 18, 0, 6))
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(holder)
	var stack: Control = Control.new()
	stack.custom_minimum_size = Vector2(w, w * 1.25)
	holder.add_child(stack)
	_view = TextureRect.new()
	_view.name = "Viewfinder"
	_view.texture = _sub.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_view)
	# 3분할 안내선 · 번쩍.
	var guide: Control = Control.new()
	guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.draw.connect(func() -> void:
		for i: int in [1, 2]:
			guide.draw_line(Vector2(guide.size.x * i / 3.0, 0), Vector2(guide.size.x * i / 3.0, guide.size.y), Color(1, 1, 1, 0.25), 2.0)
			guide.draw_line(Vector2(0, guide.size.y * i / 3.0), Vector2(guide.size.x, guide.size.y * i / 3.0), Color(1, 1, 1, 0.25), 2.0))
	stack.add_child(guide)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_flash)
	_build_controls()
	_place_camera()


func _build_controls() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	add_child(row)
	_last_thumb = TextureRect.new()
	_last_thumb.custom_minimum_size = Vector2(96, 120)
	_last_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_last_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_last_thumb.mouse_filter = Control.MOUSE_FILTER_STOP
	_last_thumb.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			if phone != null:
				phone.open_album(_last_name))
	var latest: PackedStringArray = PhotoAlbum.list()
	if not latest.is_empty():
		_last_name = latest[0]
		_last_thumb.texture = PhotoAlbum.thumb(_last_name)
	row.add_child(_last_thumb)
	var left: Button = button("←", 36)
	left.custom_minimum_size = Vector2(100, 100)
	left.pressed.connect(func() -> void: _turn(-1.0))
	row.add_child(left)
	var shutter: Button = Button.new()
	shutter.name = "Shutter"
	shutter.focus_mode = Control.FOCUS_NONE
	shutter.custom_minimum_size = Vector2(132, 132)
	shutter.flat = true
	for state: String in ["normal", "hover", "pressed", "focus"]:
		shutter.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	shutter.draw.connect(func() -> void:
		var c: Vector2 = shutter.size * 0.5
		shutter.draw_circle(c, 64.0, Color("#2A2830"))
		shutter.draw_circle(c, 56.0, Color.WHITE)
		shutter.draw_circle(c, 46.0 if not shutter.button_pressed else 40.0, Color("#FF7A3D")))
	shutter.button_down.connect(shutter.queue_redraw)
	shutter.button_up.connect(shutter.queue_redraw)
	shutter.pressed.connect(shoot)
	row.add_child(shutter)
	var right: Button = button("→", 36)
	right.custom_minimum_size = Vector2(100, 100)
	right.pressed.connect(func() -> void: _turn(1.0))
	row.add_child(right)
	var zoom_row: HBoxContainer = HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 12)
	add_child(zoom_row)
	zoom_row.add_child(label("가까이", 24, SOFT, false))
	var zoom: HSlider = HSlider.new()
	zoom.min_value = 0.0
	zoom.max_value = 1.0
	zoom.step = 0.01
	zoom.value = _zoom
	zoom.focus_mode = Control.FOCUS_NONE
	zoom.custom_minimum_size = Vector2(0, 56)
	zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom.value_changed.connect(func(v: float) -> void:
		_zoom = v
		_place_camera())
	zoom_row.add_child(zoom)
	zoom_row.add_child(label("멀리", 24, SOFT, false))
	var names: PackedStringArray = []
	for f: Array in FILTERS:
		names.append(str(f[0]))
	tabs(names, _filter, func(i: int) -> void:
		_filter = i
		_apply_filter()
		_build())
	# 포즈: 배운 감정표현 (친구 화면에도 보인다).
	var poses: HFlowContainer = HFlowContainer.new()
	poses.add_theme_constant_override("h_separation", 8)
	poses.add_theme_constant_override("v_separation", 8)
	add_child(label("포즈", 26, INK, false))
	add_child(poses)
	for id: String in Net.emotes_known:
		var b: Button = button(GameData.emote_name(id), 24)
		b.custom_minimum_size = Vector2(0, 70)
		b.pressed.connect(func() -> void:
			if phone != null and phone.player != null:
				phone.player.play_emote(id)
			Net.send_emote(id))
		poses.add_child(b)


func _turn(dir: float) -> void:
	_yaw += TURN_STEP * dir
	Audio.play_ui(Audio.SFX_CLICK)
	_place_camera()


func _process(_delta: float) -> void:
	_place_camera()


## 카메라 자리: 셀카는 캐릭터 앞(방향 _yaw)에서 얼굴을, 풍경은 캐릭터 눈높이에서 _yaw 반대쪽(앞)을.
func _place_camera() -> void:
	if _cam == null or not is_instance_valid(_cam) or phone == null or phone.player == null:
		return
	var p: Vector3 = phone.player.global_position
	var out: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	if _mode == 0:
		var dist: float = lerpf(1.25, 3.6, _zoom)
		var head: Vector3 = p + Vector3.UP * 1.1
		_cam.global_position = p + out * dist + Vector3.UP * lerpf(1.3, 1.75, _zoom) + out.cross(Vector3.UP) * 0.25
		_cam.look_at(head, Vector3.UP)
		_cam.fov = 50.0
		phone.player.look_toward(out)
	else:
		var eye: Vector3 = p + Vector3.UP * 1.35 - out * 0.4
		_cam.global_position = eye
		_cam.look_at(eye - out * 10.0 + Vector3.DOWN * 1.2, Vector3.UP)
		_cam.fov = lerpf(32.0, 72.0, _zoom)
		phone.player.look_toward(-out)


func _apply_filter() -> void:
	if _cam == null:
		return
	var base: Environment = get_viewport().find_world_3d().environment
	var env: Environment = base.duplicate() if base != null else Environment.new()
	var f: Array = FILTERS[_filter]
	env.adjustment_enabled = _filter != 0
	env.adjustment_brightness = float(f[1])
	env.adjustment_contrast = float(f[2])
	env.adjustment_saturation = float(f[3])
	_cam.environment = env


## 찰칵: 번쩍이고 지금 뷰파인더 그림을 앨범에 저장한다.
func shoot() -> void:
	if _busy or _sub == null:
		return
	_busy = true
	Audio.play_sfx("camera_shutter", -2.0, 1.0, 0.0)
	Prefs.vibrate(30, 0.4)
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_sub):
		_busy = false
		return
	var img: Image = _sub.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != PhotoAlbum.SIZE:
		img.resize(PhotoAlbum.SIZE.x, PhotoAlbum.SIZE.y, Image.INTERPOLATE_BILINEAR)
	_last_name = PhotoAlbum.save(img)
	_flash.color = Color(1, 1, 1, 0.9)
	var t: Tween = create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.35)
	if not _last_name.is_empty():
		_last_thumb.texture = PhotoAlbum.thumb(_last_name)
		_last_thumb.pivot_offset = _last_thumb.size * 0.5
		_last_thumb.scale = Vector2.ONE * 1.3
		create_tween().tween_property(_last_thumb, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_busy = false


## 마지막으로 찍은 사진 이름 (테스트용).
func last_shot() -> String:
	return _last_name
