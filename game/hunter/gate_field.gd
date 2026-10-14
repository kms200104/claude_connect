class_name GateField
extends Node3D
## v0.28 게이트 (그림만, 판정은 서버 gates.js): 도시에 열린 균열.
## 땅 위에 선 커다란 타원 고리(등급 색으로 빛남)와 안쪽에서 소용돌이치는 막, 둘레를 도는 마석 조각, 땅의 갈라진 금, 등급 색 불빛.
## 머리 위 글자 "E급 게이트 · 남은 시간". 공략 중이면 바닥에 공략 구역 고리(붉은 점선), 던전 브레이크면 붉게 맥동하며 커진다.
## 공략되거나 닫히면 줄어들며 사라진다.

const GLOW: Material = preload("res://assets/materials/lamp_glow.tres")
const CLAY: Material = preload("res://assets/materials/foliage.tres")
## 고리 크기 (반지름 · 굵기, m) · 바닥에서 띄운 높이.
const RING_R: float = 1.7
const RING_T: float = 0.22
const LIFT: float = 2.3
const BREAK_COLOR: Color = Color("#FF3A2A")

class Portal:
	var id: String = ""
	var root: Node3D
	var ring: MeshInstance3D
	var veil: Node3D
	var veil_inner: Node3D
	var shards: Node3D
	var arena: Node3D
	var light: OmniLight3D
	var label: Label3D
	var color: Color = Color.WHITE
	var st: String = ""
	var gone_t: float = -1.0

var _portals: Dictionary[String, Portal] = {}
static var _materials: Dictionary[String, ShaderMaterial] = {}
var _time: float = 0.0


func _ready() -> void:
	name = "Gates"
	Net.gate_changed.connect(_on_changed)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync())
	_sync.call_deferred()


func portal_position(id: String) -> Vector3:
	if not Net.gates.has(id):
		return Vector3.INF
	return Vector3(float(Net.gates[id]["x"]), 0.0, float(Net.gates[id]["z"]))


## 가장 가까운 게이트 id (없으면 빈 글자).
func nearest(pos: Vector3) -> String:
	var best: String = ""
	var best_d: float = INF
	for id: String in Net.gates:
		var d: float = Vector2(float(Net.gates[id]["x"]) - pos.x, float(Net.gates[id]["z"]) - pos.z).length()
		if d < best_d:
			best_d = d
			best = id
	return best


func _sync() -> void:
	for id: String in _portals.keys():
		if not Net.gates.has(id):
			_portals[id].root.queue_free()
			_portals.erase(id)
	for id: String in Net.gates:
		_on_changed(id)


func _on_changed(id: String) -> void:
	if not Net.gates.has(id):
		var gone: Portal = _portals.get(id)
		if gone != null and gone.gone_t < 0.0:
			gone.gone_t = 0.0
			Puff.burst(self, gone.root.global_position + Vector3(0.0, LIFT, 0.0), Color(gone.color, 0.9), 18, 2.2, 0.6, 0.18, 0.9)
			Audio.play_at("twinkle", gone.root.global_position, -2.0, 0.6)
		return
	var p: Portal = _portals.get(id)
	if p == null:
		p = _build(id)
		_portals[id] = p
		Audio.play_at("twinkle", p.root.global_position, 0.0, 0.5)
	var st: String = str(Net.gates[id]["st"])
	if st != p.st:
		p.st = st
		var c: Color = BREAK_COLOR if st == "break" else p.color
		p.ring.material_override = _material(c)
		(p.veil.get_child(0) as MeshInstance3D).material_override = _material(c.lerp(Color("#2A0E5A"), 0.62))
		p.light.light_color = c
		p.arena.visible = st == "raid"


