class_name AquaBoats
extends RefCounted
## 물놀이 체험 (v21) 모형: 바나나 튜브 · 유람선 · 잔교 · 매표소. 모두 점토 정점 색 (ClayMesh, 공용 머티리얼 하나).
## 배 좌표는 VehicleModel 과 같다: 수면 y = 0, 앞 = -z. 손님 자리(seats)는 같은 좌표의 { at: 엉덩이 자리, yaw: 바라보는 쪽 }.
const Shapes := preload("res://game/vehicles/vehicle_shapes.gd")

const BANANA: Color = Color("#F6D33C")
const BANANA_DARK: Color = Color("#D9A522")
const BANANA_TIP: Color = Color("#6E4A24")
const ROPE_BLUE: Color = Color("#2F5FA8")
const HULL_WHITE: Color = Color("#F4F1EA")
const HULL_BLUE: Color = Color("#2E6FB5")
const HULL_RED: Color = Color("#D24B3C")
const DECK: Color = Color("#A98E70")
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
	return Vector3(0.0, 0.39, -2.02)


## 바나나 튜브: 실제 놀이용 바나나 보트처럼 — 한 줄로 이어진 PVC 본 튜브(앞은 위로 휘며 뾰족한 원뿔 코),
## 이음매 띠 · 옆면 빨간 띠, 양옆 발 받침 튜브, 자리마다 양쪽 손잡이 고리, 바람 밸브, 코 아래 끄는 고리.
static func banana_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var yellow: Color = Shapes.gloss(BANANA)
	var stripe: Color = Shapes.gloss(Color("#D8402F"))
	# 본 튜브의 가운데 줄: 꼬리(+z) → 몸통 → 앞에서 위로 휘어 코끝.
	var spine: PackedVector3Array = Shapes.spline(PackedVector3Array([
		Vector3(0.0, 0.2, 1.62), Vector3(0.0, 0.2, 1.0), Vector3(0.0, 0.2, 0.0), Vector3(0.0, 0.205, -0.9),
		Vector3(0.0, 0.24, -1.45), Vector3(0.0, 0.36, -1.85), Vector3(0.0, 0.56, -2.08), Vector3(0.0, 0.74, -2.18),
	]), 8)
	# 꼬리는 반구로 둥글게 닫는다 (앞쪽에 점을 더해 굵기를 줄인다).
	var tail: PackedVector3Array = PackedVector3Array()
	var tail_r: PackedFloat32Array = PackedFloat32Array()
	for i: int in 6:
		var a: float = PI * 0.5 * float(6 - i) / 6.0
		tail.append(Vector3(0.0, 0.2, 1.62 + sin(a) * 0.3))
		tail_r.append(cos(a) * 0.3)
	var path: PackedVector3Array = PackedVector3Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i: int in tail.size():
		path.append(tail[i])
		radii.append(maxf(tail_r[i], 0.004))
	var total: float = 0.0
	var lengths: PackedFloat32Array = PackedFloat32Array([0.0])
	for i: int in range(1, spine.size()):
		total += spine[i].distance_to(spine[i - 1])
		lengths.append(total)
	for i: int in spine.size():
		var t: float = lengths[i] / total
		# 몸통은 굵기 그대로, 앞 35% 에서 원뿔처럼 가늘어져 코끝은 손가락만큼.
		var taper: float = clampf((t - 0.62) / 0.38, 0.0, 1.0)
		path.append(spine[i])
		radii.append(lerpf(0.3, 0.035, pow(taper, 0.85)))
	# 꼬리 끝(반구) → 몸통 → 코 차례로 한 줄.
	var main_color: Callable = func(p: Vector3, _n: Vector3) -> Color:
		# 옆면 가운데 높이의 빨간 띠 (몸통 구간만).
		if absf(p.x) > 0.2 and absf(p.y - 0.2) < 0.06 and p.z > -1.5 and p.z < 1.55:
			return stripe
		return yellow
	Shapes.sweep(st, path, radii, main_color, 40, true)
	# 이음매 띠 (용접 자리) · 코 이음매.
	for z: float in [-1.25, -0.6, 0.12, 0.85, 1.45]:
		ClayMesh.add_torus(st, Vector3(0.0, 0.2, z), 0.3, 0.012, Shapes.gloss(BANANA_DARK), 30, 5, Basis(Vector3.RIGHT, PI * 0.5))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.745, -2.185), Vector3(0.042, 0.042, 0.042), Shapes.gloss(BANANA_TIP), 10, 6)
	# 발 받침 튜브 (양옆, 앞뒤 둥근 끝) — 본 튜브 옆구리 아래에 붙는다.
	for side: float in [-1.0, 1.0]:
		var pp: PackedVector3Array = PackedVector3Array()
		var pr: PackedFloat32Array = PackedFloat32Array()
		# 앞뒤 끝은 반구 (끝 근처에 점을 촘촘히).
		var zs: PackedFloat32Array = PackedFloat32Array()
		for k2: int in 7:
			zs.append(1.33 - 0.13 * (1.0 - cos(PI * 0.5 * float(k2) / 6.0)))
		for k3: int in range(1, 12):
			zs.append(lerpf(1.2, -1.05, float(k3) / 12.0))
		for k4: int in 7:
			zs.append(-1.05 - 0.13 * sin(PI * 0.5 * float(k4) / 6.0))
		for z2: float in zs:
			var cap: float = 0.0
			if z2 > 1.2:
				cap = (z2 - 1.2) / 0.13
			elif z2 < -1.05:
				cap = (-1.05 - z2) / 0.13
			var rise: float = clampf((-0.6 - z2) / 0.6, 0.0, 1.0) * 0.05
			pp.append(Vector3(side * 0.43, 0.07 + rise, z2))
			pr.append(0.13 * sqrt(maxf(1.0 - cap * cap, 0.0)) + 0.003)
		Shapes.sweep(st, pp, pr, yellow, 18, true)
		# 받침 튜브와 본 튜브를 잇는 천 (앞뒤 두 자리).
		for z3: float in [-0.7, 0.75]:
			Shapes.strip(st, PackedVector3Array([Vector3(side * 0.2, 0.08, z3 - 0.18), Vector3(side * 0.2, 0.08, z3 + 0.18)]), Vector3(side, 0.0, 0.0), 0.3, 0.02, matte_c(BANANA_DARK), 10)
	# 자리마다 양쪽 손잡이: 검은 고무 D 고리 + 붙인 바탕 천.
	for seat: Dictionary in banana_seats():
		var at: Vector3 = seat["at"]
		for side2: float in [-1.0, 1.0]:
			var base_p: Vector3 = Vector3(side2 * 0.16, 0.2 + 0.255, at.z - 0.24)
			var out_dir: Vector3 = Vector3(side2 * 0.53, 0.85, 0.0).normalized()
			ClayMesh.add_ellipsoid(st, base_p, Vector3(0.045, 0.008, 0.06), Shapes.gloss(BANANA_DARK), 12, 4, Basis(Vector3.BACK, -side2 * 0.56))
			var loop: PackedVector3Array = PackedVector3Array()
			for k: int in 11:
				var a2: float = PI * float(k) / 10.0
				loop.append(base_p + out_dir * (0.008 + sin(a2) * 0.07) + Vector3(0.0, 0.0, -cos(a2) * 0.075))
			Shapes.sweep(st, loop, 0.014, matte_c(Color("#1E1E22")), 8, true)
	# 바람 밸브 (위 · 받침 튜브) · 꼬리 이름표.
	for v: Vector3 in [Vector3(0.0, 0.495, 1.4), Vector3(0.0, 0.495, -1.05), Vector3(0.43, 0.195, 0.0), Vector3(-0.43, 0.195, 0.0)]:
		ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.025), Vector2(0.018, 0.03), Vector2(0.0, 0.03)]), 12, Transform3D(Basis(), v), matte_c(Color("#2F2F34")))
	# 코 아래 끄는 고리 (스테인리스 D 링 + 보강 천).
	var ring_at: Vector3 = Vector3(0.0, 0.42, -1.96)
	ClayMesh.add_ellipsoid(st, ring_at + Vector3(0.0, 0.02, 0.02), Vector3(0.09, 0.02, 0.1), matte_c(Color("#2B2B30")), 10, 4, Basis(Vector3.RIGHT, 0.9))
	ClayMesh.add_torus(st, ring_at + Vector3(0.0, -0.03, -0.06), 0.05, 0.011, Shapes.chrome(), 16, 6, Basis(Vector3.BACK, PI * 0.5))
	return ClayMesh.commit(st)


