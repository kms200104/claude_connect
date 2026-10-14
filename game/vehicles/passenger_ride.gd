class_name PassengerRide
extends Node
## 동승 (v0.27): 친구가 운전하는 차량(ATV 뒷자리 · 트럭 짐칸)의 빈자리에 같이 탄다 (서버 veh_board · veh_unboard · seat).
##   - 나: 상황 버튼 "같이 타기 · 이름" → 서버가 자리를 주면(veh_seat) 운전자 탈것의 그 자리에 앉아 매 물리 프레임 따라간다
##     (Player 가 걷기 대신 follow 를 부른다). 앉은 채 "공격" 등 상황 버튼은 그대로 쓴다. HUD "내리기" 단추로 옆에 내려선다.
##   - 친구 · 내가 운전: 동승한 사람(RemotePlayer)을 운전자 탈것 자리에 붙인다 (pin) — 운전자와 같은 프레임에 그려져 어긋나지 않는다.
## 운전자가 내리거나 떠나면 서버가 내린다 (seat d = 0).

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud

## 친구 차량 곁에서 같이 탈 수 있는 거리.
const BOARD_RANGE: float = 3.4
## 앉은 자세 (CharacterRig.RIDE_ANIMS).
const POSE: String = "boat"

## 내 자리 (탈것 좌표, 서버 veh_seat).
var _seat: Vector3 = Vector3.INF
var _driver: int = 0
var _button: Button = null
var _pinned: Dictionary[int, bool] = {}


func _ready() -> void:
	if player != null:
		player.passenger = self
	Net.seat_changed.connect(_on_seat_changed)
	Net.request_failed.connect(_on_failed)
	if hud != null:
		_build_button()


func is_active() -> bool:
	return _driver != 0 and _seat != Vector3.INF


## 이 자리에서 같이 탈 수 있는 친구 (빈자리가 있는 차량을 운전 중, 없으면 0).
func pick_target(pos: Vector3) -> int:
	if is_active() or player.is_riding():
		return 0
	for r: RemotePlayer in _remotes():
		var info: VehicleCatalog.Model = r.mount_model()
		if info == null or info.seats.is_empty() or Net.seats.has(r.player_id):
			continue
		if Vector2(r.global_position.x - pos.x, r.global_position.z - pos.z).length() > BOARD_RANGE:
			continue
		var taken: int = 0
		for id: int in Net.seats:
			if int(Net.seats[id].get("d", 0)) == r.player_id:
				taken += 1
		if taken < info.seats.size():
			return r.player_id
	return 0


func board(driver_id: int) -> void:
	Net.request("veh_board", {"p": driver_id})


func leave() -> void:
	if is_active():
		Net.request("veh_unboard", {})


## Player 가 동승하는 동안 물리 프레임마다 부른다: 운전자 탈것의 내 자리로.
func follow(delta: float) -> void:
	var t: Transform3D = _seat_transform(_driver, _seat)
	if t == Transform3D():
		player.velocity = Vector3.ZERO
		return
	if delta > 0.0:
		player.velocity = (t.origin - player.global_position) / delta
	player.global_position = t.origin
	player.body.transform = Transform3D(t.basis, Vector3(0.0, player.body_rest_height() + _lift(_seat), 0.0))
	player.rig.set_riding(POSE)
	player.rig.set_move_speed(0.0)


func _process(_delta: float) -> void:
	if _button != null:
		_button.visible = is_active()
	# 동승한 친구를 운전자 탈것 자리에 붙인다.
	for id: int in Net.seats:
		if id == Net.my_id:
			continue
		var r: RemotePlayer = _remote(id)
		if r == null:
			continue
		var d: int = int(Net.seats[id].get("d", 0))
		var info: VehicleCatalog.Model = _driver_model(d)
		var s: int = int(Net.seats[id].get("s", 0))
		if info == null or s < 0 or s >= info.seats.size():
			continue
		var t: Transform3D = _seat_transform(d, info.seats[s])
		if t == Transform3D():
			continue
		r.pin(t.origin, t.basis.get_euler().y, _lift(info.seats[s]))
		if r.rig != null:
			r.rig.set_riding(POSE)
		_pinned[id] = true
	for id: int in _pinned.keys():
		if not Net.seats.has(id):
			var r: RemotePlayer = _remote(id)
			if r != null:
				r.unpin()
				if r.rig != null:
					r.rig.set_riding("")
			_pinned.erase(id)


