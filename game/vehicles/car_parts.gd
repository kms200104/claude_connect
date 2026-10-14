extends RefCounted
## 차량 몸체 (v0.26, VehicleModel 이 쓴다): 사륜 ATV · 오픈 캐빈 미니트럭. 원점 = 바닥 가운데, 앞 = -Z.
## 둥근 상자 · 막대 · 고리(ClayMesh)로 빚는다. 바퀴 · 핸들(조향 마디)은 VehicleModel 이 따로 단다.

const DARK: Color = Color("#2A2A2E")
const STEEL: Color = Color("#5C6066")
const RUBBER: Color = Color("#1E1E22")


## 몸체 (바퀴 · 핸들 빼고).
static func body(st: SurfaceTool, style: String, paint: Color, trim: Color, seat: Color, seg: int) -> void:
	if style == "truck":
		_truck(st, paint, trim, seat, seg)
	else:
		_atv(st, paint, trim, seat, seg)


static func _atv(st: SurfaceTool, paint: Color, trim: Color, seat: Color, seg: int) -> void:
	# 프레임 · 아래 보호판.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.42, 0.0), Vector3(0.62, 0.16, 1.5), 0.3, DARK, Basis(), 12, 4)
	# 앞 · 뒤 흙받이 (바퀴를 덮는 넓은 펜더).
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.66, -0.62), Vector3(1.12, 0.16, 0.66), 0.6, paint, Basis(Vector3.RIGHT, 0.08), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.66, 0.6), Vector3(1.12, 0.16, 0.66), 0.6, paint, Basis(Vector3.RIGHT, -0.06), 12, 4)
	# 몸통 · 연료통 자리 · 안장.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.62, -0.02), Vector3(0.5, 0.26, 0.9), 0.6, paint.darkened(0.08), Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.8, -0.24), Vector3(0.38, 0.18, 0.38), 0.7, trim, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.76, 0.2), Vector3(0.38, 0.12, 0.7), 0.8, seat, Basis(), 12, 4)
	# 발판.
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rounded_box(st, Vector3(side * 0.38, 0.44, 0.02), Vector3(0.24, 0.04, 0.48), 0.3, DARK, Basis(), 12, 4)
	# 앞 · 뒤 짐받이 (철망).
	for z: float in [-0.74, 0.74]:
		ClayMesh.add_rounded_box(st, Vector3(0.0, 0.8, z), Vector3(0.86, 0.035, 0.42), 0.3, STEEL, Basis(), 12, 4)
		for x: float in [-0.4, 0.4]:
			ClayMesh.add_rod(st, Vector3(x, 0.8, z - 0.2), Vector3(x, 0.8, z + 0.2), 0.018, 0.018, STEEL, 6)
	# 통뼈 앞 범퍼 (크리처를 밀어낸다).
	ClayMesh.add_rod(st, Vector3(-0.42, 0.42, -1.04), Vector3(0.42, 0.42, -1.04), 0.04, 0.04, STEEL, 8)
	ClayMesh.add_rod(st, Vector3(-0.42, 0.66, -1.0), Vector3(0.42, 0.66, -1.0), 0.035, 0.035, STEEL, 8)
	for x: float in [-0.42, -0.14, 0.14, 0.42]:
		ClayMesh.add_rod(st, Vector3(x, 0.38, -1.04), Vector3(x, 0.68, -0.98), 0.03, 0.03, STEEL, 6)
	ClayMesh.add_rod(st, Vector3(0.0, 0.42, -1.04), Vector3(0.0, 0.42, -0.7), 0.04, 0.04, STEEL, 6)


static func _truck(st: SurfaceTool, paint: Color, trim: Color, seat: Color, seg: int) -> void:
	# 사다리 프레임 · 아래.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.46, 0.0), Vector3(1.2, 0.16, 3.3), 0.2, DARK, Basis(), 12, 4)
	# 캐빈 아래 몸통 · 보닛 (앞이 짧은 캡오버) · 앞 얼굴.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.8, -0.95), Vector3(1.56, 0.58, 1.6), 0.25, paint, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.14, -1.42), Vector3(1.5, 0.24, 0.62), 0.4, paint.lightened(0.05), Basis(Vector3.RIGHT, -0.18), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.8, -1.76), Vector3(0.9, 0.24, 0.04), 0.3, DARK, Basis(), 12, 4)
	for i: int in 3:
		ClayMesh.add_rounded_box(st, Vector3(0.0, 0.72 + 0.08 * float(i), -1.785), Vector3(0.84, 0.02, 0.02), 0.2, STEEL, Basis(), 12, 4)
	# 오픈 캐빈: 계기판 · 운전대 기둥 자리 · 앞 유리틀 (유리 없이) · 롤 바.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.16, -1.06), Vector3(1.44, 0.18, 0.3), 0.4, DARK, Basis(), 12, 4)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rod(st, Vector3(side * 0.74, 1.08, -1.2), Vector3(side * 0.7, 1.82, -0.98), 0.035, 0.035, paint.darkened(0.2), 6)
		ClayMesh.add_rod(st, Vector3(side * 0.74, 1.06, 0.0), Vector3(side * 0.74, 1.86, 0.0), 0.045, 0.045, STEEL, 6)
		# 문 (허리 높이까지).
		ClayMesh.add_rounded_box(st, Vector3(side * 0.77, 1.0, -0.58), Vector3(0.05, 0.42, 0.88), 0.3, paint, Basis(), 12, 4)
	ClayMesh.add_rod(st, Vector3(-0.7, 1.82, -0.98), Vector3(0.7, 1.82, -0.98), 0.035, 0.035, paint.darkened(0.2), 6)
	ClayMesh.add_rod(st, Vector3(-0.74, 1.86, 0.0), Vector3(0.74, 1.86, 0.0), 0.045, 0.045, STEEL, 6)
	# 의자 (긴 의자 · 등받이).
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.92, -0.34), Vector3(1.24, 0.14, 0.5), 0.6, seat, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.2, -0.08), Vector3(1.24, 0.5, 0.12), 0.6, seat, Basis(Vector3.RIGHT, -0.12), 12, 4)
	# 짐칸: 바닥 · 옆 · 뒷문 · 앞벽.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.84, 0.92), Vector3(1.56, 0.08, 1.7), 0.2, trim.darkened(0.15), Basis(), 12, 4)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_rounded_box(st, Vector3(side * 0.77, 1.04, 0.92), Vector3(0.05, 0.36, 1.7), 0.2, paint, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.04, 1.76), Vector3(1.56, 0.36, 0.05), 0.2, paint, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.1, 0.07), Vector3(1.56, 0.5, 0.05), 0.2, paint.darkened(0.1), Basis(), 12, 4)
	# 바퀴 덮개 (펜더) · 통뼈 범퍼.
	for z: float in [-1.12, 1.05]:
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_rounded_box(st, Vector3(side * 0.74, 0.74 if z < 0.0 else 0.84, z), Vector3(0.22, 0.08, 0.8), 0.5, paint.darkened(0.15) if z > 0.0 else paint, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.55, -1.82), Vector3(1.64, 0.2, 0.14), 0.4, STEEL, Basis(), 12, 4)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.55, 1.8), Vector3(1.5, 0.14, 0.1), 0.4, STEEL, Basis(), 12, 4)


## 바퀴 하나 (가운데 원점, 축 = X): 굵은 타이어 · 휠.
static func wheel(st: SurfaceTool, r: float, width: float, trim: Color, seg: int) -> void:
	var axis: Basis = Basis(Vector3.BACK, PI * 0.5)
	ClayMesh.add_torus(st, Vector3.ZERO, r - width * 0.5, width * 0.5, RUBBER, seg, 6, axis)
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(width * 0.42, r * 0.6, r * 0.6), trim, seg, 4)
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(width * 0.5, r * 0.18, r * 0.18), DARK, 8, 3)


## 운전대 · 핸들 (조향 마디 원점 기준). ATV 는 막대 핸들, 트럭은 둥근 운전대.
static func steer(st: SurfaceTool, style: String, trim: Color) -> void:
	if style == "truck":
		ClayMesh.add_torus(st, Vector3.ZERO, 0.17, 0.022, DARK, 16, 5, Basis(Vector3.RIGHT, PI * 0.5 - 0.5))
		ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, -0.22, -0.18), 0.03, 0.03, DARK, 6)
	else:
		ClayMesh.add_rod(st, Vector3(-0.34, 0.0, 0.0), Vector3(0.34, 0.0, 0.0), 0.02, 0.02, DARK, 6)
		ClayMesh.add_rod(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.3, -0.04), 0.03, 0.03, DARK, 6)
		for side: float in [-1.0, 1.0]:
			ClayMesh.add_capsule(st, Vector3(side * 0.26, 0.0, 0.0), Vector3(side * 0.36, 0.0, 0.0), 0.03, trim.darkened(0.4), 6, 2)
