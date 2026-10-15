class_name SurvivalController
extends Node
## v0.23 생존 (마을에 붙는 쪽): 빈집촌(HouseField) · 밤 크리처(CreatureField) · 체력 하트 HUD · 다치면 붉은 테두리 ·
## 기절 안내 · 든 횃불 · 손전등 불빛 · 해 질 녘 안내. 상황 버튼 대상: "뒤지기"(빈집 가구) · "공격"(가까운 크리처).
## v0.24: "판자 대기 · 보수"(빈집 현관 · 깨진 창) · "일으키기"(쓰러진 동료). 쓰러지면 누운 몸 · 화면 안내(남은 시간 · 포기),
## 쓰러진 동료 머리 위 "도와줘요!".
## v0.25: 판자는 시간 들여 대고 (진행 막대, 함께 대면 빨라진다), 밤에 소리를 내면 크리처가 몰려온다 (먼지 · 안내),
## 거점(다 막은 빈집)의 "거점 상자"(StashWindow) · "자기"(침대, 누운 몸 · 일어나기). 집 안에서는 판자 몇 곳을 막았는지 알림.
## v0.26: 피 냄새 — 다쳐서 피를 흘리면 하트 아래 "피 냄새" 알림, 땅에 핏자국 (모두에게 보이고 시간이 지나면 작아져 사라진다).
## v0.27: 보급 상자 (SupplyField) — 떨어지면 안내, HUD 에 방향 화살표 · 거리, 곁에서 "보급 상자 열기" (먼저 연 사람이 갖는다).
## 판정은 서버 (Net.loot · Net.attack · Net.use_item · Net.board · Net.revive · Net.give_up · Net.stash_* · Net.sleep_in_bed).

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
const TARGET_STASH: String = "stash:"
const TARGET_BED: String = "bed:"
const TARGET_SUPPLY: String = "supply:"
## 누운 몸: 옆으로 눕히는 각 · 내리는 높이 (리그 뿌리 기준). 앞뒤(x)는 리그가 낚시 당김에 쓴다.
const DOWN_ROLL: float = 1.45
const DOWN_DROP: float = 0.55
const INPUT_LOCK: StringName = &"downed"
const SLEEP_LOCK: StringName = &"sleeping"
## 달리다 휘두르면 (기술 없이) 잠깐 선다.
const SWING_LOCK: StringName = &"swing"
## 침대 매트 높이만큼 몸을 올린다.
const BED_LIFT: float = 0.42

var houses: HouseField = null
var creatures: CreatureField = null
var supply: SupplyField = null
var barriers: BarrierField = null
var guards: GuardField = null
## v0.27 보급 상자 방향 (화살표 · 거리 글자).
var _supply_chip: HBoxContainer = null
var _supply_arrow: Label = null
var _supply_label: Label = null
var _hearts: HBoxContainer = null
var _vignette: ColorRect = null
var _hurt: HurtOverlay = null
var edge_hint: CreatureEdgeHint = null
## v0.28.1 핏자국 머티리얼 (젖어 번들거리는 정점 색) · 마지막 핏자국 자리 (끌린 방향).
static var _blood_material: StandardMaterial3D = null
var _last_drop: Vector2 = Vector2.INF
var _light: OmniLight3D = null
var _was_night: bool = false
var _swing_ready_at: float = 0.0
## 쓰러졌을 때 화면 안내.
var _down_panel: PanelContainer = null
var _down_label: Label = null
var _give_up: Button = null
## 쓰러진 동료 머리 위 글자 (id → Label3D).
var _help_tags: Dictionary[int, Label3D] = {}
var stash_window: StashWindow = null
## 판자 대는 중 막대 · 자는 중 안내 · 집 안 알림.
var _job_panel: PanelContainer = null
var _job_bar: ProgressBar = null
var _job_label: Label = null
var _sleep_panel: PanelContainer = null
var _chip: Label = null
var _hammer_at: float = 0.0
var _noise_tip_at: float = -100.0
var _blood_chip: Label = null
## 핏자국 메시 (Net.scent 와 같은 순서).
var _drops: Array[Dictionary] = []


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
	supply = SupplyField.new()
	world.add_child.call_deferred(supply)
	barriers = BarrierField.new()
	world.add_child.call_deferred(barriers)
	guards = GuardField.new()
	world.add_child.call_deferred(guards)
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
	Net.sleep_changed.connect(_on_sleep_changed)
	Net.noise_made.connect(_on_noise)
	Net.scent_dropped.connect(_on_scent)
	Net.bleed_changed.connect(_on_bleed)
	Net.supply_changed.connect(_on_supply_changed)
	Net.supply_taken.connect(_on_supply_taken)
	Net.supply_got.connect(_on_supply_got)
	Net.npc_hurt.connect(_on_npc_hurt)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void:
		for d: Dictionary in _drops:
			if is_instance_valid(d["node"]):
				(d["node"] as Node).queue_free()
		_drops.clear()
		for drop: Dictionary in Net.scent:
			_on_scent(drop))
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
	_update_jobs()
	_update_chip()
	_update_scent()
	_update_supply_chip()


