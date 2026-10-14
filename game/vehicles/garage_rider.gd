class_name GarageRider
extends Node
## 내 캐릭터의 차고 탈것 (v19.1): 자전거 · 전기오토바이.
##   부르기: 휴대폰 "탈것" 앱 · HUD 탈것 단추 → 배달 로봇 솔봇이 몰고 와서 내 곁에 세워 두고 날아간다 (서버 veh_call, ParkedVehicles 가 그린다).
##   타기: 세워 둔 내 탈것 곁에서 상황 버튼 "타기" (또는 탈것 단추) → 서버가 받아 주면(veh_ride) 그 모형에 폴짝 올라앉는다.
##   세우기: HUD 탈것 단추(P) → 왼쪽(막히면 오른쪽)으로 내려서고 탈것은 받침대를 세워 그 자리에 남는다 (서버가 저장, 친구도 본다).
## 타는 동안은 Player 가 걷기 대신 drive 를 부르고, 움직임은 VehicleDrive, 모양은 VehicleModel.
## 자전거는 리그가 바퀴 속도에 맞춰 페달을 돌리고(set_pedal_rate) 그 위상으로 크랭크가 같이 돈다.
## 실내 · 순간이동 · 접속 끊김이면 그 자리에 바로 세운다 (서버도 같은 자리에 세워 둔다). 킥보드(KickboardRider)와는 동시에 못 탄다.
## 보트(v20): 물가에서 부르면 배달 로봇이 물길로 몰고 와 곁의 물 위에 띄워 둔다 (WaterRules). 타는 동안은 물 위에서만 움직이고(땅 · 해안 벽과
##   부딪치지 않고 수면 높이에 뜬다), 세우기(P)는 곁의 땅으로 폴짝 내려서기 — 서버가 그 땅을 받아 주면(veh_ride lx, lz) 내린다. 보트는 물에 남는다.

## v0.26 차량 · 내구도 · 들이받기: 타는 동안 크리처가 차 앞 · 옆(차체 크기)에 닿으면 Net.ram — 빠르면(ram.fast) 날아가고 차는
##   무게 비만큼 조금 느려지고, 느리면 크리처가 넘어지며 차가 확 느려진다. 넘어진 크리처에 닿아 있는 동안은 contact_top 넘게
##   빨라지지 못한다 (좀보이드처럼 밟고 넘어가기 어렵다). 벽 · 나무에 세게 부딪치면(갑자기 crash_min 넘게 느려짐) Net.vehicle_crash.
##   v0.27 배터리: 속도계 아래 "배터리 n%", 바닥나면 charge.crawl m/s 로만 (밀고 가듯). 배터리 팩(가방 '충전') · 공구 창고 곁에 서면 자동 충전.
##   속도계 아래 내구도, 0 이면 고장 — 내려서 "고치기"(고철 · 못) 또는 탈것 앱 정비. 부르기는 배달 로봇 또는 헬기 보급 낙하 (air).

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
## 보트 위에서 낚시하는 중 (v21): 보트는 서고, 캐릭터는 갑판에 서서 낚싯대를 쥔다 (서버도 내리지 않는다).
var fishing: bool = false
## 보트: 타는 동안 꺼 두는 충돌 (땅 · 물 막이 · 해안 벽), 내릴 땅을 서버에 청한 동안의 자리, 물결 시각.
var _saved_mask: int = -1
var _landing: Vector2 = Vector2.INF
var _bob_t: float = 0.0
## v0.26 내구도 표시 · 크리처별 다시 들이받을 수 있는 시각 · 벽 충돌 알림 간격.
var _hp_label: Label = null
var _rammed_at: Dictionary[String, int] = {}
var _crash_at: int = 0
## 공구 창고 충전을 다시 청할 수 있는 시각 · 배터리 바닥 안내를 했는지.
var _station_at: int = 0
var _empty_told: bool = false


