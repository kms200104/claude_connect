class_name FootFx
extends Node3D
## 발걸음 파티클 (v0.13.3). 발이 땅에 닿을 때마다(Footsteps 가 소리를 내는 박자) 발밑 재질에 맞는 것이 튄다:
##   dirt  흙길 — 갈색 흙먼지가 뭉게 피어오르고 작은 흙 알갱이가 톡
##   sand  모래사장 — 밝은 모래 먼지 + 모래알
##   grass 풀밭 — 풀잎 조각이 팔랑 튀어 오른다
##   water 물기(바닷가 젖은 모래 · 여울 · 비 오는 날 흙·돌) — 물방울이 튀고 발밑에 동그란 물결
##   stone 돌 광장 — 옅은 회색 먼지 조금
##   wood  선착장·상점 안 — 아주 옅은 먼지 한 줌
## 걸으면 살짝(몇 알, 낮게), 달리면 세게(많이, 높고 멀리, 크게). 발 뒤쪽으로 차올리듯 튄다.
## 재질 × 걷기/달리기마다 한 번에 하나씩 쓰는 CPUParticles3D 를 몇 개 돌려 쓴다 (모바일에서도 가볍게).
## 화질이 절약(low)이면 알갱이 수를 반으로.

## 재질별 색 (가운데 · 가장자리). 알갱이마다 이 사이에서 고른다.
const COLORS: Dictionary[String, Array] = {
	"dirt": [Color("#A9805A"), Color("#C9A27A")],
	"sand": [Color("#E6D3A3"), Color("#F3E6C4")],
	"grass": [Color("#3F8A2E"), Color("#7CBF3E")],
	"water": [Color("#D8F1FF"), Color("#9FD3F2")],
	"stone": [Color("#BDB8AE"), Color("#DAD6CE")],
	"wood": [Color("#C9AE88"), Color("#E3D2B6")],
}
## 같은 종류의 파티클 묶음을 몇 개 돌려 쓸지 (두 발 + 상대 플레이어).
const POOL: int = 4

static var _instance: FootFx = null

var _pools: Dictionary[String, Array] = {}
var _next: Dictionary[String, int] = {}
var _ripple_mesh: Mesh = null


## 발밑에 한 걸음. surface = Footsteps.surface_of 의 재질(+ 모래 · 비 물기 구분은 여기서), back = 걸어가는 반대쪽(수평 단위벡터).
static func step(at: Vector3, surface: String, running: bool, back: Vector3) -> void:
	var fx: FootFx = _shared()
	if fx != null:
		fx.emit_step(at, surface, running, back)


static func _shared() -> FootFx:
	if _instance != null and is_instance_valid(_instance):
		return _instance if _instance.is_inside_tree() else null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	# 처음 한 번은 다음 프레임에 붙는다 (장면을 세우는 중에도 안전하게) — 그 사이의 걸음은 건너뛴다.
	_instance = FootFx.new()
	_instance.name = "FootFx"
	tree.root.add_child.call_deferred(_instance)
	return null


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func emit_step(at: Vector3, surface: String, running: bool, back: Vector3) -> void:
	if not COLORS.has(surface):
		return
	var key: String = "%s_%s" % [surface, "run" if running else "walk"]
	var p: CPUParticles3D = _take(key, surface, running)
	# 발 뒤쪽으로 조금 비켜서, 걸어가는 반대쪽으로 차올린다.
	p.global_position = at + back * (0.12 if running else 0.06) + Vector3.UP * 0.03
	var flat: Vector3 = Vector3(back.x, 0.0, back.z)
	p.direction = (flat.normalized() * (0.55 if running else 0.35) + Vector3.UP).normalized() if flat.length() > 0.01 else Vector3.UP
	p.restart()
	if surface == "water":
		_ripple(at, running)


## 이 종류의 파티클 묶음에서 다음 것 (없으면 만든다).
func _take(key: String, surface: String, running: bool) -> CPUParticles3D:
	if not _pools.has(key):
		var list: Array = []
		for i: int in POOL:
			var p: CPUParticles3D = _make(surface, running)
			add_child(p)
			list.append(p)
		_pools[key] = list
		_next[key] = 0
	var i: int = _next[key]
	_next[key] = (i + 1) % POOL
	return _pools[key][i]


