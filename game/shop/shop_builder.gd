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
## Tripo 계산대 모형 (tools/blender/import_tripo.py). 있으면 절차 계산대 대신 모든 단계가 이것을 쓴다.
const COUNTER_MODEL: String = "shop_counter"


## 계산대 모형 (없으면 null — 절차 계산대를 실내 메시에 넣는다).
static func counter_model() -> ArrayMesh:
	return PartMesh.load_model(COUNTER_MODEL)


## 계산대 모형을 놓는 자리 (방 원점 기준, 바닥 가운데). 주인 자리(keeper_offset)보다 조금 앞.
static func counter_position(level: int) -> Vector3:
	return Vector3(0.0, 0.1, -INTERIOR_SIZE[level].y + 2.2)


static func _p(shape: String, size: Array, at: Vector3, color: Variant) -> Dictionary:
	return {"s": shape, "size": size, "at": [at.x, at.y, at.z], "c": color}


static func _r(shape: String, size: Array, at: Vector3, color: Variant, roundness: float = 0.3, rot: Vector3 = Vector3.ZERO) -> Dictionary:
	var part: Dictionary = {"s": shape, "size": size, "at": [at.x, at.y, at.z], "c": color, "r": roundness}
	if rot != Vector3.ZERO:
		part["rot"] = [rot.x, rot.y, rot.z]
	return part


## 줄무늬 차양: 앞으로 기울어진 판 + 끝에 동글동글한 물결 장식.
static func _awning(parts: Array, width: float, y: float, depth: float, stripes: int, a: String, b: String) -> void:
	for i: int in stripes:
		var x: float = -width * 0.5 + width / stripes * (i + 0.5)
		var color: String = a if i % 2 == 0 else b
		parts.append(_r("rbox", [width / stripes + 0.01, 0.1, depth], Vector3(x, y, depth * 0.45), color, 0.2, Vector3(22.0, 0.0, 0.0)))
		parts.append(_r("sphere", [width / stripes * 0.5, 0.16, 0.08], Vector3(x, y - depth * 0.42 - 0.06, depth * 0.9), color, 0.0))


