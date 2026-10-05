class_name ShopController
extends Node3D
## 마을 상점: 광장의 건물(단계별 겉모습)과 마을 멀리 떨어진 실내(단계별 방 + 상점 주인 달보).
## 문으로 드나드는 건 서버가 위치를 옮겨 준다(shop_door). 단계·포인트는 마을 공용이라 둘 중 누가 사고팔아도 오른다.

@export_group("References")
@export var player: Player
@export var camera_rig: FollowCamera
@export var sky: SkyController
@export var keeper_scene: PackedScene
## 정점 색을 쓰는 흰 툰 머티리얼 (건물·실내 메시).
@export var material: Material
## 밤에 빛나는 창문·샹들리에.
@export var glow_material: Material
@export var toast_hud: FishingHud

var level: int = 0
var keeper: NpcActor = null

var _exterior: StaticBody3D = null
var _interior: StaticBody3D = null
var _sign: Label3D = null
var _chandelier_light: OmniLight3D = null
## 문으로 걸어 들어가 드나들기를 요청했고 아직 답이 없다 (두 번 보내지 않게).
var _door_pending: bool = false
var _door_pending_since: int = 0


func _ready() -> void:
	keeper = keeper_scene.instantiate()
	add_child(keeper)
	keeper.setup(GameData.shop.keeper)
	_build(1)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _on_welcomed())
	Net.shop_updated.connect(_on_shop_updated)
	Net.shop_door_passed.connect(_on_door_passed)
	# 화질이 바뀌면 그 화질의 모형(원본 / 줄인 _low)으로 다시 짓는다.
	Quality.changed.connect(func() -> void: _build(level))
	Net.request_failed.connect(func(kind: String, _code: String) -> void:
		if kind == "shop_enter" or kind == "shop_exit":
			_door_pending = false)


## 문 쪽으로 걸어가면 저절로 드나든다 (상황 버튼도 그대로 쓸 수 있다).
## 안: 출구 앞에서 남쪽(+Z)으로 밀면 나가기. 밖: 문 앞에서 북쪽(-Z, 건물 쪽)으로 밀면 들어가기.
func _physics_process(_delta: float) -> void:
	if player == null or Net.state != Net.State.ONLINE or player.is_input_locked():
		return
	if _door_pending:
		if Time.get_ticks_msec() - _door_pending_since < 2000:
			return
		_door_pending = false
	var pos: Vector3 = player.global_position
	var vz: float = player.move_intent.z * player.max_speed
	if is_inside(pos):
		if vz > 0.5 and _flat_distance(pos, GameData.shop.exit) <= 0.8:
			_walk_through_door(false)
	elif vz < -0.5 and _flat_distance(pos, GameData.shop.door) <= 1.5 and absf(pos.x - GameData.shop.door.x) < 0.9:
		_walk_through_door(true)


func _walk_through_door(enter: bool) -> void:
	_door_pending = true
	_door_pending_since = Time.get_ticks_msec()
	if enter:
		Net.enter_shop()
	else:
		Net.exit_shop()


func is_inside(position: Vector3) -> bool:
	return GameData.shop.is_inside(position)


func near_entrance(position: Vector3, margin: float = 0.3) -> bool:
	return _flat_distance(position, GameData.shop.door) <= GameData.shop.enter_range - margin


func near_exit(position: Vector3, margin: float = 0.0) -> bool:
	return is_inside(position) and _flat_distance(position, GameData.shop.exit) <= GameData.shop.exit_range - margin


func level_name() -> String:
	return GameData.shop.level_info(level).display_name


func _on_welcomed() -> void:
	_build(Net.shop_level)
	_set_indoor(is_inside(player.global_position))


func _on_shop_updated(leveled_up: bool) -> void:
	if Net.shop_level != level:
		_build(Net.shop_level)
	if leveled_up:
		toast_hud.show_toast("상점이 '%s'(으)로 커졌어요!" % level_name(), true)


func _on_door_passed(inside: bool, position: Vector3) -> void:
	_door_pending = false
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.clear_look_direction()
	# 들어가면 계산대(북쪽)를, 나오면 광장(남쪽)을 바라본다.
	player.body.rotation.y = 0.0 if inside else PI
	if camera_rig != null:
		camera_rig.snap_to_target()
	_set_indoor(inside)


func _set_indoor(inside: bool) -> void:
	if sky != null:
		sky.indoor = inside


