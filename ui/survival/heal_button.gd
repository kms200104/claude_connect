class_name HealButton
extends Button
## v0.28.6 치료 퀵버튼 (왼쪽, 조이스틱 위): 가방을 열지 않고 한 번에 치료한다 (Net.use_item — 서버가 가방 어느 칸이든 쓴다).
## 고르는 순서: 치료용(붕대 · 약초 연고 · 구급상자 — 피도 멈춘다) 중 모자란 체력을 채우는 가장 작은 것 (없으면 가장 큰 것).
## 치료용이 없으면 먹을 것(통조림 · 건빵 · 물). 그림 · 남은 개수, 체력이 30% 이하이면 붉게 맥동한다.
## 체력이 가득하거나 치료할 것이 없으면 흐리게 (눌러도 안내만). 응답을 기다리는 동안 다시 누르지 않는다.

const MEDICAL: PackedStringArray = ["bandage", "herb_salve", "first_aid_kit"]
const SIZE: float = 124.0

var toast_hud: FishingHud = null
var _icon: TextureRect = null
var _count: Label = null
var _style: StyleBoxFlat = null
var _pending_until: int = 0
var _time: float = 0.0
## 지금 고른 아이템 (빈 글자 = 없음).
var choice: String = ""


func _ready() -> void:
	name = "HealButton"
	focus_mode = Control.FOCUS_NONE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 40.0
	offset_right = 40.0 + SIZE
	offset_top = -640.0
	offset_bottom = -640.0 + SIZE
	add_to_group(&"blocks_joystick")
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.12, 0.08, 0.08, 0.82)
	_style.border_color = Color("#E8E0D0")
	_style.set_border_width_all(4)
	_style.set_corner_radius_all(int(SIZE * 0.5))
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, _style)
	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 18.0
	_icon.offset_top = 14.0
	_icon.offset_right = -18.0
	_icon.offset_bottom = -22.0
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	var plus: Label = Label.new()
	plus.text = "+"
	plus.position = Vector2(8.0, -6.0)
	plus.add_theme_font_size_override("font_size", 44)
	plus.add_theme_color_override("font_color", Color("#FF6A5A"))
	plus.add_theme_constant_override("outline_size", 8)
	plus.add_theme_color_override("font_outline_color", Color("#1A0A0A"))
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plus)
	_count = Label.new()
	_count.name = "Count"
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.offset_left = -64.0
	_count.offset_top = -40.0
	_count.offset_right = -10.0
	_count.offset_bottom = -4.0
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 28)
	_count.add_theme_constant_override("outline_size", 8)
	_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	pressed.connect(_use)
	Net.inventory_updated.connect(func(_inv: Array, _held: int) -> void: refresh())
	Net.hp_changed.connect(func(_hp: int, _max: int) -> void:
		_pending_until = 0
		refresh())
	Net.request_failed.connect(func(kind: String, _code: String) -> void:
		if kind == "use":
			_pending_until = 0)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: refresh())
	Net.state_changed.connect(func(_st: int) -> void: refresh())
	refresh()


## 가장 알맞은 치료 아이템 (빈 글자 = 없음).
static func pick(inventory: Array, heal: Dictionary, missing: int) -> String:
	var have: Dictionary[String, int] = {}
	for it: Variant in inventory:
		var item: InventoryItem = it as InventoryItem
		if item != null and heal.has(item.id):
			have[item.id] = int(have.get(item.id, 0)) + item.count
	var pool: Array[String] = []
	for id: String in have:
		if MEDICAL.has(id):
			pool.append(id)
	if pool.is_empty():
		pool.assign(have.keys())
	if pool.is_empty():
		return ""
	# 모자란 만큼을 채우는 가장 작은 것 → 없으면 가장 큰 것. (피를 흘리면 의료용만 남아 있으니 저절로 지혈된다.)
	pool.sort_custom(func(a: String, b: String) -> bool: return int(heal[a]) < int(heal[b]))
	for id: String in pool:
		if int(heal[id]) >= missing:
			return id
	return pool[pool.size() - 1]


func _slot_of(id: String) -> int:
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it != null and it.id == id:
			return i
	return -1


func refresh() -> void:
	var rules: SurvivalRules = GameData.survival
	if rules == null:
		return
	var missing: int = maxi(0, Net.max_hp - Net.hp)
	choice = pick(Net.inventory, rules.heal, maxi(missing, 1))
	visible = Net.state == Net.State.ONLINE
	if choice.is_empty():
		_icon.texture = null
		_count.text = "0"
		modulate.a = 0.45
		return
	var path: String = "res://assets/icons/items/%s.png" % choice
	_icon.texture = load(path) if ResourceLoader.exists(path) else null
	var n: int = 0
	for it: InventoryItem in Net.inventory:
		if it != null and it.id == choice:
			n += it.count
	_count.text = "×%d" % n
	modulate.a = 1.0 if missing > 0 else 0.55


func _use() -> void:
	if Time.get_ticks_msec() < _pending_until:
		return
	if choice.is_empty():
		_toast("치료할 것이 없어요 — 붕대 · 약초 연고 · 구급상자를 만들거나 사요")
		return
	if Net.hp >= Net.max_hp:
		_toast("체력이 가득해요")
		return
	var slot: int = _slot_of(choice)
	if slot < 0:
		return
	_pending_until = Time.get_ticks_msec() + 1500
	Audio.play_ui(Audio.SFX_CLICK)
	Net.use_item(slot)


func _toast(text: String) -> void:
	if toast_hud != null:
		toast_hud.show_toast(text, false)


func _process(delta: float) -> void:
	_time += delta
	var low: bool = Net.max_hp > 0 and float(Net.hp) / float(Net.max_hp) <= 0.3 and not choice.is_empty()
	var pulse: float = 0.5 + 0.5 * sin(_time * 7.0)
	_style.border_color = Color("#FF3A2A").lerp(Color("#FFD0C0"), pulse * 0.4) if low else Color("#E8E0D0")
	_style.set_border_width_all(6 if low else 4)
	scale = Vector2.ONE * (1.0 + (0.06 * pulse if low else 0.0))
	pivot_offset = size * 0.5
