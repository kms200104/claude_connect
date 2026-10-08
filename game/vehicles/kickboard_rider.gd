class_name KickboardRider
extends Node
## 내 캐릭터의 킥보드 타기 (v0.16): 가방에서 꺼내 펼쳐 올라타고, 조이스틱으로 달리고, 내려서 접어 넣는다.
## 움직임은 걷기와 따로 (Player 가 탈 때 drive 를 부른다):
##   - 앞으로 밀면 그 빠르기(밀어낸 만큼 × 최고 속도)에 닿을 때까지 뒷발로 땅을 찬다. 차는 동안(kick_push 구간)에만 빨라진다.
##   - 손을 떼면 천천히 미끄러지다 서고, 진행 방향 반대로 밀면 뒷발로 흙받이를 밟아 브레이크.
##   - 방향은 빠를수록 크게 돈다 (최소 반지름 turn_radius). 거의 서 있으면 제자리에서 핸들을 꺾어 돈다.
##   - 도는 만큼 몸 · 킥보드가 안쪽으로 기울고(바닥을 축으로) 앞바퀴 · 손잡이가 꺾인다. 바퀴는 달린 거리만큼 구른다.
## 서버에는 ride 로 탄 것만 알리고 (친구 화면 연출), 위치 · 속도는 걷기와 같은 move 로 보낸다 (서버 속도 한계 안).

signal changed(riding: bool)

enum State { OFF, MOUNTING, RIDING, DISMOUNTING }

@export var player: Player
## 안내 문구 (낚시 HUD 의 토스트).
@export var toast_hud: FishingHud

var state: State = State.OFF
var item_id: String = ""
var info: VehicleInfo = null
var board: Kickboard = null
## 지금 빠르기 (m/s, 앞으로) · 바라보는 방향 · 기울기 · 조향.
var speed: float = 0.0
var yaw: float = 0.0
var lean: float = 0.0
var yaw_rate: float = 0.0
var braking: bool = false
## 지금까지 땅을 찬 횟수 (테스트 · 소리용).
var kicks: int = 0
## 땅을 차기 시작하고 지난 시간 (차지 않으면 음수).
var _kick_t: float = -1.0
var _seq: Tween = null
var _last_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	# 퀵슬롯(Hotbar)이 찾는다.
	add_to_group(&"kickboard_rider")
	if player != null:
		player.vehicle = self


## 타고 있거나 타고 내리는 중.
func is_active() -> bool:
	return state != State.OFF


func is_riding() -> bool:
	return state == State.RIDING


## 이 아이템으로 지금 탈 수 있는지 (안 되면 그 까닭).
func mount_problem(id: String) -> String:
	var item: ItemInfo = GameData.item(id)
	if item == null or item.ride.is_empty() or VehicleInfo.of(item.ride) == null:
		return "탈 수 없는 물건이에요."
	if state != State.OFF:
		return "이미 타고 있어요."
	if player.is_input_locked():
		return "지금은 꺼낼 수 없어요."
	if Net.state != Net.State.ONLINE:
		return "마을에 접속해야 탈 수 있어요."
	if Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position)):
		return "실내에서는 탈 수 없어요."
	if player.wading or not player.is_on_floor():
		return "물이 없는 평평한 땅에서 꺼내요."
	return ""


## 가방에서 꺼내 펼치고 올라탄다.
func mount(id: String) -> bool:
	var problem: String = mount_problem(id)
	if not problem.is_empty():
		if toast_hud != null:
			toast_hud.show_toast(problem, false)
		return false
	item_id = id
	info = VehicleInfo.of(GameData.item(id).ride)
	state = State.MOUNTING
	speed = 0.0
	lean = 0.0
	yaw = player.body.rotation.y
	player.set_input_lock(&"ride", true)
	player.velocity = Vector3.ZERO
	Net.set_ride(item_id, true)
	board = Kickboard.new()
	board.build(player.rig.clay_material)
	player.rig.add_child(board)
	board.position.y = -player.body_rest_height()
	_seq = board.play_unfold(player.rig, _on_mounted, true)
	changed.emit(true)
	return true


func _on_mounted() -> void:
	state = State.RIDING
	player.set_input_lock(&"ride", false)
	_last_pos = player.global_position


## 내려서 접고 가방에 넣는다. animated 가 거짓이면 바로 (순간이동 · 실내 · 가방에서 빠졌을 때).
func dismount(animated: bool = true) -> void:
	if state == State.OFF or state == State.DISMOUNTING and animated:
		return
	Net.set_ride(item_id, false)
	Audio.set_loop("kick_roll_loop", 0.0, 10.0)
	speed = 0.0
	braking = false
	player.velocity = Vector3(0.0, player.velocity.y, 0.0)
	if not animated or board == null:
		_finish()
		return
	state = State.DISMOUNTING
	player.set_input_lock(&"ride", true)
	_restore_body()
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = board.play_fold(player.rig, _finish, true)


func _finish() -> void:
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = null
	if board != null:
		board.queue_free()
	board = null
	if player != null:
		player.rig.set_riding("")
		player.rig.set_rummaging(false)
		player.set_input_lock(&"ride", false)
		_restore_body()
	state = State.OFF
	Audio.set_loop("kick_roll_loop", 0.0, 10.0)
	changed.emit(false)


## 기울였던 몸을 똑바로 (Body 의 자리 · 방향은 yaw 만 남긴다).
func _restore_body() -> void:
	lean = 0.0
	if player != null and player.body != null:
		player.body.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, player.body_rest_height(), 0.0))


