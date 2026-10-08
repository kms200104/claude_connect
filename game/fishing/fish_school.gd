class_name FishSchool
extends Node3D
## 낚시터 물고기 그림자 (v13). 서버가 알려 주는 물고기들(Net.fishes)을 물 밑 그림자로 그린다.
## 모양은 모두 같고(어떤 물고기인지는 모른다) 몸 크기(S·M·L)만큼 크기가 다르며, 희귀할수록 둘레에 아우라가 감돈다
##   (조금 귀함: 맑은 하늘빛 · 아주 귀함: 금빛 + 반짝임). 서버 위치를 부드럽게 따라가며 헤엄치는 쪽으로 꼬리를 흔든다.
## 내가 낚는 중인 물고기(hidden_id)는 FishShadow 가 이어받아 그리므로 여기서는 숨긴다.
## v0.13.1: 그림자는 불투명하고, 등뼈가 머리에서 꼬리로 차례로 좌우로 휘며 헤엄친다 (fish_silhouette 셰이더).
##   서버 자리를 그냥 미끄러져 따라가지 않는다 — 꼬리를 칠 때마다 앞으로 밀려 나가고(힘껏 칠수록 빨리),
##   꼬리를 멈추면 미끄러지며 느려진다. 방향도 몸을 돌려서 바꾼다.

## 몸 크기별 그림자 배율 (서버 swimmers.js SIZE_SCALE 과 같다).
const SIZE_SCALE: Dictionary[String, float] = {"S": 0.75, "M": 1.0, "L": 1.35, "XL": 1.7}
## v0.16 상어 그림자 (서버 fishes 의 k: shark · hammer): 상어 모양 그림자 + 물 위로 솟은 등지느러미와 그 둘레 물결.
const FIN_COLOR: Color = Color("#4E5A64")
const FIN_HEIGHT: float = 0.36
## 지느러미 밑동 두께 (꼭대기로 갈수록 얇아진다 — 위에서 내려다봐도 짙은 쐐기로 보인다).
const FIN_THICK: float = 0.03
const SHADOW_COLOR: Color = Color(0.03, 0.08, 0.12)
const AURA_COLORS: Dictionary[String, Color] = {"uncommon": Color(0.62, 0.9, 1.0), "rare": Color(1.0, 0.82, 0.32)}

## 꼬리 한 번 칠 때 미는 힘 (m/s², 꼬리를 세게 칠수록 비례).
@export_range(0.5, 20.0, 0.5) var thrust: float = 5.5
## 물의 저항 (꼬리를 멈추면 이 비율로 느려진다).
@export_range(0.1, 10.0, 0.1) var drag: float = 1.8
## 몸을 돌리는 빠르기.
@export_range(0.5, 10.0, 0.1) var turn_speed: float = 3.0

## 내가 낚는 중이라 FishShadow 가 대신 그리는 물고기 id.
var hidden_id: String = ""

var _nodes: Dictionary[String, Node3D] = {}
var _state: Dictionary[String, Dictionary] = {}
var _time: float = 0.0
static var _body_material: ShaderMaterial = null
static var _fish_mesh: ArrayMesh = null
static var _aura_materials: Dictionary[String, StandardMaterial3D] = {}
static var _aura_mesh: QuadMesh = null
static var _sparkle_mesh: SphereMesh = null
static var _shark_meshes: Dictionary[String, ArrayMesh] = {}
static var _fin_mesh: ArrayMesh = null
static var _wake_material: StandardMaterial3D = null
static var _wake_mesh: QuadMesh = null


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
			node = make_visual(str(f.get("s", "M")), str(f.get("r", "common")), str(f.get("k", "")))
			node.name = "Fish_%s" % id
			add_child(node)
			node.global_position = target
			node.rotation.y = float(f.get("yaw", 0.0))
			node.set_meta("fade", 0.0)
			node.set_meta("v", 0.0)
			node.set_meta("phase", randf() * TAU)
			node.set_meta("amp", 0.05)
			_nodes[id] = node
		_state[id] = {"spot": spot_id, "target": target, "yaw": float(f.get("yaw", 0.0)), "size": str(f.get("s", "M")),
			"rarity": str(f.get("r", "common")), "st": str(f.get("st", "roam")), "o": int(f.get("o", 0)), "kind": str(f.get("k", ""))}
	for id: String in _nodes.keys():
		if _state.get(id, {}).get("spot", "") == spot_id and not seen.has(id):
			_remove(id)


