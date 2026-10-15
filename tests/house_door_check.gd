extends Node
## 빈집(판잣집) 안쪽 문 통과 점검: 플레이어와 같은 캡슐(반지름 0.4)이 앞방에서 침실 · 욕실 문틈을 지나 안쪽 방까지 걸어 들어가는지.
## (v0.28.1 — 문틈이 벽 끝 여유(0.1m)에 먹혀 침실 0.9m · 욕실 0.7m 라 들어가지 못하던 버그.)

var _failures: Array[String] = []


func _ready() -> void:
	var houses: HouseField = HouseField.new()
	houses.clay_material = load("res://assets/materials/building_clay.tres")
	houses.window_material = load("res://assets/materials/building_window.tres")
	add_child(houses)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var h: SurvivalRules.House = GameData.survival.houses[0]
	var turn: Basis = Basis(Vector3.UP, h.yaw)
	# 문 가운데 · 조금 비켜서 (조이스틱으로 대충 걸어 들어가는 것처럼).
	for room: Array in [["침실", -0.65], ["침실(왼쪽으로 비켜)", -1.0], ["침실(오른쪽으로 비켜)", -0.3], ["욕실", 3.05], ["욕실(비켜)", 3.35]]:
		var body: CharacterBody3D = CharacterBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.6
		shape.shape = capsule
		shape.position = Vector3(0.0, 0.8, 0.0)
		body.add_child(shape)
		add_child(body)
		var x: float = float(room[1])
		# 옆에서 비스듬히 다가오면 예전에는 벽 모서리에 걸렸다.
		body.global_position = h.position + turn * Vector3(x * 1.8 if x < 2.0 else x, 0.25, 1.6)
		var door_x: float = -0.65 if x < 2.0 else 3.05
		var goal: Vector3 = h.position + turn * Vector3(door_x, 0.25, -1.6)
		for i: int in 120:
			var to: Vector3 = goal - body.global_position
			to.y = 0.0
			if to.length() < 0.1:
				break
			body.velocity = to.normalized() * 4.5
			body.move_and_slide()
			await get_tree().physics_frame
		var local: Vector3 = turn.inverse() * (body.global_position - h.position)
		var ok: bool = local.z < -1.0
		print("[door] %s: %s 문을 지나 들어감 (z %.2f)" % ["ok  " if ok else "FAIL", room[0], local.z])
		if not ok:
			_failures.append(str(room[0]))
		body.queue_free()
	print("DOOR %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(1 if not _failures.is_empty() else 0)
