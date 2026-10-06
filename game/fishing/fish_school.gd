class_name FishSchool
extends Node3D
## 낚시터 물고기 그림자 (v13). 서버가 알려 주는 물고기들(Net.fishes)을 물 밑 그림자로 그린다.
## 모양은 모두 같고(어떤 물고기인지는 모른다) 몸 크기(S·M·L)만큼 크기가 다르며, 희귀할수록 둘레에 아우라가 감돈다
##   (조금 귀함: 맑은 하늘빛 · 아주 귀함: 금빛 + 반짝임). 서버 위치를 부드럽게 따라가며 헤엄치는 쪽으로 꼬리를 흔든다.
## 내가 낚는 중인 물고기(hidden_id)는 FishShadow 가 이어받아 그리므로 여기서는 숨긴다.

## 몸 크기별 그림자 배율 (서버 swimmers.js SIZE_SCALE 과 같다).
const SIZE_SCALE: Dictionary[String, float] = {"S": 0.75, "M": 1.0, "L": 1.35}
const SHADOW_COLOR: Color = Color(0.03, 0.08, 0.12)
const AURA_COLORS: Dictionary[String, Color] = {"uncommon": Color(0.62, 0.9, 1.0), "rare": Color(1.0, 0.82, 0.32)}

@export_range(0.05, 1.0, 0.05) var opacity: float = 0.5
## 클수록 서버 위치에 딱 붙는다.
@export_range(1.0, 20.0, 0.5) var follow_smoothing: float = 5.0

## 내가 낚는 중이라 FishShadow 가 대신 그리는 물고기 id.
var hidden_id: String = ""

var _nodes: Dictionary[String, Node3D] = {}
var _state: Dictionary[String, Dictionary] = {}
var _time: float = 0.0
static var _body_material: StandardMaterial3D = null
static var _aura_materials: Dictionary[String, StandardMaterial3D] = {}
static var _aura_mesh: QuadMesh = null
static var _sparkle_mesh: SphereMesh = null


func _ready() -> void:
	Net.fishes_updated.connect(_on_fishes)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _clear())
	Net.state_changed.connect(func(st: int) -> void:
		if st != Net.State.ONLINE:
			_clear())


## 보이는 물고기 수 (테스트·캡처용).
func count(spot_id: String = "") -> int:
	if spot_id.is_empty():
		return _nodes.size()
	return _state.values().filter(func(s: Dictionary) -> bool: return s["spot"] == spot_id).size()


## 물고기 하나의 지금 모습 {spot, position, yaw, size, rarity, st} (없으면 빈 사전).
func fish(id: String) -> Dictionary:
	if not _nodes.has(id):
		return {}
	var st: Dictionary = _state[id].duplicate()
	st["position"] = _nodes[id].global_position
	st["yaw"] = _nodes[id].rotation.y
	return st


## 던질 만한 물고기 (낚시 어시스트): from 에서 min_d~max_d 안, 아무도 낚고 있지 않은 것 가운데
## 캐릭터가 바라보는 쪽(facing)에 가까울수록, 가까울수록 먼저. 없으면 "".
func pick_for_cast(spot_id: String, from: Vector3, facing: Vector3, min_d: float, max_d: float) -> String:
	var best: String = ""
	var best_score: float = INF
	var flat_facing: Vector2 = Vector2(facing.x, facing.z).normalized()
	for id: String in _nodes:
		var st: Dictionary = _state[id]
		if st["spot"] != spot_id or str(st["st"]) != "roam" or int(st["o"]) != 0:
			continue
		var p: Vector3 = _nodes[id].global_position
		var to: Vector2 = Vector2(p.x - from.x, p.z - from.z)
		var d: float = to.length()
		if d < min_d or d > max_d:
			continue
		var angle: float = absf(flat_facing.angle_to(to)) if flat_facing != Vector2.ZERO else 0.0
		var score: float = d * 0.35 + angle * 2.0
		if score < best_score:
			best_score = score
			best = id
	return best


func _on_fishes(spot_id: String, list: Array[Dictionary]) -> void:
	var height: float = _water_height(spot_id)
	var seen: Dictionary[String, bool] = {}
	for f: Dictionary in list:
		var id: String = str(f.get("id", ""))
		seen[id] = true
		var node: Node3D = _nodes.get(id)
		var target: Vector3 = Vector3(float(f.get("x", 0.0)), height, float(f.get("z", 0.0)))
		if node == null:
			node = make_visual(str(f.get("s", "M")), str(f.get("r", "common")))
			node.name = "Fish_%s" % id
			add_child(node)
			node.global_position = target
			node.rotation.y = float(f.get("yaw", 0.0))
			node.set_meta("fade", 0.0)
			_nodes[id] = node
		_state[id] = {"spot": spot_id, "target": target, "yaw": float(f.get("yaw", 0.0)), "size": str(f.get("s", "M")),
			"rarity": str(f.get("r", "common")), "st": str(f.get("st", "roam")), "o": int(f.get("o", 0))}
	for id: String in _nodes.keys():
		if _state.get(id, {}).get("spot", "") == spot_id and not seen.has(id):
			_remove(id)


