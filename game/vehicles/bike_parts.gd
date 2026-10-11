extends RefCounted
## 자전거 부품을 실제 모양대로 빚는다 (v21, vehicle_model 이 preload 로 부른다). 좌표는 탈것 좌표 (바닥 y = 0, 앞 = -z, 오른쪽 +x = 체인 쪽).
## 생활 자전거(스텝스루 마마차리) · 미니벨로(접이식) · 하드테일 MTB(서스펜션 포크 · 디스크) · 에어로 로드(드롭 바 · 딥 림)를 본떴다.
## 굴러가는 부품(바퀴 · 크랭크)은 각자 원점 기준으로 빚어 VehicleModel 이 마디에 단다.
const Shapes := preload("res://game/vehicles/vehicle_shapes.gd")

const RUBBER: Color = Color("#1F1F22")
const GUMWALL: Color = Color("#B58A5A")
const STEEL: Color = Color("#C9CDD3")
const BLACK: Color = Color("#202024")
const CARBON: Color = Color("#17181B")
const LEATHER: Color = Color("#6B4A33")


static func gl(c: Color) -> Color:
	return Shapes.gloss(c)


static func mt(c: Color) -> Color:
	return Shapes.matte(c)


static func cr(c: Color = STEEL) -> Color:
	return Shapes.chrome(c)


# ---- 바퀴 (축 = X, 원점 = 허브) ----

## 타이어 폭 (m).
static func tire_width(style: String, tire: Dictionary) -> float:
	var w: float = {"city": 0.042, "mini": 0.04, "mtb": 0.058, "road": 0.024}.get(style, 0.04)
	return w * float(tire.get("w", 1.0))


## 바퀴 하나: 타이어(옆면 · 트레드) · 림 · 허브 · 바퀴살 (· 디스크 원판 · 스프로킷).
static func wheel(st: SurfaceTool, r: float, style: String, tire: Dictionary, trim: Color, rear: bool, disc: bool, seg: int) -> void:
	var w: float = tire_width(style, tire)
	var wall_c: Color = Color.html(str(tire.get("c", "#2A2A2E")))
	var custom_wall: bool = tire.has("c") and wall_c != Color("#2A2A2E")
	var wall: Color = wall_c if custom_wall else (GUMWALL if style == "city" else RUBBER)
	# 타이어 단면: 림에서 나와 둥글게 부풀었다가 반대쪽 림으로.
	var rc: float = r - w * 0.5
	var prof: PackedVector2Array = PackedVector2Array()
	for i: int in 15:
		var phi: float = deg_to_rad(lerpf(-112.0, 112.0, float(i) / 14.0))
		prof.append(Vector2(rc + cos(phi) * w * 0.5, sin(phi) * w * 0.5))
	var tire_color: Callable = func(p: Vector3, _n: Vector3) -> Color:
		var rho: float = Vector2(p.y, p.z).length()
		if absf(p.x) > w * 0.3 and rho < r - w * 0.28:
			return mt(wall)
		return mt(RUBBER)
	Shapes.lathe_x(st, Vector3.ZERO, prof, maxi(seg * 3, 48), tire_color)
	# 트레드: MTB 는 두 줄 + 가운데 줄 블록, 시티는 가는 홈, 로드는 매끈.
	if style == "mtb" or bool(tire.get("tread", false)):
		var knobs: int = 44
		for i: int in knobs:
			var a: float = TAU * float(i) / float(knobs)
			var basis: Basis = Basis(Vector3.RIGHT, -a)
			for side: float in [-1.0, 1.0]:
				var x: float = side * w * (0.3 if i % 2 == 0 else 0.38)
				var at: Vector3 = Vector3(x, cos(a) * (r - 0.002), sin(a) * (r - 0.002))
				ClayMesh.add_rounded_box(st, at, Vector3(0.011, 0.007, 0.01), 0.4, mt(RUBBER), basis, 6, 2)
			if i % 2 == 1:
				ClayMesh.add_rounded_box(st, Vector3(0.0, cos(a) * (r + 0.001), sin(a) * (r + 0.001)), Vector3(0.012, 0.006, 0.009), 0.4, mt(RUBBER), basis, 6, 2)
	# 림: U 자 단면 (로드는 깊은 카본 림 + 흰 글씨 띠).
	var depth: float = {"road": 0.036, "mtb": 0.02, "mini": 0.016}.get(style, 0.014)
	var rw: float = w * (0.6 if style != "road" else 0.95)
	var r_out: float = r - w * 0.92
	var r_in: float = r_out - depth
	var rim_prof: PackedVector2Array = PackedVector2Array([
		Vector2(r_in, -rw * 0.3), Vector2(r_out - 0.004, -rw * 0.5), Vector2(r_out + 0.003, -rw * 0.5),
		Vector2(r_out + 0.003, rw * 0.5), Vector2(r_out - 0.004, rw * 0.5), Vector2(r_in, rw * 0.3),
	])
	var rim_color: Variant
	match style:
		"city":
			rim_color = cr()
		"road":
			rim_color = func(p: Vector3, _n: Vector3) -> Color:
				var rho2: float = Vector2(p.y, p.z).length()
				if absf(p.x) > rw * 0.32 and rho2 < r_out - depth * 0.35 and rho2 > r_out - depth * 0.7:
					return gl(Color("#F2F2EE"))
				return gl(CARBON)
		"mtb":
			rim_color = mt(BLACK)
		_:
			rim_color = gl(trim)
	Shapes.lathe_x(st, Vector3.ZERO, rim_prof, maxi(seg * 3, 48), rim_color, true)
	# 허브: 가운데 통 · 양쪽 플랜지 · 축 끝.
	var hub_w: float = 0.034 if rear else 0.028
	var hub_prof: PackedVector2Array = PackedVector2Array([
		Vector2(0.006, -hub_w - 0.016), Vector2(0.008, -hub_w - 0.012), Vector2(0.008, -hub_w - 0.002),
		Vector2(0.022, -hub_w), Vector2(0.022, -hub_w + 0.004), Vector2(0.013, -hub_w + 0.008),
		Vector2(0.013 if style != "city" else 0.026, 0.0),
		Vector2(0.013, hub_w - 0.008), Vector2(0.022, hub_w - 0.004), Vector2(0.022, hub_w),
		Vector2(0.008, hub_w + 0.002), Vector2(0.008, hub_w + 0.012), Vector2(0.006, hub_w + 0.016),
	])
	Shapes.lathe_x(st, Vector3.ZERO, hub_prof, 18, cr(Color("#B9BEC6")) if style != "mtb" else mt(BLACK))
	# 바퀴살: 양쪽 플랜지에서 엇갈려 림으로 (3 크로스). 로드 딥 림은 방사형 20 개.
	var count: int = {"city": 36, "mini": 28, "mtb": 32, "road": 20}.get(style, 32)
	var spoke_c: Color = gl(Color("#D4D7DC")) if style != "road" and style != "mtb" else gl(Color("#2A2B2F"))
	for i: int in count:
		var side2: float = 1.0 if i % 2 == 0 else -1.0
		var ah: float = TAU * float(i) / float(count)
		var cross: float = 0.0 if style == "road" else (TAU / float(count)) * 6.0 * (1.0 if (i / 2) % 2 == 0 else -1.0)
		var ar: float = ah + cross
		var hub_p: Vector3 = Vector3(side2 * (hub_w - 0.002), cos(ah) * 0.02, sin(ah) * 0.02)
		var rim_p: Vector3 = Vector3(side2 * 0.003, cos(ar) * (r_in + 0.002), sin(ar) * (r_in + 0.002))
		Shapes.rod(st, hub_p, rim_p, 0.0016 if style != "road" else 0.0024, spoke_c, 4)
	# 바람 넣는 꼭지.
	Shapes.rod(st, Vector3(0.0, 0.0, r_in + 0.002), Vector3(0.0, 0.0, r_in - 0.022), 0.003, cr(), 6)
	if disc:
		# 디스크 원판 (왼쪽): 고리 + 다섯 팔.
		var dx: float = -hub_w - 0.006
		Shapes.lathe_x(st, Vector3(dx, 0.0, 0.0), PackedVector2Array([Vector2(0.05, -0.0012), Vector2(0.068, -0.0012), Vector2(0.068, 0.0012), Vector2(0.05, 0.0012)]), 40, cr(Color("#C2C6CC")), true)
		for k: int in 5:
			var a2: float = TAU * float(k) / 5.0
			Shapes.rod(st, Vector3(dx, cos(a2) * 0.014, sin(a2) * 0.014), Vector3(dx, cos(a2 + 0.35) * 0.052, sin(a2 + 0.35) * 0.052), 0.004, cr(Color("#C2C6CC")), 5)
	if rear and style != "city":
		# 스프로킷 (오른쪽, 큰 것부터 작은 것까지 겹친 톱니 원판).
		var cogs: int = 9 if style == "road" else 10
		for k2: int in cogs:
			var t: float = float(k2) / float(cogs - 1)
			var cog_r: float = lerpf(0.048 if style == "mtb" else 0.034, 0.014, t)
			var cx: float = hub_w - 0.006 + t * 0.018
			Shapes.lathe_x(st, Vector3(cx, 0.0, 0.0), PackedVector2Array([Vector2(0.01, -0.0009), Vector2(cog_r, -0.0009), Vector2(cog_r, 0.0009), Vector2(0.01, 0.0009)]), 28, cr(Color("#A9AEB5")), true)


