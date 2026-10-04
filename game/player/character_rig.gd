class_name CharacterRig
extends Node3D
## 캐릭터 시각 부분. AnimationTree 가 idle ↔ walk ↔ run (속도로 블렌드), 낚시 자세(가중치로 블렌드), 도끼질(원샷)을 섞는다.
## 로컬 플레이어·원격 플레이어·주민·가방 창 미리보기가 같은 리그를 쓰고,
## 게임 로직은 set_look / set_move_speed / set_fishing / set_held / play_chop / set_eye_offset / set_outfit 만 호출한다.
## 몸·팔·다리 메시는 CharacterModel 이 겉모습(CharacterLook)마다 한 번 만들어 공유한다.

@export_group("References")
@export var tree: AnimationTree
## 애니메이션이 흔드는 몸통. 머리·눈·팔다리가 여기에 붙어 같이 움직인다.
@export var visual: Node3D
@export var body_mesh: MeshInstance3D
@export var arm_left: Node3D
@export var arm_right: Node3D
@export var leg_left: Node3D
@export var leg_right: Node3D
## 오른손에 쥐는 도구 (ArmR 아래).
@export var rod: Node3D
@export var axe: Node3D
## 정점 색을 쓰는 흰 툰 머티리얼 (몸·옷·도구 모두).
@export var clay_material: Material

@export_group("Animation")
## 클수록 idle ↔ walk 전환이 빠르다 (지수 감쇠 계수).
@export_range(0.5, 40.0, 0.5) var speed_smoothing: float = 10.0
## 클수록 낚시 자세에 빨리 들어가고 나온다.
@export_range(0.5, 40.0, 0.5) var fishing_blend_speed: float = 6.0

@export_group("Eyes")
## 눈동자가 시선 방향으로 움직이는 최대 거리 (x: 좌우, y: 위아래).
@export var eye_travel: Vector2 = Vector2(0.05, 0.035)

var held_item: String = "rod"
var look: CharacterLook = CharacterLook.for_player(1)

var _move_target: float = 0.0
var _move_value: float = 0.0
var _fishing_target: float = 0.0
var _fishing_value: float = 0.0
var _eyes: MeshInstance3D = null
var _limbs: Array[MeshInstance3D] = []
var _outfit: Dictionary[String, MeshInstance3D] = {}
var _outfit_ids: Dictionary[String, String] = {"hat": "", "top": ""}


func _ready() -> void:
	if tree != null:
		tree.active = true
	_build_static_parts()
	_apply_look()
	set_held(held_item)


## 겉모습 바꾸기 (플레이어 자리·주민마다 다르다).
func set_look(new_look: CharacterLook) -> void:
	look = new_look
	if is_node_ready():
		_apply_look()


## 0 = 서 있음, 1 = 걷기, 2 = 달리기 (0~2로 잘라 쓴다). speed_to_blend 로 속도를 바꿔 넣는다.
func set_move_speed(normalized: float) -> void:
	_move_target = clampf(normalized, 0.0, 2.0)


## 실제 속도(m/s) → 이동 애니메이션 값. 걷기 속도까지 0~1, 거기서 달리기 속도까지 1~2.
static func speed_to_blend(speed: float, walk_speed: float, run_speed: float) -> float:
	if speed <= walk_speed:
		return speed / maxf(walk_speed, 0.01)
	return 1.0 + (speed - walk_speed) / maxf(run_speed - walk_speed, 0.01)


## 입은 옷 (아이템 id, 빈 문자열 = 벗음). 윗옷은 스웨터 색을 바꾸고(tint), 무늬·장식은 아이템 데이터의 모양으로 덧붙인다.
func set_outfit(hat_id: String, top_id: String) -> void:
	var changed: bool = _outfit_ids.get("top", "") != top_id
	_set_outfit_part("hat", hat_id)
	_set_outfit_part("top", top_id)
	if changed and is_node_ready():
		_apply_look()


