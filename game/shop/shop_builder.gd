class_name ShopBuilder
extends RefCounted
## 상점 단계별 겉모습(마을 광장)과 실내(마을에서 멀리 떨어진 방)의 모양 데이터.
## 도형 목록은 PartMesh 형식({s, size, at, c})이라 건물 한 채·실내 한 벌이 각각 메시 1개로 그려진다.
## 단계가 오를수록 크고 화려해진다: 1 구멍가게(나무 노점) → 2 잡화점(창문·차양) → 3 백화점(대리석·기둥·금장식·샹들리에).

## 단계별 바깥 건물 크기 (가로, 높이, 깊이). 문이 있는 앞면은 항상 문 위치(z)에 맞춘다.
const EXTERIOR_SIZE: Dictionary = {1: Vector3(4.5, 2.8, 3.5), 2: Vector3(6.5, 3.4, 5.0), 3: Vector3(9.0, 4.6, 6.5)}
## 단계별 실내 방 크기 (가로, 깊이). 남쪽 벽(출구)은 항상 같은 자리.
const INTERIOR_SIZE: Dictionary = {1: Vector2(8.0, 7.0), 2: Vector2(10.0, 8.0), 3: Vector2(12.5, 9.5)}
const WALL_HEIGHT: float = 3.0


static func _p(shape: String, size: Array, at: Vector3, color: String) -> Dictionary:
	return {"s": shape, "size": size, "at": [at.x, at.y, at.z], "c": color}


## 바깥 건물 (원점 = 앞면 가운데 바닥, 앞면이 +Z).
static func exterior_parts(level: int) -> Array:
	var size: Vector3 = EXTERIOR_SIZE[level]
	var c: Vector3 = Vector3(0.0, size.y * 0.5, -size.z * 0.5)
	var parts: Array = []
	match level:
		1:
			parts.append(_p("box", [size.x, size.y, size.z], c, "#C99A6B"))
			# 줄무늬 차양
			for i: int in 6:
				var x: float = -size.x * 0.5 + size.x / 6.0 * (i + 0.5)
				parts.append(_p("box", [size.x / 6.0, 0.12, 1.4], Vector3(x, size.y - 0.35, 0.55), "#4E9C6E" if i % 2 == 0 else "#F4F1EA"))
			parts.append(_p("box", [size.x + 0.3, 0.25, size.z + 0.3], Vector3(0.0, size.y + 0.12, c.z), "#8A5A36"))
			parts.append(_p("box", [1.6, 0.9, 0.5], Vector3(-1.2, 0.45, 0.35), "#B07A45"))
			parts.append(_p("box", [1.4, 0.12, 0.45], Vector3(-1.2, 0.95, 0.35), "#E8C872"))
		2:
			parts.append(_p("box", [size.x, size.y, size.z], c, "#F1E3C6"))
			parts.append(_p("box", [size.x + 0.4, 0.3, size.z + 0.4], Vector3(0.0, size.y + 0.15, c.z), "#4E9C8F"))
			parts.append(_p("box", [size.x * 0.75, 0.9, size.z * 0.75], Vector3(0.0, size.y + 0.75, c.z), "#3F857A"))
			for i: int in 5:
				var x: float = -size.x * 0.5 + size.x / 5.0 * (i + 0.5)
				parts.append(_p("box", [size.x / 5.0, 0.12, 1.2], Vector3(x, size.y - 0.5, 0.5), "#E87A5D" if i % 2 == 0 else "#FFF4E0"))
			parts.append(_p("box", [size.x + 0.1, 0.35, 0.1], Vector3(0.0, 0.18, 0.02), "#B07A45"))
			parts.append(_p("sphere", [0.35], Vector3(-size.x * 0.5 + 0.5, 0.35, 0.6), "#5FA052"))
			parts.append(_p("sphere", [0.35], Vector3(size.x * 0.5 - 0.5, 0.35, 0.6), "#5FA052"))
		_:
			parts.append(_p("box", [size.x, size.y, size.z], c, "#F4F1EA"))
			parts.append(_p("box", [size.x + 0.6, 0.45, size.z + 0.6], Vector3(0.0, size.y + 0.22, c.z), "#E9E3D6"))
			parts.append(_p("box", [size.x + 0.65, 0.12, size.z + 0.65], Vector3(0.0, size.y + 0.02, c.z), "#D9B44A"))
			parts.append(_p("box", [size.x * 0.6, 1.0, size.z * 0.6], Vector3(0.0, size.y + 0.95, c.z), "#F4F1EA"))
			parts.append(_p("cone", [0.5, 0.8], Vector3(0.0, size.y + 1.85, c.z), "#D9B44A"))
			for x: float in [-3.4, -1.6, 1.6, 3.4]:
				parts.append(_p("cyl", [0.28, size.y], Vector3(x, size.y * 0.5, 0.75), "#FFFFFF"))
				parts.append(_p("box", [0.7, 0.18, 0.7], Vector3(x, size.y - 0.09, 0.75), "#D9B44A"))
			parts.append(_p("box", [size.x + 0.6, 0.25, 2.2], Vector3(0.0, 0.12, 0.6), "#E0D8C8"))
			parts.append(_p("box", [2.6, 0.04, 2.0], Vector3(0.0, 0.26, 0.7), "#A3263A"))
	# 문 (앞면에 붙인다)
	var door_w: float = 1.0 if level < 3 else 1.8
	parts.append(_p("box", [door_w, 1.9, 0.08], Vector3(0.0, 0.95 + (0.25 if level == 3 else 0.0), 0.03), "#6E4A2E" if level < 3 else "#2E3A59"))
	parts.append(_p("sphere", [0.06], Vector3(door_w * 0.35, 1.0 + (0.25 if level == 3 else 0.0), 0.09), "#D9B44A"))
	return parts