## 상황 버튼 대상 (빈 글자 = 없음). 쓰러진 동료 곁이면 일으키기, 밤에 크리처가 곁이면 공격이 먼저,
## 그다음 가까운 쪽: 뒤질 가구 · 판자 댈 곳. 내가 쓰러져 있으면 없음.
func pick_target(position: Vector3, margin: float = 0.3) -> String:
	if Net.is_downed(Net.my_id) or Net.sleeping.has(Net.my_id):
		return ""
	var rules: SurvivalRules = GameData.survival
	for id: int in Net.downed:
		var at: Vector3 = _remote_position(id)
		if id != Net.my_id and at != Vector3.INF and Vector2(at.x - position.x, at.z - position.z).length() <= rules.revive_range - margin:
			return TARGET_REVIVE + str(id)
	# 보급 상자 (땅에 닿은 것): 크리처가 곁에 있어도 먼저 연다 (먼저 연 사람이 갖는다).
	if supply != null and not Net.supply.is_empty():
		var sid: String = supply.nearest(position, true)
		var sp: Vector3 = supply.crate_position(sid) if not sid.is_empty() else Vector3.INF
		if sp != Vector3.INF and Vector2(sp.x - position.x, sp.z - position.z).length() <= rules.supply_range - margin:
			return TARGET_SUPPLY + sid
	if creatures != null and not Net.creatures.is_empty():
		var w: SurvivalRules.Weapon = rules.weapon_of(player.held_item)
		# 기술이 있으면 달릴 때 더 먼 크리처도 노린다.
		var reach: float = HunterApp.skill_reach("run_attack") if _is_running() and Net.has_skill("run_attack") else 0.0
		var near: String = creatures.nearest(position, w.range_m + 0.4 + reach)
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
	# 빈집 안: 거점 상자 · 침대.
	var house: SurvivalRules.House = rules.house_at(position)
	if house != null:
		var near_d: float = board_d if best.begins_with(TARGET_BOARD) else (best_d if not best.is_empty() else INF)
		var sd: float = Vector2(house.stash_position.x - position.x, house.stash_position.z - position.z).length()
		if sd <= rules.base_range - margin and sd < near_d:
			near_d = sd
			best = TARGET_STASH + house.id
		var bd: float = Vector2(house.bed_position.x - position.x, house.bed_position.z - position.z).length()
		if bd <= rules.base_range - margin + 0.2 and bd < near_d:
			best = TARGET_BED + house.id
	return best


func is_busy() -> bool:
	return stash_window != null and stash_window.is_open()


