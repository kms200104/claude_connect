class_name AirportSite
extends KeeperSite
## 솔바람 공항: 하늘색 줄무늬 터미널, 빨간 지붕, 관제탑, 활주로 끝의 바람자루.
## 빨간 프로펠러 비행기는 마을 시계(Net.game_ms)에 맞춰 뜨고 내린다 — 두 사람 화면에서 같은 순간에 이륙한다.
##   주기 cycle_minutes: 세워 둔 비행기가 돌아서고 → 시동 → 활주로를 달려 이륙 → (away_minutes 동안 비행) → 바다 쪽에서 내려와 착륙.

const WALL: Array = ["#E6EEF2", "#FFFFFF"]
const STRIPE: String = "#6FA8D0"
const ROOF: Array = ["#C8463C", "#E8695A"]
const PLANE_RED: Array = ["#C8463C", "#F27A68"]

## 이륙·착륙에 걸리는 시간 (초).
@export_range(4.0, 40.0, 0.5, "suffix:s") var takeoff_time: float = 12.0
@export_range(4.0, 40.0, 0.5, "suffix:s") var landing_time: float = 14.0
## 이 거리 안에서만 프로펠러 소리가 들린다.
@export_range(5.0, 120.0, 1.0, "suffix:m") var engine_hear_distance: float = 45.0

var plane: Node3D = null
var _propeller: MeshInstance3D = null
var _engine: AudioStreamPlayer3D = null
var _runway: Dictionary = {}
var _cycle_s: float = 360.0
var _away_s: float = 150.0
var _prop_angle: float = 0.0


func _place() -> KeeperPlace:
	return GameData.airport


func _ready() -> void:
	super._ready()
	if place == null:
		return
	_add_sign(place.display_name, Vector3(0.0, 3.55, 2.2), Color("#FFFFFF"))
	_runway = place.extra.get("runway", {})
	var flight: Dictionary = place.extra.get("flight", {})
	_cycle_s = float(flight.get("cycle_minutes", 6.0)) * 60.0
	_away_s = float(flight.get("away_minutes", 2.5)) * 60.0
	if not _runway.is_empty():
		_build_windsock()
		_build_plane()


func _building_parts() -> Array:
	var parts: Array = []
	parts.append(p("rbox", [12.0, 3.2, 8.0], Vector3(0.0, 1.6, -4.0), WALL, 0.08))
	parts.append(p("rbox", [12.05, 0.35, 8.05], Vector3(0.0, 0.6, -4.0), STRIPE, 0.3))
	parts.append(p("rbox", [12.8, 0.42, 8.8], Vector3(0.0, 3.4, -4.0), ROOF, 0.3))
	parts.append(p("rbox", [11.0, 0.5, 7.0], Vector3(0.0, 3.75, -4.0), ROOF, 0.5))
	# 입구 차양 + 기둥
	parts.append(p("rbox", [5.2, 0.22, 2.4], Vector3(0.0, 2.85, 1.15), ROOF, 0.3))
	for x: float in [-2.3, 2.3]:
		parts.append(p("cyl", [0.12, 2.8], Vector3(x, 1.4, 2.1), ["#B8B4AC", "#E8E4DC"], 0.2))
	# 자동문 테두리
	parts.append(p("rbox", [2.4, 2.5, 0.08], Vector3(0.0, 1.25, 0.03), "#5E6E7E", 0.2))
	# 벽의 날개 마크
	for side: float in [-1.0, 1.0]:
		parts.append(p("sphere", [0.55, 0.12, 0.04], Vector3(side * 0.55, 3.0, 0.06), "#F0D27A", -1.0, Vector3(0.0, 0.0, side * -12.0)))
	parts.append(p("sphere", [0.16], Vector3(0.0, 3.0, 0.08), "#F0D27A"))
	# 관제탑: 기둥 · 유리 관제실 받침 · 빨간 모자 · 안테나
	parts.append(p("cyl", [0.9, 5.0], Vector3(-4.3, 4.4, -6.0), WALL, 0.05))
	parts.append(p("rbox", [2.2, 0.3, 2.2], Vector3(-4.3, 6.9, -6.0), STRIPE, 0.5))
	parts.append(p("cone", [1.5, 0.9], Vector3(-4.3, 8.65, -6.0), ROOF, 0.05))
	parts.append(p("rod", [0.03, 0.02], Vector3(-4.3, 9.0, -6.0), "#5E6E7E"))
	parts[-1]["to"] = [-4.3, 9.9, -6.0]
	parts.append(p("sphere", [0.08], Vector3(-4.3, 9.95, -6.0), "#E05A4A"))
	# 앞 화분과 짐수레
	for x: float in [-4.6, 4.6]:
		parts.append(p("cyl", [0.45, 0.6], Vector3(x, 0.3, 1.6), ["#A9512F", "#D9784C"], 0.1))
		parts.append(p("blob", [0.55, 0.6, 0.55], Vector3(x, 1.0, 1.6), ["#3E7A3A", "#7FB86A"]))
	parts.append(p("rbox", [1.4, 0.12, 0.8], Vector3(3.6, 0.45, 2.6), "#8A8A84", 0.3))
	parts.append(p("rbox", [0.7, 0.5, 0.5], Vector3(3.4, 0.76, 2.6), ["#8A5A36", "#B07A45"], 0.2))
	parts.append(p("rbox", [0.5, 0.35, 0.4], Vector3(3.95, 0.68, 2.6), ["#3E7FA8", "#6FA8D0"], 0.2))
	return parts


