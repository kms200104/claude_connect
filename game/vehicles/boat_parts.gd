class_name BoatParts
extends RefCounted
## 보트를 실제 모양대로 빚는다 (v21, VehicleModel 이 부른다). 좌표는 보트 좌표 (수면 y = 0, 뱃머리 = -z).
## 카약 = 레크리에이션 싯인 카약 (앞뒤가 들린 선체 · 조종석 테 · 해치 · 고무줄 · 숟가락 날 노),
## 모터보트 = 4.2 m 낚시용 스키프 (깊은 V 뱃머리 · 평평한 갑판 · 가운데 조종대와 바람막이 · 뱃머리 난간 · 선외기),
## 수상오토바이 = 스파크식 (깊은 V 선체 · 벌어진 갑판 · 핸들 포드 · 두 색 안장 · 뒤 발판 · 물 분사구).

const BLACK: Color = Color("#1E1F22")
const STEEL: Color = Color("#C9CDD3")
const NONSKID: Color = Color("#D9D6CE")


static func gl(c: Color) -> Color:
	return VehicleShapes.gloss(c)


static func mt(c: Color) -> Color:
	return VehicleShapes.matte(c)


static func cr(c: Color = STEEL) -> Color:
	return VehicleShapes.chrome(c)


# ---- 카약 ----

