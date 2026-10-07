class_name HomeController
extends Node3D
## 아파트 집 구경 (v0.10): 동 공동 현관 앞 상황 버튼 "집 구경" → 엘리베이터 창에서 호수를 고르면 서버가 그 집 안으로 옮겨 준다.
## 집 안은 평면도(FloorPlan)대로 지은 HomeInterior. 현관문 곁에서 "나가기". 내 집(우리 세대 집)이면 "꾸미기"로
## 위에서 내려다보며 가구를 끌어 옮기고(보이지 않는 0.25m 격자), 좌우로 돌리고, 가방에 넣는다 (HomeEditor).

@export var player: Player
@export var camera_rig: FollowCamera
@export var sky: SkyController
@export var hud: CanvasLayer
@export var toast_hud: FishingHud
@export var clay_material: Material
@export var window_material: Material

@export_group("Indoor camera")
## 집 안에서는 조금 더 위에서 내려다본다 (벽에 가리지 않게).
@export_range(30.0, 85.0, 0.5, "suffix:°") var indoor_pitch: float = 60.0
@export_range(3.0, 20.0, 0.1, "suffix:m") var indoor_distance: float = 7.0
@export_range(0.5, 3.0, 0.05, "suffix:m") var exit_range: float = 1.6

const TARGET_LOBBY: String = "lobby:"
const TARGET_EXIT: String = "exit"
const DECOR_BUTTON_Y: float = 340.0

var interior: HomeInterior = null
## 창밖 풍경을 찍는 곳 (마을의 아파트 동). 없으면 창은 하늘색.
@export var apartments: ApartmentSite
## 그 집 발코니에서 바깥으로 이만큼 나간 자리에서 찍는다 (자기 동 벽이 가리지 않게).
@export_range(0.0, 10.0, 0.5, "suffix:m") var view_step_out: float = 2.5
var _view: HomeView = null
var window: HomeWindow = null
var editor: HomeEditor = null
var _decor_button: Button = null
## v16 방명록 (주인이 있는 집 안에서).
var guestbook: GuestbookWindow = null
var _guestbook_button: Button = null
var _outdoor_pitch: float = 48.0
var _outdoor_distance: float = 7.5


func _ready() -> void:
	_view = HomeView.new()
	_view.name = "HomeView"
	add_child(_view)
	interior = HomeInterior.new()
	interior.name = "Interior"
	interior.clay_material = clay_material
	interior.window_material = window_material
	add_child(interior)
	window = HomeWindow.new()
	window.name = "HomeWindow"
	window.chosen.connect(func(unit: String) -> void: Home.enter(unit))
	editor = HomeEditor.new()
	editor.name = "HomeEditor"
	editor.controller = self
	add_child(editor)
	_decor_button = Button.new()
	_decor_button.name = "DecorButton"
	_decor_button.text = "꾸미기"
	_decor_button.focus_mode = Control.FOCUS_NONE
	_decor_button.add_theme_font_size_override("font_size", 30)
	_decor_button.add_theme_color_override("font_color", Color(0.3, 0.22, 0.16))
	_decor_button.add_theme_stylebox_override("normal", EventHud._box(Color(1.0, 0.94, 0.8, 0.96), Color(0.5, 0.36, 0.24), 30, 4, 10))
	_decor_button.add_theme_stylebox_override("pressed", EventHud._box(Color(0.98, 0.84, 0.55), Color(0.5, 0.36, 0.24), 30, 4, 10))
	_decor_button.add_to_group(&"blocks_joystick")
	_decor_button.visible = false
	_decor_button.pressed.connect(func() -> void: editor.start())
	HudLayout.right_top(_decor_button, Vector2(160.0, 84.0), 24.0, DECOR_BUTTON_Y)
	guestbook = GuestbookWindow.new()
	guestbook.name = "GuestbookWindow"
	_guestbook_button = _decor_button.duplicate(Node.DUPLICATE_GROUPS) as Button
	_guestbook_button.name = "GuestbookButton"
	_guestbook_button.text = "방명록"
	_guestbook_button.add_to_group(&"blocks_joystick")
	_guestbook_button.pressed.connect(func() -> void: guestbook.open())
	HudLayout.right_top(_guestbook_button, Vector2(160.0, 84.0), 24.0, DECOR_BUTTON_Y + 100.0)
	if hud != null:
		hud.add_child.call_deferred(window)
		hud.add_child.call_deferred(_decor_button)
		hud.add_child.call_deferred(_guestbook_button)
		hud.add_child.call_deferred(guestbook)
	if camera_rig != null:
		_outdoor_pitch = camera_rig.pitch_degrees
		_outdoor_distance = camera_rig.distance
	Home.door_passed.connect(_on_door)
	Home.furniture_changed.connect(func() -> void:
		interior.sync_furniture(Home.furniture)
		editor.on_furniture_changed())
	Home.failed.connect(_on_failed)


