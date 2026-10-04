class_name Bobber
extends Node3D
## 찌. 물 위에서 살랑거리다가, 가짜 입질엔 살짝, 진짜 입질엔 크게 가라앉는다.

@export var visual: Node3D
@export_range(0.0, 0.1, 0.005, "suffix:m") var idle_bob_height: float = 0.025
@export_range(0.5, 6.0, 0.1, "suffix:Hz") var idle_bob_speed: float = 1.6
@export_range(0.0, 0.5, 0.01, "suffix:m") var nibble_dip: float = 0.08
@export_range(0.0, 0.8, 0.01, "suffix:m") var bite_dip: float = 0.28

var _time: float = 0.0
var _dip: float = 0.0
var _tween: Tween = null
var _biting: bool = false


func _ready() -> void:
	visible = false


func show_at(world_position: Vector3) -> void:
	global_position = world_position
	_dip = 0.0
	_biting = false
	visible = true


func hide_bobber() -> void:
	_stop_tween()
	_biting = false
	visible = false


func nibble() -> void:
	_stop_tween()
	_tween = create_tween()
	_tween.tween_property(self, "_dip", nibble_dip, 0.08)
	_tween.tween_property(self, "_dip", 0.0, 0.18)


## 진짜 입질: 크게 가라앉은 채로 출렁인다 (챔질하거나 결과가 날 때까지).
func bite() -> void:
	_stop_tween()
	_biting = true
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "_dip", bite_dip, 0.12)
	_tween.tween_property(self, "_dip", bite_dip * 0.5, 0.12)


func _process(delta: float) -> void:
	if not visible or visual == null:
		return
	_time += delta
	var bob: float = sin(_time * TAU * idle_bob_speed) * idle_bob_height
	visual.position.y = bob - _dip


func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
