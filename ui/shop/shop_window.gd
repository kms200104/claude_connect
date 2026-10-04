class_name ShopWindow
extends Control
## 상점 창 (상점 주인과 이야기해서 연다). "사기"는 지금 단계까지 열린 진열품, "팔기"는 내 가방의 팔 수 있는 물건.
## 값·재고 판정은 서버가 하고, 여기서는 목록을 보여 주고 요청만 보낸다. 사고팔면 상점 포인트 막대가 차오른다.

signal closed

const MODE_BUY: String = "buy"
const MODE_SELL: String = "sell"

@export var player: Player

@onready var _title: Label = %TitleLabel
@onready var _sol: Label = %SolLabel
@onready var _close: Button = %CloseButton
@onready var _points_bar: ProgressBar = %PointsBar
@onready var _points_label: Label = %PointsLabel
@onready var _buy_tab: Button = %BuyTab
@onready var _sell_tab: Button = %SellTab
@onready var _list: VBoxContainer = %List
@onready var _message: Label = %MessageLabel

var mode: String = MODE_BUY


func _ready() -> void:
	visible = false
	add_to_group(&"blocks_joystick")
	_close.pressed.connect(close)
	_buy_tab.pressed.connect(func() -> void: set_mode(MODE_BUY))
	_sell_tab.pressed.connect(func() -> void: set_mode(MODE_SELL))
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _refresh())
	Net.profile_updated.connect(_refresh)
	Net.shop_updated.connect(_on_shop_updated)
	Net.shop_traded.connect(_on_traded)
	Net.request_failed.connect(_on_request_failed)
	Net.state_changed.connect(_on_net_state_changed)


func is_open() -> bool:
	return visible


func open(start_mode: String = MODE_BUY) -> void:
	visible = true
	_message.text = ""
	if player != null:
		player.set_input_lock(&"shop", true)
	set_mode(start_mode)


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.set_input_lock(&"shop", false)
	closed.emit()


func set_mode(new_mode: String) -> void:
	mode = new_mode
	_buy_tab.disabled = mode == MODE_BUY
	_sell_tab.disabled = mode == MODE_SELL
	_refresh()


## 목록의 줄 (테스트용).
func row_count() -> int:
	return _list.get_child_count()


func _refresh() -> void:
	if not visible:
		return
	var shop: ShopData = GameData.shop
	var lv: ShopData.Level = shop.level_info(Net.shop_level)
	_title.text = "%s  Lv.%d" % [lv.display_name, lv.level]
	_sol.text = "%s솔" % InventoryWindow._format_number(Net.sol)
	_refresh_points()
	for child: Node in _list.get_children():
		child.queue_free()
	if mode == MODE_BUY:
		for item_id: String in shop.stock_for(Net.shop_level):
			_list.add_child(_buy_row(GameData.item(item_id)))
	else:
		var any: bool = false
		for i: int in Net.inventory.size():
			var item: InventoryItem = Net.inventory[i]
			var info: ItemInfo = GameData.item(item.id) if item != null else null
			if info == null or info.price <= 0:
				continue
			_list.add_child(_sell_row(i, item, info))
			any = true
		if not any:
			_list.add_child(_note("팔 수 있는 물건이 없어요. 나무를 베거나 물고기를 낚아 오세요!"))


func _refresh_points() -> void:
	var shop: ShopData = GameData.shop
	if Net.shop_next < 0:
		_points_bar.value = 100.0
		_points_label.text = "최고 단계! 상점 포인트 %s" % InventoryWindow._format_number(Net.shop_points)
		return
	var start: int = shop.level_info(Net.shop_level).points
	_points_bar.value = clampf(float(Net.shop_points - start) / maxf(Net.shop_next - start, 1) * 100.0, 0.0, 100.0)
	_points_label.text = "다음 단계까지 %s포인트" % InventoryWindow._format_number(Net.shop_next - Net.shop_points)


func _buy_row(info: ItemInfo) -> Control:
	var row: HBoxContainer = _row_base(info, "%s · %s솔" % [info.kind_label(), InventoryWindow._format_number(info.buy_price)])
	var button: Button = _action_button("사기")
	button.disabled = Net.sol < info.buy_price
	button.pressed.connect(func() -> void: Net.buy_item(info.id, 1))
	row.add_child(button)
	return row


func _sell_row(slot: int, item: InventoryItem, info: ItemInfo) -> Control:
	var each: int = GameData.shop.sell_value(info.price, 1, Net.shop_level)
	var row: HBoxContainer = _row_base(info, "%d개 · 하나에 %s솔" % [item.count, InventoryWindow._format_number(each)])
	var one: Button = _action_button("1개")
	one.pressed.connect(func() -> void: Net.sell_item(slot, 1))
	row.add_child(one)
	if item.count > 1:
		var all: Button = _action_button("모두")
		all.pressed.connect(func() -> void: Net.sell_item(slot, item.count))
		row.add_child(all)
	return row


func _row_base(info: ItemInfo, detail: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var chip: ItemSlot = ItemSlot.new()
	chip.custom_minimum_size = Vector2(96, 96)
	chip.disabled = true
	chip.set_item(InventoryItem.new(info.id, 1))
	row.add_child(chip)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = Label.new()
	name_label.text = info.display_name
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", Color(0.35, 0.24, 0.15))
	text.add_child(name_label)
	var detail_label: Label = Label.new()
	detail_label.text = detail
	detail_label.add_theme_font_size_override("font_size", 28)
	detail_label.add_theme_color_override("font_color", Color(0.55, 0.45, 0.35))
	text.add_child(detail_label)
	row.add_child(text)
	return row


func _action_button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 84)
	b.add_theme_font_size_override("font_size", 32)
	return b


func _note(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.5, 0.42, 0.34))
	return label


func _on_shop_updated(leveled_up: bool) -> void:
	_refresh()
	if leveled_up and visible:
		_message.text = "상점이 커졌어요! 새 물건이 들어왔어요"


func _on_traded(kind: String, item_id: String, count: int, amount: int) -> void:
	var name_text: String = GameData.item_name(item_id)
	if kind == "sell":
		_message.text = "%s %d개를 %s솔에 팔았어요" % [name_text, count, InventoryWindow._format_number(amount)]
	else:
		_message.text = "%s을(를) %s솔에 샀어요" % [name_text, InventoryWindow._format_number(amount)]
	_refresh()


func _on_net_state_changed(new_state: int) -> void:
	if new_state == Net.State.DISCONNECTED:
		close()


func _on_request_failed(kind: String, code: String) -> void:
	if not visible or not kind.begins_with("shop_"):
		return
	match code:
		NetProtocol.ERR_NOT_ENOUGH_SOL:
			_message.text = "솔이 모자라요"
		NetProtocol.ERR_INVENTORY_FULL:
			_message.text = "가방이 가득 찼어요"
		NetProtocol.ERR_CANT_SELL:
			_message.text = "그건 팔 수 없어요"
		NetProtocol.ERR_NOT_FOR_SALE:
			_message.text = "지금은 팔지 않는 물건이에요"
		_:
			_message.text = "거래하지 못했어요"
