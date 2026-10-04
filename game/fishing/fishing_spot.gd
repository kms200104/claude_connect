class_name FishingSpot
extends Node3D
## 낚시터(수역). 위치와 크기는 data/fish/spots.json 에서 읽는다 — 서버가 판정에 쓰는 값과 같은 출처.

@export var spot_id: String = "pond"
@export var water: MeshInstance3D
## 물에 들어가지 못하게 막는 충돌체 (BoxShape3D). 크기는 데이터의 수역보다 가장자리만큼 작게 맞춘다.
@export var blocker: CollisionShape3D
## 물가에 설 수 있는 폭. 서버의 낚시 판정 거리(cast_range) 안쪽이어야 한다.
@export_range(0.0, 2.0, 0.05, "suffix:m") var shore_margin: float = 0.5
## 수면 높이. 바닥(y=0)과 겹쳐 깜빡이지 않게 살짝 띄운다.
@export_range(0.0, 0.2, 0.005, "suffix:m") var water_height: float = 0.03

var info: SpotInfo = null


func _ready() -> void:
	add_to_group(&"fishing_spots")
	info = GameData.spots.get(spot_id)
	if info == null:
		push_error("FishingSpot: spots.json 에 '%s' 가 없음" % spot_id)
		return
	global_position = Vector3(info.center.x, 0.0, info.center.y)
	if water != null:
		# 같은 씬 자원을 여러 낚시터가 나눠 쓰므로 크기를 바꾸기 전에 제 것으로 만든다.
		water.mesh = water.mesh.duplicate()
		if water.material_override != null:
			water.material_override = water.material_override.duplicate()
		var surface: Material = water.get_surface_override_material(0)
		if surface != null:
			water.set_surface_override_material(0, surface.duplicate())
		var plane: PlaneMesh = water.mesh
		plane.size = info.half_extent * 2.0
		# 월드 커브는 정점 단위로 휘므로, 수면도 1m 격자로 쪼개야 지면과 같이 휜다.
		plane.subdivide_width = maxi(int(plane.size.x), 1)
		plane.subdivide_depth = maxi(int(plane.size.y), 1)
		water.position = Vector3(0.0, water_height, 0.0)
		if water.material_override is ShaderMaterial:
			(water.material_override as ShaderMaterial).set_shader_parameter("half_extent", info.half_extent)
		elif water.get_surface_override_material(0) is ShaderMaterial:
			(water.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("half_extent", info.half_extent)
	if blocker != null and blocker.shape is BoxShape3D:
		blocker.shape = blocker.shape.duplicate()
		_build_blocker()


## 물 막이: 수역보다 물가 폭만큼 작은 상자. 선착장이 물 위로 나와 있으면 그 자리만 비워 걸어 들어갈 수 있게 한다.
func _build_blocker() -> void:
	var half: Vector2 = Vector2(maxf(info.half_extent.x - shore_margin, 0.05), maxf(info.half_extent.y - shore_margin, 0.05))
	var whole: Rect2 = Rect2(info.center - half, half * 2.0)
	var pieces: Array[Rect2] = [whole]
	var layout: VillageLayout = GameData.layout
	if layout != null and layout.dock_size.x > 0.0:
		var gap: Rect2 = layout.dock_rect()
		if whole.intersects(gap):
			pieces = _subtract(whole, gap.intersection(whole))
	var box: BoxShape3D = blocker.shape
	for i: int in pieces.size():
		var shape: CollisionShape3D = blocker
		if i > 0:
			shape = CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			blocker.get_parent().add_child(shape)
		var r: Rect2 = pieces[i]
		(shape.shape as BoxShape3D).size = Vector3(r.size.x, 2.0, r.size.y)
		shape.global_position = Vector3(r.get_center().x, 1.0, r.get_center().y)
	if pieces.is_empty():
		box.size = Vector3(0.01, 0.01, 0.01)


## 사각형 a 에서 b(a 안쪽)를 빼고 남은 조각들 (왼쪽·오른쪽 전체 높이, 가운데 위·아래).
static func _subtract(a: Rect2, b: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if b.position.x > a.position.x:
		out.append(Rect2(a.position, Vector2(b.position.x - a.position.x, a.size.y)))
	if b.end.x < a.end.x:
		out.append(Rect2(Vector2(b.end.x, a.position.y), Vector2(a.end.x - b.end.x, a.size.y)))
	if b.position.y > a.position.y:
		out.append(Rect2(Vector2(b.position.x, a.position.y), Vector2(b.size.x, b.position.y - a.position.y)))
	if b.end.y < a.end.y:
		out.append(Rect2(Vector2(b.position.x, b.end.y), Vector2(b.size.x, a.end.y - b.end.y)))
	return out


## 서버 판정(cast_range)보다 약간 안쪽에서만 던질 수 있게 해서, 경계에서 서버에 거절당하지 않게 한다.
func can_cast_from(position: Vector3, safety_margin: float = 0.3) -> bool:
	return info != null and info.distance_to(position) <= info.cast_range - safety_margin
