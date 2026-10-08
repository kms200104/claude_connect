class_name ParkedVehicles
extends Node3D
## 마을에 세워 둔 차고 탈것 (v19.1, 서버 veh_parked · welcome.parked = Net.parked). 내 것 · 친구 것 모두 보인다.
## 받침대를 세운 듯 살짝 기울여 바닥에 둔다. 주민이 가져오는 중(t 가 서버 시각보다 뒤)이면 VehicleCourier 가 타고 와서 세운다.
## 내 캐릭터가 탈 때는 take 로 그 모형을 넘겨주고(같은 물건이 그대로 타진다), 내리면 put 으로 그 자리에 다시 받는다.

## 세워 둔 탈것의 기울기 (받침대 쪽 = 왼쪽) · 핸들 꺾임.
const PARK_LEAN: float = 0.11
const PARK_STEER: float = 0.3

class Entry:
	var key: String = ""
	var vehicle_id: String = ""
	var owner: int = 0
	var shape: String = ""
	var at: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var arrive_ms: float = 0.0
	var model: VehicleModel = null
	var courier: VehicleCourier = null
	## 내가 방금 세워 서버 목록에 아직 없는 것 (목록이 올 때까지 지우지 않는다, 초).
	var pending: float = 0.0

var _entries: Dictionary[String, Entry] = {}


func _ready() -> void:
	add_to_group(&"parked_vehicles")
	Net.parked_changed.connect(_sync)
	_sync()


static func key_of(owner: int, vehicle_id: String) -> String:
	return "%d:%s" % [owner, vehicle_id]


func _process(delta: float) -> void:
	for e: Entry in _entries.values():
		if e.pending > 0.0:
			e.pending = maxf(0.0, e.pending - delta)


func _sync() -> void:
	var seen: Dictionary[String, bool] = {}
	for d: Dictionary in Net.parked:
		var key: String = key_of(int(d.get("o", 0)), str(d.get("v", "")))
		seen[key] = true
		var model_id: String = str(d.get("m", ""))
		var fit: Dictionary = d.get("f", {}) as Dictionary
		var shape: String = "%s|%s" % [model_id, JSON.stringify(fit, "", true)]
		var at: Vector3 = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
		var yaw: float = float(d.get("yaw", 0.0))
		var arrive: float = float(d.get("t", 0.0))
		var e: Entry = _entries.get(key)
		var moved: bool = e != null and (Vector2(e.at.x - at.x, e.at.z - at.z).length() > 0.6 or not is_equal_approx(e.arrive_ms, arrive))
		if e != null and moved and e.pending <= 0.0:
			# 다시 불렀다 (다른 곳으로 가져온다): 옛 모형을 치우고 새로.
			_remove(e)
			e = null
		if e == null:
			e = Entry.new()
			e.key = key
			e.vehicle_id = str(d.get("v", ""))
			e.owner = int(d.get("o", 0))
			_entries[key] = e
		e.pending = 0.0
		e.at = at
		e.yaw = yaw
		e.arrive_ms = arrive
		if e.model == null and e.courier == null:
			e.model = VehicleModel.new()
			e.model.name = "Parked_%s" % key.replace(":", "_")
			e.model.build(model_id, fit)
			e.shape = shape
			var npc: String = str(d.get("npc", ""))
			if arrive > Net.server_time_ms() + 300.0 and not npc.is_empty() and is_inside_tree():
				_start_courier(e, npc)
			else:
				add_child(e.model)
				_place(e)
		elif e.shape != shape:
			e.shape = shape
			e.model.build(model_id, fit)
		elif e.model != null and e.courier == null and e.model.get_parent() == self:
			_place(e)
	for key: String in _entries.keys():
		if not seen.has(key) and _entries[key].pending <= 0.0:
			_remove(_entries[key])