func _process(delta: float) -> void:
	_time += delta
	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	for id: String in _nodes:
		var node: Node3D = _nodes[id]
		var st: Dictionary = _state[id]
		var before: Vector3 = node.global_position
		node.global_position = before.lerp(st["target"], weight)
		node.rotation.y = lerp_angle(node.rotation.y, float(st["yaw"]), 1.0 - exp(-6.0 * delta))
		var speed: float = (node.global_position - before).length() / maxf(delta, 0.001)
		var body: Node3D = node.get_child(0)
		body.rotation.y = sin(_time * (5.0 + speed * 5.0) + float(id.hash() % 50)) * clampf(0.06 + speed * 0.12, 0.06, 0.32)
		# 나타날 때 스르르, 내가 낚는 중이면 숨긴다 (FishShadow 가 그린다).
		var fade: float = move_toward(float(node.get_meta("fade", 0.0)), 0.0 if id == hidden_id else 1.0, delta * 1.5)
		node.set_meta("fade", fade)
		node.visible = fade > 0.01
		node.scale = Vector3.ONE * (0.7 + 0.3 * fade)
		var aura: Node3D = node.get_node_or_null("Aura")
		if aura != null:
			var pulse: float = 1.0 + sin(_time * (3.2 if st["rarity"] == "rare" else 2.2) + float(id.hash() % 30)) * 0.12
			aura.scale = Vector3(pulse, 1.0, pulse) * fade
			var sparkle: Node3D = aura.get_node_or_null("Sparkle")
			if sparkle != null:
				var k: float = fmod(_time * 0.9 + float(id.hash() % 10) * 0.1, 1.0)
				sparkle.position = Vector3(cos(k * TAU) * 0.35, 0.05 + k * 0.25, sin(k * TAU) * 0.55)
				sparkle.scale = Vector3.ONE * (1.0 - k)


func _remove(id: String) -> void:
	var node: Node3D = _nodes[id]
	_nodes.erase(id)
	_state.erase(id)
	var t: Tween = create_tween()
	t.tween_property(node, "scale", Vector3.ONE * 0.2, 0.4)
	t.tween_callback(node.queue_free)


func _clear() -> void:
	for id: String in _nodes:
		_nodes[id].queue_free()
	_nodes.clear()
	_state.clear()
	hidden_id = ""


func _water_height(spot_id: String) -> float:
	for node: Node in get_tree().get_nodes_in_group(&"fishing_spots"):
		var s: FishingSpot = node as FishingSpot
		if s != null and s.spot_id == spot_id:
			return s.water_height + 0.012
	return 0.03


## 물고기 그림자 하나: 몸(같은 모양, 크기만 다름) + 희귀하면 아우라. FishShadow 도 같은 것을 쓴다.
static func make_visual(size_code: String, rarity: String) -> Node3D:
	var root: Node3D = Node3D.new()
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = FishShadow._shape()
	body.material_override = body_material()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.scale = Vector3.ONE * float(SIZE_SCALE.get(size_code, 1.0))
	root.add_child(body)
	var aura: Node3D = make_aura(rarity, float(SIZE_SCALE.get(size_code, 1.0)))
	if aura != null:
		root.add_child(aura)
	return root


static func body_material() -> StandardMaterial3D:
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		_body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_body_material.albedo_color = Color(SHADOW_COLOR, 0.5)
		_body_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_body_material.render_priority = 2
	return _body_material


## 희귀도 아우라: 몸을 감싸는 길쭉한 빛무리 (더하기 섞기). 흔한 물고기는 없음.
static func make_aura(rarity: String, size_scale: float) -> Node3D:
	if not AURA_COLORS.has(rarity):
		return null
	if _aura_mesh == null:
		_aura_mesh = QuadMesh.new()
		_aura_mesh.size = Vector2(1.0, 1.0)
		_aura_mesh.orientation = PlaneMesh.FACE_Y
		_sparkle_mesh = SphereMesh.new()
		_sparkle_mesh.radius = 0.035
		_sparkle_mesh.height = 0.07
		_sparkle_mesh.radial_segments = 8
		_sparkle_mesh.rings = 4
	if not _aura_materials.has(rarity):
		var tex: GradientTexture2D = GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		tex.gradient = g
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = tex
		m.albedo_color = Color(AURA_COLORS[rarity], 0.55 if rarity == "uncommon" else 0.85)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 1
		m.no_depth_test = false
		_aura_materials[rarity] = m
	var aura: Node3D = Node3D.new()
	aura.name = "Aura"
	var glow: MeshInstance3D = MeshInstance3D.new()
	glow.mesh = _aura_mesh
	glow.material_override = _aura_materials[rarity]
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spread: float = 1.25 if rarity == "rare" else 1.0
	glow.scale = Vector3(0.62, 1.0, 1.25) * size_scale * spread
	glow.position = Vector3(0.0, -0.004, 0.05 * size_scale)
	aura.add_child(glow)
	if rarity == "rare":
		var sparkle: MeshInstance3D = MeshInstance3D.new()
		sparkle.name = "Sparkle"
		sparkle.mesh = _sparkle_mesh
		sparkle.material_override = _aura_materials[rarity]
		sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		aura.add_child(sparkle)
	return aura
