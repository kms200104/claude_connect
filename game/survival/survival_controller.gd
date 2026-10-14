class_name SurvivalController
extends Node
## v0.23 생존 (마을에 붙는 쪽): 빈집촌(HouseField) · 밤 크리처(CreatureField) · 체력 하트 HUD · 다치면 붉은 테두리 ·
## 기절 안내 · 든 횃불 · 손전등 불빛 · 해 질 녘 안내. 상황 버튼 대상: "뒤지기"(빈집 가구) · "공격"(가까운 크리처).
## 판정은 서버 (Net.loot · Net.attack · Net.use_item).

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud
@export var clay_material: Material
@export var window_material: Material
@export var creature_material: Material

const TARGET_LOOT: String = "loot:"
const TARGET_ATTACK: String = "attack:"

var houses: HouseField = null
var creatures: CreatureField = null
var _hearts: HBoxContainer = null
var _vignette: ColorRect = null
var _light: OmniLight3D = null
var _was_night: bool = false
var _swing_ready_at: float = 0.0


func _ready() -> void:
	var world: Node = player.get_parent() if player != null else self
	houses = HouseField.new()
	houses.name = "Houses"
	houses.clay_material = clay_material
	houses.window_material = window_material
	houses.player = player
	world.add_child.call_deferred(houses)
	creatures = CreatureField.new()
	creatures.name = "Creatures"
	creatures.material = creature_material
	world.add_child.call_deferred(creatures)
	_build_hud()
	_light = OmniLight3D.new()
	_light.name = "HeldLight"
	_light.light_color = Color("#FFC870")
	_light.omni_range = 6.0
	_light.light_energy = 1.6
	_light.shadow_enabled = false
	_light.visible = false
	if player != null:
		player.add_child.call_deferred(_light)
		_light.position = Vector3(0.3, 1.5, -0.3)
	Net.hp_changed.connect(func(_hp: int, _max: int) -> void: _refresh_hearts())
	Net.hurt.connect(_on_hurt)
	Net.knocked_out.connect(_on_ko)
	Net.looted.connect(_on_looted)
	Net.swung.connect(_on_swung)
	Net.request_failed.connect(_on_failed)
	_was_night = _is_night()


func _is_night() -> bool:
	return Net.state == Net.State.ONLINE and GameData.survival.is_night(Net.game_hour())


func _process(_delta: float) -> void:
	var night: bool = _is_night()
	if night != _was_night:
		_was_night = night
		if toast_hud != null and night:
			toast_hud.show_toast("밤이 됐어요 — 크리처가 나와요. 횃불 · 손전등 · 모닥불 곁과 집 안 · 대피소는 안전해요", false)
		elif toast_hud != null:
			toast_hud.show_toast("해가 떴어요. 크리처가 흩어졌어요", true)
	# 든 횃불 · 손전등 불빛 (밤에).
	if _light != null and player != null:
		var w: SurvivalRules.Weapon = GameData.survival.weapon_of(player.held_item)
		_light.visible = night and w.light > 0.0
		if _light.visible:
			_light.omni_range = w.light * 1.8
			_light.light_color = Color("#FFC870") if player.held_item == "torch" else Color("#F4F8FF")
	if _vignette != null and _vignette.color.a > 0.0:
		_vignette.color.a = maxf(0.0, _vignette.color.a - _delta * 1.2)


## 상황 버튼 대상 (빈 글자 = 없음). 밤에 크리처가 곁이면 공격이 먼저.
func pick_target(position: Vector3, margin: float = 0.3) -> String:
	if creatures != null and not Net.creatures.is_empty():
		var w: SurvivalRules.Weapon = GameData.survival.weapon_of(player.held_item)
		var near: String = creatures.nearest(position, w.range_m + 0.4)
		if not near.is_empty():
			return TARGET_ATTACK + near
	var rules: SurvivalRules = GameData.survival
	var best: String = ""
	var best_d: float = rules.loot_range - margin
	for c: SurvivalRules.LootBox in rules.containers.values():
		var d: float = Vector2(c.position.x - position.x, c.position.z - position.z).length()
		if d <= best_d and Net.can_loot(c.id):
			best_d = d
			best = c.id
	return TARGET_LOOT + best if not best.is_empty() else ""


func target_label(target: String) -> String:
	if target.begins_with(TARGET_ATTACK):
		return "공격"
	var c: SurvivalRules.LootBox = GameData.survival.containers.get(target.trim_prefix(TARGET_LOOT))
	return "뒤지기 · %s" % GameData.survival.kind_name(c.kind) if c != null else "뒤지기"


