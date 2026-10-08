class_name GarageRider
extends Node
## 내 캐릭터의 차고 탈것 타기 (v19): 자전거 · 전기오토바이. 휴대폰 "탈것" 앱이나 HUD 탈것 단추로 올라타고, 상황 버튼 "내리기"로 내린다.
## 서버가 받아 줘야(veh_ride → 답의 mount) 올라탄다. 타는 동안은 Player 가 걷기 대신 drive 를 부르고,
## 움직임은 VehicleDrive (자전거: 페달 · 전기오토바이: 스로틀 · 회생 제동 · 가속도 다듬기), 모양은 VehicleModel.
## 자전거는 리그가 바퀴 속도에 맞춰 페달을 돌리고(set_pedal_rate) 그 위상으로 크랭크가 같이 돈다.
## 실내 · 순간이동 · 접속 끊김 · 차고에서 사라지면(팔기) 바로 내린다. 킥보드(KickboardRider)와는 동시에 못 탄다.

signal changed(riding: bool)

enum State { OFF, WAITING, MOUNTING, RIDING, DISMOUNTING }

@export var player: Player
## 안내 문구 (낚시 HUD 의 토스트).
@export var toast_hud: FishingHud
## 탈것 단추 · 속도계를 붙일 HUD.
@export var hud: CanvasLayer

@export_group("Layout")
@export var button_size: float = 118.0
## 오른쪽 단추 줄: 작은 지도(410~640) 아래, 휴대폰 단추(1010) 위.
@export var button_y: float = 870.0

var state: State = State.OFF
## 타고 있는(또는 마지막으로 탄) 차고 탈것 id.
var vehicle_id: String = ""
var model: VehicleModel = null
var info: VehicleCatalog.Model = null
var drive_state: VehicleDrive = VehicleDrive.new()
var _fit: Dictionary = {}
var _last_pos: Vector3 = Vector3.ZERO
var _seq: Tween = null
var _button: Button = null
var _gauge: Label = null


func _ready() -> void:
	add_to_group(&"garage_rider")
	if player != null:
		player.garage_ride = self
	Net.mount_changed.connect(_on_mount_changed)
	Net.request_failed.connect(_on_failed)
	Net.vehicles_changed.connect(_on_vehicles_changed)
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
	if state != State.OFF:
		return "이미 타고 있어요."
	if player.vehicle != null and player.vehicle.is_active():
		return "킥보드를 먼저 접어 넣어요."
	if player.is_input_locked():
		return "지금은 탈 수 없어요."
	if Net.state != Net.State.ONLINE:
		return "마을에 접속해야 탈 수 있어요."
	if Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position)):
		return "실내에서는 탈 수 없어요."
	if player.wading or not player.is_on_floor():
		return "물이 없는 평평한 땅에서 타요."
	return ""


## 올라타기를 서버에 청한다 (답이 오면 올라탄다).
func mount(id: String) -> bool:
	var problem: String = mount_problem(id)
	if not problem.is_empty():
		_toast(problem, false)
		return false
	vehicle_id = id
	state = State.WAITING
	Net.request("veh_ride", {"v": id})
	return true


## 탈것 단추 · 앱의 "타기"를 다시 누르면 내린다.
func toggle(id: String = "") -> void:
	if state == State.RIDING:
		dismount()
	elif state == State.OFF:
		var pick: String = id if not id.is_empty() else _default_vehicle()
		if pick.is_empty():
			_toast("휴대폰 탈것 앱에서 자전거 · 오토바이를 살 수 있어요.", false)
			return
		mount(pick)


func _default_vehicle() -> String:
	if not Net.vehicle(vehicle_id).is_empty():
		return vehicle_id
	return str(Net.vehicles[0].get("id", "")) if not Net.vehicles.is_empty() else ""


func _on_mount_changed(mount_wire: Dictionary) -> void:
	if mount_wire.is_empty():
		return
	if state != State.WAITING:
		return
	_start(str(mount_wire.get("m", "")), mount_wire.get("f", {}) as Dictionary)


func _on_failed(kind: String, code: String) -> void:
	if kind != "veh_ride" or state != State.WAITING:
		return
	state = State.OFF
	_toast("지금은 탈 수 없어요." if code == NetProtocol.ERR_CANT_RIDE else "탈 수 없어요 (%s)." % code, false)


