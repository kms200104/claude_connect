class_name FishModel
extends RefCounted
## 물고기 모형 (아이콘·전시용). 데이터의 몸 모양·색·무늬로 점토 물고기를 만든다. 머리는 -X, 길이 약 0.6m.
## 볼터치가 있는 동글동글한 얼굴 — 참고 그림(art_source/reference/fishing_items.png)의 물고기 느낌.

static var _cache: Dictionary[String, ArrayMesh] = {}


static func mesh(fish: FishInfo) -> ArrayMesh:
	if _cache.has(fish.id):
		return _cache[fish.id]
	var st: SurfaceTool = ClayMesh.begin()
	if fish.shape == "crayfish" or fish.shape == "turtle":
		if fish.shape == "crayfish":
			_add_crayfish(st, fish)
		else:
			_add_turtle(st, fish)
		var special: ArrayMesh = ClayMesh.commit(st)
		_cache[fish.id] = special
		return special
	var r: Vector3 = _radii(fish.shape)
	var body: Callable = ClayMesh.vertical_gradient(fish.belly_color, fish.body_color, 0.7)
	if fish.shape == "eel":
		ClayMesh.add_capsule(st, Vector3(-r.x, 0.0, 0.0), Vector3(r.x, 0.0, 0.0), r.y, body, 12, 4)
	else:
		ClayMesh.add_ellipsoid(st, Vector3.ZERO, r, body, 16, 10)
	if fish.shape == "sturgeon":
		ClayMesh.add_ellipsoid(st, Vector3(-r.x * 1.05, -0.01, 0.0), Vector3(0.1, 0.035, 0.035), fish.body_color, 8, 4)
		for i: int in 5:
			ClayMesh.add_ellipsoid(st, Vector3(-r.x * 0.6 + 0.16 * float(i), r.y * 0.95, 0.0), Vector3(0.03, 0.025, 0.025), fish.accent_color, 6, 3)
	# 꼬리: 위아래로 갈라진 지느러미 두 장 (금붕어는 크고 하늘하늘).
	var tail_size: Vector3 = Vector3(0.13, 0.07, 0.014) * (1.7 if fish.shape == "goldfish" else 1.0)
	for side: float in [1.0, -1.0]:
		var at: Vector3 = Vector3(r.x + tail_size.x * 0.55, side * tail_size.y * 0.6, 0.0)
		ClayMesh.add_ellipsoid(st, at, tail_size, fish.fin_color, 10, 4, Basis(Vector3.BACK, side * 0.55))
	# 등지느러미·배지느러미·가슴지느러미.
	ClayMesh.add_ellipsoid(st, Vector3(0.02, r.y * 0.92, 0.0), Vector3(r.x * 0.38, r.y * 0.4, 0.012), fish.fin_color, 10, 4, Basis(Vector3.BACK, -0.25))
	ClayMesh.add_ellipsoid(st, Vector3(0.05, -r.y * 0.9, 0.0), Vector3(r.x * 0.2, r.y * 0.25, 0.012), fish.fin_color, 8, 3)
	for side: float in [1.0, -1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(-r.x * 0.25, -r.y * 0.2, side * r.z * 0.95), Vector3(0.06, 0.035, 0.012), fish.fin_color, 8, 3, Basis(Vector3.UP, side * 0.4))
	_add_pattern(st, fish, r)
	if fish.shape == "puffer":
		for i: int in 14:
			var a: float = TAU * float(i) / 14.0
			var dir: Vector3 = Vector3(cos(a) * 0.6, sin(a * 2.0) * 0.5 + 0.3, sin(a)).normalized()
			ClayMesh.add_capsule(st, dir * r * 0.95, dir * r * 1.12, 0.012, fish.accent_color.lightened(0.3), 4, 1)
	if fish.shape == "catfish":
		for side: float in [1.0, -1.0]:
			ClayMesh.add_capsule(st, Vector3(-r.x * 0.9, -0.01, side * 0.03), Vector3(-r.x * 1.25, -0.06, side * 0.14), 0.008, fish.fin_color.darkened(0.3), 4, 1)
	# 얼굴: 큰 눈 + 반짝이 + 볼터치 + 입.
	for side: float in [1.0, -1.0]:
		var eye: Vector3 = Vector3(-r.x * 0.62, r.y * 0.25, side * r.z * 0.78)
		ClayMesh.add_ellipsoid(st, eye, Vector3(0.042, 0.045, 0.03), Color("#2B211E"), 8, 5)
		ClayMesh.add_ellipsoid(st, eye + Vector3(-0.012, 0.016, side * 0.024), Vector3(0.013, 0.013, 0.008), Color.WHITE, 5, 3)
		ClayMesh.add_ellipsoid(st, Vector3(-r.x * 0.45, -r.y * 0.25, side * r.z * 0.88), Vector3(0.035, 0.02, 0.012), Color("#F4A6A0"), 6, 3)
	ClayMesh.add_ellipsoid(st, Vector3(-r.x * 0.98, -r.y * 0.12, 0.0), Vector3(0.015, 0.012, 0.03), fish.body_color.darkened(0.4), 6, 3)
	var built: ArrayMesh = ClayMesh.commit(st)
	_cache[fish.id] = built
	return built


