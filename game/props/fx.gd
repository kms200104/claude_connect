class_name Fx
extends RefCounted
## v0.28.8 전투 효과 (핏방울 · 불꽃 · 불씨 · 흙먼지 고리 · 번쩍임 · 휘두른 궤적 · 퍼지는 고리 · 빛줄기 · 반짝이 기둥).
## 한 번 터지는 CPUParticles3D (부드러운 동그라미 그림, 색 · 크기가 시간에 따라 바뀐다) 와 궤적 띠 메시.
## 새 셰이더 파일은 쓰지 않고 머티리얼 셋 (더하기 입자 · 섞기 입자 · 더하기 띠) 을 함께 쓴다 — 짧게 살다 사라진다.
## Puff (점토 덩어리) 는 발밑 흙먼지 · 건축 같은 마을 그림에 그대로 쓰고, 싸움에는 이것을 쓴다.

static var _add_mat: StandardMaterial3D = null
static var _mix_mat: StandardMaterial3D = null
static var _ribbon_mat: StandardMaterial3D = null
static var _quad: QuadMesh = null
static var _fade_curve: Curve = null
static var _grow_curve: Curve = null
static var _ramps: Dictionary[String, Gradient] = {}


static func _dot() -> GradientTexture2D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


static func _particle_mat(additive: bool) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	# (BILLBOARD_PARTICLES 는 입자마다의 크기를 버린다 — 늘 화면을 보게 하고 크기는 그대로 둔다.)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _dot()
	m.disable_receive_shadows = true
	return m


static func add_material() -> StandardMaterial3D:
	if _add_mat == null:
		_add_mat = _particle_mat(true)
	return _add_mat


static func mix_material() -> StandardMaterial3D:
	if _mix_mat == null:
		_mix_mat = _particle_mat(false)
	return _mix_mat


static func ribbon_material() -> StandardMaterial3D:
	if _ribbon_mat == null:
		_ribbon_mat = StandardMaterial3D.new()
		_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ribbon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ribbon_mat.vertex_color_use_as_albedo = true
		_ribbon_mat.disable_receive_shadows = true
	return _ribbon_mat


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## 크기: 처음 크게 → 줄어든다 (fade) / 작게 → 커진다 (grow).
static func _curve(grow: bool) -> Curve:
	if grow:
		if _grow_curve == null:
			_grow_curve = Curve.new()
			_grow_curve.add_point(Vector2(0.0, 0.35))
			_grow_curve.add_point(Vector2(0.4, 0.9))
			_grow_curve.add_point(Vector2(1.0, 1.0))
		return _grow_curve
	if _fade_curve == null:
		_fade_curve = Curve.new()
		_fade_curve.add_point(Vector2(0.0, 1.0))
		_fade_curve.add_point(Vector2(0.6, 0.75))
		_fade_curve.add_point(Vector2(1.0, 0.0))
	return _fade_curve


## 색 바뀜: 처음 색 → 끝 색 (끝은 투명).
static func _ramp(a: Color, b: Color) -> Gradient:
	var key: String = a.to_html() + b.to_html()
	if not _ramps.has(key):
		var g: Gradient = Gradient.new()
		g.set_color(0, a)
		g.set_color(1, Color(b, 0.0))
		g.add_point(0.55, b)
		_ramps[key] = g
	return _ramps[key]


## 한 번 터지는 입자 한 덩어리. 다 살면 스스로 사라진다.
static func burst(parent: Node, at: Vector3, additive: bool, amount: int, life: float, dir: Vector3, spread_deg: float, speed: Vector2, gravity: float, size: Vector2, from_color: Color, to_color: Color, grow: bool = false, damping: float = 0.0, box: float = 0.0) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree() or amount <= 0:
		return null
	var p: CPUParticles3D = CPUParticles3D.new()
	p.mesh = _quad_mesh()
	p.material_override = add_material() if additive else mix_material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.lifetime_randomness = 0.35
	p.local_coords = false
	p.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	p.spread = spread_deg
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.damping_min = damping
	p.damping_max = damping * 1.4
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = _curve(grow)
	p.color_ramp = _ramp(from_color, to_color)
	if box > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = box
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


# ---- 쓰는 모양들 ----