static func kayak(st: SurfaceTool, paint: Color, trim: Color, seat_c: Color, seg: int) -> void:
	var bow: float = -1.47
	var stern: float = 1.47
	var rings: Array[PackedVector3Array] = []
	for i: int in 41:
		var t: float = float(i) / 40.0
		var z: float = lerpf(bow, stern, t)
		var u: float = 2.0 * t - 1.0
		var half_w: float = 0.335 * pow(maxf(1.0 - pow(absf(u + 0.06), 2.2), 0.0), 0.62) + 0.006
		var rise: float = pow(absf(u), 5.0)
		var deck: float = 0.2 + 0.03 * (1.0 - absf(u)) + rise * 0.08
		var sheer: float = 0.11 + rise * 0.1
		var keel: float = -0.12 + rise * 0.17
		rings.append(VehicleShapes.hull_section(z, half_w, deck, sheer, keel, 0.78, 0.22, 40))
	var hull_c: Callable = func(p: Vector3, n: Vector3) -> Color:
		# 위는 칠한 색, 옆 가운데 진한 띠, 바닥은 살짝 어둡게 (폴리에틸렌).
		if p.y < -0.02:
			return gl(paint.darkened(0.18))
		return gl(paint)
	VehicleShapes.loft(st, rings, hull_c, true, true)
	# 조종석: 어두운 타원 (구멍처럼) + 테(코밍) + 안쪽 등받이 · 방석.
	var cockpit: Vector3 = Vector3(0.0, 0.245, 0.1)
	ClayMesh.add_ellipsoid(st, cockpit + Vector3(0.0, -0.012, 0.0), Vector3(0.215, 0.03, 0.4), mt(Color("#141518")), 32, 6)
	var rim: PackedVector3Array = PackedVector3Array()
	for k: int in 49:
		var a: float = TAU * float(k) / 48.0
		var lift: float = 0.012 * (1.0 - sin(a)) * 0.5
		rim.append(cockpit + Vector3(cos(a) * 0.225, lift, sin(a) * 0.41))
	VehicleShapes.sweep(st, rim, 0.016, gl(trim.darkened(0.1)), 10, false, 1.0)
	VehicleShapes.strip(st, VehicleShapes.spline(PackedVector3Array([Vector3(-0.17, 0.2, 0.36), Vector3(0.0, 0.25, 0.44), Vector3(0.17, 0.2, 0.36)]), 8), Vector3(0.0, 1.0, 0.0), 0.15, 0.03, mt(seat_c), 10)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.205, 0.2), Vector3(0.15, 0.022, 0.16), mt(seat_c.lightened(0.08)), 18, 5)
	# 앞뒤 둥근 해치 (검은 뚜껑 · 테).
	for z2: float in [-0.88, 0.86]:
		var y2: float = 0.235 + 0.015 * absf(z2)
		ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.018), Vector2(0.1, 0.014), Vector2(0.115, 0.0), Vector2(0.12, -0.012)]), 28, Transform3D(Basis(), Vector3(0.0, y2, z2)), mt(BLACK))
		ClayMesh.add_torus(st, Vector3(0.0, y2 - 0.004, z2), 0.12, 0.008, gl(trim), 28, 5)
	# 갑판 고무줄 (앞 · 뒤 엇갈림) · 옆 갑판 줄.
	for zz: Array in [[-0.62, -0.42], [0.58, 0.78]]:
		var a0: float = float(zz[0])
		var a1: float = float(zz[1])
		for side: float in [-1.0, 1.0]:
			VehicleShapes.sweep(st, PackedVector3Array([Vector3(-0.2 * side, 0.215, a0), Vector3(0.0, 0.252, (a0 + a1) * 0.5), Vector3(0.2 * side, 0.215, a1)]), 0.0045, mt(BLACK), 5, true)
		for z3: float in [a0, a1]:
			VehicleShapes.sweep(st, PackedVector3Array([Vector3(-0.22, 0.208, z3), Vector3(0.0, 0.252, z3), Vector3(0.22, 0.208, z3)]), 0.0045, mt(BLACK), 5, true)
	for side2: float in [-1.0, 1.0]:
		var line: PackedVector3Array = PackedVector3Array()
		for k2: int in 9:
			var t3: float = lerpf(0.2, 0.8, float(k2) / 8.0)
			var u3: float = 2.0 * t3 - 1.0
			var hw3: float = 0.335 * pow(maxf(1.0 - pow(absf(u3 + 0.06), 2.2), 0.0), 0.62)
			line.append(Vector3(side2 * (hw3 - 0.03), 0.18 + pow(absf(u3), 5.0) * 0.1, lerpf(bow, stern, t3)))
		VehicleShapes.sweep(st, VehicleShapes.spline(line, 4), 0.004, mt(BLACK), 5, true)
	# 앞뒤 손잡이 (고무 손잡이 + 줄).
	for zz2: float in [bow + 0.07, stern - 0.07]:
		var hp: Vector3 = Vector3(0.0, 0.3, zz2)
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([hp + Vector3(-0.05, -0.02, 0.0), hp + Vector3(0.0, 0.03, 0.0), hp + Vector3(0.05, -0.02, 0.0)]), 5), 0.007, mt(BLACK), 6, true)
		VehicleShapes.sweep(st, PackedVector3Array([hp + Vector3(-0.035, 0.025, 0.0), hp + Vector3(0.035, 0.025, 0.0)]), 0.011, mt(BLACK), 8, true)
	# 바닥 용골 줄 (스케그).
	VehicleShapes.strip(st, VehicleShapes.spline(PackedVector3Array([Vector3(0.0, -0.1, 0.6), Vector3(0.0, -0.11, 1.1), Vector3(0.0, -0.04, 1.42)]), 6), Vector3(0.0, 1.0, 0.0), 0.06, 0.01, gl(paint.darkened(0.25)), 8)


## 카약 노 (원점 = 노 가운데, X 축으로 놓인다): 카본 자루 · 물방울 막이 · 숟가락처럼 오목한 날 (양쪽 엇각).
static func paddle(st: SurfaceTool, trim: Color) -> void:
	VehicleShapes.sweep(st, PackedVector3Array([Vector3(-0.92, 0.0, 0.0), Vector3(0.92, 0.0, 0.0)]), 0.0145, gl(BLACK), 10, true)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_torus(st, Vector3(side * 0.62, 0.0, 0.0), 0.03, 0.006, mt(Color("#3A3C40")), 14, 4, Basis(Vector3.BACK, PI * 0.5))
		# 날: 길이 방향 단면을 이어 붙인 얇은 숟가락 (끝이 넓고 둥글다), 반대쪽 날은 비틀린다.
		var feather: float = side * 0.35
		var rings: Array[PackedVector3Array] = []
		for i: int in 11:
			var t: float = float(i) / 10.0
			var x: float = side * lerpf(0.9, 1.3, t)
			var w: float = lerpf(0.035, 0.085, smoothstep(0.0, 0.7, t)) * (1.0 - 0.7 * smoothstep(0.88, 1.0, t)) + 0.004
			var ring: PackedVector3Array = PackedVector3Array()
			for k: int in 14:
				var a: float = TAU * float(k) / 14.0
				var cup: float = -0.012 * (1.0 - pow(sin(a), 2.0)) * smoothstep(0.1, 0.5, t)
				var local: Vector3 = Vector3(0.0, sin(a) * 0.0055 + cup, cos(a) * w)
				ring.append(Vector3(x, 0.0, 0.0) + Basis(Vector3.RIGHT, feather) * local)
			rings.append(ring)
		VehicleShapes.loft(st, rings, gl(trim), true, true)


