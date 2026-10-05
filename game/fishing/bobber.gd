class_name Bobber
extends Node3D
## 찌. 낚싯대 끝에서 포물선을 그리며 날아가 물에 퐁당 떨어지고(물결 고리), 물 위에서 살랑거리다가,
## 가짜 입질엔 살짝, 진짜 입질엔 크게 가라앉는다.

## 찌가 물에 닿았다.
signal landed(position: Vector3)

@export var visual: Node3D
@export_range(0.0, 0.1, 0.005, "suffix:m") var idle_bob_height: float = 0.025
@export_range(0.5, 6.0, 0.1, "suffix:Hz") var idle_bob_speed: float = 1.6
@export_range(0.0, 0.5, 0.01, "suffix:m") var nibble_dip: float = 0.08
@export_range(0.0, 0.8, 0.01, "suffix:m") var bite_dip: float = 0.28
## 날아가는 포물선의 꼭대기 높이 (시작·끝 사이 직선 위로).
@export_range(0.0, 5.0, 0.1, "suffix:m") var arc_height: float = 1.6
## 물결 고리를 칠할 정점 색 머티리얼 (없으면 고리를 안 그린다).
@export var ripple_material: Material

var _time: float = 0.0
var _dip: float = 0.0
var _tween: Tween = null
var _biting: bool = false
var _tug: float = 0.0
var _flight: Tween = null
static var _ring: ArrayMesh = null


func _ready() -> void:
	visible = false


func show_at(world_position: Vector3) -> void:
	global_position = world_position
	_dip = 0.0
	_biting = false
	visible = true


## start(낚싯대 끝)에서 target(수면)까지 포물선으로 날아간다. 닿으면 landed 신호 + 물결.
func cast_to(start: Vector3, target: Vector3, duration: float = 0.55) -> void:
	_stop_tween()
	if _flight != null and _flight.is_valid():
		_flight.kill()
	_dip = 0.0
	_biting = false
	visible = true
	global_position = start
	_flight = create_tween()
	_flight.tween_method(func(t: float) -> void:
		global_position = start.lerp(target, t) + Vector3(0.0, sin(t * PI) * arc_height, 0.0), 0.0, 1.0, duration)
	_flight.tween_callback(func() -> void:
		global_position = target
		ripple()
		landed.emit(target))


func is_flying() -> bool:
	return _flight != null and _flight.is_valid() and _flight.is_running()


## 수면에 퍼지는 동그란 물결 두 겹.
func ripple() -> void:
	if ripple_material == null:
		return
	if _ring == null:
		var st: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_torus(st, Vector3.ZERO, 0.3, 0.025, Color(0.95, 0.99, 1.0), 20, 4)
		_ring = ClayMesh.commit(st)
	for i: int in 2:
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.mesh = _ring
		ring.material_override = ripple_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(ring)
		ring.global_position = global_position + Vector3(0.0, 0.02, 0.0)
		ring.scale = Vector3(0.3, 1.0, 0.3)
		var tween: Tween = ring.create_tween().set_parallel(true)
		tween.tween_property(ring, "scale", Vector3(2.6, 0.4, 2.6), 0.9).set_delay(i * 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_callback(ring.queue_free)


func hide_bobber() -> void:
	if _flight != null and _flight.is_valid():
		_flight.kill()
	_stop_tween()
	_biting = false
	_tug = 0.0
	visible = false


func nibble() -> void:
	_stop_tween()
	_tween = create_tween()
	_tween.tween_property(self, "_dip", nibble_dip, 0.08)
	_tween.tween_property(self, "_dip", 0.0, 0.18)


## 진짜 입질: 물고기가 물고 들어가듯 쑥 잠겼다가(물결), 잠긴 채로 끌려가듯 출렁인다 (챔질하거나 결과가 날 때까지).
func bite() -> void:
	_stop_tween()
	_biting = true
	ripple()
	_tween = create_tween()
	_tween.tween_property(self, "_dip", bite_dip * 1.7, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "_dip", bite_dip * 1.1, 0.16)
	_tween.tween_callback(func() -> void:
		_tween = create_tween().set_loops()
		_tween.tween_property(self, "_dip", bite_dip * 1.4, 0.11)
		_tween.tween_property(self, "_dip", bite_dip * 0.9, 0.13))


## 끌어올리기: 물고기가 버티며 찌를 끌어당긴다 (반복).
func struggle() -> void:
	_stop_tween()
	_biting = true
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "_dip", bite_dip * 1.2, 0.07)
	_tween.tween_property(self, "_dip", bite_dip * 0.6, 0.09)
	_tween.tween_property(self, "_dip", bite_dip * 1.0, 0.06)
	_tween.tween_property(self, "_dip", bite_dip * 0.5, 0.1)


## 연타 한 번: 찌가 위로 홱 끌려 올라온다 (struggle 출렁임 위에 더해진다).
func tug() -> void:
	_tug = 0.12
	if randf() < 0.35:
		ripple()


func _process(delta: float) -> void:
	if not visible or visual == null:
		return
	_time += delta
	var bob: float = sin(_time * TAU * idle_bob_speed) * idle_bob_height
	_tug = move_toward(_tug, 0.0, delta * 0.8)
	visual.position.y = bob - _dip + _tug
	# 끌려가는 동안 좌우로 흔들린다.
	visual.rotation.z = sin(_time * 23.0) * 0.25 * clampf(_dip / maxf(bite_dip, 0.01), 0.0, 1.0) if _biting else 0.0


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