## 올라탄다: 탈것이 톡 나타나고(퐁) 캐릭터가 폴짝 올라 앉는다.
func _start(model_id: String, fit: Dictionary) -> void:
	info = GameData.garage.model(model_id)
	if info == null:
		state = State.OFF
		return
	_fit = fit.duplicate()
	state = State.MOUNTING
	player.set_input_lock(&"garage_ride", true)
	player.velocity = Vector3.ZERO
	drive_state.setup(info, GameData.garage.stats(model_id, _fit), GameData.garage.kinds.get(info.kind, {}), player.body.rotation.y)
	model = VehicleModel.new()
	model.name = "Vehicle"
	player.rig.add_child(model)
	model.build(model_id, _fit)
	model.position = Vector3(0.0, -player.body_rest_height(), 0.0)
	model.scale = Vector3.ONE * 0.05
	Puff.burst(player.get_parent(), player.global_position + Vector3(0.0, 0.3, 0.0), Color(1, 1, 1, 0.85), 6, 0.6, 0.4, 0.1, 0.5)
	Audio.play_sfx("kick_latch", -4.0)
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = create_tween()
	_seq.tween_property(model, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_seq.tween_callback(func() -> void: player.rig.set_riding(info.kind))
	# 폴짝: 몸이 살짝 떴다가 안장 높이에 앉는다.
	_seq.tween_method(_hop, 0.0, 1.0, 0.32)
	_seq.tween_callback(_on_mounted)
	changed.emit(true)


func _hop(t: float) -> void:
	var lift: float = info.lift * t + sin(t * PI) * 0.12
	player.body.transform = Transform3D(Basis(Vector3.UP, drive_state.yaw), Vector3(0.0, player.body_rest_height() + lift, 0.0))
	if model != null:
		model.position = Vector3(0.0, -player.body_rest_height() - lift, 0.0)


func _on_mounted() -> void:
	state = State.RIDING
	player.set_input_lock(&"garage_ride", false)
	_last_pos = player.global_position
	_update_hud()


## 내린다. animated 가 거짓이면 바로 (순간이동 · 실내 · 접속 끊김).
func dismount(animated: bool = true) -> void:
	if state == State.OFF or state == State.DISMOUNTING and animated:
		return
	if state != State.WAITING:
		Net.request("veh_ride", {"v": ""})
	Audio.set_loop("kick_roll_loop", 0.0, 10.0)
	drive_state.speed = 0.0
	player.velocity = Vector3(0.0, player.velocity.y, 0.0)
	if not animated or model == null:
		_finish()
		return
	state = State.DISMOUNTING
	player.set_input_lock(&"garage_ride", true)
	player.rig.set_riding("")
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = create_tween()
	_seq.tween_method(func(t: float) -> void: _hop(1.0 - t), 0.0, 1.0, 0.25)
	_seq.tween_property(model, "scale", Vector3.ONE * 0.05, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_seq.tween_callback(_finish)


func _finish() -> void:
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = null
	if model != null:
		Puff.burst(player.get_parent(), player.global_position + Vector3(0.0, 0.3, 0.0), Color(1, 1, 1, 0.85), 5, 0.5, 0.35, 0.1, 0.45)
		model.queue_free()
	model = null
	if player != null:
		player.rig.set_riding("")
		player.set_input_lock(&"garage_ride", false)
		player.body.transform = Transform3D(Basis(Vector3.UP, drive_state.yaw), Vector3(0.0, player.body_rest_height(), 0.0))
	state = State.OFF
	changed.emit(false)
	_update_hud()


func _process(_delta: float) -> void:
	if state == State.OFF or state == State.WAITING:
		_update_hud()
		return
	var indoor: bool = Home.is_inside() or (GameData.shop != null and GameData.shop.is_inside(player.global_position))
	if indoor or Net.state != Net.State.ONLINE or Net.vehicle(vehicle_id).is_empty():
		dismount(false)
		return
	# 크랭크는 리그가 이 프레임에 센 페달 위상으로 (리그는 Player 아래라 이 노드보다 먼저 돈다).
	if model != null:
		model.set_pedal(player.rig.pedal_phase())
	_update_hud()


## 차고가 바뀌었다 (부품을 바꿨으면 타고 있는 모양도 바꾼다).
func _on_vehicles_changed() -> void:
	if model == null:
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


## 움직인 뒤: 순간이동이면 내리고, 벽에 막혔으면 그만큼 느려진다.
func after_move(delta: float, before: Vector3) -> void:
	if state != State.RIDING or model == null:
		return
	if Vector2(before.x - _last_pos.x, before.z - _last_pos.z).length() > 4.0:
		dismount(false)
		return
	if delta > 0.0:
		drive_state.after_move((player.global_position - before) / delta)
	_last_pos = player.global_position


## 몸 · 탈것: 바닥을 축으로 안쪽으로 눕고(lean) 가속 · 브레이크에 앞뒤로 숙인다(pitch). 몸은 안장 높이(lift)만큼 올라 앉는다.
func _place_body() -> void:
	var basis: Basis = Basis(Vector3.UP, drive_state.yaw) * Basis(Vector3.BACK, drive_state.lean) * Basis(Vector3.RIGHT, drive_state.pitch)
	var height: float = player.body_rest_height() + info.lift
	player.body.transform = Transform3D(basis, basis * Vector3(0.0, height, 0.0))
	model.position = Vector3(0.0, -height, 0.0)


## 속도 (km/h, HUD · 테스트용).
func speed_kmh() -> float:
	return drive_state.speed * 3.6 if state == State.RIDING else 0.0


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
		toggle())
	_button.draw.connect(_draw_icon)
	HudLayout.right_top(_button, Vector2(button_size, button_size), 24.0, button_y)
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


func _update_hud() -> void:
	if _button == null:
		return
	var phone: PhoneWindow = hud.get_node_or_null("PhoneWindow") as PhoneWindow if hud != null else null
	var show: bool = Net.state == Net.State.ONLINE and not Net.vehicles.is_empty() and not Home.is_inside() and (phone == null or not phone.visible)
	if _button.visible != show:
		_button.visible = show
	_button.queue_redraw()
	var riding: bool = state == State.RIDING
	_gauge.visible = riding
	if riding:
		_gauge.text = "%d km/h" % roundi(speed_kmh())


## 단추 그림: 바퀴 둘 + 몸체 (타는 중이면 주황 바탕).
func _draw_icon() -> void:
	var s: Vector2 = _button.size
	var c: Vector2 = s * 0.5
	var ink: Color = Color(0.36, 0.24, 0.14)
	if state == State.RIDING:
		_button.draw_circle(c, s.x * 0.42, Color(0.98, 0.72, 0.4))
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


func _toast(text: String, good: bool) -> void:
	if toast_hud != null:
		toast_hud.show_toast(text, good)