## 핏방울 (dir 쪽으로 튀어 떨어진다) + 옅은 피안개. amount 1 = 보통 한 대.
static func blood(parent: Node, at: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	var d: Vector3 = (dir.normalized() + Vector3(0.0, 0.55, 0.0)).normalized()
	burst(parent, at, false, int(22 * amount), 0.7, d, 34.0, Vector2(2.4, 5.2), -12.0, Vector2(0.06, 0.14), Color(0.62, 0.03, 0.04, 1.0), Color(0.32, 0.0, 0.01, 0.95))
	burst(parent, at, false, int(4 * amount), 0.4, d, 55.0, Vector2(0.3, 0.9), -1.0, Vector2(0.3, 0.55), Color(0.5, 0.03, 0.03, 0.32), Color(0.25, 0.0, 0.0, 0.1), true, 2.0)


## 쇠 불꽃 (번쩍 튀어 떨어진다).
static func sparks(parent: Node, at: Vector3, dir: Vector3, n: int = 14, color: Color = Color(1.0, 0.9, 0.55)) -> void:
	burst(parent, at, true, n, 0.32, (dir.normalized() + Vector3(0.0, 0.4, 0.0)).normalized(), 55.0, Vector2(4.0, 8.5), -9.0, Vector2(0.05, 0.1), Color(1.0, 1.0, 0.9, 1.0), color)


## 불씨 (위로 올라가며 꺼진다) + 불꽃 한 번.
static func embers(parent: Node, at: Vector3, n: int = 14) -> void:
	burst(parent, at, true, n, 0.9, Vector3.UP, 70.0, Vector2(0.8, 2.6), 1.6, Vector2(0.07, 0.14), Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.9), false, 1.0, 0.15)
	burst(parent, at, true, 3, 0.24, Vector3.UP, 40.0, Vector2(0.2, 0.6), 0.5, Vector2(0.35, 0.55), Color(1.0, 0.65, 0.2, 0.7), Color(0.9, 0.2, 0.0, 0.3), true)


## 땅을 따라 퍼지는 흙먼지 고리.
static func dust_ring(parent: Node, at: Vector3, radius: float, color: Color) -> void:
	var p: CPUParticles3D = burst(parent, at + Vector3(0.0, 0.08, 0.0), false, 18, 0.7, Vector3.UP, 85.0, Vector2(radius * 1.6, radius * 2.6), -0.4, Vector2(0.45, 0.85), Color(color, 0.7), Color(color, 0.35), true, radius * 2.5, 0.0)
	if p != null:
		p.flatness = 0.92
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = radius * 0.3
		p.emission_ring_inner_radius = radius * 0.2
		p.emission_ring_height = 0.05


## 맞은 자리 번쩍 (짧게 커졌다 사라진다).
static func flash(parent: Node, at: Vector3, color: Color, size: float = 0.9) -> void:
	# 바깥 빛무리 (옅게) + 가운데 하얀 점 (짧게). size 는 '느낌' 값 — 실제 지름은 그 절반쯤.
	burst(parent, at, true, 1, 0.13, Vector3.UP, 0.0, Vector2.ZERO, 0.0, Vector2(size * 0.9, size * 0.9), Color(color, 0.55), Color(color, 0.25), true)
	burst(parent, at, true, 1, 0.07, Vector3.UP, 0.0, Vector2.ZERO, 0.0, Vector2(size * 0.35, size * 0.35), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), true)


## 반짝이 기둥 (치유 · 강화 — 둘레에서 위로 오른다).
static func sparkle_column(parent: Node, at: Vector3, color: Color, radius: float = 0.6) -> void:
	burst(parent, at + Vector3(0.0, 0.2, 0.0), true, 22, 1.1, Vector3.UP, 12.0, Vector2(1.0, 2.4), 0.6, Vector2(0.09, 0.18), Color(1, 1, 1, 1), color, false, 0.6, radius)


# ---- 띠 (궤적 · 고리 · 빛줄기) ----

