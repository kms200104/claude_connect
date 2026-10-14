class_name CreatureField
extends Node3D
## v0.23 밤 크리처 그림 (Net.creatures — 서버가 자리 · 체력을 정한다). 귀엽지만 으스스한 점토 좀비:
##   어슬렁이(회녹색 피부 · 해진 셔츠, 두 팔을 앞으로) · 달리미(마르고 앞으로 숙인 빨간 후드) · 퉁퉁이(불룩한 배 · 러닝셔츠).
## 서버 자리로 부드럽게 따라가며 걸음마다 다리를 흔들고, 덮치면(a) 팔을 내지른다. 맞으면 움찔 · "퍽!", 쓰러지면 땅으로 꺼지며 연기.
## 머리 위 이름 · 체력 칸 (가까울 때만).
## v0.26 탈것에 들이받히면 빠르기만큼 높이 · 멀리 빙글빙글 날아가 (서버가 미끄러지는 자리를 정한다) 뒤로 벌러덩 눕고,
## 느리게 닿으면 털썩 넘어진다 (f: 1 날아감 · 2 넘어짐). 벽에 부딪히면 "쿵!".

@export var material: Material
@export_range(1.0, 20.0, 0.5) var follow: float = 8.0

class Actor:
	var root: Node3D
	var body: Node3D
	var legs: Array[Node3D] = []
	var arms: Node3D
	var tag: Label3D
	var kind: String = ""
	var target: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var phase: float = 0.0
	var punch: float = 0.0
	var lunge: float = 0.0
	## 0 서 있음 · 1 날아가는 중 · 2 넘어져 있음 (서버 f).
	var flag: int = 0
	## 들이받혀 공중에 뜬 시간 · 전체 · 높이 · 도는 빠르기 (rad/s).
	var air_t: float = 0.0
	var air_total: float = 0.0
	var air_h: float = 0.0
	var spin: float = 0.0

var _actors: Dictionary[String, Actor] = {}
var _meshes: Dictionary[String, Array] = {}


func _ready() -> void:
	add_to_group(&"creature_field")
	Net.creatures_updated.connect(_sync)
	Net.creature_hit.connect(_on_hit)
	Net.creature_dead.connect(_on_dead)
	Net.welcomed.connect(_sync.unbind(3))


func actor_position(id: String) -> Vector3:
	var a: Actor = _actors.get(id)
	return a.root.global_position if a != null else Vector3.INF


## 가장 가까운 크리처 id (range 안, 없으면 빈 글자).
func nearest(p: Vector3, range_m: float) -> String:
	var best: String = ""
	var best_d: float = range_m
	for id: String in _actors:
		var d: float = Vector2(_actors[id].root.global_position.x - p.x, _actors[id].root.global_position.z - p.z).length()
		if d <= best_d:
			best_d = d
			best = id
	return best


func _sync() -> void:
	for id: String in Net.creatures:
		var c: Dictionary = Net.creatures[id]
		var a: Actor = _actors.get(id)
		if a == null:
			a = _spawn(id, str(c.get("k", "shambler")))
			a.root.position = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
		a.target = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
		a.yaw = float(c.get("yaw", 0.0))
		if int(c.get("a", 0)) == 1:
			a.lunge = 1.0
		a.flag = int(c.get("f", 0))
		_update_tag(a, int(c.get("hp", 1)))
	for id: String in _actors.keys():
		if not Net.creatures.has(id) and is_instance_valid(_actors[id].root) and not _actors[id].root.has_meta(&"dying"):
			_actors[id].root.queue_free()
			_actors.erase(id)


