class_name Hotbar
extends Control
## 화면 아래 가운데: 퀵슬롯 5칸 + 가방 아이콘. 퀵슬롯을 누르면 그 아이템을 손에 들고(한 번 더 누르면 빈손),
## 가방을 누르면 인벤토리 창을 연다.

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
	_refresh()


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
	for i: int in _slots.size():
		_slots[i].set_item(Net.inventory[i] if i < Net.inventory.size() else null)
		_slots[i].held = i == Net.held_slot


func _on_slot_pressed(index: int) -> void:
	Audio.play_ui(Audio.SFX_CLICK)
	Net.equip(-1 if Net.held_slot == index else index)