## 바깥 창문 (밤에 빛나는 머티리얼로 따로 그린다).
static func exterior_windows(level: int) -> Array:
	var size: Vector3 = EXTERIOR_SIZE[level]
	var parts: Array = []
	var count: int = [0, 1, 2, 4][level]
	for i: int in count:
		var x: float = -size.x * 0.5 + size.x / (count + 1) * (i + 1)
		if absf(x) < 1.2:
			x += 1.4 * signf(x if x != 0.0 else 1.0)
		parts.append(_p("box", [0.9 if level < 3 else 1.2, 1.0 if level < 3 else 1.6, 0.06], Vector3(x, size.y * 0.55, 0.04), "#FFFFFF"))
	return parts


## 실내 (원점 = 방 남쪽 벽 가운데 바닥, 방은 -Z 쪽으로 펼쳐진다).
static func interior_parts(level: int) -> Array:
	var room: Vector2 = INTERIOR_SIZE[level]
	var w: float = room.x
	var d: float = room.y
	var mid: float = -d * 0.5
	var floor_color: String = ["", "#B98B5E", "#D8B88A", "#EDE8E0"][level]
	var wall_color: String = ["", "#E2C9A0", "#F3E6CF", "#F7F2EA"][level]
	var parts: Array = [_p("box", [w, 0.1, d], Vector3(0.0, 0.05, mid), floor_color)]
	# 벽: 북·동·서 + 남쪽은 출구 자리를 비운다
	parts.append(_p("box", [w, WALL_HEIGHT, 0.2], Vector3(0.0, WALL_HEIGHT * 0.5, -d), wall_color))
	parts.append(_p("box", [0.2, WALL_HEIGHT, d], Vector3(-w * 0.5, WALL_HEIGHT * 0.5, mid), wall_color))
	parts.append(_p("box", [0.2, WALL_HEIGHT, d], Vector3(w * 0.5, WALL_HEIGHT * 0.5, mid), wall_color))
	var side: float = (w - 1.6) * 0.5
	parts.append(_p("box", [side, 0.6, 0.2], Vector3(-(0.8 + side * 0.5), 0.3, 0.0), wall_color))
	parts.append(_p("box", [side, 0.6, 0.2], Vector3(0.8 + side * 0.5, 0.3, 0.0), wall_color))
	# 출구 매트
	parts.append(_p("box", [1.4, 0.03, 0.9], Vector3(0.0, 0.11, -0.6), "#8A5A36" if level < 3 else "#A3263A"))
	# 계산대
	var counter_z: float = -d + 2.0
	var counter_color: String = ["", "#A0714A", "#8C5A3A", "#3A2A24"][level]
	parts.append(_p("box", [w * 0.45, 1.0, 0.7], Vector3(0.0, 0.5, counter_z), counter_color))
	parts.append(_p("box", [w * 0.45 + 0.1, 0.08, 0.8], Vector3(0.0, 1.04, counter_z), "#D9B44A" if level == 3 else "#C89A63"))
	parts.append(_p("box", [0.35, 0.25, 0.25], Vector3(w * 0.15, 1.2, counter_z), "#5A5A5A"))
	# 진열 선반 (단계가 오를수록 많아진다)
	var shelf_rows: int = level + 1
	var goods_colors: PackedStringArray = ["#C0504D", "#4F81BD", "#9BBB59", "#F2C14E", "#E87A90", "#7EC8A8"]
	for side_sign: float in [-1.0, 1.0]:
		for r: int in shelf_rows:
			var z: float = -1.6 - r * (d - 3.2) / maxf(shelf_rows, 1)
			var x: float = side_sign * (w * 0.5 - 0.45)
			parts.append(_p("box", [0.6, 1.8, 1.4], Vector3(x, 0.9, z), "#8A5A36" if level < 3 else "#E9E3D6"))
			for k: int in 3:
				parts.append(_p("box", [0.5, 0.28, 0.35], Vector3(x, 0.45 + k * 0.55, z - 0.4 + (k % 2) * 0.5), goods_colors[(r * 3 + k + (1 if side_sign > 0 else 0)) % goods_colors.size()]))
	match level:
		2:
			parts.append(_p("box", [3.2, 0.03, 2.2], Vector3(0.0, 0.11, mid + 0.6), "#E87A5D"))
			for x: float in [-w * 0.5 + 0.6, w * 0.5 - 0.6]:
				parts.append(_p("cyl", [0.25, 0.4], Vector3(x, 0.3, -d + 0.6), "#C8643C"))
				parts.append(_p("sphere", [0.4], Vector3(x, 0.8, -d + 0.6), "#5FA052"))
		3:
			parts.append(_p("box", [1.6, 0.03, d - 2.8], Vector3(0.0, 0.11, mid + 0.9), "#A3263A"))
			parts.append(_p("box", [w, 0.15, 0.22], Vector3(0.0, WALL_HEIGHT - 0.1, -d + 0.02), "#D9B44A"))
			parts.append(_p("box", [0.22, 0.15, d], Vector3(-w * 0.5 + 0.02, WALL_HEIGHT - 0.1, mid), "#D9B44A"))
			parts.append(_p("box", [0.22, 0.15, d], Vector3(w * 0.5 - 0.02, WALL_HEIGHT - 0.1, mid), "#D9B44A"))
			for x: float in [-2.2, 2.2]:
				parts.append(_p("cyl", [0.25, WALL_HEIGHT], Vector3(x, WALL_HEIGHT * 0.5, mid - 0.6), "#FFFFFF"))
				parts.append(_p("box", [0.6, 0.15, 0.6], Vector3(x, WALL_HEIGHT - 0.08, mid - 0.6), "#D9B44A"))
	return parts


