class_name NpcCrowd
extends Node3D
## 주민 전체와 주민 집. 주민 목록·집 위치는 data/npcs/npcs.json, 주민 위치는 서버가 보낸다.

@export var actor_scene: PackedScene
## 주민들이 돌아보는 내 캐릭터 (없으면 "player" 무리에서 찾는다).
@export var look_target: Node3D
@export_group("House Materials")
## 정점 색을 쓰는 흰 툰 머티리얼 (벽·지붕·문·화분 모두).
@export var clay_material: Material
## 밤에 켜지는 창문 유리.
@export var window_material: Material

const HOUSE_SIZE: Vector3 = Vector3(4.0, 2.4, 3.0)
## 기분별로 혼자 하는 몸짓 (calm 은 조용히 지낸다).
const MOOD_GESTURES: Dictionary = {
	"happy": ["happy", "clap"], "excited": ["surprise", "happy"], "sad": ["sad"], "grumpy": ["angry", "think"], "sleepy": ["sleepy"],
}

## 이 간격(초)쯤마다 화면 안의 주민 하나가 기분대로 혼자 몸짓을 하며 중얼거린다.
@export_range(2.0, 60.0, 0.5, "suffix:s") var mood_gesture_interval: float = 11.0

var _gesture_left: float = 6.0

var _actors: Dictionary[String, NpcActor] = {}
## Tripo 집 모형을 그리는 메시들 (화질이 바뀌면 그 화질의 모형으로 바꿔 끼운다).
var _house_models: Array[MeshInstance3D] = []


func _ready() -> void:
	for npc: NpcInfo in GameData.npcs.values():
		if npc.has_house:
			_build_house(npc)
		var actor: NpcActor = actor_scene.instantiate()
		add_child(actor)
		actor.setup(npc)
		_actors[npc.id] = actor
	Net.npcs_received.connect(_on_npcs_received)
	Quality.changed.connect(_on_quality_changed)
	Net.profile_updated.connect(_refresh_marks)
	Net.inventory_updated.connect(func(_slots: Array[InventoryItem], _held: int) -> void: _refresh_marks())
	_refresh_marks()


func actor(id: String) -> NpcActor:
	return _actors.get(id)


func _process(delta: float) -> void:
	if look_target == null:
		look_target = get_tree().get_first_node_in_group(&"player") as Node3D
		for a: NpcActor in _actors.values():
			a.look_target = look_target
	_gesture_left -= delta
	if _gesture_left > 0.0 or Net.state != Net.State.ONLINE:
		return
	_gesture_left = randf_range(mood_gesture_interval * 0.6, mood_gesture_interval * 1.4)
	var candidates: Array[NpcActor] = []
	for a: NpcActor in _actors.values():
		if a.talking_with == 0 and a.activity.is_empty() and MOOD_GESTURES.has(a.mood) and a.rig != null and a.rig.tree != null and a.rig.tree.active:
			candidates.append(a)
	if candidates.is_empty():
		return
	var who: NpcActor = candidates[randi() % candidates.size()]
	var options: Array = MOOD_GESTURES[who.mood]
	var line: String = MoodSpeech.apply(GameData.dialogue_line(who.info.personality, "mutter_" + who.mood), who.mood, who.info)
	who.play_emote(str(options[randi() % options.size()]), line)


