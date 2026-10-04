class_name MuseumSite
extends KeeperSite
## 솔바람 박물관: 하얀 기둥이 늘어선 현관, 청동빛 둥근 지붕, 지붕 위 금빛 물고기 풍향계.
## 앞마당의 둥근 돌 수조에서는 마을 사람들이 기증한 물고기가 헤엄친다 (Net.museum_fish 가 바뀌면 바로 늘어난다).

## 수조 물고기 한 바퀴 시간 (초).
@export_range(4.0, 60.0, 0.5, "suffix:s") var swim_period: float = 14.0

const STONE: Array = ["#CFC6B4", "#ECE6D8"]
const WALL: Array = ["#E2D8C2", "#F8F2E4"]
const COLUMN: Array = ["#E8E2D6", "#FFFFFF"]
const DOME: Array = ["#5E9A92", "#9CCFC2"]
const GOLD: Array = ["#C9A23A", "#F0D27A"]

var _tank: Node3D = null
var _water_level: float = 0.72
var _swimmers: Dictionary[String, MeshInstance3D] = {}
var _time: float = 0.0


func _place() -> KeeperPlace:
	return GameData.museum


func _ready() -> void:
	super._ready()
	if place == null:
		return
	_add_sign(place.display_name, Vector3(0.0, 4.85, 2.18), Color("#FFF4DC"))
	_build_tank()
	Net.museum_changed.connect(func(_id: String, _by: int) -> void: _refresh_fish())
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _refresh_fish())
	_refresh_fish()


func _building_parts() -> Array:
	var parts: Array = []
	# 낮은 기단 · 본관 · 납작 지붕 · 둥근 지붕(드럼 + 돔 + 꼭대기 장식)
	parts.append(p("rbox", [15.0, 0.14, 11.4], Vector3(0.0, 0.07, -4.0), STONE, 0.1))
	parts.append(p("rbox", [13.0, 4.4, 8.0], Vector3(0.0, 2.2, -4.6), WALL, 0.06))
	parts.append(p("rbox", [13.6, 0.4, 8.6], Vector3(0.0, 4.55, -4.6), STONE, 0.25))
	parts.append(p("rbox", [13.7, 0.12, 8.7], Vector3(0.0, 4.36, -4.6), GOLD, 0.4))
	parts.append(p("cyl", [2.6, 0.8], Vector3(0.0, 5.1, -4.6), WALL, 0.1))
	parts.append(p("sphere", [2.5, 1.9, 2.5], Vector3(0.0, 5.5, -4.6), DOME))
	parts.append(p("cyl", [0.35, 0.5], Vector3(0.0, 7.45, -4.6), GOLD, 0.2))
	# 풍향계: 금빛 물고기
	parts.append(p("rod", [0.04, 0.03], Vector3(0.0, 7.6, -4.6), "#8A6A2A"))
	parts[-1]["to"] = [0.0, 8.5, -4.6]
	parts.append(p("sphere", [0.45, 0.22, 0.1], Vector3(0.05, 8.35, -4.6), GOLD))
	parts.append(p("cone", [0.2, 0.32], Vector3(-0.5, 8.35, -4.6), "#D9B44A", -1.0, Vector3(0.0, 0.0, 90.0)))
	# 현관: 기둥 여섯 개 · 지붕 · 박공 띠
	for x: float in [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]:
		parts.append(p("cyl", [0.3, 3.9], Vector3(x, 2.09, 1.15), COLUMN, 0.05))
		parts.append(p("rbox", [0.8, 0.22, 0.8], Vector3(x, 4.08, 1.15), STONE, 0.3))
		parts.append(p("rbox", [0.75, 0.2, 0.75], Vector3(x, 0.24, 1.15), STONE, 0.3))
	parts.append(p("rbox", [13.4, 0.5, 2.9], Vector3(0.0, 4.4, 0.75), STONE, 0.2))
	parts.append(p("rbox", [13.5, 0.14, 3.0], Vector3(0.0, 4.13, 0.75), GOLD, 0.4))
	for side: float in [-1.0, 1.0]:
		parts.append(p("rbox", [7.0, 0.32, 3.0], Vector3(side * 3.3, 5.15, 0.75), DOME, 0.3, Vector3(0.0, 0.0, -side * 11.0)))
	# 문: 커다란 두 짝 나무문 + 문 위 물고기 장식
	parts.append(p("rbox", [2.8, 3.3, 0.14], Vector3(0.0, 1.75, 0.03), GOLD, 0.2))
	parts.append(p("rbox", [2.5, 3.1, 0.16], Vector3(0.0, 1.65, 0.07), ["#4E3420", "#7A5232"], 0.15))
	parts.append(p("rbox", [0.05, 3.0, 0.18], Vector3(0.0, 1.65, 0.1), "#3A2616", 0.3))
	for x: float in [-0.25, 0.25]:
		parts.append(p("sphere", [0.07], Vector3(x, 1.6, 0.18), "#F0D27A"))
	parts.append(p("sphere", [0.42, 0.22, 0.08], Vector3(0.0, 3.55, 0.12), GOLD))
	parts.append(p("cone", [0.17, 0.26], Vector3(-0.48, 3.55, 0.12), "#D9B44A", -1.0, Vector3(0.0, 0.0, 90.0)))
	# 깃발 둘
	for x: float in [-6.6, 6.6]:
		parts.append(p("rod", [0.05, 0.04], Vector3(x, 0.0, 2.3), "#8A6A4A"))
		parts[-1]["to"] = [x, 4.2, 2.3]
		parts.append(p("rbox", [0.06, 1.3, 0.75], Vector3(x, 3.4, 2.7), ["#3E7FA8", "#6FA8D0"], 0.2))
		parts.append(p("sphere", [0.14, 0.08, 0.04], Vector3(x, 3.5, 2.7), "#F0D27A"))
	# 앞 화단
	for x: float in [-4.2, 4.2]:
		parts.append(p("rbox", [2.2, 0.35, 0.7], Vector3(x, 0.17, 2.55), STONE, 0.3))
		parts.append(p("blob", [1.0, 0.35, 0.32], Vector3(x, 0.45, 2.55), ["#4E8A3E", "#7FB86A"]))
		for k: int in 4:
			parts.append(p("sphere", [0.09], Vector3(x - 0.6 + 0.4 * k, 0.72, 2.6), ["#F6A6B8", "#FFD866", "#9EC1F2", "#F4F1EA"][k]))
	return parts