func _process(delta: float) -> void:
	_time += delta
	var now: int = Time.get_ticks_msec()
	for id: String in _portals.keys():
		var p: Portal = _portals[id]
		if p.gone_t >= 0.0:
			p.gone_t += delta
			p.root.scale = Vector3.ONE * maxf(0.01, 1.0 - p.gone_t * 1.4)
			if p.gone_t > 0.75:
				p.root.queue_free()
				_portals.erase(id)
			continue
		var breaking: bool = p.st == "break"
		var pulse: float = 0.5 + 0.5 * sin(_time * (5.0 if breaking else 2.2))
		p.veil.rotation.z += delta * (2.6 if breaking else 1.2)
		p.veil_inner.rotation.z -= delta * (3.4 if breaking else 1.8)
		p.veil.scale = Vector3.ONE * (0.96 + pulse * 0.06)
		p.shards.rotation.y += delta * 0.9
		p.light.light_energy = 1.6 + pulse * (2.4 if breaking else 1.2)
		var s: float = 1.0 + (pulse * 0.08 if breaking else 0.0)
		p.ring.scale = Vector3(s, s, 1.0)
		var info: Dictionary = Net.gates.get(id, {})
		if info.is_empty():
			continue
		var left: int = maxi(0, int(info["until"]) - now)
		var t: String = "%d:%02d" % [left / 60000, (left / 1000) % 60]
		match p.st:
			"raid":
				p.label.text = "%s급 게이트 · 공략 중\n%s" % [str(info["rank"]), "우두머리!" if bool(info["boss"]) else "웨이브 %d/%d" % [int(info["wave"]) + 1, int(info["waves"])]]
			"break":
				p.label.text = "던전 브레이크!\n%s" % t
			_:
				p.label.text = "%s급 게이트\n브레이크까지 %s" % [str(info["rank"]), t]
		p.label.modulate = BREAK_COLOR.lightened(0.3) if breaking else p.color.lightened(0.35)