## 말을 걸 수 있는 가장 가까운 주민 (다른 사람과 이야기 중인 주민은 뺀다). 없으면 빈 문자열.
func nearest_talkable(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for id: String in _actors:
		var a: NpcActor = _actors[id]
		# 식당 의자에 앉아 있는 동안(돌아다니는 모습을 숨긴 동안)은 말을 걸 수 없다.
		if not a.visible or (a.talking_with != 0 and a.talking_with != Net.my_id):
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


## 주민 집: 돌 기초 · 파스텔 벽 · 기와 지붕(주민 색) · 굴뚝 · 문 · 창문과 꽃 상자. 메시 2개(집 + 밤에 빛나는 유리) + 충돌 상자.
## 문은 집의 +Z 쪽 (데이터의 yaw로 돌린다). 같은 주민 색은 메시를 공유한다.
func _build_house(npc: NpcInfo) -> void:
	var house: StaticBody3D = StaticBody3D.new()
	house.name = "House_%s" % npc.id
	add_child(house)
	house.global_position = npc.house_position
	house.rotation.y = npc.house_yaw

	# Tripo 로 만든 집 모형(tools/blender/import_tripo.py)이 있으면 모든 주민이 그 집을 쓴다 (텍스처 머티리얼). 창문은 밤에 빛나지 않는다.
	var model: ArrayMesh = PartMesh.load_model("npc_house")
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = HOUSE_SIZE
	if model != null:
		box.size = Vector3(model.get_aabb().size.x, HOUSE_SIZE.y, model.get_aabb().size.z) - Vector3(0.3, 0.0, 0.3)
	shape.shape = box
	shape.position.y = HOUSE_SIZE.y * 0.5
	house.add_child(shape)

	if model != null:
		_add_mesh(house, model, Vector3.ZERO, PartMesh.material_for("npc_house", clay_material))
		_house_models.append(house.get_child(house.get_child_count() - 1) as MeshInstance3D)
		return
	var key: String = npc.color.to_html(false)
	if not _house_meshes.has(key):
		_house_meshes[key] = _house_mesh(npc.color)
	_add_mesh(house, _house_meshes[key], Vector3.ZERO, clay_material)
	_add_mesh(house, _glass_mesh(), Vector3.ZERO, window_material)


func _on_quality_changed() -> void:
	var model: ArrayMesh = PartMesh.load_model("npc_house")
	for mi: MeshInstance3D in _house_models:
		mi.mesh = model


static var _house_meshes: Dictionary[String, ArrayMesh] = {}
static var _glass: ArrayMesh = null


static func _house_mesh(accent: Color) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var w: float = HOUSE_SIZE.x
	var h: float = HOUSE_SIZE.y
	var d: float = HOUSE_SIZE.z
	var front: float = d * 0.5
	var wall: Color = Color("#F6EEDF").lerp(accent, 0.18)
	var trim: Color = Color("#FFF9EF")
	var wood: Color = Color("#9B6A45")
	# 돌 기초와 벽 (아래쪽이 살짝 어둡다).
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.12, 0.0), Vector3(w + 0.3, 0.3, d + 0.3), 0.25, Color("#B9B3A8"), Basis(), 12, 6)
	ClayMesh.add_rounded_box(st, Vector3(0.0, h * 0.5 + 0.1, 0.0), Vector3(w, h, d), 0.12, ClayMesh.vertical_gradient(wall.darkened(0.12), wall, 0.6), Basis(), 16, 10)
	# 박공 (지붕 아래 세모 벽) 양쪽.
	var gable: PrismMesh = PrismMesh.new()
	gable.size = Vector3(d, 1.15, w - 0.1)
	ClayMesh.add_primitive(st, gable, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, h + 0.1 + 0.575, 0.0)), wall)
	# 지붕: 앞뒤 두 장, 줄마다 어두운 기와 줄무늬. 용마루는 둥근 막대.
	var roof_color: Color = accent.darkened(0.12)
	var ridge: Vector3 = Vector3(0.0, h + 1.35, 0.0)
	for side: float in [1.0, -1.0]:
		var eave: Vector3 = Vector3(0.0, h - 0.05, side * (front + 0.45))
		var dir: Vector3 = (eave - ridge).normalized()
		var tiles: Callable = func(local: Vector3, normal: Vector3) -> Color:
			var along: float = (local - ridge).dot(dir)
			var row: float = fposmod(along * 3.2, 1.0)
			var shade: float = 0.0 if normal.y > 0.2 else 0.15
			return roof_color.darkened(shade + (0.12 if row > 0.82 else 0.0)).lightened(0.05 * clampf(1.0 - along * 0.3, 0.0, 1.0))
		ClayMesh.add_rounded_box(st, (ridge + eave) * 0.5, Vector3(w + 0.7, 0.2, ridge.distance_to(eave) + 0.1), 0.2, tiles, Basis.looking_at(dir, Vector3.UP), 12, 6)
	ClayMesh.add_capsule(st, ridge + Vector3(-(w + 0.7) * 0.5, 0.05, 0.0), ridge + Vector3((w + 0.7) * 0.5, 0.05, 0.0), 0.12, roof_color.darkened(0.2), 8, 2)
	# 굴뚝.
	ClayMesh.add_rounded_box(st, Vector3(w * 0.28, h + 1.25, -0.45), Vector3(0.45, 1.0, 0.45), 0.2, ClayMesh.vertical_gradient(Color("#A9614C"), Color("#C98A6E"), 1.0), Basis(), 8, 6)
	ClayMesh.add_rounded_box(st, Vector3(w * 0.28, h + 1.78, -0.45), Vector3(0.55, 0.12, 0.55), 0.3, Color("#8E5240"), Basis(), 8, 4)
	# 문: 흰 문틀 + 나무 문 + 금색 손잡이 + 둥근 창 + 디딤돌.
	var door_x: float = -0.8
	ClayMesh.add_rounded_box(st, Vector3(door_x, 0.98, front + 0.02), Vector3(1.1, 1.85, 0.12), 0.25, trim, Basis(), 10, 6)
	ClayMesh.add_rounded_box(st, Vector3(door_x, 0.93, front + 0.07), Vector3(0.88, 1.66, 0.1), 0.2, ClayMesh.vertical_gradient(wood.darkened(0.15), wood.lightened(0.08), 1.0), Basis(), 10, 6)
	ClayMesh.add_ellipsoid(st, Vector3(door_x + 0.3, 0.9, front + 0.14), Vector3(0.05, 0.05, 0.04), Color("#E8B84A"), 8, 4)
	ClayMesh.add_ellipsoid(st, Vector3(door_x, 1.95, front + 0.1), Vector3(0.66, 0.22, 0.08), accent.lightened(0.15), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(door_x, 0.06, front + 0.55), Vector3(1.0, 0.12, 0.55), 0.4, Color("#C8C1B5"), Basis(), 10, 4)
	# 창문: 흰 창틀 + 십자 창살 + 아래 꽃 상자.
	var win: Vector3 = Vector3(0.95, 1.5, front + 0.03)
	ClayMesh.add_rounded_box(st, win, Vector3(1.0, 0.85, 0.12), 0.25, trim, Basis(), 10, 6)
	ClayMesh.add_box(st, win + Vector3(0.0, 0.0, 0.09), Vector3(0.06, 0.62, 0.04), trim)
	ClayMesh.add_box(st, win + Vector3(0.0, 0.0, 0.09), Vector3(0.78, 0.06, 0.04), trim)
	ClayMesh.add_rounded_box(st, win + Vector3(0.0, -0.55, 0.12), Vector3(1.05, 0.22, 0.28), 0.3, wood, Basis(), 10, 4)
	var petals: Array[Color] = [Color("#F6A6B8"), Color("#FFD866"), accent.lightened(0.2), Color("#F6A6B8")]
	for i: int in 4:
		var at: Vector3 = win + Vector3(-0.36 + 0.24 * float(i), -0.38, 0.14)
		ClayMesh.add_ellipsoid(st, at, Vector3(0.1, 0.08, 0.1), Color("#6FA35A"), 8, 4)
		ClayMesh.add_ellipsoid(st, at + Vector3(0.0, 0.07, 0.03), Vector3(0.06, 0.04, 0.06), petals[i], 6, 3)
	# 옆벽 둥근 창 (밤에 빛나는 유리는 따로).
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_torus(st, Vector3(side * (w * 0.5 + 0.03), 1.5, 0.0), 0.33, 0.06, trim, 14, 4, Basis(Vector3.FORWARD, PI * 0.5))
	return ClayMesh.commit(st)


## 창 유리 (밤에 빛난다): 앞 창 + 옆 둥근 창 둘.
static func _glass_mesh() -> ArrayMesh:
	if _glass != null:
		return _glass
	var st: SurfaceTool = ClayMesh.begin()
	var front: float = HOUSE_SIZE.z * 0.5
	ClayMesh.add_box(st, Vector3(0.95, 1.5, front + 0.07), Vector3(0.8, 0.66, 0.04), Color.WHITE)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(side * (HOUSE_SIZE.x * 0.5 + 0.02), 1.5, 0.0), Vector3(0.03, 0.3, 0.3), Color.WHITE, 12, 4)
	_glass = ClayMesh.commit(st)
	return _glass


func _add_mesh(parent: Node3D, mesh: Mesh, offset: Vector3, material: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = offset
	parent.add_child(mi)