func target_label(target: String) -> String:
	if target.begins_with(TARGET_ATTACK):
		return "공격"
	if target.begins_with(TARGET_SUPPLY):
		return "보급 상자 열기"
	if target.begins_with(TARGET_REVIVE):
		return "일으키기 · %s" % GameData.player_name(int(target.trim_prefix(TARGET_REVIVE)))
	if target.begins_with(TARGET_BOARD):
		var key: String = target.trim_prefix(TARGET_BOARD)
		var where: String = "현관" if key.ends_with(":door") else "창"
		if Net.board_jobs.has(key) and not (Net.board_jobs[key]["helpers"] as Array).has(Net.my_id):
			return "함께 판자 대기 · %s (빨라져요)" % where
		var verb: String = "판자 보수" if int(Net.boards.get(key, 0)) > 0 else "판자 대기"
		return "%s · %s (%s)" % [verb, where, cost_text()]
	if target.begins_with(TARGET_STASH):
		var h: SurvivalRules.House = _house(target.trim_prefix(TARGET_STASH))
		return "거점 상자 열기" if h != null and HouseField.is_base(h) else "상자 · 판자를 다 대면 열려요 (%s)" % _boarded_text(h)
	if target.begins_with(TARGET_BED):
		var hb: SurvivalRules.House = _house(target.trim_prefix(TARGET_BED))
		return "자기 · 빨리 회복" if hb != null and HouseField.is_base(hb) else "침대 · 판자를 다 대야 잘 수 있어요 (%s)" % _boarded_text(hb)
	var c: SurvivalRules.LootBox = GameData.survival.containers.get(target.trim_prefix(TARGET_LOOT))
	return "뒤지기 · %s" % GameData.survival.kind_name(c.kind) if c != null else "뒤지기"


## 판자 값 글자 ("목재 2 · 못 1").
func cost_text() -> String:
	var parts: PackedStringArray = []
	for c: Dictionary in GameData.survival.fortify_cost:
		parts.append("%s ×%d" % [GameData.item_name(str(c["id"])), int(c["n"])])
	return " · ".join(parts)


func activate(target: String) -> void:
	if target.begins_with(TARGET_SUPPLY):
		var sid: String = target.trim_prefix(TARGET_SUPPLY)
		var sp: Vector3 = supply.crate_position(sid)
		if sp != Vector3.INF:
			player.look_toward(sp - player.global_position)
		player.play_plant()
		Net.open_supply(sid)
		return
	if target.begins_with(TARGET_ATTACK):
		var now_s: float = Time.get_ticks_msec() / 1000.0
		if now_s < _swing_ready_at:
			return
		var w: SurvivalRules.Weapon = GameData.survival.weapon_of(player.held_item)
		# 민첩만큼 공격 간격이 짧다.
		_swing_ready_at = now_s + float(w.cooldown_ms) / 1000.0 * (1.0 - float((Net.hunter.get("st", {}) as Dictionary).get("agi", 0)) * HunterApp.stat_value("agi", "cooldown"))
		var at: Vector3 = creatures.actor_position(target.trim_prefix(TARGET_ATTACK))
		var run: bool = _is_running()
		# v0.28.1 달리며 공격: 기술이 있으면 멈추지 않고 돌진해 벤다, 없으면 달리다 휘두르면 잠깐 멈춘다.
		if run and Net.has_skill("run_attack"):
			if at != Vector3.INF:
				Puff.burst(player.get_parent(), player.global_position + Vector3(0.0, 0.3, 0.0), Color(0.85, 0.8, 0.7, 0.8), 6, 0.6, 0.25, 0.08, 0.35)
		else:
			if at != Vector3.INF:
				player.look_toward(at - player.global_position)
			if run:
				player.set_input_lock(SWING_LOCK, true)
				get_tree().create_timer(0.35).timeout.connect(func() -> void: player.set_input_lock(SWING_LOCK, false))
		player.play_chop()
		Audio.play_sfx("chop", -10.0, 1.3)
		Net.attack(run)
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
	if target.begins_with(TARGET_STASH) or target.begins_with(TARGET_BED):
		var bed: bool = target.begins_with(TARGET_BED)
		var h: SurvivalRules.House = _house(target.trim_prefix(TARGET_BED if bed else TARGET_STASH))
		if h == null:
			return
		if not HouseField.is_base(h):
			if toast_hud != null:
				toast_hud.show_toast("현관과 깨진 창에 판자를 다 대야 거점이 돼요 (%s)" % _boarded_text(h), false)
			return
		if bed:
			if Net.hp >= Net.max_hp:
				if toast_hud != null:
					toast_hud.show_toast("체력이 가득해서 잠이 안 와요", false)
				return
			Net.sleep_in_bed(true)
		else:
			player.look_toward(h.stash_position - player.global_position)
			stash_window.open(h.id)
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
	# v0.28.1 화면 가장자리가 붉게 번지고 피가 튀며 화면이 흔들린다 (HurtOverlay).
	var lost: float = 1.0 - float(Net.hp) / float(maxi(Net.max_hp, 1))
	if _hurt != null:
		_hurt.hit(0.4 + lost * 0.6)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and cam.get_parent() is FollowCamera:
		(cam.get_parent() as FollowCamera).shake(0.1 + lost * 0.12, 0.35)
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
	elif (kind == "stash" or kind == "sleep") and code == NetProtocol.ERR_NOT_BASE:
		toast_hud.show_toast("판자가 부서졌어요 — 다시 막아야 거점이 돼요", false)
	elif kind == "stash" and code == NetProtocol.ERR_STASH_FULL:
		toast_hud.show_toast("상자가 가득해요 (%d칸)" % GameData.survival.stash_slots, false)
	elif kind == "stash" and code == NetProtocol.ERR_INVENTORY_FULL:
		toast_hud.show_toast("가방이 가득해요", false)
	elif kind == "sleep" and code == NetProtocol.ERR_HP_FULL:
		toast_hud.show_toast("체력이 가득해서 잠이 안 와요", false)
	elif kind == "supply_open" and code == NetProtocol.ERR_ALREADY_LOOTED:
		toast_hud.show_toast("한발 늦었어요 — 누가 먼저 열었어요", false)
	elif kind == "supply_open" and code == NetProtocol.ERR_SUPPLY_FALLING:
		toast_hud.show_toast("아직 떨어지는 중이에요", false)
	elif kind == "supply_open" and code == NetProtocol.ERR_TOO_FAR:
		toast_hud.show_toast("조금 더 가까이 가요", false)


