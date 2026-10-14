class_name SupplyField
extends Node3D
## v0.27 보급 상자 (그림만, 판정은 서버 supply · supply_land · supply_gone): 밤에 헬기가 떨어뜨리는 낙하산 상자.
## 헬기 그림자가 지나가며 상자를 떨어뜨리고, 상자는 서버가 정한 시각에 딱 땅에 닿는다 (쿵 · 먼지).
## 땅에 닿은 뒤에는 낙하산이 옆으로 접혀 눕고, 빨간 신호탄 기둥이 하늘로 솟아 (맥박) 멀리서도 보인다 (붉은 불빛).
## 누가 열면 뚜껑이 튀어 오르고 사라진다. HUD 화살표 · 거리는 SurvivalController 가 nearest 로 그린다.

const CLAY: Material = preload("res://assets/materials/foliage.tres")
const GLOW: Material = preload("res://assets/materials/lamp_glow.tres")
## 떨어지는 높이 · 헬기 그림자 빠르기 (m/s) · 보이는 거리.
const DROP_H: float = 26.0
const SHADOW_SPEED: float = 16.0
const SHADOW_SHOW: float = 40.0
## 신호탄 기둥 높이 · 맥박 주기 (초).
const BEAM_H: float = 34.0
const BLINK_S: float = 0.9
## 상자 크기.
const SIZE: Vector3 = Vector3(1.1, 0.8, 0.8)

const OLIVE: Color = Color("#5E6B3A")
const OLIVE_DARK: Color = Color("#424B28")
const STRAP: Color = Color("#2C2F26")
const STRIPE: Color = Color("#E8C23A")
const SHADOW: Color = Color("#2A2E33")

class Crate:
	var id: String = ""
	var root: Node3D
	var box: Node3D
	var lid: Node3D
	var chute: Node3D
	var beam: Node3D
	var light: OmniLight3D
	var shadow: Node3D
	var rotor: Node3D
	var ground: Vector3 = Vector3.ZERO
	var land_ms: int = 0
	var fall_ms: int = 9000
	var dir: Vector3 = Vector3.FORWARD
	var landed: bool = false
	var land_t: float = 0.0
	## 열려서 사라지는 중 (초, < 0 이면 아직).
	var gone_t: float = -1.0

var _crates: Dictionary[String, Crate] = {}
static var _beam_material: ShaderMaterial = null


func _ready() -> void:
	name = "Supply"
	Net.supply_changed.connect(_on_changed)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync())
	_sync.call_deferred()


## 가장 가까운 상자 자리 (없으면 Vector3.INF). landed_only 면 땅에 닿은 것만.
func nearest(pos: Vector3, landed_only: bool = false) -> String:
	var best: String = ""
	var best_d: float = INF
	for id: String in Net.supply:
		if landed_only and Time.get_ticks_msec() < int(Net.supply[id]["land"]):
			continue
		var d: float = Vector2(float(Net.supply[id]["x"]) - pos.x, float(Net.supply[id]["z"]) - pos.z).length()
		if d < best_d:
			best_d = d
			best = id
	return best


func crate_position(id: String) -> Vector3:
	var c: Crate = _crates.get(id)
	if c != null:
		return c.ground
	if Net.supply.has(id):
		return Vector3(float(Net.supply[id]["x"]), 0.0, float(Net.supply[id]["z"]))
	return Vector3.INF


func _sync() -> void:
	for id: String in _crates.keys():
		if not Net.supply.has(id):
			_crates[id].root.queue_free()
			_crates.erase(id)
	for id: String in Net.supply:
		if not _crates.has(id):
			_add(id)


func _on_changed(id: String) -> void:
	if not Net.supply.has(id):
		var c: Crate = _crates.get(id)
		if c != null and c.gone_t < 0.0:
			c.gone_t = 0.0
			Puff.burst(self, c.ground + Vector3(0.0, 0.5, 0.0), Color(0.86, 0.8, 0.6, 0.9), 10, 0.8, 0.4, 0.12, 0.6)
			Audio.play_at("kick_latch", c.ground, -4.0, 1.2)
		return
	if not _crates.has(id):
		_add(id)
	else:
		_crates[id].land_ms = int(Net.supply[id]["land"])


