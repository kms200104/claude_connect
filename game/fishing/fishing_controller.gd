class_name FishingController
extends Node
## 낚시 한 판의 클라이언트 쪽 진행. 판정은 전부 서버가 하고, 여기서는 연출과 입력만 맡는다.
##   던지기 요청 → (대기, 가짜 입질…) → 진짜 입질 → 챔질 요청(반응 시간 보고) → 서버가 확정한 결과

enum Phase { IDLE, CASTING, WAITING, BITE, RESULT }

@export_group("References")
@export var player: Player
@export var spot: FishingSpot
@export var bobber: Bobber
@export var hud: FishingHud

@export_group("Feel")
## 캐릭터 앞쪽 몇 미터에 찌를 던질지 (수역 안쪽으로 잘라 쓴다).
@export_range(1.0, 8.0, 0.1, "suffix:m") var cast_distance: float = 2.8
## 결과를 보여 주고 다시 움직일 수 있게 되기까지의 시간.
@export_range(0.2, 5.0, 0.1, "suffix:s") var result_hold: float = 1.6
@export var vibrate_on_bite: bool = true

var phase: Phase = Phase.IDLE

var _bite_shown_ms: float = 0.0
var _hooked: bool = false


func _ready() -> void:
	hud.action_pressed.connect(_on_action_pressed)
	hud.cancel_pressed.connect(Net.cancel_fishing)
	Net.fish_started.connect(_on_started)
	Net.fish_nibble.connect(_on_nibble)
	Net.fish_bite.connect(_on_bite)
	Net.fish_result.connect(_on_result)
	Net.action_rejected.connect(_on_rejected)
	Net.state_changed.connect(_on_net_state_changed)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _reset())


func _process(_delta: float) -> void:
	if phase == Phase.IDLE:
		var ready_to_cast: bool = Net.state == Net.State.ONLINE and spot.can_cast_from(player.global_position) \
			and not player.is_input_locked()
		hud.show_cast_available(ready_to_cast)


func _on_action_pressed() -> void:
	match phase:
		Phase.IDLE:
			phase = Phase.CASTING
			hud.show_casting()
			Net.cast_fishing(spot.spot_id)
		Phase.WAITING:
			# 입질 전에 당기면 서버가 early 로 실패 처리한다.
			Net.hook_fishing(0.0)
		Phase.BITE:
			if not _hooked:
				_hooked = true
				# 입질 연출이 보인 시점부터 누른 시점까지 — 네트워크 지연이 섞이지 않는 값.
				Net.hook_fishing(Time.get_ticks_msec() - _bite_shown_ms)
				hud.show_hooked()


func _on_started() -> void:
	phase = Phase.WAITING
	_hooked = false
	player.set_input_lock(&"fishing", true)
	var forward: Vector3 = -player.body.global_basis.z
	forward.y = 0.0
	var target: Vector3 = spot.info.clamp_inside(player.global_position + forward.normalized() * cast_distance)
	target.y = spot.water_height + 0.02
	bobber.show_at(target)
	player.look_toward(target - player.global_position)
	player.set_fishing_pose(true)
	hud.show_waiting()


func _on_nibble() -> void:
	if phase != Phase.WAITING:
		return
	bobber.nibble()
	hud.show_nibble()
	if vibrate_on_bite:
		Input.vibrate_handheld(30)


func _on_bite(window_ms: int) -> void:
	if phase != Phase.WAITING:
		return
	phase = Phase.BITE
	_bite_shown_ms = Time.get_ticks_msec()
	bobber.bite()
	hud.show_bite(window_ms)
	if vibrate_on_bite:
		Input.vibrate_handheld(120)


func _on_result(success: bool, fish_id: String, reason: String) -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.RESULT
	bobber.hide_bobber()
	player.set_fishing_pose(false)
	hud.show_result(_describe(success, fish_id, reason), success)
	await get_tree().create_timer(result_hold).timeout
	if phase == Phase.RESULT:
		_reset()


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
	phase = Phase.IDLE
	_hooked = false
	bobber.hide_bobber()
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
		_:
			return "지금은 낚시할 수 없어요"