static func matte_c(c: Color) -> Color:
	return Shapes.matte(c)


## 유람선: 작은 호수 관광선처럼 — 뱃머리가 벌어지며 솟는 선체(아래는 V, 고물은 평평한 트랜섬, 물 아래는 붉은 방오 도료),
## 갑판 둘레 낮은 뱃전벽 · 스테인리스 난간, 앞 조타실(빙 두른 창 · 처마 지붕), 양쪽 긴 의자, 구명 튜브, 고물 사다리 · 깃대.
static func cruise_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var white: Color = Shapes.gloss(HULL_WHITE)
	var blue: Color = Shapes.gloss(HULL_BLUE)
	var hull_color: Callable = func(p: Vector3, _n: Vector3) -> Color:
		if p.y < -0.02:
			return Shapes.gloss(Color("#8E2F2A"))
		if p.y < 0.03:
			return Shapes.gloss(Color("#1E2A38"))
		return white
	var bow: float = -3.95
	var stern: float = 3.65
	var rings: Array[PackedVector3Array] = []
	for i: int in 34:
		var t: float = float(i) / 33.0
		var z: float = lerpf(bow, stern, t)
		var fwd: float = clampf(t / 0.36, 0.0, 1.0)
		var half_w: float = 1.32 * pow(sin(fwd * PI * 0.5), 0.75) * (1.0 - 0.06 * smoothstep(0.85, 1.0, t)) + 0.015
		var deck: float = DECK_Y + 0.12 * pow(1.0 - fwd, 2.0)
		var keel: float = -0.34 + 0.3 * pow(1.0 - clampf(t / 0.28, 0.0, 1.0), 1.6)
		var dead: float = lerpf(1.1, 0.28, smoothstep(0.0, 0.6, t))
		rings.append(Shapes.hull_section(z, half_w, deck, deck - 0.02, keel, 0.55, dead, 36))
	Shapes.loft(st, rings, hull_color, true, true)
	# 갑판 둘레 뱃전벽 (갑판 위 0.26 m, 바깥으로 살짝 벌어진다) · 뱃전 띠.
	for side: float in [-1.0, 1.0]:
		var edge: PackedVector3Array = PackedVector3Array()
		var heights: PackedFloat32Array = PackedFloat32Array()
		for i: int in 26:
			var t2: float = lerpf(0.08, 0.985, float(i) / 25.0)
			var z2: float = lerpf(bow, stern, t2)
			var fwd2: float = clampf(t2 / 0.36, 0.0, 1.0)
			var hw: float = 1.32 * pow(sin(fwd2 * PI * 0.5), 0.75) * (1.0 - 0.06 * smoothstep(0.85, 1.0, t2)) - 0.04
			edge.append(Vector3(side * hw, DECK_Y + 0.12 * pow(1.0 - fwd2, 2.0) + 0.13, z2))
			heights.append(0.26)
		Shapes.strip(st, edge, Vector3(0.0, 1.0, 0.0), heights, 0.05, white, 10)
		var rub: PackedVector3Array = PackedVector3Array()
		for p2: Vector3 in edge:
			rub.append(Vector3(p2.x + side * 0.045, p2.y - 0.13, p2.z))
		Shapes.sweep(st, rub, 0.035, Shapes.matte(Color("#3A3F46")), 8, true)
		# 뱃전 아래 파란 띠 (선체 옆면에 붙인 띠).
		var band: PackedVector3Array = PackedVector3Array()
		for k0: int in range(2, edge.size()):
			var t3: float = lerpf(0.08, 0.985, float(k0) / 25.0)
			var fwd3: float = clampf(t3 / 0.36, 0.0, 1.0)
			var hw3: float = 1.32 * pow(sin(fwd3 * PI * 0.5), 0.75) * (1.0 - 0.06 * smoothstep(0.85, 1.0, t3)) + 0.012
			band.append(Vector3(side * hw3, edge[k0].y - 0.26, edge[k0].z))
		Shapes.strip(st, band, Vector3(0.0, 1.0, 0.0), 0.08, 0.012, blue, 8)
		# 스테인리스 난간: 기둥 + 위 · 가운데 줄 (뱃전벽 위).
		var rail_top: PackedVector3Array = PackedVector3Array()
		var rail_mid: PackedVector3Array = PackedVector3Array()
		for k: int in range(3, edge.size()):
			rail_top.append(edge[k] + Vector3(0.0, 0.5, 0.0))
			rail_mid.append(edge[k] + Vector3(0.0, 0.3, 0.0))
			if k % 3 == 0:
				Shapes.rod(st, edge[k] + Vector3(0.0, 0.1, 0.0), edge[k] + Vector3(0.0, 0.5, 0.0), 0.018, Shapes.chrome(), 6)
		Shapes.sweep(st, rail_top, 0.02, Shapes.chrome(), 8, true)
		Shapes.sweep(st, rail_mid, 0.012, Shapes.chrome(), 6, true)
		# 긴 의자 (바깥을 본다): 나무 앉는 판 · 등받이 · 스테인리스 다리.
		var seat_y: float = DECK_Y + BENCH_Y
		Shapes.strip(st, PackedVector3Array([Vector3(side * 0.42, seat_y - 0.03, -1.45), Vector3(side * 0.42, seat_y - 0.03, 2.5)]), Vector3(1.0, 0.0, 0.0), 0.4, 0.06, Shapes.matte(WOOD_LIGHT), 12)
		Shapes.strip(st, PackedVector3Array([Vector3(side * 0.2, seat_y + 0.22, -1.45), Vector3(side * 0.2, seat_y + 0.22, 2.5)]), Vector3(0.0, 1.0, 0.0), 0.36, 0.05, Shapes.matte(WOOD), 12)
		for z3: float in [-1.3, 0.53, 2.35]:
			Shapes.rod(st, Vector3(side * 0.42, DECK_Y, z3), Vector3(side * 0.42, seat_y - 0.05, z3), 0.022, Shapes.chrome(), 6)
			Shapes.rod(st, Vector3(side * 0.24, seat_y - 0.05, z3), Vector3(side * 0.2, seat_y + 0.42, z3), 0.016, Shapes.chrome(), 6)
		# 구명 튜브 (조타실 옆, 흰 띠 넷).
		var ring_c: Vector3 = Vector3(side * 0.985, DECK_Y + 0.72, -2.05)
		ClayMesh.add_torus(st, ring_c, 0.2, 0.055, Shapes.gloss(RING), 20, 8, Basis(Vector3.BACK, PI * 0.5))
		for q: int in 4:
			var a: float = TAU * float(q) / 4.0 + 0.4
			ClayMesh.add_torus(st, ring_c + Vector3(side * 0.0, cos(a) * 0.2, sin(a) * 0.2), 0.058, 0.012, Shapes.gloss(HULL_WHITE), 10, 4, Basis(Vector3.RIGHT, a))
	# 갑판 바닥 (나무 판자 결).
	var plank: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var row: float = fposmod(p.x * 6.0, 1.0)
		return Shapes.matte(DECK.darkened(0.18) if row < 0.07 else DECK)
	ClayMesh.add_rounded_box(st, Vector3(0.0, DECK_Y + 0.01, 0.6), Vector3(2.3, 0.03, 5.6), 0.12, plank, Basis(), 24, 3)
	# 조타실: 아래 벽 → 빙 두른 창 → 처마 지붕 (위로 쌓은 둥근 네모 고리, 앞 창은 뒤로 눕는다).
	var cab: Array[PackedVector3Array] = []
	var levels: Array = [[0.0, 0.0, 0.95, 0.66], [0.5, 0.0, 0.95, 0.66], [0.56, 0.02, 0.94, 0.64], [1.0, 0.1, 0.88, 0.56], [1.08, 0.11, 0.87, 0.55]]
	for lv: Array in levels:
		cab.append(Shapes.ring_xz(0.0, DECK_Y + float(lv[0]), -2.35 + float(lv[1]), float(lv[2]), float(lv[3]), 40, 0.82))
	var cab_color: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var h: float = p.y - DECK_Y
		# 네 귀퉁이 기둥은 흰 칠로 남긴다.
		var corner: bool = absf(absf(p.x) - 0.9) < 0.08 and absf(absf(p.z + 2.3) - 0.6) < 0.1
		if h > 0.55 and h < 1.02 and not corner:
			return Shapes.glass(Color("#30455A"))
		return white
	Shapes.loft(st, cab, cab_color, false, true)
	var roof: Array[PackedVector3Array] = [
		Shapes.ring_xz(0.0, DECK_Y + 1.08, -2.24, 1.08, 0.82, 40, 0.85),
		Shapes.ring_xz(0.0, DECK_Y + 1.15, -2.24, 1.08, 0.82, 40, 0.85),
	]
	Shapes.loft(st, roof, blue, true, true)
	# 조타실 지붕 위 등 · 경적 · 안테나.
	Shapes.rod(st, Vector3(0.0, DECK_Y + 1.15, -2.0), Vector3(0.0, DECK_Y + 1.55, -2.0), 0.018, Shapes.chrome(), 6)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, DECK_Y + 1.58, -2.0), Vector3(0.05, 0.05, 0.05), Shapes.matte(Color("#FFF6D8")), 10, 6)
	# 뱃머리 계선주 · 고물 사다리 · 깃대.
	Shapes.lathe_x(st, Vector3(-0.06, DECK_Y + 0.2, -3.45), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.03, 0.12), Vector2(0.0, 0.12)]), 10, Shapes.chrome())
	for x2: float in [-0.25, 0.25]:
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([Vector3(x2, DECK_Y + 0.25, 3.45), Vector3(x2, DECK_Y + 0.3, 3.75), Vector3(x2, 0.1, 3.85), Vector3(x2, -0.2, 3.8)]), 6), 0.016, Shapes.chrome(), 6, true)
	for k2: int in 3:
		Shapes.rod(st, Vector3(-0.25, 0.25 - float(k2) * 0.18, 3.83), Vector3(0.25, 0.25 - float(k2) * 0.18, 3.83), 0.012, Shapes.chrome(), 6)
	Shapes.rod(st, Vector3(0.0, DECK_Y + 0.25, 3.35), Vector3(0.0, DECK_Y + 1.5, 3.35), 0.022, Shapes.chrome(), 8, 0.016)
	Shapes.strip(st, PackedVector3Array([Vector3(0.0, DECK_Y + 1.3, 3.4), Vector3(0.0, DECK_Y + 1.3, 3.85)]), Vector3(0.0, 1.0, 0.0), 0.28, 0.01, Shapes.matte(HULL_RED), 8)
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