func _process(delta: float) -> void:
	_time += delta
	for id: String in _nodes:
		var node: Node3D = _nodes[id]
		var st: Dictionary = _state[id]
		_swim(node, st, delta)
		# 나타날 때 스르르, 내가 낚는 중이면 숨긴다 (FishShadow 가 그린다).
		var fade: float = move_toward(float(node.get_meta("fade", 0.0)), 0.0 if id == hidden_id else 1.0, delta * 1.5)
		node.set_meta("fade", fade)
		node.visible = fade > 0.01
		var body: GeometryInstance3D = node.get_child(0)
		body.set_instance_shader_parameter("alpha", fade)
		# 상어 등지느러미: 나타날 때 물 위로 스르륵 솟고, 꼬리 치는 박자에 맞춰 좌우로 흔들린다.
		update_fin(node, fade, float(node.get_meta("phase", 0.0)), float(node.get_meta("amp", 0.05)), float(node.get_meta("v", 0.0)), _time)
		var aura: Node3D = node.get_node_or_null("Aura")
		if aura != null:
			# 오라는 일반 머티리얼이라 땅 휘기를 스크립트로 맞춘다 (몸통은 셰이더가 휜다).
			aura.position.y = -WorldStyle.curve_drop(node.global_position)
			var pulse: float = 1.0 + sin(_time * (3.2 if st["rarity"] == "rare" else 2.2) + float(id.hash() % 30)) * 0.12
			aura.scale = Vector3(pulse, 1.0, pulse) * fade
			var sparkle: Node3D = aura.get_node_or_null("Sparkle")
			if sparkle != null:
				var k: float = fmod(_time * 0.9 + float(id.hash() % 10) * 0.1, 1.0)
				sparkle.position = Vector3(cos(k * TAU) * 0.35, 0.05 + k * 0.25, sin(k * TAU) * 0.55)
				sparkle.scale = Vector3.ONE * (1.0 - k)


## 꼬리 헤엄: 서버 자리(target) 쪽으로 몸을 돌리고, 꼬리를 칠 때만 앞으로 나간다.
func _swim(node: Node3D, st: Dictionary, delta: float) -> void:
	var target: Vector3 = st["target"]
	var to: Vector3 = Vector3(target.x - node.global_position.x, 0.0, target.z - node.global_position.z)
	var dist: float = to.length()
	var v: float = float(node.get_meta("v", 0.0))
	var phase: float = float(node.get_meta("phase", 0.0))
	var amp: float = float(node.get_meta("amp", 0.05))
	if dist > 3.0:
		# 너무 멀면(처음 · 순간이동) 바로 그 자리로.
		node.global_position = Vector3(target.x, target.y, target.z)
		dist = 0.0
	var size_scale: float = float(SIZE_SCALE.get(str(st["size"]), 1.0))
	var effort: float = 0.0
	if dist > 0.06:
		var want_yaw: float = atan2(-to.x, -to.z)
		node.rotation.y = lerp_angle(node.rotation.y, want_yaw, 1.0 - exp(-turn_speed * delta))
		var facing: float = cos(angle_difference(node.rotation.y, want_yaw))
		# 멀수록 힘껏 (작은 물고기는 더 바지런히 친다). 몸이 아직 돌아가는 중이면 덜 민다.
		effort = clampf(dist * 1.4, 0.15, 1.0) * clampf(facing, 0.0, 1.0) + 0.15
	else:
		node.rotation.y = lerp_angle(node.rotation.y, float(st["yaw"]), 1.0 - exp(-1.5 * delta))
	# 꼬리 치기: 세기(amp)와 빠르기(위상 속도)가 effort 를 따라간다. 쉬면 살랑살랑.
	amp = lerpf(amp, 0.035 + 0.13 * effort, 1.0 - exp(-4.0 * delta))
	phase += delta * (4.0 + 11.0 * effort) / sqrt(size_scale)
	# 미는 힘은 꼬리가 한가운데를 지날 때 가장 크다 (한 번 칠 때마다 쑥).
	var push: float = absf(cos(phase)) * amp / 0.165
	v += (thrust * push * effort - drag * v) * delta
	v = minf(v, dist * 3.0 + 0.05)
	var forward: Vector3 = Vector3(-sin(node.rotation.y), 0.0, -cos(node.rotation.y))
	node.global_position += forward * v * delta
	node.global_position.y = target.y
	node.set_meta("v", v)
	node.set_meta("phase", phase)
	node.set_meta("amp", amp)
	var body: GeometryInstance3D = node.get_child(0)
	body.set_instance_shader_parameter("phase", phase)
	body.set_instance_shader_parameter("amp", amp)


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
## kind 가 shark · hammer 면 상어 모양 그림자에 물 위로 솟은 등지느러미.
static func make_visual(size_code: String, rarity: String, kind: String = "") -> Node3D:
	var root: Node3D = Node3D.new()
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = shark_mesh(kind == "hammer") if not kind.is_empty() else fish_mesh()
	body.material_override = body_material()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.scale = Vector3.ONE * float(SIZE_SCALE.get(size_code, 1.0))
	root.add_child(body)
	var aura: Node3D = make_aura(rarity, float(SIZE_SCALE.get(size_code, 1.0)))
	if aura != null:
		root.add_child(aura)
	if not kind.is_empty():
		root.add_child(make_fin(float(SIZE_SCALE.get(size_code, 1.0))))
	return root