func _window_parts() -> Array:
	var parts: Array = []
	for x: float in [-3.8, 3.8]:
		parts.append(p("rbox", [3.2, 1.6, 0.06], Vector3(x, 1.9, 0.03), "#FFFFFF", 0.3))
	parts.append(p("rbox", [2.0, 2.2, 0.06], Vector3(0.0, 1.15, 0.08), "#FFFFFF", 0.2))
	parts.append(p("cyl", [1.25, 1.2], Vector3(-4.3, 7.65, -6.0), "#FFFFFF", 0.1))
	return parts


func _colliders() -> Array[AABB]:
	return [
		AABB(Vector3(0.0, 1.7, -4.0), Vector3(12.2, 3.4, 8.2)),
		AABB(Vector3(-2.3, 1.4, 2.1), Vector3(0.3, 2.8, 0.3)),
		AABB(Vector3(2.3, 1.4, 2.1), Vector3(0.3, 2.8, 0.3)),
		AABB(Vector3(-4.6, 0.6, 1.6), Vector3(1.0, 1.2, 1.0)),
		AABB(Vector3(4.6, 0.6, 1.6), Vector3(1.0, 1.2, 1.0)),
	]


## 활주로 동쪽 끝의 줄무늬 바람자루.
func _build_windsock() -> void:
	var parts: Array = []
	parts.append(p("rod", [0.06, 0.05], Vector3.ZERO, "#B8B4AC"))
	parts[-1]["to"] = [0.0, 3.2, 0.0]
	for i: int in 4:
		parts.append(p("cyl", [0.26 - 0.04 * i, 0.4], Vector3(0.25 + 0.4 * i, 3.05 - 0.06 * i, 0.0), "#F27A28" if i % 2 == 0 else "#FFFFFF", 0.05, Vector3(0.0, 0.0, 90.0)))
	var sock: MeshInstance3D = _add_mesh(self, PartMesh.build(parts), clay_material)
	sock.global_position = Vector3(float(_runway.x1) + 2.0, 0.0, float(_runway.z) - float(_runway.width) * 0.5 - 2.0)


## 빨간 프로펠러 비행기 (머리 = +X). 프로펠러는 따로 돌린다.
func _build_plane() -> void:
	plane = Node3D.new()
	plane.name = "Plane"
	add_child(plane)
	var parts: Array = []
	parts.append(p("cap", [0.55], Vector3(-2.2, 1.2, 0.0), PLANE_RED))
	parts[-1]["to"] = [1.6, 1.2, 0.0]
	parts.append(p("sphere", [0.6, 0.55, 0.55], Vector3(1.75, 1.2, 0.0), ["#E8E4DC", "#FFFFFF"]))
	parts.append(p("sphere", [0.55, 0.32, 0.42], Vector3(0.6, 1.62, 0.0), ["#6FA8D0", "#BFE0F4"]))
	parts.append(p("rbox", [1.3, 0.14, 7.0], Vector3(0.4, 1.55, 0.0), PLANE_RED, 0.5))
	parts.append(p("rbox", [0.8, 0.1, 2.6], Vector3(-2.5, 1.35, 0.0), PLANE_RED, 0.5))
	parts.append(p("rbox", [0.9, 1.1, 0.12], Vector3(-2.6, 1.9, 0.0), PLANE_RED, 0.5))
	parts.append(p("rbox", [0.4, 0.06, 7.04], Vector3(0.4, 1.63, 0.0), "#FFFFFF", 0.5))
	# 바퀴 (수상비행기처럼 동그란 바퀴 셋)
	for z: float in [-0.8, 0.8]:
		parts.append(p("rod", [0.05, 0.05], Vector3(0.8, 1.0, z * 0.5), "#5E5E5E"))
		parts[-1]["to"] = [0.8, 0.3, z]
		parts.append(p("torus", [0.18, 0.1], Vector3(0.8, 0.28, z), "#3A3A3A", -1.0, Vector3(90.0, 0.0, 0.0)))
	parts.append(p("torus", [0.12, 0.07], Vector3(-2.4, 0.75, 0.0), "#3A3A3A", -1.0, Vector3(90.0, 0.0, 0.0)))
	_add_mesh(plane, PartMesh.build(parts), clay_material)
	_propeller = MeshInstance3D.new()
	_propeller.mesh = PartMesh.build([
		p("rbox", [0.08, 2.0, 0.22], Vector3.ZERO, ["#5E5E5E", "#8A8A84"], 0.5),
		p("sphere", [0.16], Vector3(0.08, 0.0, 0.0), "#F0D27A"),
	])
	_propeller.material_override = clay_material
	plane.add_child(_propeller)
	_propeller.position = Vector3(2.35, 1.2, 0.0)
	_engine = AudioStreamPlayer3D.new()
	var stream: AudioStream = load("res://assets/audio/sfx/plane_loop.wav") if ResourceLoader.exists("res://assets/audio/sfx/plane_loop.wav") else null
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		_engine.stream = wav
	_engine.bus = "Sfx"
	_engine.unit_size = 10.0
	_engine.max_distance = engine_hear_distance
	_engine.volume_db = -6.0
	plane.add_child(_engine)