func _window_parts() -> Array:
	var parts: Array = []
	for x: float in [-4.6, -2.4, 2.4, 4.6]:
		parts.append(p("rbox", [1.1, 2.0, 0.06], Vector3(x, 2.3, 0.03), "#FFFFFF", 0.4))
	for side: float in [-1.0, 1.0]:
		for z: float in [-2.2, -6.2]:
			parts.append(p("rbox", [0.06, 1.8, 1.1], Vector3(side * 6.53, 2.3, z), "#FFFFFF", 0.4))
	return parts


func _colliders() -> Array[AABB]:
	var boxes: Array[AABB] = [AABB(Vector3(0.0, 2.2, -4.6), Vector3(13.2, 4.4, 8.2))]
	for x: float in [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]:
		boxes.append(AABB(Vector3(x, 2.0, 1.15), Vector3(0.6, 4.0, 0.6)))
	for x: float in [-6.6, 6.6]:
		boxes.append(AABB(Vector3(x, 2.0, 2.3), Vector3(0.3, 4.0, 0.3)))
	return boxes


## 둥근 돌 수조: 돌 테두리 + 물 (호수와 같은 물 셰이더는 수면이 불투명해서, 물고기는 등이 물 위로 살짝 보이게 헤엄친다).
func _build_tank() -> void:
	var a: Dictionary = place.extra.get("aquarium", {})
	if a.is_empty():
		return
	var size: Vector2 = Vector2(float(a.get("width", 6.0)), float(a.get("depth", 3.4)))
	_tank = Node3D.new()
	_tank.name = "Aquarium"
	add_child(_tank)
	_tank.global_position = Vector3(float(a.get("x", 0.0)), 0.0, float(a.get("z", 0.0)))
	var parts: Array = []
	# 낮은 돌 바닥 + 둘레의 돌 테두리 네 쪽 (가운데는 물).
	var wall: float = 0.38
	var rim_h: float = 0.9
	parts.append(p("rbox", [size.x + 2.0 * wall, 0.4, size.y + 2.0 * wall], Vector3(0.0, 0.2, 0.0), STONE, 0.3))
	for side: float in [-1.0, 1.0]:
		parts.append(p("rbox", [size.x + 2.0 * wall, rim_h, wall], Vector3(0.0, rim_h * 0.5, side * (size.y * 0.5 + wall * 0.5)), STONE, 0.35))
		parts.append(p("rbox", [wall, rim_h, size.y], Vector3(side * (size.x * 0.5 + wall * 0.5), rim_h * 0.5, 0.0), STONE, 0.35))
	# 물 위로 살짝 고개를 내민 수초와 물가 자갈
	for i: int in 6:
		var x: float = -size.x * 0.42 + size.x * 0.84 * float(i) / 5.0
		var z: float = (0.32 if i % 2 == 0 else -0.34) * size.y
		parts.append(p("blob", [0.12, 0.28, 0.1], Vector3(x, _water_level + 0.06, z), ["#3E7A4A", "#6FAF6A"]))
	for i: int in 8:
		var angle: float = TAU * float(i) / 8.0
		parts.append(p("blob", [0.14, 0.08, 0.12], Vector3(cos(angle) * (size.x * 0.5 + 0.55), 0.06, sin(angle) * (size.y * 0.5 + 0.5)), ["#9A968C", "#C8C2B4"]))
	_add_mesh(_tank, PartMesh.build(parts), clay_material)
	var water: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = int(size.x)
	plane.subdivide_depth = int(size.y)
	water.mesh = plane
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lake_water: Material = load("res://assets/materials/water.tres")
	if lake_water is ShaderMaterial:
		var m: ShaderMaterial = (lake_water as ShaderMaterial).duplicate()
		m.set_shader_parameter("half_extent", size * 0.5)
		water.material_override = m
	_tank.add_child(water)
	water.position = Vector3(0.0, _water_level, 0.0)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(size.x + 0.8, 1.0, size.y + 0.8)
	shape.shape = box
	shape.position.y = 0.5
	body.add_child(shape)
	_tank.add_child(body)
	# 안내판
	var label: Label3D = Label3D.new()
	label.text = "기증된 물고기"
	label.font_size = 56
	label.pixel_size = 0.008
	label.outline_size = 12
	label.modulate = Color("#FFF4DC")
	label.outline_modulate = Color("#5A3E26")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tank.add_child(label)
	label.position = Vector3(0.0, 1.35, size.y * 0.5 + 0.3)


