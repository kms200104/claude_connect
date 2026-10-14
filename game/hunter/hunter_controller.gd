class_name HunterController
extends Node
## v0.28 헌터 (마을에 붙는 쪽): 동사무소 옆 헌터 협회 출장소(HunterOffice) · 창구 창(HunterWindow) ·
## 처치할 때 HUD 에 "+n점" 이 떴다 사라진다 · 마석 · 매각 · 등급 재심사 · 의뢰 · 길드 결과 안내.
## 상황 버튼 대상: "헌터 협회 창구" (출장소 앞). 판정은 서버 (Net.hunter_sell · hunter_rank_up · hunter_claim · guild_*).
## 게이트 (GateField): 곁에서 "게이트 진입 · E급", HUD 에 가장 가까운 게이트 방향 화살표 · 거리 · 남은 시간 (공략 중이면 웨이브 · 남은 크리처),
## 열림 · 브레이크는 재난문자로 온다 (SafetyController), 공략 보상 안내.

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud

const TARGET_OFFICE: String = "office"
const TARGET_GATE: String = "gate:"

var office: HunterOffice = null
var window: HunterWindow = null
var gates: GateField = null
var _gate_chip: HBoxContainer = null
var _gate_arrow: Label = null
var _gate_label: Label = null
var _popup: Label = null
var _popup_t: float = 0.0


func _ready() -> void:
	var world: Node = player.get_parent() if player != null else self
	office = HunterOffice.new()
	world.add_child.call_deferred(office)
	gates = GateField.new()
	world.add_child.call_deferred(gates)
	window = HunterWindow.new()
	_popup = Label.new()
	_popup.name = "HunterPoints"
	_popup.position = Vector2(28.0, 448.0)
	_popup.add_theme_font_size_override("font_size", 30)
	_popup.add_theme_constant_override("outline_size", 8)
	_popup.add_theme_color_override("font_outline_color", Color("#1E2A42"))
	_popup.add_theme_color_override("font_color", Color("#E8C23A"))
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.visible = false
	_build_gate_chip()
	if hud != null:
		hud.add_child.call_deferred(_popup)
		hud.add_child.call_deferred(_gate_chip)
		hud.add_child.call_deferred(window)
	Net.hunter_done.connect(_on_done)
	Net.guild_changed.connect(_on_guild)
	Net.request_failed.connect(_on_failed)
	Net.gate_entered.connect(_on_gate_entered)
	Net.gate_cleared.connect(_on_gate_cleared)
	Net.gate_changed.connect(_on_gate_changed)


func _process(delta: float) -> void:
	if _popup != null and _popup.visible:
		_popup_t -= delta
		_popup.modulate.a = clampf(_popup_t / 0.6, 0.0, 1.0)
		_popup.position.y = 448.0 - (1.8 - maxf(_popup_t, 0.0)) * 14.0
		if _popup_t <= 0.0:
			_popup.visible = false
	_update_gate_chip()


func is_busy() -> bool:
	return window != null and window.is_open()


## 상황 버튼 대상 (빈 글자 = 없음): 출장소 창구 앞.
func pick_target(pos: Vector3, margin: float = 0.3) -> String:
	if Net.state != Net.State.ONLINE:
		return ""
	var at: Vector3 = GameData.hunter.counter_position()
	if Vector2(at.x - pos.x, at.z - pos.z).length() <= GameData.hunter.office_range - margin:
		return TARGET_OFFICE
	# 게이트 곁 (아직 진입하지 않았고, 브레이크가 아닐 때).
	for id: String in Net.gates:
		var g: Dictionary = Net.gates[id]
		if str(g["st"]) == "break" or (g["raiders"] as Array).has(Net.my_id):
			continue
		if Vector2(float(g["x"]) - pos.x, float(g["z"]) - pos.z).length() <= GameData.hunter.gate_enter_range - margin:
			return TARGET_GATE + id
	return ""


func target_label(target: String) -> String:
	if target.begins_with(TARGET_GATE):
		var g: Dictionary = Net.gates.get(target.trim_prefix(TARGET_GATE), {})
		var rank: String = str(g.get("rank", "E"))
		return "게이트 진입 · %s급%s" % [rank, " (함께 공략)" if str(g.get("st", "")) == "raid" else ""]
	return "헌터 협회 창구"


func activate(target: String) -> void:
	if target.begins_with(TARGET_GATE):
		var gid: String = target.trim_prefix(TARGET_GATE)
		var g: Dictionary = Net.gates.get(gid, {})
		if not GameData.hunter.can_enter(str(Net.hunter.get("rank", "E")), str(g.get("rank", "E"))):
			if toast_hud != null:
				toast_hud.show_toast("%s급 게이트는 %s급 이상 헌터만 들어갈 수 있어요" % [str(g.get("rank", "")), GameData.hunter.ranks[maxi(0, GameData.hunter.rank(str(g.get("rank", "E"))).index - 1)].id], false)
			return
		Audio.play_sfx("twinkle", -4.0, 0.6)
		Net.gate_enter(gid)
		return
	if player != null:
		player.look_toward(GameData.hunter.office_position - player.global_position)
	Audio.play_ui(Audio.SFX_CLICK)
	window.open()


