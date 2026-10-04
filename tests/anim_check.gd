extends Node
## AnimationTree 블렌딩 검증: idle / walk / fishing 자세가 서로 다르고, 중간 가중치에서 섞이는지 본다.

var _failures: int = 0


func _ready() -> void:
	var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
	add_child(rig)
	var visual: Node3D = rig.get_node("Visual")
	var rod: Node3D = rig.rod
	await _settle(rig, 0.0, false)
	var idle_lean: float = visual.rotation.x
	var idle_rod: float = rod.rotation.x
	var idle_rod_up: float = rod.global_basis.y.normalized().y
	await _settle(rig, 1.0, false)
	var walk_lean: float = visual.rotation.x
	await _settle(rig, 0.0, true)
	var fish_rod: float = rod.rotation.x
	var fish_rod_dir: Vector3 = rod.global_basis.y.normalized()
	var fish_lean: float = visual.rotation.x
	await _settle(rig, 0.5, false)
	var half_lean: float = visual.rotation.x
	_check(idle_rod_up > 0.6, "idle: 낚싯대를 세워 둠 (위쪽 성분 %.2f)" % idle_rod_up)
	_check(walk_lean < -0.1, "walk: 앞으로 기울어짐 (lean=%.2f)" % walk_lean)
	_check(fish_rod_dir.z < -0.5, "fishing: 낚싯대를 앞(-Z)으로 내밈 (방향 %s)" % str(fish_rod_dir))
	_check(absf(idle_lean) < 0.05, "idle: 기울기 없음 (%.2f)" % idle_lean)
	_check(half_lean < idle_lean - 0.03 and half_lean > walk_lean + 0.01, "walk 가중치 0.5에서 idle과 walk 사이로 블렌드 (%.3f)" % half_lean)
	# 낚시 가중치 0.5: 낚싯대 각도가 들고 다닐 때와 낚시 자세 사이
	await _settle(rig, 0.0, false)
	rig.fishing_blend_speed = 1.0
	rig.set_fishing(true)
	await get_tree().create_timer(0.35).timeout
	var mid_rod: float = rod.rotation.x
	_check(mid_rod < idle_rod - 0.1 and mid_rod > fish_rod + 0.1, "낚시 자세로 들어가는 중간 단계가 있다 (%.2f)" % mid_rod)
	# 도끼 들기 · 도끼질 원샷
	rig.set_held("axe")
	_check(rig.axe.visible and not rig.rod.visible, "도끼를 들면 도끼만 보임")
	await _settle(rig, 0.0, false)
	var arm: Node3D = rig.arm_right
	var axe: Node3D = rig.axe
	var rest_arm: float = arm.rotation.x
	var rest_axe: float = axe.rotation.x
	rig.play_chop()
	await get_tree().create_timer(0.17).timeout
	_check(rig.is_chopping() and arm.rotation.x > rest_arm + 1.5, "도끼질: 팔을 머리 위로 들어 올림 (%.2f → %.2f)" % [rest_arm, arm.rotation.x])
	var visual_scale: Vector3 = rig.get_node("Visual").scale
	_check(visual_scale.y > 0.9 and visual_scale.x > 0.9, "도끼질 중에도 몸 크기가 그대로 (%s)" % str(visual_scale))
	await get_tree().create_timer(0.6).timeout
	_check(not rig.is_chopping() and absf(axe.rotation.x - rest_axe) < 0.15 and absf(arm.rotation.x - rest_arm) < 0.15, "도끼질이 끝나면 원래 자세 (도끼 %.2f, 팔 %.2f)" % [axe.rotation.x, arm.rotation.x])
	# 걸을 때 팔다리가 앞뒤로 엇갈려 흔들린다.
	await _settle(rig, 1.0, false)
	var swing: float = 0.0
	for i: int in 12:
		await get_tree().create_timer(0.05).timeout
		swing = maxf(swing, absf(rig.leg_left.rotation.x - rig.leg_right.rotation.x))
	_check(swing > 0.6, "walk: 두 다리가 엇갈려 움직임 (%.2f)" % swing)
	# 브레이크: 몸을 뒤로 젖히고(+X) 앞발로 버틴다. 풀면 돌아온다.
	await _settle(rig, 0.0, false)
	rig.set_braking(true)
	await get_tree().create_timer(0.3).timeout
	_check(visual.rotation.x > 0.2 and rig.leg_left.rotation.x > 0.4, "brake: 몸을 젖히고 앞발로 버팀 (몸 %.2f, 다리 %.2f)" % [visual.rotation.x, rig.leg_left.rotation.x])
	rig.set_braking(false)
	await get_tree().create_timer(0.5).timeout
	_check(absf(visual.rotation.x) < 0.06, "brake 해제 (%.2f)" % visual.rotation.x)
	# 감정표현: 원샷. 안녕은 오른손을 번쩍 들어 흔든다, 시무룩은 고개를 숙인다.
	rig.set_held("")
	rig.play_emote("hello")
	await get_tree().create_timer(0.2).timeout
	_check(rig.is_emoting() and rig.arm_right.rotation.z > 1.8, "안녕: 오른손을 들어 흔듦 (%.2f)" % rig.arm_right.rotation.z)
	await get_tree().create_timer(1.4).timeout
	_check(not rig.is_emoting(), "감정표현이 끝나면 원래대로")
	rig.play_emote("sad")
	await get_tree().create_timer(0.45).timeout
	_check(visual.rotation.x < -0.15, "시무룩: 고개를 푹 (%.2f)" % visual.rotation.x)
	await get_tree().create_timer(1.6).timeout
	# 자랑: 물고기를 머리 위로, 도구는 숨김.
	rig.set_held("rod")
	var fish: FishInfo = GameData.fish.values()[0]
	rig.show_off(FishModel.mesh(fish))
	await get_tree().create_timer(0.6).timeout
	_check(rig.is_showing_off() and not rig.rod.visible and rig.arm_left.rotation.x > 1.5 and rig.arm_right.rotation.x > 1.5, "자랑: 두 손을 앞으로 쭉 (%.2f)" % rig.arm_left.rotation.x)
	rig.show_off(null)
	_check(rig.rod.visible, "자랑이 끝나면 낚싯대를 다시 듦")
	rig.set_eye_offset(Vector2(1.0, 0.0))
	_check(rig.get_eye_offset().is_equal_approx(Vector2(1.0, 0.0)), "눈동자 위치를 옮길 수 있음")
	print("ANIM %s (fishing lean %.2f)" % ["PASS" if _failures == 0 else "FAIL", fish_lean])
	get_tree().quit(_failures)


func _settle(rig: CharacterRig, speed: float, fishing: bool) -> void:
	rig.set_move_speed(speed)
	rig.set_fishing(fishing)
	await get_tree().create_timer(1.2).timeout


func _check(ok: bool, what: String) -> void:
	print("[anim] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