func _process(delta: float) -> void:
	for a: Actor in _actors.values():
		if not is_instance_valid(a.root) or a.root.has_meta(&"dying"):
			continue
		var before: Vector3 = a.root.position
		a.root.position = before.lerp(a.target, minf(1.0, delta * (follow * 2.0 if a.flag != 0 else follow)))
		var moved: float = before.distance_to(a.root.position) / maxf(delta, 0.001)
		if a.air_total > 0.0 or a.flag != 0:
			_tumble(a, delta)
			continue
		# 모형은 -Z 를 본다 (서버 yaw 는 +Z 기준 방향).
		a.root.rotation.y = lerp_angle(a.root.rotation.y, a.yaw + PI, minf(1.0, delta * 8.0))
		a.phase += delta * clampf(moved * 3.2, 0.0, 14.0)
		var swing: float = sin(a.phase) * clampf(moved * 0.25, 0.0, 0.6)
		if a.legs.size() == 2:
			a.legs[0].rotation.x = swing
			a.legs[1].rotation.x = -swing
		a.body.position.y = absf(sin(a.phase)) * 0.05
		a.body.rotation.z = sin(a.phase * 0.5) * 0.08
		a.lunge = maxf(0.0, a.lunge - delta * 3.0)
		a.arms.rotation.x = -0.15 - a.lunge * 0.6
		a.arms.position.z = -a.lunge * 0.25
		a.punch = maxf(0.0, a.punch - delta * 5.0)
		a.body.scale = Vector3.ONE * (1.0 + a.punch * 0.12)
		if a.tag != null:
			a.tag.visible = player_near(a.root.global_position, 14.0)


## 들이받혀 날아가는 동안 빙글빙글 (포물선), 내려앉으면 뒤로 누워 있다가 일어난다.
func _tumble(a: Actor, delta: float) -> void:
	if a.air_total > 0.0:
		a.air_t += delta
		var k: float = clampf(a.air_t / a.air_total, 0.0, 1.0)
		a.body.position.y = 4.0 * a.air_h * k * (1.0 - k)
		a.body.rotation.x += a.spin * delta
		if k >= 1.0:
			a.air_total = 0.0
			a.body.rotation.x = wrapf(a.body.rotation.x, -PI, PI)
			Puff.burst(self, a.root.global_position + Vector3(0.0, 0.1, 0.0), Color(0.75, 0.68, 0.55, 0.8), 8, 0.8, 0.2, 0.1, 0.5)
		return
	# 누워 있다 (f 2 · 미끄러지는 중 f 1), 일어나면 다시 선다.
	var lying: bool = a.flag != 0
	a.body.rotation.x = move_toward(a.body.rotation.x, -1.45 if lying else 0.0, delta * (6.0 if lying else 2.5))
	a.body.position.y = move_toward(a.body.position.y, 0.15 if lying else 0.0, delta * 2.0)
	a.body.rotation.z = move_toward(a.body.rotation.z, 0.0, delta * 2.0)
	if a.tag != null:
		a.tag.visible = player_near(a.root.global_position, 14.0)


func player_near(p: Vector3, d: float) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(p) < d + 10.0


func _on_hit(info: Dictionary) -> void:
	var a: Actor = _actors.get(str(info.get("id", "")))
	if a == null:
		return
	a.punch = 1.0
	_update_tag(a, int(info.get("hp", 0)))
	if info.has("ram"):
		var u: float = float(info.get("ram", 0.0))
		if u > 0.0:
			# 빠를수록 높이 · 오래 날고 빨리 돈다.
			a.flag = 1
			a.air_t = 0.0
			a.air_total = clampf(0.25 + u * 0.06, 0.3, 1.4)
			a.air_h = clampf(u * u / 70.0, 0.2, 3.6)
			a.spin = -u * 0.9
			_float_text(a.root.global_position + Vector3(0.0, 2.2, 0.0), "쾅!", Color("#FF9A5A"))
			Puff.burst(self, a.root.global_position + Vector3(0.0, 0.8, 0.0), Color(0.9, 0.85, 0.7, 0.9), 10, 0.9, 0.4, 0.12, 0.5)
			Audio.play_sfx("chop", -2.0, 0.5)
			Prefs.vibrate(90, 0.7)
		else:
			a.flag = 2
			_float_text(a.root.global_position + Vector3(0.0, 1.8, 0.0), "털썩", Color("#E8E0C8"))
			Audio.play_sfx("chop", -10.0, 0.6)
		return
	if int(info.get("wall", 0)) > 0:
		_float_text(a.root.global_position + Vector3(0.0, 1.6, 0.0), "쿵! -%d" % int(info.get("wall", 0)), Color("#FF6A5A"))
		Audio.play_sfx("chop", -3.0, 0.45)
		Puff.burst(self, a.root.global_position + Vector3(0.0, 0.6, 0.0), Color(0.8, 0.8, 0.8, 0.9), 12, 1.0, 0.3, 0.12, 0.5)
		return
	_float_text(a.root.global_position + Vector3(0.0, 2.0, 0.0), "퍽!", Color("#FFE08A"))
	Audio.play_sfx("chop", -6.0, 0.7)


