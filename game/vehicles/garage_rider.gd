class_name GarageRider
extends Node
## 내 캐릭터의 차고 탈것 (v19.1): 자전거 · 전기오토바이.
##   부르기: 휴대폰 "탈것" 앱 · HUD 탈것 단추 → 동네 주민이 타고 와서 내 곁에 세워 두고 간다 (서버 veh_call, ParkedVehicles 가 그린다).
##   타기: 세워 둔 내 탈것 곁에서 상황 버튼 "타기" (또는 탈것 단추) → 서버가 받아 주면(veh_ride) 그 모형에 폴짝 올라앉는다.
##   세우기: 상황 버튼 "세우기" → 왼쪽(막히면 오른쪽)으로 내려서고 탈것은 받침대를 세워 그 자리에 남는다 (서버가 저장, 친구도 본다).
## 타는 동안은 Player 가 걷기 대신 drive 를 부르고, 움직임은 VehicleDrive, 모양은 VehicleModel.
## 자전거는 리그가 바퀴 속도에 맞춰 페달을 돌리고(set_pedal_rate) 그 위상으로 크랭크가 같이 돈다.
## 실내 · 순간이동 · 접속 끊김이면 그 자리에 바로 세운다 (서버도 같은 자리에 세워 둔다). 킥보드(KickboardRider)와는 동시에 못 탄다.

signal changed(riding: bool)

enum State { OFF, WAITING, MOUNTING, RIDING, DISMOUNTING }

@export var player: Player
## 안내 문구 (낚시 HUD 의 토스트).
@export var toast_hud: FishingHud
## 탈것 단추 · 속도계를 붙일 HUD.
@export var hud: CanvasLayer
## 세워 둔 탈것 (모형을 넘겨받고 돌려준다).
@export var parked: ParkedVehicles

@export_group("Layout")
@export var button_size: float = 118.0
## 오른쪽 아래 단추 줄: 휴대폰 단추(오른쪽 24, 위 1010, 118) 왼쪽에 나란히.
@export var button_right: float = 158.0
@export var button_y: float = 1010.0

## 곁에서 올라탈 수 있는 거리 (서버 delivery.ride_range 보다 조금 안쪽).
const RIDE_RANGE: float = 2.6
## 내려설 때 옆으로 비키는 거리.
const STEP_OFF: float = 0.7
## 부른 탈것을 세울 자리 (내 오른쪽 · 왼쪽 · 앞 · 뒤 순서로 트인 곳).
const CALL_OFFSET: float = 1.6
## 서버 답을 기다리는 최대 시간.
const WAIT_S: float = 3.0

var state: State = State.OFF
## 타고 있는(또는 마지막으로 탄) 차고 탈것 id.
var vehicle_id: String = ""
var model: VehicleModel = null
var info: VehicleCatalog.Model = null
var drive_state: VehicleDrive = VehicleDrive.new()
var _fit: Dictionary = {}
var _last_pos: Vector3 = Vector3.ZERO
var _last_yaw: float = 0.0
var _seq: Tween = null
var _wait_left: float = 0.0
## 올라타기를 청하는 동안 세워 둔 모형 · 자리 (거절되면 돌려놓는다).
var _spot: Vector3 = Vector3.ZERO
var _spot_yaw: float = 0.0
var _button: Button = null
var _gauge: Label = null
var _hud_left: float = 0.0
var _icon_state: String = ""


func _ready() -> void:
	add_to_group(&"garage_rider")
	if player != null:
		player.garage_ride = self
	Net.mount_changed.connect(_on_mount_changed)
	Net.request_failed.connect(_on_failed)
	Net.vehicles_changed.connect(_on_vehicles_changed)
	Net.vehicle_done.connect(_on_vehicle_done)
	if hud != null:
		_build_hud()


func is_active() -> bool:
	return state != State.OFF


func is_riding() -> bool:
	return state == State.RIDING


