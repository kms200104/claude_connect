class_name RemotePlayer
extends Node3D
## 다른 사람의 캐릭터. 서버 스냅샷을 버퍼에 쌓고, 서버 시계 기준으로 조금 과거(interpolation_delay)를
## 보간해서 그린다. 패킷이 늦거나 몇 개 빠져도 끊기지 않고, 너무 늦으면 짧게 외삽한 뒤 멈춘다.

@export_group("References")
@export var body: Node3D
@export var rig: CharacterRig
@export var name_label: Label3D

@export_group("Interpolation")
## 클수록 부드럽지만 상대 움직임이 늦게 보인다. 스냅샷 주기(50ms)의 2~3배가 적당.
@export_range(0.0, 500.0, 5.0, "suffix:ms") var interpolation_delay_ms: float = 120.0
## 최신 스냅샷보다 앞서야 할 때 속도로 추정해 이동하는 최대 시간.
@export_range(0.0, 500.0, 10.0, "suffix:ms") var max_extrapolation_ms: float = 200.0
## 이 거리 이상 한 번에 움직이면 보간하지 않고 순간이동으로 본다.
@export_range(0.5, 50.0, 0.5, "suffix:m") var teleport_distance: float = 6.0
## 보간 결과를 한 번 더 부드럽게 따라가는 정도 (클수록 딱 붙는다).
@export_range(1.0, 60.0, 0.5) var follow_smoothing: float = 30.0
@export_range(4, 100) var max_samples: int = 40

@export_group("Animation")
## 이 속도(m/s)로 움직이면 walk 애니메이션이 100% 재생된다 (플레이어 최대 속도와 같게).
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var walk_speed_reference: float = 4.5
## 이 속도면 run 애니메이션이 100% (플레이어 달리기 속도와 같게).
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var run_speed_reference: float = 7.0
## 화면에서 실제 움직인 속도를 이 정도로 부드럽게 따라가며 걷기 애니메이션에 쓴다.
@export_range(1.0, 40.0, 0.5) var speed_smoothing: float = 12.0

var player_id: int = 0
var online: bool = true
var fishing: bool = false
## 리그의 기본값(낚싯대)과 같게 시작해야 첫 상태가 빈손일 때도 반영된다.
var held_item: String = "rod"

## v12: 상대 낚시 장면 (던진 찌가 날아가 떨어지고, 톡·쑥 입질, 끌어올리기, 낚으면 들어 올려 자랑). FishingController 와 같은 값.
const BOBBER_SCENE: PackedScene = preload("res://game/fishing/bobber.tscn")
const CAST_DISTANCE: float = 2.8
const CAST_RELEASE_S: float = 0.24
const CAST_FLIGHT_S: float = 0.55
const SHOW_OFF_S: float = 2.6

var _samples: Array[Sample] = []
var _bobber: Bobber = null
## 낚시 장면 번호 — 기다리는 동안 다음 장면이 오면 이전 것은 멈춘다.
var _fish_seq: int = 0
var _shown_speed: float = 0.0
var _footsteps: Footsteps = Footsteps.new()


class Sample:
	var time_ms: float
	var position: Vector3
	var yaw: float
	var velocity: Vector3
	var fishing: bool
	var held: String

	func _init(t: float, p: Vector3, y: float, v: Vector3, f: bool, h: String) -> void:
		time_ms = t
		position = p
		yaw = y
		velocity = v
		fishing = f
		held = h


## 입은 옷 (스냅샷마다 온다).
func set_outfit(hat: String, top: String) -> void:
	if rig != null:
		rig.set_outfit(hat, top)


func setup(state: NetPlayerState) -> void:
	player_id = state.id
	if rig != null:
		rig.set_look(Net.look_of(state.id))
	global_position = state.position
	if body != null:
		body.rotation.y = state.yaw
	set_online(state.online)
	_apply_held(state.held)
	set_outfit(state.hat, state.top)


func set_online(value: bool) -> void:
	online = value
	if name_label != null:
		name_label.text = "플레이어 %d" % player_id if online else "플레이어 %d · 연결 끊김" % player_id
		name_label.modulate = Color.WHITE if online else Color(1.0, 1.0, 1.0, 0.55)


## 상대의 동작 이벤트: 도끼질 · 뜰채질 · 삽질 · 요리 동작(같이 요리할 때 친구 손이 보이게).
const COOK_TOOLS: Dictionary = {"cook_chop": "knife", "cook_stir": "pan", "cook_flip": "pan", "cook_mix": "", "cook_plate": ""}