func _on_dead(info: Dictionary) -> void:
	var id: String = str(info.get("id", ""))
	var a: Actor = _actors.get(id)
	if a == null or not is_instance_valid(a.root):
		_actors.erase(id)
		return
	_actors.erase(id)
	a.root.set_meta(&"dying", true)
	if a.tag != null:
		a.tag.visible = false
	var sun: bool = bool(info.get("sun", false)) or bool(info.get("gone", false))
	if not sun:
		_float_text(a.root.global_position + Vector3(0.0, 2.2, 0.0), "쓰러뜨렸다!", Color("#FFFFFF"))
	var tween: Tween = a.root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(a.root, "position:y", -1.6, 1.0 if not sun else 2.0).set_ease(Tween.EASE_IN)
	tween.tween_property(a.root, "scale", Vector3(1.3, 0.2, 1.3), 1.0 if not sun else 2.0)
	tween.chain().tween_callback(a.root.queue_free)


func _float_text(at: Vector3, text: String, color: Color) -> void:
	var l: Label3D = Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.008
	l.outline_size = 16
	l.modulate = color
	l.outline_modulate = Color("#3A2A1A")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = at
	var tween: Tween = l.create_tween()
	tween.set_parallel(true)
	tween.tween_property(l, "position:y", l.position.y + 0.8, 0.7)
	tween.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(l.queue_free)


func _update_tag(a: Actor, hp: int) -> void:
	if a.tag == null:
		return
	var kind: SurvivalRules.CreatureKind = GameData.survival.creature_kinds.get(a.kind)
	var max_hp: int = kind.hp if kind != null else maxi(hp, 1)
	a.tag.text = "%s\n%s" % [kind.name if kind != null else a.kind, "■".repeat(maxi(hp, 0)) + "□".repeat(maxi(max_hp - hp, 0))]


func _spawn(id: String, kind: String) -> Actor:
	var a: Actor = Actor.new()
	a.kind = kind
	a.root = Node3D.new()
	a.root.name = "Creature_%s" % id
	add_child(a.root)
	a.body = Node3D.new()
	a.root.add_child(a.body)
	var parts: Array = _meshes_for(kind)
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.mesh = parts[0]
	torso.material_override = material
	a.body.add_child(torso)
	a.arms = Node3D.new()
	a.arms.position = Vector3(0.0, float(parts[3]), 0.0)
	a.body.add_child(a.arms)
	var arms: MeshInstance3D = MeshInstance3D.new()
	arms.mesh = parts[1]
	arms.material_override = material
	arms.position = Vector3(0.0, -float(parts[3]), 0.0)
	a.arms.add_child(arms)
	for s: float in [-1.0, 1.0]:
		var hip: Node3D = Node3D.new()
		hip.position = Vector3(s * 0.13, float(parts[4]), 0.0)
		a.root.add_child(hip)
		var leg: MeshInstance3D = MeshInstance3D.new()
		leg.mesh = parts[2]
		leg.material_override = material
		hip.add_child(leg)
		a.legs.append(hip)
	a.tag = Label3D.new()
	a.tag.font_size = 40
	a.tag.pixel_size = 0.007
	a.tag.outline_size = 10
	a.tag.modulate = Color("#FFB0A0")
	a.tag.outline_modulate = Color("#2A1A1A")
	a.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	a.tag.position = Vector3(0.0, 2.15 if kind != "bloated" else 2.3, 0.0)
	a.root.add_child(a.tag)
	_actors[id] = a
	return a