func _on_boarded(info: Dictionary) -> void:
	if toast_hud == null:
		return
	var where: String = "현관" if str(info.get("o", "")) == "door" else "창"
	var together: String = " · 함께 대서 빨랐어요" if int(info.get("helpers", 1)) > 1 else ""
	toast_hud.show_toast("%s에 판자를 %s (튼튼함 %d)%s" % [where, "다시 댔어요" if bool(info.get("repaired", false)) else "댔어요", int(info.get("hp", 0)), together], true)
	Audio.play_sfx("chop", -6.0, 0.8)
	var h: SurvivalRules.House = _house(str(info.get("h", "")))
	if h != null and HouseField.is_base(h):
		toast_hud.show_toast("거점이 됐어요! 상자에 물건을 두고 침대에서 쉴 수 있어요", true)


func _house(id: String) -> SurvivalRules.House:
	for h: SurvivalRules.House in GameData.survival.houses:
		if h.id == id:
			return h
	return null


func _boarded_text(h: SurvivalRules.House) -> String:
	if h == null:
		return ""
	var done: int = 0
	for b: SurvivalRules.Breach in h.breaches:
		if int(Net.boards.get(b.key, 0)) > 0:
			done += 1
	return "판자 %d/%d" % [done, h.breaches.size()]


# ---- 피 냄새 (v0.26) ----

func _on_bleed(id: int) -> void:
	if id != Net.my_id:
		return
	if toast_hud != null and Net.bleeding.has(id):
		toast_hud.show_toast("피 냄새가 나요 — 크리처가 더 멀리서 알아채고 핏자국을 따라와요. 붕대 · 연고 · 구급상자로 멈춰요", false)
	elif toast_hud != null and Net.hp > 0:
		toast_hud.show_toast("피가 멈췄어요", true)


## 땅에 핏자국 한 점 (작은 얼룩 몇 개).
func _on_scent(drop: Dictionary) -> void:
	if player == null:
		return
	var at: Vector2 = Vector2(float(drop["x"]), float(drop["z"]))
	# 걸어온 쪽 (앞 핏자국에서) — 피가 그쪽으로 끌린다.
	var dir: Vector2 = (at - _last_drop).normalized() if _last_drop != Vector2.INF and _last_drop.distance_to(at) < 12.0 and _last_drop.distance_to(at) > 0.05 else Vector2.from_angle(float(hash(at) % 628) * 0.01)
	_last_drop = at
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Scent"
	mi.mesh = blood_mesh(hash(at), dir)
	mi.material_override = _blood()
	mi.visibility_range_end = 60.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_parent().add_child(mi)
	mi.global_position = Vector3(at.x, _ground_y(Vector3(at.x, 0.0, at.y)) + 0.012, at.y)
	_drops.append({"node": mi, "until": int(drop["until"]), "life": maxi(1, int(drop["until"]) - Time.get_ticks_msec())})