func _ready() -> void:
	add_to_group(&"garage_rider")
	if player != null:
		player.garage_ride = self
	Net.mount_changed.connect(_on_mount_changed)
	Net.request_failed.connect(_on_failed)
	Net.vehicles_changed.connect(_on_vehicles_changed)
	Net.vehicle_done.connect(_on_vehicle_done)
	Net.vehicle_hp.connect(_on_vehicle_hp)
	Net.vehicle_charge.connect(_on_vehicle_charge)
	if hud != null:
		_build_hud()
	# v0.27 동승 (친구 차 빈자리).
	var ps: PassengerRide = PassengerRide.new()
	ps.name = "PassengerRide"
	ps.player = player
	ps.hud = hud
	ps.toast_hud = toast_hud
	add_child(ps)


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
		return "배달 로봇 솔봇이 가져오는 중이에요."
	if Net.vehicle_health(id) <= 0.0:
		return "고장났어요 — 곁에서 '고치기' (%s) 또는 탈것 앱에서 정비해요." % kit_text()
	if _flat(player.global_position, spot["at"]) > ride_range_of(id):
		return "세워 둔 곳 곁에서 탈 수 있어요."
	return ""


## 그 탈것에 올라탈 수 있는 거리 (보트는 물가에서 닿게 더 멀다 · 서버 값보다 조금 안쪽).
static func ride_range_of(id: String) -> float:
	var m: VehicleCatalog.Model = GameData.garage.model(str(Net.vehicle(id).get("model", "")))
	if m == null or not GameData.garage.is_water_kind(m.kind):
		return RIDE_RANGE
	return GameData.garage.ride_range(m.kind) - 0.4


## 보트를 타고 있는지.
func is_boat() -> bool:
	return info != null and GameData.garage.is_water_kind(info.kind) and state != State.OFF


## 물에 떠서 가는 중 (Player 가 중력을 쓰지 않는다).
func is_floating() -> bool:
	return is_boat() and (state == State.RIDING or state == State.MOUNTING)


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


## 고치기 재료 글자 ("고철 ×1 · 못 한 줌 ×1").
static func kit_text() -> String:
	var parts: PackedStringArray = []
	for k: Variant in GameData.garage.repair.get("kit", []):
		parts.append("%s ×%d" % [GameData.item_name(str(k.get("id", ""))), int(k.get("n", 1))])
	return " · ".join(parts)


## 세워 둔 고장난 탈것을 곁에서 재료로 고친다.
func repair_kit(id: String) -> void:
	Net.request("veh_repair", {"v": id, "how": "kit"})


## 배달 로봇(또는 air = 헬기 보급 낙하)에게 그 탈것을 가져다 달라고 한다 (내 곁 트인 자리에 세워 두고 간다).
func call_vehicle(id: String, air: bool = false) -> bool:
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
	var m: VehicleCatalog.Model = GameData.garage.model(str(v.get("model", "")))
	if m != null and GameData.garage.is_water_kind(m.kind):
		# 보트: 내 곁의 트인 물 위, 물가에서 바로 올라탈 수 있는 거리 안 (뱃머리는 물 쪽으로).
		var here: Vector2 = Vector2(player.global_position.x, player.global_position.z)
		var water: Vector2 = WaterRules.water_near(here, minf(GameData.garage.park_range(m.kind) - 0.8, ride_range_of(id) - 0.3))
		if water == Vector2.INF:
			_toast("보트는 물가에서 불러요 (곡교천 · 중앙공원 연못).", false)
			return false
		var out: Vector2 = (water - here)
		yaw = atan2(-out.x, -out.y) if out.length() > 0.1 else yaw
		at = Vector3(water.x, 0.0, water.y)
	if air and m != null and GameData.garage.is_water_kind(m.kind):
		_toast("보트는 헬기로 떨어뜨릴 수 없어요.", false)
		return false
	var msg: Dictionary = {"v": id, "x": at.x, "z": at.z, "yaw": yaw}
	if air:
		msg["mode"] = "air"
	Net.request("veh_call", msg)
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
	var near: String = parked.nearest_own(player.global_position, RIDE_RANGE, true) if parked != null else ""
	if not near.is_empty():
		mount(near)
		return
	var pick: String = _default_vehicle()
	var spot: Dictionary = parked.spot_of(pick) if parked != null else {}
	if not spot.is_empty() and not bool(spot.get("arrived", true)):
		_toast("배달 로봇 솔봇이 가져오는 중이에요.", true)
		return
	call_vehicle(pick)


