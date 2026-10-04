class_name NpcActor
extends Node3D
## 주민 한 명의 화면 표시. 위치·방향은 서버가 정하고(10Hz), 여기서는 부드럽게 따라가며 걷기 애니메이션을 맞춘다.
## 머리 위 표시: 내가 받은 부탁이 있으면 "…", 완료할 수 있으면 "!".

@export_group("References")
@export var body: Node3D
@export var rig: CharacterRig
@export var name_label: Label3D
@export var mark: Label3D
## 주민마다 색만 바꿔 복제할 몸 머티리얼.
@export var base_material: ShaderMaterial

@export_group("Motion")
## 클수록 서버 위치에 딱 붙는다 (지수 감쇠 계수).
@export_range(1.0, 40.0, 0.5) var follow_smoothing: float = 8.0
@export_range(1.0, 40.0, 0.5) var turn_smoothing: float = 8.0
## 이 속도(m/s)로 움직이면 walk 애니메이션이 100% 재생된다 (서버 주민 걷기 속도).
@export_range(0.2, 10.0, 0.1, "suffix:m/s") var walk_speed_reference: float = 1.4
## 이보다 멀리 떨어진 서버 위치는 보간하지 않고 바로 옮긴다.
@export_range(1.0, 50.0, 0.5, "suffix:m") var teleport_distance: float = 8.0

var info: NpcInfo = null
## 대화 중인 플레이어 id (0 = 없음).
var talking_with: int = 0

var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _shown_speed: float = 0.0
var _has_state: bool = false
var _mark_time: float = 0.0


func setup(npc: NpcInfo) -> void:
	info = npc
	name = "Npc_%s" % npc.id
	if name_label != null:
		name_label.text = npc.display_name
	if rig != null:
		rig.set_held("")
		if base_material != null:
			var material: ShaderMaterial = base_material.duplicate()
			material.set_shader_parameter("albedo", npc.color)
			rig.set_body_material(material)
	global_position = npc.home
	_target_position = npc.home
	set_mark("")
	# 화면 밖에 있는 주민은 애니메이션을 계산하지 않는다.
	var notifier: VisibleOnScreenNotifier3D = VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 2.6, 1.2))
	notifier.screen_entered.connect(func() -> void: _set_animating(true))
	notifier.screen_exited.connect(func() -> void: _set_animating(false))
	add_child(notifier)


func apply_state(state: NetNpcState) -> void:
	talking_with = state.talking_with
	_target_yaw = state.yaw
	if not _has_state or global_position.distance_to(state.position) > teleport_distance:
		global_position = state.position
		if body != null:
			body.rotation.y = state.yaw
	_target_position = state.position
	_has_state = true


## 머리 위 표시 ("" = 숨김).
func set_mark(text: String) -> void:
	if mark == null:
		return
	mark.visible = not text.is_empty()
	mark.text = text


## 서버가 방향을 알려 주기 전에 먼저 상대를 돌아본다 (대화 시작 반응).
func face_toward(position: Vector3) -> void:
	var d: Vector3 = position - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_target_yaw = atan2(-d.x, -d.z)


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	var before: Vector3 = global_position
	global_position = global_position.lerp(_target_position, weight)
	if body != null:
		body.rotation.y = lerp_angle(body.rotation.y, _target_yaw, 1.0 - exp(-turn_smoothing * delta))
	if rig != null and delta > 0.0:
		var moved: float = Vector3(global_position.x - before.x, 0.0, global_position.z - before.z).length() / delta
		_shown_speed = lerpf(_shown_speed, moved, 1.0 - exp(-10.0 * delta))
		rig.set_move_speed(_shown_speed / walk_speed_reference)
	if mark != null and mark.visible:
		_mark_time += delta
		mark.position.y = 2.45 + sin(_mark_time * 4.0) * 0.06


func _set_animating(on: bool) -> void:
	if rig != null and rig.tree != null:
		rig.tree.active = on