## 지금 탈 수 있는지 (안 되면 그 까닭).
func mount_problem(id: String) -> String:
	var v: Dictionary = Net.vehicle(id)
	if v.is_empty() or GameData.garage.model(str(v.get("model", ""))) == null:
		return "차고에 없는 탈것이에요."
	if state != State.OFF and state != State.RIDING:
		return "잠깐만요, 타고 내리는 중이에요."
	if state == State.RIDING and id == vehicle_id:
		return "이미 타고 있어요."
	if player.vehicle != null and player.vehicle.is_active():
		return "킥보드를 먼저 접어 넣어요."
	if state == State.OFF and player.is_input_locked():
		return "지금은 탈 수 없어요."
	if _outside_problem():
		return _outside_problem()
	var spot: Dictionary = parked.spot_of(id) if parked != null else {}
	if spot.is_empty():
		return "먼저 탈것을 불러요 (휴대폰 탈것 앱 · 탈것 단추)."
	if not bool(spot.get("arrived", false)):
		return "주민이 가져오는 중이에요."
	if _flat(player.global_position, spot["at"]) > RIDE_RANGE:
		return "세워 둔 곳 곁에서 탈 수 있어요."
	return ""


func _outside_problem() -> String:
	if Net.state != Net.State.ONLINE:
		return "마을에 접속해야 해요."
	if Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position)):
		return "실내에서는 탈 수 없어요."
	if player.wading:
		return "물이 없는 땅에서 해요."
	return ""


## 세워 둔 내 탈것에 올라타기를 서버에 청한다 (답이 오면 올라탄다). 타는 중이면 지금 것을 세우고 바꿔 탄다.
func mount(id: String) -> bool:
	var problem: String = mount_problem(id)
	if not problem.is_empty():
		_toast(problem, false)
		return false
	if state == State.RIDING:
		# 타던 것을 먼저 서버에도 세운다고 알린다 (새 탈것을 못 타게 되어도 둘이 어긋나지 않게).
		_park_here(true)
	var spot: Dictionary = parked.spot_of(id)
	_spot = spot["at"]
	_spot_yaw = float(spot["yaw"])
	# 세워 둔 모형을 먼저 받아 둔다 (서버 목록이 먼저 와서 지워져도 같은 모형으로 탄다).
	model = parked.take(id)
	vehicle_id = id
	state = State.WAITING
	_wait_left = WAIT_S
	Net.request("veh_ride", {"v": id})
	return true


## 주민에게 그 탈것을 가져다 달라고 한다 (내 곁 트인 자리에 세워 두고 간다).
func call_vehicle(id: String) -> bool:
	var v: Dictionary = Net.vehicle(id)
	if v.is_empty():
		_toast("차고에 없는 탈것이에요.", false)
		return false
	if state != State.OFF and id == vehicle_id:
		_toast("지금 타고 있는 탈것이에요.", false)
		return false
	var problem: String = _outside_problem()
	if not problem.is_empty():
		_toast(problem, false)
		return false
	var yaw: float = player.body.global_rotation.y
	var at: Vector3 = _call_spot(yaw)
	Net.request("veh_call", {"v": id, "x": at.x, "z": at.z, "yaw": yaw})
	return true


## 부른 탈것을 세울 자리: 내 오른쪽 → 왼쪽 → 앞 → 뒤 가운데 막히지 않은 곳.
func _call_spot(yaw: float) -> Vector3:
	var b: Basis = Basis(Vector3.UP, yaw)
	var from: Vector3 = player.global_position
	for dir: Vector3 in [b.x, -b.x, -b.z, b.z]:
		var at: Vector3 = from + dir * CALL_OFFSET
		if _clear(from, at):
			return at
	return from


## 두 자리 사이 (허리 높이) 가 막히지 않았는지.
func _clear(from: Vector3, to: Vector3) -> bool:
	if not player.is_inside_tree():
		return true
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.6, 0), to + (to - from).normalized() * 0.5 + Vector3(0, 0.6, 0))
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## HUD 탈것 단추: 타는 중이면 세우기, 곁에 세워 둔 것이 있으면 타기, 아니면 마지막으로 탄 탈것 부르기.
func quick_action() -> void:
	if state == State.RIDING:
		dismount()
		return
	if state != State.OFF:
		return
	if Net.vehicles.is_empty():
		_toast("휴대폰 탈것 앱에서 자전거 · 오토바이를 살 수 있어요.", false)
		return
	var near: String = parked.nearest_own(player.global_position, RIDE_RANGE) if parked != null else ""
	if not near.is_empty():
		mount(near)
		return
	var pick: String = _default_vehicle()
	var spot: Dictionary = parked.spot_of(pick) if parked != null else {}
	if not spot.is_empty() and not bool(spot.get("arrived", true)):
		_toast("주민이 가져오는 중이에요.", true)
		return
	call_vehicle(pick)


