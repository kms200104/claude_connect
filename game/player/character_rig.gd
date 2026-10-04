class_name CharacterRig
extends Node3D
## 캐릭터 시각 부분. AnimationTree 가 idle ↔ walk (속도로 블렌드), 낚시 자세(가중치로 블렌드), 도끼질(원샷)을 섞는다.
## 로컬 플레이어·원격 플레이어·주민·가방 창 미리보기가 같은 리그를 쓰고,
## 게임 로직은 set_move_speed / set_fishing / set_held / play_chop / set_eye_offset 만 호출한다.

## 두 눈을 한 메시로 합쳐 캐릭터마다 드로우콜 1개만 쓴다 (모든 리그가 공유).
static var _eyes_mesh: ArrayMesh = null

@export_group("References")
@export var capsule: MeshInstance3D
@export var tree: AnimationTree
@export var body_material: Material
## 애니메이션이 흔드는 몸통. 눈은 여기에 붙어 같이 움직인다.
@export var visual: Node3D
@export var rod: Node3D
@export var axe: Node3D
@export var eye_material: Material
## 옷·모자 메시 머티리얼 (정점 색을 쓰는 흰 툰 머티리얼).
@export var outfit_material: Material

@export_group("Animation")
## 클수록 idle ↔ walk 전환이 빠르다 (지수 감쇠 계수).
@export_range(0.5, 40.0, 0.5) var speed_smoothing: float = 10.0
## 클수록 낚시 자세에 빨리 들어가고 나온다.
@export_range(0.5, 40.0, 0.5) var fishing_blend_speed: float = 6.0

@export_group("Eyes")
## 얼굴 위 눈 위치 (Visual 기준). 정면은 -Z.
@export var eye_center: Vector3 = Vector3(0.0, 0.6, -0.33)
## 눈이 시선 방향으로 움직이는 최대 거리 (x: 좌우, y: 위아래).
@export var eye_travel: Vector2 = Vector2(0.06, 0.04)

var held_item: String = "rod"

var _move_target: float = 0.0
var _move_value: float = 0.0
var _fishing_target: float = 0.0
var _fishing_value: float = 0.0
var _eyes: MeshInstance3D = null
var _outfit: Dictionary[String, MeshInstance3D] = {}
var _outfit_ids: Dictionary[String, String] = {"hat": "", "top": ""}


func _ready() -> void:
	if capsule != null and body_material != null:
		capsule.set_surface_override_material(0, body_material)
	if tree != null:
		tree.active = true
	_build_eyes()
	set_held(held_item)


## 0 = 서 있음, 1 = 걷기, 2 = 달리기 (0~2로 잘라 쓴다). speed_to_blend 로 속도를 바꿔 넣는다.
func set_move_speed(normalized: float) -> void:
	_move_target = clampf(normalized, 0.0, 2.0)


## 실제 속도(m/s) → 이동 애니메이션 값. 걷기 속도까지 0~1, 거기서 달리기 속도까지 1~2.
static func speed_to_blend(speed: float, walk_speed: float, run_speed: float) -> float:
	if speed <= walk_speed:
		return speed / maxf(walk_speed, 0.01)
	return 1.0 + (speed - walk_speed) / maxf(run_speed - walk_speed, 0.01)


## 입은 옷 (아이템 id, 빈 문자열 = 벗음). 아이템 데이터의 모양으로 메시를 만들어 몸에 붙인다.
func set_outfit(hat_id: String, top_id: String) -> void:
	_set_outfit_part("hat", hat_id)
	_set_outfit_part("top", top_id)


func outfit_item(part: String) -> String:
	return _outfit_ids.get(part, "")


func _set_outfit_part(part: String, item_id: String) -> void:
	if _outfit_ids.get(part, "") == item_id or visual == null:
		return
	_outfit_ids[part] = item_id
	var mi: MeshInstance3D = _outfit.get(part)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Outfit_%s" % part
		mi.material_override = outfit_material
		visual.add_child(mi)
		_outfit[part] = mi
	var info: ItemInfo = GameData.item(item_id) if not item_id.is_empty() else null
	mi.visible = info != null and not info.model.is_empty()
	mi.mesh = PartMesh.get_mesh(item_id, info.model) if mi.visible else null


func set_fishing(active: bool) -> void:
	_fishing_target = 1.0 if active else 0.0


## 몸 색 바꾸기 (주민마다 다른 색).
func set_body_material(material: Material) -> void:
	body_material = material
	if capsule != null:
		capsule.set_surface_override_material(0, material)


## 손에 든 아이템 (rod, axe, 그 밖은 빈손으로 보인다).
func set_held(item_id: String) -> void:
	held_item = item_id
	if rod != null:
		rod.visible = item_id == "rod"
	if axe != null:
		axe.visible = item_id == "axe"


func play_chop() -> void:
	if tree != null:
		tree.set("parameters/ChopShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_chopping() -> bool:
	return tree != null and bool(tree.get("parameters/ChopShot/active"))


## 눈동자 위치 (-1~1). x 양수 = 캐릭터 기준 오른쪽(+X), y 양수 = 위.
func set_eye_offset(offset: Vector2) -> void:
	if _eyes == null:
		return
	var o: Vector2 = offset.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	_eyes.position = eye_center + Vector3(o.x * eye_travel.x, o.y * eye_travel.y, 0.0)


func get_eye_offset() -> Vector2:
	if _eyes == null:
		return Vector2.ZERO
	var d: Vector3 = _eyes.position - eye_center
	return Vector2(d.x / eye_travel.x, d.y / eye_travel.y)


func _process(delta: float) -> void:
	if tree == null:
		return
	_move_value = lerpf(_move_value, _move_target, 1.0 - exp(-speed_smoothing * delta))
	_fishing_value = lerpf(_fishing_value, _fishing_target, 1.0 - exp(-fishing_blend_speed * delta))
	tree.set("parameters/Locomotion/blend_position", _move_value)
	tree.set("parameters/FishBlend/blend_amount", _fishing_value)


func _build_eyes() -> void:
	if visual == null:
		return
	if _eyes_mesh == null:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		sphere.radial_segments = 8
		sphere.rings = 4
		var st: SurfaceTool = SurfaceTool.new()
		for side: float in [-1.0, 1.0]:
			st.append_from(sphere, 0, Transform3D(Basis.from_scale(Vector3(1.0, 1.25, 0.6)), Vector3(0.12 * side, 0.0, 0.0)))
		_eyes_mesh = st.commit()
	_eyes = MeshInstance3D.new()
	_eyes.name = "Eyes"
	_eyes.mesh = _eyes_mesh
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if eye_material != null:
		_eyes.material_override = eye_material
	visual.add_child(_eyes)
	_eyes.position = eye_center
