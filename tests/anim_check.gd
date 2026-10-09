extends Node
## AnimationTree 블렌딩 검증: idle / walk / fishing 자세가 서로 다르고, 중간 가중치에서 섞이는지 본다.

var _failures: int = 0


## 몸 전체가 기운 정도 (v0.13: 골반 + 허리 + 목).
func _lean(rig: CharacterRig) -> float:
	return rig.visual.rotation.x + rig.waist.rotation.x + rig.neck.rotation.x


func _ready() -> void:
	var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
	add_child(rig)
	var visual: Node3D = rig.get_node("Visual")
	var rod: Node3D = rig.rod
	await _settle(rig, 0.0, false)
	var idle_lean: float = _lean(rig)
	var idle_rod: float = rod.rotation.x
	var idle_rod_dir: Vector3 = rod.global_basis.y.normalized()
	var idle_hand: Vector3 = rig.upper.global_transform.affine_inverse() * (rig.elbow_right.global_transform * Vector3(0.0, -0.19, 0.0))
	await _settle(rig, 1.0, false)
	var walk_lean: float = _lean(rig)
	await _settle(rig, 0.0, true)
	var fish_rod: float = rod.rotation.x
	var fish_rod_dir: Vector3 = rod.global_basis.y.normalized()
	var fish_lean: float = _lean(rig)
	await _settle(rig, 0.5, false)
	var half_lean: float = _lean(rig)
	# v0.16.1 들고 다니기: 낚싯대는 오른 어깨에 메고 뒤 · 위로 (캐릭터 정면은 -Z).
	_check(idle_rod_dir.z > 0.5 and idle_rod_dir.y > 0.2 and idle_rod_dir.x > 0.15, "idle: 낚싯대를 어깨에 메고 뒤 · 위 · 바깥으로 (방향 %s)" % str(idle_rod_dir))
	_check(idle_hand.distance_to(CharacterModel.SHOULDER) < 0.2 and idle_hand.z < -0.05, "idle: 오른손은 어깨 앞 (%s)" % str(idle_hand))
	_check(rig.carry_kind() == "rod", "낚싯대를 들면 메는 자세 (%s)" % rig.carry_kind())
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
	# 도끼는 두 손으로 배 앞에 옆으로 (오른손 자루 끝, 왼손이 그 위, 도끼 머리는 왼쪽). 걸어도 그대로.
	await _settle(rig, 1.0, false)
	var to_upper: Transform3D = rig.upper.global_transform.affine_inverse()
	var hand_r: Vector3 = to_upper * (rig.elbow_right.global_transform * Vector3(0.0, -0.19, 0.0))
	var hand_l: Vector3 = to_upper * (rig.elbow_left.global_transform * Vector3(0.0, -0.19, 0.0))
	var axe_dir: Vector3 = (to_upper.basis * axe.global_basis.y).normalized()
	_check(rig.carry_kind() == "axe" and hand_r.distance_to(hand_l) < 0.18 and hand_r.z < -0.08 and hand_l.z < -0.08, "걸을 때 도끼를 두 손으로 앞에 쥠 (오른손 %s, 왼손 %s)" % [str(hand_r), str(hand_l)])
	_check(axe_dir.x < -0.6 and axe_dir.y > 0.1, "도끼는 옆(왼쪽)으로 비스듬히 (%s)" % str(axe_dir))
	await _settle(rig, 0.0, false)
	var rest_arm: float = arm.rotation.x
	var rest_axe: float = axe.rotation.x
	rig.play_chop()
	await get_tree().create_timer(0.17).timeout
	_check(rig.is_chopping() and arm.rotation.x > 1.5, "도끼질: 팔을 머리 위로 들어 올림 (%.2f → %.2f)" % [rest_arm, arm.rotation.x])
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
	_check(_lean(rig) > 0.2 and rig.leg_left.rotation.x > 0.4, "brake: 몸을 젖히고 앞발로 버팀 (몸 %.2f, 다리 %.2f)" % [_lean(rig), rig.leg_left.rotation.x])
	rig.set_braking(false)
	await get_tree().create_timer(0.5).timeout
	_check(absf(_lean(rig)) < 0.06, "brake 해제 (%.2f)" % _lean(rig))
	# 감정표현: 원샷. 안녕은 오른손을 번쩍 들어 흔든다, 시무룩은 고개를 숙인다.
	rig.set_held("")
	rig.play_emote("hello")
	# 손이 올라가는 도중 한 순간이 아니라 구간에서 가장 높이 든 값을 본다 (프레임 타이밍에 흔들리지 않게).
	var wave: float = -INF
	var emoting: bool = false
	for i: int in 8:
		await get_tree().create_timer(0.05).timeout
		wave = maxf(wave, rig.arm_right.rotation.z)
		emoting = emoting or rig.is_emoting()
	_check(emoting and wave > 1.8, "안녕: 오른손을 들어 흔듦 (%.2f)" % wave)
	await get_tree().create_timer(1.2).timeout
	_check(not rig.is_emoting(), "감정표현이 끝나면 원래대로")
	rig.play_emote("sad")
	var droop: float = INF
	for i: int in 14:
		await get_tree().create_timer(0.05).timeout
		droop = minf(droop, _lean(rig))
	_check(droop < -0.15, "시무룩: 고개를 푹 (%.2f)" % droop)
	await get_tree().create_timer(1.35).timeout
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
	# 허리 · 목 관절 (v0.13): 인사(꾸벅)는 골반보다 허리·목이 더 숙고, 목은 허리보다 늦게 따라온다.
	rig.play_emote("bow")
	var waist_first: float = 0.0
	var neck_first: float = 0.0
	for i: int in 10:
		await get_tree().create_timer(0.05).timeout
		if waist_first == 0.0 and rig.waist.rotation.x < -0.05:
			waist_first = i * 0.05
		if neck_first == 0.0 and rig.neck.rotation.x < -0.03:
			neck_first = i * 0.05
	_check(rig.waist.rotation.x < -0.1 and rig.neck.rotation.x < -0.05, "꾸벅: 허리와 목이 따로 숙인다 (허리 %.2f, 목 %.2f)" % [rig.waist.rotation.x, rig.neck.rotation.x])
	_check(neck_first >= waist_first, "목은 허리보다 조금 늦게 (허리 %.2fs, 목 %.2fs)" % [waist_first, neck_first])
	await get_tree().create_timer(1.6).timeout
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
