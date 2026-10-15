class_name GuardField
extends Node3D
## v0.28.2 가디언 (그림만, 판정은 서버 guardians.js): 시내 둘레 초소에 선 총을 든 아군.
## 남색 방탄조끼 · 헬멧 · 소총, 초소에는 모래주머니와 작은 깃발. 크리처를 쏘면 총구가 번쩍이고 탄 자국이 크리처까지 그어진다.
## 쓰러지면 옆으로 눕고 머리 위에 "가디언 · 다시 서기까지 m:ss" (서버가 정한 세상 시간 20분 → 이 기기 시간).

const RIG: PackedScene = preload("res://game/player/character_rig.tscn")
const CLAY: Material = preload("res://assets/materials/foliage.tres")
const GLOW: Material = preload("res://assets/materials/lamp_glow.tres")

class Guard:
	var id: String = ""
	var root: Node3D
	var body: Node3D
	var rig: CharacterRig
	var tag: Label3D
	var flash: Node3D
	var down: float = 0.0

var _guards: Dictionary[String, Guard] = {}
static var _flash_material: ShaderMaterial = null


func _ready() -> void:
	name = "Guards"
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync())
	Net.guard_changed.connect(func(_id: String) -> void: _sync())
	Net.guard_shot.connect(_on_shot)
	_sync.call_deferred()


func guard_count() -> int:
	return _guards.size()


func is_down(id: String) -> bool:
	return Net.guards.has(id) and int(Net.guards[id]["until"]) > 0


func _sync() -> void:
	for id: String in Net.guards:
		if not _guards.has(id):
			_guards[id] = _build(id)


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for id: String in _guards:
		var g: Guard = _guards[id]
		var info: Dictionary = Net.guards.get(id, {})
		if info.is_empty():
			continue
		var until: int = int(info["until"])
		var lying: bool = until > 0
		g.down = move_toward(g.down, 1.0 if lying else 0.0, delta * 2.5)
		g.body.rotation.y = lerp_angle(g.body.rotation.y, float(info["yaw"]) + PI, 1.0 - exp(-8.0 * delta)) if not lying else g.body.rotation.y
		g.body.rotation.z = g.down * 1.45
		g.body.position.y = lerpf(0.72, 0.2, g.down)
		# 글자가 바뀔 때만 넣는다 (Label3D 는 글자를 넣을 때마다 메시를 다시 만든다).
		var text: String
		if lying:
			var left: int = maxi(0, until - now)
			text = "가디언 · 다시 서기까지 %d:%02d" % [left / 60000, (left / 1000) % 60]
		else:
			text = "가디언 %s" % "■".repeat(ceili(5.0 * float(info["hp"]) / maxf(float(info["max"]), 1.0)))
		if g.tag.text != text:
			g.tag.text = text
			g.tag.modulate = Color("#FF9A8A") if lying else Color("#A8D8FF")
		g.flash.visible = g.flash.visible and g.flash.get_meta("until", 0) > now


func _on_shot(info: Dictionary) -> void:
	var g: Guard = _guards.get(str(info.get("g", "")))
	if g == null:
		return
	var muzzle: Vector3 = g.flash.global_position
	var target: Vector3 = Vector3(float(info.get("x", 0.0)), 1.0, float(info.get("z", 0.0)))
	g.flash.visible = true
	g.flash.set_meta("until", Time.get_ticks_msec() + 70)
	# 탄 자국: 총구에서 크리처까지 가는 밝은 줄 (잠깐).
	var tracer: MeshInstance3D = MeshInstance3D.new()
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, 0.0, -muzzle.distance_to(target)), 0.025, 0.012, Color.WHITE, 4)
	tracer.mesh = ClayMesh.commit(st)
	tracer.material_override = _flash()
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)
	tracer.global_position = muzzle
	if muzzle.distance_to(target) > 0.1:
		tracer.look_at(target, Vector3.UP)
	get_tree().create_timer(0.08).timeout.connect(tracer.queue_free)
	Puff.burst(self, target, Color(0.55, 0.1, 0.08, 0.9), 5, 0.3, 0.2, 0.06, 0.35)
	Audio.play_at("kick_latch", muzzle, -2.0, 1.9)


