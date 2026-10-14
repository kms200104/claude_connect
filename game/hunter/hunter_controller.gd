class_name HunterController
extends Node
## v0.28 헌터 (마을에 붙는 쪽): 동사무소 옆 헌터 협회 출장소(HunterOffice) · 창구 창(HunterWindow) ·
## 처치할 때 HUD 에 "+n점" 이 떴다 사라진다 · 마석 · 매각 · 등급 재심사 · 의뢰 · 길드 결과 안내.
## 상황 버튼 대상: "헌터 협회 창구" (출장소 앞). 판정은 서버 (Net.hunter_sell · hunter_rank_up · hunter_claim · guild_*).

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud

const TARGET_OFFICE: String = "office"

var office: HunterOffice = null
var window: HunterWindow = null
var _popup: Label = null
var _popup_t: float = 0.0


func _ready() -> void:
	var world: Node = player.get_parent() if player != null else self
	office = HunterOffice.new()
	world.add_child.call_deferred(office)
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
	if hud != null:
		hud.add_child.call_deferred(_popup)
		hud.add_child.call_deferred(window)
	Net.hunter_done.connect(_on_done)
	Net.guild_changed.connect(_on_guild)
	Net.request_failed.connect(_on_failed)


func _process(delta: float) -> void:
	if _popup != null and _popup.visible:
		_popup_t -= delta
		_popup.modulate.a = clampf(_popup_t / 0.6, 0.0, 1.0)
		_popup.position.y = 448.0 - (1.8 - maxf(_popup_t, 0.0)) * 14.0
		if _popup_t <= 0.0:
			_popup.visible = false


func is_busy() -> bool:
	return window != null and window.is_open()


## 상황 버튼 대상 (빈 글자 = 없음): 출장소 창구 앞.
func pick_target(pos: Vector3, margin: float = 0.3) -> String:
	if Net.state != Net.State.ONLINE:
		return ""
	var at: Vector3 = GameData.hunter.counter_position()
	if Vector2(at.x - pos.x, at.z - pos.z).length() <= GameData.hunter.office_range - margin:
		return TARGET_OFFICE
	return ""


func target_label(_target: String) -> String:
	return "헌터 협회 창구"


func activate(_target: String) -> void:
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
	if toast_hud == null or not (kind.begins_with("hunter_") or kind.begins_with("guild_")):
		return
	var text: String = ""
	match code:
		NetProtocol.ERR_NOT_AT_OFFICE:
			text = "헌터 협회 출장소 창구에서 해요 (동사무소 옆)"
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
		_:
			text = "지금은 할 수 없어요"
	toast_hud.show_toast(text, false)
