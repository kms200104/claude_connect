class_name InventoryWindow
extends Control
## 가방 창 (v0.12). 가방 아이콘을 누르면 캐릭터가 주머니를 뒤적이고, 카메라가 스르륵 다가가 캐릭터를 화면 아래에 두면
## 그 머리 위에 말풍선처럼 가방 창이 뜬다. 월드는 멈추지 않는다.
##   - 가방 6×5 칸 + 퀵슬롯 5칸 + 입은 옷 2칸, 아래는 고른 아이템 설명.
##   - 칸을 눌러 고르고 다른 칸을 누르면 옮긴다. 꾹 눌러 끌어다 놓아도 옮긴다(드래그 앤 드롭).
##   - 창 밖(월드)으로 끌어 놓으면 그 칸 전부를 발밑에 내려놓는다. 창 밖을 톡 누르면 닫힌다.

signal closed

@export var player: Player
## 열면 이 카메라를 가방 구도(캐릭터는 아래, 머리 위는 비움)로 옮긴다.
@export var camera_rig: FollowCamera
@export var bag_columns: int = 6
@export var slot_size: float = 104.0
## 창 아래 꼬리 끝과 머리 꼭대기 사이 (화면 px).
@export var head_gap: float = 26.0
## 화면 위쪽에 남겨 둘 자리 (상단 바).
@export var top_margin: float = 172.0

## 캐릭터 발에서 머리 꼭대기까지 (m). 창 꼬리가 여기를 가리킨다.
const HEAD_TOP: float = 1.75
const TAIL_SIZE: Vector2 = Vector2(56, 34)
const PANEL_COLOR: Color = Color(0.99, 0.95, 0.86, 0.97)
const BORDER_COLOR: Color = Color(0.55, 0.4, 0.28, 1)
const TITLE_COLOR: Color = Color(0.4, 0.27, 0.17, 1)

@onready var _panel: PanelContainer = %Panel
@onready var _tail: Control = %Tail
@onready var _sol: Label = %SolLabel
@onready var _close: Button = %CloseButton
@onready var _grid: GridContainer = %BagGrid
@onready var _quick_row: HBoxContainer = %QuickRow
@onready var _name: Label = %ItemName
@onready var _desc: Label = %ItemDesc
@onready var _meta: Label = %ItemMeta
@onready var _discard: Button = %DiscardButton
## 가구는 "설치하기", 옷은 "입기".
@onready var _use: Button = %UseButton
@onready var _outfit_row: HBoxContainer = %OutfitRow
@onready var _hint: Label = %HintLabel

var selected_slot: int = -1
var _open: bool = false
var _slots: Array[ItemSlot] = []
## 입은 옷 칸 (hat, top). 누르면 벗는다.
var _outfit_slots: Dictionary[String, ItemSlot] = {}
var _pop: Tween = null
## 꼬리 끝 (창 기준 x). 머리 바로 위를 가리킨다.
var _tail_tip: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close.pressed.connect(close)
	_discard.pressed.connect(_on_discard_pressed)
	_use.pressed.connect(_on_use_pressed)
	_tail.draw.connect(_draw_tail)
	Net.profile_updated.connect(_refresh_outfit)
	_grid.columns = bag_columns
	add_to_group(&"blocks_joystick")
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _refresh())
	Net.profile_updated.connect(_refresh_sol)
	Net.state_changed.connect(_on_net_state_changed)
	set_process(false)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	Audio.play_ui(Audio.SFX_OPEN)
	visible = true
	if player != null:
		player.set_input_lock(&"inventory", true)
		player.rig.set_rummaging(true)
		# 카메라 쪽으로 몸을 돌려 주머니를 뒤진다 (얼굴이 보이게).
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			player.look_toward(cam.global_position - player.global_position)
	if camera_rig != null:
		camera_rig.set_bag_view(true)
	selected_slot = -1
	_refresh()
	_refresh_outfit()
	_refresh_sol()
	set_process(true)
	# 주머니를 뒤적이기 시작한 뒤에 머리 위로 톡 튀어나온다.
	_panel.modulate.a = 0.0
	_panel.scale = Vector2.ONE * 0.4
	_tail.modulate.a = 0.0
	_kill_pop()
	_pop = create_tween().set_parallel(true)
	_pop.tween_property(_panel, "scale", Vector2.ONE, 0.32).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(_panel, "modulate:a", 1.0, 0.16).set_delay(0.3)
	_pop.tween_property(_tail, "modulate:a", 1.0, 0.16).set_delay(0.4)


