class_name HomeEditor
extends Node
## 집 꾸미기 (v0.10): 바로 위에서 내려다보는 카메라(직교)로 평면도를 보며 가구를 손가락으로 끌어 옮긴다.
## 보이지 않는 격자(0.25m)에 저절로 맞춰져 줄을 맞추느라 애쓰지 않아도 되고, 버튼으로 왼쪽·오른쪽 45° 씩 돌린다.
## 가구는 한 방 안(거실·주방·복도·현관은 하나로)에서만, 네 귀퉁이가 바닥 위에 있어야 놓인다 — 벽을 뚫거나 두 방에 걸치지 않는다.
## 확정은 서버(home_move · home_place · home_pickup). 거절되면 원래 자리로 돌아간다.

var controller: HomeController = null
var active: bool = false

const HIGHLIGHT: Color = Color(1.0, 0.82, 0.3, 0.55)
const BAD: Color = Color(1.0, 0.35, 0.3, 0.6)

var _camera: Camera3D = null
var _layer: CanvasLayer = null
var _info: Label = null
var _bag: HBoxContainer = null
var _actions: Array[Button] = []
var _marker: MeshInstance3D = null
var _marker_mat: StandardMaterial3D = null
var _selected: String = ""
var _pressing: bool = false
var _dragging: bool = false
var _press_screen: Vector2 = Vector2.ZERO
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_at: Vector2 = Vector2.ZERO
var _drag_ok: bool = true
## 가방에서 놓은 가구를 서버가 받아 주면 그 가구를 고른다.
var _select_new: bool = false
var _before_ids: Dictionary[String, bool] = {}
var _hud_was_visible: bool = true


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "DecorCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.near = 0.5
	_camera.far = 80.0
	add_child(_camera)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = HIGHLIGHT
	_marker = MeshInstance3D.new()
	_marker.name = "SelectMarker"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.0, 0.02, 1.0)
	_marker.mesh = box
	_marker.material_override = _marker_mat
	_marker.visible = false
	add_child(_marker)
	_build_ui()
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void:
		if active:
			_refresh_bag())


func start() -> void:
	if active or not Home.is_inside() or not Home.editable or Home.plan == null:
		return
	active = true
	_selected = ""
	controller.player.set_input_lock(&"decor", true)
	if controller.hud != null:
		_hud_was_visible = controller.hud.visible
		controller.hud.visible = false
	_layer.visible = true
	# 평면도 전체가 화면 너비에 들어오게, 아래 단추 판만큼 위로 올려 보여 준다.
	var plan: FloorPlan = Home.plan
	var view: Vector2 = controller.get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)
	_camera.size = maxf(plan.size.x + 1.2, (plan.size.y + 1.2) * aspect * 1.6)
	var visible_depth: float = _camera.size / maxf(aspect, 0.01)
	var center: Vector3 = Home.to_world(plan.size * 0.5)
	_camera.global_position = center + Vector3(0.0, 30.0, visible_depth * 0.14)
	_camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_camera.current = true
	controller.interior.set_labels_visible(true)
	_refresh_bag()
	_update_info()


func stop() -> void:
	if not active:
		return
	active = false
	_pressing = false
	_dragging = false
	_selected = ""
	_marker.visible = false
	_layer.visible = false
	_camera.current = false
	if controller.camera_rig != null and controller.camera_rig.camera != null:
		controller.camera_rig.camera.current = true
	if controller.hud != null:
		controller.hud.visible = _hud_was_visible
	controller.player.set_input_lock(&"decor", false)
	controller.interior.set_labels_visible(false)
	# 끌던 가구가 있으면 서버 목록대로 되돌린다.
	controller.interior.sync_furniture(Home.furniture)


## 서버가 가구 목록을 다시 보냈다.
func on_furniture_changed() -> void:
	if not active:
		return
	if _select_new:
		for f: Home.Furniture in Home.furniture:
			if not _before_ids.has(f.id):
				_selected = f.id
				_select_new = false
	if Home.find(_selected) == null:
		_selected = ""
	_update_marker()
	_update_info()