## 핏자국 하나: 고르지 않은 웅덩이(가장자리는 옅고 가운데는 검붉게) · 둘레에 튄 방울 · 걸어온 쪽으로 끌린 자국.
static func blood_mesh(seed_value: int, dir: Vector2) -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: SurfaceTool = ClayMesh.begin()
	var fwd: Vector3 = Vector3(dir.x, 0.0, dir.y)
	var side: Vector3 = Vector3(-dir.y, 0.0, dir.x)
	var dark: Color = Color("#1E0202")
	var wet: Color = Color("#3A0504")
	var thin: Color = Color("#561008")
	# 웅덩이 (울퉁불퉁한 납작한 덩어리 둘을 겹친다).
	var r: float = rng.randf_range(0.16, 0.26)
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(r * 1.25, 0.002, r), thin, 16, 2, Basis(Vector3.UP, rng.randf() * TAU), ClayMesh.blob_wobble(seed_value, 0.28, 5))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.003, 0.0), Vector3(r * 0.8, 0.002, r * 0.62), wet, 14, 2, Basis(Vector3.UP, rng.randf() * TAU), ClayMesh.blob_wobble(seed_value + 7, 0.22, 4))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.006, 0.0), Vector3(r * 0.35, 0.002, r * 0.3), dark, 10, 2, Basis(Vector3.UP, rng.randf() * TAU), ClayMesh.blob_wobble(seed_value + 13, 0.2, 3))
	# 걸어온 반대쪽으로 끌린 자국 (가늘어지는 줄 두셋).
	for k: int in rng.randi_range(1, 2):
		var off: float = rng.randf_range(-r * 0.4, r * 0.4)
		var length: float = rng.randf_range(0.08, 0.22)
		var from: Vector3 = side * off - fwd * r * 0.3
		var to: Vector3 = from - fwd * length + side * rng.randf_range(-0.06, 0.06)
		ClayMesh.add_rod(st, from + Vector3(0.0, 0.004, 0.0), to + Vector3(0.0, 0.004, 0.0), rng.randf_range(0.025, 0.045), 0.006, wet, 5)
	# 튄 방울 (진행 방향 쪽으로 더 멀리, 작을수록 멀리).
	for k: int in rng.randi_range(5, 9):
		var a: float = rng.randf_range(-1.2, 1.2)
		var d: float = rng.randf_range(r * 1.1, r * 2.6)
		var p: Vector3 = (fwd * cos(a) + side * sin(a)) * d
		var s: float = rng.randf_range(0.012, 0.04) * (1.4 - d / (r * 2.6))
		ClayMesh.add_ellipsoid(st, p + Vector3(0.0, 0.004, 0.0), Vector3(s * 1.4, 0.003, s), wet if rng.randf() < 0.6 else thin, 8, 2, Basis(Vector3.UP, atan2(p.x, p.z)))
	return ClayMesh.commit(st)


## 젖은 피: 정점 색 + 번들거림 (거칠기 낮게).
static func _blood() -> StandardMaterial3D:
	if _blood_material == null:
		_blood_material = StandardMaterial3D.new()
		_blood_material.vertex_color_use_as_albedo = true
		_blood_material.vertex_color_is_srgb = true
		_blood_material.roughness = 0.38
		_blood_material.metallic_specular = 0.35
	return _blood_material


func _ground_y(at: Vector3) -> float:
	if not is_inside_tree() or player == null:
		return 0.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, player.global_position.y + 2.0, at.z), Vector3(at.x, player.global_position.y - 3.0, at.z))
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0


## 핏자국은 시간이 지나면 작아져 사라진다.
func _update_scent() -> void:
	if _drops.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	for i: int in range(_drops.size() - 1, -1, -1):
		var d: Dictionary = _drops[i]
		var mi: MeshInstance3D = d["node"]
		var left: float = float(int(d["until"]) - now_ms) / float(d["life"])
		if left <= 0.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_drops.remove_at(i)
			continue
		# 거의 마를 때까지 그대로 있다가 마지막에 스며든다.
		var k: float = clampf(left * 4.0, 0.0, 1.0)
		mi.scale = Vector3(lerpf(0.55, 1.0, k), 1.0, lerpf(0.55, 1.0, k))
		mi.visible = left > 0.02


