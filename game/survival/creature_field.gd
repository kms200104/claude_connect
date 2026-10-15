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
	## v0.28 게이트 우두머리 이름 · 게이트 크리처 최대 hp (0 = 종류 기본).
	var boss: String = ""
	var max_hp: int = 0
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
	# v0.28.2 독침이 침 · 비명이 비명 (그림 · 소리).
	Net.message_received.connect(_on_message)


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
			# v0.28 게이트 우두머리: 크게 · 금빛 이름표 · 게이트 크리처는 푸른 이름표.
			if c.has("b"):
				a.root.scale = Vector3.ONE * float(c.get("s", 1.5))
				a.boss = str(c.get("b", ""))
				a.tag.modulate = Color("#FFD24A")
				a.tag.font_size = 34
			elif c.has("g"):
				a.tag.modulate = Color("#A8D8FF")
		a.target = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
		a.yaw = float(c.get("yaw", 0.0))
		if int(c.get("a", 0)) == 1:
			a.lunge = 1.0
		a.flag = int(c.get("f", 0))
		a.max_hp = int(c.get("m", 0))
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
	var max_hp: int = a.max_hp if a.max_hp > 0 else (kind.hp if kind != null else maxi(hp, 1))
	var title: String = a.boss if not a.boss.is_empty() else (kind.name if kind != null else a.kind)
	if max_hp > 10:
		# 체력이 많으면 10칸 막대로.
		var full: int = ceili(10.0 * float(maxi(hp, 0)) / float(max_hp))
		a.tag.text = "%s\n%s %d" % [title, "■".repeat(full) + "□".repeat(10 - full), maxi(hp, 0)]
	else:
		a.tag.text = "%s\n%s" % [title, "■".repeat(maxi(hp, 0)) + "□".repeat(maxi(max_hp - hp, 0))]


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
	a.tag.position = Vector3(0.0, 1.15 if kind == "crawler" else (2.3 if kind in ["bloated", "brute"] else 2.15), 0.0)
	# v0.28.2 철갑이는 덩치가 크다.
	if kind == "brute":
		a.root.scale = Vector3.ONE * 1.22
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
		"crawler":
			return _crawler_meshes()
		"screamer":
			skin = Color("#C9CBB8")
			shirt = Color("#3A3A46")
			pants = Color("#2E2E36")
			thin = 0.72
			lean = 0.15
		"brute":
			skin = Color("#7E9070")
			shirt = Color("#4A4A50")
			pants = Color("#38383E")
			thin = 1.35
			belly = 0.08
		"spitter":
			skin = Color("#7FA868")
			shirt = Color("#5A6A40")
			pants = Color("#3E4632")
			lean = 0.2
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
	match kind:
		"screamer":
			# 찢어질 듯 벌린 입 · 긴 목.
			ClayMesh.add_ellipsoid(st, head + Vector3(0.0, -0.13, -0.18), Vector3(0.1, 0.13, 0.05), Color("#3A0A0A"))
			ClayMesh.add_capsule(st, Vector3(0.0, 1.42, -lean * 0.4), head + Vector3(0.0, -0.18, 0.02), 0.07, skin.darkened(0.08))
		"brute":
			# 철판 갑옷 (가슴 · 어깨) · 철모 · 리벳.
			var steel: Color = Color("#6A6E74")
			ClayMesh.add_rounded_box(st, Vector3(0.0, 1.12, -0.24), Vector3(0.62, 0.5, 0.08), 0.3, steel)
			for sd: float in [-1.0, 1.0]:
				ClayMesh.add_rounded_box(st, Vector3(sd * 0.36, 1.42, -0.02), Vector3(0.26, 0.12, 0.36), 0.4, steel.darkened(0.1), Basis(Vector3.BACK, sd * 0.35))
				ClayMesh.add_ellipsoid(st, Vector3(sd * 0.2, 1.3, -0.29), Vector3(0.03, 0.03, 0.02), Color("#3A3E44"))
			ClayMesh.add_ellipsoid(st, head + Vector3(0.0, 0.1, 0.0), Vector3(0.27, 0.16, 0.26), steel.darkened(0.05))
		"spitter":
			# 부풀어 오른 독주머니 (목) · 초록 침.
			ClayMesh.add_ellipsoid(st, head + Vector3(0.0, -0.24, -0.1), Vector3(0.17, 0.13, 0.15), Color("#B8D06A"))
			ClayMesh.add_ellipsoid(st, head + Vector3(0.0, -0.13, -0.21), Vector3(0.05, 0.05, 0.03), Color("#6AA83A"))
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