func _default_vehicle() -> String:
	if not Net.vehicle(vehicle_id).is_empty():
		return vehicle_id
	return str(Net.vehicles[0].get("id", "")) if not Net.vehicles.is_empty() else ""


func _on_vehicle_done(result: Dictionary) -> void:
	if str(result.get("kind", "")) == "mod":
		_toast("%s 을(를) 달았어요! 내구도 %d/%d" % [GameData.item_name(str(result.get("item", ""))), int(result.get("hp", 0)), int(result.get("max", 0))], true)
		Audio.play_sfx("chop", -4.0, 0.7)
		return
	if str(result.get("kind", "")) == "refuel":
		_toast("%s 배터리 %d%%" % ["공구 창고 충전기로 가득 충전했어요!" if str(result.get("how", "")) == "station" else "배터리 팩으로 충전했어요!", roundi(float(result.get("charge", 0)) / maxf(1.0, float(result.get("max", 1))) * 100.0)], true)
		Audio.play_sfx("kick_latch", -6.0, 1.4)
		return
	if str(result.get("kind", "")) == "repair":
		_toast("고쳤어요! 내구도 %d%%%s" % [roundi(float(result.get("hp", 0)) / maxf(1.0, float(result.get("max", 1))) * 100.0), " (%s)" % Money.delta(-int(result.get("cost", 0))) if int(result.get("cost", 0)) > 0 else ""], true)
		Audio.play_sfx("chop", -6.0, 1.2)
		return
	if str(result.get("kind", "")) != "call":
		return
	var v: Dictionary = Net.vehicle(str(result.get("v", "")))
	var m: VehicleCatalog.Model = GameData.garage.model(str(v.get("model", "")))
	if str(result.get("npc", "")) == "heli":
		_toast("보급 헬기가 %s 을(를) 떨어뜨려 줄게요! 하늘을 봐요 (%s)" % [m.name if m != null else "탈것", Money.delta(-int(result.get("cost", 0)))], true)
		return
	_toast("배달 로봇 솔봇이 %s 을(를) 가져다줄게요!" % (m.name if m != null else "탈것"), true)


func _on_mount_changed(mount_wire: Dictionary) -> void:
	if mount_wire.is_empty() and _landing != Vector2.INF and state == State.RIDING:
		# 서버가 내릴 땅을 받아 줬다: 폴짝 내려선다.
		_hop_to_land(_landing)
		return
	if mount_wire.is_empty() or state != State.WAITING or str(mount_wire.get("v", "")) != vehicle_id:
		return
	_start(str(mount_wire.get("m", "")), mount_wire.get("f", {}) as Dictionary)