func close() -> void:
	if not _open:
		return
	_open = false
	Audio.play_ui(Audio.SFX_CLOSE)
	selected_slot = -1
	if player != null:
		player.set_input_lock(&"inventory", false)
		player.rig.set_rummaging(false)
		player.clear_look_direction()
	if camera_rig != null:
		camera_rig.set_bag_view(false)
	_kill_pop()
	_pop = create_tween().set_parallel(true)
	_pop.tween_property(_panel, "scale", Vector2.ONE * 0.6, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_pop.tween_property(_panel, "modulate:a", 0.0, 0.14)
	_pop.tween_property(_tail, "modulate:a", 0.0, 0.1)
	_pop.chain().tween_callback(func() -> void:
		if not _open:
			visible = false
			set_process(false))
	closed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## 칸 누르기 (테스트·키보드에서도 같은 길로 들어온다).
func press_slot(index: int) -> void:
	Audio.play_ui(Audio.SFX_CLICK)
	var item: InventoryItem = _item_at(index)
	if selected_slot == -1:
		if item != null:
			_select(index)
		return
	if index == selected_slot:
		_select(-1)
		return
	# 고른 아이템을 이 칸으로 옮긴다 (같은 아이템이면 합치고, 다르면 맞바꾼다).
	move_slot(selected_slot, index)


## from 칸을 to 칸으로 (끌어다 놓기 · 두 번 누르기). 서버가 확정한다.
func move_slot(from: int, to: int) -> void:
	if from == to or _item_at(from) == null:
		return
	Net.move_item(from, to)
	_select(-1)


## 칸 하나를 통째로 발밑에 내려놓는다 (창 밖으로 끌어 놓기). 도구는 못 버린다.
func drop_slot(index: int) -> bool:
	var item: InventoryItem = _item_at(index)
	var info: ItemInfo = GameData.item(item.id) if item != null else null
	if info == null or info.is_tool():
		return false
	Net.discard_item(index, item.count)
	_select(-1)
	return true


func slot_control(index: int) -> ItemSlot:
	return _slots[index] if index >= 0 and index < _slots.size() else null


## 창(말풍선) 영역 (화면 좌표). 테스트·캡처용.
func panel_rect() -> Rect2:
	return _panel.get_global_rect()


func _process(_delta: float) -> void:
	_follow_head()


## 말풍선을 캐릭터 머리 위에 붙인다. 화면 밖으로 나가지 않게 가둔다.
func _follow_head() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var area: Vector2 = size
	var panel_size: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = panel_size
	_panel.pivot_offset = Vector2(panel_size.x * 0.5, panel_size.y)
	var head: Vector2 = Vector2(area.x * 0.5, area.y * 0.62)
	if cam != null and player != null and not cam.is_position_behind(player.global_position + Vector3.UP * HEAD_TOP):
		head = cam.unproject_position(player.global_position + Vector3.UP * HEAD_TOP)
	var bottom: float = head.y - head_gap - TAIL_SIZE.y
	var top: float = clampf(bottom - panel_size.y, top_margin, maxf(area.y - panel_size.y - 20.0, top_margin))
	var left: float = clampf(head.x - panel_size.x * 0.5, 16.0, maxf(area.x - panel_size.x - 16.0, 16.0))
	_panel.position = Vector2(left, top)
	# 꼬리는 창 아래 가운데 근처에서 머리 쪽을 가리킨다.
	var base_y: float = top + panel_size.y - 8.0
	var base_x: float = clampf(head.x, left + 60.0, left + panel_size.x - 60.0)
	_tail.position = Vector2(base_x, base_y)
	_tail_tip = Vector2(clampf(head.x - base_x, -TAIL_SIZE.x, TAIL_SIZE.x), maxf(TAIL_SIZE.y, minf(head.y - head_gap - base_y, TAIL_SIZE.y * 1.6)))
	_tail.scale = _panel.scale
	_tail.queue_redraw()


func _draw_tail() -> void:
	var half: float = TAIL_SIZE.x * 0.5
	var pts: PackedVector2Array = PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), _tail_tip])
	_tail.draw_colored_polygon(pts, PANEL_COLOR)
	_tail.draw_line(Vector2(-half, 0) + Vector2(0, 6), _tail_tip, BORDER_COLOR, 7.0, true)
	_tail.draw_line(Vector2(half, 0) + Vector2(0, 6), _tail_tip, BORDER_COLOR, 7.0, true)
	_tail.draw_circle(_tail_tip, 3.5, BORDER_COLOR)


## 창 밖을 톡 누르면 닫는다.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			accept_event()
			close()


## 칸을 창 밖(월드)으로 끌어 놓으면 발밑에 내려놓는다.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and (data as Dictionary).has("slot_drag")):
		return false
	var item: InventoryItem = _item_at(int(data["slot_drag"]))
	var info: ItemInfo = GameData.item(item.id) if item != null else null
	return info != null and not info.is_tool()


func _drop_data(_at: Vector2, data: Variant) -> void:
	if drop_slot(int(data["slot_drag"])):
		Audio.play_ui(Audio.SFX_CONFIRM)


