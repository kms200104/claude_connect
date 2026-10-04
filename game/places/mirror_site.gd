class_name MirrorSite
extends Node3D
## 마을에 놓인 큰 전신 거울 (data/world/village_layout.json 의 mirrors). 앞에 서서 상황 버튼을 누르면 거울 창(얼굴 꾸미기)이 열린다.
## 모양은 거울 가구(standing_mirror)를 크게 키운 것 + 위에 "거울" 팻말. 부딪히는 몸체가 있다.

## 가구 거울보다 이만큼 크게.
@export_range(1.0, 2.0, 0.05) var mirror_scale: float = 1.4
@export var clay_material: Material

var _spots: Array[Vector3] = []


func _ready() -> void:
	if GameData.layout == null:
		return
	var info: ItemInfo = GameData.item("standing_mirror")
	for spot: Vector3 in GameData.layout.mirrors:
		_spots.append(spot)
		var root: Node3D = Node3D.new()
		root.name = "Mirror%d" % _spots.size()
		add_child(root)
		root.position = Vector3(spot.x, 0.0, spot.y)
		root.rotation.y = spot.z
		if info != null:
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = PartMesh.get_mesh(info.id, info.model)
			mi.material_override = clay_material
			mi.scale = Vector3.ONE * mirror_scale
			root.add_child(mi)
		var label: Label3D = Label3D.new()
		label.text = "거울"
		label.font_size = 44
		label.pixel_size = 0.008
		label.outline_size = 12
		label.modulate = Color("#FFF8EA")
		label.outline_modulate = Color("#5A3E26")
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		root.add_child(label)
		label.position = Vector3(0.0, 2.45, 0.0)
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(0.95, 2.2, 0.7) * Vector3(mirror_scale / 1.4, 1.0, 1.0)
		shape.shape = box
		shape.position = Vector3(0.0, 1.1, 0.0)
		body.add_child(shape)
		root.add_child(body)


## pos 에서 max_distance 안에 있는 마을 거울의 번호 (없으면 -1).
func nearest(pos: Vector3, max_distance: float) -> int:
	var best: int = -1
	var best_d: float = max_distance
	for i: int in _spots.size():
		var d: float = Vector2(pos.x - _spots[i].x, pos.z - _spots[i].y).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


## 거울 i 의 자리.
func spot_position(i: int) -> Vector3:
	return Vector3(_spots[i].x, 0.0, _spots[i].y) if i >= 0 and i < _spots.size() else Vector3.ZERO


## 거울 i 앞(거울이 보는 쪽) distance 미터 자리.
func stand_position(i: int, distance: float = 1.0) -> Vector3:
	if i < 0 or i >= _spots.size():
		return Vector3.ZERO
	return spot_position(i) + Vector3(sin(_spots[i].z), 0.0, cos(_spots[i].z)) * distance