func _default_vehicle() -> String:
	if not Net.vehicle(vehicle_id).is_empty():
		return vehicle_id
	return str(Net.vehicles[0].get("id", "")) if not Net.vehicles.is_empty() else ""


func _on_vehicle_done(result: Dictionary) -> void:
	if str(result.get("kind", "")) != "call":
		return
	var v: Dictionary = Net.vehicle(str(result.get("v", "")))
	var m: VehicleCatalog.Model = GameData.garage.model(str(v.get("model", "")))
	var who: String = GameData.npc_name(str(result.get("npc", "")))
	_toast("%s님이 %s 을(를) 가져다줄게요!" % [who if not who.is_empty() else "주민", m.name if m != null else "탈것"], true)


func _on_mount_changed(mount_wire: Dictionary) -> void:
	if mount_wire.is_empty() or state != State.WAITING or str(mount_wire.get("v", "")) != vehicle_id:
		return
	_start(str(mount_wire.get("m", "")), mount_wire.get("f", {}) as Dictionary)


func _on_failed(kind: String, code: String) -> void:
	if kind == "veh_call":
		_toast("부를 수 없어요." if code != NetProtocol.ERR_CANT_RIDE else "실내 · 낚시 중에는 부를 수 없어요.", false)
		return
	if kind != "veh_ride" or state != State.WAITING:
		return
	_give_back()
	_toast("지금은 탈 수 없어요." if code == NetProtocol.ERR_CANT_RIDE else ("세워 둔 곳 곁에서 탈 수 있어요." if code == NetProtocol.ERR_NOT_NEAR_VEHICLE else "탈 수 없어요 (%s)." % code), false)


## 올라타기가 안 됐다: 받아 둔 모형을 제자리에 돌려놓는다.
func _give_back() -> void:
	state = State.OFF
	if model != null and parked != null:
		parked.put(vehicle_id, model, _spot, _spot_yaw)
	model = null


## 올라탄다: 세워 둔 탈것 쪽으로 다가가 폴짝 안장에 앉는다 (탈것은 제자리 그대로).
func _start(model_id: String, fit: Dictionary) -> void:
	info = GameData.garage.model(model_id)
	if info == null:
		_give_back()
		return
	_fit = fit.duplicate()
	state = State.MOUNTING
	player.set_input_lock(&"garage_ride", true)
	player.velocity = Vector3.ZERO
	drive_state.setup(info, GameData.garage.stats(model_id, _fit), GameData.garage.kinds.get(info.kind, {}), _spot_yaw)
	if model == null:
		model = VehicleModel.new()
		model.build(model_id, _fit)
	elif model.model_id != model_id or model.fit != _fit:
		model.build(model_id, _fit)
	model.name = "Vehicle"
	model.lights_on = true
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	player.rig.add_child(model)
	model.scale = Vector3.ONE
	var ground: Transform3D = Transform3D(Basis(Vector3.UP, _spot_yaw), Vector3(_spot.x, player.global_position.y, _spot.z))
	var from: Vector3 = player.global_position
	var from_yaw: float = player.body.global_rotation.y
	Audio.play_sfx("kick_latch", -6.0)
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_last_pos = ground.origin
	_last_yaw = _spot_yaw
	# 다가가며 탈것 방향으로 돌아서고, 폴짝 뛰어 안장에 앉는다. 탈것은 땅에 그대로.
	var hop: Callable = func(t: float) -> void:
		var k: float = t * t * (3.0 - 2.0 * t)
		player.global_position = from.lerp(ground.origin, k)
		var yaw: float = lerp_angle(from_yaw, _spot_yaw, k)
		var lift: float = info.lift * k + sin(k * PI) * 0.16
		player.body.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, player.body_rest_height() + lift, 0.0))
		if model != null:
			model.global_transform = ground
		if t > 0.45:
			player.rig.set_riding(info.kind)
	_seq = create_tween()
	_seq.tween_method(hop, 0.0, 1.0, 0.42)
	_seq.tween_callback(_on_mounted)
	changed.emit(true)