# ---- 모터보트 (4.2 m 낚시 스키프) ----

static func skiff(st: SurfaceTool, paint: Color, trim: Color, seat_c: Color, seg: int) -> void:
	var bow: float = -2.08
	var stern: float = 1.95
	var rings: Array[PackedVector3Array] = []
	var deck_at: Callable = func(t: float) -> float:
		return 0.36 + 0.18 * pow(1.0 - clampf(t / 0.45, 0.0, 1.0), 2.0)
	for i: int in 37:
		var t: float = float(i) / 36.0
		var z: float = lerpf(bow, stern, t)
		var fwd: float = clampf(t / 0.42, 0.0, 1.0)
		var half_w: float = 0.8 * pow(sin(fwd * PI * 0.5), 0.7) * (1.0 - 0.05 * smoothstep(0.8, 1.0, t)) + 0.012
		var deck: float = deck_at.call(t)
		var keel: float = -0.22 + 0.2 * pow(1.0 - clampf(t / 0.3, 0.0, 1.0), 1.7)
		var dead: float = lerpf(1.25, 0.3, smoothstep(0.0, 0.65, t))
		rings.append(VehicleShapes.hull_section(z, half_w, deck + 0.015, deck, keel, 0.6, dead, 40))
	var hull_c: Callable = func(p: Vector3, n: Vector3) -> Color:
		# 갑판(위를 보는 면)은 미끄럼 방지 회색, 옆은 칠, 물 아래는 방오 도료.
		if n.y > 0.75 and p.y > 0.3:
			return mt(NONSKID)
		if p.y < -0.02:
			return gl(Color("#28323E"))
		return gl(paint)
	VehicleShapes.loft(st, rings, hull_c, true, true)
	# 뱃전 고무 띠 · 옆 줄무늬 띠.
	for side: float in [-1.0, 1.0]:
		var rub: PackedVector3Array = PackedVector3Array()
		var band: PackedVector3Array = PackedVector3Array()
		for k: int in 31:
			var t2: float = lerpf(0.03, 0.995, float(k) / 30.0)
			var fwd2: float = clampf(t2 / 0.42, 0.0, 1.0)
			var hw: float = 0.8 * pow(sin(fwd2 * PI * 0.5), 0.7) * (1.0 - 0.05 * smoothstep(0.8, 1.0, t2)) + 0.012
			var y: float = deck_at.call(t2)
			rub.append(Vector3(side * (hw + 0.012), y - 0.015, lerpf(bow, stern, t2)))
			band.append(Vector3(side * (hw + 0.004), y - 0.15, lerpf(bow, stern, t2)))
		VehicleShapes.sweep(st, rub, 0.022, mt(Color("#2A2D33")), 8, true, 1.0)
		VehicleShapes.strip(st, band.slice(11), Vector3(0.0, 1.0, 0.0), 0.06, 0.008, gl(trim), 8)
	# 가운데 조종대 (위로 쌓은 둥근 네모 · 앞 바람막이 · 계기판).
	var console: Array[PackedVector3Array] = []
	for lv: Array in [[0.36, 0.0, 0.3, 0.24], [0.62, -0.01, 0.29, 0.23], [0.78, -0.03, 0.27, 0.18], [0.82, -0.04, 0.24, 0.14]]:
		console.append(VehicleShapes.ring_xz(0.0, float(lv[0]), 0.02 + float(lv[1]), float(lv[2]), float(lv[3]), 32, 0.75))
	VehicleShapes.loft(st, console, gl(Color("#F4F1EA")), false, true)
	var screen: Array[PackedVector3Array] = []
	for i2: int in 6:
		var t3: float = float(i2) / 5.0
		screen.append(MotoParts._crescent(lerpf(0.8, 1.05, t3), lerpf(-0.12, -0.03, t3), lerpf(0.3, 0.27, t3), 0.08, 0.006, 26))
	VehicleShapes.loft(st, screen, VehicleShapes.glass(Color("#7C98A8")), true, true)
	VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(-0.29, 1.05, -0.03), Vector3(0.0, 1.06, -0.13), Vector3(0.29, 1.05, -0.03)]), 8), 0.008, cr(), 6, true)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.83, 0.02), Vector3(0.3, 0.025, 0.14), 0.3, VehicleShapes.glass(Color("#1C2328")), Basis(Vector3.RIGHT, -0.5), 10, 3)
	# 운전석 (등받이 있는 방석 · 받침 기둥) · 뒤 긴 의자.
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.05, 0.02), Vector2(0.04, 0.2), Vector2(0.0, 0.2)]), 20, Transform3D(Basis(), Vector3(0.0, 0.36, 0.55)), cr())
	MotoParts._seat_loft(st, Vector3(0.0, 0.58, 0.58), 0.21, 0.36, 0.06, seat_c, "", seat_c)
	VehicleShapes.strip(st, VehicleShapes.spline(PackedVector3Array([Vector3(-0.19, 0.66, 0.76), Vector3(0.0, 0.7, 0.8), Vector3(0.19, 0.66, 0.76)]), 6), Vector3(0.0, 1.0, 0.0), 0.18, 0.05, mt(seat_c), 10)
	MotoParts._seat_loft(st, Vector3(0.0, 0.43, 1.5), 0.62, 0.34, 0.07, seat_c, "", seat_c)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.4, 1.5), Vector3(1.28, 0.08, 0.36), 0.25, gl(Color("#F4F1EA")), Basis(), 12, 4)
	# 뱃머리 난간 (스테인리스) · 계선주 · 닻 보관 뚜껑.
	for side3: float in [-1.0, 1.0]:
		var rail: PackedVector3Array = PackedVector3Array()
		for k3: int in 8:
			var t4: float = lerpf(0.02, 0.3, float(k3) / 7.0)
			var fwd4: float = clampf(t4 / 0.42, 0.0, 1.0)
			var hw4: float = 0.8 * pow(sin(fwd4 * PI * 0.5), 0.7) + 0.012 - 0.05
			rail.append(Vector3(side3 * hw4, deck_at.call(t4) + 0.22, lerpf(bow, stern, t4)))
			if k3 % 2 == 1:
				VehicleShapes.rod(st, Vector3(side3 * hw4, deck_at.call(t4), lerpf(bow, stern, t4)), Vector3(side3 * hw4, deck_at.call(t4) + 0.22, lerpf(bow, stern, t4)), 0.012, cr(), 6)
		VehicleShapes.sweep(st, VehicleShapes.spline(rail, 4), 0.014, cr(), 8, true)
		# 계선주 (클리트).
		ClayMesh.add_rounded_box(st, Vector3(side3 * 0.66, 0.38, 1.6), Vector3(0.03, 0.025, 0.12), 0.5, cr(), Basis(), 8, 3)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.53, -1.25), Vector3(0.42, 0.012, 0.36), 0.3, mt(NONSKID.darkened(0.1)), Basis(Vector3.RIGHT, 0.22), 10, 3)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.535, -1.12), Vector3(0.1, 0.012, 0.03), 0.4, cr(), Basis(Vector3.RIGHT, 0.22), 6, 2)
	# 트랜섬 (고물판) 위 선외기 받침 · 뒤 사다리.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.3, 1.96), Vector3(0.36, 0.18, 0.05), 0.3, gl(paint.darkened(0.06)), Basis(), 10, 3)
	for x: float in [0.45, 0.6]:
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(x, 0.38, 1.85), Vector3(x, 0.42, 2.0), Vector3(x, 0.1, 2.05), Vector3(x, -0.18, 2.02)]), 6), 0.011, cr(), 6, true)
	for k4: int in 3:
		VehicleShapes.rod(st, Vector3(0.45, 0.2 - float(k4) * 0.14, 2.04), Vector3(0.6, 0.2 - float(k4) * 0.14, 2.04), 0.01, cr(), 6)


