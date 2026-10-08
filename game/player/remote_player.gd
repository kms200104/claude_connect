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
## 화면에 그리는 이동 속도의 상한 (m/s, 달리기 7 + 여유). 위치 소식이 몰려 오면(모바일 망 · 끊김 뒤) 보간 목표가 한꺼번에
## 앞으로 튀는데, 그대로 따라가면 순간 빨라 보인다. 상한까지만 따라가고, 너무 뒤처지면(catch_up_after 넘게) 조금씩 더 빨리 따라잡는다.
@export_range(1.0, 30.0, 0.1, "suffix:m/s") var max_display_speed: float = 8.0
@export_range(0.1, 5.0, 0.1, "suffix:m") var catch_up_after: float = 1.0
@export_range(0.0, 20.0, 0.5) var catch_up_gain: float = 6.0

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


## 입은 옷 (스냅샷마다 온다). 보이던 친구의 옷이 바뀌면 탈의소에서 갈아입는다 (v0.15). 처음 나타날 때는 바로 입는다.
func set_outfit(hat: String, top: String) -> void:
	if rig == null:
		return
	_want_hat = hat
	_want_top = top
	if OutfitBooth.is_pending(rig):
		return
	if rig.outfit_item("hat") == hat and rig.outfit_item("top") == top:
		_outfit_known = true
		return
	if _outfit_known and online and visible and is_inside_tree():
		OutfitBooth.play(rig, _apply_wanted)
		return
	_outfit_known = true
	rig.set_outfit(hat, top)


## 탈것 (v0.16, 스냅샷마다 온다): 타면 꺼내 펼쳐 올라타는 모습, 내리면 접어 넣는 모습. 처음 나타날 때 이미 타고 있으면 바로.
func set_ride(item_id: String) -> void:
	if rig == null or item_id == _ride_item:
		return
	var animated: bool = _outfit_known and online and visible and is_inside_tree()
	_ride_item = item_id
	if _board_tween != null and _board_tween.is_valid():
		_board_tween.kill()
	if not item_id.is_empty():
		if _board == null:
			_board = Kickboard.new()
			_board.build(rig.clay_material)
			rig.add_child(_board)
		_board.position = Vector3(0.0, -(_body_rest_y if not is_nan(_body_rest_y) else body.position.y), 0.0)
		_board.scale = Vector3.ONE
		_board.visible = true
		_ride_speed = 0.0
		if animated:
			_board_tween = _board.play_unfold(rig, func() -> void: pass, false)
		else:
			_board.fold = 0.0
			rig.set_riding("kick")
		return
	if _board == null:
		rig.set_riding("")
		return
	var board: Kickboard = _board
	_board = null
	_ride_lean = 0.0
	body.transform = Transform3D(Basis(Vector3.UP, body.rotation.y), Vector3(0.0, _body_rest_y if not is_nan(_body_rest_y) else 0.8, 0.0))
	_board_tween = board.play_fold(rig, board.queue_free, false) if animated else null
	if not animated:
		rig.set_riding("")
		board.queue_free()


## 탄 친구: 화면에서 움직인 만큼 바퀴를 굴리고, 빨라지면 땅을 차고, 확 느려지면 브레이크 자세, 도는 만큼 바닥을 축으로 기운다.
func _update_ride(delta: float, before: Vector3) -> void:
	if _board == null or delta <= 0.0 or rig.riding_kind().is_empty():
		return
	var step: Vector3 = (global_position - before) * Vector3(1.0, 0.0, 1.0)
	var forward: Vector3 = Vector3(-sin(body.rotation.y), 0.0, -cos(body.rotation.y))
	_board.roll(step.dot(forward))
	var spd: float = step.length() / delta
	_ride_speed = lerpf(_ride_speed, spd, 1.0 - exp(-6.0 * delta))
	_ride_check -= delta
	if _ride_check <= 0.0:
		var gain: float = _ride_speed - _ride_last
		if gain > 0.3 and not rig.is_kicking():
			rig.play_kick()
			Audio.play_at("kick_push", global_position, -10.0)
		rig.set_riding("kick_brake" if gain < -0.9 and _ride_speed > 0.4 else "kick")
		_ride_last = _ride_speed
		_ride_check = 0.25
	var rate: float = wrapf(body.rotation.y - _ride_yaw, -PI, PI) / delta
	_ride_yaw = body.rotation.y
	_ride_lean = lerpf(_ride_lean, clampf(rate * _ride_speed * 0.085, -0.32, 0.32), 1.0 - exp(-7.0 * delta))
	_board.steer = lerpf(_board.steer, clampf(atan(rate * 0.54 / maxf(_ride_speed, 0.6)), -0.55, 0.55), 1.0 - exp(-10.0 * delta))
	var rest: float = _body_rest_y if not is_nan(_body_rest_y) else 0.8
	var basis: Basis = Basis(Vector3.UP, body.rotation.y) * Basis(Vector3.BACK, _ride_lean)
	body.transform = Transform3D(basis, basis * Vector3(0.0, rest, 0.0))