func play_action(kind: String, target: String = "") -> void:
	if rig == null:
		return
	match kind:
		"chop", "net":
			rig.play_chop()
			if kind == "net":
				Audio.play_at("fish_plop", global_position, -6.0, 1.2)
		"dig":
			rig.play_dig()
			Audio.play_at("dig", global_position, -4.0)
		"cook":
			rig.set_cooking(target, str(COOK_TOOLS.get(target, "")))
		"cook_end":
			rig.set_cooking("")
		"carry":
			# 배달 물건을 받아 든다 (손에 든 모습은 위치 스냅샷의 held 로 바뀐다, 빈 문자열 = 그만둠).
			if not target.is_empty():
				rig.play_plant()
		"plant", "pick", "place":
			# 쪼그려 앉아 심기·줍기·가구 놓기 (같은 몸짓).
			rig.play_plant()
		"give", "deliver":
			rig.play_emote("bow")


## 상대의 낚시 장면 한 토막 (서버 act kind = fish).
func fish_event(msg: Dictionary) -> void:
	_fish_seq += 1
	var seq: int = _fish_seq
	match str(msg.get("e", "")):
		"cast":
			if rig != null:
				rig.play_cast()
			Audio.play_at("fish_cast", global_position, -4.0, 1.0, 0.05)
			await get_tree().create_timer(CAST_RELEASE_S).timeout
			if seq != _fish_seq or not is_inside_tree():
				return
			var target: Vector3 = _cast_target(str(msg.get("spot", "")))
			if target == Vector3.INF:
				return
			_ensure_bobber().cast_to(_rod_tip(), target, CAST_FLIGHT_S)
			_bobber.landed.connect(func(at: Vector3) -> void: Audio.play_at("fish_plop", at, -4.0, 1.0, 0.08), CONNECT_ONE_SHOT)
		"nibble":
			if _bobber != null and _bobber.visible:
				_bobber.nibble()
		"bite":
			if _bobber != null and _bobber.visible:
				_bobber.bite()
				Audio.play_at("fish_bite", _bobber.global_position, -3.0)
		"reel":
			if _bobber != null and _bobber.visible:
				_bobber.struggle()
			if rig != null:
				rig.reel_tug()
		"land":
			if _bobber != null:
				_bobber.hide_bobber()
			var fish: FishInfo = GameData.fish.get(str(msg.get("fish", "")))
			if fish == null or rig == null:
				return
			rig.show_off(FishModel.mesh(fish), {"S": 0.75, "M": 1.0, "L": 1.25}.get(fish.size, 1.0))
			EmoteBubble.say(self, GameData.catch_shout(fish.rarity, fish.display_name), 2.95, SHOW_OFF_S - 0.4)
			Audio.play_at("fanfare_small" if fish.rarity != "common" else "fish_catch", global_position, -4.0)
			await get_tree().create_timer(SHOW_OFF_S).timeout
			if seq == _fish_seq and rig != null and rig.is_showing_off():
				rig.show_off(null)
		_:
			if _bobber != null:
				_bobber.hide_bobber()


func _ensure_bobber() -> Bobber:
	if _bobber == null or not is_instance_valid(_bobber):
		_bobber = BOBBER_SCENE.instantiate()
		_bobber.top_level = true
		add_child(_bobber)
	return _bobber


## 상대 찌가 떨어질 자리: 낚시터 안, 바라보는 방향으로 CAST_DISTANCE 앞 (FishingController._on_started 와 같은 식).
func _cast_target(spot_id: String) -> Vector3:
	for node: Node in get_tree().get_nodes_in_group(&"fishing_spots"):
		var spot: FishingSpot = node as FishingSpot
		if spot == null or spot.info == null or spot.spot_id != spot_id:
			continue
		var forward: Vector3 = -body.global_basis.z if body != null else Vector3.FORWARD
		forward.y = 0.0
		var target: Vector3 = spot.info.clamp_inside(global_position + forward.normalized() * CAST_DISTANCE)
		target.y = spot.water_height + 0.02
		return target
	return Vector3.INF


func _rod_tip() -> Vector3:
	if rig != null and rig.rod != null:
		return rig.rod.global_transform * Vector3(0.0, 1.5, 0.0)
	return global_position + Vector3(0.0, 1.6, 0.0)


