class_name VehicleInfo
extends RefCounted
## 탈것 하나의 움직임 값 (data/vehicles/vehicles.json, v0.16). 속도 m/s, 가속 m/s², 각도 rad.

const PATH: String = "res://data/vehicles/vehicles.json"

var id: String = ""
var display_name: String = ""
## 리그 자세 (CharacterRig.RIDE_ANIMS 의 키).
var anim: String = ""
var max_speed: float = 7.0
## 한 번 찰 때 늘어나는 속도와 차는 동작 길이, 그중 땅을 미는 구간 (동작 시작부터 초).
var kick_boost: float = 1.4
var kick_time: float = 0.62
var kick_push: Vector2 = Vector2(0.2, 0.42)
## 그냥 미끄러질 때 · 조이스틱을 놓았을 때 · 반대로 밀어 브레이크 잡을 때 줄어드는 빠르기.
var coast_drag: float = 0.5
var idle_brake: float = 1.5
var brake: float = 6.0
## 빠를 때 가장 작게 도는 반지름 (m)과 거의 멈췄을 때 제자리에서 도는 빠르기 (rad/s).
var turn_radius: float = 1.5
var slow_turn: float = 2.4
var max_lean: float = 0.3
var max_steer: float = 0.55
## 물(여울)에 들어갔을 때 낼 수 있는 빠르기.
var wade_speed: float = 1.2

static var _all: Dictionary[String, VehicleInfo] = {}


static func of(vehicle_id: String) -> VehicleInfo:
	if _all.is_empty():
		_load()
	return _all.get(vehicle_id)


static func _load() -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var root: Dictionary = parsed
	for key: String in root:
		if key.begins_with("_") or not root[key] is Dictionary:
			continue
		var d: Dictionary = root[key]
		var v: VehicleInfo = VehicleInfo.new()
		v.id = key
		v.display_name = str(d.get("name", key))
		v.anim = str(d.get("anim", ""))
		v.max_speed = float(d.get("max_speed", v.max_speed))
		v.kick_boost = float(d.get("kick_boost", v.kick_boost))
		v.kick_time = float(d.get("kick_time", v.kick_time))
		var push: Array = d.get("kick_push", [v.kick_push.x, v.kick_push.y])
		v.kick_push = Vector2(float(push[0]), float(push[1]))
		v.coast_drag = float(d.get("coast_drag", v.coast_drag))
		v.idle_brake = float(d.get("idle_brake", v.idle_brake))
		v.brake = float(d.get("brake", v.brake))
		v.turn_radius = float(d.get("turn_radius", v.turn_radius))
		v.slow_turn = float(d.get("slow_turn", v.slow_turn))
		v.max_lean = float(d.get("max_lean", v.max_lean))
		v.max_steer = float(d.get("max_steer", v.max_steer))
		v.wade_speed = float(d.get("wade_speed", v.wade_speed))
		_all[key] = v