func activate(target: String) -> void:
	if target.begins_with(TARGET_ATTACK):
		var now_s: float = Time.get_ticks_msec() / 1000.0
		if now_s < _swing_ready_at:
			return
		var w: SurvivalRules.Weapon = GameData.survival.weapon_of(player.held_item)
		_swing_ready_at = now_s + float(w.cooldown_ms) / 1000.0
		var at: Vector3 = creatures.actor_position(target.trim_prefix(TARGET_ATTACK))
		if at != Vector3.INF:
			player.look_toward(at - player.global_position)
		player.play_chop()
		Audio.play_sfx("chop", -10.0, 1.3)
		Net.attack()
		return
	var c: SurvivalRules.LootBox = GameData.survival.containers.get(target.trim_prefix(TARGET_LOOT))
	if c == null:
		return
	player.look_toward(c.position - player.global_position)
	player.play_plant()
	Net.loot(c.id)


func _on_looted(info: Dictionary) -> void:
	var items: Array = info.get("items", [])
	if toast_hud == null:
		return
	if items.is_empty():
		toast_hud.show_toast("아무것도 없었어요…", false)
		return
	var parts: PackedStringArray = []
	for it: Variant in items:
		parts.append("%s ×%d" % [GameData.item_name(str(it.get("id", ""))), int(it.get("n", 1))])
	toast_hud.show_toast("찾았다! %s" % " · ".join(parts), true)
	Audio.play_sfx("quest_done", -10.0)


func _on_swung(info: Dictionary) -> void:
	if str(info.get("hit", "")).is_empty():
		Audio.play_sfx("chop", -16.0, 1.6)


func _on_hurt(info: Dictionary) -> void:
	if _vignette != null:
		_vignette.color.a = 0.45
	Prefs.vibrate(120, 0.5)
	Audio.play_sfx("chop", -4.0, 0.5)
	var kind: SurvivalRules.CreatureKind = GameData.survival.creature_kinds.get(str(info.get("by", "")))
	if toast_hud != null and Net.hp <= 3:
		toast_hud.show_toast("%s에게 맞았어요! 체력이 얼마 안 남았어요 — 붕대 · 음식을 쓰거나 집 안으로" % (kind.name if kind != null else "크리처"), false)


func _on_ko(info: Dictionary) -> void:
	if player != null:
		player.global_position = Vector3(float(info.get("x", 0.0)), 0.1, float(info.get("z", 0.0)))
		player.velocity = Vector3.ZERO
	if toast_hud != null:
		toast_hud.show_toast("기절했어요… 대피소에서 깨어났어요 (%s)" % Money.delta(-int(info.get("lost", 0))), false)
	if _vignette != null:
		_vignette.color = Color(0.0, 0.0, 0.0, 0.85)
		var tween: Tween = _vignette.create_tween()
		tween.tween_property(_vignette, "color", Color(0.6, 0.0, 0.0, 0.0), 1.6)


func _on_failed(kind: String, code: String) -> void:
	if toast_hud == null:
		return
	if kind == "use" and code == NetProtocol.ERR_HP_FULL:
		toast_hud.show_toast("체력이 가득해요", false)
	elif kind == "loot" and code == NetProtocol.ERR_ALREADY_LOOTED:
		toast_hud.show_toast("이미 누가 뒤졌어요. 시간이 지나면 다시 찰지도", false)
	elif kind == "loot" and code == NetProtocol.ERR_TOO_FAR:
		toast_hud.show_toast("조금 더 가까이 가요", false)


func _build_hud() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "HurtVignette"
	_vignette.color = Color(0.7, 0.0, 0.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hearts = HBoxContainer.new()
	_hearts.name = "Hearts"
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hearts.add_theme_constant_override("separation", 2)
	_hearts.position = Vector2(24.0, 262.0)
	if hud != null:
		hud.add_child.call_deferred(_vignette)
		hud.add_child.call_deferred(_hearts)
	_refresh_hearts()


func _refresh_hearts() -> void:
	if _hearts == null:
		return
	for c: Node in _hearts.get_children():
		c.queue_free()
	# 하트 하나 = 체력 2 (반 하트는 옅게).
	var full: int = Net.hp / 2
	var half: int = Net.hp % 2
	var total: int = ceili(Net.max_hp / 2.0)
	for i: int in total:
		var l: Label = Label.new()
		l.text = "♥"
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color("#4A2A2A"))
		var color: Color = Color("#E8453C") if i < full else (Color("#F2A09A") if i == full and half == 1 else Color("#6A5A58", 0.6))
		l.add_theme_color_override("font_color", color)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hearts.add_child(l)
	_hearts.visible = Net.state == Net.State.ONLINE
