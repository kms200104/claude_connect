class_name MotoParts
extends RefCounted
## 전기 오토바이 부품을 실제 모양대로 빚는다 (v21, VehicleModel 이 부른다). 좌표는 탈것 좌표 (바닥 y = 0, 앞 = -z).
## 스쿠터 = 베스파식 모노코크 (다리 가림판 · 옆 볼록 카울 · 핸들 덮개에 박힌 둥근 등), 클래식 = 카페 레이서 (물방울 탱크 ·
## 철사 바퀴살 · 쌍 크롬 쇼크 · 포크 주름 고무), 스포츠 = 풀 카울 (두 눈 앞 카울 · 바람막이 · 솟은 꼬리 · 도립 포크 · 웨이브 디스크 · 벨트).

const RUBBER: Color = Color("#1E1E21")
const BLACK: Color = Color("#202024")
const ALLOY: Color = Color("#B9BDC4")
const STEEL: Color = Color("#C9CDD3")
const DARK_METAL: Color = Color("#3A3D42")
const GOLD: Color = Color("#D7A84A")


static func gl(c: Color) -> Color:
	return VehicleShapes.gloss(c)


static func mt(c: Color) -> Color:
	return VehicleShapes.matte(c)


static func cr(c: Color = STEEL) -> Color:
	return VehicleShapes.chrome(c)


# ---- 바퀴 (축 = X, 원점 = 허브) ----

static func tire_width(style: String, rear: bool, tire: Dictionary) -> float:
	var w: float = {"scooter": 0.072, "classic": 0.064}.get(style, 0.08 if not rear else 0.095)
	return w * float(tire.get("w", 1.0))