## 바깥 건물 (원점 = 앞면 가운데 바닥, 앞면이 +Z).
static func exterior_parts(level: int) -> Array:
	var size: Vector3 = EXTERIOR_SIZE[level]
	var c: Vector3 = Vector3(0.0, size.y * 0.5, -size.z * 0.5)
	var parts: Array = []
	match level:
		1:
			# 나무 노점: 판자 벽 · 폭신한 지붕 · 빨강/흰 줄무늬 차양 · 과일 상자 · 종.
			parts.append(_r("rbox", [size.x, size.y, size.z], c, ["#A8703F", "#D9A673"], 0.12))
			for y: float in [0.7, 1.4, 2.1]:
				parts.append(_p("box", [size.x + 0.02, 0.04, size.z + 0.02], Vector3(0.0, y, c.z), "#9A6236"))
			parts.append(_r("rbox", [size.x + 0.6, 0.5, size.z + 0.6], Vector3(0.0, size.y + 0.2, c.z), ["#B8503E", "#D96A52"], 0.5))
			parts.append(_r("rbox", [size.x * 0.55, 0.5, size.z * 0.6], Vector3(0.0, size.y + 0.6, c.z), ["#B8503E", "#E07A60"], 0.6))
			_awning(parts, size.x + 0.2, size.y - 0.45, 1.3, 7, "#E05A4A", "#FFF4E8")
			parts.append(_r("rbox", [1.5, 0.85, 0.6], Vector3(-1.35, 0.43, 0.42), ["#9A6236", "#C98A55"], 0.25))
			for i: int in 5:
				var fruit: String = ["#E0453A", "#F29A2E", "#E0453A", "#9CC44A", "#F29A2E"][i]
				parts.append(_p("sphere", [0.13], Vector3(-1.85 + 0.25 * i, 0.95, 0.42 + (0.08 if i % 2 == 0 else -0.08)), fruit))
			parts.append(_r("rbox", [0.75, 0.55, 0.5], Vector3(1.6, 0.28, 0.45), ["#9A6236", "#C98A55"], 0.25))
			for i: int in 3:
				parts.append(_p("sphere", [0.12], Vector3(1.42 + 0.18 * i, 0.62, 0.45), "#F2C14E"))
			parts.append(_p("cone", [0.14, 0.2], Vector3(0.75, size.y - 0.75, 0.25), "#E8B84A"))
			parts.append(_p("sphere", [0.04], Vector3(0.75, size.y - 0.87, 0.25), "#B8862E"))
			parts.append(_r("rbox", [0.5, 0.22, 0.04], Vector3(0.0, 1.55, 0.09), "#7FB86A", 0.3))
		2:
			# 잡화점: 크림색 벽 · 청록 지붕 두 단 · 산호색 차양 · 꽃 상자 · 둥근 덤불.
			parts.append(_r("rbox", [size.x, size.y, size.z], c, ["#E6D2AE", "#F6EBD5"], 0.1))
			parts.append(_r("rbox", [size.x + 0.5, 0.4, size.z + 0.5], Vector3(0.0, size.y + 0.15, c.z), ["#3F857A", "#5AA898"], 0.4))
			parts.append(_r("rbox", [size.x * 0.75, 0.9, size.z * 0.75], Vector3(0.0, size.y + 0.75, c.z), ["#3F857A", "#64B4A2"], 0.45))
			_awning(parts, size.x, size.y - 0.55, 1.2, 9, "#E87A5D", "#FFF4E0")
			parts.append(_r("rbox", [size.x + 0.1, 0.35, 0.12], Vector3(0.0, 0.18, 0.02), "#B07A45", 0.3))
			for side: float in [-1.0, 1.0]:
				parts.append(_p("blob", [0.45, 0.38, 0.4], Vector3(side * (size.x * 0.5 - 0.4), 0.35, 0.6), ["#4E8A3E", "#7FB86A"]))
				parts.append(_r("rbox", [1.1, 0.22, 0.3], Vector3(side * 1.9, size.y * 0.55 - 0.65, 0.16), "#B07A45", 0.3))
				for k: int in 4:
					parts.append(_p("sphere", [0.07], Vector3(side * 1.9 - 0.36 + 0.24 * k, size.y * 0.55 - 0.48, 0.2), ["#F6A6B8", "#FFD866", "#F4F1EA", "#E87A90"][k]))
		_:
			# 백화점: 대리석 · 금빛 띠 · 둥근 기둥 · 계단 · 붉은 카펫 · 작은 금 첨탑.
			parts.append(_r("rbox", [size.x, size.y, size.z], c, ["#E2DCD0", "#FBF8F2"], 0.06))
			parts.append(_r("rbox", [size.x + 0.6, 0.45, size.z + 0.6], Vector3(0.0, size.y + 0.22, c.z), ["#DCD5C6", "#F2EDE3"], 0.3))
			parts.append(_r("rbox", [size.x + 0.65, 0.12, size.z + 0.65], Vector3(0.0, size.y + 0.02, c.z), "#D9B44A", 0.4))
			parts.append(_r("rbox", [size.x * 0.6, 1.0, size.z * 0.6], Vector3(0.0, size.y + 0.95, c.z), ["#E2DCD0", "#FBF8F2"], 0.25))
			parts.append(_p("sphere", [1.0, 0.7, 1.0], Vector3(0.0, size.y + 1.45, c.z), ["#C9A23A", "#F0D27A"]))
			parts.append(_p("cone", [0.2, 0.7], Vector3(0.0, size.y + 2.45, c.z), "#D9B44A"))
			for x: float in [-3.4, -1.6, 1.6, 3.4]:
				parts.append(_r("cyl", [0.28, size.y], Vector3(x, size.y * 0.5, 0.75), ["#E8E2D6", "#FFFFFF"], 0.05))
				parts.append(_r("rbox", [0.75, 0.2, 0.75], Vector3(x, size.y - 0.1, 0.75), "#D9B44A", 0.3))
				parts.append(_r("rbox", [0.7, 0.18, 0.7], Vector3(x, 0.09, 0.75), "#D9D2C4", 0.3))
			parts.append(_r("rbox", [size.x + 0.6, 0.25, 2.2], Vector3(0.0, 0.12, 0.6), "#E0D8C8", 0.15))
			parts.append(_r("rbox", [2.6, 0.04, 2.0], Vector3(0.0, 0.26, 0.7), "#A3263A", 0.2))
	# 문 (앞면에 붙인다): 문틀 + 문 + 손잡이.
	var door_w: float = 1.0 if level < 3 else 1.8
	var lift: float = 0.25 if level == 3 else 0.0
	parts.append(_r("rbox", [door_w + 0.2, 2.05, 0.1], Vector3(0.0, 1.0 + lift, 0.02), "#FFF6E6" if level < 3 else "#D9B44A", 0.25))
	parts.append(_r("rbox", [door_w, 1.9, 0.1], Vector3(0.0, 0.95 + lift, 0.06), ["#5E3E26", "#8A5A36"] if level < 3 else ["#253049", "#3A4A70"], 0.2))
	parts.append(_p("sphere", [0.06], Vector3(door_w * 0.35, 1.0 + lift, 0.13), "#D9B44A"))
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
	# 출구: 낮은 문(벽과 같은 높이) + 문기둥 + 매트. 문 쪽으로 걸어가면 밖으로 나간다 (ShopController).
	parts.append(_p("box", [1.4, 0.03, 0.9], Vector3(0.0, 0.11, -0.6), "#8A5A36" if level < 3 else "#A3263A"))
	parts.append(_r("rbox", [1.56, 0.5, 0.1], Vector3(0.0, 0.3, 0.06), ["#7A4E30", "#A87244"] if level < 3 else ["#253049", "#3A4A70"], 0.25))
	parts.append(_p("sphere", [0.05], Vector3(0.45, 0.42, 0.0), "#D9B44A"))
	for x: float in [-0.85, 0.85]:
		parts.append(_r("rbox", [0.16, 0.9, 0.24], Vector3(x, 0.45, 0.0), "#6E4A2E" if level < 3 else "#D9B44A", 0.3))
	# 계산대 (모형이 있으면 ShopController 가 따로 놓는다)
	if counter_model() == null:
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
		# 출구 자리도 막는다 (문 밖 허공으로 걸어 나가지 않게). 나가는 건 서버가 옮겨 준다.
		AABB(Vector3(-0.8, 0.0, 0.0), Vector3(1.6, WALL_HEIGHT, 0.3)),
	]
	var counter: ArrayMesh = counter_model()
	if counter != null:
		var aabb: AABB = counter.get_aabb()
		boxes.append(AABB(aabb.position + counter_position(level), aabb.size))
	else:
		boxes.append(AABB(Vector3(-w * 0.225, 0.0, -d + 1.65), Vector3(w * 0.45, 1.1, 0.7)))
	for side_sign: float in [-1.0, 1.0]:
		boxes.append(AABB(Vector3(side_sign * (w * 0.5 - 0.45) - 0.3, 0.0, -d + 0.8), Vector3(0.6, 1.8, d - 2.4)))
	return boxes


## 실내에서 상점 주인이 서는 곳 (방 원점 기준).
static func keeper_offset(level: int) -> Vector3:
	return Vector3(0.0, 0.0, -INTERIOR_SIZE[level].y + 1.1)
