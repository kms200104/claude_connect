class_name FishingController
extends Node
## 낚시 한 판의 클라이언트 쪽 진행. 판정은 전부 서버가 하고, 여기서는 연출과 입력만 맡는다.
##   던지기 요청 → (대기: 물고기 그림자가 다가옴, 가짜 입질…) → 진짜 입질(강한 진동 + 찌가 쑥) → 챔질 요청(반응 시간 보고)
##   → 끌어올리기 연타(v0.11, 정해진 시간 안에 정해진 횟수) → 서버가 확정한 결과

enum Phase { IDLE, CASTING, WAITING, BITE, REEL, RESULT }

@export_group("References")
@export var player: Player
## 기본 낚시터. 마을에 낚시터가 여럿이면(FishingSpot 이 "fishing_spots" 무리에 든다) 가장 가까운 곳에서 던진다.
@export var spot: FishingSpot
@export var bobber: Bobber
@export var hud: FishingHud
## 주민·나무가 가까이 있으면 그쪽 버튼이 우선이라 낚시 버튼을 숨긴다 (없어도 된다).
@export var interaction: InteractionController
## 낚으면 카메라가 다가가 물고기를 든 캐릭터를 비추고, 자랑 카드를 띄운다 (없어도 된다).
@export var camera_rig: FollowCamera
@export var catch_card: CatchCard

@export_group("Feel")
## 캐릭터 앞쪽 몇 미터에 찌를 던질지 (수역 안쪽으로 잘라 쓴다).
@export_range(1.0, 8.0, 0.1, "suffix:m") var cast_distance: float = 2.8
## 던지는 동작에서 낚싯대를 놓는 순간 (이때 찌가 날아가기 시작한다).
@export_range(0.0, 1.0, 0.01, "suffix:s") var release_delay: float = 0.24
## 찌가 날아가는 시간 (물에 닿을 때 퐁당 소리).
@export_range(0.1, 2.0, 0.05, "suffix:s") var flight_time: float = 0.55
## 결과를 보여 주고 다시 움직일 수 있게 되기까지의 시간.
@export_range(0.2, 5.0, 0.1, "suffix:s") var result_hold: float = 1.6
## 낚은 물고기를 두 손으로 내밀고 자랑하는 시간 (희귀할수록 조금 더 길게).
@export_range(0.5, 8.0, 0.1, "suffix:s") var show_off_time: float = 3.2
@export var vibrate_on_bite: bool = true
## 진동 (ms, 세기 0~1): 그림자가 찌를 건드림 · 물고 들어감 · 연타 한 번.
@export var nibble_vibration: Vector2 = Vector2(45.0, 0.35)
@export var bite_vibration: Vector2 = Vector2(320.0, 1.0)
@export var tap_vibration: Vector2 = Vector2(18.0, 0.5)

var phase: Phase = Phase.IDLE

var _bite_shown_ms: float = 0.0
var _hooked: bool = false
var _cast_pressed_ms: int = 0
var _shadow_size: float = 1.0
var _shadow: FishShadow = null
var _bite_window_ms: int = 0
var _reel_need: int = 0
var _reel_ms: int = 0
var _reel_shown_ms: float = 0.0
var _reel_taps: PackedFloat32Array = PackedFloat32Array()
var _reel_sent: bool = false


func _ready() -> void:
	hud.action_pressed.connect(_on_action_pressed)
	bobber.landed.connect(_on_bobber_landed)
	hud.cancel_pressed.connect(Net.cancel_fishing)
	Net.fish_started.connect(_on_started)
	Net.fish_nibble.connect(_on_nibble)
	Net.fish_bite.connect(_on_bite)
	Net.fish_reel.connect(_on_reel)
	_shadow = FishShadow.new()
	_shadow.name = "FishShadow"
	_shadow.touched.connect(_on_shadow_touched)
	add_child.call_deferred(_shadow)
	Net.fish_result.connect(_on_result)
	Net.action_rejected.connect(_on_rejected)
	Net.state_changed.connect(_on_net_state_changed)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _reset())