func _on_failed(kind: String, code: String) -> void:
	if kind == "veh_repair":
		_toast("고칠 재료가 모자라요 (%s)." % kit_text() if code == NetProtocol.ERR_NOT_ENOUGH_ITEMS else ("솔이 모자라요." if code == NetProtocol.ERR_NOT_ENOUGH_SOL else "고칠 수 없어요."), false)
		return
	if kind == "veh_mod":
		_toast("이미 달려 있어요." if code == NetProtocol.ERR_ALREADY_BOARDED else ("차량(ATV · 트럭)에만 달 수 있어요." if code == NetProtocol.ERR_BAD_PART else "달 수 없어요 (차량 곁에서)."), false)
		return
	if kind == "veh_refuel":
		if code == NetProtocol.ERR_NOT_ENOUGH_ITEMS:
			_toast("배터리 팩이 없어요.", false)
		elif code != NetProtocol.ERR_TOO_FAR:
			_toast("배터리가 가득해요." if code == NetProtocol.ERR_BAD_PART else "충전할 수 없어요 (탈것 곁에서).", code == NetProtocol.ERR_BAD_PART)
		return
	if kind == "veh_call" and code == NetProtocol.ERR_NOT_ENOUGH_SOL:
		_toast("헬기 보급은 %s 이 들어요." % Money.short(int(GameData.garage.delivery.get("air_cost", 0))), false)
		return
	if kind == "veh_call":
		_toast("부를 수 없어요." if code != NetProtocol.ERR_CANT_RIDE else "실내 · 낚시 중에는 부를 수 없어요.", false)
		return
	if kind == "veh_ride" and _landing != Vector2.INF and state == State.RIDING:
		# 내릴 땅을 서버가 받아 주지 않았다: 계속 탄다.
		_landing = Vector2.INF
		player.set_input_lock(&"garage_ride", false)
		_toast("여기서는 내릴 수 없어요. 물가 가까이 가요.", false)
		return
	if kind == "veh_call" and code == NetProtocol.ERR_NOT_ON_WATER:
		_toast("보트는 물가에서 불러요.", false)
		return
	if kind != "veh_ride" or state != State.WAITING:
		return
	_give_back()
	if code == NetProtocol.ERR_VEHICLE_BROKEN:
		_toast("고장났어요 — 곁에서 '고치기' (%s) 또는 탈것 앱에서 정비해요." % kit_text(), false)
		return
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
	var boat: bool = GameData.garage.is_water_kind(info.kind)
	var ground_y: float = WaterRules.level_at(Vector2(_spot.x, _spot.z)) if boat else player.global_position.y
	var ground: Transform3D = Transform3D(Basis(Vector3.UP, _spot_yaw), Vector3(_spot.x, ground_y, _spot.z))
	model.floating = false
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	if boat:
		# 물 위로 폴짝: 땅 · 물 막이 · 해안 벽과 부딪치지 않게 충돌을 끈다 (물 밖으로는 drive 가 막는다).
		_saved_mask = player.collision_mask
		player.collision_mask = 0
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
			player.rig.set_riding(info.pose)
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


## 세우기 (탈것 단추 P): 옆으로 내려서고 탈것은 그 자리에 받침대를 세워 둔다.
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
	if is_boat():
		# 보트: 곁의 땅을 찾아 서버에 청한다 (받아 주면 _hop_to_land).
		if _landing != Vector2.INF:
			return
		var here: Vector2 = Vector2(player.global_position.x, player.global_position.z)
		var land: Vector2 = WaterRules.landing_near(here, 5.5)
		if land == Vector2.INF:
			_toast("물가 가까이에서 내릴 수 있어요.", false)
			return
		_landing = land
		drive_state.speed = 0.0
		player.velocity = Vector3.ZERO
		player.set_input_lock(&"garage_ride", true)
		Net.request("veh_ride", {"v": "", "lx": land.x, "lz": land.y})
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


