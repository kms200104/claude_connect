class_name SurvivalController
extends Node
## v0.23 생존 (마을에 붙는 쪽): 빈집촌(HouseField) · 밤 크리처(CreatureField) · 체력 하트 HUD · 다치면 붉은 테두리 ·
## 기절 안내 · 든 횃불 · 손전등 불빛 · 해 질 녘 안내. 상황 버튼 대상: "뒤지기"(빈집 가구) · "공격"(가까운 크리처).
## v0.24: "판자 대기 · 보수"(빈집 현관 · 깨진 창) · "일으키기"(쓰러진 동료). 쓰러지면 누운 몸 · 화면 안내(남은 시간 · 포기),
## 쓰러진 동료 머리 위 "도와줘요!".
## 판정은 서버 (Net.loot · Net.attack · Net.use_item · Net.board · Net.revive · Net.give_up).

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud
@export var clay_material: Material
@export var window_material: Material
@export var creature_material: Material

const TARGET_LOOT: String = "loot:"
const TARGET_ATTACK: String = "attack:"
const TARGET_BOARD: String = "board:"
const TARGET_REVIVE: String = "revive:"
## 누운 몸: 옆으로 눕히는 각 · 내리는 높이 (리그 뿌리 기준). 앞뒤(x)는 리그가 낚시 당김에 쓴다.
const DOWN_ROLL: float = 1.45
const DOWN_DROP: float = 0.55
const INPUT_LOCK: StringName = &"downed"

var houses: HouseField = null
var creatures: CreatureField = null
var _hearts: HBoxContainer = null
var _vignette: ColorRect = null
var _light: OmniLight3D = null
var _was_night: bool = false
var _swing_ready_at: float = 0.0
## 쓰러졌을 때 화면 안내.
var _down_panel: PanelContainer = null
var _down_label: Label = null
var _give_up: Button = null
## 쓰러진 동료 머리 위 글자 (id → Label3D).
var _help_tags: Dictionary[int, Label3D] = {}


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
	Net.boarded.connect(_on_boarded)
	Net.downed_changed.connect(_on_downed_changed)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void:
		_on_downed_changed(Net.my_id)
		for id: int in Net.downed:
			_on_downed_changed(id))
	_was_night = _is_night()


func _is_night() -> bool:
	return Net.state == Net.State.ONLINE and GameData.survival.is_night(Net.game_hour())


func _process(_delta: float) -> void:
	var night: bool = _is_night()
	if night != _was_night:
		_was_night = night
		if toast_hud != null and night:
			toast_hud.show_toast("밤이 됐어요 — 크리처가 나와요. 횃불 · 손전등 · 모닥불 곁, 대피소, 판자를 댄 빈집이 안전해요", false)
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
	_update_downed(_delta)


## 상황 버튼 대상 (빈 글자 = 없음). 쓰러진 동료 곁이면 일으키기, 밤에 크리처가 곁이면 공격이 먼저,
## 그다음 가까운 쪽: 뒤질 가구 · 판자 댈 곳. 내가 쓰러져 있으면 없음.
func pick_target(position: Vector3, margin: float = 0.3) -> String:
	if Net.is_downed(Net.my_id):
		return ""
	var rules: SurvivalRules = GameData.survival
	for id: int in Net.downed:
		var at: Vector3 = _remote_position(id)
		if id != Net.my_id and at != Vector3.INF and Vector2(at.x - position.x, at.z - position.z).length() <= rules.revive_range - margin:
			return TARGET_REVIVE + str(id)
	if creatures != null and not Net.creatures.is_empty():
		var w: SurvivalRules.Weapon = rules.weapon_of(player.held_item)
		var near: String = creatures.nearest(position, w.range_m + 0.4)
		if not near.is_empty():
			return TARGET_ATTACK + near
	var best: String = ""
	var best_d: float = rules.loot_range - margin
	for c: SurvivalRules.LootBox in rules.containers.values():
		var d: float = Vector2(c.position.x - position.x, c.position.z - position.z).length()
		if d <= best_d and Net.can_loot(c.id):
			best_d = d
			best = TARGET_LOOT + c.id
	var board_d: float = minf(best_d, rules.fortify_range - margin) if not best.is_empty() else rules.fortify_range - margin
	for b: SurvivalRules.Breach in rules.breaches.values():
		var d: float = Vector2(b.position.x - position.x, b.position.z - position.z).length()
		if d <= board_d and int(Net.boards.get(b.key, 0)) < b.max_hp:
			board_d = d
			best = TARGET_BOARD + b.key
	return best


