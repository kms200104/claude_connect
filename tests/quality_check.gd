extends Node
## 화질 설정 검사 (서버 없이 마을을 띄운다): 절약·고화질을 바꾸면 3D 해상도·MSAA·그림자·풀 개수·캐릭터 촘촘함·리소스팩이 바뀌는지,
## 갤럭시 S24 · Z 폴드7 화면에서 3D 해상도 배율이 맞는지.
## 사용: godot --headless --path . res://tests/quality_check.tscn

var _failed: int = 0


func _ready() -> void:
	var village: Node = load("res://game/village/village.tscn").instantiate()
	add_child(village)
	await get_tree().create_timer(0.3).timeout
	var decor: VillageDecor = village.get_node("Decor")
	var player: Player = village.get_node("Player")
	_check(Array(Quality.preset_ids()) == ["low", "high"], "설정 두 가지: %s" % str(Quality.preset_ids()))
	# 기기별 3D 해상도 (가로×세로 픽셀)
	var low_budget: int = int((Quality._presets["low"] as Dictionary)["pixel_budget"])
	var high_budget: int = int((Quality._presets["high"] as Dictionary)["pixel_budget"])
	_check(is_equal_approx(Quality.scale_for(Vector2i(1080, 2340), low_budget), 0.8), "S24 절약: 3D 80%% (%.2f)" % Quality.scale_for(Vector2i(1080, 2340), low_budget))
	_check(is_equal_approx(Quality.scale_for(Vector2i(1080, 2340), high_budget), 1.0), "S24 고화질: 3D 100%")
	_check(is_equal_approx(Quality.scale_for(Vector2i(1968, 2184), high_budget), 0.9), "폴드7 펼침 고화질: 3D 90%% (%.2f)" % Quality.scale_for(Vector2i(1968, 2184), high_budget))
	_check(is_equal_approx(Quality.scale_for(Vector2i(1080, 2520), high_budget), 1.0), "폴드7 접음(바깥 화면) 고화질: 3D 100%")
	_check(Quality.scale_for(Vector2i(1968, 2184), low_budget) <= 0.65, "폴드7 펼침 절약: 3D %.2f" % Quality.scale_for(Vector2i(1968, 2184), low_budget))

	Quality.choose("low")
	await get_tree().process_frame
	var low_grass: int = _instances(decor)
	var low_mesh: Mesh = player.rig.body_mesh.mesh
	var root: Window = get_tree().root
	_check(CharacterModel.detail == 0 and root.msaa_3d == Viewport.MSAA_2X and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "절약: 캐릭터 0단계 · MSAA 2배 · 쌍선형")
	_check(_ground_size() == 512, "절약 리소스팩: 바닥 512 (%d)" % _ground_size())
	Quality.choose("high")
	await get_tree().process_frame
	var high_grass: int = _instances(decor)
	_check(CharacterModel.detail == 1 and root.msaa_3d == Viewport.MSAA_4X and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, "고화질: 캐릭터 1단계 · MSAA 4배 · FSR")
	_check(_ground_size() == 2048, "고화질 리소스팩: 바닥 2048 (%d)" % _ground_size())
	_check(high_grass > low_grass * 1.5, "풀·꽃이 고화질에서 더 많다 (%d → %d)" % [low_grass, high_grass])
	_check(player.rig.body_mesh.mesh != low_mesh, "서 있던 캐릭터도 다시 빚는다")
	var style: WorldStyle = village.get_node("WorldStyle")
	_check(is_equal_approx(style.shadow_distance, 32.0), "그림자 거리 32m (%.1f)" % style.shadow_distance)
	Quality.choose(Quality.AUTO)
	_check(Quality.preset_id == Quality.recommended, "자동 = 기기 추천 (%s)" % Quality.recommended)
	print("QUALITY %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(0 if _failed == 0 else 1)


func _instances(node: Node) -> int:
	var total: int = 0
	for child: Node in node.get_children():
		if child is MultiMeshInstance3D and not child.is_queued_for_deletion() and (child as MultiMeshInstance3D).multimesh != null:
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func _ground_size() -> int:
	var material: ShaderMaterial = load(Quality.GROUND_MATERIAL)
	var texture: Texture2D = material.get_shader_parameter("map_texture")
	return texture.get_width() if texture != null else 0


func _check(ok: bool, label: String) -> void:
	print("[quality] %s: %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failed += 1