## 다음 이륙까지 남은 시간 (초). 조종사가 "다음 비행기는 몇 분 뒤에 떠!" 라고 알려 줄 때 쓴다.
func seconds_until_takeoff(game_seconds: float) -> float:
	var t: float = fposmod(game_seconds, _cycle_s)
	var takeoff_at: float = _cycle_s - _away_s - landing_time - takeoff_time
	return takeoff_at - t if t <= takeoff_at else _cycle_s - t + takeoff_at


## 지금 시각의 비행기 자리·방향·높이·프로펠러 빠르기 (0~1). 마을 시계로 정하니 모두에게 같다.
func plane_pose(game_seconds: float) -> Dictionary:
	var x0: float = float(_runway.x0)
	var x1: float = float(_runway.x1)
	var z: float = float(_runway.z)
	var park: float = x0 + 3.5
	var t: float = fposmod(game_seconds, _cycle_s)
	var takeoff_at: float = _cycle_s - _away_s - landing_time - takeoff_time
	var away_at: float = takeoff_at + takeoff_time
	var landing_at: float = _cycle_s - landing_time
	if t < 5.0:
		# 내려앉은 뒤 제자리에서 빙 돌아선다.
		return {"pos": Vector3(park, 0.0, z), "yaw": lerpf(PI, 0.0, smoothstep(0.0, 5.0, t)), "prop": 0.6, "visible": true}
	if t < takeoff_at - 18.0:
		return {"pos": Vector3(park, 0.0, z), "yaw": 0.0, "prop": 0.0, "visible": true}
	if t < takeoff_at:
		return {"pos": Vector3(park, 0.0, z), "yaw": 0.0, "prop": smoothstep(takeoff_at - 18.0, takeoff_at - 10.0, t), "visible": true}
	if t < away_at:
		var k: float = (t - takeoff_at) / takeoff_time
		var run: float = k * k
		var x: float = lerpf(park, x1 + 70.0, run)
		var lift: float = smoothstep(0.55, 1.0, k)
		return {"pos": Vector3(x, lift * lift * 28.0, z - lift * 10.0), "yaw": 0.0, "pitch": lift * 0.25, "prop": 1.0, "visible": true}
	if t < landing_at:
		return {"pos": Vector3(park, 0.0, z), "yaw": 0.0, "prop": 0.0, "visible": false}
	var k2: float = (t - landing_at) / landing_time
	# 바다 쪽(동쪽) 하늘에서 내려와 활주로 동쪽 끝에 닿고, 서쪽 끝 주차 자리까지 미끄러지며 선다.
	var touch: float = 0.55
	var pos: Vector3
	var pitch: float = 0.0
	if k2 < touch:
		var a: float = k2 / touch
		pos = Vector3(lerpf(x1 + 80.0, x1 - 2.0, a), lerpf(26.0, 0.0, smoothstep(0.0, 1.0, a)), lerpf(z - 12.0, z, a))
		pitch = -0.12 * (1.0 - a)
	else:
		var b: float = (k2 - touch) / (1.0 - touch)
		pos = Vector3(lerpf(x1 - 2.0, park, 1.0 - (1.0 - b) * (1.0 - b)), 0.0, z)
	return {"pos": pos, "yaw": PI, "pitch": pitch, "prop": 1.0 - k2 * 0.4, "visible": true}


func _process(delta: float) -> void:
	if plane == null:
		return
	var pose: Dictionary = plane_pose(Net.game_ms() / 1000.0)
	plane.visible = bool(pose["visible"])
	plane.global_position = pose["pos"]
	plane.rotation = Vector3(0.0, float(pose["yaw"]), float(pose.get("pitch", 0.0)))
	var spin: float = float(pose["prop"])
	_prop_angle += delta * (2.0 + 40.0 * spin)
	_propeller.rotation.x = _prop_angle
	var audible: bool = plane.visible and spin > 0.05
	if _engine != null and _engine.stream != null:
		if audible and not _engine.playing:
			_engine.play()
		elif not audible and _engine.playing:
			_engine.stop()
		_engine.pitch_scale = 0.7 + 0.6 * spin
