class_name ShopWindow
extends Control
## 상점 창 (상점 주인과 이야기해서 연다). "사기"는 지금 단계까지 열린 진열품, "팔기"는 내 가방의 팔 수 있는 물건.
## 값·재고 판정은 서버가 하고, 여기서는 목록을 보여 주고 요청만 보낸다. 사고팔면 상점 포인트 막대가 차오른다.
## 떠돌이 상인 모드(at = AT_MERCHANT): 상인의 보따리 물건을 사고, 상인이 찾는 물건만 2배 값에 판다 (포인트는 쌓이지 않음).
## 특가 매입의 날에는 고른 물건 줄에 "×2 특가" 표시와 두 배 값을 보여 준다.
## 공항 모드(at = AT_AIRPORT): 조종사의 여행 기념품(씨앗·소품)만 산다 (팔기 없음, 포인트 없음).

signal closed

const MODE_BUY: String = "buy"
const MODE_SELL: String = "sell"
const AT_MERCHANT: String = "merchant"
const AT_AIRPORT: String = "airport"

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
## 거래 상대: "" = 상점, AT_MERCHANT = 떠돌이 상인.
var at: String = ""


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


func open(start_mode: String = MODE_BUY, partner: String = "") -> void:
	Audio.play_ui(Audio.SFX_OPEN)
	at = partner
	visible = true
	_message.text = ""
	if player != null:
		player.set_input_lock(&"shop", true)
	set_mode(start_mode)


func close() -> void:
	if not visible:
		return
	Audio.play_ui(Audio.SFX_CLOSE)
	visible = false
	if player != null:
		player.set_input_lock(&"shop", false)
	closed.emit()


func set_mode(new_mode: String) -> void:
	mode = MODE_BUY if at == AT_AIRPORT else new_mode
	_buy_tab.disabled = mode == MODE_BUY
	_sell_tab.disabled = mode == MODE_SELL
	_sell_tab.visible = at != AT_AIRPORT
	_refresh()


## 목록의 줄 (테스트용).
func row_count() -> int:
	var n: int = 0
	for child: Node in _list.get_children():
		if not child.is_queued_for_deletion():
			n += 1
	return n


func _refresh() -> void:
	if not visible:
		return
	var shop: ShopData = GameData.shop
	var merchant: ActiveEvent = Net.event_active(EventInfo.MERCHANT) if at == AT_MERCHANT else null
	if at == AT_MERCHANT:
		_title.text = "떠돌이 상인 누리의 보따리"
	elif at == AT_AIRPORT:
		_title.text = "%s 기념품 가게" % GameData.airport.display_name
	else:
		var lv: ShopData.Level = shop.level_info(Net.shop_level)
		_title.text = "%s  Lv.%d" % [lv.display_name, lv.level]
	_sol.text = "%s솔" % InventoryWindow._format_number(Net.sol)
	_points_bar.visible = at == ""
	_points_label.visible = at == ""
	_refresh_points()
	for child: Node in _list.get_children():
		child.queue_free()
	if mode == MODE_BUY:
		var stock: PackedStringArray = merchant.stock if merchant != null else (GameData.airport.stock if at == AT_AIRPORT else shop.stock_for(Net.shop_level))
		for item_id: String in stock:
			_list.add_child(_buy_row(GameData.item(item_id)))
	else:
		var any: bool = false
		for i: int in Net.inventory.size():
			var item: InventoryItem = Net.inventory[i]
			var info: ItemInfo = GameData.item(item.id) if item != null else null
			if info == null or info.price <= 0 or Net.sell_multiplier(info.id, at) <= 0.0:
				continue
			_list.add_child(_sell_row(i, item, info))
			any = true
		if not any:
			if merchant != null:
				_list.add_child(_note("누리가 찾는 물건은 %s 이에요. 구해 오면 2배 값에 사 줄 거예요!" % DialogueController.wanted_names(merchant)))
			else:
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
	button.pressed.connect(func() -> void: Net.buy_item(info.id, 1, at))
	row.add_child(button)
	return row


func _sell_row(slot: int, item: InventoryItem, info: ItemInfo) -> Control:
	var mult: float = Net.sell_multiplier(info.id, at)
	var each: int = int(floor(info.price * mult)) if at == AT_MERCHANT else int(floor(GameData.shop.sell_value(info.price, 1, Net.shop_level) * mult))
	var detail: String = "%d개 · 하나에 %s솔" % [item.count, InventoryWindow._format_number(each)]
	if mult > 1.0:
		detail = "×%s 특가! %s" % [EventHud._format_mult(mult), detail]
	var row: HBoxContainer = _row_base(info, detail)
	if mult > 1.0:
		(row.get_child(1).get_child(1) as Label).add_theme_color_override("font_color", Color(0.86, 0.36, 0.3))
	var one: Button = _action_button("1개")
	one.pressed.connect(func() -> void: Net.sell_item(slot, 1, at))
	row.add_child(one)
	if item.count > 1:
		var all: Button = _action_button("모두")
		all.pressed.connect(func() -> void: Net.sell_item(slot, item.count, at))
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
		NetProtocol.ERR_NOT_NEAR_KEEPER:
			_message.text = "조종사 곁에서만 살 수 있어요"
		NetProtocol.ERR_MERCHANT_AWAY:
			_message.text = "누리에게 더 가까이 가야 해요"
		NetProtocol.ERR_NOT_WANTED:
			_message.text = "누리가 찾는 물건이 아니에요"
		_:
			_message.text = "거래하지 못했어요"