## 백화점 샹들리에. 위에서 내려다보는 카메라를 가리지 않게 계산대 위 벽 쪽에 낮고 작게 단다. 다른 단계는 빈 목록.
static func chandelier_parts(level: int) -> Array:
	if level < 3:
		return []
	var d: float = INTERIOR_SIZE[3].y
	var at: Vector3 = Vector3(0.0, WALL_HEIGHT - 0.2, -d + 0.6)
	return [
		_p("cyl", [0.45, 0.06], at, "#D9B44A"),
		_p("sphere", [0.11], at + Vector3(0.36, -0.08, 0.0), "#FFF4D0"),
		_p("sphere", [0.11], at + Vector3(-0.36, -0.08, 0.0), "#FFF4D0"),
		_p("sphere", [0.11], at + Vector3(0.0, -0.08, 0.36), "#FFF4D0"),
		_p("sphere", [0.15], at + Vector3(0.0, -0.16, 0.0), "#FFF4D0"),
	]


## 실내 충돌 상자: (크기, 가운데) 목록. 벽 4면 + 계산대.
static func interior_colliders(level: int) -> Array[AABB]:
	var room: Vector2 = INTERIOR_SIZE[level]
	var w: float = room.x
	var d: float = room.y
	var side: float = (w - 1.6) * 0.5
	var boxes: Array[AABB] = [
		AABB(Vector3(-w * 0.5, 0.0, -d - 0.1), Vector3(w, WALL_HEIGHT, 0.2)),
		AABB(Vector3(-w * 0.5 - 0.1, 0.0, -d), Vector3(0.2, WALL_HEIGHT, d)),
		AABB(Vector3(w * 0.5 - 0.1, 0.0, -d), Vector3(0.2, WALL_HEIGHT, d)),
		AABB(Vector3(-w * 0.5, 0.0, -0.1), Vector3(side, WALL_HEIGHT, 0.2)),
		AABB(Vector3(0.8, 0.0, -0.1), Vector3(side, WALL_HEIGHT, 0.2)),
		AABB(Vector3(-w * 0.225, 0.0, -d + 1.65), Vector3(w * 0.45, 1.1, 0.7)),
	]
	for side_sign: float in [-1.0, 1.0]:
		boxes.append(AABB(Vector3(side_sign * (w * 0.5 - 0.45) - 0.3, 0.0, -d + 0.8), Vector3(0.6, 1.8, d - 2.4)))
	return boxes


## 실내에서 상점 주인이 서는 곳 (방 원점 기준).
static func keeper_offset(level: int) -> Vector3:
	return Vector3(0.0, 0.0, -INTERIOR_SIZE[level].y + 1.1)
