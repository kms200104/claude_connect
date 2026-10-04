class_name NpcCrowd
extends Node3D
## 주민 전체와 주민 집. 주민 목록·집 위치는 data/npcs/npcs.json, 주민 위치는 서버가 보낸다.

@export var actor_scene: PackedScene
@export_group("House Materials")
@export var wall_material: Material
## 주민 색으로 지붕을 칠할 때 복제할 머티리얼.
@export var roof_material: ShaderMaterial
@export var door_material: Material
## 밤에 켜지는 창문.
@export var window_material: Material

const HOUSE_SIZE: Vector3 = Vector3(4.0, 2.6, 3.0)

var _actors: Dictionary[String, NpcActor] = {}


func _ready() -> void:
	for npc: NpcInfo in GameData.npcs.values():
		_build_house(npc)
		var actor: NpcActor = actor_scene.instantiate()
		add_child(actor)
		actor.setup(npc)
		_actors[npc.id] = actor
	Net.npcs_received.connect(_on_npcs_received)
	Net.profile_updated.connect(_refresh_marks)
	Net.inventory_updated.connect(func(_slots: Array[InventoryItem], _held: int) -> void: _refresh_marks())
	_refresh_marks()


func actor(id: String) -> NpcActor:
	return _actors.get(id)


## 말을 걸 수 있는 가장 가까운 주민 (다른 사람과 이야기 중인 주민은 뺀다). 없으면 빈 문자열.
func nearest_talkable(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for id: String in _actors:
		var a: NpcActor = _actors[id]
		if a.talking_with != 0 and a.talking_with != Net.my_id:
			continue
		var d: float = Vector2(position.x - a.global_position.x, position.z - a.global_position.z).length()
		if d <= best_d:
			best_d = d
			best = id
	return best


func _on_npcs_received(_server_time_ms: float, states: Array[NetNpcState]) -> void:
	for state: NetNpcState in states:
		var a: NpcActor = _actors.get(state.id)
		if a != null:
			a.apply_state(state)


func _refresh_marks() -> void:
	for id: String in _actors:
		var q: QuestInfo = Net.quest_from(id)
		var text: String = ""
		if q != null:
			text = "!" if q.is_ready() else "…"
		_actors[id].set_mark(text)


## 주민 집: 벽·지붕·문·창문 4개 메시 + 충돌 상자. 문은 집의 +Z 쪽(데이터의 yaw로 돌린다).
func _build_house(npc: NpcInfo) -> void:
	var house: StaticBody3D = StaticBody3D.new()
	house.name = "House_%s" % npc.id
	add_child(house)
	house.global_position = npc.house_position
	house.rotation.y = npc.house_yaw

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = HOUSE_SIZE
	shape.shape = box
	shape.position.y = HOUSE_SIZE.y * 0.5
	house.add_child(shape)

	var walls: BoxMesh = BoxMesh.new()
	walls.size = HOUSE_SIZE
	_add_mesh(house, walls, Vector3(0.0, HOUSE_SIZE.y * 0.5, 0.0), wall_material)

	var roof: PrismMesh = PrismMesh.new()
	roof.size = Vector3(HOUSE_SIZE.x + 0.6, 1.3, HOUSE_SIZE.z + 0.4)
	var roof_mat: Material = roof_material
	if roof_material != null:
		var tinted: ShaderMaterial = roof_material.duplicate()
		tinted.set_shader_parameter("albedo", npc.color.darkened(0.15))
		roof_mat = tinted
	_add_mesh(house, roof, Vector3(0.0, HOUSE_SIZE.y + 0.65, 0.0), roof_mat)

	var door: BoxMesh = BoxMesh.new()
	door.size = Vector3(0.9, 1.6, 0.08)
	_add_mesh(house, door, Vector3(-0.8, 0.8, HOUSE_SIZE.z * 0.5 + 0.02), door_material)

	var window: BoxMesh = BoxMesh.new()
	window.size = Vector3(0.8, 0.6, 0.06)
	_add_mesh(house, window, Vector3(0.9, 1.45, HOUSE_SIZE.z * 0.5 + 0.02), window_material)


func _add_mesh(parent: Node3D, mesh: Mesh, offset: Vector3, material: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = offset
	parent.add_child(mi)