## 오토바이 바퀴: 둥근 타이어(트레드 홈) · 림 · 휠(스쿠터 5 살 · 클래식 철사살 · 스포츠 Y 3 살) · 디스크 · 허브 모터.
static func wheel(st: SurfaceTool, r: float, style: String, tire: Dictionary, trim: Color, rear: bool, seg: int) -> void:
	var w: float = tire_width(style, rear, tire)
	var wall_c: Color = Color.html(str(tire.get("c", "#2A2A2E")))
	var custom_wall: bool = tire.has("c") and wall_c != Color("#2A2A2E")
	var h: float = w * 0.82
	var rc: float = r - h * 0.5
	var prof: PackedVector2Array = PackedVector2Array()
	for i: int in 17:
		var phi: float = deg_to_rad(lerpf(-118.0, 118.0, float(i) / 16.0))
		prof.append(Vector2(rc + cos(phi) * h * 0.5, sin(phi) * w * 0.5))
	var tire_color: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var rho: float = Vector2(p.y, p.z).length()
		if custom_wall and absf(p.x) > w * 0.32 and rho < r - h * 0.3 and rho > r - h * 0.75:
			return mt(wall_c)
		return mt(RUBBER)
	VehicleShapes.lathe_x(st, Vector3.ZERO, prof, maxi(seg * 3, 56), tire_color)
	# 트레드 홈 (비스듬한 홈 무늬).
	var grooves: int = 30
	for i2: int in grooves:
		var a: float = TAU * float(i2) / float(grooves)
		for side: float in [-1.0, 1.0]:
			var x: float = side * w * 0.22
			ClayMesh.add_rounded_box(st, Vector3(x, cos(a) * (r - 0.0015), sin(a) * (r - 0.0015)), Vector3(0.004, 0.003, w * 0.42), 0.4, mt(Color("#141416")), Basis(Vector3.RIGHT, -a) * Basis(Vector3.UP, side * 0.6), 4, 2)
	# 림.
	var r_out: float = r - h * 0.92
	var rim_w: float = w * 0.78
	var rim_c: Color = cr() if style == "classic" else gl(trim.darkened(0.05) if style == "scooter" else BLACK)
	VehicleShapes.lathe_x(st, Vector3.ZERO, PackedVector2Array([
		Vector2(r_out - 0.016, -rim_w * 0.35), Vector2(r_out - 0.003, -rim_w * 0.5), Vector2(r_out + 0.004, -rim_w * 0.52),
		Vector2(r_out + 0.004, rim_w * 0.52), Vector2(r_out - 0.003, rim_w * 0.5), Vector2(r_out - 0.016, rim_w * 0.35),
	]), maxi(seg * 3, 56), rim_c, true)
	if style == "sport":
		# 림 가장자리 색 띠.
		for side2: float in [-1.0, 1.0]:
			ClayMesh.add_torus(st, Vector3(side2 * rim_w * 0.53, 0.0, 0.0), r_out - 0.004, 0.0025, gl(trim), 48, 4, Basis(Vector3.BACK, PI * 0.5))
	# 허브.
	var hub_r: float = 0.05 if rear else 0.034
	var hub_w: float = 0.05 if rear else 0.04
	VehicleShapes.lathe_x(st, Vector3.ZERO, PackedVector2Array([
		Vector2(0.01, -hub_w - 0.012), Vector2(0.016, -hub_w - 0.01), Vector2(hub_r * 0.8, -hub_w), Vector2(hub_r, -hub_w * 0.6),
		Vector2(hub_r, hub_w * 0.6), Vector2(hub_r * 0.8, hub_w), Vector2(0.016, hub_w + 0.01), Vector2(0.01, hub_w + 0.012),
	]), 24, mt(DARK_METAL) if rear else (cr(ALLOY) if style == "classic" else gl(BLACK)))
	if rear:
		# 허브 모터 덮개의 냉각 핀.
		for k: int in 16:
			var a2: float = TAU * float(k) / 16.0
			ClayMesh.add_rounded_box(st, Vector3(0.0, cos(a2) * hub_r * 1.02, sin(a2) * hub_r * 1.02), Vector3(hub_w * 1.6, 0.006, 0.008), 0.3, mt(Color("#4A4E55")), Basis(Vector3.RIGHT, -a2), 4, 2)
	match style:
		"classic":
			# 철사 바퀴살 36 개 (엇갈림).
			for i3: int in 36:
				var side3: float = 1.0 if i3 % 2 == 0 else -1.0
				var ah: float = TAU * float(i3) / 36.0
				var ar: float = ah + (TAU / 36.0) * 5.0 * (1.0 if (i3 / 2) % 2 == 0 else -1.0)
				VehicleShapes.rod(st, Vector3(side3 * hub_w * 0.8, cos(ah) * hub_r * 0.85, sin(ah) * hub_r * 0.85), Vector3(side3 * 0.004, cos(ar) * (r_out - 0.014), sin(ar) * (r_out - 0.014)), 0.0022, cr(), 4)
		"scooter":
			# 다섯 살 알루미늄 휠 (살이 림 쪽에서 둘로 갈라진다).
			for i4: int in 5:
				var a4: float = TAU * float(i4) / 5.0
				for fork: float in [-0.12, 0.12]:
					var spoke: PackedVector3Array = PackedVector3Array([Vector3(0.0, cos(a4) * hub_r * 0.9, sin(a4) * hub_r * 0.9), Vector3(0.0, cos(a4 + fork * 0.4) * r_out * 0.6, sin(a4 + fork * 0.4) * r_out * 0.6), Vector3(0.0, cos(a4 + fork) * (r_out - 0.012), sin(a4 + fork) * (r_out - 0.012))])
					VehicleShapes.sweep(st, spoke, PackedFloat32Array([0.011, 0.008, 0.0065]), gl(trim.darkened(0.05)), 8, true, 1.6, Vector3(1.0, 0.0, 0.0))
		_:
			# 스포츠: Y 자 세 살 (날카로운 주조 휠).
			for i5: int in 3:
				var a5: float = TAU * float(i5) / 3.0
				for fork2: float in [-0.22, 0.22]:
					var spoke2: PackedVector3Array = VehicleShapes.spline(PackedVector3Array([Vector3(0.0, cos(a5) * hub_r * 0.9, sin(a5) * hub_r * 0.9), Vector3(0.0, cos(a5) * r_out * 0.5, sin(a5) * r_out * 0.5), Vector3(0.0, cos(a5 + fork2) * (r_out - 0.012), sin(a5 + fork2) * (r_out - 0.012))]), 5)
					VehicleShapes.sweep(st, spoke2, PackedFloat32Array(_ramp(spoke2.size(), 0.012, 0.007)), gl(BLACK), 8, true, 1.7, Vector3(1.0, 0.0, 0.0))
	if not rear or style == "sport":
		# 디스크 (스포츠 앞은 양쪽 웨이브 디스크).
		var sides: Array = [-1.0] if style != "sport" or rear else [-1.0, 1.0]
		var disc_r: float = r_out - 0.03
		for s4: float in sides:
			var dx: float = s4 * (hub_w + 0.006)
			var wave: PackedVector2Array = PackedVector2Array()
			wave.append(Vector2(disc_r * 0.62, -0.002))
			wave.append(Vector2(disc_r, -0.002))
			wave.append(Vector2(disc_r, 0.002))
			wave.append(Vector2(disc_r * 0.62, 0.002))
			VehicleShapes.lathe_x(st, Vector3(dx, 0.0, 0.0), wave, 56, cr(Color("#BFC3C9")), true)
			if style == "sport":
				for k2: int in 12:
					var a6: float = TAU * float(k2) / 12.0
					ClayMesh.add_ellipsoid(st, Vector3(dx, cos(a6) * disc_r, sin(a6) * disc_r), Vector3(0.0035, 0.014, 0.014), mt(Color("#202226")), 6, 3)
			for k3: int in 6:
				var a7: float = TAU * float(k3) / 6.0
				ClayMesh.add_ellipsoid(st, Vector3(dx, cos(a7) * disc_r * 0.78, sin(a7) * disc_r * 0.78), Vector3(0.004, 0.006, 0.006), mt(Color("#202226")), 6, 3)
			# 디스크 받침: 허브에서 원판 안쪽으로 다섯 팔 (가운데는 뚫려 휠이 보인다).
			for k4: int in 5:
				var a8: float = TAU * float(k4) / 5.0 + 0.3
				VehicleShapes.rod(st, Vector3(dx - s4 * 0.002, cos(a8) * hub_r * 0.7, sin(a8) * hub_r * 0.7), Vector3(dx, cos(a8) * disc_r * 0.64, sin(a8) * disc_r * 0.64), 0.006, gl(BLACK) if style == "sport" else mt(DARK_METAL), 6)


# ---- 몸체 ----

## p: { axle_f, axle_r, head_top, seat, floor, tail, frame, r } — 탈것 좌표.
static func body(st: SurfaceTool, style: String, paint: Color, trim: Color, seat_c: Color, seat_shape: String, p: Dictionary, seg: int) -> void:
	match style:
		"scooter":
			_scooter_body(st, paint, trim, seat_c, seat_shape, p, seg)
		"classic":
			_classic_body(st, paint, trim, seat_c, seat_shape, p, seg)
		_:
			_sport_body(st, paint, trim, seat_c, seat_shape, p, seg)


