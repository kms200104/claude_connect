extends Node
## AnimationTree 블렌딩 검증: idle / walk / fishing 자세가 서로 다르고, 중간 가중치에서 섞이는지 본다.

var _failures: int = 0


func _ready() -> void:
	var rig: CharacterRig = load("res://game/player/character_rig.tscn").instantiate()
	add_child(rig)
	var visual: Node3D = rig.get_node("Visual")
	var rod: Node3D = rig.get_node("Visual/Rod")
	await _settle(rig, 0.0, false)
	var idle_lean: float = visual.rotation.x
	var idle_rod: float = rod.rotation.x
	await _settle(rig, 1.0, false)
	var walk_lean: float = visual.rotation.x
	await _settle(rig, 0.0, true)
	var fish_rod: float = rod.rotation.x
	var fish_lean: float = visual.rotation.x
	await _settle(rig, 0.5, false)
	var half_lean: float = visual.rotation.x
	_check(is_equal_approx(idle_rod, 0.3) or absf(idle_rod - 0.32) < 0.06, "idle: 낚싯대를 세워 둠 (rod.x=%.2f)" % idle_rod)
	_check(walk_lean < -0.1, "walk: 앞으로 기울어짐 (lean=%.2f)" % walk_lean)
	_check(fish_rod < -0.9, "fishing: 낚싯대를 앞으로 내밈 (rod.x=%.2f)" % fish_rod)
	_check(absf(idle_lean) < 0.05, "idle: 기울기 없음 (%.2f)" % idle_lean)
	_check(half_lean < idle_lean - 0.03 and half_lean > walk_lean + 0.01, "walk 가중치 0.5에서 idle과 walk 사이로 블렌드 (%.3f)" % half_lean)
	# 낚시 가중치 0.5: 낚싯대 각도가 stowed(0.3)와 fishing(-1.1) 사이
	await _settle(rig, 0.0, false)
	rig.fishing_blend_speed = 1.0
	rig.set_fishing(true)
	await get_tree().create_timer(0.35).timeout
	var mid_rod: float = rod.rotation.x
	_check(mid_rod < idle_rod - 0.1 and mid_rod > fish_rod + 0.1, "낚시 자세로 들어가는 중간 단계가 있다 (%.2f)" % mid_rod)
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