## 보트에서 곁의 땅으로 폴짝 내려선다 (보트는 물 위 그 자리에 남는다).
func _hop_to_land(land: Vector2) -> void:
	_landing = Vector2.INF
	Audio.set_loop("kick_roll_loop", 0.0, 10.0)
	state = State.DISMOUNTING
	player.set_input_lock(&"garage_ride", true)
	drive_state.speed = 0.0
	player.rig.set_riding("")
	var yaw: float = drive_state.yaw
	var boat_at: Vector3 = player.global_position
	var ground: Transform3D = Transform3D(Basis(Vector3.UP, yaw), boat_at)
	var from: Vector3 = player.global_position
	var to: Vector3 = Vector3(land.x, 0.05, land.y)
	var face: float = atan2(-(to.x - from.x), -(to.z - from.z))
	if _seq != null and _seq.is_valid():
		_seq.kill()
	var hop: Callable = func(t: float) -> void:
		var k: float = t * t * (3.0 - 2.0 * t)
		player.global_position = from.lerp(to, k) + Vector3(0.0, sin(k * PI) * 0.5, 0.0)
		player.body.transform = Transform3D(Basis(Vector3.UP, lerp_angle(yaw, face, k)), Vector3(0.0, player.body_rest_height() + info.lift * (1.0 - k), 0.0))
		if model != null:
			model.global_transform = ground
	var done: Callable = func() -> void:
		Audio.play_sfx("fish_plop", -10.0, 1.3)
		_hand_to_parked(ground.origin, yaw)
		_finish()
	_seq = create_tween()
	_seq.tween_method(hop, 0.0, 1.0, 0.55)
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
	_landing = Vector2.INF
	fishing = false
	if _saved_mask >= 0 and player != null:
		player.collision_mask = _saved_mask
		_saved_mask = -1
		# 보트에서 갑자기 내렸다 (순간이동 · 접속 끊김): 물 위에 서 있지 않게 곁의 땅으로.
		var here: Vector2 = Vector2(player.global_position.x, player.global_position.z)
		if not WaterRules.is_land(here) and not Home.is_inside():
			var land: Vector2 = WaterRules.landing_near(here, 30.0)
			if land != Vector2.INF:
				player.global_position = Vector3(land.x, 0.1, land.y)
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
		_gauge.text = ("R · %d km/h" if drive_state.speed < -0.05 else "%d km/h") % roundi(speed_kmh())
		var health: float = Net.vehicle_health(vehicle_id)
		var battery: float = Net.vehicle_battery(vehicle_id)
		_hp_label.text = "내구도 %d%%" % roundi(health * 100.0) + ("" if battery < 0.0 else " · 배터리 %d%%" % roundi(battery * 100.0))
		_check_station()
		_hp_label.add_theme_color_override("font_color", Color("#7EE08A") if health > 0.6 else (Color("#F2D05A") if health > 0.3 else Color("#FF6A5A")))


## 차고가 바뀌었다 (부품을 바꿨으면 타고 있는 모양도 바꾼다).
func _on_vehicles_changed() -> void:
	if model == null or state == State.WAITING:
		return
	var v: Dictionary = Net.vehicle(vehicle_id)
	if v.is_empty():
		return
	model.set_cargo((v.get("cargo", []) as Array).size() if v.get("cargo") is Array else 0)
	model.set_mods(v.get("mods", []) as Array if v.get("mods") is Array else [])
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
	var boat: bool = is_boat()
	var v: Vector3 = drive_state.step(move_dir, amount, 1.0 if boat else (drive_state.stats.wade if player.wading else 1.0), delta)
	if boat:
		v = _keep_on_water(v, delta)
	elif _ram_check(delta):
		v = drive_state.forward() * drive_state.speed
	# 배터리가 바닥나면 밀고 가듯 천천히.
	if Net.vehicle_battery(vehicle_id) == 0.0:
		var crawl: float = float(GameData.garage.charge.get("crawl", 1.4))
		if absf(drive_state.speed) > crawl:
			drive_state.speed = move_toward(drive_state.speed, signf(drive_state.speed) * crawl, 6.0 * delta)
			drive_state.accel = minf(drive_state.accel, 0.0)
		v = drive_state.forward() * drive_state.speed
	player.velocity.x = v.x
	player.velocity.z = v.z
	var speed: float = drive_state.speed
	# 후진: 자전거는 페달을 멈추고(프리휠) 카약은 거꾸로 젓는다.
	var pedal_speed: float = absf(speed) if info.kind == "boat" else maxf(speed, 0.0)
	player.rig.set_pedal_rate(model.pedal_rate(pedal_speed) if info.pose in CharacterRig.PHASED_RIDES else 0.0)
	model.animate(speed, drive_state.steer, delta)
	# 바퀴 구르는 소리: 빠를수록 크게 (오토바이는 조금 더 크게). 보트는 물 가르는 소리 대신 조용히.
	Audio.set_loop("kick_roll_loop", clampf(absf(speed) / maxf(drive_state.stats.top, 0.1), 0.0, 1.0) * (0.35 if info.kind == "bike" else (0.2 if boat else 0.5)), delta)
	_place_body()