func _build(new_level: int) -> void:
	level = clampi(new_level, 1, 3)
	var shop: ShopData = GameData.shop
	if _exterior != null:
		_exterior.queue_free()
	if _interior != null:
		_interior.queue_free()

	# 바깥 건물: 앞면(문)이 data 의 door 위치에 오도록.
	_exterior = StaticBody3D.new()
	_exterior.name = "ShopExterior"
	add_child(_exterior)
	_exterior.global_position = Vector3(shop.door.x, 0.0, shop.door.z)
	_add_mesh(_exterior, "shop_ext_%d" % level, ShopBuilder.exterior_parts(level), material)
	# Tripo 건물 모형(앞면이 z=0)이면 창문이 모형에 칠해져 있어 따로 빛나는 유리를 붙이지 않는다.
	var ext_model: ArrayMesh = PartMesh.load_model("shop_ext_%d" % level)
	var size: Vector3 = ShopBuilder.EXTERIOR_SIZE[level]
	if ext_model == null:
		_add_mesh(_exterior, "shop_win_%d" % level, ShopBuilder.exterior_windows(level), glow_material)
		_add_box(_exterior, AABB(Vector3(-size.x * 0.5, 0.0, -size.z), size))
	else:
		# 앞에 내놓은 과일 상자·계단은 밟고 문 앞까지 갈 수 있게 충돌은 앞면에서 0.5m 들인다.
		var aabb: AABB = ext_model.get_aabb()
		_add_box(_exterior, AABB(Vector3(aabb.position.x + 0.2, 0.0, aabb.position.z), Vector3(aabb.size.x - 0.4, aabb.size.y, aabb.size.z - 0.5)))
	_sign = Label3D.new()
	_sign.text = shop.level_info(level).display_name
	_sign.font_size = 40 if level < 3 else 48
	_sign.outline_size = 12
	_sign.pixel_size = 0.006
	_sign.modulate = Color(1.0, 0.95, 0.8) if level < 3 else Color(1.0, 0.85, 0.35)
	# 간판은 차양(1·2단계)이나 지붕(3단계) 앞 끝에 붙인다. 위에서 내려다봐도 가려지지 않게.
	_sign.position = [Vector3.ZERO, Vector3(0.0, size.y - 0.15, 1.3), Vector3(0.0, size.y - 0.3, 1.15), Vector3(0.0, size.y + 0.25, 0.4)][level]
	if ext_model != null:
		# 모형 지붕 위, 앞쪽 끝 (위에서 내려다보는 카메라에 가려지지 않게).
		_sign.position = Vector3(0.0, ext_model.get_aabb().end.y + 0.3, -0.6)
	_sign.double_sided = false
	_exterior.add_child(_sign)

	# 실내: 남쪽 벽(출구)이 room_origin 에 오도록.
	_interior = StaticBody3D.new()
	_interior.name = "ShopInterior"
	add_child(_interior)
	_interior.global_position = shop.room_origin
	_add_mesh(_interior, "shop_room_%d" % level, ShopBuilder.interior_parts(level), material)
	var counter: ArrayMesh = ShopBuilder.counter_model()
	if counter != null:
		var counter_mi: MeshInstance3D = MeshInstance3D.new()
		counter_mi.name = "Counter"
		counter_mi.mesh = counter
		counter_mi.material_override = material
		counter_mi.position = ShopBuilder.counter_position(level)
		_interior.add_child(counter_mi)
	var chandelier: Array = ShopBuilder.chandelier_parts(level)
	if not chandelier.is_empty():
		_add_mesh(_interior, "shop_chandelier", chandelier, material)
	for box: AABB in ShopBuilder.interior_colliders(level):
		_add_box(_interior, box)
	# 실내 불빛: 구멍가게는 등 하나, 백화점은 샹들리에 (그림자 없음).
	var light: OmniLight3D = OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.62)
	light.light_energy = [0.0, 0.2, 0.35, 0.7][level]
	light.omni_range = ShopBuilder.INTERIOR_SIZE[level].x
	light.position = Vector3(0.0, ShopBuilder.WALL_HEIGHT - 0.2, -ShopBuilder.INTERIOR_SIZE[level].y * 0.5)
	_interior.add_child(light)
	# 백화점 소품: 피아노·소파 (아이템 데이터의 가구 모양을 그대로 쓴다).
	if level == 3:
		_add_prop("grand_piano", Vector3(-4.3, 0.1, -5.6), PI * 0.5)
		_add_prop("sofa", Vector3(4.3, 0.1, -3.2), -PI * 0.5)
	elif level == 2:
		_add_prop("round_table", Vector3(-2.5, 0.1, -2.2), 0.0)
		_add_prop("wood_chair", Vector3(-2.5, 0.1, -1.4), PI)

	var keeper_pos: Vector3 = shop.room_origin + ShopBuilder.keeper_offset(level)
	keeper.global_position = keeper_pos
	keeper.apply_state(_keeper_state(keeper_pos))


func _keeper_state(position: Vector3) -> NetNpcState:
	var state: NetNpcState = NetNpcState.new()
	state.id = GameData.shop.keeper.id
	state.position = position
	state.yaw = PI  # 출구(+Z) 쪽 손님을 바라본다
	return state


func _add_mesh(parent: Node3D, key: String, parts: Array, mat: Material) -> void:
	if parts.is_empty():
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = PartMesh.get_mesh(key, parts)
	mi.material_override = mat
	parent.add_child(mi)


func _add_box(parent: Node3D, box: AABB) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var b: BoxShape3D = BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	shape.position = box.get_center()
	parent.add_child(shape)


func _add_prop(item_id: String, offset: Vector3, yaw: float) -> void:
	var info: ItemInfo = GameData.item(item_id)
	if info == null:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = PartMesh.get_mesh(item_id, info.model)
	mi.material_override = material
	mi.position = offset
	mi.rotation.y = yaw
	_interior.add_child(mi)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
