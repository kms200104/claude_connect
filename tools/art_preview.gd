extends Node3D
## 모델 확인용 사진관 (테스트 아님, 실제 렌더러 필요). 나무·캐릭터·소품을 줄지어 세우고 PNG로 찍는다.
## 사용: godot --path . res://tools/art_preview.tscn -- --what=trees --out=/tmp/preview.png
##   --what: trees / characters / outfits / furniture / clothes / shop / village (--cam=x,y,z --at=x,y,z, 서버 없이 마을 전체)

var _what: String = "trees"
var _out: String = "user://preview.png"
var _cam: Vector3 = Vector3(0.0, 30.0, 30.0)
var _at: Vector3 = Vector3.ZERO


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--what="):
			_what = arg.trim_prefix("--what=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--cam="):
			_cam = _vec(arg.trim_prefix("--cam="))
		elif arg.begins_with("--at="):
			_at = _vec(arg.trim_prefix("--at="))
	if _what == "village":
		var village: Node = load("res://game/village/village.tscn").instantiate()
		add_child(village)
		(village.get_node("HUD") as CanvasLayer).visible = false
		await get_tree().create_timer(0.3).timeout
		_camera(_cam, _at, 50.0)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("[preview] %s" % _out)
		get_tree().quit()
		return
	_stage()
	match _what:
		"trees":
			_row_meshes(["round", "pine", "birch", "stump", "sapling"].map(func(k: String) -> Mesh: return TreeField._mesh(k)), 3.2)
			_camera(Vector3(0.0, 4.5, 13.0), Vector3(0.0, 1.6, 0.0), 40.0)
		"characters":
			var looks: Array[CharacterLook] = [CharacterLook.for_player(1), CharacterLook.for_player(2)]
			for npc: NpcInfo in GameData.npcs.values():
				looks.append(npc.look)
			looks.append(GameData.shop.keeper.look)
			for i: int in looks.size():
				var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
				add_child(rig)
				rig.position = Vector3((float(i) - float(looks.size() - 1) * 0.5) * 1.15, 0.8, 0.0)
				rig.set_look(looks[i])
				rig.set_held("rod" if i == 0 else ("axe" if i == 1 else ""))
				if i % 3 == 2:
					rig.rotation.y = 0.6
			_camera(Vector3(0.0, 1.6, -6.5), Vector3(0.0, 0.85, 0.0), 40.0)
		"outfits":
			var worn: Array[ItemInfo] = []
			for info: ItemInfo in GameData.items.values():
				if info.is_clothing():
					worn.append(info)
			for i: int in worn.size():
				var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
				add_child(rig)
				rig.position = Vector3((float(i) - float(worn.size() - 1) * 0.5) * 1.05, 0.8, 0.0)
				rig.set_look(CharacterLook.for_player(1 + i % 2))
				rig.set_held("")
				rig.set_outfit(worn[i].id if worn[i].wear_slot == "hat" else "", worn[i].id if worn[i].wear_slot == "top" else "")
			_camera(Vector3(0.0, 2.0, -7.0), Vector3(0.0, 0.85, 0.0), 40.0)
		"shop":
			for level: int in [1, 2, 3]:
				var mi: MeshInstance3D = MeshInstance3D.new()
				mi.mesh = PartMesh.build(ShopBuilder.exterior_parts(level))
				mi.material_override = load("res://assets/materials/foliage.tres")
				mi.position = Vector3([0.0, -7.0, 0.0, 9.0][level], 0.0, 0.0)
				add_child(mi)
			_camera(Vector3(0.0, 7.0, 16.0), Vector3(0.0, 2.0, -2.0), 45.0)
		"furniture", "clothes":
			var kind: String = ItemInfo.KIND_FURNITURE if _what == "furniture" else ItemInfo.KIND_CLOTHING
			var meshes: Array = []
			for info: ItemInfo in GameData.items.values():
				if info.kind == kind and not info.model.is_empty():
					meshes.append(PartMesh.get_mesh(info.id, info.model))
			_grid_meshes(meshes, 2.0, 5)
			_camera(Vector3(0.0, 7.5, 9.5), Vector3(0.0, 0.0, 0.5), 45.0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	print("[preview] %s" % _out)
	get_tree().quit()


func _stage() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.87, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.98, 0.9, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-150.0), 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _material(Color(0.86, 0.87, 0.88))
	add_child(floor_mesh)


func _material(color: Color) -> ShaderMaterial:
	var m: ShaderMaterial = (load("res://assets/materials/foliage.tres") as ShaderMaterial).duplicate()
	m.set_shader_parameter("albedo", color)
	return m


func _row_meshes(meshes: Array, spacing: float) -> void:
	for i: int in meshes.size():
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.material_override = load("res://assets/materials/foliage.tres")
		mi.position = Vector3((float(i) - float(meshes.size() - 1) * 0.5) * spacing, 0.0, 0.0)
		add_child(mi)


func _grid_meshes(meshes: Array, spacing: float, columns: int) -> void:
	for i: int in meshes.size():
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.material_override = load("res://assets/materials/foliage.tres")
		mi.position = Vector3((float(i % columns) - float(columns - 1) * 0.5) * spacing, 0.0, float(i / columns) * spacing - 1.0)
		add_child(mi)


static func _vec(text: String) -> Vector3:
	var p: PackedStringArray = text.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() >= 3 else Vector3.ZERO


func _camera(from: Vector3, at: Vector3, fov: float) -> void:
	var cam: Camera3D = Camera3D.new()
	cam.fov = fov
	add_child(cam)
	cam.look_at_from_position(from, at)
	cam.current = true