# ---- 크랭크 (원점 = 크랭크 축, X 축으로 돈다) ----

## 앞 체인링(톱니) · 스파이더 · 크랭크 팔 둘. 왼쪽(-x) 팔이 위(+y), 오른쪽 팔이 아래 (페달 자리와 같다).
static func crank(st: SurfaceTool, style: String, crank_r: float) -> void:
	var rings: Array = [0.07] if style != "road" else [0.072, 0.054]
	var ring_c: Color = cr(Color("#B7BBC2")) if style != "mtb" else mt(BLACK)
	for k: int in rings.size():
		var rr: float = float(rings[k])
		var x: float = 0.05 - float(k) * 0.007
		Shapes.lathe_x(st, Vector3(x, 0.0, 0.0), PackedVector2Array([Vector2(rr - 0.012, -0.0015), Vector2(rr - 0.002, -0.0015), Vector2(rr - 0.002, 0.0015), Vector2(rr - 0.012, 0.0015)]), 48, ring_c, true)
		var teeth: int = int(rr * 560.0)
		for i: int in teeth:
			var a: float = TAU * float(i) / float(teeth)
			ClayMesh.add_rounded_box(st, Vector3(x, cos(a) * rr, sin(a) * rr), Vector3(0.0028, 0.006, 0.0042), 0.5, ring_c, Basis(Vector3.RIGHT, -a), 4, 2)
	# 스파이더 (다섯 팔).
	for i2: int in 5:
		var a2: float = TAU * float(i2) / 5.0 + 0.2
		Shapes.sweep(st, PackedVector3Array([Vector3(0.056, 0.0, 0.0), Vector3(0.052, cos(a2) * 0.045, sin(a2) * 0.045), Vector3(0.05, cos(a2) * 0.06, sin(a2) * 0.06)]), PackedFloat32Array([0.008, 0.006, 0.005]), ring_c, 6, true, 1.0)
	# 크랭크 팔 (끝이 가늘어지는 납작한 팔).
	var arm_c: Color = cr(Color("#C4C8CE")) if style == "city" or style == "mini" else gl(BLACK)
	for side: float in [-1.0, 1.0]:
		var x2: float = side * 0.068
		# 왼팔이 위(위상 0 에 왼발 페달이 맨 위), 오른팔이 아래.
		Shapes.sweep(st, PackedVector3Array([Vector3(x2 - side * 0.01, 0.0, 0.0), Vector3(x2, -side * crank_r * 0.5, 0.0), Vector3(x2 + side * 0.004, -side * crank_r, 0.0)]), PackedFloat32Array([0.013, 0.01, 0.008]), arm_c, 10, true, 0.55, Vector3(1.0, 0.0, 0.0))
	# 축 · 볼트.
	Shapes.lathe_x(st, Vector3(-0.07, 0.0, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.012, 0.14), Vector2(0.0, 0.14)]), 14, mt(Color("#5A5E66")))


