class_name InventoryPanel
extends Control
## 가방 버튼과 목록 창. 내용은 서버가 보낸 인벤토리를 그대로 보여 주고, 놓아주기도 서버에 요청만 한다.

@export var player: Player

@onready var _bag_button: Button = %BagButton
@onready var _window: PanelContainer = %Window
@onready var _title: Label = %TitleLabel
@onready var _list: VBoxContainer = %List
@onready var _empty: Label = %EmptyLabel
@onready var _close: Button = %CloseButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_button.pressed.connect(func() -> void: _set_open(not _window.visible))
	_close.pressed.connect(func() -> void: _set_open(false))
	Net.inventory_updated.connect(func(_items: Array[InventoryItem], _cap: int) -> void: _refresh())
	Net.state_changed.connect(func(_s: int) -> void: _on_net_state_changed())
	_window.visible = false
	_on_net_state_changed()
	_refresh()


func _on_net_state_changed() -> void:
	var online: bool = Net.state == Net.State.ONLINE
	_bag_button.visible = online
	if not online:
		_set_open(false)


func _set_open(open: bool) -> void:
	_window.visible = open
	if player != null:
		# 창이 열려 있는 동안에는 뒤쪽 조이스틱 입력으로 캐릭터가 움직이지 않게 한다.
		player.set_input_lock(&"inventory", open)
	if open:
		_refresh()


func _refresh() -> void:
	var items: Array[InventoryItem] = Net.inventory
	var cap: int = Net.inventory_capacity
	_bag_button.text = "가방 %d/%d" % [items.size(), cap]
	_title.text = "가방 (%d/%d칸)" % [items.size(), cap]
	_empty.visible = items.is_empty()
	for child: Node in _list.get_children():
		child.queue_free()
	for item: InventoryItem in items:
		_list.add_child(_build_row(item))


func _build_row(item: InventoryItem) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label: Label = Label.new()
	var info: FishInfo = GameData.fish.get(item.id)
	label.text = "%s × %d" % [GameData.fish_name(item.id), item.count]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 38)
	if info != null:
		label.add_theme_color_override("font_color", _rarity_color(info.rarity))
	row.add_child(label)

	var release: Button = Button.new()
	release.text = "놓아주기"
	release.custom_minimum_size = Vector2(200, 72)
	release.add_theme_font_size_override("font_size", 30)
	release.pressed.connect(func() -> void: Net.discard_item(item.id, 1))
	row.add_child(release)
	return row


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":
			return Color(1.0, 0.82, 0.35)
		"uncommon":
			return Color(0.6, 0.95, 0.65)
		_:
			return Color.WHITE