## 물 위로 솟은 상어 등지느러미 (+ 밑동 둘레 하얀 물결). 몸 그림자의 등지느러미 자리(머리 쪽에서 조금 뒤)에 선다.
static func make_fin(size_scale: float) -> Node3D:
	var fin: Node3D = Node3D.new()
	fin.name = "Fin"
	fin.position = Vector3(0.0, 0.0, -0.03 * size_scale)
	var blade: MeshInstance3D = MeshInstance3D.new()
	blade.name = "Blade"
	blade.mesh = shark_fin_mesh()
	blade.material_override = load("res://assets/materials/foliage.tres")
	blade.scale = Vector3.ONE * size_scale
	fin.add_child(blade)
	if _wake_material == null:
		# 부드러운 거품 얼룩 (가운데 하얗고 가장자리로 사라진다). 길게 늘이면 물결 줄기.
		var tex: GradientTexture2D = GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.5, Color(1, 1, 1, 0.45))
		tex.gradient = g
		_wake_material = StandardMaterial3D.new()
		_wake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wake_material.albedo_texture = tex
		_wake_material.albedo_color = Color(0.95, 0.98, 1.0, 0.85)
		_wake_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_wake_material.render_priority = 3
		_wake_mesh = QuadMesh.new()
		_wake_mesh.size = Vector2(1.0, 1.0)
		_wake_mesh.orientation = PlaneMesh.FACE_Y
		_wake_mesh.center_offset = Vector3(0.0, 0.0, 0.5)
	var wake: Node3D = Node3D.new()
	wake.name = "Wake"
	fin.add_child(wake)
	# 지느러미 앞에서 갈라지는 거품 + 뒤로 벌어지는 두 줄기 (V 자).
	for spec: Array in [["Bow", 0.0, Vector3(0.0, 0.0, -0.1)], ["L", 0.32, Vector3(-0.01, 0.0, -0.05)], ["R", -0.32, Vector3(0.01, 0.0, -0.05)]]:
		var q: MeshInstance3D = MeshInstance3D.new()
		q.name = str(spec[0])
		q.mesh = _wake_mesh
		q.material_override = _wake_material
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.rotation.y = float(spec[1])
		q.position = (spec[2] as Vector3) * size_scale
		wake.add_child(q)
	return fin


## 지느러미 움직임: fade 만큼 물 위로 솟고(사라질 때 가라앉는다), 꼬리 박자에 따라 흔들리고, 빠를수록 물결이 길게 끌린다.
static func update_fin(node: Node3D, fade: float, phase: float, amp: float, speed: float, time: float) -> void:
	var fin: Node3D = node.get_node_or_null("Fin")
	if fin == null:
		return
	var blade: Node3D = fin.get_node("Blade")
	var s: float = blade.scale.x
	blade.position.y = -FIN_HEIGHT * s * (1.0 - fade) - WorldStyle.curve_drop(node.global_position)
	blade.rotation = Vector3(0.0, sin(phase) * amp * 0.9, sin(phase + 0.6) * amp * 0.35)
	var wake: Node3D = fin.get_node("Wake")
	wake.position.y = 0.006 - WorldStyle.curve_drop(node.global_position)
	var pulse: float = 1.0 + 0.08 * sin(time * 5.0 + phase)
	var trail: float = 0.35 + minf(speed, 2.0) * 0.5
	var bow: Node3D = wake.get_node("Bow")
	bow.scale = Vector3(0.16 * pulse, 1.0, 0.2 * pulse) * s * fade
	for side: String in ["L", "R"]:
		(wake.get_node(side) as Node3D).scale = Vector3(0.06 * pulse, 1.0, trail) * s * fade