## 페달 (원점 = 페달 축): 테가 둘린 평평한 발판 + 미끄럼 방지 핀.
static func pedal(st: SurfaceTool, side: float, style: String) -> void:
	Shapes.lathe_x(st, Vector3(-side * 0.012, 0.0, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.006, 0.0), Vector2(0.006, 0.012), Vector2(0.0, 0.012)]), 10, cr())
	var body: Color = mt(BLACK) if style != "city" else mt(Color("#3A3A3E"))
	ClayMesh.add_rounded_box(st, Vector3(side * 0.03, 0.0, 0.0), Vector3(0.06, 0.012, 0.055), 0.25, body, Basis(), 10, 3)
	if style == "city":
		# 반사경.
		for z: float in [-0.029, 0.029]:
			ClayMesh.add_rounded_box(st, Vector3(side * 0.03, 0.0, z), Vector3(0.04, 0.008, 0.004), 0.3, gl(Color("#F2A030")), Basis(), 6, 2)
	else:
		for i: int in 4:
			ClayMesh.add_rounded_box(st, Vector3(side * (0.012 + float(i % 2) * 0.036), 0.007, -0.02 + float(i / 2) * 0.04), Vector3(0.003, 0.004, 0.003), 0.4, cr(), Basis(), 4, 2)


# ---- 몸체 (프레임 · 체인 · 흙받이 · 짐받이 · 받침대) ----

