class_name Hotbar
extends Control
## 화면 아래 가운데: 퀵슬롯 5칸 + 가방 아이콘. 퀵슬롯을 누르면 그 아이템을 손에 들고(한 번 더 누르면 빈손),
## 가방을 누르면 인벤토리 창을 연다.
## v0.16: 탈것(킥보드) 칸은 손에 드는 대신 누르면 꺼내 타고, 타는 중에 다시 누르면 접어 넣는다 (타는 동안 그 칸이 빛난다).

signal bag_pressed

@export var slot_size: float = 124.0

@onready var _row: HBoxContainer = %Row
@onready var _bag: BagButton = %BagButton

var _slots: Array[ItemSlot] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.pressed.connect(func() -> void: bag_pressed.emit())
	_bag.add_to_group(&"blocks_joystick")
	_row.add_to_group(&"blocks_joystick")
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _refresh())
	Net.state_changed.connect(func(_s: int) -> void: _refresh())
	_refresh.call_deferred()
	(func() -> void:
		var rider: KickboardRider = _rider()
		if rider != null:
			rider.changed.connect(func(_on: bool) -> void: _refresh())).call_deferred()


func slot_button(index: int) -> ItemSlot:
	return _slots[index] if index >= 0 and index < _slots.size() else null


func bag_button() -> BagButton:
	return _bag


func _refresh() -> void:
	visible = Net.state == Net.State.ONLINE or Net.state == Net.State.RECONNECTING
	while _slots.size() < Net.quick_slot_count:
		var slot: ItemSlot = ItemSlot.new()
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.slot_index = _slots.size()
		slot.hotkey = _slots.size() + 1
		slot.pressed.connect(_on_slot_pressed.bind(slot.slot_index))
		_row.add_child(slot)
		_row.move_child(_bag, -1)
		_slots.append(slot)
	var rider: KickboardRider = _rider()
	var riding: String = rider.item_id if rider != null and rider.is_active() else ""
	for i: int in _slots.size():
		var item: InventoryItem = Net.inventory[i] if i < Net.inventory.size() else null
		_slots[i].set_item(item)
		_slots[i].held = i == Net.held_slot or (item != null and not riding.is_empty() and item.id == riding)


func _on_slot_pressed(index: int) -> void:
	Audio.play_ui(Audio.SFX_CLICK)
	var item: InventoryItem = Net.inventory[index] if index < Net.inventory.size() else null
	var info: ItemInfo = GameData.item(item.id) if item != null else null
	var rider: KickboardRider = _rider()
	if info != null and not info.ride.is_empty() and rider != null:
		if rider.is_riding():
			rider.dismount()
		elif rider.state == KickboardRider.State.OFF:
			rider.mount(item.id)
		return
	Net.equip(-1 if Net.held_slot == index else index)


func _rider() -> KickboardRider:
	return get_tree().get_first_node_in_group(&"kickboard_rider") as KickboardRider if is_inside_tree() else null