func _add(id: String) -> void:
	var info: Dictionary = Net.supply[id]
	var c: Crate = Crate.new()
	c.id = id
	c.land_ms = int(info["land"])
	c.fall_ms = maxi(1500, c.land_ms - Time.get_ticks_msec())
	var at: Vector3 = Vector3(float(info["x"]), 0.0, float(info["z"]))
	c.root = Node3D.new()
	c.root.name = "Crate_%s" % id
	add_child(c.root)
	c.ground = Vector3(at.x, _ground_y(at), at.z)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id)
	c.dir = Basis(Vector3.UP, rng.randf() * TAU) * Vector3.FORWARD
	_build(c, rng.randf() * TAU)
	_crates[id] = c
	# 이미 땅에 있던 상자 (welcome) 는 바로 내려놓는다.
	if Time.get_ticks_msec() >= c.land_ms:
		_settle(c, false)


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for id: String in _crates.keys():
		var c: Crate = _crates[id]
		if c.gone_t >= 0.0:
			c.gone_t += delta
			c.lid.position = Vector3(0.6 * minf(c.gone_t * 2.0, 1.0), SIZE.y + sin(minf(c.gone_t * 2.0, 1.0) * PI) * 0.6, 0.0)
			c.lid.rotation.z = minf(c.gone_t * 2.0, 1.0) * 1.3
			c.beam.visible = false
			c.light.visible = false
			c.box.scale = Vector3.ONE * clampf(1.6 - c.gone_t, 0.01, 1.0)
			if c.gone_t > 1.6:
				c.root.queue_free()
				_crates.erase(id)
			continue
		# 헬기 그림자: 떨어뜨리는 순간 위를 지나간다.
		var drop_at: int = c.land_ms - c.fall_ms
		var along: float = float(now - drop_at) / 1000.0 * SHADOW_SPEED
		c.shadow.visible = absf(along) < SHADOW_SHOW
		if c.shadow.visible:
			c.shadow.global_position = c.ground + c.dir * along + Vector3(0.0, 0.05, 0.0)
			c.shadow.global_basis = Basis(Vector3.UP, atan2(-c.dir.x, -c.dir.z))
			c.rotor.rotation.y += delta * 22.0
		if not c.landed:
			if now < drop_at:
				c.box.visible = false
				continue
			c.box.visible = true
			var k: float = clampf(float(now - drop_at) / float(c.fall_ms), 0.0, 1.0)
			c.box.position = c.ground + Vector3(0.0, DROP_H * (1.0 - k), 0.0)
			c.box.rotation = Vector3(0.0, c.box.rotation.y + delta * 0.4, sin(float(now) / 700.0) * 0.08)
			if k >= 1.0:
				_settle(c, true)
			continue
		c.land_t += delta
		# 낙하산이 옆으로 쓰러지며 접힌다.
		c.chute.rotation.z = minf(c.land_t * 1.6, 1.45)
		c.chute.scale = Vector3.ONE * maxf(0.35, 1.0 - c.land_t * 0.5)
		# 신호탄 맥박 (굵기 · 불빛).
		var pulse: float = 0.5 + 0.5 * sin(float(now) / 1000.0 * TAU / BLINK_S)
		c.beam.scale = Vector3(0.7 + pulse * 0.6, 1.0, 0.7 + pulse * 0.6)
		c.light.light_energy = 1.4 + pulse * 1.6 + sin(float(now) / 60.0) * 0.3


## 땅에 닿았다 (또는 이미 땅에 있었다): 상자를 바닥에 놓고 신호탄을 켠다.
func _settle(c: Crate, impact: bool) -> void:
	c.landed = true
	c.box.visible = true
	c.box.global_position = c.ground
	c.box.rotation = Vector3(0.0, c.box.rotation.y, 0.0)
	c.beam.visible = true
	c.light.visible = true
	if impact:
		Puff.burst(self, c.ground + Vector3(0.0, 0.2, 0.0), Color(0.8, 0.74, 0.6, 0.9), 14, 1.2, 0.35, 0.14, 0.7)
		Audio.play_at("kick_latch", c.ground, -2.0, 0.6)
	else:
		c.land_t = 10.0