## p: { head_top, head_bottom, bb, seat_top, seat, axle_r, axle_f, r, rear } — 탈것 좌표.
static func frame(st: SurfaceTool, style: String, paint: Color, trim: Color, p: Dictionary, has_rear_part: bool, seg: int) -> void:
	var ht: Vector3 = p["head_top"]
	var hb: Vector3 = p["head_bottom"]
	var bb: Vector3 = p["bb"]
	var stp: Vector3 = p["seat_top"]
	var seat: Vector3 = p["seat"]
	var ar: Vector3 = p["axle_r"]
	var r: float = float(p["r"])
	var paint_c: Variant = gl(paint)
	if style == "road":
		# 다운 튜브에 흰 글씨 띠.
		paint_c = func(q: Vector3, _n: Vector3) -> Color:
			if q.z < -0.16 and q.z > -0.34 and q.y < 0.56 and q.y > 0.36 and absf(q.x) > 0.008:
				return gl(Color("#F7F5F0"))
			return gl(paint)
	var head_dir: Vector3 = (ht - hb).normalized()
	# 헤드 튜브 (위아래 헤드셋 컵).
	Shapes.sweep(st, PackedVector3Array([hb - head_dir * 0.012, ht + head_dir * 0.004]), PackedFloat32Array([0.026 if style == "mtb" else 0.022, 0.022 if style == "mtb" else 0.02]), paint_c, seg + 6, true)
	Shapes.sweep(st, PackedVector3Array([ht, ht + head_dir * 0.014]), 0.019, mt(BLACK), seg + 4, true)
	Shapes.sweep(st, PackedVector3Array([hb - head_dir * 0.024, hb - head_dir * 0.01]), 0.024, mt(BLACK), seg + 4, true)
	var seat_cluster: Vector3 = stp
	match style:
		"city":
			# 스텝스루: 머리 관 아래에서 낮게 휘어 크랭크로 가는 굵은 관 + 위쪽 가는 보조 관.
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([hb + head_dir * 0.02, Vector3(0.0, 0.47, -0.39), Vector3(0.0, 0.31, -0.21), Vector3(0.0, 0.265, -0.06), bb + Vector3(0.0, -0.005, 0.0)]), 8), 0.021, paint_c, seg + 6, true)
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([ht - head_dir * 0.05, Vector3(0.0, 0.55, -0.33), Vector3(0.0, 0.43, -0.16), Vector3(0.0, 0.39, -0.02), stp + Vector3(0.0, -0.03, -0.012)]), 8), 0.014, paint_c, seg + 4, true)
		"mini":
			# 미니벨로: 굵은 외통 관 (가운데 접이 경첩).
			var beam: PackedVector3Array = Shapes.spline(PackedVector3Array([hb + head_dir * 0.07, Vector3(0.0, 0.5, -0.3), Vector3(0.0, 0.42, -0.12), stp + Vector3(0.0, -0.06, -0.02)]), 8)
			Shapes.sweep(st, beam, 0.03, paint_c, seg + 8, true)
			var hinge: Vector3 = beam[beam.size() / 2]
			ClayMesh.add_torus(st, hinge, 0.033, 0.008, mt(BLACK), seg + 8, 5, ClayMesh._basis_along(beam[beam.size() / 2 + 1] - beam[beam.size() / 2 - 1]))
			Shapes.sweep(st, PackedVector3Array([hinge + Vector3(0.034, 0.0, 0.0), hinge + Vector3(0.045, -0.01, 0.05)]), 0.006, cr(), 6, true)
			Shapes.sweep(st, PackedVector3Array([hb + head_dir * 0.01, bb + Vector3(0.0, 0.01, -0.03)]), 0.016, paint_c, seg + 4, true)
		"mtb":
			# 하드테일: 기운 탑 튜브 (세로로 납작) · 굵은 다운 튜브.
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([ht - head_dir * 0.03, Vector3(0.0, 0.6, -0.24), stp + Vector3(0.0, -0.025, -0.012)]), 8), PackedFloat32Array(_ramp(17, 0.021, 0.016)), paint_c, seg + 6, true, 0.72, Vector3(1.0, 0.0, 0.0))
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([hb + head_dir * 0.025, Vector3(0.0, 0.45, -0.27), bb + Vector3(0.0, 0.012, -0.022)]), 8), PackedFloat32Array(_ramp(17, 0.03, 0.026)), paint_c, seg + 8, true, 0.85, Vector3(1.0, 0.0, 0.0))
		_:
			# 에어로 로드: 날개꼴로 납작한 관 (옆에서 넓고 위에서 좁다).
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([ht - head_dir * 0.02, Vector3(0.0, 0.6, -0.22), stp + Vector3(0.0, -0.01, -0.01)]), 8), 0.02, paint_c, seg + 6, true, 0.5, Vector3(1.0, 0.0, 0.0))
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([hb + head_dir * 0.02, Vector3(0.0, 0.44, -0.26), bb + Vector3(0.0, 0.015, -0.02)]), 8), 0.03, paint_c, seg + 6, true, 0.42, Vector3(1.0, 0.0, 0.0))
	# 시트 튜브 (로드는 뒷바퀴를 따라 휜다) · 시트 클램프 · 시트포스트.
	if style == "road":
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([bb, bb + Vector3(0.0, 0.06, 0.01), Vector3(0.0, (bb.y + stp.y) * 0.5 + 0.02, (bb.z + stp.z) * 0.5 - 0.012), stp]), 6), 0.022, paint_c, seg + 6, true, 0.5, Vector3(1.0, 0.0, 0.0))
	else:
		Shapes.sweep(st, PackedVector3Array([bb, stp]), 0.018 if style != "mini" else 0.02, paint_c, seg + 6, true)
	Shapes.sweep(st, PackedVector3Array([stp + (stp - bb).normalized() * -0.012, stp + (stp - bb).normalized() * 0.008]), 0.02, mt(BLACK) if style != "city" else cr(), seg + 4, true)
	var post_c: Color = cr() if style == "city" or style == "mini" else gl(BLACK)
	Shapes.sweep(st, PackedVector3Array([stp, seat + Vector3(0.0, -0.025, 0.006)]), 0.0125 if style != "road" else 0.016, post_c, seg + 2, true, 0.6 if style == "road" else 1.0, Vector3(1.0, 0.0, 0.0))
	# 크랭크 통 (BB 셸).
	Shapes.lathe_x(st, bb + Vector3(-0.036, 0.0, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.021, 0.0), Vector2(0.023, 0.004), Vector2(0.023, 0.068), Vector2(0.021, 0.072), Vector2(0.0, 0.072)]), seg + 6, paint_c)
	# 체인 스테이 · 시트 스테이 (양쪽).
	for side: float in [-1.0, 1.0]:
		var drop: Vector3 = ar + Vector3(side * 0.05, 0.0, 0.0)
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([bb + Vector3(side * 0.022, 0.0, 0.01), bb + Vector3(side * 0.04, -0.004, 0.12), drop + Vector3(0.0, 0.004, -0.02)]), 6), PackedFloat32Array(_ramp(13, 0.012 if style != "mtb" else 0.014, 0.008)), paint_c, seg, true)
		var stay_top: Vector3 = seat_cluster + Vector3(side * 0.016, -0.01, 0.006)
		if style == "road":
			stay_top = bb.lerp(stp, 0.62) + Vector3(side * 0.018, 0.0, 0.012)
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([stay_top, stay_top.lerp(drop, 0.5) + Vector3(side * 0.012, 0.0, 0.0), drop + Vector3(0.0, 0.014, 0.0)]), 6), PackedFloat32Array(_ramp(13, 0.01, 0.007)), paint_c, seg, true)
		# 뒤 드롭아웃.
		ClayMesh.add_rounded_box(st, drop + Vector3(0.0, 0.006, -0.006), Vector3(0.006, 0.03, 0.03), 0.4, mt(Color("#3A3C40")), Basis(), 6, 3)
	_chain(st, style, bb, ar, r, trim)
	match style:
		"city":
			_city_body(st, paint, trim, p, has_rear_part, seg)
		"mtb":
			# 뒤 디스크 캘리퍼 · 물통 받이와 물통.
			ClayMesh.add_rounded_box(st, ar + Vector3(-0.044, 0.06, -0.025), Vector3(0.016, 0.034, 0.05), 0.35, mt(BLACK), Basis(Vector3.RIGHT, 0.6), 8, 3)
			_bottle(st, hb.lerp(bb, 0.55) + Vector3(0.0, 0.035, 0.022), (bb - hb).normalized(), Color("#3BA0D8"))
		"road":
			ClayMesh.add_rounded_box(st, ar + Vector3(-0.044, 0.06, -0.025), Vector3(0.014, 0.03, 0.045), 0.35, mt(BLACK), Basis(Vector3.RIGHT, 0.6), 8, 3)
			_bottle(st, hb.lerp(bb, 0.55) + Vector3(0.0, 0.03, 0.022), (bb - hb).normalized(), Color("#F2F2EE"))
			# 앞 변속기.
			ClayMesh.add_rounded_box(st, bb.lerp(stp, 0.32) + Vector3(0.04, 0.0, -0.02), Vector3(0.014, 0.022, 0.05), 0.35, gl(BLACK), Basis(Vector3.RIGHT, 0.4), 8, 3)
		"mini":
			# 접이 받침 바퀴 · 옆 받침대.
			Shapes.sweep(st, PackedVector3Array([bb + Vector3(-0.03, -0.01, 0.04), bb + Vector3(-0.1, -bb.y + 0.015, 0.14)]), PackedFloat32Array([0.008, 0.006]), mt(BLACK), 8, true)
	if style != "city" and style != "mini":
		_derailleur(st, ar, style)
	if style != "city":
		# 옆 받침대 (왼쪽, 뒤로 접힌 채 땅에 닿는다).
		if style != "mini":
			Shapes.sweep(st, PackedVector3Array([bb + Vector3(-0.03, -0.01, 0.05), bb + Vector3(-0.09, -bb.y + 0.03, 0.17), bb + Vector3(-0.1, -bb.y + 0.012, 0.18)]), PackedFloat32Array([0.008, 0.006, 0.007]), mt(BLACK), 8, true)
	# 케이블 (브레이크 · 변속 선) — 머리 관 옆에서 다운 튜브를 따라.
	if style != "road":
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([ht + Vector3(0.025, 0.05, -0.03), ht + Vector3(0.03, -0.04, 0.02), hb.lerp(bb, 0.4) + Vector3(0.026, 0.0, 0.0), bb.lerp(ar, 0.4) + Vector3(0.035, 0.03, 0.0)]), 8), 0.0035, mt(BLACK), 5, true)


