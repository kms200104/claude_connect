class_name CharacterRig
extends Node3D
## 캐릭터 시각 부분. AnimationTree 가 idle ↔ walk ↔ run (속도로 블렌드), 낚시 자세(가중치로 블렌드), 도끼질(원샷)을 섞는다.
## 로컬 플레이어·원격 플레이어·주민·가방 창 미리보기가 같은 리그를 쓰고,
## 게임 로직은 set_look / set_move_speed / set_fishing / set_held / play_chop / set_eye_offset / set_outfit,
## 그리고 set_braking(미끄러지며 멈춤) / play_emote(감정표현) / play_plant(심기) / show_off(잡은 물고기 자랑) 만 호출한다.
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
## 브레이크 자세에 들어가고 나오는 빠르기.
@export_range(0.5, 40.0, 0.5) var brake_blend_speed: float = 18.0

@export_group("Eyes")
## 눈동자가 시선 방향으로 움직이는 최대 거리 (x: 좌우, y: 위아래).
@export var eye_travel: Vector2 = Vector2(0.05, 0.035)

## play_emote 로 할 수 있는 감정표현 (data/emotes/emotes.json 의 id 와 같다).
const EMOTES: PackedStringArray = ["hello", "happy", "laugh", "surprise", "love", "sad", "angry", "think", "clap", "bow", "sleepy"]
## 자랑할 때 손에 든 물건의 자리 (몸통 기준, 턱 아래 앞으로 내민 두 손 위). 머리가 커서 머리 위로 들면 팔이 닿지 않는다.
const SHOW_HOLD_POSITION: Vector3 = Vector3(0.0, 0.0, -0.44)

var held_item: String = "rod"
var look: CharacterLook = CharacterLook.for_player(1)

var _move_target: float = 0.0
var _move_value: float = 0.0
var _fishing_target: float = 0.0
var _fishing_value: float = 0.0
var _brake_target: float = 0.0
var _brake_value: float = 0.0
var _show_target: float = 0.0
var _show_value: float = 0.0
## 자랑할 때 머리 위로 드는 물건 (show_off).
var _hold: Node3D = null
var _held_before_show: String = ""
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
	if _show_target > 0.5:
		_held_before_show = item_id
		return
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


## 감정표현 한 번 (EMOTES 중 하나). 모르는 id 는 무시.
func play_emote(emote_id: String) -> void:
	if tree == null or not emote_id in EMOTES:
		return
	tree.set("parameters/EmoteSwitch/transition_request", emote_id)
	tree.set("parameters/EmoteShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_emoting() -> bool:
	return tree != null and bool(tree.get("parameters/EmoteShot/active"))


## 쪼그려 앉아 흙을 토닥이는 동작 (씨앗 심기).
func play_plant() -> void:
	if tree != null:
		tree.set("parameters/PlantShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 달리다 방향을 확 틀 때: 몸을 젖히고 앞발로 버티는 자세.
func set_braking(active: bool) -> void:
	_brake_target = 1.0 if active else 0.0


func is_braking() -> bool:
	return _brake_target > 0.5


## 잡은 물건을 두 손으로 앞으로 쭉 내밀어 들고 자랑한다. mesh 가 null 이면 내려놓는다. 드는 동안 도구는 숨긴다.
func show_off(mesh: Mesh, mesh_scale: float = 1.0, material: Material = null) -> void:
	if visual == null:
		return
	if _hold == null:
		_hold = Node3D.new()
		_hold.name = "ShowHold"
		visual.add_child(_hold)
		_hold.position = SHOW_HOLD_POSITION
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Mesh"
		_hold.add_child(mi)
	var holder: MeshInstance3D = _hold.get_node("Mesh")
	if mesh == null:
		_show_target = 0.0
		_hold.visible = false
		holder.mesh = null
		set_held(_held_before_show)
		return
	if _show_target < 0.5:
		_held_before_show = held_item
	holder.mesh = mesh
	holder.material_override = material if material != null else clay_material
	holder.scale = Vector3.ONE * mesh_scale
	# 물고기 모형은 옆모습이 XY 평면이라 그대로 들면 몸 앞뒤로 옆모습이 보인다 (머리는 캐릭터 오른쪽).
	holder.rotation = Vector3.ZERO
	_hold.visible = true
	_show_target = 1.0
	if rod != null:
		rod.visible = false
	if axe != null:
		axe.visible = false


func is_showing_off() -> bool:
	return _show_target > 0.5


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
	_brake_value = move_toward(_brake_value, _brake_target, brake_blend_speed * delta)
	tree.set("parameters/BrakeBlend/blend_amount", _brake_value)
	_show_value = lerpf(_show_value, _show_target, 1.0 - exp(-10.0 * delta))
	tree.set("parameters/ShowBlend/blend_amount", _show_value)


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
