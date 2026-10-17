class_name Hotbar
extends Control
## 화면 아래 가운데: 퀵슬롯 5칸 + 가방 아이콘. 퀵슬롯을 누르면 그 아이템을 손에 들고(한 번 더 누르면 빈손),
## 가방을 누르면 인벤토리 창을 연다.
## v0.16: 탈것(킥보드) 칸은 손에 드는 대신 누르면 꺼내 타고, 타는 중에 다시 누르면 접어 넣는다 (타는 동안 그 칸이 빛난다).
## v0.28.7: 치료 · 생존 식량 (통조림 · 건빵 · 물) 칸은 손에 드는 대신 누르면 바로 쓴다 (Net.use_item, 서버가 확정). 화살 칸은 남은 수만 알려 준다.
## 그런 칸에는 오른쪽 위에 "치료" · "먹기" · "화살" 띠가 붙는다. 가방 창에서 아이템을 1~5번 칸으로 끌어다 놓으면 된다.

signal bag_pressed

@export var slot_size: float = 124.0

@onready var _row: HBoxContainer = %Row
@onready var _bag: BagButton = %BagButton

var _slots: Array[ItemSlot] = []
## 바로 쓰기 안내 (SurvivalController 가 넣는다).
var toast_hud: FishingHud = null
var _use_wait_until: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.pressed.connect(func() -> void: bag_pressed.emit())
	_bag.add_to_group(&"blocks_joystick")
	_row.add_to_group(&"blocks_joystick")
	Net.inventory_updated.connect(func(_s: Array[InventoryItem], _h: int) -> void: _refresh())
	Net.hp_changed.connect(func(_hp: int, _max: int) -> void: _use_wait_until = 0)
	Net.request_failed.connect(func(kind: String, _code: String) -> void:
		if kind == "use":
			_use_wait_until = 0)
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
		var kind: String = quick_use_kind(item.id) if item != null else ""
		_slots[i].badge = {"heal": "치료", "eat": "먹기", "ammo": "화살"}.get(kind, "")
		_slots[i].badge_color = Color("#C8463A") if kind == "heal" else (Color("#4A9A3A") if kind == "eat" else Color("#6A6A78"))


## 퀵슬롯에서 누르면 바로 쓰는 종류: "heal" (치료용) · "eat" (먹고 마실 것) · "ammo" (무기 탄약) · "" (손에 든다).
static func quick_use_kind(item_id: String) -> String:
	var rules: SurvivalRules = GameData.survival
	if rules == null:
		return ""
	if HealButton.MEDICAL.has(item_id):
		return "heal"
	# (달걀 · 감자 같은 요리 재료는 손에 드는 그대로 — 실수로 먹지 않게. 가방 창 '사용' 이나 배고픔 막대로 먹는다.)
	if rules.heal_of(item_id) > 0:
		return "eat"
	for w: SurvivalRules.Weapon in rules.weapons.values():
		if w.ammo == item_id:
			return "ammo"
	return ""


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
	match quick_use_kind(item.id) if item != null else "":
		"heal", "eat":
			# 응답을 기다리는 동안 겹쳐 누르지 않는다 (서버 응답 · 실패가 오면 풀린다).
			if Time.get_ticks_msec() < _use_wait_until:
				return
			_use_wait_until = Time.get_ticks_msec() + 700
			Net.use_item(index)
			_pop(index)
			return
		"ammo":
			if toast_hud != null:
				toast_hud.show_toast("%s %d개 — 석궁을 들고 공격하면 하나씩 쏴요" % [GameData.item_name(item.id), item.count], false)
			return
	Net.equip(-1 if Net.held_slot == index else index)


## 바로 쓴 칸이 톡 줄었다 돌아온다.
func _pop(index: int) -> void:
	var s: ItemSlot = slot_button(index)
	if s == null:
		return
	s.pivot_offset = s.size * 0.5
	var tw: Tween = s.create_tween()
	tw.tween_property(s, "scale", Vector2.ONE * 0.86, 0.06)
	tw.tween_property(s, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _rider() -> KickboardRider:
	return get_tree().get_first_node_in_group(&"kickboard_rider") as KickboardRider if is_inside_tree() else null