## 선외기 (원점 = 고물판 받침 자리, 위 덮개 · 몸통 · 아래 다리 · 물막이판 · 스케그 · 세 날 프로펠러).
static func outboard(st: SurfaceTool, trim: Color) -> void:
	var cowl: Array[PackedVector3Array] = []
	var spec: Array = [[0.12, 0.13, 0.12, 0.0], [0.22, 0.16, 0.18, 0.02], [0.34, 0.165, 0.2, 0.03], [0.44, 0.15, 0.19, 0.03], [0.5, 0.1, 0.13, 0.02], [0.52, 0.04, 0.05, 0.01]]
	for row: Array in spec:
		cowl.append(VehicleShapes.ring_xz(0.0, float(row[0]), 0.08 + float(row[3]), float(row[1]), float(row[2]), 32, 0.55))
	var cowl_c: Callable = func(p: Vector3, _n: Vector3) -> Color:
		if p.y > 0.3 and p.y < 0.36:
			return gl(trim)
		return gl(Color("#26282C"))
	VehicleShapes.loft(st, cowl, cowl_c, true, true)
	# 몸통 (배기 몸통, 아래로 좁아진다).
	var mid: Array[PackedVector3Array] = []
	for lv: Array in [[0.13, 0.08, 0.12], [-0.05, 0.055, 0.1], [-0.3, 0.045, 0.085], [-0.45, 0.05, 0.09]]:
		mid.append(VehicleShapes.ring_xz(0.0, float(lv[0]), 0.1, float(lv[1]), float(lv[2]), 24, 0.4))
	VehicleShapes.loft(st, mid, gl(Color("#2E3034")), false, false)
	# 물막이판 · 기어 통(어뢰) · 스케그.
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.44, 0.12), Vector3(0.16, 0.012, 0.3), 0.4, gl(Color("#2E3034")), Basis(), 10, 3)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, -0.55, 0.11), Vector3(0.045, 0.045, 0.16), gl(Color("#2E3034")), 18, 8)
	VehicleShapes.strip(st, PackedVector3Array([Vector3(0.0, -0.58, 0.08), Vector3(0.0, -0.68, 0.12)]), Vector3(0.0, 0.0, 1.0), 0.07, 0.012, gl(Color("#2E3034")), 8)
	# 프로펠러 (세 날, 비틀린 넓은 날).
	var hub: Vector3 = Vector3(0.0, -0.55, 0.28)
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, -0.04), Vector2(0.022, -0.035), Vector2(0.024, 0.03), Vector2(0.0, 0.045)]), 14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hub), gl(Color("#3A3C40")))
	for k: int in 3:
		var a: float = TAU * float(k) / 3.0
		var rings: Array[PackedVector3Array] = []
		for i: int in 7:
			var t: float = float(i) / 6.0
			var rr: float = lerpf(0.02, 0.1, t)
			var w: float = lerpf(0.03, 0.05, sin(t * PI)) + 0.004
			var ring: PackedVector3Array = PackedVector3Array()
			for j: int in 10:
				var b: float = TAU * float(j) / 10.0
				var local: Vector3 = Vector3(cos(a) * rr, sin(a) * rr, 0.0) + Basis(Vector3(cos(a), sin(a), 0.0), 0.55) * Vector3(-sin(a) * cos(b) * w, cos(a) * cos(b) * w, sin(b) * 0.004)
				ring.append(hub + local)
			rings.append(ring)
		VehicleShapes.loft(st, rings, gl(Color("#9EA3AA")), true, true)
	# 고물판 죔쇠 · 앞 손잡이.
	for x: float in [-0.08, 0.08]:
		ClayMesh.add_rounded_box(st, Vector3(x, 0.08, -0.04), Vector3(0.03, 0.12, 0.06), 0.35, gl(Color("#2E3034")), Basis(), 8, 3)