func _show_points(text: String) -> void:
	if _popup == null:
		return
	_popup.text = text
	_popup.visible = true
	_popup_t = 1.8
	_popup.modulate.a = 1.0


func _on_done(info: Dictionary) -> void:
	match str(info.get("kind", "")):
		"kill":
			var mana: Array = info.get("mana", [])
			var extra: String = ""
			if not mana.is_empty():
				extra = " · %s" % GameData.item_name(str((mana[0] as Dictionary).get("id", "")))
			_show_points("헌터 점수 +%d%s" % [int(info.get("pts", 0)), extra])
		"sell":
			if toast_hud != null:
				var n: int = 0
				for s: Variant in info.get("sold", []):
					n += int((s as Dictionary).get("n", 0))
				toast_hud.show_toast("마석 %d개를 팔았어요 %s%s" % [n, Money.delta(int(info.get("amount", 0))), " (+%d점)" % int(info.get("pts", 0)) if int(info.get("pts", 0)) > 0 else ""], true)
			Audio.play_sfx("coin", -6.0)
		"rank":
			var r: HunterRules.Rank = GameData.hunter.rank(str(info.get("rank", "E")))
			if toast_hud != null:
				toast_hud.show_toast("재심사 통과! %s 헌터가 됐어요 — 마석을 %d%% 더 받아요" % [r.name, roundi(r.sell_bonus * 100.0)], true)
			Audio.play_sfx("level_up", -2.0)
			Prefs.vibrate(120, 0.6)
		"claim":
			if toast_hud != null:
				toast_hud.show_toast("의뢰 완료 보고! %s · 헌터 점수 +%d" % [Money.delta(int(info.get("reward", 0))), int(info.get("pts", 0))], true)
			Audio.play_sfx("quest_done", -6.0)
		"remote_rank":
			if toast_hud != null and int(info.get("id", 0)) != Net.my_id:
				toast_hud.show_toast("%s 님이 %s급 헌터가 됐어요!" % [GameData.player_name(int(info.get("id", 0))), str(info.get("rank", ""))], true)


func _on_guild(msg: Dictionary) -> void:
	if toast_hud == null:
		return
	var by: int = int(msg.get("by", 0))
	var g: Dictionary = msg.get("g", {}) if msg.get("g") is Dictionary else {}
	match str(msg.get("op", "")):
		"create":
			toast_hud.show_toast("길드 '%s' 를 만들었어요" % str(g.get("name", "")) if by == Net.my_id else "%s 님이 길드 '%s' 를 만들었어요 — 헌터넷에서 가입해요" % [GameData.player_name(by), str(g.get("name", ""))], true)
		"join":
			toast_hud.show_toast("길드 '%s' 에 들어왔어요! 함께 사냥하면 점수가 25%% 더" % str(g.get("name", "")) if by == Net.my_id else "%s 님이 길드에 들어왔어요" % GameData.player_name(by), true)
		"leave":
			toast_hud.show_toast("길드에서 나왔어요" if by == Net.my_id else "%s 님이 길드에서 나갔어요" % GameData.player_name(by), false)
	if bool(msg.get("up", false)):
		toast_hud.show_toast("길드가 %s 로 올랐어요!" % str(g.get("title", "")), true)


func _on_failed(kind: String, code: String) -> void:
	if toast_hud == null or not (kind.begins_with("hunter_") or kind.begins_with("guild_") or kind == "gate_enter"):
		return
	var text: String = ""
	match code:
		NetProtocol.ERR_NOT_AT_OFFICE:
			text = "헌터 협회 출장소 창구에서 해요 (동사무소 대피소 앞)"
		NetProtocol.ERR_RANK_NOT_READY:
			text = "아직 재심사 점수가 모자라요"
		NetProtocol.ERR_BOUNTY_NOT_DONE:
			text = "의뢰를 아직 다 채우지 않았어요"
		NetProtocol.ERR_BAD_GUILD_NAME:
			text = "길드 이름은 %d~%d글자예요" % [GameData.hunter.guild_name_min, GameData.hunter.guild_name_max]
		NetProtocol.ERR_GUILD_EXISTS:
			text = "이 마을에는 이미 길드가 있어요"
		NetProtocol.ERR_NO_GUILD:
			text = "길드가 없어요"
		NetProtocol.ERR_GUILD_FULL:
			text = "길드원이 다 찼어요"
		NetProtocol.ERR_ALREADY_LOOTED:
			text = "이미 보고한 의뢰예요"
		NetProtocol.ERR_RANK_TOO_LOW:
			text = "헌터 등급이 모자라요 — 협회 창구에서 재심사를 받아요"
		NetProtocol.ERR_GATE_BROKEN:
			text = "던전 브레이크 중이에요! 들어갈 수 없어요"
		NetProtocol.ERR_NO_GATE:
			text = "게이트가 닫혔어요"
		NetProtocol.ERR_TOO_FAR:
			text = "게이트에 조금 더 가까이 가요"
		_:
			text = "지금은 할 수 없어요"
	toast_hud.show_toast(text, false)