## 종류마다 [몸통 메시, 팔 메시, 다리 메시(엉덩이 기준, 아래로), 어깨 높이, 엉덩이 높이].
func _meshes_for(kind: String) -> Array:
	if _meshes.has(kind):
		return _meshes[kind]
	var skin: Color = Color("#8FA58A")
	var shirt: Color = Color("#6B6F7A")
	var pants: Color = Color("#4A4E58")
	var belly: float = 0.0
	var lean: float = 0.0
	var thin: float = 1.0
	match kind:
		"runner":
			skin = Color("#A3B39A")
			shirt = Color("#8A3B33")
			pants = Color("#3B4046")
			lean = 0.35
			thin = 0.8
		"bloated":
			skin = Color("#9AAE84")
			shirt = Color("#C9C2A8")
			pants = Color("#5A5E50")
			belly = 0.22
	var hip_y: float = 0.72
	var shoulder_y: float = 1.42
	var st: SurfaceTool = ClayMesh.begin()
	var tilt: Basis = Basis(Vector3.RIGHT, -lean)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 1.08, -lean * 0.3), Vector3(0.5 * thin + belly, 0.68, 0.3 * thin + belly), 0.3, shirt, tilt)
	if belly > 0.0:
		ClayMesh.add_ellipsoid(st, Vector3(0.0, 1.0, -0.12), Vector3(0.36, 0.34, 0.34), skin.lightened(0.05))
	# 해진 셔츠 자락 · 얼룩.
	ClayMesh.add_box(st, Vector3(0.12, 0.76, -0.12 - lean * 0.2), Vector3(0.14, 0.12, 0.02), shirt.darkened(0.25), Basis(Vector3.BACK, 0.4))
	ClayMesh.add_ellipsoid(st, Vector3(-0.1, 1.2, -0.16 - lean * 0.3), Vector3(0.08, 0.06, 0.02), Color("#5A3A2A"))
	# 머리: 기운 머리 · 퀭한 눈(노랗게 빛나는 눈동자) · 벌린 입.
	var head: Vector3 = Vector3(0.04, 1.68, -lean * 0.55)
	ClayMesh.add_ellipsoid(st, head, Vector3(0.24, 0.25, 0.23), skin, 12, 8, Basis(Vector3.BACK, 0.2))
	ClayMesh.add_ellipsoid(st, head + Vector3(0.0, 0.17, 0.02), Vector3(0.22, 0.1, 0.2), Color("#3E3A30"))
	for s: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, head + Vector3(s * 0.09, 0.03, -0.2), Vector3(0.06, 0.05, 0.03), Color("#2A2620"))
		ClayMesh.add_ellipsoid(st, head + Vector3(s * 0.09, 0.03, -0.225), Vector3(0.025, 0.025, 0.015), Color("#F4E04A"))
	ClayMesh.add_ellipsoid(st, head + Vector3(0.0, -0.11, -0.19), Vector3(0.07, 0.04, 0.03), Color("#4A2A2A"))
	var torso: ArrayMesh = ClayMesh.commit(st)
	# 팔: 어깨에서 앞으로 쭉 (좀비 자세).
	st = ClayMesh.begin()
	for s: float in [-1.0, 1.0]:
		var sh: Vector3 = Vector3(s * (0.3 * thin + belly * 0.5), shoulder_y, -lean * 0.4)
		ClayMesh.add_capsule(st, sh, sh + Vector3(s * 0.02, -0.08, -0.55), 0.07 * thin + 0.01, shirt)
		ClayMesh.add_capsule(st, sh + Vector3(s * 0.02, -0.08, -0.5), sh + Vector3(s * 0.03, -0.12, -0.7), 0.06, skin)
	var arms: ArrayMesh = ClayMesh.commit(st)
	# 다리 (엉덩이 0 기준 아래로).
	st = ClayMesh.begin()
	ClayMesh.add_capsule(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.58, 0.02), 0.09 * thin + 0.02, pants)
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.66, -0.06), Vector3(0.14, 0.1, 0.26), 0.4, Color("#3A3632"))
	var leg: ArrayMesh = ClayMesh.commit(st)
	_meshes[kind] = [torso, arms, leg, shoulder_y, hip_y]
	return _meshes[kind]