## 보트: 다음 자리가 물이 아니면 물가를 따라 미끄러지고(한 축씩), 그래도 막히면 선다 (쿵).
func _keep_on_water(v: Vector3, delta: float) -> Vector3:
	var p: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var step: Vector2 = Vector2(v.x, v.z) * delta
	if WaterRules.is_water(p + step * 3.0):
		return v
	for along: Vector2 in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		if along.length() > 0.0001 and WaterRules.is_water(p + along * 3.0):
			var keep: Vector2 = along / delta
			drive_state.speed *= 0.97
			return Vector3(keep.x, 0.0, keep.y)
	if absf(drive_state.speed) > 1.5:
		Prefs.vibrate(40, 0.4)
		Audio.play_sfx("fish_plop", -12.0, 0.7)
	drive_state.speed = 0.0
	return Vector3.ZERO


## 움직인 뒤: 순간이동이면 떠나기 전 자리에 세우고, 벽에 막혔으면 그만큼 느려진다.
func after_move(delta: float, before: Vector3) -> void:
	if state != State.RIDING or model == null:
		return
	if Vector2(before.x - _last_pos.x, before.z - _last_pos.z).length() > 4.0:
		dismount(false)
		return
	if is_boat():
		# 수면 높이에 뜬다.
		player.global_position.y = WaterRules.level_at(Vector2(player.global_position.x, player.global_position.z))
		player.velocity.y = 0.0
	if delta > 0.0:
		var was: float = absf(drive_state.speed)
		drive_state.after_move((player.global_position - before) / delta)
		# 벽 · 나무에 세게 부딪쳤다 → 탈것이 닳는다 (서버가 그 탈것 최고 속도까지만 믿는다).
		var drop: float = was - absf(drive_state.speed)
		var now_ms: int = Time.get_ticks_msec()
		if not is_boat() and drop > float(GameData.garage.repair.get("crash_min", 3.0)) and now_ms >= _crash_at:
			_crash_at = now_ms + 500
			Net.vehicle_crash(drop)
			Prefs.vibrate(120, 0.8)
			Audio.play_sfx("chop", -2.0, 0.4)
	_last_pos = player.global_position
	_last_yaw = drive_state.yaw


## 크리처와 닿았는지 보고 들이받는다 (빠르기를 바꿨으면 true). 차체 크기 = 바퀴 자리 + 바퀴 + 여유.
func _ram_check(delta: float) -> bool:
	if Net.creatures.is_empty() or info == null:
		return false
	var field: CreatureField = get_tree().get_first_node_in_group(&"creature_field") as CreatureField
	if field == null:
		return false
	var rules: Dictionary = GameData.survival.ram
	var fast: float = float(rules.get("fast", 4.2))
	var f: Vector3 = drive_state.forward()
	var right: Vector3 = Vector3(-f.z, 0.0, f.x)
	var front: float = absf(info.anchor("axle_f").z) + info.wheel + 0.3
	var back: float = absf(info.anchor("axle_r").z) + info.wheel
	var half: float = (0.85 if info.style == "truck" else 0.66) if info.kind == "car" else 0.35
	var now_ms: int = Time.get_ticks_msec()
	var touching: bool = false
	var changed: bool = false
	for id: String in Net.creatures:
		var at: Vector3 = field.actor_position(id)
		if at == Vector3.INF:
			continue
		var rel: Vector3 = (at - player.global_position) * Vector3(1, 0, 1)
		var along: float = rel.dot(f) * signf(drive_state.speed if absf(drive_state.speed) > 0.05 else 1.0)
		if absf(rel.dot(right)) > half + 0.3 or along < -0.2 or along > front + 0.3:
			continue
		var c: Dictionary = Net.creatures[id]
		if int(c.get("f", 0)) == 1:
			continue
		# 빨라지기 어렵게 하는 건 앞을 막은 크리처 · 차 밑에 넘어진 크리처 (옆에 붙은 건 아니다).
		if int(c.get("f", 0)) == 2 or along > front * 0.45:
			touching = true
		var speed: float = absf(drive_state.speed)
		if speed < 0.4 or now_ms < int(_rammed_at.get(id, 0)):
			continue
		_rammed_at[id] = now_ms + 650
		Net.ram(id, speed, f * signf(drive_state.speed))
		var kind: SurvivalRules.CreatureKind = GameData.survival.creature_kinds.get(str(c.get("k", "")))
		var m: float = kind.mass if kind != null else 70.0
		if speed >= fast:
			# 무거운 탈것일수록 덜 느려진다 (운동량).
			drive_state.speed *= 1.0 - (1.0 + float(rules.get("restitution", 0.5))) * m / (info.mass + m)
			Prefs.vibrate(70, 0.6)
		else:
			# 느리게 닿았다: 크리처가 넘어지고 차가 확 느려진다 (벽처럼 딱 서지는 않는다).
			drive_state.speed *= float(rules.get("slow_keep", 0.45))
			Prefs.vibrate(40, 0.4)
		changed = true
	# 넘어진 · 서 있는 크리처에 닿아 있는 동안은 빨라지기 어렵다.
	var top: float = float(rules.get("contact_top", 1.6))
	if touching and drive_state.speed > top and drive_state.speed < fast:
		drive_state.speed = move_toward(drive_state.speed, top, 8.0 * delta)
		drive_state.accel = minf(drive_state.accel, 0.0)
		changed = true
	return changed