## 위에서 본 상어 그림자 (머리 -Z, 꼬리 +Z): 뾰족한 주둥이 · 크게 뒤로 젖힌 가슴지느러미 · 위 갈래가 긴 꼬리.
## 귀상어는 머리 앞이 양옆으로 넓적한 망치. 셰이더가 휠 수 있게 앞뒤로 여러 마디.
static func shark_mesh(hammer: bool) -> ArrayMesh:
	var key: String = "hammer" if hammer else "shark"
	if _shark_meshes.has(key):
		return _shark_meshes[key]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var profile: Array[Vector2] = [Vector2(-0.46, 0.0), Vector2(-0.43, 0.035), Vector2(-0.37, 0.066), Vector2(-0.28, 0.092), Vector2(-0.18, 0.104),
		Vector2(-0.06, 0.1), Vector2(0.06, 0.084), Vector2(0.16, 0.062), Vector2(0.25, 0.04), Vector2(0.32, 0.026), Vector2(0.37, 0.022)]
	if hammer:
		profile[0] = Vector2(-0.43, 0.0)
		profile[1] = Vector2(-0.42, 0.06)
	for i: int in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		_quad(st, Vector3(-a.y, 0.0, a.x), Vector3(a.y, 0.0, a.x), Vector3(b.y, 0.0, b.x), Vector3(-b.y, 0.0, b.x))
	if hammer:
		# 망치 머리: 양옆으로 길쭉한 판 (끝이 살짝 뒤로).
		for side: float in [-1.0, 1.0]:
			var m: Vector3 = Vector3(side, 1.0, 1.0)
			_quad(st, Vector3(0.0, 0.0, -0.44) * m, Vector3(0.24, 0.0, -0.42) * m, Vector3(0.25, 0.0, -0.37) * m, Vector3(0.0, 0.0, -0.33) * m)
	for side: float in [-1.0, 1.0]:
		var m: Vector3 = Vector3(side, 1.0, 1.0)
		# 가슴지느러미: 크게, 뒤로 젖힌 낫 모양.
		_tri(st, Vector3(0.09, 0.0, -0.2) * m, Vector3(0.34, 0.0, -0.02) * m, Vector3(0.08, 0.0, -0.08) * m)
		_tri(st, Vector3(0.08, 0.0, -0.08) * m, Vector3(0.34, 0.0, -0.02) * m, Vector3(0.29, 0.0, 0.01) * m)
		# 배지느러미 (작게).
		_tri(st, Vector3(0.05, 0.0, 0.14) * m, Vector3(0.12, 0.0, 0.21) * m, Vector3(0.04, 0.0, 0.2) * m)
	# 꼬리: 위 갈래(길게 한쪽으로 휜다)와 짧은 아래 갈래 — 위에서 보면 비스듬히 갈라진 낫.
	var upper: Array[Vector3] = [Vector3(0.022, 0.0, 0.37), Vector3(0.05, 0.0, 0.46), Vector3(0.085, 0.0, 0.55), Vector3(0.12, 0.0, 0.63)]
	var spine: Array[Vector3] = [Vector3(-0.022, 0.0, 0.37), Vector3(-0.012, 0.0, 0.45), Vector3(0.0, 0.0, 0.52), Vector3(0.03, 0.0, 0.58)]
	for i: int in upper.size() - 1:
		_quad(st, spine[i], upper[i], upper[i + 1], spine[i + 1])
	_tri(st, Vector3(-0.022, 0.0, 0.38), Vector3(-0.1, 0.0, 0.47), Vector3(-0.01, 0.0, 0.44))
	_shark_meshes[key] = st.commit()
	return _shark_meshes[key]