## 베스파식: 발판(고무 줄) · 다리 가림판(앞이 볼록한 판, 가운데 "넥타이" 그릴) · 옆이 볼록한 뒤 카울 · 시트(파이핑) · 손잡이 레일 · 짐받이.
static func _scooter_body(st: SurfaceTool, paint: Color, trim: Color, seat_c: Color, seat_shape: String, p: Dictionary, seg: int) -> void:
	var ar: Vector3 = p["axle_r"]
	var ht: Vector3 = p["head_top"]
	var fl: Vector3 = p["floor"]
	var pc: Color = gl(paint)
	# 발판: 둥근 판 + 고무 줄.
	var floor_rings: Array[PackedVector3Array] = []
	for i: int in 9:
		var t: float = float(i) / 8.0
		var z: float = lerpf(-0.36, 0.06, t)
		var hw: float = lerpf(0.15, 0.135, t)
		floor_rings.append(VehicleShapes.section(0.0, fl.y - 0.03, z, hw, 0.012, 0.03, 24, 0.75))
	VehicleShapes.loft(st, floor_rings, pc, true, true)
	for k: int in 5:
		var x: float = -0.09 + float(k) * 0.045
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(x, fl.y - 0.012, -0.32), Vector3(x, fl.y - 0.012, 0.03)]), 0.006, mt(Color("#2E2E32")), 6, true, 2.0, Vector3(1.0, 0.0, 0.0))
	# 다리 가림판: 발판 앞에서 핸들 아래까지 위로 쌓은 초승달 단면 (앞이 볼록, 뒤는 오목).
	var shield: Array[PackedVector3Array] = []
	for i2: int in 11:
		var t2: float = float(i2) / 10.0
		var y: float = lerpf(fl.y - 0.04, ht.y - 0.06, t2)
		var cz: float = lerpf(-0.34, ht.z - 0.02, pow(t2, 1.3))
		var hw2: float = lerpf(0.215, 0.15, t2) * (1.0 - 0.25 * smoothstep(0.85, 1.0, t2))
		shield.append(_crescent(y, cz, hw2, 0.075, 0.022, 30))
	VehicleShapes.loft(st, shield, pc, true, true)
	# 가림판 가운데 넥타이 (크롬 테 그릴) · 경적.
	VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(0.0, ht.y - 0.12, ht.z - 0.1), Vector3(0.0, ht.y - 0.22, -0.43), Vector3(0.0, ht.y - 0.32, -0.42)]), 6), PackedFloat32Array(_ramp(13, 0.022, 0.03)), gl(paint.darkened(0.08)), 12, true, 1.0, Vector3(1.0, 0.0, 0.0))
	for k2: int in 4:
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(-0.02, ht.y - 0.22 - float(k2) * 0.025, -0.455 + float(k2) * 0.004), Vector3(0.02, ht.y - 0.22 - float(k2) * 0.025, -0.455 + float(k2) * 0.004)]), 0.0035, cr(), 5, true)
	# 뒤 카울: 시트 밑에서 꼬리까지, 바퀴 위 옆구리가 볼록하다 (베스파 엉덩이).
	var cowl: Array[PackedVector3Array] = []
	var spec: Array = [[-0.1, 0.09, 0.29, 0.08, 0.1], [0.0, 0.14, 0.3, 0.075, 0.11], [0.12, 0.19, 0.31, 0.07, 0.11], [0.26, 0.215, 0.31, 0.07, 0.1], [0.4, 0.215, 0.315, 0.065, 0.09], [0.53, 0.18, 0.33, 0.06, 0.07], [0.64, 0.12, 0.35, 0.05, 0.05], [0.71, 0.06, 0.37, 0.035, 0.035], [0.745, 0.02, 0.38, 0.015, 0.015]]
	for row: Array in spec:
		cowl.append(VehicleShapes.section(0.0, float(row[2]), float(row[0]), float(row[1]), float(row[3]), float(row[4]), 36, 0.25))
	VehicleShapes.loft(st, cowl, pc, true, true)
	# 옆 장식 띠 · 엠블럼.
	for side: float in [-1.0, 1.0]:
		var line_pts: PackedVector3Array = PackedVector3Array()
		for row2: Array in spec.slice(1, 7):
			line_pts.append(Vector3(side * (float(row2[1]) + 0.003), float(row2[2]) - 0.02, float(row2[0])))
		VehicleShapes.sweep(st, VehicleShapes.spline(line_pts, 5), 0.004, cr(), 5, true)
		ClayMesh.add_ellipsoid(st, Vector3(side * 0.205, 0.32, 0.3), Vector3(0.006, 0.018, 0.04), cr(), 10, 4)
	# 시트 (파이핑 테두리) · 손잡이 레일 · 짐받이.
	var seat_at: Vector3 = p["seat"]
	_seat_loft(st, seat_at + Vector3(0.0, -0.035, 0.04), 0.14, 0.5, 0.06, seat_c, seat_shape, trim)
	var rail: PackedVector3Array = VehicleShapes.spline(PackedVector3Array([Vector3(-0.12, 0.42, 0.24), Vector3(-0.13, 0.43, 0.42), Vector3(-0.08, 0.43, 0.55), Vector3(0.0, 0.43, 0.58), Vector3(0.08, 0.43, 0.55), Vector3(0.13, 0.43, 0.42), Vector3(0.12, 0.42, 0.24)]), 6)
	VehicleShapes.sweep(st, rail, 0.008, cr(), 8, true)
	for z2: float in [0.46, 0.52]:
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(-0.1, 0.432, z2), Vector3(0.1, 0.432, z2)]), 0.005, cr(), 6, true)
	# 가운데 받침대 · 왼쪽 스윙암 덮개 (허브 모터).
	VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(-0.1, 0.16, 0.1), Vector3(-0.1, 0.08, 0.2), Vector3(-0.1, 0.03, 0.28)]), 5), 0.008, mt(BLACK), 6, true)
	VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(-0.1, 0.24, 0.05), Vector3(-0.1, 0.23, 0.3), ar + Vector3(-0.1, 0.0, 0.0)]), 6), PackedFloat32Array(_ramp(13, 0.03, 0.04)), mt(DARK_METAL), 10, true, 0.45, Vector3(1.0, 0.0, 0.0))
	# 번호판 받이.
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.3, 0.74), Vector3(0.11, 0.06, 0.008), 0.25, mt(Color("#F2EEE4")), Basis(Vector3.RIGHT, -0.35), 8, 3)


