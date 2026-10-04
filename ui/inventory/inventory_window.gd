class_name InventoryWindow
extends Control
## 가방 창. 왼쪽은 가방 칸(4×5)과 퀵슬롯 5칸, 오른쪽은 내 캐릭터 미리보기, 아래는 고른 아이템 설명.
## 칸을 누르면 고르고 → 캐릭터가 그 칸을 바라본다. 고른 상태에서 다른 칸을 누르면 자리를 옮긴다(서버 요청).
## 창이 열려 있는 동안 메인 월드는 마지막 화면을 멈춰 두고(3D 렌더 끔) 미리보기만 그린다.

signal closed

@export var player: Player
## 열려 있는 동안 월드 3D 렌더링을 멈출지 (배터리·발열 절약).
@export var freeze_world: bool = true
@export var bag_columns: int = 4

@onready var _backdrop: TextureRect = %Backdrop
@onready var _sol: Label = %SolLabel
@onready var _close: Button = %CloseButton
@onready var _grid: GridContainer = %BagGrid
@onready var _quick_row: HBoxContainer = %QuickRow
@onready var _preview: CharacterPreview = %CharacterPreview
@onready var _name: Label = %ItemName
@onready var _desc: Label = %ItemDesc
@onready var _meta: Label = %ItemMeta
@onready var _discard: Button = %DiscardButton
@onready var _hint: Label = %HintLabel

var selected_slot: int = -1
var _slots: Array[ItemSlot] = []


func _ready() -> void:
	visible = false
	_close.pressed.connect(close)
	_discard.pressed.connect(_on_discard_pressed)
	_grid.columns = bag_columns
	add_to_group(&"blocks_joystick")
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _refresh())
	Net.profile_updated.connect(_refresh_sol)
	Net.state_changed.connect(_on_net_state_changed)
	if player != null:
		_preview.follow = player


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	if freeze_world:
		_freeze(true)
	visible = true
	if player != null:
		player.set_input_lock(&"inventory", true)
	selected_slot = -1
	_preview.set_open(true)
	_refresh()
	_refresh_sol()


func close() -> void:
	if not visible:
		return
	visible = false
	selected_slot = -1
	_preview.set_open(false)
	if player != null:
		player.set_input_lock(&"inventory", false)
	_freeze(false)
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## 칸 누르기 (테스트·키보드에서도 같은 길로 들어온다).
func press_slot(index: int) -> void:
	var item: InventoryItem = _item_at(index)
	if selected_slot == -1:
		if item != null:
			_select(index)
		return
	if index == selected_slot:
		_select(-1)
		return
	# 고른 아이템을 이 칸으로 옮긴다 (같은 아이템이면 합치고, 다르면 맞바꾼다). 캐릭터는 옮긴 칸을 바라본다.
	Net.move_item(selected_slot, index)
	_preview.look_at_control(slot_control(index))
	_select(-1, false)


func slot_control(index: int) -> ItemSlot:
	return _slots[index] if index >= 0 and index < _slots.size() else null


func preview() -> CharacterPreview:
	return _preview


func _select(index: int, clear_look: bool = true) -> void:
	selected_slot = index
	for s: ItemSlot in _slots:
		s.selected = s.slot_index == index
	if index >= 0:
		var item: InventoryItem = _item_at(index)
		_preview.look_at_control(_slots[index], GameData.item(item.id) if item != null else null)
	elif clear_look:
		_preview.clear_look()
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
		slot.pressed.connect(press_slot.bind(i))
		if i < Net.quick_slot_count:
			slot.hotkey = i + 1
			slot.custom_minimum_size = Vector2(100, 100)
			_quick_row.add_child(slot)
		else:
			_grid.add_child(slot)
		_slots.append(slot)


func _refresh_detail() -> void:
	var item: InventoryItem = _item_at(selected_slot)
	var info: ItemInfo = GameData.item(item.id) if item != null else null
	_discard.visible = info != null and not info.is_tool()
	if info == null:
		_name.text = "아이템을 골라 보세요"
		_desc.text = "칸을 누르면 캐릭터가 그 아이템을 바라봐요."
		_meta.text = ""
		_hint.text = ""
		return
	_name.text = info.display_name
	_name.add_theme_color_override("font_color", info.color.darkened(0.25))
	_desc.text = info.description
	var kind: String = {"tool": "도구", "material": "재료", "fish": "물고기"}.get(info.kind, info.kind)
	_meta.text = "%s · %d개%s" % [kind, item.count, " · 손에 듦" if selected_slot == Net.held_slot else ""]
	_discard.text = "놓아주기" if info.is_fish() else "버리기"
	_hint.text = "옮길 칸을 누르면 자리를 바꿔요"


func _refresh_sol() -> void:
	_sol.text = "%s솔" % _format_number(Net.sol)


func _on_discard_pressed() -> void:
	if selected_slot >= 0:
		Net.discard_item(selected_slot, 1)


func _on_net_state_changed(new_state: int) -> void:
	if new_state == Net.State.DISCONNECTED:
		close()


func _item_at(index: int) -> InventoryItem:
	return Net.inventory[index] if index >= 0 and index < Net.inventory.size() else null


## 창을 여는 동안 월드를 멈춘다: 마지막 화면을 배경으로 깔고 3D 렌더링을 끈다.
func _freeze(on: bool) -> void:
	var vp: Viewport = get_viewport()
	if on:
		# 헤드리스(테스트)에는 그려진 화면이 없다.
		var headless: bool = DisplayServer.get_name() == "headless"
		var image: Image = vp.get_texture().get_image() if not headless and vp.get_texture() != null else null
		_backdrop.texture = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
		vp.disable_3d = true
	else:
		vp.disable_3d = false
		_backdrop.texture = null


static func _format_number(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	for i: int in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out