## 휘두른 궤적: origin 둘레 radius m 에 sweep 도만큼 휘는 초승달 띠. yaw 쪽을 가운데로, 앞쪽 끝이 밝고 꼬리는 투명.
## dur 동안 sweep 방향으로 돌며 사라진다. height = 땅에서 높이, tilt = 기울기 (위에서 내려치기 등).
static func slash(parent: Node, origin: Vector3, yaw: float, color: Color, radius: float = 1.3, sweep_deg: float = 140.0, height: float = 1.0, dur: float = 0.2, width: float = 0.38, tilt: float = 0.0, clockwise: bool = true) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var seg: int = maxi(16, int(sweep_deg / 5.0))
	var sweep: float = deg_to_rad(sweep_deg)
	# 세 줄 (안 · 가운데 · 바깥): 가운데가 가장 밝고 양쪽은 투명 — 부드러운 빛 띠. 앞 끝 (t=1) 이 굵고 밝다.
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var core: Color = color.lightened(0.25)
	for i: int in seg + 1:
		var t: float = float(i) / float(seg)
		var a: float = -sweep * 0.5 + sweep * t
		var w: float = width * (0.2 + 0.8 * t * t)
		var fade: float = t * t
		for k: int in 3:
			var r: float = radius - w * (1.0 - float(k) * 0.5)
			verts.append(Vector3(sin(a) * r, 0.0, -cos(a) * r))
			cols.append(Color(color.lightened(0.45), fade) if k == 1 else Color(core, 0.0))
	var arrays_mesh: ArrayMesh = _strip_mesh(verts, cols, 3)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = arrays_mesh
	mi.material_override = ribbon_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = origin + Vector3(0.0, height, 0.0)
	var dirn: float = -1.0 if clockwise else 1.0
	mi.rotation = Vector3(tilt, yaw - dirn * deg_to_rad(sweep_deg) * 0.35, 0.0)
	if not clockwise:
		mi.scale = Vector3(-1.0, 1.0, 1.0)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "rotation:y", yaw + dirn * deg_to_rad(sweep_deg) * 0.25, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, dur * 1.4).set_delay(dur * 0.35)
	tw.chain().tween_callback(mi.queue_free)


## 줄 수 (lanes) 만큼 가로로 놓인 꼭짓점 띠 (verts[i * lanes + k]) 를 삼각형으로 잇는다.
static func _strip_mesh(verts: PackedVector3Array, cols: PackedColorArray, lanes: int, closed: bool = false) -> ArrayMesh:
	var n: int = verts.size() / lanes
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in n - 1 + (1 if closed else 0):
		var j: int = (i + 1) % n
		for k: int in lanes - 1:
			var a: int = i * lanes + k
			var b: int = j * lanes + k
			idx.append_array([a, b, b + 1, a, b + 1, a + 1])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


## SurfaceTool 에 4개씩 넣은 꼭짓점 (in0 out0 out1 in1) 을 삼각형 둘로 잇는다.
static func _quads_to_mesh(st: SurfaceTool) -> ArrayMesh:
	var arr: Array = st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = PackedInt32Array()
	for q: int in verts.size() / 4:
		var b: int = q * 4
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


## 땅 위로 퍼지는 빛 고리 (회전 베기 · 내려치기 · 치유).
static func ring_wave(parent: Node, at: Vector3, color: Color, radius: float, dur: float = 0.45, width: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var seg: int = 64
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var rel: float = width / maxf(radius, 0.1)
	for i: int in seg:
		var a: float = TAU * float(i) / float(seg)
		for k: int in 3:
			var r: float = 1.0 - rel * (1.0 - float(k) * 0.5)
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
			cols.append(Color(color.lightened(0.35), 0.9) if k == 1 else Color(color, 0.0))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _strip_mesh(verts, cols, 3, true)
	mi.material_override = ribbon_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at + Vector3(0.0, 0.06, 0.0)
	mi.scale = Vector3.ONE * radius * 0.25
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, dur).set_delay(dur * 0.3)
	tw.chain().tween_callback(mi.queue_free)


## 빛줄기 (관통 사격): from → to 로 가로 · 세로 두 장 띠, 굵었다가 가늘어지며 사라진다.
static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, width: float = 0.35, dur: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree() or from.distance_to(to) < 0.05:
		return
	var len: float = from.distance_to(to)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane: int in 2:
		var side: Vector3 = Vector3(width * 0.5, 0.0, 0.0) if plane == 0 else Vector3(0.0, width * 0.5, 0.0)
		for half: int in 2:
			var s: Vector3 = side if half == 0 else -side
			st.set_color(Color(color, 0.0))
			st.add_vertex(s)
			st.set_color(Color(color.lightened(0.6), 1.0))
			st.add_vertex(Vector3.ZERO)
			st.set_color(Color(color.lightened(0.6), 0.6))
			st.add_vertex(Vector3(0.0, 0.0, -len))
			st.set_color(Color(color, 0.0))
			st.add_vertex(s + Vector3(0.0, 0.0, -len))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _quads_to_mesh(st)
	mi.material_override = ribbon_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.look_at_from_position(from, to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.15, 0.15, 1.0), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "transparency", 1.0, dur)
	tw.chain().tween_callback(mi.queue_free)