## 체인 (닫힌 고리): 체인링 앞쪽 반 바퀴 → 아래 → 뒤 스프로킷 뒤쪽 반 바퀴 → 위.
static func _chain(st: SurfaceTool, style: String, bb: Vector3, ar: Vector3, r: float, trim: Color) -> void:
	var x: float = 0.05
	var ring: float = 0.072 if style == "road" else 0.07
	var cog: float = 0.032 if style == "mtb" else 0.026
	var c0: Vector3 = Vector3(x, bb.y, bb.z)
	var c1: Vector3 = Vector3(x, ar.y, ar.z)
	var loop: PackedVector3Array = PackedVector3Array()
	for i: int in 13:
		var a: float = deg_to_rad(lerpf(90.0, 270.0, float(i) / 12.0))
		loop.append(c0 + Vector3(0.0, sin(a) * ring, cos(a) * ring))
	for i2: int in 13:
		var a2: float = deg_to_rad(lerpf(-90.0, 90.0, float(i2) / 12.0))
		loop.append(c1 + Vector3(0.0, sin(a2) * cog, cos(a2) * cog))
	loop.append(loop[0])
	Shapes.sweep(st, loop, 0.0042, mt(Color("#4A4D52")), 6, false, 2.2, Vector3(1.0, 0.0, 0.0))


## 생활 자전거: 앞뒤 흙받이(긴 판) · 체인 덮개 · 뒤 짐받이 · 가운데 두 발 받침대 · 뒤 반사경.
static func _city_body(st: SurfaceTool, paint: Color, trim: Color, p: Dictionary, has_rear_part: bool, seg: int) -> void:
	var ar: Vector3 = p["axle_r"]
	var bb: Vector3 = p["bb"]
	var stp: Vector3 = p["seat_top"]
	var r: float = float(p["r"])
	var fender: PackedVector3Array = Shapes.arc_points(ar, r + 0.024, -28.0, 152.0, 30)
	Shapes.strip(st, fender, Vector3(1.0, 0.0, 0.0), 0.062, 0.008, gl(paint), 12)
	for side: float in [-1.0, 1.0]:
		Shapes.sweep(st, PackedVector3Array([ar + Vector3(side * 0.05, 0.0, 0.0), fender[3] + Vector3(side * 0.03, 0.0, 0.0)]), 0.0035, cr(), 5, true)
	# 체인 덮개 (위 줄과 체인링을 덮는 판).
	var guard: PackedVector3Array = Shapes.spline(PackedVector3Array([bb + Vector3(0.068, 0.085, -0.03), bb + Vector3(0.068, 0.07, 0.15), ar + Vector3(0.062, 0.05, -0.04)]), 8)
	Shapes.strip(st, guard, Vector3(0.0, 1.0, 0.0), PackedFloat32Array(_ramp(guard.size(), 0.07, 0.04)), 0.008, gl(paint.darkened(0.1)), 10)
	Shapes.lathe_x(st, bb + Vector3(0.064, 0.0, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.084, 0.0), Vector2(0.086, 0.006), Vector2(0.0, 0.006)]), 36, gl(paint.darkened(0.1)))
	if not has_rear_part:
		# 뒤 짐받이: 두 줄 레일 + 가로대 + 바퀴 축으로 내려가는 다리.
		var top_y: float = ar.y + r + 0.045
		for side2: float in [-1.0, 1.0]:
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([stp + Vector3(side2 * 0.04, -0.005, 0.03), Vector3(side2 * 0.06, top_y, ar.z - 0.16), Vector3(side2 * 0.06, top_y, ar.z + 0.2), Vector3(side2 * 0.05, top_y - 0.02, ar.z + 0.23)]), 6), 0.0055, cr(), 6, true)
			for k: int in 3:
				var zz: float = ar.z - 0.08 + float(k) * 0.12
				Shapes.sweep(st, PackedVector3Array([Vector3(side2 * 0.058, top_y - 0.004, zz), ar + Vector3(side2 * 0.056, 0.012, 0.0)]), 0.0045, cr(), 5, true)
		for k2: int in 5:
			var zz2: float = ar.z - 0.14 + float(k2) * 0.085
			Shapes.sweep(st, PackedVector3Array([Vector3(-0.06, top_y, zz2), Vector3(0.06, top_y, zz2)]), 0.004, cr(), 5, true)
	# 가운데 두 발 받침대 (뒤 축에 접혀 올라가 있다).
	for side3: float in [-1.0, 1.0]:
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([ar + Vector3(side3 * 0.062, 0.0, 0.0), ar + Vector3(side3 * 0.07, -0.08, 0.1), ar + Vector3(side3 * 0.06, -0.12, 0.18)]), 5), 0.0055, mt(BLACK), 6, true)
	# 뒤 반사경 (흙받이 끝).
	ClayMesh.add_rounded_box(st, fender[2] + Vector3(0.0, 0.02, 0.012), Vector3(0.04, 0.028, 0.008), 0.3, gl(Color("#D23A2E")), Basis(Vector3.RIGHT, -0.5), 8, 3)


