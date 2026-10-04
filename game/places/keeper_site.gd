class_name KeeperSite
extends Node3D
## 지기가 지키는 건물 한 채 (박물관·공항의 공통 부분): 점토 건물 메시 + 밤에 빛나는 창 + 충돌체 + 건물 앞에 선 지기.
## 건물 모양은 PartMesh 도형 목록(앞면 가운데 바닥 = 원점, 앞면이 +Z)으로 만들어 메시 1개로 그린다.
## 지기와 이야기하면 DialogueController 가 장소별 흐름(기증·기념품)을 연다. 판정은 서버가 한다.

@export var actor_scene: PackedScene
@export var clay_material: Material
@export var window_material: Material

var place: KeeperPlace = null
var actor: NpcActor = null
var building: Node3D = null


## 자식 클래스가 정한다: 어느 장소인지, 건물 모양, 창문, 충돌 상자들 (건물 기준 [가운데, 크기]).
func _place() -> KeeperPlace:
	return null


func _building_parts() -> Array:
	return []


func _window_parts() -> Array:
	return []


func _colliders() -> Array[AABB]:
	return []


func _ready() -> void:
	place = _place()
	if place == null:
		return
	building = Node3D.new()
	building.name = "Building"
	add_child(building)
	building.global_position = place.building_position
	building.rotation.y = place.building_yaw
	_add_mesh(building, PartMesh.build(_building_parts()), clay_material)
	var windows: Array = _window_parts()
	if not windows.is_empty():
		_add_mesh(building, PartMesh.build(windows), window_material)
	var body: StaticBody3D = StaticBody3D.new()
	building.add_child(body)
	for box: AABB in _colliders():
		var shape: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = box.size
		shape.shape = b
		shape.position = box.position
		body.add_child(shape)
	if actor_scene != null:
		actor = actor_scene.instantiate()
		add_child(actor)
		actor.setup(place.keeper)
		var state: NetNpcState = NetNpcState.new()
		state.id = place.keeper.id
		state.position = place.keeper_position
		state.yaw = place.keeper_yaw
		actor.apply_state(state)
		# 지기는 움직이지 않는다: 몸에 부딪히지 않게 작은 기둥 충돌체.
		var keeper_body: StaticBody3D = StaticBody3D.new()
		var keeper_shape: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = 1.8
		keeper_shape.shape = cyl
		keeper_shape.position = Vector3(0.0, 0.9, 0.0)
		keeper_body.add_child(keeper_shape)
		add_child(keeper_body)
		keeper_body.global_position = place.keeper_position


func npc_id() -> String:
	return place.keeper.id if place != null else ""


func info() -> NpcInfo:
	return place.keeper if place != null else null


## 말을 걸 수 있는 거리 안인지.
func near(position: Vector3, max_distance: float) -> bool:
	return actor != null and Vector2(position.x - actor.global_position.x, position.z - actor.global_position.z).length() <= max_distance


## 건물 기준 좌표 → 월드 좌표.
func to_world(local: Vector3) -> Vector3:
	return building.global_transform * local if building != null else local


func _add_mesh(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	return mi


## 건물 위 이름판 (점토 판 + 글씨).
func _add_sign(text: String, at: Vector3, color: Color) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.01
	label.outline_size = 18
	label.modulate = color
	label.outline_modulate = Color("#5A3E26")
	label.double_sided = false
	building.add_child(label)
	label.position = at


static func p(shape: String, size: Array, at: Vector3, color: Variant, roundness: float = -1.0, rot: Vector3 = Vector3.ZERO) -> Dictionary:
	var part: Dictionary = {"s": shape, "size": size, "at": [at.x, at.y, at.z], "c": color}
	if roundness >= 0.0:
		part["r"] = roundness
	if rot != Vector3.ZERO:
		part["rot"] = [rot.x, rot.y, rot.z]
	return part
