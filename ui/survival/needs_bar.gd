class_name NeedsBar
extends HBoxContainer
## v0.28.7 배고픔 · 목마름 (하트 오른쪽): 작은 그림 + 막대 둘 (배 · 물). 낮아지면 주황 → 빨강, 바닥나면 맥동.
## 막대를 누르면 가방에서 알맞은 것을 골라 바로 먹거나 마신다 (Net.use_item). 알림 기준 아래로 · 바닥나면 한 번씩 알림.
## 판정은 서버 (survival.js tickNeeds · handleUse).

const BAR: Vector2 = Vector2(116.0, 18.0)

var toast_hud: FishingHud = null
var _food: Button = null
var _water: Button = null
var _fills: Dictionary[String, ColorRect] = {}
var _warned: Dictionary[String, int] = {"food": 2, "water": 2}
var _time: float = 0.0


func _ready() -> void:
	name = "NeedsBar"
	position = Vector2(236.0, 258.0)
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_food = _make("food", "res://assets/icons/items/canned_food.png", Color("#E8A040"))
	_water = _make("water", "res://assets/icons/items/clean_water.png", Color("#4AA8E8"))
	Net.needs_changed.connect(_on_changed)
	Net.state_changed.connect(func(_st: int) -> void: visible = Net.state == Net.State.ONLINE)
	visible = Net.state == Net.State.ONLINE
	_on_changed(Net.food, Net.water)


func _make(kind: String, icon_path: String, color: Color) -> Button:
	var b: Button = Button.new()
	b.name = "Need_%s" % kind
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BAR.x + 40.0, 40.0)
	b.add_to_group(&"blocks_joystick")
	b.pressed.connect(func() -> void: consume(kind))
	var icon: TextureRect = TextureRect.new()
	icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(36.0, 36.0)
	icon.position = Vector2(0.0, 2.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var back: ColorRect = ColorRect.new()
	back.color = Color(0.08, 0.06, 0.06, 0.75)
	back.position = Vector2(38.0, 11.0)
	back.size = BAR
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(back)
	var fill: ColorRect = ColorRect.new()
	fill.color = color
	fill.position = Vector2(40.0, 13.0)
	fill.size = BAR - Vector2(4.0, 4.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_meta("base", color)
	b.add_child(fill)
	_fills[kind] = fill
	add_child(b)
	return b


func _on_changed(food: int, water: int) -> void:
	var mx: float = float(maxi(GameData.survival.needs_max if GameData.survival != null else 100, 1))
	for kind: String in ["food", "water"]:
		var v: int = food if kind == "food" else water
		var fill: ColorRect = _fills[kind]
		fill.size.x = (BAR.x - 4.0) * clampf(float(v) / mx, 0.0, 1.0)
		var base: Color = fill.get_meta("base")
		var warn: int = GameData.survival.needs_warn if GameData.survival != null else 25
		fill.color = base if v > warn else base.lerp(Color("#E83A2A"), 0.7)
		# 알림: 기준 아래로 (1) · 바닥 (0) 으로 떨어질 때 한 번씩.
		var level: int = 2 if v > warn else (1 if v > 0 else 0)
		if level < int(_warned[kind]) and toast_hud != null and Net.state == Net.State.ONLINE:
			if level == 1:
				toast_hud.show_toast("배가 고파요 — 막대를 누르면 가방의 통조림 · 건빵을 먹어요" if kind == "food" else "목이 말라요 — 막대를 누르면 가방의 물을 마셔요", false)
			else:
				toast_hud.show_toast("%s! 체력이 돌아오지 않고 조금씩 줄어요" % ("굶주리고 있어요" if kind == "food" else "탈수 상태예요"), false)
		_warned[kind] = level


## 가방에서 알맞은 것을 골라 먹거나 마신다 (모자란 만큼에 가장 가까운 것).
func consume(kind: String) -> void:
	var rules: SurvivalRules = GameData.survival
	var have_v: int = Net.food if kind == "food" else Net.water
	var missing: int = rules.needs_max - have_v
	var best_slot: int = -1
	var best_score: float = INF
	for i: int in Net.inventory.size():
		var it: InventoryItem = Net.inventory[i]
		if it == null or not rules.nourish.has(it.id):
			continue
		var gain: int = int((rules.nourish[it.id] as Dictionary).get(kind, 0))
		if gain <= 0:
			continue
		var score: float = absf(float(gain - missing)) + (50.0 if rules.heal_of(it.id) > 0 and gain < missing * 0.3 else 0.0)
		if score < best_score:
			best_score = score
			best_slot = i
	if best_slot < 0:
		if toast_hud != null:
			toast_hud.show_toast("가방에 %s 없어요 — 빈집 냉장고 · 상점에서 구해요" % ("먹을 것이" if kind == "food" else "마실 것이"), false)
		return
	if missing <= 1:
		if toast_hud != null:
			toast_hud.show_toast("배가 불러요" if kind == "food" else "목마르지 않아요", false)
		return
	Audio.play_ui(Audio.SFX_CLICK)
	Net.use_item(best_slot)


func _process(delta: float) -> void:
	_time += delta
	for kind: String in ["food", "water"]:
		var v: int = Net.food if kind == "food" else Net.water
		_fills[kind].modulate.a = (0.55 + 0.45 * absf(sin(_time * 5.0))) if v <= 0 else 1.0