# ---- 수상오토바이 ----

static func jetski(st: SurfaceTool, paint: Color, trim: Color, seat_c: Color, seg: int) -> void:
	var bow: float = -1.25
	var stern: float = 1.2
	var hull_rings: Array[PackedVector3Array] = []
	for i: int in 31:
		var t: float = float(i) / 30.0
		var z: float = lerpf(bow, stern, t)
		var fwd: float = clampf(t / 0.38, 0.0, 1.0)
		var hw: float = 0.47 * pow(sin(fwd * PI * 0.5), 0.6) * (1.0 - 0.06 * smoothstep(0.85, 1.0, t)) + 0.01
		var deck: float = 0.33 + 0.12 * pow(1.0 - fwd, 1.5)
		var keel: float = -0.12 + 0.12 * pow(1.0 - clampf(t / 0.3, 0.0, 1.0), 1.6)
		hull_rings.append(VehicleShapes.hull_section(z, hw, deck + 0.01, deck, keel, 0.62, lerpf(1.1, 0.45, t), 40))
	var hull_c: Callable = func(p: Vector3, n: Vector3) -> Color:
		if n.y > 0.8 and p.y > 0.28:
			return mt(Color("#2A2C30"))
		if p.y < 0.08:
			return gl(Color("#F2F0EA"))
		return gl(paint)
	VehicleShapes.loft(st, hull_rings, hull_c, true, true)
	# 위 몸체 (앞 덮개가 핸들 포드까지 솟고, 안장 받침이 가운데로 솟는다).
	var top: Array[PackedVector3Array] = []
	var spec: Array = [[-1.12, 0.05, 0.42, 0.04, 0.05], [-1.0, 0.25, 0.47, 0.08, 0.1], [-0.82, 0.35, 0.51, 0.13, 0.13], [-0.62, 0.37, 0.53, 0.17, 0.15], [-0.44, 0.34, 0.5, 0.14, 0.13], [-0.25, 0.29, 0.45, 0.07, 0.1], [0.3, 0.28, 0.44, 0.06, 0.1], [0.75, 0.26, 0.43, 0.05, 0.09], [0.95, 0.18, 0.42, 0.04, 0.08], [1.02, 0.06, 0.41, 0.02, 0.04]]
	for row: Array in spec:
		top.append(VehicleShapes.section(0.0, float(row[2]), float(row[0]), float(row[1]), float(row[3]), float(row[4]), 36, 0.45))
	var top_c: Callable = func(p: Vector3, _n: Vector3) -> Color:
		if p.z < -0.3 and absf(p.x) > 0.26 and absf(p.y - 0.5 - (p.z + 0.7) * 0.25) < 0.025:
			return gl(trim)
		return gl(paint)
	VehicleShapes.loft(st, top, top_c, true, true)
	# 안장 (두 색, 뒤는 동승석 턱).
	var seat_rings: Array[PackedVector3Array] = []
	for i2: int in 13:
		var t2: float = float(i2) / 12.0
		var z2: float = lerpf(-0.22, 0.88, t2)
		var hw2: float = 0.15 * (1.0 - 0.3 * pow(2.0 * t2 - 1.0, 4.0))
		var y2: float = 0.555 + 0.025 * smoothstep(0.55, 0.7, t2)
		seat_rings.append(VehicleShapes.section(0.0, y2, z2, hw2, 0.04, 0.05, 30, 0.55))
	var seat_color: Callable = func(p: Vector3, _n: Vector3) -> Color:
		if absf(p.x) > 0.11:
			return mt(seat_c.lightened(0.25))
		return mt(seat_c)
	VehicleShapes.loft(st, seat_rings, seat_color, true, true)
	# 앞 등줄 (두 눈처럼 보이는 앞 덮개 선) · 거울 · 손잡이 끈.
	for side: float in [-1.0, 1.0]:
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(side * 0.06, 0.58, -1.0), Vector3(side * 0.2, 0.62, -0.82), Vector3(side * 0.28, 0.6, -0.62)]), 6), 0.006, mt(BLACK), 6, true)
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(side * 0.2, 0.7, -0.6), Vector3(side * 0.3, 0.8, -0.62)]), 0.007, mt(BLACK), 6, true)
		ClayMesh.add_ellipsoid(st, Vector3(side * 0.32, 0.81, -0.62), Vector3(0.05, 0.03, 0.015), gl(BLACK), 12, 5)
		# 발판 홈 미끄럼 방지 매트.
		ClayMesh.add_rounded_box(st, Vector3(side * 0.38, 0.335, 0.25), Vector3(0.1, 0.012, 0.95), 0.3, mt(Color("#2A2C30")), Basis(), 10, 2)
	# 뒤 발판 (계단) · 물 분사구 · 견인 고리.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.3, 1.18), Vector3(0.6, 0.04, 0.16), 0.35, mt(Color("#2A2C30")), Basis(), 10, 3)
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.075, 0.0), Vector2(0.065, 0.12), Vector2(0.05, 0.14), Vector2(0.04, 0.0)]), 22, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.06, 1.12)), gl(Color("#3A3C40")))
	ClayMesh.add_torus(st, Vector3(0.0, 0.36, 1.25), 0.025, 0.006, cr(), 12, 4, Basis(Vector3.RIGHT, PI * 0.5))
	# 앞 등 자리 (VehicleModel 이 빛을 단다) 양옆 홈.
	for side2: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(side2 * 0.12, 0.58, -1.05), Vector3(0.05, 0.016, 0.03), VehicleShapes.glass(Color("#C8D4DC")), 12, 5, Basis(Vector3.UP, side2 * 0.5))


