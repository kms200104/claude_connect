extends Node3D
## 모델 확인용 사진관 (테스트 아님, 실제 렌더러 필요). 나무·캐릭터·소품을 줄지어 세우고 PNG로 찍는다.
## 사용: godot --path . res://tools/art_preview.tscn -- --what=trees --out=/tmp/preview.png
##   --what: trees / characters / outfits / furniture / clothes / shop / village (--cam=x,y,z --at=x,y,z, 서버 없이 마을 전체)
##           compare (--ids=tv,bed_double: 앞줄 = 절차 모형, 뒷줄 = Blender 모형 assets/models/items)
##           faces / faces_side (눈·코·입·피부·머리 모양을 바꿔 가며 얼굴 12개, side 는 비스듬히) / hairs (머리 모양 10가지)
##           portraits (표정 6가지를 정면에서, 얼굴 비율 비교용)
##   --stats: 찍은 프레임의 그린 삼각형·드로우콜·물체 수를 함께 출력 (village 는 --at 자리에서 게임 카메라 구도: 거리 7.5m · 48° · FOV 55)
##           expressions (감정표현 표정: 웃음 · 깜짝 · 화남 · 슬픔 · 고민 · 졸림 — 눈썹·눈물·땀방울)

var _what: String = "trees"
var _out: String = "user://preview.png"
var _cam: Vector3 = Vector3(0.0, 30.0, 30.0)
var _at: Vector3 = Vector3.ZERO
var _ids: PackedStringArray = []
var _stats: bool = false


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
		elif arg.begins_with("--ids="):
			_ids = arg.trim_prefix("--ids=").split(",")
		elif arg == "--stats":
			_stats = true
	if _what == "village":
		var village: Node = load("res://game/village/village.tscn").instantiate()
		add_child(village)
		(village.get_node("HUD") as CanvasLayer).visible = false
		await get_tree().create_timer(0.3).timeout
		if _stats:
			var pitch: float = deg_to_rad(48.0)
			var look: Vector3 = _at + Vector3(0.0, 1.0, 0.0)
			_camera(look + Vector3(0.0, sin(pitch), cos(pitch)) * 7.5, look, 55.0)
		else:
			_camera(_cam, _at, 50.0)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("[preview] %s" % _out)
		_print_stats()
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
		"faces", "faces_side", "hairs":
			var f: FaceCatalog = GameData.face
			var count: int = f.hair_styles.size() if _what == "hairs" else 12
			var columns: int = 5 if _what == "hairs" else 6
			for i: int in count:
				var ids: Dictionary = {
					"eyes": f.eyes[i % f.eyes.size()].id, "nose": f.noses[i % f.noses.size()].id,
					"mouth": f.mouths[i % f.mouths.size()].id, "skin": f.skins[(i * 3) % f.skins.size()].id,
					"hair": f.hair_styles[i % f.hair_styles.size()].id, "hair_color": f.hair_colors[i % f.hair_colors.size()].id,
					"eye_color": f.eye_colors[i % f.eye_colors.size()].id}
				if _what == "hairs":
					ids = {"hair": f.hair_styles[i].id, "hair_color": f.hair_colors[i % f.hair_colors.size()].id}
				var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
				add_child(rig)
				var row: int = i / columns
				rig.position = Vector3((float(i % columns) - float(columns - 1) * 0.5) * 0.95, 0.8 + 1.45 * float(1 - row), 0.0)
				rig.set_look(GameData.player_look(1, ids))
				rig.set_held("")
				rig.tree.active = false
				if _what == "faces_side":
					rig.rotation.y = -0.75
				elif _what == "hairs":
					rig.rotation.y = 0.5 if row == 0 else PI - 0.5
			_camera(Vector3(0.0, 1.95, -4.6), Vector3(0.0, 1.95, 0.0), 42.0)
		"portraits":
			# 얼굴 비율 비교용: 표정 6가지를 정면에서 (신난 · 곤란한 · 사랑에 빠진 · 시무룩한 · 무뚝뚝한 · 깜짝 놀란).
			var presets: Array[Dictionary] = [
				{"eyes": "happy", "nose": "button", "mouth": "laugh", "hair": "long", "hair_color": "brown"},
				{"eyes": "round", "nose": "button", "mouth": "flat", "hair": "spiky", "hair_color": "brown"},
				{"eyes": "heart", "nose": "big", "mouth": "o", "hair": "bob", "hair_color": "mint"},
				{"eyes": "droopy", "nose": "big", "mouth": "pout", "hair": "pigtails", "hair_color": "brown"},
				{"eyes": "round", "nose": "big", "mouth": "flat", "hair": "short", "hair_color": "black"},
				{"eyes": "sparkle", "nose": "button", "mouth": "open", "hair": "curly", "hair_color": "brown"}]
			for i: int in presets.size():
				var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
				add_child(rig)
				rig.position = Vector3((2.5 - float(i)) * 1.1, 0.0, 0.0)
				rig.set_look(GameData.player_look(1, presets[i]))
				rig.set_held("")
				rig.tree.active = false
			# 눈높이 정면, 멀리서 좁게 (원근 때문에 옆 머리가 돌아가 보이지 않게).
			_camera(Vector3(0.0, 0.4, -24.0), Vector3(0.0, 0.4, 0.0), 6.0)
		"expressions":
			var emotes: PackedStringArray = ["happy", "surprise", "angry", "sad", "think", "sleepy"]
			var hairs: PackedStringArray = ["short", "bob", "spiky", "long", "buzz", "pigtails"]
			for i: int in emotes.size():
				var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
				add_child(rig)
				rig.position = Vector3((2.5 - float(i)) * 1.1, 0.0, 0.0)
				rig.set_look(GameData.player_look(1, {"hair": hairs[i], "hair_color": "brown"}))
				rig.set_held("")
				rig.tree.active = false
				rig.play_emote(emotes[i])
				# 애니메이션 트리를 멈춰 두었으니 표정이 바로 감춰지지 않게 리그 갱신을 끈다.
				rig.set_process(false)
			_camera(Vector3(0.0, 0.5, -24.0), Vector3(0.0, 0.45, 0.0), 4.0)
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
				mi.mesh = PartMesh.get_mesh("shop_ext_%d" % level, ShopBuilder.exterior_parts(level))
				mi.material_override = load("res://assets/materials/foliage.tres")
				mi.position = Vector3([0.0, -7.0, 0.0, 9.0][level], 0.0, 0.0)
				add_child(mi)
			_camera(Vector3(0.0, 7.0, 16.0), Vector3(0.0, 2.0, -2.0), 45.0)
		"compare":
			# 왼쪽 = 절차 모형, 오른쪽 = Blender 모형. 아이템마다 한 줄씩 (위에서 아래로).
			var z: float = 0.0
			for id: String in _ids:
				var info: ItemInfo = GameData.item(id)
				var procedural: ArrayMesh = PartMesh.build(info.model)
				var size: Vector3 = procedural.get_aabb().size
				for col: int in 2:
					var mi: MeshInstance3D = MeshInstance3D.new()
					mi.mesh = procedural if col == 0 else PartMesh.load_model(id)
					mi.material_override = load("res://assets/materials/foliage.tres")
					mi.position = Vector3((col - 0.5) * (maxf(size.x, 0.6) + 0.5), 0.0, -z)
					add_child(mi)
				z += maxf(size.z, 0.6) + 0.6
			_camera(Vector3(0.0, 2.2 + z * 0.55, 2.6 + z * 0.4), Vector3(0.0, 0.3, -z * 0.45), 40.0)
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
	_print_stats()
	get_tree().quit()


func _print_stats() -> void:
	if not _stats:
		return
	var vp: Viewport = get_viewport()
	var tris: int = vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	var draws: int = vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var objects: int = vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
	var shadow_tris: int = vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	print("[stats] tris %d · draws %d · objects %d · shadow tris %d · 3d scale %.2f" % [tris, draws, objects, shadow_tris, vp.scaling_3d_scale])


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