## 공구 창고(공용 작업대) 곁에 서면 공짜로 가득 충전.
func _check_station() -> void:
	var battery: float = Net.vehicle_battery(vehicle_id)
	if battery < 0.0 or battery > 0.97 or absf(drive_state.speed) > 0.4 or Time.get_ticks_msec() < _station_at:
		return
	var range_m: float = float(GameData.garage.charge.get("station_range", 8.0)) - 1.0
	for b: CraftingRules.Bench in GameData.crafting.benches:
		if Vector2(b.position.x - player.global_position.x, b.position.z - player.global_position.z).length() <= range_m:
			_station_at = Time.get_ticks_msec() + 5000
			Net.request("veh_refuel", {"v": vehicle_id, "how": "station"})
			return


## 가방 "차에 달기": 타는 (아니면 곁에 세워 둔) 내 차량에 개조 아이템 (스파이크 범퍼 · 철판 장갑).
func install_mod(item_id: String) -> void:
	var id: String = vehicle_id if state == State.RIDING else (parked.nearest_own(player.global_position, RIDE_RANGE + 1.0) if parked != null else "")
	if id.is_empty():
		_toast("달 차량 곁에서 써요 (타고 있거나 세워 둔 곁).", false)
		return
	Net.request("veh_mod", {"v": id, "item": item_id})


## 가방 "충전": 타는 탈것 (아니면 곁에 세워 둔 내 탈것) 에 배터리 팩 하나.
func refuel_pack() -> void:
	var id: String = vehicle_id if state == State.RIDING else (parked.nearest_own(player.global_position, RIDE_RANGE + 1.0) if parked != null else "")
	if id.is_empty():
		_toast("충전할 탈것 곁에서 써요 (타고 있거나 세워 둔 곁).", false)
		return
	if Net.vehicle_battery(id) < 0.0:
		_toast("배터리가 없는 탈것이에요.", false)
		return
	Net.request("veh_refuel", {"v": id, "how": "pack"})


func _on_vehicle_charge(info_c: Dictionary) -> void:
	if str(info_c.get("v", "")) != vehicle_id:
		return
	if bool(info_c.get("empty", false)):
		if not _empty_told:
			_empty_told = true
			_toast("배터리가 다 됐어요! 배터리 팩으로 충전하거나 공구 창고 곁에서 충전해요 (지금은 천천히만).", false)
	else:
		_empty_told = false


func _on_vehicle_hp(info_hp: Dictionary) -> void:
	if str(info_hp.get("v", "")) != vehicle_id:
		return
	if bool(info_hp.get("broken", false)):
		if state == State.RIDING:
			dismount()
		_toast("고장났어요! 곁에서 '고치기' (%s) 또는 탈것 앱에서 정비해요." % kit_text(), false)
		Prefs.vibrate(200, 1.0)
	elif str(info_hp.get("why", "")) == "crash" and Net.vehicle_health(vehicle_id) < 0.35:
		_toast("쾅! 많이 상했어요 (내구도 %d%%)" % roundi(Net.vehicle_health(vehicle_id) * 100.0), false)


