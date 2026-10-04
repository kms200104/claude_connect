class_name CharacterRig
extends Node3D
## 캐릭터 시각 부분. AnimationTree 가 idle ↔ walk (속도로 블렌드) 와 낚시 자세(가중치로 블렌드)를 섞는다.
## 로컬 플레이어와 원격 플레이어가 같은 리그를 쓰고, 게임 로직은 set_move_speed / set_fishing 만 호출한다.

@export_group("References")
@export var capsule: MeshInstance3D
@export var tree: AnimationTree
@export var body_material: Material

@export_group("Animation")
## 클수록 idle ↔ walk 전환이 빠르다 (지수 감쇠 계수).
@export_range(0.5, 40.0, 0.5) var speed_smoothing: float = 10.0
## 클수록 낚시 자세에 빨리 들어가고 나온다.
@export_range(0.5, 40.0, 0.5) var fishing_blend_speed: float = 6.0

var _move_target: float = 0.0
var _move_value: float = 0.0
var _fishing_target: float = 0.0
var _fishing_value: float = 0.0


func _ready() -> void:
	if capsule != null and body_material != null:
		capsule.set_surface_override_material(0, body_material)
	if tree != null:
		tree.active = true


## 0 = 서 있음, 1 = 기준 속도로 걷는 중 (0~1로 잘라 쓴다).
func set_move_speed(normalized: float) -> void:
	_move_target = clampf(normalized, 0.0, 1.0)


func set_fishing(active: bool) -> void:
	_fishing_target = 1.0 if active else 0.0


func _process(delta: float) -> void:
	if tree == null:
		return
	_move_value = lerpf(_move_value, _move_target, 1.0 - exp(-speed_smoothing * delta))
	_fishing_value = lerpf(_fishing_value, _fishing_target, 1.0 - exp(-fishing_blend_speed * delta))
	tree.set("parameters/Locomotion/blend_position", _move_value)
	tree.set("parameters/FishBlend/blend_amount", _fishing_value)