static func _radii(shape: String) -> Vector3:
	match shape:
		"carp":
			return Vector3(0.28, 0.15, 0.085)
		"perch":
			return Vector3(0.27, 0.13, 0.08)
		"trout":
			return Vector3(0.32, 0.11, 0.075)
		"eel":
			return Vector3(0.36, 0.055, 0.055)
		"catfish":
			return Vector3(0.3, 0.1, 0.1)
		"goldfish":
			return Vector3(0.19, 0.15, 0.1)
		"puffer":
			return Vector3(0.18, 0.17, 0.16)
		"sturgeon":
			return Vector3(0.4, 0.085, 0.075)
	return Vector3(0.27, 0.085, 0.06)


static func _add_pattern(st: SurfaceTool, fish: FishInfo, r: Vector3) -> void:
	match fish.pattern:
		"stripe":
			ClayMesh.add_ellipsoid(st, Vector3(0.02, 0.0, 0.0), Vector3(r.x * 0.82, 0.013, r.z * 1.02), fish.accent_color, 14, 3)
		"band":
			for i: int in 3:
				var x: float = -r.x * 0.25 + float(i) * r.x * 0.32
				var k: float = sqrt(maxf(1.0 - pow(x / r.x, 2.0), 0.05))
				ClayMesh.add_ellipsoid(st, Vector3(x, 0.0, 0.0), Vector3(0.025, r.y * k * 1.02, r.z * k * 1.03), fish.accent_color, 10, 5)
		"spots":
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = fish.id.hash()
			for i: int in 9:
				var u: float = rng.randf_range(-0.6, 0.75)
				var v: float = rng.randf_range(-0.1, 0.8)
				var side: float = 1.0 if i % 2 == 0 else -1.0
				var k: float = sqrt(maxf(1.0 - u * u - v * v * 0.6, 0.05))
				ClayMesh.add_ellipsoid(st, Vector3(u * r.x, v * r.y * 0.8, side * r.z * k), Vector3(0.022, 0.02, 0.012), fish.accent_color, 6, 3)