func outfit_item(part: String) -> String:
	return _outfit_ids.get(part, "")


func set_fishing(active: bool) -> void:
	_fishing_target = 1.0 if active else 0.0


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


## 낚싯대를 휙 던지는 동작 (한 번).
func play_cast() -> void:
	if tree != null:
		tree.set("parameters/CastShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_chopping() -> bool:
	return tree != null and bool(tree.get("parameters/ChopShot/active"))


## 눈동자 위치 (-1~1). x 양수 = 캐릭터 기준 오른쪽(+X), y 양수 = 위.
func set_eye_offset(offset: Vector2) -> void:
	if _eyes == null:
		return
	var o: Vector2 = offset.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	_eyes.position = CharacterModel.EYE_CENTER + Vector3(o.x * eye_travel.x, o.y * eye_travel.y, 0.0)


func get_eye_offset() -> Vector2:
	if _eyes == null:
		return Vector2.ZERO
	var d: Vector3 = _eyes.position - CharacterModel.EYE_CENTER
	return Vector2(d.x / eye_travel.x, d.y / eye_travel.y)


func _process(delta: float) -> void:
	if tree == null:
		return
	_move_value = lerpf(_move_value, _move_target, 1.0 - exp(-speed_smoothing * delta))
	_fishing_value = lerpf(_fishing_value, _fishing_target, 1.0 - exp(-fishing_blend_speed * delta))
	tree.set("parameters/Locomotion/blend_position", _move_value)
	tree.set("parameters/FishBlend/blend_amount", _fishing_value)


## 겉모습과 상관없는 부분: 눈, 도구, 팔다리 메시 자리.
func _build_static_parts() -> void:
	if visual == null:
		return
	_eyes = MeshInstance3D.new()
	_eyes.name = "Eyes"
	_eyes.mesh = CharacterModel.eyes()
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eyes.material_override = clay_material
	visual.add_child(_eyes)
	_eyes.position = CharacterModel.EYE_CENTER
	_add_tool_mesh(rod, CharacterModel.rod())
	_add_tool_mesh(axe, CharacterModel.axe())
	for limb: Node3D in [arm_left, arm_right, leg_left, leg_right]:
		if limb == null:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Mesh"
		mi.material_override = clay_material
		limb.add_child(mi)
		_limbs.append(mi)


func _add_tool_mesh(holder: Node3D, mesh: Mesh) -> void:
	if holder == null:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = clay_material
	holder.add_child(mi)


func _apply_look() -> void:
	var worn: CharacterLook = look
	var top_id: String = _outfit_ids.get("top", "")
	var top: ItemInfo = GameData.item(top_id) if not top_id.is_empty() else null
	if top != null and top.tint.a > 0.0:
		worn = look.duplicate_look()
		worn.top = top.tint
	if body_mesh != null:
		body_mesh.mesh = CharacterModel.body(worn)
		body_mesh.material_override = clay_material
	var arm_mesh: ArrayMesh = CharacterModel.arm(worn)
	var leg_mesh: ArrayMesh = CharacterModel.leg(worn)
	for mi: MeshInstance3D in _limbs:
		var parent: Node = mi.get_parent()
		mi.mesh = arm_mesh if parent == arm_left or parent == arm_right else leg_mesh


func _set_outfit_part(part: String, item_id: String) -> void:
	if _outfit_ids.get(part, "") == item_id or visual == null:
		return
	_outfit_ids[part] = item_id
	var mi: MeshInstance3D = _outfit.get(part)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Outfit_%s" % part
		mi.material_override = clay_material
		visual.add_child(mi)
		_outfit[part] = mi
	var info: ItemInfo = GameData.item(item_id) if not item_id.is_empty() else null
	mi.visible = info != null and not info.model.is_empty()
	mi.mesh = PartMesh.get_mesh(item_id, info.model) if mi.visible else null