# ---- 판자 대는 중 · 소리 · 잠 · 집 안 알림 (v0.25) ----

func _update_jobs() -> void:
	if _job_panel == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	var mine: Dictionary = {}
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	var swing: bool = Time.get_ticks_msec() / 1000.0 >= _hammer_at
	if swing:
		_hammer_at = Time.get_ticks_msec() / 1000.0 + 0.55
	for key: String in Net.board_jobs:
		var j: Dictionary = Net.board_jobs[key]
		var helpers: Array = j["helpers"]
		if helpers.has(Net.my_id):
			mine = j
		if swing and replicator != null:
			for r: RemotePlayer in replicator.remote_nodes():
				if helpers.has(r.player_id):
					r.play_action("chop")
	_job_panel.visible = not mine.is_empty()
	if mine.is_empty():
		return
	var n: int = (mine["helpers"] as Array).size()
	var progress: float = float(mine["progress"]) + float(now_ms - int(mine["at"])) * n
	_job_bar.value = clampf(progress / maxf(1.0, float(mine["need"])), 0.0, 1.0) * 100.0
	_job_label.text = "판자 대는 중…" + (" 둘이서 ×%d 빨라요" % n if n > 1 else " (곁에 있어 주세요)")
	if swing and player != null:
		player.play_chop()
		Audio.play_sfx("chop", -12.0, 0.9)


func _on_noise(info: Dictionary) -> void:
	if player != null:
		Puff.burst(player.get_parent(), player.global_position + Vector3(0.0, 0.1, 0.0), Color(0.8, 0.78, 0.72, 0.7), 10, 1.4, 0.15, 0.08, 0.6)
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if toast_hud != null and int(info.get("n", 0)) > 0 and now_s - _noise_tip_at > 20.0:
		_noise_tip_at = now_s
		var what: String = {"swing": "휘두르는", "run": "뛰는", "board": "망치질"}.get(str(info.get("k", "")), "")
		toast_hud.show_toast("%s 소리를 듣고 크리처 %d마리가 다가와요!" % [what, int(info.get("n", 0))], false)


func _on_sleep_changed(id: int) -> void:
	if id != Net.my_id:
		return
	var on: bool = Net.sleeping.has(id)
	if player != null:
		player.set_input_lock(SLEEP_LOCK, on)
		if on:
			player.velocity = Vector3.ZERO
			# 침대 위에 길게 눕는다 (머리는 베개 쪽).
			var h: SurvivalRules.House = GameData.survival.house_at(player.global_position)
			if h != null:
				player.global_position = Vector3(h.bed_position.x, player.global_position.y, h.bed_position.z)
				# 옆으로 눕히면(DOWN_ROLL) 머리가 몸의 −x 쪽 → 그쪽이 집의 −z (베개) 를 보게.
				var yaw: float = h.yaw - PI * 0.5
				player.look_toward(Vector3(-sin(yaw), 0.0, -cos(yaw)))
				player.body.rotation.y = yaw
	if _sleep_panel != null:
		_sleep_panel.visible = on
	if toast_hud != null and not on and Net.hp >= Net.max_hp:
		toast_hud.show_toast("푹 잤어요! 체력이 가득해요", true)


func _update_chip() -> void:
	if _chip == null or player == null:
		return
	_blood_chip.visible = Net.bleeding.has(Net.my_id) and Net.state == Net.State.ONLINE
	var h: SurvivalRules.House = GameData.survival.house_at(player.global_position)
	_chip.visible = h != null and Net.state == Net.State.ONLINE
	if h != null:
		_chip.text = "거점 · 안전해요" if HouseField.is_base(h) else "빈집 · %s" % _boarded_text(h)
		_chip.add_theme_color_override("font_color", Color("#FFE9A8") if HouseField.is_base(h) else Color("#F4E8D8"))


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
		_pose(player.body, Net.is_downed(Net.my_id) or Net.sleeping.has(Net.my_id), player.body_rest_height(), delta, BED_LIFT if Net.sleeping.has(Net.my_id) else 0.0)
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if replicator != null:
		for r: RemotePlayer in replicator.remote_nodes():
			if r.body != null:
				_pose(r.body, Net.is_downed(r.player_id) or Net.sleeping.has(r.player_id), 0.8, delta, BED_LIFT if Net.sleeping.has(r.player_id) else 0.0)
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