## 몸 · 탈것: 바닥을 축으로 안쪽으로 눕고(lean) 가속 · 브레이크에 앞뒤로 숙인다(pitch). 몸은 안장 높이(lift)만큼 올라 앉는다.
func _place_body() -> void:
	var basis: Basis = Basis(Vector3.UP, drive_state.yaw) * Basis(Vector3.BACK, drive_state.lean) * Basis(Vector3.RIGHT, drive_state.pitch)
	# 낚시하는 동안은 갑판에 선다 (카약처럼 낮게 앉는 배도 발이 물에 잠기지 않게).
	var height: float = player.body_rest_height() + (maxf(info.lift, 0.12) if fishing else info.lift)
	if is_boat():
		# 물결에 출렁 (멈춰 있을수록 조금 더).
		_bob_t += get_physics_process_delta_time()
		var calm: float = 1.0 - clampf(absf(drive_state.speed) / 4.0, 0.0, 0.7)
		height += sin(_bob_t * 1.7) * 0.025 * calm
		basis = basis * Basis(Vector3.BACK, sin(_bob_t * 1.3) * 0.03 * calm)
	player.body.transform = Transform3D(basis, basis * Vector3(0.0, height, 0.0))
	model.transform = Transform3D(Basis(), Vector3(0.0, -height, 0.0))


## 보트 위 낚시 시작 · 끝 (FishingController). 보트가 아니면 아무것도 하지 않는다.
func set_fishing(on: bool) -> void:
	if fishing == on or (on and (state != State.RIDING or not is_boat())):
		return
	fishing = on
	if on:
		drive_state.speed = 0.0
		drive_state.throttle = 0.0
		drive_state.yaw_rate = 0.0
		player.velocity = Vector3.ZERO
		# 타는 자세를 풀어야 낚싯대가 손에 보이고 던지는 동작이 나온다.
		player.rig.set_riding("")
	elif state == State.RIDING and info != null:
		player.rig.set_riding(info.pose)


## 속도 (km/h, HUD · 테스트용).
func speed_kmh() -> float:
	return absf(drive_state.speed) * 3.6 if state == State.RIDING else 0.0


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
	_hp_label = Label.new()
	_hp_label.name = "VehicleHealth"
	_hp_label.add_theme_font_size_override("font_size", 28)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.2, 0.16, 0.14))
	_hp_label.add_theme_constant_override("outline_size", 8)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.anchor_left = 0.5
	_hp_label.anchor_right = 0.5
	_hp_label.anchor_top = 1.0
	_hp_label.anchor_bottom = 1.0
	_hp_label.offset_left = -160.0
	_hp_label.offset_right = 160.0
	_hp_label.offset_top = -412.0
	_hp_label.offset_bottom = -372.0
	_hp_label.visible = false
	hud.add_child.call_deferred(_hp_label)


## 단추 · 속도계 보이기 (휴대폰을 연 동안 · 집 안 · 탈것이 없으면 숨김). 그림은 상태가 바뀔 때만 다시 그린다.
func _update_hud(force: bool) -> void:
	if _button == null:
		return
	var phone: PhoneWindow = hud.get_node_or_null("PhoneWindow") as PhoneWindow if hud != null else null
	var show: bool = Net.state == Net.State.ONLINE and not Net.vehicles.is_empty() and not Home.is_inside() and (phone == null or not phone.visible)
	if _button.visible != show:
		_button.visible = show
	var near: bool = state == State.OFF and parked != null and not parked.nearest_own(player.global_position, RIDE_RANGE, true).is_empty()
	var icon: String = "ride" if state == State.RIDING else ("near" if near else "call")
	if force or icon != _icon_state:
		_icon_state = icon
		_button.tooltip_text = {"ride": "세우기", "near": "타기", "call": "탈것 부르기"}[icon]
		_button.queue_redraw()
	_gauge.visible = state == State.RIDING
	_hp_label.visible = state == State.RIDING


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