## 엘리베이터 창·꾸미기·방명록 중이면 다른 상황 버튼을 숨긴다.
func is_busy() -> bool:
	return (window != null and window.is_open()) or (editor != null and editor.active) or (guestbook != null and guestbook.is_open())


func pick_target(position: Vector3) -> String:
	if GameData.econ == null:
		return ""
	if Home.is_inside():
		if Home.plan != null and _flat(position, Home.front_world()) <= exit_range:
			return TARGET_EXIT
		return ""
	for b: Variant in GameData.econ.buildings():
		if not b is Dictionary:
			continue
		var id: String = str(b.get("id", ""))
		if _flat(position, GameData.econ.lobby_of(id)) <= GameData.econ.lobby_range() - 0.3:
			return TARGET_LOBBY + id
	return ""


func target_label(target: String) -> String:
	if target.begins_with(TARGET_LOBBY):
		return "집 구경 (%s동)" % target.trim_prefix(TARGET_LOBBY)
	if target == TARGET_EXIT:
		return "나가기"
	return ""


func activate(target: String) -> void:
	if target.begins_with(TARGET_LOBBY):
		window.open(target.trim_prefix(TARGET_LOBBY))
	elif target == TARGET_EXIT:
		Home.exit()


func _process(_delta: float) -> void:
	if _decor_button != null:
		_decor_button.visible = Home.is_inside() and Home.editable and not editor.active and Net.state == Net.State.ONLINE
	if _guestbook_button != null:
		_guestbook_button.visible = Home.is_inside() and Home.owner_slot > 0 and not editor.active and Net.state == Net.State.ONLINE


func _on_door(unit: String, position: Vector3) -> void:
	editor.stop()
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.clear_look_direction()
	if not unit.is_empty():
		interior.global_position = Home.origin
		interior.build(Home.plan)
		interior.visible = true
		interior.sync_furniture(Home.furniture)
		interior.set_view(null)
		_capture_view(unit)
		# 현관에 들어서면 집 안(남쪽, 발코니 쪽)을 바라본다.
		player.body.rotation.y = PI
		if sky != null:
			sky.indoor = true
		if camera_rig != null:
			camera_rig.pitch_degrees = indoor_pitch
			camera_rig.distance = indoor_distance
		var u: EconData.Unit = GameData.econ.unit(unit)
		var whose: String = "내 집" if Home.editable else ("%s 님 집" % GameData.player_name(Home.owner_slot) if Home.owner_slot > 0 else "빈 집 (구경만)")
		toast_hud.show_toast("%s동 %d층 %d호 · %s · %s" % [u.building, u.floor, u.line, Home.plan.display_name if Home.plan != null else "", whose], true)
	else:
		interior.visible = false
		for c: Node in interior.get_children():
			c.queue_free()
		player.body.rotation.y = PI
		if sky != null:
			sky.indoor = false
		if camera_rig != null:
			camera_rig.pitch_degrees = _outdoor_pitch
			camera_rig.distance = _outdoor_distance
	if camera_rig != null:
		camera_rig.snap_to_target()


## 창밖 풍경: 마을의 이 집 발코니 앞에서 여섯 방향을 찍어 창유리에 넣는다 (여섯 프레임쯤, 그동안은 하늘색 유리).
func _capture_view(unit: String) -> void:
	if apartments == null:
		return
	var view: HomeView.View = await _view.capture(apartments.unit_position(unit) + Vector3(0.0, 0.4, view_step_out))
	if view != null and Home.unit == unit:
		interior.set_view(view)


func _on_failed(kind: String, code: String) -> void:
	var msg: String = {
		NetProtocol.ERR_NOT_AT_LOBBY: "공동 현관 앞에서 들어갈 수 있어요",
		NetProtocol.ERR_NOT_EDITABLE: "내 집(우리 세대 집)만 꾸밀 수 있어요",
		NetProtocol.ERR_HOME_FULL: "가구를 더 놓을 수 없어요",
		NetProtocol.ERR_BAD_PLACE: "거기에는 놓을 수 없어요",
		NetProtocol.ERR_INVENTORY_FULL: "가방이 가득 찼어요",
		NetProtocol.ERR_NOT_HOME: "현관문 곁에서 나갈 수 있어요" if kind == "home_exit" else "집 안이 아니에요",
	}.get(code, code)
	toast_hud.show_toast(msg, false)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