## 뒤 변속기 (스프로킷 아래로 늘어진 팔 + 작은 도르래 둘).
static func _derailleur(st: SurfaceTool, ar: Vector3, style: String) -> void:
	var base: Vector3 = ar + Vector3(0.062, -0.012, 0.012)
	var c: Color = gl(BLACK) if style == "mtb" else gl(Color("#2E3036"))
	Shapes.sweep(st, Shapes.spline(PackedVector3Array([base, base + Vector3(0.006, -0.03, 0.02), base + Vector3(0.004, -0.07, 0.0)]), 5), PackedFloat32Array(_ramp(11, 0.012, 0.009)), c, 8, true, 0.6, Vector3(1.0, 0.0, 0.0))
	for k: int in 2:
		var at: Vector3 = base + Vector3(0.0, -0.035 - float(k) * 0.038, 0.012 - float(k) * 0.01)
		Shapes.lathe_x(st, at + Vector3(-0.004, 0.0, 0.0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.012, 0.008), Vector2(0.0, 0.008)]), 16, mt(Color("#3C3F45")))


## 물통 받이 + 물통 (다운 튜브 위).
static func _bottle(st: SurfaceTool, at: Vector3, along: Vector3, color: Color) -> void:
	var b: Basis = ClayMesh._basis_along(-along)
	var lift: Vector3 = b * Vector3(0.0, 0.0, 1.0)
	var prof: PackedVector2Array = PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.022, -0.05), Vector2(0.024, -0.04), Vector2(0.024, 0.03), Vector2(0.02, 0.045), Vector2(0.01, 0.055), Vector2(0.008, 0.07), Vector2(0.0, 0.07)])
	ClayMesh.add_lathe(st, prof, 14, Transform3D(b, at + lift * 0.026), Shapes.gloss(color))
	Shapes.sweep(st, PackedVector3Array([at + b * Vector3(0.0, -0.04, 0.0), at + b * Vector3(0.0, 0.03, 0.0)]), 0.004, mt(BLACK), 5, true)


# ---- 안장 ----

## 안장: 앞이 좁고 뒤가 넓은 매끈한 몸통 + 레일 (생활 자전거는 넓고 푹신, 뒤 스프링).
static func saddle(st: SurfaceTool, at: Vector3, style: String, color: Color, wide: bool) -> void:
	var rings: Array[PackedVector3Array] = []
	var back_w: float = 0.1 if (style == "city" or wide) else (0.062 if style == "road" else 0.072)
	var length: float = 0.2 if style != "city" else 0.18
	for i: int in 13:
		var t: float = float(i) / 12.0
		var z: float = at.z - length * 0.55 + t * length
		var w: float = lerpf(0.022, back_w, smoothstep(0.15, 0.85, t))
		var top: float = 0.022 + 0.008 * sin(t * PI)
		var y: float = at.y + (0.01 if t > 0.75 else 0.0) * (t - 0.75) / 0.25 - 0.004 * sin(t * PI)
		rings.append(Shapes.section(0.0, y, z, w, top, 0.012, 22, 0.35))
	var leather: Color = Shapes.gloss(color) if style == "city" else Shapes.matte(color)
	Shapes.loft(st, rings, leather, true, true)
	# 레일 (안장 아래 두 줄) · 클램프.
	for side: float in [-1.0, 1.0]:
		Shapes.sweep(st, Shapes.spline(PackedVector3Array([at + Vector3(side * 0.012, -0.008, -length * 0.5), at + Vector3(side * 0.022, -0.03, -length * 0.15), at + Vector3(side * 0.03, -0.03, length * 0.2), at + Vector3(side * 0.04, -0.006, length * 0.42)]), 5), 0.0035, Shapes.chrome(), 6, true)
	ClayMesh.add_rounded_box(st, at + Vector3(0.0, -0.032, 0.0), Vector3(0.05, 0.016, 0.03), 0.4, Shapes.matte(Color("#3A3C40")), Basis(), 8, 3)
	if style == "city":
		for side2: float in [-1.0, 1.0]:
			Shapes.sweep(st, Shapes.helix(at + Vector3(side2 * 0.045, -0.055, length * 0.36), at + Vector3(side2 * 0.045, -0.008, length * 0.36), 0.011, 5.0, 60), 0.0028, Shapes.chrome(), 5, true)


# ---- 조향 (원점 = 헤드 튜브 위, 좌표는 탈것 좌표에서 그 자리를 뺀 것) ----