func _process(_delta: float) -> void:
	if state != State.RIDING:
		return
	# 실내로 들어가거나(문 · 집) 접속이 끊기거나 가방에서 빠지면 바로 내린다 (순간이동은 after_move 가 본다).
	var indoor: bool = Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position))
	if indoor or Net.state != Net.State.ONLINE or not _has_item():
		dismount(false)


func _has_item() -> bool:
	for item: InventoryItem in Net.inventory:
		if item != null and item.id == item_id:
			return true
	return false


## Player 가 탈 때마다 (물리 프레임) 부른다: 조이스틱 방향(월드)과 세기로 속도 · 방향 · 기울기를 정한다.
func drive(delta: float, move_dir: Vector3, amount: float) -> void:
	if state != State.RIDING:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return
	var turn_to: float = 0.0
	var target_speed: float = 0.0
	var was_braking: bool = braking
	braking = false
	if amount > 0.08 and move_dir != Vector3.ZERO:
		var want: float = atan2(-move_dir.x, -move_dir.z)
		var diff: float = wrapf(want - yaw, -PI, PI)
		# 반대로 밀었다: 방향은 그대로 두고 뒷발 브레이크 (잡기 시작했으면 설 때까지 계속).
		if absf(diff) > deg_to_rad(125.0) and (speed > 0.6 or was_braking and speed > 0.05):
			braking = true
		else:
			turn_to = diff
			# 많이 돌아야 하면 먼저 돌고 나서 찬다 (옆 · 뒤로 차고 나가지 않게).
			target_speed = amount * info.max_speed * clampf((cos(diff) - 0.3) / 0.6, 0.0, 1.0)
	# 방향: 빠를수록 크게 돈다. 거의 서 있으면 제자리에서.
	var slow: float = clampf(1.0 - speed / 1.5, 0.0, 1.0)
	var max_rate: float = maxf(info.slow_turn * slow, minf(speed / info.turn_radius, 3.2))
	var want_rate: float = clampf(turn_to * 5.0, -max_rate, max_rate)
	yaw_rate = lerpf(yaw_rate, want_rate, 1.0 - exp(-12.0 * delta))
	yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
	# 땅 차기: 원하는 빠르기에 모자라면 한 번씩 찬다 (차는 동안 미는 구간에만 빨라진다).
	if _kick_t < 0.0 and not braking and target_speed > speed + 0.35 and speed < info.max_speed - 0.15:
		_kick_t = 0.0
		kicks += 1
		player.rig.play_kick()
	if _kick_t >= 0.0:
		var before: float = _kick_t
		_kick_t += delta
		var push: Vector2 = info.kick_push
		var overlap: float = maxf(0.0, minf(_kick_t, push.y) - maxf(before, push.x))
		if overlap > 0.0:
			speed += info.kick_boost * overlap / (push.y - push.x)
			if before < push.x:
				Audio.play_sfx("kick_push", -8.0)
		if _kick_t >= info.kick_time:
			_kick_t = -1.0
	# 줄어드는 빠르기: 브레이크 > 손 뗌 > 그냥 미끄러짐.
	var drag: float = info.coast_drag
	if braking:
		drag = info.brake
	elif amount <= 0.08:
		drag = info.idle_brake
	speed = maxf(0.0, speed - drag * delta)
	if player.wading:
		speed = move_toward(speed, minf(speed, info.wade_speed), 6.0 * delta)
	speed = minf(speed, info.max_speed)
	player.rig.set_riding("kick_brake" if braking and speed > 0.2 else "kick")
	if braking and not was_braking and speed > 0.8:
		Audio.play_sfx("kick_brake", -6.0)
	# 바퀴 구르는 소리: 빠를수록 크게.
	Audio.set_loop("kick_roll_loop", clampf(speed / info.max_speed, 0.0, 1.0) * 0.55, delta)
	var heading: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	player.velocity.x = heading.x * speed
	player.velocity.z = heading.z * speed
	# 기울기 · 조향 (안쪽으로).
	var lean_target: float = clampf(yaw_rate * speed * 0.085, -info.max_lean, info.max_lean)
	lean = lerpf(lean, lean_target, 1.0 - exp(-7.0 * delta))
	var steer_target: float = 0.0
	if speed > 0.6:
		steer_target = atan(yaw_rate * 0.54 / speed)
	else:
		steer_target = info.max_steer * clampf(yaw_rate / info.slow_turn, -1.0, 1.0)
	board.steer = lerpf(board.steer, clampf(steer_target, -info.max_steer, info.max_steer), 1.0 - exp(-10.0 * delta))
	_place_body()


## 움직인 뒤: 바퀴를 굴리고, 벽에 막혔으면 그만큼 느려진다.
func after_move(delta: float, before: Vector3) -> void:
	if state != State.RIDING or board == null:
		return
	# 순간이동(문 · 테스트)으로 지난 물리 프레임 끝 자리에서 확 벗어났으면 바로 내린다.
	if Vector2(before.x - _last_pos.x, before.z - _last_pos.z).length() > 4.0:
		dismount(false)
		return
	var step: Vector3 = (player.global_position - before) * Vector3(1.0, 0.0, 1.0)
	var heading: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	board.roll(step.dot(heading))
	var actual: float = step.length() / maxf(delta, 0.0001)
	if speed > 1.0 and actual < speed * 0.5:
		speed = actual
	_last_pos = player.global_position


## 몸(Body) 방향 · 기울기: 바닥을 축으로 기울인다 (골반을 축으로 돌리면 발이 발판에서 미끄러진다).
func _place_body() -> void:
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean)
	player.body.transform = Transform3D(basis, basis * Vector3(0.0, player.body_rest_height(), 0.0))


## 지금 화면에 낼 빠르기 비율 (HUD · 테스트용).
func speed_ratio() -> float:
	return speed / info.max_speed if info != null else 0.0