## 카페 레이서: 물방울 탱크(무릎 홈 · 크롬 뚜껑) · 이중 요람 프레임 · 배터리 상자(냉각 핀) · 납작한 시트와 꼬리 혹 ·
## 스윙암 · 쌍 쇼크(크롬 스프링) · 짧은 크롬 흙받이 · 발판.
static func _classic_body(st: SurfaceTool, paint: Color, trim: Color, seat_c: Color, seat_shape: String, p: Dictionary, seg: int) -> void:
	var ar: Vector3 = p["axle_r"]
	var ht: Vector3 = p["head_top"]
	var fl: Vector3 = p["floor"]
	var r: float = float(p["r"])
	var pc: Color = gl(paint)
	# 프레임: 등뼈 관 · 아래 요람 관 둘.
	var neck: Vector3 = ht + Vector3(0.0, -0.06, 0.03)
	VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([neck, Vector3(0.0, 0.55, -0.15), Vector3(0.0, 0.42, 0.06), Vector3(0.0, 0.385, 0.3), Vector3(0.0, 0.43, 0.62)]), 6), PackedFloat32Array(_ramp(25, 0.022, 0.014)), gl(BLACK), 12, true)
	for side: float in [-1.0, 1.0]:
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([neck + Vector3(side * 0.01, -0.05, 0.0), Vector3(side * 0.06, 0.38, -0.3), Vector3(side * 0.07, 0.17, -0.18), Vector3(side * 0.07, 0.15, 0.04), Vector3(side * 0.065, 0.3, 0.1), Vector3(side * 0.06, 0.39, 0.22)]), 6), 0.013, gl(BLACK), 10, true)
		# 뒤 서브프레임 · 쇼크 업소버 (스프링 + 몸통).
		var shock_top: Vector3 = Vector3(side * 0.085, 0.42, 0.42)
		var shock_low: Vector3 = ar + Vector3(side * 0.085, 0.03, -0.05)
		VehicleShapes.sweep(st, PackedVector3Array([shock_low, shock_top]), 0.012, mt(BLACK), 10, true)
		VehicleShapes.sweep(st, VehicleShapes.helix(shock_low.lerp(shock_top, 0.15), shock_low.lerp(shock_top, 0.85), 0.018, 8.0, 120), 0.0042, cr(), 6, true)
		# 스윙암.
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(side * 0.07, 0.25, 0.08), ar + Vector3(side * 0.075, 0.0, 0.0)]), 0.015, gl(BLACK), 10, true)
		# 발판.
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(side * 0.06, fl.y, fl.z), Vector3(side * 0.15, fl.y, fl.z + 0.01)]), 0.011, mt(Color("#2A2A2E")), 8, true)
	# 탱크 (물방울, 무릎 홈) + 크롬 뚜껑 · 가로 띠.
	var tank: Array[PackedVector3Array] = []
	for i: int in 13:
		var t: float = float(i) / 12.0
		var z: float = lerpf(-0.37, 0.02, t)
		var hw: float = 0.105 * sin(lerpf(0.35, 2.75, t)) * (1.0 - 0.18 * smoothstep(0.55, 1.0, t))
		var top: float = 0.075 * sin(lerpf(0.5, 2.6, t))
		var cy: float = lerpf(0.6, 0.55, t)
		tank.append(VehicleShapes.section(0.0, cy, z, hw + 0.01, top + 0.01, 0.055, 32, 0.15))
	VehicleShapes.loft(st, tank, pc, true, true)
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.01), Vector2(0.022, 0.016), Vector2(0.0, 0.017)]), 18, Transform3D(Basis(), Vector3(0.0, 0.676, -0.2)), cr())
	for side2: float in [-1.0, 1.0]:
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(side2 * 0.08, 0.6, -0.31), Vector3(side2 * 0.113, 0.58, -0.18), Vector3(side2 * 0.095, 0.57, -0.06)]), 6), 0.005, gl(trim), 6, true)
		ClayMesh.add_ellipsoid(st, Vector3(side2 * 0.112, 0.585, -0.2), Vector3(0.004, 0.022, 0.04), cr(), 10, 4)
	# 배터리 상자 (모터 자리, 냉각 핀 · 은색 덮개).
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.31, -0.08), Vector3(0.14, 0.2, 0.3), 0.2, mt(Color("#2A2C30")), Basis(), 10, 4)
	for k: int in 7:
		ClayMesh.add_rounded_box(st, Vector3(0.0, 0.23 + float(k) * 0.026, -0.08), Vector3(0.152, 0.008, 0.31), 0.3, mt(Color("#3E4248")), Basis(), 8, 2)
	for side3: float in [-1.0, 1.0]:
		ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.012), Vector2(0.04, 0.02), Vector2(0.0, 0.022)]), 24, Transform3D(Basis(Vector3.BACK, -side3 * PI * 0.5), Vector3(side3 * 0.078, 0.3, -0.08)), cr(ALLOY))
	# 시트 (평평한 가죽, 가로 주름) + 꼬리 혹 + 짧은 크롬 흙받이.
	var seat_at: Vector3 = p["seat"]
	_seat_loft(st, seat_at + Vector3(0.0, -0.03, 0.06), 0.11, 0.42, 0.05, seat_c, "quilt" if seat_shape == "" else seat_shape, trim)
	var hump: Array[PackedVector3Array] = []
	for i2: int in 7:
		var t2: float = float(i2) / 6.0
		hump.append(VehicleShapes.section(0.0, 0.5 + 0.02 * sin(t2 * PI), lerpf(0.5, 0.74, t2), 0.09 * (1.0 - 0.6 * t2) + 0.01, 0.05 * (1.0 - 0.5 * t2) + 0.005, 0.03, 24, 0.3))
	VehicleShapes.loft(st, hump, pc, true, true)
	VehicleShapes.strip(st, VehicleShapes.arc_points(ar, r + 0.035, -10.0, 75.0, 14), Vector3(1.0, 0.0, 0.0), 0.1, 0.006, cr(), 10)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.36, 0.8), Vector3(0.11, 0.06, 0.008), 0.25, mt(Color("#F2EEE4")), Basis(Vector3.RIGHT, -0.25), 8, 3)