## 포크 · 스템 · 핸들 · 그립 · 레버 (· 서스펜션 · 앞 흙받이 · 바구니 · 등). q: { head_bottom, axle_f, bar, head, front } (조향 좌표).
static func steer(st: SurfaceTool, style: String, paint: Color, trim: Color, q: Dictionary, r: float, has_front_part: bool, seg: int) -> void:
	var hb: Vector3 = q["head_bottom"]
	var af: Vector3 = q["axle_f"]
	var bar: Vector3 = q["bar"]
	var down: Vector3 = (af - hb).normalized()
	var crown: Vector3 = hb + down * 0.03
	var fork_c: Color = gl(paint) if style == "city" or style == "road" else (gl(trim) if style == "mini" else mt(BLACK))
	match style:
		"mtb":
			# 서스펜션 포크: 크라운 · 번쩍이는 이너 튜브 · 굵은 아우터 · 앞 아치.
			ClayMesh.add_rounded_box(st, crown, Vector3(0.11, 0.03, 0.045), 0.45, mt(BLACK), ClayMesh._basis_along(-down), 10, 4)
			for side: float in [-1.0, 1.0]:
				var top_p: Vector3 = crown + Vector3(side * 0.045, 0.0, 0.0)
				var low_p: Vector3 = af + Vector3(side * 0.048, 0.0, 0.0)
				var mid: Vector3 = top_p.lerp(low_p, 0.42)
				Shapes.sweep(st, PackedVector3Array([top_p, mid]), 0.0145, cr(Color("#E4C46A")), seg + 2, true)
				Shapes.sweep(st, PackedVector3Array([mid - down * 0.02, low_p - down * 0.01]), PackedFloat32Array([0.02, 0.017]), mt(BLACK), seg + 2, true)
				ClayMesh.add_rounded_box(st, low_p, Vector3(0.012, 0.03, 0.03), 0.4, mt(BLACK), Basis(), 6, 3)
			var arch: PackedVector3Array = PackedVector3Array()
			for k: int in 9:
				var a: float = PI * float(k) / 8.0
				var c0: Vector3 = (crown + af) * 0.5 + down * 0.02
				arch.append(c0 + Vector3(-cos(a) * 0.048, sin(a) * 0.035, -0.03))
			Shapes.sweep(st, arch, 0.009, mt(BLACK), 8, true)
			# 앞 디스크 캘리퍼 (왼쪽 다리 뒤).
			ClayMesh.add_rounded_box(st, af + Vector3(-0.05, 0.058, 0.022), Vector3(0.016, 0.034, 0.05), 0.35, mt(BLACK), Basis(Vector3.RIGHT, -0.4), 8, 3)
		_:
			# 단단한 포크: 크라운에서 내려와 끝이 앞으로 휜다 (rake).
			ClayMesh.add_rounded_box(st, crown, Vector3(0.09, 0.022, 0.04), 0.5, fork_c, ClayMesh._basis_along(-down), 10, 4)
			for side2: float in [-1.0, 1.0]:
				var blade: PackedVector3Array = Shapes.spline(PackedVector3Array([crown + Vector3(side2 * 0.034, 0.0, 0.0), crown.lerp(af, 0.55) + Vector3(side2 * 0.042, 0.0, 0.0), af + Vector3(side2 * 0.045, 0.05, -0.022), af + Vector3(side2 * 0.045, 0.0, -0.012)]), 6)
				Shapes.sweep(st, blade, PackedFloat32Array(_ramp(blade.size(), 0.0135, 0.0075)), fork_c, seg + 2, true, 0.55 if style == "road" else 1.0, Vector3(1.0, 0.0, 0.0))
			if style == "road":
				ClayMesh.add_rounded_box(st, af + Vector3(-0.048, 0.058, 0.022), Vector3(0.014, 0.03, 0.045), 0.35, mt(BLACK), Basis(Vector3.RIGHT, -0.4), 8, 3)
			else:
				# 림 브레이크 (크라운 위 캘리퍼).
				ClayMesh.add_rounded_box(st, crown + down * 0.0 + Vector3(0.0, 0.0, -0.035), Vector3(0.1, 0.016, 0.02), 0.4, cr(), Basis(), 8, 3)
	# 스템 (헤드에서 핸들로).
	var stem_c: Color = cr() if style == "city" or style == "mini" else gl(BLACK)
	var stem: PackedVector3Array
	if style == "city":
		stem = Shapes.spline(PackedVector3Array([Vector3(0.0, -0.01, 0.0), Vector3(0.0, 0.05, 0.02), bar + Vector3(0.0, 0.0, -0.04), bar]), 6)
	elif style == "mini":
		stem = Shapes.spline(PackedVector3Array([Vector3(0.0, -0.01, 0.0), Vector3(0.0, 0.05, 0.03), bar + Vector3(0.0, -0.02, -0.01), bar]), 6)
	else:
		stem = Shapes.spline(PackedVector3Array([Vector3(0.0, -0.01, 0.0), Vector3(0.0, 0.04, 0.03), bar + Vector3(0.0, -0.01, -0.03), bar]), 6)
	Shapes.sweep(st, stem, PackedFloat32Array(_ramp(stem.size(), 0.0165, 0.013)), stem_c, seg + 2, true)
	ClayMesh.add_rounded_box(st, bar, Vector3(0.042, 0.03, 0.03), 0.45, stem_c, Basis(), 8, 3)
	# 핸들 (모양별) · 그립 · 브레이크 레버.
	var grip_c: Color = mt(Color("#7A4E30")) if style == "city" else mt(BLACK)
	for side3: float in [-1.0, 1.0]:
		var bar_path: PackedVector3Array
		match style:
			"city":
				bar_path = Shapes.spline(PackedVector3Array([bar, bar + Vector3(side3 * 0.1, 0.012, -0.015), bar + Vector3(side3 * 0.2, 0.012, 0.02), bar + Vector3(side3 * 0.25, 0.008, 0.07)]), 8)
			"road":
				bar_path = Shapes.spline(PackedVector3Array([bar, bar + Vector3(side3 * 0.13, 0.0, -0.005), bar + Vector3(side3 * 0.2, -0.005, -0.06), bar + Vector3(side3 * 0.215, -0.07, -0.07), bar + Vector3(side3 * 0.21, -0.1, -0.02), bar + Vector3(side3 * 0.2, -0.095, 0.03)]), 8)
			_:
				bar_path = Shapes.spline(PackedVector3Array([bar, bar + Vector3(side3 * 0.08, 0.018, 0.0), bar + Vector3(side3 * 0.2, 0.022, 0.012), bar + Vector3(side3 * 0.3, 0.025, 0.03)]), 8)
		Shapes.sweep(st, bar_path, 0.0105, stem_c if style != "road" else gl(BLACK), seg, true)
		var grip_at: Vector3 = bar_path[bar_path.size() - 1]
		var grip_dir: Vector3 = (bar_path[bar_path.size() - 1] - bar_path[bar_path.size() - 4]).normalized()
		if style == "road":
			# 후드 (브레이크 · 변속 레버 몸통) — 손을 얹는 자리.
			var hood: Vector3 = bar + Vector3(side3 * 0.205, 0.012, -0.075)
			ClayMesh.add_ellipsoid(st, hood, Vector3(0.017, 0.026, 0.035), mt(BLACK), 12, 6, Basis(Vector3.RIGHT, 0.5))
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([hood + Vector3(0.0, -0.01, -0.025), hood + Vector3(0.0, -0.06, -0.04), hood + Vector3(0.0, -0.1, -0.02)]), 5), 0.006, gl(Color("#2E3036")), 6, true)
			# 바 테이프.
			Shapes.sweep(st, bar_path.slice(5), 0.0125, mt(paint if trim.get_luminance() < 0.2 else Color("#F2F2EE")), seg, true)
		else:
			Shapes.sweep(st, PackedVector3Array([grip_at - grip_dir * 0.085, grip_at + grip_dir * 0.004]), 0.0165 if style != "city" else 0.017, grip_c, seg + 2, true)
			if style == "mtb":
				ClayMesh.add_torus(st, grip_at - grip_dir * 0.085, 0.017, 0.004, cr(), 12, 4, ClayMesh._basis_along(grip_dir))
			# 브레이크 레버 (그립 앞, 손가락 자리).
			var lever_base: Vector3 = grip_at - grip_dir * 0.1
			Shapes.sweep(st, Shapes.spline(PackedVector3Array([lever_base, lever_base + Vector3(0.0, 0.004, -0.03), lever_base + grip_dir * 0.07 + Vector3(0.0, -0.006, -0.032)]), 5), 0.0045, cr() if style != "mtb" else mt(BLACK), 6, true)
			ClayMesh.add_rounded_box(st, lever_base, Vector3(0.02, 0.018, 0.026), 0.4, mt(Color("#2E3036")), Basis(), 6, 3)
	if style == "city":
		# 종 (왼쪽 그립 안쪽).
		var bell: Vector3 = bar + Vector3(-0.13, 0.03, 0.0)
		ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.024, 0.0), Vector2(0.022, 0.012), Vector2(0.012, 0.022), Vector2(0.0, 0.025)]), 16, Transform3D(Basis(), bell), cr())
		# 앞 흙받이 (조향과 같이 돈다).
		var ff: PackedVector3Array = Shapes.arc_points(af, r + 0.024, 20.0, 172.0, 24)
		Shapes.strip(st, ff, Vector3(1.0, 0.0, 0.0), 0.062, 0.008, gl(paint), 12)
		for side4: float in [-1.0, 1.0]:
			Shapes.sweep(st, PackedVector3Array([af + Vector3(side4 * 0.046, 0.0, 0.0), ff[18] + Vector3(side4 * 0.03, 0.0, 0.0)]), 0.0035, cr(), 5, true)
		if not has_front_part:
			_basket(st, q["front"], r)