func _select(index: int) -> void:
	selected_slot = index
	for s: ItemSlot in _slots:
		s.selected = s.slot_index == index
	_refresh_detail()


func _refresh() -> void:
	_build_slots()
	for s: ItemSlot in _slots:
		s.set_item(_item_at(s.slot_index))
		s.held = s.slot_index == Net.held_slot
		s.selected = s.slot_index == selected_slot
	if selected_slot >= 0 and _item_at(selected_slot) == null:
		selected_slot = -1
	_refresh_detail()


func _build_slots() -> void:
	var total: int = Net.quick_slot_count + Net.inventory_capacity
	if _slots.size() == total:
		return
	for s: ItemSlot in _slots:
		s.queue_free()
	_slots.clear()
	for i: int in total:
		var slot: ItemSlot = ItemSlot.new()
		slot.slot_index = i
		slot.draggable = true
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.pressed.connect(press_slot.bind(i))
		slot.item_dropped.connect(move_slot.bind(i))
		if i < Net.quick_slot_count:
			slot.hotkey = i + 1
			_quick_row.add_child(slot)
		else:
			_grid.add_child(slot)
		_slots.append(slot)


func _refresh_detail() -> void:
	var item: InventoryItem = _item_at(selected_slot)
	var info: ItemInfo = GameData.item(item.id) if item != null else null
	_discard.visible = info != null and not info.is_tool()
	_use.visible = info != null and (info.is_furniture() or info.is_clothing())
	if info == null:
		_name.text = "아이템을 골라 보세요"
		_name.add_theme_color_override("font_color", TITLE_COLOR)
		_desc.text = "칸을 꾹 눌러 끌면 자리를 옮길 수 있어요."
		_meta.text = ""
		_hint.text = "창 밖으로 끌어 놓으면 발밑에 내려놓아요"
		return
	_name.text = info.display_name
	_name.add_theme_color_override("font_color", info.color.darkened(0.25))
	_desc.text = info.description
	var price: String = " · 상점에서 %s" % Money.sol(info.price) if info.price > 0 else ""
	_meta.text = "%s · %d개%s%s" % [info.kind_label(), item.count, " · 손에 듦" if selected_slot == Net.held_slot else "", price]
	_use.text = "설치하기" if info.is_furniture() else "입기"
	_hint.text = "옮길 칸을 누르거나 끌어다 놓아요"


func _refresh_sol() -> void:
	_sol.text = Money.short(Net.sol)


## 가구: 캐릭터 앞 1.5m 에 캐릭터를 바라보게 놓는다. 옷: 입는다 (입던 옷은 이 칸으로).
func _on_use_pressed() -> void:
	var item: InventoryItem = _item_at(selected_slot)
	var info: ItemInfo = GameData.item(item.id) if item != null else null
	if info == null:
		return
	if info.is_clothing():
		Net.wear(selected_slot)
		_select(-1)
		return
	if info.is_furniture() and player != null:
		var yaw: float = player.body.rotation.y if player.body != null else 0.0
		var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var rot: int = posmod(roundi(yaw / (PI * 0.5)), 4)
		if Home.is_inside():
			# 집 안 (v0.10): 집 가구로 놓는다 (45° 단위, 보이지 않는 격자에 맞춘다). 내 집이 아니면 서버가 거절한다.
			var at: Vector2 = Home.to_local(player.global_position + forward * 1.2)
			Home.place(selected_slot, at.snapped(Vector2.ONE * Home.grid()), rot * 2)
		else:
			Net.place_furniture(selected_slot, player.global_position + forward * 1.5, rot)
		close()


func _refresh_outfit() -> void:
	if _outfit_slots.is_empty():
		for part: String in ["hat", "top"]:
			var slot: ItemSlot = ItemSlot.new()
			slot.custom_minimum_size = Vector2(slot_size, slot_size)
			slot.pressed.connect(func() -> void: Net.unwear(part))
			_outfit_row.add_child(slot)
			_outfit_slots[part] = slot
	_outfit_slots["hat"].set_item(InventoryItem.new(Net.outfit_hat, 1) if not Net.outfit_hat.is_empty() else null)
	_outfit_slots["top"].set_item(InventoryItem.new(Net.outfit_top, 1) if not Net.outfit_top.is_empty() else null)


## 버튼: 하나씩 발밑에 내려놓는다.
func _on_discard_pressed() -> void:
	if selected_slot >= 0:
		Net.discard_item(selected_slot, 1)


func _on_net_state_changed(new_state: int) -> void:
	if new_state == Net.State.DISCONNECTED:
		close()


func _item_at(index: int) -> InventoryItem:
	return Net.inventory[index] if index >= 0 and index < Net.inventory.size() else null


func _kill_pop() -> void:
	if _pop != null and _pop.is_valid():
		_pop.kill()


static func _format_number(n: int) -> String:
	return Money.digits(n)