func _on_mounted() -> void:
	state = State.RIDING
	drive_state.yaw = _spot_yaw
	player.set_input_lock(&"garage_ride", false)
	_last_pos = player.global_position
	_last_yaw = drive_state.yaw
	_place_body()
	_update_hud(true)


## 세우기 (상황 버튼 · 탈것 단추): 옆으로 내려서고 탈것은 그 자리에 받침대를 세워 둔다.
## animated 가 거짓이면 바로 (순간이동 · 실내 · 접속 끊김) — 떠나기 전 자리에 세운다.
func dismount(animated: bool = true) -> void:
	if state == State.OFF or state == State.DISMOUNTING and animated:
		return
	if state == State.WAITING:
		_give_back()
		return
	Audio.set_loop("kick_roll_loop", 0.0, 10.0)
	if not animated or model == null:
		_park_here(Net.state == Net.State.ONLINE and not _server_parks())
		return
	Net.request("veh_ride", {"v": ""})
	state = State.DISMOUNTING
	player.set_input_lock(&"garage_ride", true)
	drive_state.speed = 0.0
	player.velocity = Vector3(0.0, player.velocity.y, 0.0)
	player.rig.set_riding("")
	var yaw: float = drive_state.yaw
	var ground: Transform3D = Transform3D(Basis(Vector3.UP, yaw), player.global_position)
	var left: Vector3 = -Basis(Vector3.UP, yaw).x
	var to: Vector3 = player.global_position + left * STEP_OFF
	if not _clear(player.global_position, to):
		to = player.global_position - left * STEP_OFF
	var from: Vector3 = player.global_position
	if _seq != null and _seq.is_valid():
		_seq.kill()
	var hop: Callable = func(t: float) -> void:
		var k: float = t * t * (3.0 - 2.0 * t)
		player.global_position = from.lerp(to, k)
		var lift: float = info.lift * (1.0 - k) + sin(k * PI) * 0.1
		player.body.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, player.body_rest_height() + lift, 0.0))
		if model != null:
			model.global_transform = ground
	var done: Callable = func() -> void:
		Audio.play_sfx("kick_latch", -8.0)
		_hand_to_parked(ground.origin, yaw)
		_finish()
	_seq = create_tween()
	_seq.tween_method(hop, 0.0, 1.0, 0.36)
	_seq.tween_callback(done)


## 서버가 이미 세워 둔 경우 (문 · 집 드나들기 · 끊김) — 다시 알릴 필요가 없다.
func _server_parks() -> bool:
	return Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position)) or Net.state != Net.State.ONLINE


## 지금(또는 방금 전) 자리에 바로 세운다. tell 이면 서버에도 내린다고 알린다.
func _park_here(tell: bool) -> void:
	if tell:
		Net.request("veh_ride", {"v": ""})
	_hand_to_parked(_last_pos, _last_yaw)
	_finish()


func _hand_to_parked(at: Vector3, yaw: float) -> void:
	if model == null:
		return
	if parked != null and not Net.vehicle(vehicle_id).is_empty():
		parked.put(vehicle_id, model, at, yaw)
	else:
		model.queue_free()
	model = null


func _finish() -> void:
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = null
	if model != null:
		model.queue_free()
	model = null
	if player != null:
		player.rig.set_riding("")
		player.rig.set_pedal_rate(0.0)
		player.set_input_lock(&"garage_ride", false)
		player.body.transform = Transform3D(Basis(Vector3.UP, drive_state.yaw), Vector3(0.0, player.body_rest_height(), 0.0))
	drive_state.speed = 0.0
	state = State.OFF
	changed.emit(false)
	_update_hud(true)


