extends Node
## 아이템 아이콘 사진관 (실제 렌더러 필요): 아이템 모형(data 의 model, 물고기 look)을 점토 조명으로 찍어
## assets/icons/items/<id>.png (128×128, 투명 배경)로 저장한다. 참고 그림에서 오려 낸 아이콘(HAND_MADE)은 건드리지 않는다.
## 머리 모양 그림(거울 창)도 찍는다: assets/ui/face/hair_<id>.png (--only=hair 로 머리만).
## 식당 요리 그림도 찍는다: assets/icons/dishes/<id>.png (--only=dishes 로 요리만).
## 사용: godot --path . res://tools/render_icons.tscn [-- --only=wood,acorn]

## tools/art/extract_reference.py 가 참고 그림에서 오려 낸 아이콘.
const HAND_MADE: PackedStringArray = ["rod", "log_stool", "braided_rug", "bookshelf", "quilt_bed", "flower_pot", "floor_lamp",
		"wooden_bucket", "pale_chub", "goldfish", "river_puffer", "spiral_shell"]
const OUT_DIR: String = "res://assets/icons/items"
const RENDER_SIZE: int = 256
const ICON_SIZE: int = 128

var _viewport: SubViewport = null
var _holder: MeshInstance3D = null
var _camera: Camera3D = null
var _material: ShaderMaterial = null


func _ready() -> void:
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	RenderingServer.global_shader_parameter_set("world_curve_strength", 0.0)
	_build_studio()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var count: int = 0
	for info: ItemInfo in GameData.items.values():
		if info.id in HAND_MADE or (not only.is_empty() and not info.id in only):
			continue
		var built: Array = _mesh_for(info)
		if built.is_empty():
			print("[icons] 모형 없음: %s" % info.id)
			continue
		await _shoot(info.id, built[0], built[1])
		count += 1
	# 식당 요리 (assets/icons/dishes/<id>.png): 접시를 비스듬히 위에서.
	if only.is_empty() or "dishes" in only:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DishArt.ICON_DIR))
		for r: RecipeInfo in GameData.econ.recipe_order:
			await _shoot(r.id, DishArt.mesh(r.id), Vector3(0.0, 1.0, 0.85), DishArt.ICON_DIR)
			count += 1
	# 이벤트 그림: 선물 풍선 (assets/ui/icons/gift.png).
	if only.is_empty() or "gift" in only:
		await _shoot("gift", DropField.gift_mesh(0), Vector3(0.5, 0.35, 1.0), "res://assets/ui/icons")
		count += 1
	# 거울 창의 머리 모양 그림: 기본 얼굴에 머리 모양만 바꿔 3/4 앞모습.
	if only.is_empty() or "hair" in only:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/face"))
		for hair: FaceCatalog.Part in GameData.face.hair_styles:
			var look: CharacterLook = GameData.player_look(1, {"hair": hair.id, "hair_color": "brown"})
			await _shoot_head("hair_%s" % hair.id, look)
			count += 1
	print("[icons] %d개 저장" % count)
	get_tree().quit()


## [메시, 카메라 방향] 또는 빈 배열.
func _mesh_for(info: ItemInfo) -> Array:
	if info.is_fish():
		var fish: FishInfo = GameData.fish.get(info.id)
		return [FishModel.mesh(fish), Vector3(0.12, 0.35, 1.0)] if fish != null else []
	if info.is_clothing() and info.wear_slot == "top":
		return [_shirt(info), Vector3(0.35, 0.3, -1.0)]
	if info.model.is_empty():
		return []
	var mesh: ArrayMesh = PartMesh.build(info.model)
	var view: Vector3 = Vector3(0.6, 0.55, 1.0)
	if info.id == "braided_rug":
		view = Vector3(0.0, 1.4, 0.7)
	elif info.is_clothing():
		view = Vector3(0.4, 0.6, -1.0)
	return [mesh, view]


## 윗옷 아이콘: 머리 없는 몸통 + 소매 (입었을 때 색) 위에 무늬를 덧붙인다.
func _shirt(info: ItemInfo) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var color: Color = info.tint if info.tint.a > 0.0 else Color("#F1E8D6")
	var torso: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -0.37), Vector2(0.2, -0.37), Vector2(0.225, -0.33), Vector2(0.215, -0.22), Vector2(0.225, -0.1),
		Vector2(0.215, -0.02), Vector2(0.16, 0.03), Vector2(0.0, 0.05)])
	ClayMesh.add_lathe(st, torso, 16, Transform3D(), ClayMesh.vertical_gradient(color.darkened(0.12), color, 1.0))
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.125, 0.115, -0.01, 0.1, 0.03, 2), 12, Transform3D(), color.darkened(0.05))
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(st, Vector3(0.22 * side, -0.04, 0.0), Vector3(0.36 * side, -0.24, 0.0), 0.068, color, 10, 3)
	PartMesh.append(st, info.model)
	return ClayMesh.commit(st)


func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.95, 0.9)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-30.0), 0.0)
	key.light_energy = 0.85
	key.light_color = Color(1.0, 0.96, 0.9)
	_viewport.add_child(key)
	_camera = Camera3D.new()
	_camera.fov = 26.0
	_viewport.add_child(_camera)
	_camera.current = true
	_material = (load("res://assets/materials/foliage.tres") as ShaderMaterial).duplicate()
	_material.shader = load("res://assets/shaders/lit_world.gdshader")
	_holder = MeshInstance3D.new()
	_holder.material_override = _material
	_viewport.add_child(_holder)


## 캐릭터 머리 (몸 메시 + 눈 메시)를 같은 각도로.
func _shoot_head(id: String, look: CharacterLook) -> void:
	_holder.mesh = CharacterModel.body(look)
	var eyes: MeshInstance3D = MeshInstance3D.new()
	eyes.mesh = CharacterModel.eyes(look)
	eyes.material_override = _material
	eyes.position = CharacterModel.HEAD_CENTER
	_viewport.add_child(eyes)
	var center: Vector3 = CharacterModel.HEAD_CENTER + Vector3(0.0, 0.02, 0.0)
	# 캐릭터 앞 = -Z. 살짝 옆에서.
	_camera.look_at_from_position(center + Vector3(0.45, 0.25, -1.0).normalized() * 2.5, center)
	for i: int in 3:
		await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	var path: String = ProjectSettings.globalize_path("res://assets/ui/face/%s.png" % id)
	image.save_png(path)
	print("[icons] %s" % path)
	eyes.queue_free()


func _shoot(id: String, mesh: ArrayMesh, view: Vector3, dir: String = OUT_DIR) -> void:
	_holder.mesh = mesh
	var box: AABB = mesh.get_aabb()
	var radius: float = box.size.length() * 0.5
	var center: Vector3 = box.get_center()
	var distance: float = radius / sin(deg_to_rad(_camera.fov * 0.5)) * 0.82
	_camera.look_at_from_position(center + view.normalized() * distance, center)
	for i: int in 3:
		await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [dir, id])
	image.save_png(path)
	print("[icons] %s" % path)