## 배달 알바 복장 (스냅샷마다 온다). 보이던 친구가 배달을 받거나 끝내면 탈의소에서 갈아입는다.
func set_uniform(on: bool) -> void:
	if rig == null:
		return
	_want_job = on
	if OutfitBooth.is_pending(rig) or rig.is_uniformed() == on:
		return
	if _outfit_known and online and visible and is_inside_tree():
		OutfitBooth.play(rig, _apply_wanted)
		return
	rig.set_uniform(on)


## 커튼이 닫혔을 때: 그때까지 들어온 옷 · 복장을 입힌다.
func _apply_wanted() -> void:
	rig.set_outfit(_want_hat, _want_top)
	rig.set_uniform(_want_job)


func _ready() -> void:
	# 닉네임이 바뀌면 머리 위 이름도 바꾼다 (v14).
	Net.name_changed.connect(func(id: int, _n: String) -> void:
		if id == player_id:
			set_online(online))
	# v16: 칭호를 바꾸면 닉네임 옆 칭호도.
	Journal.title_changed.connect(func(id: int) -> void:
		if id == player_id:
			set_online(online))


var _want_hat: String = ""
var _want_top: String = ""
var _want_job: bool = false
var _ride_item: String = ""
var _board: Kickboard = null
var _board_tween: Tween = null
var _ride_speed: float = 0.0
var _ride_last: float = 0.0
var _ride_check: float = 0.0
var _ride_yaw: float = 0.0
var _ride_lean: float = 0.0
var _outfit_known: bool = false


func setup(state: NetPlayerState) -> void:
	player_id = state.id
	if rig != null:
		rig.set_look(Net.look_of(state.id))
	global_position = state.position
	if body != null:
		body.rotation.y = state.yaw
	set_online(state.online)
	_apply_held(state.held)
	# 처음 나타날 때는 탈의소 없이 바로 (복장을 먼저 — 옷을 입히면 그다음부터 바뀔 때 탈의소).
	set_uniform(state.job)
	set_ride(state.ride)
	set_outfit(state.hat, state.top)
	set_phone(state.phone)


func set_online(value: bool) -> void:
	online = value
	if name_label != null:
		var shown: String = Journal.display_name(player_id)
		name_label.text = shown if online else "%s · 연결 끊김" % shown
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
		"plant", "pick", "place", "drop":
			# 쪼그려 앉아 심기·줍기·가구 놓기·내려놓기 (같은 몸짓).
			rig.play_plant()
		"give", "deliver":
			rig.play_emote("bow")
		"phone_tap":
			rig.phone_tap()


## 휴대폰을 꺼내 보는 중인지 (스냅샷마다 온다, v15).
func set_phone(on: bool) -> void:
	if rig != null and rig.is_holding_phone() != on:
		rig.set_phone(on and online)


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
			# v13: 겨눠 던진 자리 (물고기 머리 앞).
			if msg.get("bx") != null and msg.get("bz") != null:
				target = Vector3(float(msg["bx"]), target.y, float(msg["bz"]))
			_ensure_bobber().cast_to(_rod_tip(), target, CAST_FLIGHT_S)
			_bobber.landed.connect(func(at: Vector3) -> void: Audio.play_at("fish_plop", at, -4.0, 1.0, 0.08), CONNECT_ONE_SHOT)
		"found":
			# 지나가던 물고기가 찌를 알아챘다 (물고기 그림자는 FishSchool 이 그린다).
			pass
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
	var next: Vector3 = global_position.lerp(target_pos, weight)
	var step: Vector2 = Vector2(next.x - before.x, next.z - before.z)
	var lag: float = Vector2(target_pos.x - before.x, target_pos.z - before.z).length()
	if lag < teleport_distance and delta > 0.0:
		var limit: float = (max_display_speed + maxf(0.0, lag - catch_up_after) * catch_up_gain) * delta
		if step.length() > limit:
			step = step.normalized() * limit
			next = Vector3(before.x + step.x, next.y, before.z + step.y)
	global_position = next
	if rig != null and delta > 0.0:
		# 실제로 화면에서 움직인 속도로 걷기 애니메이션을 정한다 (낚시 중에는 서 있는다).
		var moved: float = Vector3(global_position.x - before.x, 0.0, global_position.z - before.z).length() / delta
		_shown_speed = lerpf(_shown_speed, moved, 1.0 - exp(-speed_smoothing * delta))
		rig.set_move_speed(0.0 if target_fishing else CharacterRig.speed_to_blend(_shown_speed, walk_speed_reference, run_speed_reference))
		rig.set_fishing(target_fishing)
		if not target_fishing and _ride_item.is_empty():
			_footsteps.advance(moved * delta, _shown_speed > walk_speed_reference * 1.25, global_position, true)
	if body != null:
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, weight)
	_update_ride(delta, before)