## 기증된 물고기만큼 헤엄치는 물고기를 맞춘다.
func _refresh_fish() -> void:
	if _tank == null:
		return
	for id: String in _swimmers.keys():
		if not Net.museum_fish.has(id):
			_swimmers[id].queue_free()
			_swimmers.erase(id)
	for id: String in Net.museum_fish:
		if _swimmers.has(id):
			continue
		var fish: FishInfo = GameData.fish.get(id)
		if fish == null:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = FishModel.mesh(fish)
		mi.material_override = clay_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s: float = {"S": 0.55, "M": 0.75, "L": 1.0}.get(fish.size, 0.75)
		mi.scale = Vector3.ONE * s
		_tank.add_child(mi)
		_swimmers[id] = mi
		# 새로 들어온 물고기는 퐁 하고 튀어 오른다.
		mi.position = Vector3(0.0, _water_level + 0.6, 0.0)


func _process(delta: float) -> void:
	if _tank == null or _swimmers.is_empty():
		return
	_time += delta
	var a: Dictionary = place.extra.get("aquarium", {})
	var half: Vector2 = Vector2(float(a.get("width", 6.0)), float(a.get("depth", 3.4))) * 0.5 - Vector2(0.55, 0.45)
	var i: int = 0
	var count: int = _swimmers.size()
	for id: String in _swimmers:
		var mi: MeshInstance3D = _swimmers[id]
		# 물고기마다 다른 크기의 타원을 다른 빠르기로 돈다.
		var phase: float = TAU * float(i) / float(count)
		var speed: float = TAU / swim_period * (0.7 + 0.6 * float(id.hash() % 100) / 100.0)
		var t: float = _time * speed + phase
		var ring: float = 0.45 + 0.55 * float((i * 37) % 10) / 10.0
		var target: Vector3 = Vector3(cos(t) * half.x * ring, _water_level - 0.02 + sin(t * 3.0 + phase) * 0.015, sin(t) * half.y * ring)
		mi.position = mi.position.lerp(target, 1.0 - exp(-3.0 * delta))
		var heading: Vector3 = Vector3(-sin(t), 0.0, cos(t))
		# 물고기 모형의 머리는 -X: 머리가 헤엄치는 쪽을 보게 돌린다.
		mi.rotation.y = atan2(heading.z, -heading.x)
		i += 1