## 수상오토바이 핸들 (원점 = 조향 기둥 자리, 조향 좌표): 포드 덮개 · 바 · 그립 · 스로틀 레버 · 계기판.
static func jet_bars(st: SurfaceTool, paint: Color, bar: Vector3) -> void:
	var pod: Array[PackedVector3Array] = []
	for lv: Array in [[0.0, 0.1, 0.1], [0.08, 0.13, 0.11], [0.16, 0.12, 0.09], [0.2, 0.07, 0.05]]:
		pod.append(VehicleShapes.ring_xz(0.0, float(lv[0]), 0.0, float(lv[1]), float(lv[2]), 28, 0.5))
	VehicleShapes.loft(st, pod, gl(paint), false, true)
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.045, 0.008), Vector2(0.0, 0.01)]), 22, Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0.0, 0.2, 0.0)), VehicleShapes.glass(Color("#1E2A30")))
	for side: float in [-1.0, 1.0]:
		var path: PackedVector3Array = VehicleShapes.spline(PackedVector3Array([bar + Vector3(side * 0.05, 0.0, 0.0), bar + Vector3(side * 0.18, 0.01, 0.01), bar + Vector3(side * 0.26, 0.015, 0.03)]), 6)
		VehicleShapes.sweep(st, path, 0.013, cr(), 10, true)
		var end: Vector3 = path[path.size() - 1]
		var dir: Vector3 = (path[path.size() - 1] - path[path.size() - 2]).normalized()
		VehicleShapes.sweep(st, PackedVector3Array([end - dir * 0.02, end + dir * 0.1]), 0.019, mt(BLACK), 14, true)
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([end - dir * 0.02 + Vector3(0.0, 0.0, -0.02), end + dir * 0.03 + Vector3(0.0, -0.01, -0.04), end + dir * 0.07 + Vector3(0.0, -0.015, -0.03)]), 4), 0.006, mt(BLACK), 6, true)
	VehicleShapes.sweep(st, PackedVector3Array([Vector3(0.0, 0.0, 0.0), bar]), 0.03, gl(paint), 12, true)