func _process(delta: float) -> void:
	_hud_left -= delta
	if _hud_left <= 0.0:
		_hud_left = 0.2
		_update_hud(false)
	if state == State.WAITING:
		_wait_left -= delta
		if _wait_left <= 0.0:
			_give_back()
		return
	if state != State.RIDING and state != State.MOUNTING:
		return
	var indoor: bool = Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position))
	if indoor or Net.state != Net.State.ONLINE or Net.vehicle(vehicle_id).is_empty():
		dismount(false)
		return
	# 크랭크는 리그가 이 프레임에 센 페달 위상으로 (리그는 Player 아래라 이 노드보다 먼저 돈다).
	if model != null:
		model.set_pedal(player.rig.pedal_phase())
	if state == State.RIDING and _gauge != null:
		_gauge.text = "%d km/h" % roundi(speed_kmh())


## 차고가 바뀌었다 (부품을 바꿨으면 타고 있는 모양도 바꾼다).
func _on_vehicles_changed() -> void:
	if model == null or state == State.WAITING:
		return
	var v: Dictionary = Net.vehicle(vehicle_id)
	if v.is_empty():
		return
	var fit: Dictionary = v.get("fit", {}) as Dictionary
	if fit != _fit:
		_fit = fit.duplicate()
		model.build(str(v.get("model", "")), _fit)
		drive_state.stats = GameData.garage.stats(str(v.get("model", "")), _fit)


## Player 가 탈 때마다 (물리 프레임) 부른다.
func drive(delta: float, move_dir: Vector3, amount: float) -> void:
	if state != State.RIDING:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return
	var v: Vector3 = drive_state.step(move_dir, amount, drive_state.stats.wade if player.wading else 1.0, delta)
	player.velocity.x = v.x
	player.velocity.z = v.z
	var speed: float = drive_state.speed
	player.rig.set_pedal_rate(model.pedal_rate(speed) if info.kind == "bike" else 0.0)
	model.animate(speed, drive_state.steer, delta)
	# 바퀴 구르는 소리: 빠를수록 크게 (오토바이는 조금 더 크게).
	Audio.set_loop("kick_roll_loop", clampf(speed / maxf(drive_state.stats.top, 0.1), 0.0, 1.0) * (0.35 if info.kind == "bike" else 0.5), delta)
	_place_body()


## 움직인 뒤: 순간이동이면 떠나기 전 자리에 세우고, 벽에 막혔으면 그만큼 느려진다.
func after_move(delta: float, before: Vector3) -> void:
	if state != State.RIDING or model == null:
		return
	if Vector2(before.x - _last_pos.x, before.z - _last_pos.z).length() > 4.0:
		dismount(false)
		return
	if delta > 0.0:
		drive_state.after_move((player.global_position - before) / delta)
	_last_pos = player.global_position
	_last_yaw = drive_state.yaw


## 몸 · 탈것: 바닥을 축으로 안쪽으로 눕고(lean) 가속 · 브레이크에 앞뒤로 숙인다(pitch). 몸은 안장 높이(lift)만큼 올라 앉는다.
func _place_body() -> void:
	var basis: Basis = Basis(Vector3.UP, drive_state.yaw) * Basis(Vector3.BACK, drive_state.lean) * Basis(Vector3.RIGHT, drive_state.pitch)
	var height: float = player.body_rest_height() + info.lift
	player.body.transform = Transform3D(basis, basis * Vector3(0.0, height, 0.0))
	model.transform = Transform3D(Basis(), Vector3(0.0, -height, 0.0))


## 속도 (km/h, HUD · 테스트용).
func speed_kmh() -> float:
	return drive_state.speed * 3.6 if state == State.RIDING else 0.0


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---- HUD: 탈것 단추 · 속도계 ----