# ---- v0.28 게이트 ----

func _build_gate_chip() -> void:
	_gate_chip = HBoxContainer.new()
	_gate_chip.name = "GateChip"
	_gate_chip.position = Vector2(28.0, 496.0)
	_gate_chip.add_theme_constant_override("separation", 10)
	_gate_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate_chip.visible = false
	_gate_arrow = Label.new()
	_gate_arrow.text = "▲"
	_gate_arrow.custom_minimum_size = Vector2(44.0, 44.0)
	_gate_arrow.pivot_offset = Vector2(22.0, 22.0)
	_gate_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gate_arrow.add_theme_font_size_override("font_size", 40)
	_gate_arrow.add_theme_constant_override("outline_size", 8)
	_gate_arrow.add_theme_color_override("font_outline_color", Color("#10101A"))
	_gate_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate_chip.add_child(_gate_arrow)
	_gate_label = Label.new()
	_gate_label.name = "GateLabel"
	_gate_label.add_theme_font_size_override("font_size", 28)
	_gate_label.add_theme_constant_override("outline_size", 8)
	_gate_label.add_theme_color_override("font_outline_color", Color("#10101A"))
	_gate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate_chip.add_child(_gate_label)


## 가장 가까운 게이트: 카메라 기준 화살표 · 거리 · 남은 시간 (공략 중이면 웨이브 · 남은 크리처).
func _update_gate_chip() -> void:
	if _gate_chip == null or player == null:
		return
	var gid: String = gates.nearest(player.global_position) if gates != null and Net.state == Net.State.ONLINE else ""
	_gate_chip.visible = not gid.is_empty()
	if gid.is_empty():
		return
	var g: Dictionary = Net.gates[gid]
	var to: Vector3 = Vector3(float(g["x"]), 0.0, float(g["z"])) - player.global_position
	to.y = 0.0
	var cam: Camera3D = get_viewport().get_camera_3d()
	var fwd: Vector3 = -cam.global_basis.z if cam != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	_gate_arrow.rotation = atan2(to.dot(Vector3(-fwd.z, 0.0, fwd.x)), to.dot(fwd))
	var color: Color = Color("#FF5A4A") if str(g["st"]) == "break" else GameData.hunter.gate_colors.get(str(g["rank"]), Color.WHITE).lightened(0.3)
	_gate_arrow.add_theme_color_override("font_color", color)
	_gate_label.add_theme_color_override("font_color", color)
	var left: int = maxi(0, int(g["until"]) - Time.get_ticks_msec())
	var time_text: String = "%d:%02d" % [left / 60000, (left / 1000) % 60]
	var d: int = roundi(to.length())
	match str(g["st"]):
		"raid":
			if (g["raiders"] as Array).has(Net.my_id):
				_gate_label.text = "%s급 게이트 공략 · %s · 남은 크리처 %d" % [str(g["rank"]), "우두머리!" if bool(g["boss"]) else "웨이브 %d/%d" % [int(g["wave"]) + 1, int(g["waves"])], int(g["alive"])]
			else:
				_gate_label.text = "%s급 게이트 · 공략 중 %dm" % [str(g["rank"]), d]
		"break":
			_gate_label.text = "던전 브레이크! %s · %dm" % [time_text, d]
		_:
			_gate_label.text = "%s급 게이트 %dm · 브레이크까지 %s" % [str(g["rank"]), d, time_text]


func _on_gate_entered(id: String) -> void:
	var g: Dictionary = Net.gates.get(id, {})
	if toast_hud != null:
		toast_hud.show_toast("%s급 게이트 진입! 크리처를 모두 쓰러뜨리면 우두머리가 나와요" % str(g.get("rank", "")), true)
	Prefs.vibrate(80, 0.5)


var _boss_seen: Dictionary[String, bool] = {}


func _on_gate_changed(id: String) -> void:
	var g: Dictionary = Net.gates.get(id, {})
	if g.is_empty():
		_boss_seen.erase(id)
		return
	if bool(g["boss"]) and not _boss_seen.has(id) and (g["raiders"] as Array).has(Net.my_id):
		_boss_seen[id] = true
		if toast_hud != null:
			toast_hud.show_toast("우두머리가 나타났어요!", false)
		Audio.play_sfx("fanfare_small", -6.0, 0.7)
		Prefs.vibrate(160, 0.7)


func _on_gate_cleared(info: Dictionary) -> void:
	if toast_hud == null:
		return
	var parts: PackedStringArray = []
	for it: Variant in info.get("items", []):
		parts.append("%s ×%d" % [GameData.item_name(str(it.get("id", ""))), int(it.get("n", 1))])
	toast_hud.show_toast("%s급 게이트 공략! %s · 헌터 점수 +%d · %s" % [str(info.get("rank", "")), Money.delta(int(info.get("sol", 0))), int(info.get("pts", 0)), " · ".join(parts)], true)
	Audio.play_sfx("fanfare_big", -4.0)