## v0.28.2 기어미: 배를 땅에 깔고 기어 온다 (몸통 · 머리가 낮고, 팔로 땅을 짚는다). 다리는 뒤로 끌린다.
func _crawler_meshes() -> Array:
	var skin: Color = Color("#8E9C86")
	var rag: Color = Color("#5A4E44")
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.32, 0.05), Vector3(0.24, 0.16, 0.48), rag, 12, 6)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.36, 0.3), Vector3(0.2, 0.12, 0.22), rag.darkened(0.15), 10, 5)
	var head: Vector3 = Vector3(0.0, 0.42, -0.5)
	ClayMesh.add_ellipsoid(st, head, Vector3(0.2, 0.18, 0.2), skin, 12, 8)
	ClayMesh.add_ellipsoid(st, head + Vector3(0.0, 0.12, 0.04), Vector3(0.18, 0.08, 0.16), Color("#3E3A30"))
	for sd: float in [-1.0, 1.0]:
		ClayMesh.add_ellipsoid(st, head + Vector3(sd * 0.08, 0.02, -0.17), Vector3(0.05, 0.04, 0.03), Color("#2A2620"))
		ClayMesh.add_ellipsoid(st, head + Vector3(sd * 0.08, 0.02, -0.19), Vector3(0.022, 0.022, 0.014), Color("#F4E04A"))
	ClayMesh.add_ellipsoid(st, head + Vector3(0.0, -0.08, -0.16), Vector3(0.07, 0.04, 0.03), Color("#4A2A2A"))
	var torso: ArrayMesh = ClayMesh.commit(st)
	# 팔: 앞으로 뻗어 땅을 짚는다 (어깨 0.36 기준).
	st = ClayMesh.begin()
	for sd: float in [-1.0, 1.0]:
		var sh: Vector3 = Vector3(sd * 0.2, 0.36, -0.3)
		ClayMesh.add_capsule(st, sh, sh + Vector3(sd * 0.18, -0.18, -0.32), 0.06, rag)
		ClayMesh.add_capsule(st, sh + Vector3(sd * 0.18, -0.18, -0.32), sh + Vector3(sd * 0.22, -0.32, -0.46), 0.05, skin)
	var arms: ArrayMesh = ClayMesh.commit(st)
	# 다리: 뒤로 끌린다 (엉덩이 0 기준).
	st = ClayMesh.begin()
	ClayMesh.add_capsule(st, Vector3.ZERO, Vector3(0.0, -0.18, 0.55), 0.08, Color("#3A3E44"))
	ClayMesh.add_rounded_box(st, Vector3(0.0, -0.2, 0.62), Vector3(0.12, 0.1, 0.2), 0.4, Color("#3A3632"))
	var leg: ArrayMesh = ClayMesh.commit(st)
	_meshes["crawler"] = [torso, arms, leg, 0.36, 0.3]
	return _meshes["crawler"]


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"creature_spit":
			_spit(str(msg.get("id", "")), int(msg.get("to", 0)))
		"creature_scream":
			_scream(str(msg.get("id", "")))


## 독침이 침: 입에서 초록 덩어리가 포물선으로 날아가 맞은 자리에 튄다.
func _spit(id: String, to: int) -> void:
	var a: Actor = _actors.get(id)
	if a == null or not is_instance_valid(a.root):
		return
	var from: Vector3 = a.root.global_position + Vector3(0.0, 1.5, 0.0)
	var target: Node3D = null
	if to == Net.my_id:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	else:
		var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
		if replicator != null:
			for r: RemotePlayer in replicator.remote_nodes():
				if r.player_id == to:
					target = r
	if target == null:
		return
	var goal: Vector3 = target.global_position + Vector3(0.0, 1.1, 0.0)
	var blob: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.16
	sphere.radial_segments = 8
	sphere.rings = 4
	blob.mesh = sphere
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color("#9AD040")
	m.emission_enabled = true
	m.emission = Color("#6AA020")
	blob.material_override = m
	add_child(blob)
	blob.global_position = from
	a.lunge = 1.0
	var tween: Tween = blob.create_tween()
	tween.tween_method(func(k: float) -> void:
		if is_instance_valid(blob):
			blob.global_position = from.lerp(goal, k) + Vector3(0.0, sin(k * PI) * 1.2, 0.0), 0.0, 1.0, 0.32)
	tween.tween_callback(func() -> void:
		Puff.burst(self, goal, Color(0.6, 0.85, 0.25, 0.9), 8, 0.4, 0.2, 0.07, 0.4)
		blob.queue_free())
	Audio.play_at("fish_plop", from, -6.0, 1.6)


## 비명이 비명: 머리 위로 퍼지는 고리 · "끼아아악!" · 소리.
func _scream(id: String) -> void:
	var a: Actor = _actors.get(id)
	if a == null or not is_instance_valid(a.root):
		return
	var at: Vector3 = a.root.global_position
	var l: Label3D = Label3D.new()
	l.text = "끼아아악!"
	l.font_size = 64
	l.pixel_size = 0.009
	l.outline_size = 12
	l.modulate = Color("#FF8A7A")
	l.outline_modulate = Color("#2A0A0A")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = at + Vector3(0.0, 2.6, 0.0)
	var tween: Tween = l.create_tween()
	tween.set_parallel(true)
	tween.tween_property(l, "scale", Vector3.ONE * 1.5, 0.8)
	tween.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.5)
	tween.chain().tween_callback(l.queue_free)
	for i: int in 3:
		Puff.burst(self, at + Vector3(0.0, 1.8, 0.0), Color(1.0, 0.6, 0.5, 0.5), 10, 1.6 + i * 0.8, 0.1, 0.1, 0.6)
	Audio.play_at("emote_hey", at, 2.0, 0.55)
	a.punch = 1.0