func target_label(target: String) -> String:
	if target.begins_with(TARGET_ATTACK):
		return "공격"
	if target.begins_with(TARGET_REVIVE):
		return "일으키기 · %s" % GameData.player_name(int(target.trim_prefix(TARGET_REVIVE)))
	if target.begins_with(TARGET_BOARD):
		var key: String = target.trim_prefix(TARGET_BOARD)
		var where: String = "현관" if key.ends_with(":door") else "창"
		var verb: String = "판자 보수" if int(Net.boards.get(key, 0)) > 0 else "판자 대기"
		return "%s · %s (%s)" % [verb, where, cost_text()]
	var c: SurvivalRules.LootBox = GameData.survival.containers.get(target.trim_prefix(TARGET_LOOT))
	return "뒤지기 · %s" % GameData.survival.kind_name(c.kind) if c != null else "뒤지기"


## 판자 값 글자 ("목재 2 · 못 1").
func cost_text() -> String:
	var parts: PackedStringArray = []
	for c: Dictionary in GameData.survival.fortify_cost:
		parts.append("%s ×%d" % [GameData.item_name(str(c["id"])), int(c["n"])])
	return " · ".join(parts)


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
	if target.begins_with(TARGET_REVIVE):
		var id: int = int(target.trim_prefix(TARGET_REVIVE))
		var at: Vector3 = _remote_position(id)
		if at != Vector3.INF:
			player.look_toward(at - player.global_position)
		player.play_plant()
		Net.revive(id)
		if toast_hud != null:
			toast_hud.show_toast("%s 님을 일으키는 중… %d초 동안 곁에 있어 주세요" % [GameData.player_name(id), ceili(GameData.survival.revive_ms / 1000.0)], true)
		return
	if target.begins_with(TARGET_BOARD):
		var key: String = target.trim_prefix(TARGET_BOARD)
		var b: SurvivalRules.Breach = GameData.survival.breaches.get(key)
		if b == null:
			return
		player.look_toward(b.position - player.global_position)
		player.play_chop()
		Audio.play_sfx("chop", -8.0, 0.9)
		Net.board(b.house, b.id)
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
		toast_hud.show_toast("%s에게 맞았어요! 체력이 얼마 안 남았어요 — 붕대 · 음식을 쓰거나 판자 댄 빈집으로" % (kind.name if kind != null else "크리처"), false)


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
	elif (kind == "loot" or kind == "board" or kind == "revive") and code == NetProtocol.ERR_TOO_FAR:
		toast_hud.show_toast("조금 더 가까이 가요", false)
	elif kind == "board" and code == NetProtocol.ERR_NOT_ENOUGH_ITEMS:
		toast_hud.show_toast("판자를 대려면 %s 가 있어야 해요 (목재는 도끼로 나무, 못은 공구 창고에서 고철로)" % cost_text(), false)
	elif kind == "board" and code == NetProtocol.ERR_ALREADY_BOARDED:
		toast_hud.show_toast("판자가 아직 튼튼해요", true)


func _on_boarded(info: Dictionary) -> void:
	if toast_hud == null:
		return
	var where: String = "현관" if str(info.get("o", "")) == "door" else "창"
	toast_hud.show_toast("%s에 판자를 %s (튼튼함 %d)" % [where, "다시 댔어요" if bool(info.get("repaired", false)) else "댔어요", int(info.get("hp", 0))], true)
	Audio.play_sfx("chop", -6.0, 0.8)


# ---- 쓰러짐 ----

func _remote_node(id: int) -> RemotePlayer:
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if replicator == null:
		return null
	for r: RemotePlayer in replicator.remote_nodes():
		if r.player_id == id:
			return r
	return null


func _remote_position(id: int) -> Vector3:
	var r: RemotePlayer = _remote_node(id)
	return r.global_position if r != null else Vector3.INF