func _process(_delta: float) -> void:
	if phase == Phase.REEL and not _reel_sent:
		var left: float = _reel_ms - (Time.get_ticks_msec() - _reel_shown_ms)
		hud.update_reel(_reel_taps.size(), _reel_need, left / maxf(_reel_ms, 1.0))
		if left <= 0.0:
			_send_reel()
	if phase == Phase.IDLE:
		# 낚싯대를 손에 들고 물가에 있어야 던질 수 있다.
		spot = _nearest_spot(player.global_position)
		var ready_to_cast: bool = Net.state == Net.State.ONLINE and spot != null and spot.can_cast_from(player.global_position) \
			and not player.is_input_locked() and player.held_item == "rod" \
			and (interaction == null or not interaction.has_target())
		hud.show_cast_available(ready_to_cast)


## 가장 가까운 낚시터 (마을 호수 · 성성호수 …).
func _nearest_spot(position: Vector3) -> FishingSpot:
	var best: FishingSpot = spot
	var best_d: float = INF if spot == null or spot.info == null else spot.info.distance_to(position)
	for node: Node in get_tree().get_nodes_in_group(&"fishing_spots"):
		var s: FishingSpot = node as FishingSpot
		if s == null or s.info == null:
			continue
		var d: float = s.info.distance_to(position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _on_action_pressed() -> void:
	match phase:
		Phase.IDLE:
			phase = Phase.CASTING
			hud.show_casting()
			# 낚싯대를 머리 뒤로 젖혔다가 휙 던진다. 휙 소리는 앞으로 내던지는 순간에 맞춘다.
			_cast_pressed_ms = Time.get_ticks_msec()
			player.play_cast()
			_play_cast_whoosh()
			Net.cast_fishing(spot.spot_id)
		Phase.WAITING:
			# 입질 전에 당기면 서버가 early 로 실패 처리한다.
			Net.hook_fishing(0.0)
		Phase.BITE:
			if not _hooked:
				_hooked = true
				# 입질 연출이 보인 시점부터 누른 시점까지 — 네트워크 지연이 섞이지 않는 값.
				# 찌가 잠기기 전에 누르면 반응 0 → 서버가 '너무 일찍'으로 처리한다.
				Net.hook_fishing(0.0 if _bite_shown_ms < 0.0 else Time.get_ticks_msec() - _bite_shown_ms)
				hud.show_hooked()
				Audio.play_sfx("fish_reel", -3.0)
		Phase.REEL:
			_reel_tap()


func _on_started(shadow: float = 1.0) -> void:
	phase = Phase.WAITING
	_hooked = false
	_shadow_size = shadow
	player.set_input_lock(&"fishing", true)
	var forward: Vector3 = -player.body.global_basis.z
	forward.y = 0.0
	var target: Vector3 = spot.info.clamp_inside(player.global_position + forward.normalized() * cast_distance)
	target.y = spot.water_height + 0.02
	player.look_toward(target - player.global_position)
	player.set_fishing_pose(true)
	hud.show_waiting()
	# 던지는 동작에서 낚싯대를 놓는 순간까지 기다렸다가 찌를 날린다 (서버 답이 늦게 오면 바로).
	var wait_s: float = release_delay - float(Time.get_ticks_msec() - _cast_pressed_ms) / 1000.0
	if wait_s > 0.0:
		await get_tree().create_timer(wait_s).timeout
	if phase != Phase.WAITING and phase != Phase.BITE:
		return
	Audio.play_sfx("line_zip", -6.0, 1.0, 0.05)
	bobber.cast_to(player.rod_tip(), target, flight_time)


func _play_cast_whoosh() -> void:
	await get_tree().create_timer(maxf(release_delay - 0.12, 0.0)).timeout
	Audio.play_sfx("fish_cast", 0.0, 1.0, 0.05)


## 찌가 물에 닿았다: 퐁당. 곧 물 밑에서 물고기 그림자가 다가온다 (희귀할수록 크다).
func _on_bobber_landed(landed_at: Vector3) -> void:
	Audio.play_sfx("fish_plop", 0.0, 1.0, 0.08)
	if phase == Phase.WAITING and _shadow != null:
		_shadow.appear(Vector3(landed_at.x, spot.water_height + 0.015, landed_at.z), _shadow_size)


## 가짜 입질: 그림자가 쏙 다가와 찌를 건드린다. 닿는 순간(_on_shadow_touched) 찌가 톡, 휴대폰이 살짝 떨린다.
func _on_nibble() -> void:
	if phase != Phase.WAITING:
		return
	if _shadow != null and _shadow.mode != FishShadow.Mode.HIDDEN:
		_shadow.nibble()
	else:
		_on_shadow_touched(false)


## 진짜 입질: 그림자가 확 달려들어 찌를 물고 들어간다. 닿는 순간 강한 진동과 함께 찌가 쑥 잠긴다.
func _on_bite(window_ms: int) -> void:
	if phase != Phase.WAITING:
		return
	phase = Phase.BITE
	_bite_window_ms = window_ms
	_bite_shown_ms = -1.0
	if _shadow != null and _shadow.mode != FishShadow.Mode.HIDDEN:
		_shadow.bite()
	else:
		_on_shadow_touched(true)


## 진짜 입질에서 찌가 잠기는 게 화면에 보였는가 (이때부터 챔질 반응 시간을 잰다).
func is_bite_visible() -> bool:
	return phase == Phase.BITE and _bite_shown_ms >= 0.0


func _on_shadow_touched(strong: bool) -> void:
	if not strong:
		if phase != Phase.WAITING:
			return
		bobber.nibble()
		Audio.play_at("fish_nibble", bobber.global_position, -4.0, 1.0, 0.15)
		hud.show_nibble()
		_vibrate(nibble_vibration)
		return
	if phase != Phase.BITE or _hooked:
		return
	# 반응 시간은 찌가 잠기는 게 보인 때부터 잰다.
	_bite_shown_ms = Time.get_ticks_msec()
	bobber.bite()
	Audio.play_at("fish_bite", bobber.global_position, 1.0)
	hud.show_bite(_bite_window_ms)
	_vibrate(bite_vibration)


## 챔질 성공 → 끌어올리기: 정해진 시간 안에 정해진 만큼 연타. 다 채우면 바로 서버에 보낸다.
func _on_reel(taps: int, ms: int) -> void:
	if phase != Phase.BITE:
		return
	phase = Phase.REEL
	_reel_need = taps
	_reel_ms = ms
	_reel_taps = PackedFloat32Array()
	_reel_sent = false
	_reel_shown_ms = Time.get_ticks_msec()
	bobber.struggle()
	if _shadow != null:
		_shadow.struggle()
	hud.show_reel(taps, ms)
	_vibrate(Vector2(90.0, 0.8))


func _reel_tap() -> void:
	if _reel_sent:
		return
	_reel_taps.append(Time.get_ticks_msec() - _reel_shown_ms)
	bobber.tug()
	_vibrate(tap_vibration)
	Audio.play_sfx("fish_reel", -8.0, 1.0 + 0.04 * _reel_taps.size(), 0.05)
	hud.update_reel(_reel_taps.size(), _reel_need, 1.0 - (Time.get_ticks_msec() - _reel_shown_ms) / maxf(_reel_ms, 1.0))
	if player.rig != null:
		player.rig.reel_tug()
	if _reel_taps.size() >= _reel_need:
		_send_reel()


func _send_reel() -> void:
	if _reel_sent:
		return
	_reel_sent = true
	hud.show_hooked()
	Net.reel_fishing(_reel_taps)


func _vibrate(v: Vector2) -> void:
	if vibrate_on_bite:
		Input.vibrate_handheld(int(v.x), v.y)


func _on_result(success: bool, fish_id: String, reason: String) -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.RESULT
	bobber.hide_bobber()
	if _shadow != null:
		if success:
			_shadow.hide_shadow()
		else:
			_shadow.leave()
	player.set_fishing_pose(false)
	if success and GameData.fish.has(fish_id):
		await _show_off(fish_id)
		return
	hud.show_result(_describe(success, fish_id, reason), success)
	Audio.play_sfx("fish_catch" if success else "fish_escape", -2.0, 1.0, 0.0)
	await get_tree().create_timer(result_hold).timeout
	if phase == Phase.RESULT:
		_reset()


## 낚았다! 카메라 쪽으로 돌아서서 물고기를 두 손으로 쭉 내밀어 들고, 카메라가 다가가고, 희귀도별 외침과 물고기 한마디.
func _show_off(fish_id: String) -> void:
	var fish: FishInfo = GameData.fish[fish_id]
	var shout: String = GameData.catch_shout(fish.rarity, fish.display_name)
	player.look_toward(Vector3.BACK)
	if player.rig != null:
		var size_scale: float = {"S": 0.75, "M": 1.0, "L": 1.25}.get(fish.size, 1.0)
		player.rig.show_off(FishModel.mesh(fish), size_scale)
	if camera_rig != null:
		camera_rig.set_focus(1.0, 0.7)
	# 외침은 자랑 카드에 크게 뜨니 낚시 토스트에는 겹쳐 띄우지 않는다.
	hud.show_result("" if catch_card != null else shout, true)
	if catch_card != null:
		catch_card.show_catch(fish_id, shout)
	match fish.rarity:
		"rare":
			Audio.play_sfx("fanfare_big", 0.0, 1.0, 0.0)
		"uncommon":
			Audio.play_sfx("fanfare_small", -1.0, 1.0, 0.0)
		_:
			Audio.play_sfx("fish_catch", -2.0, 1.0, 0.0)
	var hold: float = show_off_time + (1.0 if fish.rarity == "rare" else 0.0)
	var waited: float = 0.0
	# 카드를 누르면 바로 끝낸다.
	while waited < hold and phase == Phase.RESULT and (catch_card == null or catch_card.is_showing()):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_end_show_off()
	if phase == Phase.RESULT:
		_reset()


func _end_show_off() -> void:
	if player.rig != null and player.rig.is_showing_off():
		player.rig.show_off(null)
	if camera_rig != null and camera_rig.focus > 0.0:
		camera_rig.set_focus(0.0, 0.5)
	if catch_card != null:
		catch_card.hide_card()


func _on_rejected(code: String) -> void:
	if phase != Phase.CASTING:
		return
	phase = Phase.IDLE
	hud.reset()
	hud.show_toast(_describe_error(code), false)


func _on_net_state_changed(new_state: int) -> void:
	if new_state != Net.State.ONLINE:
		_reset()


func _reset() -> void:
	_end_show_off()
	phase = Phase.IDLE
	_hooked = false
	_reel_sent = false
	bobber.hide_bobber()
	if _shadow != null and _shadow.is_inside_tree():
		_shadow.hide_shadow()
	player.set_fishing_pose(false)
	player.clear_look_direction()
	player.set_input_lock(&"fishing", false)
	hud.reset()


func _describe(success: bool, fish_id: String, reason: String) -> String:
	if success:
		return "%s 낚았다!" % GameData.fish_name(fish_id)
	match reason:
		NetProtocol.FISH_EARLY:
			return "너무 일찍 당겼어요"
		NetProtocol.FISH_LATE:
			return "너무 늦었어요"
		NetProtocol.FISH_ESCAPED:
			return "물고기가 도망갔어요"
		NetProtocol.FISH_SNAPPED:
			return "힘이 모자라 놓쳤어요… 더 빨리 연타!"
		NetProtocol.FISH_MOVED:
			return "움직여서 낚시가 끊겼어요"
		NetProtocol.FISH_INVENTORY_FULL:
			return "가방이 가득 차서 놓쳤어요"
		_:
			return "낚시를 그만뒀어요"


func _describe_error(code: String) -> String:
	match code:
		NetProtocol.ERR_NOT_AT_SPOT:
			return "물가로 더 가까이 가야 해요"
		NetProtocol.ERR_INVENTORY_FULL:
			return "가방이 가득 찼어요"
		NetProtocol.ERR_ALREADY_FISHING:
			return "이미 낚시 중이에요"
		NetProtocol.ERR_NO_TOOL:
			return "낚싯대를 손에 들어야 해요"
		_:
			return "지금은 낚시할 수 없어요"