func _pose(body: Node3D, down: bool, rest: float, delta: float, lift: float = 0.0) -> void:
	var goal: float = DOWN_ROLL if down else 0.0
	if is_equal_approx(body.rotation.z, goal) and not down:
		return
	body.rotation.z = move_toward(body.rotation.z, goal, delta * 4.0)
	body.position.y = rest + (lift - DOWN_DROP) * (body.rotation.z / DOWN_ROLL)


func _build_hud() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "HurtVignette"
	_vignette.color = Color(0.7, 0.0, 0.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt = HurtOverlay.new()
	edge_hint = CreatureEdgeHint.new()
	edge_hint.player = player
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
	# 판자 대는 중 막대.
	_job_panel = _bottom_panel("BoardJobPanel", -560.0, -440.0)
	var job_box: VBoxContainer = VBoxContainer.new()
	_job_panel.add_child(job_box)
	_job_label = Label.new()
	_job_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_job_label.add_theme_font_size_override("font_size", 30)
	_job_label.add_theme_color_override("font_color", Color("#FFF4E0"))
	job_box.add_child(_job_label)
	_job_bar = ProgressBar.new()
	_job_bar.name = "BoardJobBar"
	_job_bar.custom_minimum_size = Vector2(0.0, 28.0)
	_job_bar.show_percentage = false
	job_box.add_child(_job_bar)
	# 자는 중.
	_sleep_panel = _bottom_panel("SleepPanel", -600.0, -420.0)
	var sleep_box: VBoxContainer = VBoxContainer.new()
	sleep_box.add_theme_constant_override("separation", 14)
	_sleep_panel.add_child(sleep_box)
	var sleep_label: Label = Label.new()
	sleep_label.text = "쿨쿨… 자는 동안 체력이 빨리 차요"
	sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleep_label.add_theme_font_size_override("font_size", 32)
	sleep_label.add_theme_color_override("font_color", Color("#E8EEFF"))
	sleep_box.add_child(sleep_label)
	var wake_button: Button = Button.new()
	wake_button.name = "WakeButton"
	wake_button.text = "일어나기"
	wake_button.custom_minimum_size = Vector2(0.0, 92.0)
	wake_button.add_theme_font_size_override("font_size", 32)
	wake_button.pressed.connect(func() -> void: Net.sleep_in_bed(false))
	sleep_box.add_child(wake_button)
	# 집 안 알림 (하트 아래).
	_chip = Label.new()
	_chip.name = "HouseChip"
	_chip.position = Vector2(28.0, 318.0)
	_chip.add_theme_font_size_override("font_size", 28)
	_chip.add_theme_constant_override("outline_size", 8)
	_chip.add_theme_color_override("font_outline_color", Color("#3A2A20"))
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.visible = false
	_blood_chip = Label.new()
	_blood_chip.name = "BloodChip"
	_blood_chip.text = "피 냄새 · 붕대로 멈춰요"
	_blood_chip.position = Vector2(28.0, 356.0)
	_blood_chip.add_theme_font_size_override("font_size", 28)
	_blood_chip.add_theme_constant_override("outline_size", 8)
	_blood_chip.add_theme_color_override("font_outline_color", Color("#3A1010"))
	_blood_chip.add_theme_color_override("font_color", Color("#FF7A6A"))
	_blood_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_chip.visible = false
	_supply_chip = HBoxContainer.new()
	_supply_chip.name = "SupplyChip"
	_supply_chip.position = Vector2(28.0, 400.0)
	_supply_chip.add_theme_constant_override("separation", 10)
	_supply_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_supply_chip.visible = false
	_supply_arrow = _chip_label("▲", 40, Color("#FF6A4A"))
	_supply_arrow.custom_minimum_size = Vector2(44.0, 44.0)
	_supply_arrow.pivot_offset = Vector2(22.0, 22.0)
	_supply_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_supply_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_supply_chip.add_child(_supply_arrow)
	_supply_label = _chip_label("보급 상자", 30, Color("#FFD9A0"))
	_supply_label.name = "SupplyLabel"
	_supply_chip.add_child(_supply_label)
	stash_window = StashWindow.new()
	if hud != null:
		hud.add_child.call_deferred(edge_hint)
		hud.move_child.call_deferred(edge_hint, 0)
		hud.add_child.call_deferred(_vignette)
		hud.add_child.call_deferred(_hurt)
		hud.add_child.call_deferred(_hearts)
		hud.add_child.call_deferred(_down_panel)
		hud.add_child.call_deferred(_job_panel)
		hud.add_child.call_deferred(_sleep_panel)
		hud.add_child.call_deferred(_chip)
		hud.add_child.call_deferred(_blood_chip)
		hud.add_child.call_deferred(_supply_chip)
		hud.add_child.call_deferred(stash_window)
	_refresh_hearts()


func _bottom_panel(node_name: String, top: float, bottom: float) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.14, 0.8)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -400.0
	panel.offset_right = 400.0
	panel.offset_top = top
	panel.offset_bottom = bottom
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.visible = false
	return panel


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