## 상대의 감정표현·몸짓. 브레이크는 몸을 젖히고 끼이익 미끄러지며 흙먼지를 일으킨다.
func play_emote(emote_id: String) -> void:
	if emote_id == NetProtocol.MOTION_BRAKE:
		_brake()
		return
	if rig != null:
		rig.play_emote(emote_id)
	EmoteBubble.pop(self, emote_id)
	var info: EmoteInfo = GameData.emote(emote_id)
	Audio.play_at(info.sound if info != null else "emote_pop", global_position + Vector3(0.0, 1.5, 0.0), -3.0)


func _brake() -> void:
	if rig == null:
		return
	rig.set_braking(true)
	Audio.play_at("skid", global_position, -1.0, 1.0, 0.06)
	for i: int in 6:
		Puff.burst(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Puff.dust_color(global_position), 2, 0.45, 0.25, 0.08, 0.45)
		await get_tree().create_timer(0.07).timeout
	rig.set_braking(false)


func push_sample(server_time_ms: float, position: Vector3, yaw: float, velocity: Vector3, is_fishing: bool = false, held: String = "") -> void:
	if not _samples.is_empty():
		var last: Sample = _samples[-1]
		if server_time_ms <= last.time_ms:
			return  # 순서가 뒤바뀐 패킷
		if last.position.distance_to(position) > teleport_distance:
			_samples.clear()
			global_position = position
	_samples.append(Sample.new(server_time_ms, position, yaw, velocity, is_fishing, held))
	# 손에 든 도구는 보간할 값이 아니라서 받자마자 바꾼다.
	_apply_held(held)
	if _samples.size() > max_samples:
		_samples.pop_front()


func _apply_held(item_id: String) -> void:
	if item_id == held_item:
		return
	held_item = item_id
	if rig != null:
		rig.set_held(item_id)


## 몸(Body)의 원래 높이 (여울에서 잠길 때 기준).
var _body_rest_y: float = NAN


func _process(delta: float) -> void:
	# 여울에 들어간 친구도 물에 잠겨 보인다 (Player.WADE_SINK).
	if body != null:
		if is_nan(_body_rest_y):
			_body_rest_y = body.position.y
		var sink: float = Player.WADE_SINK if not Field.zone_at(global_position, 0.1).is_empty() else 0.0
		body.position.y = move_toward(body.position.y, _body_rest_y - sink, delta * 1.2)
	if _samples.is_empty():
		return
	var render_time: float = Net.server_time_ms() - interpolation_delay_ms
	var target_pos: Vector3
	var target_yaw: float
	var target_fishing: bool
	var last: Sample = _samples[-1]

	if render_time >= last.time_ms:
		var ahead: float = minf(render_time - last.time_ms, max_extrapolation_ms) / 1000.0
		target_pos = last.position + last.velocity * ahead
		target_yaw = last.yaw
		target_fishing = last.fishing
	elif render_time <= _samples[0].time_ms:
		target_pos = _samples[0].position
		target_yaw = _samples[0].yaw
		target_fishing = _samples[0].fishing
	else:
		var i: int = _samples.size() - 2
		while i > 0 and _samples[i].time_ms > render_time:
			i -= 1
		var a: Sample = _samples[i]
		var b: Sample = _samples[i + 1]
		var span: float = maxf(b.time_ms - a.time_ms, 0.001)
		var f: float = clampf((render_time - a.time_ms) / span, 0.0, 1.0)
		target_pos = a.position.lerp(b.position, f)
		target_yaw = lerp_angle(a.yaw, b.yaw, f)
		target_fishing = a.fishing

	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	var before: Vector3 = global_position
	global_position = global_position.lerp(target_pos, weight)
	if rig != null and delta > 0.0:
		# 실제로 화면에서 움직인 속도로 걷기 애니메이션을 정한다 (낚시 중에는 서 있는다).
		var moved: float = Vector3(global_position.x - before.x, 0.0, global_position.z - before.z).length() / delta
		_shown_speed = lerpf(_shown_speed, moved, 1.0 - exp(-speed_smoothing * delta))
		rig.set_move_speed(0.0 if target_fishing else CharacterRig.speed_to_blend(_shown_speed, walk_speed_reference, run_speed_reference))
		rig.set_fishing(target_fishing)
		if not target_fishing:
			_footsteps.advance(moved * delta, _shown_speed > walk_speed_reference * 1.25, global_position, true)
	if body != null:
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, weight)