func _start_courier(e: Entry, npc: String) -> void:
	var courier: VehicleCourier = VehicleCourier.new()
	add_child(courier)
	var exclude: Array[RID] = []
	for body: Node in get_tree().get_nodes_in_group(&"player"):
		if body is CollisionObject3D:
			exclude.append((body as CollisionObject3D).get_rid())
	courier.setup(npc, e.model, _park_transform(e), e.arrive_ms, exclude)
	e.courier = courier
	courier.arrived.connect(func(model: VehicleModel) -> void:
		e.courier = null
		if not is_instance_valid(model):
			return
		if model.get_parent() != null:
			model.get_parent().remove_child(model)
		if _entries.get(e.key) != e:
			model.queue_free()
			return
		e.model = model
		add_child(model)
		_place(e))


## 세울 자리 (바닥 높이 · 받침대 기울기는 _place 가).
func _park_transform(e: Entry) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, e.yaw), Vector3(e.at.x, _ground_y(e.at), e.at.z))


func _place(e: Entry) -> void:
	if e.model == null:
		return
	e.model.global_transform = Transform3D(Basis(Vector3.UP, e.yaw) * Basis(Vector3.BACK, PARK_LEAN), Vector3(e.at.x, _ground_y(e.at), e.at.z))
	e.model.animate(0.0, PARK_STEER, 1.0)
	e.model.lights_on = false


func _ground_y(at: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 6.0, at.z), Vector3(at.x, -3.0, at.z))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	# 나무 · 건물 지붕이 아니라 땅 (낮은 곳)만.
	return float((hit["position"] as Vector3).y) if not hit.is_empty() and (hit["position"] as Vector3).y < 0.6 else 0.0


func _remove(e: Entry) -> void:
	if e.courier != null and is_instance_valid(e.courier):
		e.courier.queue_free()
	if e.model != null and is_instance_valid(e.model) and (e.model.get_parent() == self or e.model.get_parent() == null):
		e.model.queue_free()
	_entries.erase(e.key)


## 내 것 가운데 다 와서 세워 둔 탈것 (range m 안에서 가장 가까운 것, 없으면 빈 문자열).
func nearest_own(position: Vector3, max_range: float) -> String:
	var best: String = ""
	var best_d: float = max_range
	for e: Entry in _entries.values():
		if e.owner != Net.my_id or e.courier != null or e.model == null or e.model.get_parent() != self:
			continue
		var d: float = Vector2(e.at.x - position.x, e.at.z - position.z).length()
		if d <= best_d:
			best_d = d
			best = e.vehicle_id
	return best


## 내 그 탈것이 세워진(오는 중 포함) 자리 · 방향 · 도착했는지.
func spot_of(vehicle_id: String) -> Dictionary:
	var e: Entry = _entries.get(key_of(Net.my_id, vehicle_id))
	if e == null:
		return {}
	return {"at": e.at, "yaw": e.yaw, "arrived": e.courier == null}


## 내 캐릭터가 탄다: 세워 둔 모형을 넘겨준다 (부모에서 뗀 채, 없으면 null).
func take(vehicle_id: String) -> VehicleModel:
	var e: Entry = _entries.get(key_of(Net.my_id, vehicle_id))
	if e == null or e.courier != null or e.model == null:
		return null
	var model: VehicleModel = e.model
	e.model = null
	_entries.erase(e.key)
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	return model


## 내 캐릭터가 내려 세웠다: 그 모형을 지금 자리 · 방향에 받침대를 세워 둔다 (서버 목록이 오기 전에도 보이게).
func put(vehicle_id: String, model: VehicleModel, at: Vector3, yaw: float) -> void:
	var key: String = key_of(Net.my_id, vehicle_id)
	var old: Entry = _entries.get(key)
	if old != null:
		_remove(old)
	var e: Entry = Entry.new()
	e.key = key
	e.vehicle_id = vehicle_id
	e.owner = Net.my_id
	e.at = at
	e.yaw = yaw
	e.model = model
	e.shape = "%s|%s" % [model.model_id, JSON.stringify(model.fit, "", true)]
	e.pending = 2.0
	_entries[key] = e
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	add_child(model)
	model.scale = Vector3.ONE
	_place(e)


func count() -> int:
	return _entries.size()


func courier_count() -> int:
	var n: int = 0
	for e: Entry in _entries.values():
		if e.courier != null:
			n += 1
	return n