## 물 위로 나온 등지느러미 (높이 FIN_HEIGHT): 앞 가장자리는 둥글게 뒤로 젖히고, 뒤 가장자리는 오목하게 파였다.
## 양면 · 정점 색 (끝은 짙고 밑동은 물에 젖어 조금 밝다).
static func shark_fin_mesh() -> ArrayMesh:
	if _fin_mesh != null:
		return _fin_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 10
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for i: int in n + 1:
		var t: float = float(i) / float(n)
		var y: float = t * FIN_HEIGHT
		# 앞 가장자리: 밑동 앞에서 꼭대기까지 둥글게 뒤로 (볼록).
		var fz: float = -0.11 + 0.19 * pow(t, 1.6)
		# 뒤 가장자리: 꼭대기에서 밑동 뒤로 오목하게 파인 곡선.
		var bz: float = lerpf(0.09, 0.085, t) - 0.06 * sin(PI * minf(t * 1.1, 1.0))
		if i == n:
			bz = fz
		front.append(Vector3(0.0, y, fz))
		back.append(Vector3(0.0, y, maxf(bz, fz)))
	for side: float in [1.0, -1.0]:
		var nrm: Vector3 = Vector3(side, 0.3, 0.0).normalized()
		var order: Array[int] = [0, 1, 2, 0, 2, 3]
		if side < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for i: int in n:
			var t0: float = float(i) / float(n)
			var t1: float = float(i + 1) / float(n)
			var c0: Color = FIN_COLOR.lerp(FIN_COLOR.lightened(0.15), 1.0 - t0)
			var c1: Color = FIN_COLOR.lerp(FIN_COLOR.darkened(0.2), t1)
			# 밑동은 두툼하고 꼭대기로 갈수록 얇다 (앞 · 뒤 가장자리는 날처럼 붙는다).
			var w0: Vector3 = Vector3(side * FIN_THICK * pow(1.0 - t0, 1.3), 0.0, 0.0)
			var w1: Vector3 = Vector3(side * FIN_THICK * pow(1.0 - t1, 1.3), 0.0, 0.0)
			var mid0: Vector3 = (front[i] + back[i]) * 0.5 + w0
			var mid1: Vector3 = (front[i + 1] + back[i + 1]) * 0.5 + w1
			for half: Array in [[front[i], mid0, mid1, front[i + 1]], [mid0, back[i], back[i + 1], mid1]]:
				var cols: Array[Color] = [c0, c0, c1, c1]
				for k: int in order:
					st.set_color(cols[k])
					st.set_normal(nrm)
					st.add_vertex(half[k])
	_fin_mesh = st.commit()
	return _fin_mesh


static func body_material() -> ShaderMaterial:
	if _body_material == null:
		_body_material = ShaderMaterial.new()
		_body_material.shader = load("res://assets/shaders/fish_silhouette.gdshader")
		_body_material.set_shader_parameter("shadow_color", SHADOW_COLOR)
		_body_material.render_priority = 2
	return _body_material


## 위에서 본 물고기 (머리 -Z, 꼬리 +Z). 셰이더가 휠 수 있게 몸을 앞뒤로 여러 마디로 나눈다:
## 통통한 머리 → 가늘어지는 꼬리자루 → 두 갈래 꼬리지느러미, 가슴지느러미 한 쌍, 등지느러미 자국.
static func fish_mesh() -> ArrayMesh:
	if _fish_mesh != null:
		return _fish_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# 몸통 반폭 (z, w): 둥근 주둥이 → 가장 넓은 어깨 → 꼬리자루.
	var profile: Array[Vector2] = [Vector2(-0.36, 0.0), Vector2(-0.335, 0.055), Vector2(-0.29, 0.095), Vector2(-0.22, 0.123),
		Vector2(-0.14, 0.135), Vector2(-0.05, 0.13), Vector2(0.04, 0.113), Vector2(0.12, 0.088), Vector2(0.2, 0.062),
		Vector2(0.27, 0.04), Vector2(0.32, 0.03), Vector2(0.36, 0.034)]
	for i: int in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		_quad(st, Vector3(-a.y, 0.0, a.x), Vector3(a.y, 0.0, a.x), Vector3(b.y, 0.0, b.x), Vector3(-b.y, 0.0, b.x))
	# 꼬리지느러미: 꼬리자루에서 두 갈래로 벌어진다 (휘어지게 세 마디).
	var fork: Array[Vector3] = [Vector3(0.034, 0.0, 0.36), Vector3(0.09, 0.0, 0.44), Vector3(0.15, 0.0, 0.52), Vector3(0.19, 0.0, 0.58)]
	var notch: Array[Vector3] = [Vector3(0.0, 0.0, 0.36), Vector3(0.02, 0.0, 0.43), Vector3(0.03, 0.0, 0.48), Vector3(0.0, 0.0, 0.5)]
	for side: float in [-1.0, 1.0]:
		var m: Vector3 = Vector3(side, 1.0, 1.0)
		for i: int in fork.size() - 1:
			_quad(st, notch[i] * m, fork[i] * m, fork[i + 1] * m, notch[i + 1] * m)
	# 가슴지느러미 (어깨 옆으로 비스듬히).
	for side: float in [-1.0, 1.0]:
		var m: Vector3 = Vector3(side, 1.0, 1.0)
		_tri(st, Vector3(0.11, 0.0, -0.17) * m, Vector3(0.24, 0.0, -0.08) * m, Vector3(0.12, 0.0, -0.06) * m)
		# 배지느러미 (작게).
		_tri(st, Vector3(0.09, 0.0, 0.06) * m, Vector3(0.16, 0.0, 0.14) * m, Vector3(0.08, 0.0, 0.12) * m)
	_fish_mesh = st.commit()
	return _fish_mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


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