func _build(id: String) -> Guard:
	var info: Dictionary = Net.guards[id]
	var g: Guard = Guard.new()
	g.id = id
	g.root = Node3D.new()
	g.root.name = "Guard_%s" % id
	add_child(g.root)
	g.root.global_position = Vector3(float(info["x"]), _ground_y(Vector3(float(info["x"]), 0.0, float(info["z"]))), float(info["z"]))
	g.rig = RIG.instantiate() as CharacterRig
	g.body = g.rig
	g.rig.scale = Vector3.ONE * 0.9
	g.rig.position = Vector3(0.0, 0.72, 0.0)
	g.root.add_child(g.rig)
	g.rig.set_look(CharacterLook.from_dict({"skin": "#E8C4A8", "hair": "#2A2420", "style": "short", "top": "#2A3A5A", "bottom": "#3A4048", "shoes": "#1E1E22", "mouth": "flat"}, Color("#2A3A5A")))
	g.rig.set_held("")
	# 헬멧 · 조끼 · 소총은 몸에 붙인다 (손 자리 근처 앞으로).
	var gear: MeshInstance3D = MeshInstance3D.new()
	gear.mesh = gear_mesh()
	gear.material_override = CLAY
	g.rig.add_child(gear)
	g.flash = Node3D.new()
	g.flash.position = Vector3(0.2, -0.2, -0.84)
	g.rig.add_child(g.flash)
	var fm: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 6
	sphere.rings = 3
	fm.mesh = sphere
	fm.material_override = _flash()
	g.flash.add_child(fm)
	g.flash.visible = false
	# 초소: 모래주머니 반원 · 깃발.
	var b: BoxBatch = BoxBatch.new()
	for i: int in 5:
		var a: float = PI * (0.15 + 0.175 * float(i)) + PI
		b.box(Vector3(cos(a) * 1.3, 0.18, sin(a) * 1.3), Vector3(0.7, 0.32, 0.4), Color("#B8A070").darkened(0.05 * float(i % 2)), Basis(Vector3.UP, -a + PI * 0.5))
	b.box(Vector3(-1.2, 1.2, 0.8), Vector3(0.06, 2.4, 0.06), Color("#8A9096"))
	b.box(Vector3(-0.92, 2.15, 0.8), Vector3(0.5, 0.34, 0.03), Color("#2A3A5A"))
	b.box(Vector3(-0.92, 2.15, 0.82), Vector3(0.16, 0.16, 0.02), Color("#E8C23A"), Basis(Vector3.BACK, PI * 0.25))
	var post: MeshInstance3D = MeshInstance3D.new()
	post.mesh = b.commit()
	post.material_override = CLAY
	g.root.add_child(post)
	g.tag = Label3D.new()
	g.tag.font_size = 40
	g.tag.pixel_size = 0.007
	g.tag.outline_size = 10
	g.tag.outline_modulate = Color("#10182A")
	g.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.tag.position = Vector3(0.0, 2.25, 0.0)
	g.root.add_child(g.tag)
	return g


## 헬멧 · 방탄조끼 · 소총 (리그 기준, 앞 = -Z).
static func gear_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var olive: Color = Color("#3E4A3A")
	var dark: Color = Color("#22262A")
	# 헬멧: 머리 윗반을 덮는 반구 + 테 (눈 · 얼굴은 드러난다).
	var dome: PackedVector2Array = PackedVector2Array()
	for i: int in 7:
		var a: float = PI * 0.5 * float(i) / 6.0
		dome.append(Vector2(cos(a), sin(a)))
	var shell: Transform3D = Transform3D(Basis.from_scale(Vector3(0.47, 0.4, 0.43)), Vector3(0.0, 0.49, 0.03))
	ClayMesh.add_lathe(st, dome, 16, shell, olive)
	ClayMesh.add_torus(st, Vector3(0.0, 0.49, 0.03), 0.46, 0.035, olive.darkened(0.2), 16, 4)
	# 방탄조끼 (가슴 · 등) · 무전기 · 이름표.
	var vest: Color = Color("#2A3A5A").darkened(0.25)
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.16, -0.2), Vector3(0.4, 0.3, 0.07), 0.3, vest)
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.16, 0.2), Vector3(0.4, 0.3, 0.07), 0.3, vest)
	ClayMesh.add_rounded_box(st, Vector3(0.11, -0.07, -0.25), Vector3(0.07, 0.11, 0.04), 0.3, dark)
	ClayMesh.add_rounded_box(st, Vector3(-0.09, -0.24, -0.245), Vector3(0.15, 0.06, 0.03), 0.3, Color("#E8C23A").darkened(0.3))
	# 소총: 앞으로 겨눈 자세 (오른손 높이에서 앞으로).
	var r: Vector3 = Vector3(0.2, -0.22, -0.24)
	ClayMesh.add_rounded_box(st, r + Vector3(0.0, 0.0, -0.18), Vector3(0.06, 0.09, 0.44), 0.3, dark)
	ClayMesh.add_rod(st, r + Vector3(0.0, 0.02, -0.4), r + Vector3(0.0, 0.02, -0.58), 0.018, 0.018, dark, 6)
	ClayMesh.add_rounded_box(st, r + Vector3(0.0, -0.09, -0.14), Vector3(0.045, 0.13, 0.07), 0.3, dark)
	ClayMesh.add_rounded_box(st, r + Vector3(0.0, -0.01, 0.1), Vector3(0.05, 0.1, 0.16), 0.3, Color("#5A4632"))
	ClayMesh.add_rounded_box(st, r + Vector3(0.0, 0.07, -0.2), Vector3(0.035, 0.045, 0.12), 0.3, dark)
	return ClayMesh.commit(st)


static func _flash() -> ShaderMaterial:
	if _flash_material == null:
		_flash_material = (GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		_flash_material.set_shader_parameter("albedo", Color("#FFF4C0"))
		_flash_material.set_shader_parameter("emission", Color("#FFC860"))
		_flash_material.set_shader_parameter("emission_energy", 3.0)
	return _flash_material


func _ground_y(at: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 6.0, at.z), Vector3(at.x, -3.0, at.z))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() and (hit["position"] as Vector3).y < 0.6 else 0.0