## 풀 카울 스포츠: 옆 카울(배터리를 감싸고 공기 구멍) · 탱크 덮개 · 솟은 꼬리 · 조각 시트 · 알루미늄 스윙암 · 벨트 · 발판.
static func _sport_body(st: SurfaceTool, paint: Color, trim: Color, seat_c: Color, seat_shape: String, p: Dictionary, seg: int) -> void:
	var ar: Vector3 = p["axle_r"]
	var ht: Vector3 = p["head_top"]
	var fl: Vector3 = p["floor"]
	var pc: Color = gl(paint)
	var accent: Color = gl(trim)
	# 옆 카울 (배터리 덩어리를 감싼 매끈한 덩어리, 앞쪽이 높다).
	var side_body: Array[PackedVector3Array] = []
	var spec: Array = [[-0.44, 0.06, 0.5, 0.08, 0.09], [-0.36, 0.13, 0.44, 0.12, 0.17], [-0.24, 0.15, 0.4, 0.15, 0.2], [-0.1, 0.15, 0.38, 0.14, 0.18], [0.02, 0.13, 0.37, 0.12, 0.14], [0.1, 0.08, 0.38, 0.09, 0.08]]
	for row: Array in spec:
		side_body.append(VehicleShapes.section(0.0, float(row[2]), float(row[0]), float(row[1]), float(row[3]), float(row[4]), 40, 0.45))
	var body_color: Callable = func(q: Vector3, _n: Vector3) -> Color:
		# 아래는 검은 배터리 덮개, 옆 가운데 비스듬한 색 띠.
		if q.y < 0.27:
			return mt(Color("#24262A"))
		if absf(q.x) > 0.12 and absf((q.y - 0.42) + (q.z + 0.2) * 0.45) < 0.018:
			return accent
		return pc
	VehicleShapes.loft(st, side_body, body_color, true, true)
	# 공기 구멍 (검은 비스듬한 틈 셋).
	for side: float in [-1.0, 1.0]:
		for k: int in 3:
			var z: float = -0.3 + float(k) * 0.06
			VehicleShapes.sweep(st, PackedVector3Array([Vector3(side * 0.148, 0.36 - float(k) * 0.01, z), Vector3(side * 0.152, 0.3 - float(k) * 0.01, z + 0.05)]), 0.0065, mt(Color("#141518")), 6, true, 1.0)
	# 탱크 덮개 (무릎 사이).
	var tank: Array[PackedVector3Array] = []
	for i: int in 9:
		var t: float = float(i) / 8.0
		tank.append(VehicleShapes.section(0.0, lerpf(0.58, 0.5, t), lerpf(-0.36, 0.06, t), lerpf(0.1, 0.075, t), lerpf(0.06, 0.035, t), 0.06, 32, 0.4))
	VehicleShapes.loft(st, tank, pc, true, true)
	# 꼬리: 시트 뒤로 솟으며 뾰족해진다 (아래는 검은 언더 트레이).
	var tail: Array[PackedVector3Array] = []
	for i2: int in 9:
		var t2: float = float(i2) / 8.0
		var z2: float = lerpf(0.18, 0.8, t2)
		var y2: float = lerpf(0.46, 0.6, pow(t2, 1.3))
		tail.append(VehicleShapes.section(0.0, y2, z2, lerpf(0.11, 0.03, pow(t2, 1.2)), lerpf(0.05, 0.012, t2), lerpf(0.06, 0.012, t2), 32, 0.5))
	VehicleShapes.loft(st, tail, pc, true, true)
	VehicleShapes.strip(st, VehicleShapes.spline(PackedVector3Array([Vector3(0.0, 0.42, 0.42), Vector3(0.0, 0.46, 0.62), Vector3(0.0, 0.43, 0.82)]), 6), Vector3(1.0, 0.0, 0.0), 0.11, 0.012, mt(Color("#24262A")), 10)
	var seat_at: Vector3 = p["seat"]
	_seat_loft(st, seat_at + Vector3(0.0, -0.02, 0.04), 0.11, 0.3, 0.045, seat_c, "sport" if seat_shape == "" else seat_shape, trim)
	# 알루미늄 스윙암 (오른쪽) · 벨트 · 뒤 풀리.
	VehicleShapes.sweep(st, PackedVector3Array([Vector3(0.07, 0.28, 0.05), ar + Vector3(0.075, 0.0, 0.0)]), 0.024, cr(ALLOY), 12, true, 0.55, Vector3(1.0, 0.0, 0.0))
	VehicleShapes.sweep(st, PackedVector3Array([Vector3(-0.07, 0.28, 0.05), ar + Vector3(-0.075, 0.0, 0.0)]), 0.022, cr(ALLOY), 12, true, 0.55, Vector3(1.0, 0.0, 0.0))
	var belt: PackedVector3Array = PackedVector3Array()
	var c0: Vector3 = Vector3(0.1, 0.27, 0.06)
	var c1: Vector3 = ar + Vector3(0.1, 0.0, 0.0)
	for i3: int in 9:
		var a: float = deg_to_rad(lerpf(90.0, 270.0, float(i3) / 8.0))
		belt.append(c0 + Vector3(0.0, sin(a) * 0.035, cos(a) * 0.035))
	for i4: int in 13:
		var a2: float = deg_to_rad(lerpf(-90.0, 90.0, float(i4) / 12.0))
		belt.append(c1 + Vector3(0.0, sin(a2) * 0.09, cos(a2) * 0.09))
	belt.append(belt[0])
	VehicleShapes.sweep(st, belt, 0.006, mt(Color("#2A2B2E")), 6, false, 2.4, Vector3(1.0, 0.0, 0.0))
	# 발판 (뒤로 높게 — 스포츠 자세) · 뒤 브레이크 레버.
	for side2: float in [-1.0, 1.0]:
		ClayMesh.add_rounded_box(st, Vector3(side2 * 0.1, fl.y + 0.08, fl.z + 0.08), Vector3(0.04, 0.05, 0.08), 0.3, cr(ALLOY), Basis(), 8, 3)
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(side2 * 0.11, fl.y + 0.07, fl.z + 0.06), Vector3(side2 * 0.17, fl.y + 0.07, fl.z + 0.07)]), 0.01, mt(Color("#2A2A2E")), 8, true)
	# 번호판 받이 (뒤 바퀴 위 긴 팔).
	VehicleShapes.sweep(st, PackedVector3Array([Vector3(0.0, 0.43, 0.66), Vector3(0.0, 0.36, 0.85)]), 0.012, mt(BLACK), 8, true, 2.5, Vector3(1.0, 0.0, 0.0))
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.33, 0.87), Vector3(0.1, 0.055, 0.008), 0.25, mt(Color("#F2EEE4")), Basis(Vector3.RIGHT, -0.2), 8, 3)
	# 앞 카울 (몸체에 붙어 돌지 않는다): 두 눈 전조등 자리 · 바람막이.
	var nose: Array[PackedVector3Array] = []
	for i5: int in 9:
		var t5: float = float(i5) / 8.0
		var z5: float = lerpf(-0.64, -0.36, t5)
		var hw5: float = lerpf(0.05, 0.16, pow(t5, 0.6))
		nose.append(VehicleShapes.section(0.0, lerpf(0.6, 0.58, t5), z5, hw5, lerpf(0.05, 0.13, pow(t5, 0.7)), lerpf(0.06, 0.17, pow(t5, 0.7)), 36, 0.45))
	VehicleShapes.loft(st, nose, pc, true, false)
	var screen: Array[PackedVector3Array] = []
	for i6: int in 6:
		var t6: float = float(i6) / 5.0
		screen.append(_crescent(lerpf(0.68, 0.82, t6), lerpf(-0.47, -0.34, t6), lerpf(0.12, 0.08, t6), 0.04, 0.006, 22))
	VehicleShapes.loft(st, screen, VehicleShapes.glass(Color("#56707F")), true, true)
	# 두 눈 (유리 렌즈 둘 — 불빛은 VehicleModel 이 단다) · 카울 거울.
	for side3: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(side3 * 0.055, 0.6, -0.615), Vector3(0.042, 0.02, 0.025), VehicleShapes.glass(Color("#C8D4DC")), 14, 6, Basis(Vector3.BACK, side3 * 0.25))
		VehicleShapes.sweep(st, PackedVector3Array([Vector3(side3 * 0.15, 0.66, -0.38), Vector3(side3 * 0.2, 0.71, -0.4)]), 0.006, mt(BLACK), 6, true)
		ClayMesh.add_ellipsoid(st, Vector3(side3 * 0.215, 0.72, -0.4), Vector3(0.035, 0.022, 0.014), gl(BLACK), 12, 5)


## 시트: 앞이 좁고 뒤가 넓은 쿠션 (테두리 파이핑, quilt = 가로 주름, sport = 가운데 색 띠).
static func _seat_loft(st: SurfaceTool, at: Vector3, half_w: float, length: float, thick: float, color: Color, shape: String, trim: Color) -> void:
	var rings: Array[PackedVector3Array] = []
	for i: int in 11:
		var t: float = float(i) / 10.0
		var z: float = at.z - length * 0.5 + t * length
		var w: float = half_w * lerpf(0.72, 1.0, smoothstep(0.0, 0.6, t)) * (1.0 - 0.15 * smoothstep(0.85, 1.0, t))
		var top: float = thick * (0.75 + 0.25 * sin(t * PI))
		rings.append(VehicleShapes.section(0.0, at.y, z, w, top, thick * 0.5, 30, 0.6))
	var seat_color: Variant = VehicleShapes.matte(color)
	if shape == "quilt":
		seat_color = func(q: Vector3, _n: Vector3) -> Color:
			var band: float = fposmod((q.z - at.z) * 22.0, 1.0)
			return VehicleShapes.matte(color.darkened(0.22) if band < 0.12 and q.y > at.y + thick * 0.4 else color)
	elif shape == "sport":
		seat_color = func(q: Vector3, _n: Vector3) -> Color:
			return VehicleShapes.matte(trim if absf(q.x) < half_w * 0.18 and q.y > at.y + thick * 0.4 else color)
	VehicleShapes.loft(st, rings, seat_color, true, true)
	# 파이핑 (시트 테두리).
	var edge: PackedVector3Array = PackedVector3Array()
	for i2: int in 25:
		var a: float = TAU * float(i2) / 24.0
		edge.append(Vector3(cos(a) * half_w * 0.98, at.y - thick * 0.05, at.z + sin(a) * length * 0.49))
	VehicleShapes.sweep(st, edge, 0.0045, VehicleShapes.matte(color.darkened(0.3)), 5, false)


