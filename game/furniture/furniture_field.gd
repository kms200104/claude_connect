class_name FurnitureField
extends Node3D
## 마을에 설치된 가구 전체. 위치·방향·주인은 서버가 정하고(Net.placed), 모양은 아이템 데이터의 도형 목록(PartMesh).
## 가구 하나 = 메시 1개 + 충돌 상자 1개. 같은 가구는 메시를 공유한다.

@export var material: Material
## 이 거리보다 먼 가구는 그리지 않는다.
@export_range(10.0, 200.0, 1.0, "suffix:m") var draw_distance: float = 45.0

var _bodies: Dictionary[String, StaticBody3D] = {}


func _ready() -> void:
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _rebuild())
	Net.furniture_placed.connect(func(info: PlacedInfo, _by: int) -> void: _add(info, true))
	Net.furniture_removed.connect(_remove)


## 내가 놓은 가구 중 가장 가까운 것 (줍기 대상). 없으면 빈 문자열.
func nearest_own(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for info: PlacedInfo in Net.placed.values():
		if info.owner != Net.my_id:
			continue
		var d: float = Vector2(position.x - info.position.x, position.z - info.position.z).length()
		if d <= best_d:
			best_d = d
			best = info.id
	return best


func has_furniture(id: String) -> bool:
	return _bodies.has(id)


func _rebuild() -> void:
	for id: String in _bodies.keys():
		_remove(id)
	for info: PlacedInfo in Net.placed.values():
		_add(info, false)


func _add(info: PlacedInfo, animate: bool) -> void:
	if _bodies.has(info.id):
		return
	var item: ItemInfo = GameData.item(info.item)
	if item == null:
		return
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Furniture_%s" % info.id
	add_child(body)
	body.global_position = info.position
	body.rotation.y = info.rot * PI * 0.5
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = PartMesh.get_mesh(item.id, item.model)
	mesh_instance.material_override = material
	mesh_instance.visibility_range_end = draw_distance
	body.add_child(mesh_instance)
	var aabb: AABB = mesh_instance.mesh.get_aabb()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = aabb.size.max(Vector3(0.2, 0.2, 0.2))
	shape.shape = box
	shape.position = aabb.get_center()
	body.add_child(shape)
	_bodies[info.id] = body
	if animate:
		mesh_instance.scale = Vector3(0.6, 1.3, 0.6)
		create_tween().tween_property(mesh_instance, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _remove(id: String) -> void:
	var body: StaticBody3D = _bodies.get(id)
	if body != null:
		body.queue_free()
		_bodies.erase(id)