func _build(c: Crate, yaw: float) -> void:
	# 상자 (국방색 · 검은 띠 · 노란 줄) + 뚜껑.
	c.box = Node3D.new()
	c.box.name = "Box"
	c.root.add_child(c.box)
	c.box.position = c.ground + Vector3(0.0, DROP_H, 0.0)
	c.box.rotation.y = yaw
	var b: BoxBatch = BoxBatch.new()
	b.box(Vector3(0.0, SIZE.y * 0.5, 0.0), SIZE, OLIVE)
	for x: float in [-0.32, 0.32]:
		b.box(Vector3(x, SIZE.y * 0.5, 0.0), Vector3(0.1, SIZE.y + 0.02, SIZE.z + 0.03), STRAP)
	b.box(Vector3(0.0, SIZE.y * 0.62, 0.0), Vector3(SIZE.x + 0.02, 0.07, SIZE.z + 0.02), STRIPE)
	for z: float in [-1.0, 1.0]:
		b.box(Vector3(0.0, 0.08, z * SIZE.z * 0.42), Vector3(SIZE.x + 0.06, 0.12, 0.1), OLIVE_DARK)
	_mesh(c.box, b)
	c.lid = Node3D.new()
	c.lid.name = "Lid"
	c.lid.position = Vector3(0.0, SIZE.y, 0.0)
	c.box.add_child(c.lid)
	var lb: BoxBatch = BoxBatch.new()
	lb.box(Vector3(0.0, 0.04, 0.0), Vector3(SIZE.x + 0.08, 0.08, SIZE.z + 0.08), OLIVE_DARK)
	lb.box(Vector3(0.0, 0.09, 0.0), Vector3(0.22, 0.03, 0.22), STRIPE)
	_mesh(c.lid, lb)
	# 낙하산 (주황 · 하양 돔) · 줄 — 상자에 매달려 함께 떨어진다.
	c.chute = Node3D.new()
	c.chute.name = "Parachute"
	c.chute.position = Vector3(0.0, SIZE.y, 0.0)
	c.box.add_child(c.chute)
	var st: SurfaceTool = ClayMesh.begin()
	var r: float = 1.5
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 3.0, 0.0), Vector3(r, r * 0.42, r), Color("#F08A2C"), 14, 5)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 3.05, 0.0), Vector3(r * 0.55, r * 0.28, r * 0.55), Color("#F4F0E8"), 10, 4)
	for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		ClayMesh.add_rod(st, Vector3(corner.x * SIZE.x * 0.45, 0.0, corner.z * SIZE.z * 0.45), Vector3(corner.x * r * 0.8, 2.9, corner.z * r * 0.8), 0.014, 0.014, Color("#E8E4DA"), 4)
	var chute: MeshInstance3D = MeshInstance3D.new()
	chute.mesh = ClayMesh.commit(st)
	chute.material_override = CLAY
	chute.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.chute.add_child(chute)
	# 신호탄: 상자 곁 막대 + 하늘로 솟는 붉은 기둥 · 붉은 불빛.
	c.beam = Node3D.new()
	c.beam.name = "Flare"
	c.beam.position = c.ground + Vector3(0.75, 0.0, 0.0)
	c.root.add_child(c.beam)
	var bst: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(bst, Vector3(0.0, 0.0, 0.0), Vector3(0.0, BEAM_H, 0.0), 0.16, 0.05, Color.WHITE, 6)
	ClayMesh.add_ellipsoid(bst, Vector3(0.0, 0.35, 0.0), Vector3(0.14, 0.14, 0.14), Color.WHITE, 8, 4)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.mesh = ClayMesh.commit(bst)
	beam.material_override = _beam()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.beam.add_child(beam)
	c.beam.visible = false
	c.light = OmniLight3D.new()
	c.light.light_color = Color("#FF4A3A")
	c.light.omni_range = 9.0
	c.light.light_energy = 2.4
	c.light.shadow_enabled = false
	c.light.position = Vector3(0.0, 0.8, 0.0)
	c.light.visible = false
	c.beam.add_child(c.light)
	# 헬기 그림자 (위에서 본 몸통 · 꼬리 · 회전날개).
	c.shadow = Node3D.new()
	c.shadow.name = "HeliShadow"
	c.root.add_child(c.shadow)
	var sb: BoxBatch = BoxBatch.new()
	sb.box(Vector3.ZERO, Vector3(1.8, 0.02, 3.8), SHADOW)
	sb.box(Vector3(0.0, 0.0, 3.8), Vector3(0.4, 0.02, 4.0), SHADOW)
	sb.box(Vector3(0.0, 0.0, 5.7), Vector3(1.5, 0.02, 0.32), SHADOW)
	_mesh(c.shadow, sb)
	c.rotor = Node3D.new()
	c.rotor.position = Vector3(0.0, 0.01, -0.2)
	c.shadow.add_child(c.rotor)
	var rb: BoxBatch = BoxBatch.new()
	for i: int in 2:
		rb.box(Vector3.ZERO, Vector3(10.0, 0.02, 0.3), SHADOW, Basis(Vector3.UP, PI * 0.5 * float(i)))
	_mesh(c.rotor, rb)
	c.shadow.visible = false


func _mesh(parent: Node3D, b: BoxBatch) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = CLAY
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 신호탄 기둥: 등불 머티리얼(같은 셰이더)을 붉게.
static func _beam() -> ShaderMaterial:
	if _beam_material == null:
		_beam_material = (GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		_beam_material.set_shader_parameter("albedo", Color(1.0, 0.35, 0.28))
		_beam_material.set_shader_parameter("emission", Color(1.0, 0.22, 0.15))
		_beam_material.set_shader_parameter("emission_energy", 2.6)
	return _beam_material


func _ground_y(at: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 6.0, at.z), Vector3(at.x, -3.0, at.z))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() and (hit["position"] as Vector3).y < 0.6 else 0.0