## 앞 바구니 (철사 그물: 테두리 · 세로 살 · 가로 줄).
static func _basket(st: SurfaceTool, at: Vector3, _r: float) -> void:
	var c: Color = Shapes.chrome(Color("#D6D9DE"))
	var w: float = 0.15
	var d: float = 0.12
	var h: float = 0.16
	var base: Vector3 = at + Vector3(0.0, -0.06, -0.01)
	for level: int in 4:
		var y: float = float(level) / 3.0 * h
		var k: float = 1.0 + float(level) * 0.04
		var ring: PackedVector3Array = Shapes.ring_xz(base.x, base.y + y, base.z, w * k, d * k, 24, 0.85)
		ring.append(ring[0])
		Shapes.sweep(st, ring, 0.0035 if level != 3 else 0.006, c, 5, false)
	for i: int in 16:
		var a: float = TAU * float(i) / 16.0
		var bottom: Vector3 = base + Vector3(signf(cos(a)) * pow(absf(cos(a)), 0.5) * w, 0.0, signf(sin(a)) * pow(absf(sin(a)), 0.5) * d)
		var top: Vector3 = base + Vector3(signf(cos(a)) * pow(absf(cos(a)), 0.5) * w * 1.12, h, signf(sin(a)) * pow(absf(sin(a)), 0.5) * d * 1.12)
		Shapes.sweep(st, PackedVector3Array([bottom, top]), 0.0032, c, 4, true)
	# 바닥판 · 핸들에 거는 고리.
	ClayMesh.add_rounded_box(st, base + Vector3(0.0, -0.004, 0.0), Vector3(w * 2.0, 0.006, d * 2.0), 0.2, c, Basis(), 8, 2)


## 앞 등 껍데기 (생활 자전거 = 둥근 크롬 사발, 그 밖 = 작은 LED 몸통). head = 렌즈 자리 (조향 좌표).
static func lamp(st: SurfaceTool, style: String, head: Vector3, lens_r: float, trim: Color) -> void:
	if style == "city":
		ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, 0.07), Vector2(lens_r * 0.6, 0.065), Vector2(lens_r + 0.012, 0.03), Vector2(lens_r + 0.014, -0.0), Vector2(lens_r + 0.006, -0.004)]), 18, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), head + Vector3(0.0, 0.0, -0.035)), Shapes.chrome())
	else:
		ClayMesh.add_rounded_box(st, head + Vector3(0.0, 0.0, 0.0), Vector3(lens_r * 2.6, lens_r * 2.0, 0.06), 0.5, Shapes.gloss(Color("#2A2B2F")), Basis(), 10, 4)
	Shapes.sweep(st, PackedVector3Array([head + Vector3(0.0, -lens_r - 0.004, 0.02), head + Vector3(0.0, -lens_r - 0.03, 0.05)]), 0.005, Shapes.matte(Color("#3A3C40")), 6, true)


## a → b 로 고르게 변하는 굵기 n 개.
static func _ramp(n: int, a: float, b: float) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(lerpf(a, b, float(i) / float(maxi(n - 1, 1))))
	return out