# ---- v0.27 보급 상자 ----

func _chip_label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color("#2A1A10"))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 가장 가까운 상자 쪽 화살표 (카메라 기준 — 위가 화면 안쪽) · 거리.
func _update_supply_chip() -> void:
	if _supply_chip == null or player == null:
		return
	var sid: String = supply.nearest(player.global_position) if supply != null and Net.state == Net.State.ONLINE else ""
	_supply_chip.visible = not sid.is_empty()
	if sid.is_empty():
		return
	var at: Vector3 = supply.crate_position(sid)
	var to: Vector3 = at - player.global_position
	to.y = 0.0
	var cam: Camera3D = get_viewport().get_camera_3d()
	var fwd: Vector3 = -cam.global_basis.z if cam != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
	_supply_arrow.rotation = atan2(to.dot(right), to.dot(fwd))
	var falling: bool = Time.get_ticks_msec() < int(Net.supply[sid]["land"])
	_supply_label.text = "보급 상자 %dm%s" % [roundi(to.length()), " · 떨어지는 중" if falling else ""]


func _on_supply_changed(id: String) -> void:
	if toast_hud == null or not Net.supply.has(id) or Time.get_ticks_msec() >= int(Net.supply[id]["land"]):
		return
	# 새로 떨어지는 상자.
	var d: float = Vector2(float(Net.supply[id]["x"]) - player.global_position.x, float(Net.supply[id]["z"]) - player.global_position.z).length()
	toast_hud.show_toast("보급 상자가 떨어져요! %dm · 먼저 열면 내 것" % roundi(d), true)
	Audio.play_sfx("quest_done", -8.0, 0.7)
	Prefs.vibrate(60, 0.4)


func _on_supply_taken(_id: String, by: int) -> void:
	if toast_hud == null or by == Net.my_id:
		return
	if by == 0:
		toast_hud.show_toast("해가 떠서 남은 보급 상자를 헬기가 거둬 갔어요", false)
	else:
		toast_hud.show_toast("%s 님이 보급 상자를 열었어요" % GameData.player_name(by), true)


func _on_supply_got(info: Dictionary) -> void:
	if toast_hud == null:
		return
	var parts: PackedStringArray = []
	for it: Variant in info.get("items", []):
		parts.append("%s ×%d" % [GameData.item_name(str(it.get("id", ""))), int(it.get("n", 1))])
	toast_hud.show_toast("보급 상자를 열었어요! %s" % " · ".join(parts), true)
	Audio.play_sfx("quest_done", -6.0)


## 달리는 중인지 (조이스틱을 끝까지 밀어 달리기 · 실제로 움직이는 중).
func _is_running() -> bool:
	return player != null and player.running and Vector2(player.velocity.x, player.velocity.z).length() > 3.0


# ---- v0.28.2 주민이 크리처에게 ----

func _on_npc_hurt(info: Dictionary) -> void:
	if toast_hud == null:
		return
	var who: NpcInfo = GameData.npcs.get(str(info.get("id", "")))
	var name_text: String = who.display_name if who != null else "주민"
	match str(info.get("t", "")):
		"npc_down":
			toast_hud.show_toast("%s 님이 크리처에게 쓰러졌어요!" % name_text, false)
		"npc_up":
			toast_hud.show_toast("%s 님이 다시 일어났어요" % name_text, true)