func _build_hud() -> void:
	_button = Button.new()
	_button.name = "GarageButton"
	_button.tooltip_text = "탈것"
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_stylebox_override("normal", EventHud._box(Color(0.98, 0.95, 0.88, 0.96), Color(0.36, 0.3, 0.28), 59, 5, 8))
	_button.add_theme_stylebox_override("hover", EventHud._box(Color(1.0, 0.98, 0.92), Color(0.36, 0.3, 0.28), 59, 5, 8))
	_button.add_theme_stylebox_override("pressed", EventHud._box(Color(0.98, 0.84, 0.55), Color(0.36, 0.3, 0.28), 59, 5, 8))
	_button.add_to_group(&"blocks_joystick")
	_button.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		quick_action())
	_button.draw.connect(_draw_icon)
	HudLayout.right_top(_button, Vector2(button_size, button_size), button_right, button_y)
	_button.visible = false
	hud.add_child.call_deferred(_button)
	_gauge = Label.new()
	_gauge.name = "Speedometer"
	_gauge.add_theme_font_size_override("font_size", 40)
	_gauge.add_theme_color_override("font_color", Color.WHITE)
	_gauge.add_theme_color_override("font_outline_color", Color(0.2, 0.16, 0.14))
	_gauge.add_theme_constant_override("outline_size", 10)
	_gauge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.anchor_left = 0.5
	_gauge.anchor_right = 0.5
	_gauge.anchor_top = 1.0
	_gauge.anchor_bottom = 1.0
	_gauge.offset_left = -160.0
	_gauge.offset_right = 160.0
	_gauge.offset_top = -470.0
	_gauge.offset_bottom = -410.0
	_gauge.visible = false
	hud.add_child.call_deferred(_gauge)


## 단추 · 속도계 보이기 (휴대폰을 연 동안 · 집 안 · 탈것이 없으면 숨김). 그림은 상태가 바뀔 때만 다시 그린다.
func _update_hud(force: bool) -> void:
	if _button == null:
		return
	var phone: PhoneWindow = hud.get_node_or_null("PhoneWindow") as PhoneWindow if hud != null else null
	var show: bool = Net.state == Net.State.ONLINE and not Net.vehicles.is_empty() and not Home.is_inside() and (phone == null or not phone.visible)
	if _button.visible != show:
		_button.visible = show
	var near: bool = state == State.OFF and parked != null and not parked.nearest_own(player.global_position, RIDE_RANGE).is_empty()
	var icon: String = "ride" if state == State.RIDING else ("near" if near else "call")
	if force or icon != _icon_state:
		_icon_state = icon
		_button.tooltip_text = {"ride": "세우기", "near": "타기", "call": "탈것 부르기"}[icon]
		_button.queue_redraw()
	_gauge.visible = state == State.RIDING


## 단추 그림: 자전거 (부르기 = 작은 종 · 곁에 있음 = 초록 바탕 · 타는 중 = 주황 바탕에 P).
func _draw_icon() -> void:
	var s: Vector2 = _button.size
	var c: Vector2 = s * 0.5
	var ink: Color = Color(0.36, 0.24, 0.14)
	match _icon_state:
		"ride":
			_button.draw_circle(c, s.x * 0.42, Color(0.98, 0.72, 0.4))
			var font: Font = _button.get_theme_default_font()
			var w: float = font.get_string_size("P", HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
			_button.draw_string(font, c + Vector2(-w * 0.5, 20.0), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, ink)
			return
		"near":
			_button.draw_circle(c, s.x * 0.42, Color(0.62, 0.86, 0.6))
	var r: float = s.x * 0.15
	var back: Vector2 = c + Vector2(-s.x * 0.2, s.y * 0.1)
	var front: Vector2 = c + Vector2(s.x * 0.2, s.y * 0.1)
	_button.draw_arc(back, r, 0.0, TAU, 20, ink, 5.0, true)
	_button.draw_arc(front, r, 0.0, TAU, 20, ink, 5.0, true)
	var seat: Vector2 = c + Vector2(-s.x * 0.06, -s.y * 0.1)
	var bar: Vector2 = c + Vector2(s.x * 0.14, -s.y * 0.17)
	_button.draw_polyline(PackedVector2Array([back, c + Vector2(0.0, s.y * 0.1), seat, back]), ink, 5.0, true)
	_button.draw_polyline(PackedVector2Array([c + Vector2(0.0, s.y * 0.1), bar, front]), ink, 5.0, true)
	_button.draw_line(bar, bar + Vector2(-s.x * 0.07, 0.0), ink, 5.0, true)
	if _icon_state == "call":
		# 부르기: 오른쪽 위 작은 말풍선.
		var b: Vector2 = c + Vector2(s.x * 0.24, -s.y * 0.26)
		_button.draw_circle(b, s.x * 0.1, Color("#3D8BFF"))
		_button.draw_circle(b, s.x * 0.035, Color.WHITE)


func _toast(text: String, good: bool) -> void:
	if toast_hud != null:
		toast_hud.show_toast(text, good)