## 앞이 볼록한 초승달 단면 (XZ 평면, 높이 y) — 다리 가림판 · 바람막이를 위로 쌓는다. bulge = 앞으로 나온 정도, thick = 두께.
static func _crescent(y: float, cz: float, half_w: float, bulge: float, thick: float, n: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var half: int = n / 2
	for i: int in half:
		var t: float = float(i) / float(half - 1)
		var x: float = lerpf(-half_w, half_w, t)
		var k: float = 1.0 - pow(x / half_w, 2.0)
		out.append(Vector3(x, y, cz - bulge * k - thick))
	for i2: int in half:
		var t2: float = float(i2) / float(half - 1)
		var x2: float = lerpf(half_w, -half_w, t2)
		var k2: float = 1.0 - pow(x2 / half_w, 2.0)
		out.append(Vector3(x2 * 0.97, y, cz - bulge * k2 * 0.85))
	return out


# ---- 조향 (원점 = 헤드 위, 조향 좌표) ----

## 포크 · 핸들 · 그립 · 레버 · 거울 · 앞 흙받이 · 등 껍데기 (스쿠터는 핸들 덮개, 클래식은 둥근 크롬 등, 스포츠는 카울에 등이 있다).
## q: { axle_f, bar, head } (조향 좌표).
static func steer(st: SurfaceTool, style: String, paint: Color, trim: Color, q: Dictionary, r: float, lens_r: float, seg: int) -> void:
	var af: Vector3 = q["axle_f"]
	var bar: Vector3 = q["bar"]
	var head: Vector3 = q["head"]
	var down: Vector3 = af.normalized()
	var crown: Vector3 = down * 0.1
	var pc: Color = gl(paint)
	match style:
		"scooter":
			# 한쪽 링크 포크 (왼쪽) · 앞 흙받이(조개껍데기) · 핸들 덮개(둥근 등 박힘).
			VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([Vector3(0.0, 0.0, 0.0), crown + Vector3(0.0, 0.0, 0.0), af + Vector3(-0.07, 0.08, 0.03), af + Vector3(-0.07, 0.0, 0.0)]), 6), PackedFloat32Array(_ramp(19, 0.024, 0.02)), mt(DARK_METAL), 12, true)
			VehicleShapes.sweep(st, PackedVector3Array([af + Vector3(-0.07, 0.05, 0.05), af + Vector3(-0.07, 0.13, 0.06)]), 0.014, mt(BLACK), 10, true)
			var fender: Array[PackedVector3Array] = []
			for i: int in 13:
				var a: float = deg_to_rad(lerpf(40.0, 170.0, float(i) / 12.0))
				var c: Vector3 = af + Vector3(0.0, sin(a) * (r + 0.03), cos(a) * (r + 0.03))
				var hw: float = 0.07 + 0.025 * sin(float(i) / 12.0 * PI)
				fender.append(VehicleShapes.section(0.0, c.y, c.z, hw, 0.02, 0.02, 24, 0.3))
			VehicleShapes.loft(st, fender, pc, true, true)
			# 핸들 덮개: 아래로 갈수록 앞으로 나와 둥근 등을 품는다 (베스파 프리마베라).
			var cover: Array[PackedVector3Array] = []
			var spec: Array = [[-0.16, -0.08, 0.05, 0.05], [-0.13, -0.095, 0.085, 0.075], [-0.09, -0.09, 0.12, 0.085], [-0.04, -0.07, 0.15, 0.09], [0.0, -0.05, 0.165, 0.085], [0.04, -0.045, 0.16, 0.075], [0.075, -0.045, 0.12, 0.055], [0.095, -0.045, 0.06, 0.03]]
			for row: Array in spec:
				cover.append(VehicleShapes.ring_xz(0.0, bar.y + float(row[0]), bar.z + float(row[1]), float(row[2]), float(row[3]), 32, 0.55))
			VehicleShapes.loft(st, cover, pc, true, true)
			# 계기판 (위 둥근 창).
			ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.008), Vector2(0.0, 0.01)]), 24, Transform3D(Basis(Vector3.RIGHT, -0.35), bar + Vector3(0.0, 0.085, -0.03)), VehicleShapes.glass(Color("#3A4A56")))
			# 둥근 전조등 테 (핸들 덮개 앞).
			ClayMesh.add_torus(st, head + Vector3(0.0, 0.0, -0.03), lens_r + 0.008, 0.008, cr(), 28, 6, Basis(Vector3.RIGHT, PI * 0.5))
		"classic":
			# 크롬 텔레스코픽 포크 (주름 고무) · 트리플 클램프 · 둥근 크롬 전조등 · 짧은 크롬 흙받이.
			ClayMesh.add_rounded_box(st, crown, Vector3(0.17, 0.025, 0.06), 0.4, cr(ALLOY), ClayMesh._basis_along(-down), 10, 3)
			ClayMesh.add_rounded_box(st, Vector3(0.0, -0.005, 0.0), Vector3(0.16, 0.02, 0.055), 0.4, cr(ALLOY), ClayMesh._basis_along(-down), 10, 3)
			for side: float in [-1.0, 1.0]:
				var top_p: Vector3 = Vector3(side * 0.065, 0.02, 0.0)
				var low_p: Vector3 = af + Vector3(side * 0.07, 0.0, 0.0)
				VehicleShapes.sweep(st, PackedVector3Array([top_p, top_p.lerp(low_p, 0.55)]), 0.017, cr(), 14, true)
				var gaiter: PackedVector3Array = PackedVector3Array()
				var gr: PackedFloat32Array = PackedFloat32Array()
				for k: int in 15:
					var t2: float = float(k) / 14.0
					gaiter.append(top_p.lerp(low_p, lerpf(0.3, 0.58, t2)))
					gr.append(0.022 + 0.004 * (1.0 if k % 2 == 0 else -1.0))
				VehicleShapes.sweep(st, gaiter, gr, mt(Color("#1A1A1C")), 14, true)
				VehicleShapes.sweep(st, PackedVector3Array([top_p.lerp(low_p, 0.58), low_p]), PackedFloat32Array([0.022, 0.02]), cr(ALLOY), 14, true)
			VehicleShapes.strip(st, VehicleShapes.arc_points(af, r + 0.03, 35.0, 150.0, 14), Vector3(1.0, 0.0, 0.0), 0.085, 0.006, cr(), 10)
			for side2: float in [-1.0, 1.0]:
				VehicleShapes.sweep(st, PackedVector3Array([af + Vector3(side2 * 0.07, 0.0, 0.0), VehicleShapes.arc_points(af, r + 0.03, 100.0, 100.0, 1)[0] + Vector3(side2 * 0.045, 0.0, 0.0)]), 0.004, cr(), 5, true)
			# 둥근 크롬 전조등 (깊은 사발 · 앞 테) + 받침 귀.
			ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.085), Vector2(lens_r * 0.5, 0.08), Vector2(lens_r + 0.015, 0.04), Vector2(lens_r + 0.018, 0.0), Vector2(lens_r + 0.006, -0.006)]), 28, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), head + Vector3(0.0, 0.0, -0.025)), cr())
			for side3: float in [-1.0, 1.0]:
				VehicleShapes.sweep(st, PackedVector3Array([head + Vector3(side3 * (lens_r + 0.02), 0.0, 0.03), Vector3(side3 * 0.065, head.y + 0.02, head.z + 0.1)]), 0.006, cr(), 6, true)
			# 계기판 (둥근 속도계).
			ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.037, 0.03), Vector2(0.03, 0.034), Vector2(0.0, 0.033)]), 22, Transform3D(Basis(Vector3.RIGHT, -0.4), bar + Vector3(0.0, 0.01, -0.06)), cr())
			ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.0, 0.002)]), 22, Transform3D(Basis(Vector3.RIGHT, -0.4), bar + Vector3(0.0, 0.043, -0.072)), VehicleShapes.glass(Color("#1E2A30")))
		_:
			# 도립 포크 (금색 아우터 위 · 검은 이너 아래) · 레이디얼 캘리퍼 · 앞 흙받이(짧은 카본).
			ClayMesh.add_rounded_box(st, crown, Vector3(0.18, 0.026, 0.06), 0.4, cr(ALLOY), ClayMesh._basis_along(-down), 10, 3)
			for side4: float in [-1.0, 1.0]:
				var top4: Vector3 = Vector3(side4 * 0.07, 0.02, 0.0)
				var low4: Vector3 = af + Vector3(side4 * 0.075, 0.0, 0.0)
				VehicleShapes.sweep(st, PackedVector3Array([top4, top4.lerp(low4, 0.62)]), 0.025, cr(GOLD), 14, true)
				VehicleShapes.sweep(st, PackedVector3Array([top4.lerp(low4, 0.6), low4]), PackedFloat32Array([0.017, 0.016]), cr(Color("#3A3D44")), 14, true)
				ClayMesh.add_rounded_box(st, low4 + Vector3(0.0, 0.06, 0.05), Vector3(0.024, 0.075, 0.04), 0.35, gl(Color("#D23A2E")), Basis(Vector3.RIGHT, -0.3), 10, 4)
			VehicleShapes.strip(st, VehicleShapes.arc_points(af, r + 0.028, 50.0, 140.0, 12), Vector3(1.0, 0.0, 0.0), 0.11, 0.008, gl(Color("#1A1B1E")), 10)
	# 핸들: 스쿠터 = 덮개 속 짧은 바, 클래식 = 크롬 둥근 바, 스포츠 = 클립온.
	var bar_c: Color = cr() if style == "classic" else mt(BLACK)
	for side5: float in [-1.0, 1.0]:
		var path: PackedVector3Array
		match style:
			"scooter":
				path = PackedVector3Array([bar + Vector3(side5 * 0.12, 0.0, 0.0), bar + Vector3(side5 * 0.24, 0.0, 0.01)])
			"classic":
				path = VehicleShapes.spline(PackedVector3Array([bar, bar + Vector3(side5 * 0.1, 0.02, 0.0), bar + Vector3(side5 * 0.2, 0.02, 0.02), bar + Vector3(side5 * 0.25, 0.01, 0.04)]), 6)
			_:
				path = PackedVector3Array([bar + Vector3(side5 * 0.08, -0.04, -0.02), bar + Vector3(side5 * 0.24, -0.02, 0.02)])
		VehicleShapes.sweep(st, path, 0.012, bar_c, 10, true)
		var end: Vector3 = path[path.size() - 1]
		var dir: Vector3 = (path[path.size() - 1] - path[path.size() - 2]).normalized()
		VehicleShapes.sweep(st, PackedVector3Array([end - dir * 0.02, end + dir * 0.1]), 0.019, mt(Color("#1C1C1F")), 14, true)
		ClayMesh.add_rounded_box(st, end + dir * 0.103, Vector3(0.008, 0.028, 0.028), 0.5, cr(ALLOY), ClayMesh._basis_along(dir), 8, 3)
		# 브레이크 레버 · 스위치 뭉치.
		ClayMesh.add_rounded_box(st, end - dir * 0.025, Vector3(0.035, 0.03, 0.036), 0.4, mt(Color("#2A2B2F")), Basis(), 8, 3)
		VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([end - dir * 0.02 + Vector3(0.0, 0.0, -0.025), end + dir * 0.03 + Vector3(0.0, -0.004, -0.04), end + dir * 0.09 + Vector3(0.0, -0.008, -0.035)]), 5), 0.005, cr(ALLOY), 6, true, 1.6, Vector3(0.0, 1.0, 0.0))
		if style != "sport":
			# 거울 (둥근 거울 + 대).
			var stalk_top: Vector3 = end - dir * 0.04 + Vector3(0.0, 0.1, 0.02)
			VehicleShapes.sweep(st, VehicleShapes.spline(PackedVector3Array([end - dir * 0.04, end - dir * 0.02 + Vector3(0.0, 0.08, 0.0), stalk_top]), 5), 0.005, cr(), 6, true)
			ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, -0.012), Vector2(0.04, -0.012), Vector2(0.042, 0.0), Vector2(0.036, 0.006), Vector2(0.0, 0.006)]), 22, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), stalk_top + Vector3(0.0, 0.0, 0.01)), cr())


static func _ramp(n: int, a: float, b: float) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(lerpf(a, b, float(i) / float(maxi(n - 1, 1))))
	return out