## 운전자 탈것의 그 자리 (월드, 방향 = 탈것 방향). 운전자를 못 찾으면 빈 Transform3D.
func _seat_transform(driver_id: int, seat: Vector3) -> Transform3D:
	var root: Node3D = null
	var yaw: float = 0.0
	if driver_id == Net.my_id and player.garage_ride != null and player.garage_ride.is_riding():
		root = player
		yaw = player.garage_ride.drive_state.yaw
	else:
		var r: RemotePlayer = _remote(driver_id)
		if r != null and r.body != null:
			root = r
			yaw = r.body.global_rotation.y
	if root == null:
		return Transform3D()
	var b: Basis = Basis(Vector3.UP, yaw)
	return Transform3D(b, root.global_position + b * Vector3(seat.x, 0.0, seat.z))


func _driver_model(driver_id: int) -> VehicleCatalog.Model:
	if driver_id == Net.my_id:
		return player.garage_ride.info if player.garage_ride != null and player.garage_ride.is_riding() else null
	var r: RemotePlayer = _remote(driver_id)
	return r.mount_model() if r != null else null


## 앉는 높이 → 몸을 올리는 높이 (골반이 자리보다 조금 위, VehicleModel.RIDER_HIP).
static func _lift(seat: Vector3) -> float:
	return seat.y + 0.06 - VehicleModel.RIDER_HIP.y


func _on_seat_changed(id: int) -> void:
	if id != Net.my_id:
		return
	var info: Dictionary = Net.seats.get(id, {})
	var was: bool = is_active()
	if info.is_empty():
		_driver = 0
		_seat = Vector3.INF
		if was:
			_step_off()
		return
	_driver = int(info.get("d", 0))
	var seat: Variant = info.get("seat", [])
	if seat is Array and (seat as Array).size() >= 3:
		_seat = Vector3(float(seat[0]), float(seat[1]), float(seat[2]))
	else:
		var m: VehicleCatalog.Model = _driver_model(_driver)
		var s: int = int(info.get("s", 0))
		_seat = m.seats[s] if m != null and s >= 0 and s < m.seats.size() else Vector3(0.0, 0.8, 0.6)
	if toast_hud != null and not was:
		toast_hud.show_toast("%s 님 차에 탔어요! 달리는 동안 크리처를 '공격'할 수 있어요" % GameData.player_name(_driver), true)
	Audio.play_sfx("kick_latch", -6.0)


## 자리에서 옆으로 내려선다.
func _step_off() -> void:
	var right: Vector3 = player.body.global_basis.x
	right.y = 0.0
	player.global_position += right.normalized() * 1.3 + Vector3(0.0, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	player.body.transform = Transform3D(Basis(Vector3.UP, player.body.global_rotation.y), Vector3(0.0, player.body_rest_height(), 0.0))
	player.rig.set_riding("")
	if toast_hud != null:
		toast_hud.show_toast("차에서 내렸어요", true)


func _on_failed(kind: String, code: String) -> void:
	if kind != "veh_board" or toast_hud == null:
		return
	toast_hud.show_toast("자리가 다 찼어요." if code == NetProtocol.ERR_VEHICLE_FULL else "같이 탈 수 없어요.", false)


func _remotes() -> Array[RemotePlayer]:
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	return replicator.remote_nodes() if replicator != null else []


func _remote(id: int) -> RemotePlayer:
	for r: RemotePlayer in _remotes():
		if r.player_id == id:
			return r
	return null


func _build_button() -> void:
	_button = Button.new()
	_button.name = "PassengerOffButton"
	_button.text = "내리기"
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 32)
	_button.add_theme_stylebox_override("normal", EventHud._box(Color(0.98, 0.95, 0.88, 0.96), Color(0.36, 0.3, 0.28), 30, 5, 12))
	_button.add_to_group(&"blocks_joystick")
	_button.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		leave())
	HudLayout.right_top(_button, Vector2(150.0, 96.0), 300.0, 1020.0)
	_button.visible = false
	hud.add_child.call_deferred(_button)