func _build(id: String) -> Portal:
	var info: Dictionary = Net.gates[id]
	var p: Portal = Portal.new()
	p.id = id
	p.color = GameData.hunter.gate_colors.get(str(info["rank"]), Color("#8FB8C8"))
	p.root = Node3D.new()
	p.root.name = "Gate_%s" % id
	add_child(p.root)
	var at: Vector3 = Vector3(float(info["x"]), 0.0, float(info["z"]))
	p.root.global_position = Vector3(at.x, _ground_y(at), at.z)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id)
	# 타원 고리 (세로로 선 토러스, 위아래로 길게). 카메라(고정 방향, 북쪽을 내려다본다)를 마주 보고 조금 뒤로 젖힌다.
	var holder: Node3D = Node3D.new()
	holder.position = Vector3(0.0, LIFT, 0.0)
	holder.rotation.x = -0.3
	holder.scale = Vector3(1.0, 1.25, 1.0)
	p.root.add_child(holder)
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_torus(st, Vector3.ZERO, RING_R, RING_T, Color.WHITE, 32, 6, Basis(Vector3.RIGHT, PI * 0.5))
	for i: int in 10:
		var a: float = TAU * float(i) / 10.0
		var tip: Vector3 = Vector3(cos(a), sin(a), 0.0) * (RING_R + 0.35)
		ClayMesh.add_rod(st, Vector3(cos(a), sin(a), 0.0) * RING_R, tip, 0.09, 0.0, Color.WHITE, 4)
	p.ring = MeshInstance3D.new()
	p.ring.mesh = ClayMesh.commit(st)
	p.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p.ring)
	# 소용돌이 막 (둘, 서로 반대로 돈다).
	p.veil = _veil(RING_R * 0.92, 0.06)
	holder.add_child(p.veil)
	p.veil_inner = _veil(RING_R * 0.55, 0.1)
	holder.add_child(p.veil_inner)
	(p.veil_inner.get_child(0) as MeshInstance3D).material_override = _material(Color("#120624"))
	# 둘레를 도는 마석 조각.
	p.shards = Node3D.new()
	p.shards.position = Vector3(0.0, LIFT, 0.0)
	p.root.add_child(p.shards)
	var sh: SurfaceTool = ClayMesh.begin()
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0
		var r: float = RING_R + 0.9 + rng.randf() * 0.6
		var c: Vector3 = Vector3(cos(a) * r, -1.0 + rng.randf() * 2.4, sin(a) * r)
		ClayMesh.add_rod(sh, c - Vector3(0.0, 0.16, 0.0), c + Vector3(0.0, 0.2, 0.0), 0.07, 0.0, Color.WHITE, 5)
		ClayMesh.add_rod(sh, c - Vector3(0.0, 0.16, 0.0), c - Vector3(0.0, 0.3, 0.0), 0.07, 0.0, Color.WHITE, 5)
	var shards: MeshInstance3D = MeshInstance3D.new()
	shards.mesh = ClayMesh.commit(sh)
	shards.material_override = _material(p.color.lightened(0.3))
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.shards.add_child(shards)
	# 땅의 갈라진 금 (어두운 판 · 가운데 그을림).
	var cb: BoxBatch = BoxBatch.new()
	cb.box(Vector3(0.0, 0.03, 0.0), Vector3(1.8, 0.02, 0.7), Color("#1E1A22"))
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0 + rng.randf() * 0.3
		var l: float = 1.4 + rng.randf() * 2.4
		cb.box(Vector3(cos(a), 0.0, sin(a)) * (l * 0.5 + 0.7) + Vector3(0.0, 0.035, 0.0), Vector3(l, 0.02, 0.07 + rng.randf() * 0.07), Color("#2A2430"), Basis(Vector3.UP, -a))
	var cracks: MeshInstance3D = MeshInstance3D.new()
	cracks.rotation.y = rng.randf() * TAU
	cracks.mesh = cb.commit()
	cracks.material_override = CLAY
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.root.add_child(cracks)
	# 공략 구역 고리 (붉은 점선).
	p.arena = Node3D.new()
	p.arena.name = "Arena"
	p.root.add_child(p.arena)
	var ab: BoxBatch = BoxBatch.new()
	var ar: float = GameData.hunter.gate_arena
	for i: int in 36:
		var a: float = TAU * float(i) / 36.0
		ab.box(Vector3(cos(a) * ar, 0.05, sin(a) * ar), Vector3(1.4, 0.03, 0.22), Color("#E8483A"), Basis(Vector3.UP, -a + PI * 0.5))
	var arena: MeshInstance3D = MeshInstance3D.new()
	arena.mesh = ab.commit()
	arena.material_override = CLAY
	arena.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.arena.add_child(arena)
	p.arena.visible = false
	# 불빛 · 글자.
	p.light = OmniLight3D.new()
	p.light.omni_range = 12.0
	p.light.shadow_enabled = false
	p.light.position = Vector3(0.0, LIFT, 0.0)
	p.root.add_child(p.light)
	p.label = Label3D.new()
	p.label.name = "GateLabel"
	p.label.font_size = 56
	p.label.pixel_size = 0.01
	p.label.outline_size = 14
	p.label.outline_modulate = Color("#10101A")
	p.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.label.no_depth_test = true
	p.label.position = Vector3(0.0, LIFT + RING_R * 1.25 + 1.2, 0.0)
	p.root.add_child(p.label)
	return p


func _veil(r: float, depth: float) -> Node3D:
	var n: Node3D = Node3D.new()
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(r, r, depth), Color.WHITE, 20, 4)
	# 소용돌이 팔 (돌 때 보이게).
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0
		ClayMesh.add_ellipsoid(st, Vector3(cos(a), sin(a), 0.0) * r * 0.45, Vector3(r * 0.42, r * 0.12, depth * 1.4), Color(0.6, 0.6, 0.7), 10, 3, Basis(Vector3.BACK, a + 0.7))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = ClayMesh.commit(st)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


## 등급 색으로 빛나는 머티리얼 (등불 셰이더 그대로, 색만).
static func _material(c: Color) -> ShaderMaterial:
	var key: String = c.to_html(false)
	if not _materials.has(key):
		var m: ShaderMaterial = (GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("albedo", c.lightened(0.2))
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_energy", 2.0)
		_materials[key] = m
	return _materials[key]


func _ground_y(at: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 6.0, at.z), Vector3(at.x, -3.0, at.z))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() and (hit["position"] as Vector3).y < 0.6 else 0.0
