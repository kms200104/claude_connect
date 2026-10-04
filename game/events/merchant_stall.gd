class_name MerchantStall
extends Node3D
## 떠돌이 상인 누리와 노점 (보라 줄무늬 파라솔 · 깔개 · 보따리 · 상자). 떠돌이 상인 이벤트가 열린 동안만 광장에 선다.
## 사고팔기는 대화(DialogueController) → 상점 창(떠돌이 상인 모드)으로 하고, 판정은 서버가 한다.

@export var actor_scene: PackedScene
@export var clay_material: Material

var actor: NpcActor = null
var _info: EventInfo = null
var _stall: MeshInstance3D = null


func _ready() -> void:
	_info = GameData.event_info(EventInfo.MERCHANT)
	if _info == null or _info.npc == null:
		return
	global_position = _info.spot
	actor = actor_scene.instantiate()
	add_child(actor)
	actor.setup(_info.npc)
	actor.global_position = _info.spot
	var state: NetNpcState = NetNpcState.new()
	state.id = _info.npc.id
	state.position = _info.spot
	state.yaw = _info.spot_yaw
	actor.apply_state(state)
	_stall = MeshInstance3D.new()
	_stall.mesh = _stall_mesh()
	_stall.material_override = clay_material
	_stall.rotation.y = _info.spot_yaw + PI  # 노점 모양은 +Z 가 앞, 상인은 -Z 를 본다
	add_child(_stall)
	var collider: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 2.0
	shape.shape = cyl
	shape.position.y = 1.0
	collider.add_child(shape)
	add_child(collider)
	Net.events_changed.connect(func(_started: PackedStringArray) -> void: _refresh())
	Net.state_changed.connect(func(_s: int) -> void: _refresh())
	_refresh()


func npc_id() -> String:
	return _info.npc.id if _info != null and _info.npc != null else ""


func info() -> NpcInfo:
	return _info.npc if _info != null else null


func is_open() -> bool:
	return visible


## 말을 걸 수 있는 거리 안인지.
func near(position: Vector3, max_distance: float) -> bool:
	return visible and actor != null and Vector2(position.x - actor.global_position.x, position.z - actor.global_position.z).length() <= max_distance


func _refresh() -> void:
	var open: bool = Net.state == Net.State.ONLINE and Net.event_active(EventInfo.MERCHANT) != null
	visible = open
	for child: Node in get_children():
		if child is StaticBody3D:
			(child.get_child(0) as CollisionShape3D).disabled = not open


## 노점: 상인 뒤의 파라솔과 앞쪽 깔개 위의 보따리·상자 (상인 기준 +Z 가 앞).
static func _stall_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var purple: Color = Color("#9A6AB8")
	var cream: Color = Color("#FFF4E8")
	ClayMesh.add_rod(st, Vector3(0.0, 0.0, -0.75), Vector3(0.0, 2.5, -0.75), 0.04, 0.035, Color("#8A5A36"), 6)
	for i: int in 8:
		var a0: float = TAU * float(i) / 8.0
		var color: Color = purple if i % 2 == 0 else cream
		var dir: Vector3 = Vector3(cos(a0 + TAU / 16.0), 0.0, sin(a0 + TAU / 16.0))
		ClayMesh.add_ellipsoid(st, Vector3(0.0, 2.35, -0.75) + dir * 0.62 - Vector3(0.0, 0.14, 0.0), Vector3(0.62, 0.05, 0.3), color, 8, 3, Basis(Vector3.UP, -(a0 + TAU / 16.0)) * Basis(Vector3.BACK, -0.35))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 2.52, -0.75), Vector3(0.08, 0.08, 0.08), Color("#F2C14E"), 6, 3)
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(1.1, 1.1, 0.0, 0.03, 0.02, 1), 18, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), Vector3(0.0, 0.0, 0.55)), Color("#C8504A"))
	ClayMesh.add_torus(st, Vector3(0.0, 0.03, 0.55), 0.9, 0.04, Color("#F2C14E"), 18, 4, Basis.from_scale(Vector3(1.0, 1.0, 0.7)))
	ClayMesh.add_ellipsoid(st, Vector3(-0.55, 0.28, 0.5), Vector3(0.3, 0.28, 0.28), ClayMesh.vertical_gradient(Color("#7A4A8A"), Color("#B07AC8"), 1.0), 10, 6, Basis(), ClayMesh.blob_wobble(9, 0.1, 3))
	ClayMesh.add_ellipsoid(st, Vector3(-0.55, 0.58, 0.5), Vector3(0.08, 0.06, 0.08), Color("#F2C14E"), 6, 3)
	ClayMesh.add_rounded_box(st, Vector3(0.6, 0.2, 0.55), Vector3(0.5, 0.4, 0.4), 0.25, ClayMesh.vertical_gradient(Color("#8A5A36"), Color("#C99466"), 1.0), Basis(Vector3.UP, 0.3), 8, 5)
	for i: int in 3:
		ClayMesh.add_ellipsoid(st, Vector3(0.48 + 0.12 * float(i), 0.46, 0.55), Vector3(0.07, 0.07, 0.07), [Color("#F7D35A"), Color("#9EC1F2"), Color("#F6A6B8")][i], 6, 3)
	return ClayMesh.commit(st)