func _make(surface: String, running: bool) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.07 if running else 0.04
	var low: bool = Quality.preset_id == "low"
	var colors: Array = COLORS[surface]
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.95))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.55, Color(1, 1, 1, 0.75))
	p.color_ramp = ramp
	var tint: Gradient = Gradient.new()
	tint.set_color(0, colors[0])
	tint.set_color(1, colors[1])
	p.color_initial_ramp = tint
	var scale_curve: Curve = Curve.new()
	p.mesh = _particle_mesh(surface)
	match surface:
		"dirt", "sand", "stone", "wood":
			# 뭉게 먼지: 천천히 퍼지며 커지고, 거의 떨어지지 않는다.
			var strong: float = 1.0 if surface == "dirt" or surface == "sand" else 0.45
			p.amount = int((10 if running else 4) * strong) + 1
			p.lifetime = 0.75 if running else 0.5
			p.spread = 70.0
			p.initial_velocity_min = 0.25 if running else 0.12
			p.initial_velocity_max = (0.9 if running else 0.35) * (0.7 + 0.3 * strong)
			p.gravity = Vector3(0.0, 0.25, 0.0)
			p.damping_min = 1.5
			p.damping_max = 2.5
			p.scale_amount_min = 0.7 if running else 0.5
			p.scale_amount_max = (1.6 if running else 0.9) * (0.6 + 0.4 * strong)
			scale_curve.add_point(Vector2(0.0, 0.5))
			scale_curve.add_point(Vector2(1.0, 1.3))
		"grass":
			# 풀잎 조각: 톡 튀어 올라 빙글 돌며 떨어진다.
			p.amount = 12 if running else 4
			p.lifetime = 0.7 if running else 0.5
			p.spread = 40.0
			p.initial_velocity_min = 0.6 if running else 0.35
			p.initial_velocity_max = 1.7 if running else 0.7
			p.gravity = Vector3(0.0, -4.5, 0.0)
			p.angular_velocity_min = -360.0
			p.angular_velocity_max = 360.0
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.3 if running else 1.0
			scale_curve.add_point(Vector2(0.0, 1.0))
			scale_curve.add_point(Vector2(1.0, 0.6))
		"water":
			# 물방울: 위로 튀었다 떨어진다.
			p.amount = 14 if running else 5
			p.lifetime = 0.55 if running else 0.4
			p.spread = 30.0
			p.initial_velocity_min = 0.9 if running else 0.5
			p.initial_velocity_max = 2.2 if running else 1.0
			p.gravity = Vector3(0.0, -9.0, 0.0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3 if running else 0.9
			scale_curve.add_point(Vector2(0.0, 1.0))
			scale_curve.add_point(Vector2(1.0, 0.4))
	p.scale_amount_curve = scale_curve
	if low:
		p.amount = maxi(1, p.amount / 2)
	return p


## 재질별 알갱이 모양: 먼지는 동그란 뭉게(가장자리가 흐린 원), 풀은 길쭉한 잎, 물은 작은 방울.
func _particle_mesh(surface: String) -> Mesh:
	var quad: QuadMesh = QuadMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	# 파티클 색은 sRGB 로 준 값 (안 하면 하얗게 바랜다).
	mat.vertex_color_is_srgb = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _soft_dot() if surface != "grass" else _leaf()
	match surface:
		"grass":
			quad.size = Vector2(0.07, 0.13)
		"water":
			quad.size = Vector2(0.07, 0.07)
		_:
			quad.size = Vector2(0.22, 0.22)
	quad.material = mat
	return quad


## 발밑에 퍼지는 동그란 물결 (물기 있는 바닥).
func _ripple(at: Vector3, running: bool) -> void:
	if _ripple_mesh == null:
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.09
		torus.outer_radius = 0.11
		torus.rings = 16
		torus.ring_segments = 4
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.92, 0.98, 1.0, 0.7)
		torus.material = mat
		_ripple_mesh = torus
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.mesh = _ripple_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.transparency = 0.2
	add_child(ring)
	ring.global_position = Vector3(at.x, at.y + 0.02, at.z)
	ring.scale = Vector3(0.6, 0.3, 0.6)
	var grow: float = 3.2 if running else 2.0
	var t: Tween = ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(grow, 0.3, grow), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "transparency", 1.0, 0.5)
	t.chain().tween_callback(ring.queue_free)


static var _dot_tex: Texture2D = null
static var _leaf_tex: Texture2D = null


## 가장자리가 흐린 동그라미 (먼지 · 물방울).
static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g: GradientTexture2D = GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad: Gradient = Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		grad.add_point(0.55, Color(1, 1, 1, 0.8))
		g.gradient = grad
		g.width = 32
		g.height = 32
		_dot_tex = g
	return _dot_tex


## 끝이 뾰족한 풀잎 (위아래로 길쭉, 가운데가 진한 잎맥).
static func _leaf() -> Texture2D:
	if _leaf_tex == null:
		var img: Image = Image.create(16, 32, false, Image.FORMAT_RGBA8)
		for y: int in 32:
			var t: float = float(y) / 31.0
			# 아래(밑동)는 넓고 위(끝)는 뾰족.
			var half: float = lerpf(6.5, 0.5, t) * (1.0 - pow(1.0 - t, 6.0) * 0.4)
			for x: int in 16:
				var d: float = absf(float(x) - 7.5)
				var a: float = clampf(half - d + 0.5, 0.0, 1.0)
				var shade: float = 0.82 if d < 1.0 else 1.0
				img.set_pixel(x, 31 - y, Color(shade, shade, shade, a))
		_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex
