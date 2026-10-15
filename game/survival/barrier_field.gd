class_name BarrierField
extends Node3D
## v0.28.2 배리어 (그림만, 판정은 서버 survival.js safeAt): 상점 · 광장 · 주요 건물 둘레의 보호막.
## 아주 옅은 하늘색 돔(투명 머티리얼 하나를 모두 같이 쓴다) · 땅에 빛나는 고리 · 둘레의 낮은 기둥(꼭대기가 빛난다).
## 밤에는 조금 더 또렷하고, 크리처가 가까이 오면 그쪽 돔이 잠깐 일렁인다.

const GLOW: Material = preload("res://assets/materials/lamp_glow.tres")
const CLAY: Material = preload("res://assets/materials/foliage.tres")
const COLOR: Color = Color("#7AD8FF")

var _domes: Array[Dictionary] = []
var _time: float = 0.0
static var _dome_material: StandardMaterial3D = null
static var _ring_material: ShaderMaterial = null


func _ready() -> void:
	name = "Barriers"
	for b: Dictionary in GameData.survival.barriers:
		_build(b)


## 배리어 수 (테스트용).
func count() -> int:
	return _domes.size()


func _process(delta: float) -> void:
	_time += delta
	var night: bool = Net.state == Net.State.ONLINE and GameData.survival.is_night(Net.game_hour())
	var base: float = 0.07 if night else 0.04
	var m: StandardMaterial3D = _dome()
	# 크리처가 가까우면 일렁인다 (가장 가까운 배리어 기준으로 한 머티리얼 전체 — 은은하게).
	var stir: float = 0.0
	for d: Dictionary in _domes:
		var c: Vector2 = d["c"]
		var r: float = d["r"]
		for id: String in Net.creatures:
			var cr: Dictionary = Net.creatures[id]
			var dist: float = Vector2(float(cr.get("x", 0.0)) - c.x, float(cr.get("z", 0.0)) - c.y).length() - r
			if dist < 4.0:
				stir = maxf(stir, 1.0 - maxf(dist, 0.0) / 4.0)
	m.albedo_color.a = base + stir * 0.08 * (0.5 + 0.5 * sin(_time * 9.0)) + 0.01 * sin(_time * 1.3)


func _build(b: Dictionary) -> void:
	var c: Vector2 = Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))
	var r: float = float(b.get("r", 10.0))
	var root: Node3D = Node3D.new()
	root.name = "Barrier_%s" % str(b.get("id", ""))
	root.position = Vector3(c.x, 0.0, c.y)
	add_child(root)
	# 돔: 납작한 반구 (안쪽에서도 보이게 양면).
	var dome: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.is_hemisphere = true
	sphere.radial_segments = 32
	sphere.rings = 8
	dome.mesh = sphere
	dome.scale = Vector3(1.0, 0.42, 1.0)
	dome.material_override = _dome()
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dome)
	# 땅의 빛 고리 (조각) · 기둥.
	var ring: BoxBatch = BoxBatch.new()
	var n: int = maxi(24, roundi(r * 3.0))
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		ring.box(Vector3(cos(a) * r, 0.04, sin(a) * r), Vector3(TAU * r / float(n) * 0.7, 0.03, 0.12), Color.WHITE, Basis(Vector3.UP, -a + PI * 0.5))
	var ring_mi: MeshInstance3D = MeshInstance3D.new()
	ring_mi.mesh = ring.commit()
	ring_mi.material_override = _ring()
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring_mi)
	var posts: BoxBatch = BoxBatch.new()
	var tips: BoxBatch = BoxBatch.new()
	var pn: int = maxi(6, roundi(r / 2.5))
	for i: int in pn:
		var a: float = TAU * (float(i) + 0.5) / float(pn)
		var p: Vector3 = Vector3(cos(a) * r, 0.0, sin(a) * r)
		posts.box(p + Vector3(0.0, 0.45, 0.0), Vector3(0.16, 0.9, 0.16), Color("#4A5058"))
		tips.box(p + Vector3(0.0, 0.95, 0.0), Vector3(0.2, 0.12, 0.2), Color.WHITE)
	var posts_mi: MeshInstance3D = MeshInstance3D.new()
	posts_mi.mesh = posts.commit()
	posts_mi.material_override = CLAY
	root.add_child(posts_mi)
	var tips_mi: MeshInstance3D = MeshInstance3D.new()
	tips_mi.mesh = tips.commit()
	tips_mi.material_override = _ring()
	tips_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tips_mi)
	_domes.append({"c": c, "r": r, "node": root})


static func _dome() -> StandardMaterial3D:
	if _dome_material == null:
		_dome_material = StandardMaterial3D.new()
		_dome_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dome_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dome_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_dome_material.albedo_color = Color(COLOR, 0.05)
		_dome_material.no_depth_test = false
	return _dome_material


static func _ring() -> ShaderMaterial:
	if _ring_material == null:
		_ring_material = (GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		_ring_material.set_shader_parameter("albedo", COLOR.lightened(0.3))
		_ring_material.set_shader_parameter("emission", COLOR)
		_ring_material.set_shader_parameter("emission_energy", 1.6)
	return _ring_material
