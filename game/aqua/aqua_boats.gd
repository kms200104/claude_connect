class_name AquaBoats
extends RefCounted
## 물놀이 체험 (v21) 모형: 바나나 튜브 · 유람선 · 잔교 · 매표소. 모두 점토 정점 색 (ClayMesh, 공용 머티리얼 하나).
## 배 좌표는 VehicleModel 과 같다: 수면 y = 0, 앞 = -z. 손님 자리(seats)는 같은 좌표의 { at: 엉덩이 자리, yaw: 바라보는 쪽 }.

const BANANA: Color = Color("#F6D33C")
const BANANA_DARK: Color = Color("#D9A522")
const BANANA_TIP: Color = Color("#6E4A24")
const ROPE_BLUE: Color = Color("#2F5FA8")
const HULL_WHITE: Color = Color("#F4F1EA")
const HULL_BLUE: Color = Color("#2E6FB5")
const HULL_RED: Color = Color("#D24B3C")
const DECK: Color = Color("#B98A57")
const GLASS: Color = Color("#3D5B78")
const CANOPY: Color = Color("#F2F0E6")
const CANOPY_STRIPE: Color = Color("#3C8FD0")
const RAIL: Color = Color("#E9E6DF")
const WOOD: Color = Color("#A9784A")
const WOOD_LIGHT: Color = Color("#C9A06C")
const RING: Color = Color("#F07A2E")

## 바나나 튜브 위 손님 자리 높이 (수면 위).
const BANANA_SEAT_Y: float = 0.5
## 유람선 갑판 높이 · 의자 높이.
const DECK_Y: float = 0.62
const BENCH_Y: float = 0.45


## 바나나 튜브 자리 4개 (앞에서부터, 모두 앞을 본다).
static func banana_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 4:
		out.append({"at": Vector3(0.0, BANANA_SEAT_Y, -0.95 + float(i) * 0.72), "yaw": 0.0})
	return out


## 유람선 자리 8개: 양쪽 뱃전 긴 의자에 넷씩, 바깥(호수)을 보고 앉는다.
static func cruise_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for side: float in [-1.0, 1.0]:
		for i: int in 4:
			out.append({"at": Vector3(side * 0.62, DECK_Y, -0.9 + float(i) * 0.95), "yaw": -side * PI * 0.5})
	return out


## 끄는 줄을 매는 바나나 코 (배 좌표).
static func banana_nose() -> Vector3:
	return Vector3(0.0, 0.55, -2.05)


static func banana_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	# 몸통: 앞이 들린 굽은 튜브 (마디마다 타원체를 겹쳐 매끈하게).
	var n: int = 9
	for i: int in n:
		var t: float = float(i) / float(n - 1)
		var z: float = lerpf(1.75, -1.75, t)
		var lift: float = 0.18 + pow(maxf(0.0, t - 0.55) / 0.45, 2.0) * 0.32
		var r: float = 0.34 * (1.0 - pow(absf(t - 0.45) / 0.55, 3.0) * 0.45)
		var c: Color = BANANA.lerp(BANANA_DARK, 0.25 * absf(t - 0.5))
		ClayMesh.add_ellipsoid(st, Vector3(0.0, lift, z), Vector3(r, r * 0.95, 0.42), c, 12, 7)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.58, -2.0), Vector3(0.11, 0.1, 0.16), BANANA_TIP, 8, 5)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.17, 1.95), Vector3(0.1, 0.09, 0.12), BANANA_TIP, 8, 5)
	# 양옆 받침 튜브 (뒤집히지 않게): 몸통보다 짧고 가늘게, 앞뒤 끝이 둥글게.
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(st, Vector3(side * 0.5, 0.06, 1.05), Vector3(side * 0.5, 0.1, -0.95), 0.14, BANANA.darkened(0.08), 10, 3)
		ClayMesh.add_rod(st, Vector3(side * 0.2, 0.14, 0.05), Vector3(side * 0.45, 0.09, 0.05), 0.06, 0.06, BANANA.darkened(0.12), 6)
	# 손잡이 고리 (자리마다 앞에).
	for seat: Dictionary in banana_seats():
		var at: Vector3 = seat["at"]
		ClayMesh.add_torus(st, Vector3(0.0, at.y + 0.08, at.z - 0.3), 0.1, 0.025, ROPE_BLUE, 10, 4, Basis(Vector3.RIGHT, PI * 0.5))
	return ClayMesh.commit(st)


static func cruise_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var hull: Callable = func(p: Vector3, _n: Vector3) -> Color:
		if p.y < 0.05:
			return HULL_BLUE
		return HULL_RED if p.y < 0.16 else HULL_WHITE
	# 선체: 길쭉한 둥근 상자 + 뾰족한 뱃머리.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.25, 0.4), Vector3(2.7, 0.9, 6.4), 0.35, hull, Basis(), 16, 8)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.28, -2.75), Vector3(1.32, 0.46, 1.6), hull, 14, 7)
	# 갑판.
	ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y - 0.04, 0.3), Vector3(2.4, 0.08, 6.6), 0.15, DECK, Basis(), 12, 4)
	# 앞 조타실 (창 띠).
	ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y + 0.62, -2.35), Vector3(1.9, 1.24, 1.3), 0.25, HULL_WHITE, Basis(), 12, 6)
	ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y + 0.82, -2.35), Vector3(1.96, 0.4, 1.36), 0.2, GLASS, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y + 1.3, -2.35), Vector3(2.1, 0.12, 1.5), 0.25, HULL_BLUE, Basis(), 12, 4)
	# 조타실 뒤 짧은 줄무늬 차양 (손님 자리는 하늘이 트여 위에서도 보인다).
	for x: float in [-1.0, 1.0]:
		ClayMesh.add_rod(st, Vector3(x, DECK_Y, -1.25), Vector3(x, DECK_Y + 1.42, -1.25), 0.04, 0.04, RAIL, 6)
	for i: int in 2:
		var c: Color = CANOPY if i % 2 == 0 else CANOPY_STRIPE
		ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y + 1.42, -1.5 + float(i) * 0.4), Vector3(2.3, 0.06, 0.42), 0.3, c, Basis(), 8, 3)
	# 뱃전 난간.
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rod(st, Vector3(side * 1.18, DECK_Y + 0.55, -1.6), Vector3(side * 1.18, DECK_Y + 0.55, 3.25), 0.03, 0.03, RAIL, 5)
		for z: float in [-1.6, -0.4, 0.8, 2.0, 3.2]:
			ClayMesh.add_rod(st, Vector3(side * 1.18, DECK_Y, z), Vector3(side * 1.18, DECK_Y + 0.55, z), 0.025, 0.025, RAIL, 5)
		# 긴 의자 (바깥을 본다): 앉는 판 + 등받이.
		ClayMesh.add_rounded_box(st, Vector3(side * 0.42, DECK_Y + BENCH_Y - 0.05, 0.53), Vector3(0.42, 0.08, 3.9), 0.2, WOOD_LIGHT, Basis(), 8, 3)
		ClayMesh.add_rounded_box(st, Vector3(side * 0.2, DECK_Y + BENCH_Y + 0.22, 0.53), Vector3(0.07, 0.45, 3.9), 0.2, WOOD, Basis(), 8, 3)
		for z: float in [-1.2, 0.53, 2.25]:
			ClayMesh.add_rounded_box(st, Vector3(side * 0.42, DECK_Y + BENCH_Y * 0.5 - 0.05, z), Vector3(0.36, BENCH_Y - 0.06, 0.08), 0.2, WOOD, Basis(), 6, 3)
		# 구명 튜브 (조타실 옆).
		ClayMesh.add_torus(st, Vector3(side * 0.99, DECK_Y + 0.7, -2.0), 0.2, 0.06, RING, 12, 5, Basis(Vector3.BACK, PI * 0.5))
	# 고물 깃대 · 깃발.
	ClayMesh.add_rod(st, Vector3(0.0, DECK_Y, 3.45), Vector3(0.0, DECK_Y + 1.35, 3.45), 0.03, 0.025, RAIL, 5)
	ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y + 1.18, 3.72), Vector3(0.03, 0.3, 0.52), 0.2, HULL_RED, Basis(), 6, 3)
	return ClayMesh.commit(st)


## 잔교 (root → tip, 폭 width): 가로 판자 + 들보 + 말뚝. 수면 위 top.
static func pier_mesh(root: Vector2, tip: Vector2, width: float, top: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var along: Vector2 = tip - root
	var length: float = along.length()
	var yaw: float = atan2(-along.x, -along.y)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var planks: int = maxi(2, int(length / 0.32))
	for i: int in planks:
		var t: float = (float(i) + 0.5) / float(planks)
		var p: Vector2 = root.lerp(tip, t)
		var tone: Color = WOOD_LIGHT.lerp(WOOD, rng.randf_range(0.0, 0.55))
		ClayMesh.add_rounded_box(st, Vector3(p.x, top - 0.04, p.y), Vector3(width, 0.08, length / float(planks) - 0.04), 0.2, tone, basis * Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), 8, 4)
	var side_dir: Vector3 = basis * Vector3.RIGHT
	for side: float in [-1.0, 1.0]:
		var off: Vector3 = side_dir * side * (width * 0.5 - 0.06)
		var mid: Vector2 = root.lerp(tip, 0.5)
		ClayMesh.add_rounded_box(st, Vector3(mid.x, top - 0.13, mid.y) + off, Vector3(0.12, 0.12, length), 0.3, WOOD.darkened(0.15), basis, 8, 4)
		for t: float in [0.05, 0.5, 0.95]:
			var q: Vector2 = root.lerp(tip, t)
			ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(0.1, 0.09, -0.6, top + 0.3, 0.05, 2), 10, Transform3D(Basis(), Vector3(q.x, 0.0, q.y) + off * 1.08), ClayMesh.vertical_gradient(WOOD.darkened(0.35), WOOD_LIGHT, 1.0))
	# 끝 말뚝 둘에 구명 튜브 하나.
	var end: Vector3 = Vector3(tip.x, top + 0.35, tip.y) + side_dir * (width * 0.5 + 0.02)
	ClayMesh.add_torus(st, end, 0.2, 0.06, RING, 12, 5, basis * Basis(Vector3.BACK, PI * 0.5))
	return ClayMesh.commit(st)


## 매표소: 작은 나무 오두막 + 줄무늬 차양 + 바나나 · 배 그림 간판 받침. 앞 = -z (yaw 로 돌린다).
static func booth_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.7, 0.0), Vector3(1.7, 1.4, 1.3), 0.2, ClayMesh.vertical_gradient(WOOD.darkened(0.2), WOOD_LIGHT, 1.0), Basis(), 12, 6)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.05, -0.62), Vector3(1.1, 0.5, 0.06), 0.2, GLASS, Basis(), 8, 3)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.78, -0.78), Vector3(1.4, 0.07, 0.36), 0.2, WOOD_LIGHT, Basis(), 8, 3)
	for i: int in 5:
		var c: Color = CANOPY if i % 2 == 0 else CANOPY_STRIPE
		ClayMesh.add_rounded_box(st, Vector3(-0.72 + float(i) * 0.36, 1.5, -0.86), Vector3(0.37, 0.06, 0.62), 0.3, c, Basis(Vector3.RIGHT, -0.32), 6, 3)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.62, 0.05), Vector3(1.95, 0.14, 1.55), 0.3, HULL_BLUE, Basis(), 10, 4)
	# 간판 기둥 (글씨는 Label3D).
	ClayMesh.add_rod(st, Vector3(-0.7, 1.62, 0.0), Vector3(-0.7, 2.25, 0.0), 0.035, 0.035, RAIL, 5)
	ClayMesh.add_rod(st, Vector3(0.7, 1.62, 0.0), Vector3(0.7, 2.25, 0.0), 0.035, 0.035, RAIL, 5)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 2.3, 0.0), Vector3(1.9, 0.42, 0.08), 0.25, HULL_WHITE, Basis(), 10, 4)
	# 옆에 기대 둔 구명 튜브 · 작은 바나나 장식.
	ClayMesh.add_torus(st, Vector3(0.9, 0.55, -0.2), 0.22, 0.07, RING, 12, 5, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, 0.2))
	ClayMesh.add_ellipsoid(st, Vector3(-0.98, 0.35, 0.0), Vector3(0.12, 0.12, 0.42), BANANA, 10, 6, Basis(Vector3.RIGHT, 0.25))
	return ClayMesh.commit(st)