## 가재: 마디진 몸 + 부채 꼬리 + 집게 두 개 + 더듬이. 머리는 -X.
static func _add_crayfish(st: SurfaceTool, fish: FishInfo) -> void:
	var shell: Callable = ClayMesh.vertical_gradient(fish.belly_color, fish.body_color, 0.6)
	ClayMesh.add_ellipsoid(st, Vector3(-0.08, 0.0, 0.0), Vector3(0.14, 0.08, 0.09), shell, 12, 7)
	for i: int in 4:
		var x: float = 0.06 + 0.07 * float(i)
		var k: float = 1.0 - 0.15 * float(i)
		ClayMesh.add_ellipsoid(st, Vector3(x, -0.005 * float(i), 0.0), Vector3(0.045, 0.06 * k, 0.07 * k), shell, 10, 5)
	for side: float in [-1.0, 0.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(0.37, -0.02, side * 0.04), Vector3(0.05, 0.012, 0.035), fish.fin_color, 6, 3, Basis(Vector3.UP, side * 0.5))
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_capsule(st, Vector3(-0.15, -0.01, side * 0.07), Vector3(-0.27, 0.0, side * 0.17), 0.025, fish.body_color, 6, 1)
		ClayMesh.add_ellipsoid(st, Vector3(-0.33, 0.0, side * 0.19), Vector3(0.07, 0.035, 0.045), shell, 8, 4, Basis(Vector3.UP, side * 0.3))
		ClayMesh.add_ellipsoid(st, Vector3(-0.39, 0.0, side * 0.16), Vector3(0.04, 0.02, 0.025), fish.fin_color, 6, 3, Basis(Vector3.UP, side * 0.6))
		ClayMesh.add_capsule(st, Vector3(-0.2, 0.02, side * 0.03), Vector3(-0.42, 0.06, side * 0.12), 0.006, fish.fin_color, 4, 1)
		for leg: int in 3:
			ClayMesh.add_capsule(st, Vector3(-0.04 + 0.05 * float(leg), -0.05, side * 0.06), Vector3(-0.02 + 0.05 * float(leg), -0.09, side * 0.14), 0.01, fish.fin_color, 4, 1)
		var eye: Vector3 = Vector3(-0.2, 0.06, side * 0.045)
		ClayMesh.add_ellipsoid(st, eye, Vector3(0.025, 0.028, 0.025), Color("#2B211E"), 8, 4)
		ClayMesh.add_ellipsoid(st, eye + Vector3(-0.01, 0.012, side * 0.012), Vector3(0.008, 0.008, 0.006), Color.WHITE, 4, 2)


## 자라: 납작한 등딱지 + 목을 내민 머리 + 지느러미발 넷. 머리는 -X.
static func _add_turtle(st: SurfaceTool, fish: FishInfo) -> void:
	ClayMesh.add_ellipsoid(st, Vector3(0.02, 0.02, 0.0), Vector3(0.24, 0.07, 0.2), ClayMesh.vertical_gradient(fish.belly_color, fish.body_color, 0.4), 16, 8)
	ClayMesh.add_ellipsoid(st, Vector3(0.02, -0.01, 0.0), Vector3(0.25, 0.03, 0.21), fish.belly_color, 16, 4)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = fish.id.hash()
	for i: int in 7:
		var a: float = rng.randf() * TAU
		var rr: float = rng.randf_range(0.0, 0.6)
		ClayMesh.add_ellipsoid(st, Vector3(0.02 + cos(a) * 0.24 * rr, 0.07 * sqrt(1.0 - rr * rr) + 0.02, sin(a) * 0.2 * rr), Vector3(0.03, 0.012, 0.03), fish.accent_color, 6, 2)
	ClayMesh.add_capsule(st, Vector3(-0.2, 0.01, 0.0), Vector3(-0.3, 0.03, 0.0), 0.04, fish.fin_color, 8, 2)
	ClayMesh.add_ellipsoid(st, Vector3(-0.34, 0.04, 0.0), Vector3(0.06, 0.05, 0.05), fish.fin_color, 10, 5)
	ClayMesh.add_ellipsoid(st, Vector3(-0.4, 0.04, 0.0), Vector3(0.02, 0.015, 0.015), fish.fin_color.darkened(0.2), 6, 3)
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, Vector3(-0.12, -0.01, side * 0.2), Vector3(0.08, 0.015, 0.05), fish.fin_color, 8, 3, Basis(Vector3.UP, side * -0.6))
		ClayMesh.add_ellipsoid(st, Vector3(0.16, -0.01, side * 0.17), Vector3(0.06, 0.015, 0.04), fish.fin_color, 8, 3, Basis(Vector3.UP, side * 0.6))
		var eye: Vector3 = Vector3(-0.36, 0.065, side * 0.03)
		ClayMesh.add_ellipsoid(st, eye, Vector3(0.016, 0.018, 0.014), Color("#2B211E"), 6, 3)
		ClayMesh.add_ellipsoid(st, Vector3(-0.33, 0.035, side * 0.045), Vector3(0.014, 0.01, 0.008), Color("#F4A6A0"), 4, 2)
	ClayMesh.add_ellipsoid(st, Vector3(0.27, 0.0, 0.0), Vector3(0.04, 0.015, 0.02), fish.fin_color, 6, 3)