func _on_downed_changed(id: int) -> void:
	var down: bool = Net.is_downed(id)
	if id == Net.my_id:
		if player != null:
			player.set_input_lock(INPUT_LOCK, down)
			if down:
				player.velocity = Vector3.ZERO
		if _down_panel != null:
			if not down and _down_panel.visible and toast_hud != null and Net.hp > 0:
				toast_hud.show_toast("일어났어요! 고마워요", true)
			_down_panel.visible = down
		return
	var r: RemotePlayer = _remote_node(id)
	if down and not _help_tags.has(id) and r != null:
		var tag: Label3D = Label3D.new()
		tag.name = "HelpTag"
		tag.text = "도와줘요!"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.font_size = 56
		tag.outline_size = 12
		tag.modulate = Color("#FF6A5A")
		tag.position = Vector3(0.0, 1.6, 0.0)
		r.add_child(tag)
		_help_tags[id] = tag
		if toast_hud != null:
			toast_hud.show_toast("%s 님이 쓰러졌어요! 곁에 가서 '일으키기'" % GameData.player_name(id), false)
	elif not down and _help_tags.has(id):
		if is_instance_valid(_help_tags[id]):
			_help_tags[id].queue_free()
		_help_tags.erase(id)


## 누운 몸 (나 · 동료), 쓰러진 동안 화면 안내 · 동료 머리 위 글자.
func _update_downed(delta: float) -> void:
	if player != null and player.body != null:
		_pose(player.body, Net.is_downed(Net.my_id), player.body_rest_height(), delta)
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if replicator != null:
		for r: RemotePlayer in replicator.remote_nodes():
			if r.body != null:
				_pose(r.body, Net.is_downed(r.player_id), 0.8, delta)
	var now_ms: int = Time.get_ticks_msec()
	for id: int in _help_tags:
		var info: Dictionary = Net.downed.get(id, {})
		var tag: Label3D = _help_tags[id]
		if is_instance_valid(tag) and not info.is_empty():
			tag.text = "일으키는 중…" if int(info.get("by", 0)) != 0 else "도와줘요! %d" % maxi(0, ceili((int(info["until"]) - now_ms) / 1000.0))
	if _down_panel != null and _down_panel.visible:
		var me: Dictionary = Net.downed.get(Net.my_id, {})
		var left: int = maxi(0, ceili((int(me.get("until", now_ms)) - now_ms) / 1000.0))
		var by: int = int(me.get("by", 0))
		_down_label.text = ("%s 님이 일으키는 중…" % GameData.player_name(by)) if by != 0 else "쓰러졌어요!\n동료가 와서 일으켜 주면 솔을 잃지 않아요 (%d초)" % left


func _pose(body: Node3D, down: bool, rest: float, delta: float) -> void:
	var goal: float = DOWN_ROLL if down else 0.0
	if is_equal_approx(body.rotation.z, goal) and not down:
		return
	body.rotation.z = move_toward(body.rotation.z, goal, delta * 4.0)
	body.position.y = rest - DOWN_DROP * (body.rotation.z / DOWN_ROLL)


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
	_down_panel = PanelContainer.new()
	_down_panel.name = "DownedPanel"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.04, 0.04, 0.82)
	style.set_corner_radius_all(28)
	style.set_content_margin_all(28)
	_down_panel.add_theme_stylebox_override("panel", style)
	_down_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_down_panel.offset_left = -440.0
	_down_panel.offset_right = 440.0
	_down_panel.offset_top = -620.0
	_down_panel.offset_bottom = -380.0
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_down_panel.add_child(box)
	_down_label = Label.new()
	_down_label.name = "DownedLabel"
	_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_down_label.add_theme_font_size_override("font_size", 36)
	_down_label.add_theme_color_override("font_color", Color("#FFE8E0"))
	box.add_child(_down_label)
	_give_up = Button.new()
	_give_up.name = "GiveUpButton"
	_give_up.text = "포기하고 대피소에서 깨어나기"
	_give_up.custom_minimum_size = Vector2(0.0, 96.0)
	_give_up.add_theme_font_size_override("font_size", 32)
	_give_up.pressed.connect(Net.give_up)
	box.add_child(_give_up)
	_down_panel.visible = false
	if hud != null:
		hud.add_child.call_deferred(_vignette)
		hud.add_child.call_deferred(_hearts)
		hud.add_child.call_deferred(_down_panel)
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