# ---- 입력 ----

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressing:
		_on_drag((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()


func _on_press(screen: Vector2) -> void:
	var at: Vector2 = _screen_to_plan(screen)
	_pressing = true
	_dragging = false
	_press_screen = screen
	var hit: String = _hit_test(at)
	if hit.is_empty():
		_selected = ""
		_pressing = false
	else:
		_selected = hit
		var f: Home.Furniture = Home.find(hit)
		_drag_offset = f.position - at
		_drag_at = f.position
		_drag_ok = true
	_update_marker()
	_update_info()


func _on_drag(screen: Vector2) -> void:
	var f: Home.Furniture = Home.find(_selected)
	if f == null:
		return
	if not _dragging and screen.distance_to(_press_screen) < 12.0:
		return
	_dragging = true
	var g: float = Home.grid()
	_drag_at = (_screen_to_plan(screen) + _drag_offset).snapped(Vector2(g, g))
	_drag_ok = fits(f.item, _drag_at, f.rot, f.id)
	var node: StaticBody3D = controller.interior.furniture_node(f.id)
	if node != null:
		node.position = Vector3(_drag_at.x, 0.0, _drag_at.y)
		var mesh: MeshInstance3D = node.get_node_or_null("Mesh")
		if mesh != null:
			mesh.transparency = 0.0 if _drag_ok else 0.55
	_update_marker()


func _on_release() -> void:
	if not _pressing:
		return
	_pressing = false
	var f: Home.Furniture = Home.find(_selected)
	if f == null or not _dragging:
		return
	_dragging = false
	var node: StaticBody3D = controller.interior.furniture_node(f.id)
	if node != null:
		var mesh: MeshInstance3D = node.get_node_or_null("Mesh")
		if mesh != null:
			mesh.transparency = 0.0
	if _drag_ok and _drag_at != f.position:
		Home.move(f.id, _drag_at, f.rot)
		Audio.play_sfx("step_wood_1", -4.0)
	else:
		if not _drag_ok:
			controller.toast_hud.show_toast("거기에는 놓을 수 없어요 (벽·다른 방에 걸쳐요)", false)
		controller.interior.sync_furniture(Home.furniture)
	_update_marker()


# ---- 판정 ----

## 그 자리·방향이면 놓을 수 있는지: 네 귀퉁이와 가운데가 바닥 위, 한 방(이어진 거실 쪽은 하나로) 안.
func fits(item: String, at: Vector2, rot: int, _ignore_id: String = "") -> bool:
	var plan: FloorPlan = Home.plan
	if plan == null or not plan.on_floor(at, 0.05):
		return false
	var home_room: FloorPlan.Room = plan.room_at(at)
	for c: Vector2 in HomeInterior.corners(item, at, rot):
		# 벽 두께만큼은 봐준다.
		var inside: Vector2 = at + (c - at) * 0.96
		if not plan.on_floor(inside, 0.0):
			return false
		var r: FloorPlan.Room = plan.room_at(inside)
		if r != home_room and not (_is_open(r) and _is_open(home_room)):
			return false
	return true


func _is_open(room: FloorPlan.Room) -> bool:
	return room != null and bool(GameData.econ.room_kind(room.kind).get("open", false))


## 그 자리에 있는 가구 (여럿이면 가장 작은 것 — 침대 위 선풍기를 먼저).
func _hit_test(at: Vector2) -> String:
	var best: String = ""
	var best_area: float = INF
	for f: Home.Furniture in Home.furniture:
		var half: Vector2 = HomeInterior.footprint(f.item) * 0.5 + Vector2(0.12, 0.12)
		var rel: Vector2 = (at - f.position).rotated(f.rot * PI * 0.25)
		if absf(rel.x) <= half.x and absf(rel.y) <= half.y:
			var area: float = half.x * half.y
			if area < best_area:
				best_area = area
				best = f.id
	return best


func _screen_to_plan(screen: Vector2) -> Vector2:
	var origin: Vector3 = _camera.project_ray_origin(screen)
	var dir: Vector3 = _camera.project_ray_normal(screen)
	var t: float = 0.0 if absf(dir.y) < 0.0001 else -origin.y / dir.y
	return Home.to_local(origin + dir * t)


# ---- 단추 ----

## 좌우로 45° 씩 돌린다. 좁은 방이라 45° 로는 벽에 걸리면 격자 몇 칸 안쪽으로 밀어 보고,
## 그래도 안 되면 바로 다음 90° 로 넘어간다 (긴 침대도 좁은 방에서 돌릴 수 있게).
func _rotate(step: int) -> void:
	var f: Home.Furniture = Home.find(_selected)
	if f == null:
		return
	var g: float = Home.grid()
	for turn: int in [step, step * 2, step * 3, step * 4]:
		var rot: int = posmod(f.rot + turn, 8)
		for dx: float in [0.0, g, -g, 2 * g, -2 * g, 3 * g, -3 * g]:
			for dz: float in [0.0, g, -g, 2 * g, -2 * g, 3 * g, -3 * g]:
				var at: Vector2 = f.position + Vector2(dx, dz)
				if fits(f.item, at, rot, f.id):
					Home.move(f.id, at, rot)
					controller.interior.sync_furniture(Home.furniture)
					_update_marker()
					return
	controller.toast_hud.show_toast("여기서는 돌릴 수 없어요", false)


func _pickup() -> void:
	if _selected.is_empty():
		return
	Home.pickup(_selected)
	_selected = ""
	_update_marker()
	_update_info()


## 가방의 가구를 지금 보이는 집 가운데 쯤 빈 자리에 놓는다.
func _place_from_bag(slot: int, item: String) -> void:
	var plan: FloorPlan = Home.plan
	var g: float = Home.grid()
	var living: FloorPlan.Room = plan.first_room("living")
	var center: Vector2 = (living.main_rect().get_center() if living != null else plan.size * 0.5).snapped(Vector2(g, g))
	for ring: int in 12:
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var at: Vector2 = center + Vector2(dx, dz) * g * 2.0
				if fits(item, at, 0) and _hit_test(at).is_empty():
					_before_ids.clear()
					for f: Home.Furniture in Home.furniture:
						_before_ids[f.id] = true
					_select_new = true
					Home.place(slot, at, 0)
					return
	controller.toast_hud.show_toast("놓을 빈자리가 없어요", false)


# ---- 화면 ----

func _update_marker() -> void:
	var f: Home.Furniture = Home.find(_selected)
	if f == null or not active:
		_marker.visible = false
		return
	var at: Vector2 = _drag_at if _dragging else f.position
	var size: Vector2 = HomeInterior.footprint(f.item) + Vector2(0.16, 0.16)
	_marker.visible = true
	_marker.global_position = Home.to_world(at) + Vector3(0.0, 0.012, 0.0)
	_marker.rotation.y = f.rot * PI * 0.25
	_marker.scale = Vector3(size.x, 1.0, size.y)
	_marker_mat.albedo_color = HIGHLIGHT if (_drag_ok or not _dragging) else BAD


func _update_info() -> void:
	var f: Home.Furniture = Home.find(_selected)
	_info.text = ("%s · 끌어서 옮기기 · 단추로 돌리기" % GameData.item_name(f.item)) if f != null else "가구를 눌러 고르고 끌어서 옮기세요"
	for b: Button in _actions:
		b.disabled = f == null


func _refresh_bag() -> void:
	for c: Node in _bag.get_children():
		c.queue_free()
	var any: bool = false
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it == null:
			continue
		var info: ItemInfo = GameData.item(it.id)
		if info == null or not info.is_furniture():
			continue
		any = true
		var b: Button = _button("%s\n놓기" % GameData.item_name(it.id), 24)
		b.custom_minimum_size = Vector2(170, 100)
		b.pressed.connect(_place_from_bag.bind(i, it.id))
		_bag.add_child(b)
	if not any:
		var empty: Label = _label("가방에 가구가 없어요 (상점에서 TV·소파·식탁 등을 살 수 있어요)", 24, Color(0.4, 0.36, 0.3))
		empty.autowrap_mode = TextServer.AUTOWRAP_OFF
		_bag.add_child(empty)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DecorLayer"
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)
	var top: PanelContainer = PanelContainer.new()
	top.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.97, 0.9, 0.94), Color(0.5, 0.36, 0.24), 26, 4, 14))
	HudLayout.center_top(top, 980.0, 40.0)
	_layer.add_child(top)
	var top_col: VBoxContainer = VBoxContainer.new()
	top.add_child(top_col)
	top_col.add_child(_label("집 꾸미기 · 위에서 본 평면도", 34, Color(0.3, 0.22, 0.16)))
	_info = _label("", 26, Color(0.42, 0.34, 0.26))
	top_col.add_child(_info)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.97, 0.9, 0.96), Color(0.5, 0.36, 0.24), 30, 5, 16))
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 24.0
	panel.offset_right = -24.0
	panel.offset_top = -420.0
	panel.offset_bottom = -30.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	for spec: Array in [["왼쪽으로\n돌리기", -1], ["오른쪽으로\n돌리기", 1]]:
		var b: Button = _button(str(spec[0]), 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_rotate.bind(int(spec[1])))
		row.add_child(b)
		_actions.append(b)
	var put: Button = _button("가방에 넣기", 30)
	put.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	put.pressed.connect(_pickup)
	row.add_child(put)
	_actions.append(put)
	var done: Button = _button("완료", 32)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(stop)
	row.add_child(done)
	col.add_child(_label("가방의 가구", 26, Color(0.42, 0.34, 0.26)))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_bag = HBoxContainer.new()
	_bag.add_theme_constant_override("separation", 10)
	scroll.add_child(_bag)


func _button(text: String, font_size: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 96)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(0.3, 0.22, 0.16))
	b.add_theme_color_override("font_disabled_color", Color(0.3, 0.22, 0.16, 0.35))
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
