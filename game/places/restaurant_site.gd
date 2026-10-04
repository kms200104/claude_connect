class_name RestaurantSite
extends Node3D
## 솔바람 식당: 기와지붕 부엌 건물 + 앞쪽 줄무늬 차양 아래 바 카운터(화구·도마·냄비) + 앞마당 둥근 식탁 두 개와 의자 여덟 개.
## 위치는 data/restaurant/restaurant.json (서버와 같은 파일). 손님(주민·섬 밖 손님)은 서버가 주문을 받으면 의자에 앉고,
## 머리 위에 주문한 요리 그림과 남은 기다림 막대를 띄운다. 요리가 나오면 식탁에 접시가 놓이고, 별점만큼 기뻐하거나 시무룩해한다.
## 단골이 되면 하트가 뜬다. 앉아 있는 주민은 돌아다니는 모습을 잠깐 숨긴다.

@export var actor_scene: PackedScene
@export var clay_material: Material
@export var window_material: Material
## 앉은 주민의 돌아다니는 모습을 숨길 곳 (없어도 된다).
@export var npcs: NpcCrowd

const WALL: Array = ["#E8D8BC", "#F6ECD8"]
const WOOD: Array = ["#8A5A36", "#B07A4A"]
const DARK_WOOD: Array = ["#5A3A24", "#7A5232"]
const TILE: Array = ["#3E4A5A", "#5E6E80"]
const STONE: Array = ["#B8B0A0", "#D8D0C0"]
const STRIPE_A: String = "#E8604A"
const STRIPE_B: String = "#FFF4E0"
const STOOL_HEIGHT: float = 0.3
## 요리가 나온 뒤 손님이 일어나기까지.
const LEAVE_AFTER: float = 3.2

var _rules: Dictionary = {}
var _counter: Vector3 = Vector3.ZERO
var _open_range: float = 2.6
var _seats: Array[Dictionary] = []
var _tables: Array[Vector3] = []
var _status: Label3D = null
var _rating: Label3D = null
var _steam: GPUParticles3D = null
## 주문 id → { actor, bubble, fill, customer, dish, seat }
var _guests: Dictionary[String, Dictionary] = {}
var _white: ImageTexture = null


func _ready() -> void:
	var econ: EconData = GameData.econ
	if econ == null:
		return
	_rules = econ.restaurant
	var c: Dictionary = _rules.get("counter", {})
	_counter = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
	_open_range = float(_rules.get("open_range", 2.6))
	for s: Variant in _rules.get("seats", []):
		if s is Dictionary:
			_seats.append(s)
	for t: Variant in _rules.get("tables", []):
		if t is Dictionary:
			_tables.append(Vector3(float(t.get("x", 0.0)), 0.0, float(t.get("z", 0.0))))
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	_build_building()
	_build_terrace()
	Economy.restaurant_changed.connect(_sync)
	Economy.served.connect(_on_served)
	Economy.customer_left.connect(_on_left)
	Economy.order_arrived.connect(func(o: Dictionary) -> void:
		Audio.play_at("order_bell", _counter, -6.0)
		_sync()
		var g: Dictionary = _guests.get(str(o.get("order", "")), {})
		if not g.is_empty() and bool(o.get("regular", false)):
			EmoteBubble.pop(g["actor"], "love", 2.0))
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync())
	_sync()


## 카운터 곁인지 (상황 버튼 "식당 열기" / "주방").
func near_counter(position: Vector3, max_distance: float) -> bool:
	return Vector2(position.x - _counter.x, position.z - _counter.z).length() <= minf(max_distance, _open_range)


func counter_position() -> Vector3:
	return _counter


## 요리하는 사람이 바라보는 쪽 (손님 쪽 = +Z).
func counter_facing() -> Vector3:
	return Vector3(0.0, 0.0, 1.0)


func seat_position(seat: int) -> Vector3:
	if seat < 0 or seat >= _seats.size():
		return _counter
	return Vector3(float(_seats[seat].get("x", 0.0)), 0.0, float(_seats[seat].get("z", 0.0)))


## 요리하는 동안 화구 위로 김이 오른다.
func set_steaming(on: bool) -> void:
	if _steam != null:
		_steam.emitting = on


func _process(_delta: float) -> void:
	for id: String in _guests:
		var g: Dictionary = _guests[id]
		var fill: Sprite3D = g.get("fill")
		if fill == null or not Economy.orders.has(id):
			continue
		var o: Dictionary = Economy.orders[id]
		var ratio: float = clampf(Economy.order_left_ms(o) / maxf(float(o.get("patience", 1.0)), 1.0), 0.0, 1.0)
		fill.scale.x = maxf(ratio, 0.001)
		fill.position.x = -0.5 * (1.0 - ratio) * 0.9
		fill.modulate = Color("#7BC67A").lerp(Color("#E8604A"), 1.0 - ratio)


# ---- 손님 ----

func _sync() -> void:
	for id: String in _guests.keys():
		if not Economy.orders.has(id) and not bool(_guests[id].get("leaving", false)):
			_dismiss(id, "")
	for id: String in Economy.orders:
		if not _guests.has(id):
			_seat_guest(Economy.orders[id])
	var open: bool = bool(Economy.rest.get("open", false))
	if _status != null:
		_status.text = ("영업 중 · %s" % GameData.player_name(int(Economy.rest.get("owner", 0)))) if open else "준비 중"
		_status.modulate = Color("#FFE27A") if open else Color("#D8D0C0")
	if _rating != null:
		var rating: float = float(Economy.rest.get("rating", 2.0))
		_rating.text = "%s %.1f · %d단계 메뉴" % [_stars_text(roundi(rating)), rating, int(Economy.rest.get("tier", 1))]


func _seat_guest(o: Dictionary) -> void:
	if actor_scene == null:
		return
	var customer: EconData.Customer = GameData.econ.customers.get(str(o.get("customer", "")))
	if customer == null:
		return
	var seat: int = int(o.get("seat", 0))
	var actor: NpcActor = actor_scene.instantiate()
	add_child(actor)
	actor.setup(_npc_info(customer))
	var state: NetNpcState = NetNpcState.new()
	state.id = customer.id
	state.position = seat_position(seat)
	state.yaw = float(_seats[seat].get("yaw", 0.0)) if seat < _seats.size() else 0.0
	actor.apply_state(state)
	actor.rig.set_sitting(true)
	actor.set_mark("")
	if customer.villager and npcs != null and npcs.actor(customer.id) != null:
		npcs.actor(customer.id).visible = false
	# 머리 위: 요리 그림 + 기다림 막대.
	var bubble: Node3D = Node3D.new()
	actor.add_child(bubble)
	bubble.position = Vector3(0.0, 2.3, 0.0)
	var icon: Sprite3D = Sprite3D.new()
	icon.texture = DishArt.icon(str(o.get("dish", "")))
	icon.pixel_size = 0.0045
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	bubble.add_child(icon)
	var back: Sprite3D = _bar(Color(0.15, 0.12, 0.1, 0.7), 0.95)
	back.position = Vector3(0.0, -0.36, 0.0)
	bubble.add_child(back)
	var fill: Sprite3D = _bar(Color("#7BC67A"), 0.9)
	fill.position = Vector3(0.0, -0.36, 0.0)
	fill.render_priority = 1
	bubble.add_child(fill)
	_guests[str(o.get("id", o.get("order", "")))] = {"actor": actor, "bubble": bubble, "fill": fill, "customer": customer.id, "dish": str(o.get("dish", "")), "seat": seat}
	# 앉는 순간 톡.
	actor.scale = Vector3(0.6, 0.6, 0.6)
	create_tween().tween_property(actor, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_served(info: Dictionary) -> void:
	var id: String = str(info.get("order", ""))
	var g: Dictionary = _guests.get(id, {})
	if g.is_empty():
		return
	g["leaving"] = true
	var actor: NpcActor = g["actor"]
	(g["bubble"] as Node3D).visible = false
	var stars: int = int(info.get("stars", 3))
	# 식탁에 접시.
	var dish: MeshInstance3D = MeshInstance3D.new()
	dish.mesh = DishArt.mesh(str(info.get("dish", "")))
	dish.material_override = clay_material
	add_child(dish)
	dish.global_position = _plate_spot(int(g.get("seat", 0)))
	dish.scale = Vector3(1.6, 1.6, 1.6)
	g["dish_node"] = dish
	Audio.play_at("cook_plate", dish.global_position, -4.0)
	var line: String = ""
	if bool(info.get("became", false)):
		line = "여기 단골 할래요!"
	elif bool(info.get("lost", false)):
		line = "예전 맛이 아니네…"
	actor.play_emote("happy" if stars >= 4 else ("think" if stars == 3 else "sad"), line)
	_float_text(actor, _stars_text(stars), Color("#FFD866"))
	if bool(info.get("became", false)):
		EmoteBubble.pop(actor, "love", 2.6)
	get_tree().create_timer(LEAVE_AFTER).timeout.connect(_dismiss.bind(id, "done"))


func _on_left(info: Dictionary) -> void:
	var id: String = str(info.get("order", ""))
	var g: Dictionary = _guests.get(id, {})
	if g.is_empty():
		return
	g["leaving"] = true
	(g["bubble"] as Node3D).visible = false
	var actor: NpcActor = g["actor"]
	actor.play_emote("angry" if str(info.get("reason", "")) == "late" else "sad", "너무 오래 걸려요…" if str(info.get("reason", "")) == "late" else "")
	get_tree().create_timer(1.8).timeout.connect(_dismiss.bind(id, "left"))


func _dismiss(id: String, _why: String) -> void:
	var g: Dictionary = _guests.get(id, {})
	if g.is_empty():
		return
	_guests.erase(id)
	var actor: NpcActor = g["actor"]
	var dish: Node3D = g.get("dish_node")
	var customer: String = str(g.get("customer", ""))
	var tween: Tween = create_tween()
	tween.tween_property(actor, "scale", Vector3(0.05, 0.05, 0.05), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		actor.queue_free()
		if dish != null:
			dish.queue_free()
		# 같은 주민이 다른 자리에 또 앉아 있지 않으면 다시 돌아다닌다.
		var still: bool = false
		for other: Dictionary in _guests.values():
			if str(other.get("customer", "")) == customer:
				still = true
		if not still and npcs != null and npcs.actor(customer) != null:
			npcs.actor(customer).visible = true)


func _plate_spot(seat: int) -> Vector3:
	var at: Vector3 = seat_position(seat)
	var best: Vector3 = at
	var best_d: float = INF
	for t: Vector3 in _tables:
		var d: float = at.distance_to(t)
		if d < best_d:
			best_d = d
			best = t
	return best + (at - best).normalized() * 0.42 + Vector3(0.0, 0.78, 0.0)


## 섬 밖 손님은 NpcInfo 가 없으니 겉모습만 담아 만든다.
func _npc_info(c: EconData.Customer) -> NpcInfo:
	if c.villager and GameData.npcs.has(c.id):
		return GameData.npcs[c.id]
	var info: NpcInfo = NpcInfo.new()
	info.id = c.id
	info.display_name = c.display_name
	info.look = c.look
	info.mbti = c.mbti
	info.about = c.about
	info.voice = 0.9 + float(absi(c.id.hash()) % 30) / 100.0
	return info


func _bar(color: Color, width: float) -> Sprite3D:
	var s: Sprite3D = Sprite3D.new()
	s.texture = _white
	s.pixel_size = 1.0
	s.scale = Vector3(1.0, 1.0, 1.0)
	s.region_enabled = false
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.centered = true
	# 4px 텍스처 × pixel_size → 크기를 직접 맞춘다.
	s.pixel_size = width / 4.0
	s.scale = Vector3(1.0, 0.09 / width, 1.0)
	return s


func _float_text(parent: Node3D, text: String, color: Color) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.009
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color("#5A3E26")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	label.position = Vector3(0.0, 2.5, 0.0)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "position:y", 3.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.6).set_delay(0.8)
	tween.tween_callback(label.queue_free)


static func _stars_text(stars: int) -> String:
	var n: int = clampi(stars, 0, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


# ---- 건물 ----

func _build_building() -> void:
	var b: Dictionary = _rules.get("building", {})
	var root: Node3D = Node3D.new()
	root.name = "Building"
	add_child(root)
	root.global_position = Vector3(float(b.get("x", 0.0)), 0.0, float(b.get("z", 0.0)))
	root.rotation.y = float(b.get("yaw", 0.0))
	var w: float = float(b.get("width", 10.0))
	var d: float = float(b.get("depth", 7.0))
	var front: float = d * 0.5
	# 카운터는 건물 앞면에서 이만큼 떨어져 있다 (그 사이에 요리하는 사람이 선다).
	var counter_z: float = _counter.z - root.global_position.z + 1.0
	var parts: Array = []
	parts.append(KeeperSite.p("rbox", [w + 0.6, 0.18, d + 0.6], Vector3(0.0, 0.09, 0.0), STONE, 0.2))
	parts.append(KeeperSite.p("rbox", [w, 3.0, d], Vector3(0.0, 1.6, 0.0), WALL, 0.05))
	# 나무 기둥 · 보 (한옥 느낌)
	for x: float in [-w * 0.5, -w * 0.17, w * 0.17, w * 0.5]:
		parts.append(KeeperSite.p("rbox", [0.32, 3.1, 0.32], Vector3(x, 1.6, front), DARK_WOOD, 0.2))
	parts.append(KeeperSite.p("rbox", [w + 0.4, 0.3, 0.36], Vector3(0.0, 3.05, front), DARK_WOOD, 0.2))
	# 기와지붕: 앞뒤로 기운 두 장 + 용마루 + 처마 끝 살짝 들림
	for side: float in [-1.0, 1.0]:
		parts.append(KeeperSite.p("rbox", [w + 1.6, 0.32, d * 0.5 + 1.4], Vector3(0.0, 3.85, side * (d * 0.25 + 0.5)), TILE, 0.25, Vector3(side * 22.0, 0.0, 0.0)))
	parts.append(KeeperSite.p("rbox", [w + 1.8, 0.36, 0.5], Vector3(0.0, 4.45, 0.0), ["#2E3846", "#4A5666"], 0.4))
	for x: float in [-(w + 1.6) * 0.5, (w + 1.6) * 0.5]:
		parts.append(KeeperSite.p("sphere", [0.32, 0.22, 0.32], Vector3(x, 4.5, 0.0), "#2E3846"))
	# 줄무늬 차양 (카운터 위)
	var stripes: int = 8
	var awning_w: float = 7.2
	for i: int in stripes:
		var x: float = -awning_w * 0.5 + awning_w * (float(i) + 0.5) / float(stripes)
		parts.append(KeeperSite.p("box", [awning_w / float(stripes), 0.08, 2.0], Vector3(x, 2.75, front + 1.0), STRIPE_A if i % 2 == 0 else STRIPE_B, -1.0, Vector3(-14.0, 0.0, 0.0)))
	for i: int in stripes:
		var x: float = -awning_w * 0.5 + awning_w * (float(i) + 0.5) / float(stripes)
		parts.append(KeeperSite.p("sphere", [awning_w / float(stripes) * 0.5, 0.12, 0.08], Vector3(x, 2.47, front + 2.0), STRIPE_A if i % 2 == 0 else STRIPE_B))
	for x: float in [-awning_w * 0.5, awning_w * 0.5]:
		parts.append(KeeperSite.p("rod", [0.05, 0.05], Vector3(x, 0.0, front + 1.9), "#6A4A2E"))
		parts[-1]["to"] = [x, 2.5, front + 1.9]
	# 바 카운터: 나무 몸통 + 밝은 상판, 위에 화구 · 냄비 · 도마 · 양념병
	parts.append(KeeperSite.p("rbox", [6.4, 0.9, 0.62], Vector3(0.0, 0.45, counter_z), WOOD, 0.15))
	parts.append(KeeperSite.p("rbox", [6.7, 0.08, 0.8], Vector3(0.0, 0.94, counter_z), ["#D8B888", "#F0D8B0"], 0.4))
	parts.append(KeeperSite.p("rbox", [0.9, 0.12, 0.55], Vector3(1.6, 1.03, counter_z), "#3A3A40", 0.3))
	parts.append(KeeperSite.p("torus", [0.16, 0.03], Vector3(1.4, 1.1, counter_z), "#5A5A60"))
	parts.append(KeeperSite.p("cyl", [0.24, 0.3], Vector3(1.85, 1.25, counter_z), ["#B04A3A", "#E06A4A"], 0.06))
	parts.append(KeeperSite.p("torus", [0.24, 0.03], Vector3(1.85, 1.4, counter_z), "#8A3A2E"))
	parts.append(KeeperSite.p("rbox", [0.8, 0.06, 0.45], Vector3(-1.5, 1.01, counter_z), ["#C9A070", "#E8C898"], 0.4))
	parts.append(KeeperSite.p("sphere", [0.1, 0.16, 0.1], Vector3(-1.35, 1.12, counter_z), "#F4F1EA"))
	parts.append(KeeperSite.p("sphere", [0.05, 0.08, 0.05], Vector3(-1.35, 1.3, counter_z), "#6FAF5A"))
	for i: int in 3:
		parts.append(KeeperSite.p("cyl", [0.05, 0.2], Vector3(-2.7 + 0.14 * i, 1.08, counter_z - 0.15), ["#5A3A24", "#C0402A", "#E8C060"][i], 0.04))
	parts.append(KeeperSite.p("rbox", [0.6, 0.05, 0.4], Vector3(-0.2, 1.0, counter_z), "#F4F1EA", 0.4))
	# 문 위 가로 간판 바탕 + 포렴(문발)
	parts.append(KeeperSite.p("rbox", [4.6, 0.8, 0.14], Vector3(0.0, 3.55, front + 0.2), DARK_WOOD, 0.3))
	for i: int in 3:
		parts.append(KeeperSite.p("rbox", [0.5, 0.9, 0.04], Vector3(-w * 0.5 + 1.2 + 0.52 * i, 2.35, front + 0.04), ["#2E4A7A", "#3E5E92"], 0.15))
	# 붉은 등 두 개
	for x: float in [-3.4, 3.4]:
		parts.append(KeeperSite.p("rod", [0.015, 0.015], Vector3(x, 2.62, front + 1.8), "#3A2A20"))
		parts[-1]["to"] = [x, 2.4, front + 1.8]
		parts.append(KeeperSite.p("sphere", [0.2, 0.26, 0.2], Vector3(x, 2.18, front + 1.8), ["#C83A2A", "#F06A4A"]))
	root.add_child(_mesh(PartMesh.build(parts), clay_material))
	var windows: Array = []
	windows.append(KeeperSite.p("box", [3.2, 1.2, 0.04], Vector3(1.8, 1.9, front + 0.02), "#FFFFFF"))
	for side: float in [-1.0, 1.0]:
		windows.append(KeeperSite.p("box", [0.04, 1.0, 1.6], Vector3(side * (w * 0.5 + 0.02), 1.9, 0.0), "#FFFFFF"))
	root.add_child(_mesh(PartMesh.build(windows), window_material))
	var title: Label3D = _label(str(_rules.get("name", "솔바람 식당")), 96, Color("#FFF4DC"))
	root.add_child(title)
	title.position = Vector3(0.0, 3.55, front + 0.3)
	_status = _label("준비 중", 56, Color("#D8D0C0"))
	root.add_child(_status)
	_status.position = Vector3(-3.3, 3.2, front + 0.3)
	_rating = _label("", 48, Color("#FFD866"))
	_rating.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(_rating)
	_rating.position = Vector3(0.0, 5.2, front)
	_steam = _make_steam()
	root.add_child(_steam)
	_steam.position = Vector3(1.85, 1.45, counter_z)
	var body: StaticBody3D = StaticBody3D.new()
	root.add_child(body)
	for box: AABB in [AABB(Vector3(0.0, 1.5, 0.0), Vector3(w, 3.0, d)), AABB(Vector3(0.0, 0.5, counter_z), Vector3(6.4, 1.0, 0.62))]:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var bs: BoxShape3D = BoxShape3D.new()
		bs.size = box.size
		shape.shape = bs
		shape.position = box.position
		body.add_child(shape)


func _build_terrace() -> void:
	var parts: Array = []
	for t: Vector3 in _tables:
		parts.append(KeeperSite.p("cyl", [0.78, 0.07], t + Vector3(0.0, 0.72, 0.0), ["#C9A070", "#E8C898"], 0.03))
		parts.append(KeeperSite.p("cyl", [0.08, 0.7], t + Vector3(0.0, 0.36, 0.0), "#6A4A2E", 0.02))
		parts.append(KeeperSite.p("cyl", [0.36, 0.05], t + Vector3(0.0, 0.03, 0.0), "#6A4A2E", 0.02))
		# 식탁 위 작은 꽃병
		parts.append(KeeperSite.p("cyl", [0.06, 0.14], t + Vector3(0.0, 0.83, 0.0), "#9EC1F2", 0.03))
		parts.append(KeeperSite.p("sphere", [0.07], t + Vector3(0.0, 0.95, 0.0), "#F6A6B8"))
	for s: Dictionary in _seats:
		var at: Vector3 = Vector3(float(s.get("x", 0.0)), 0.0, float(s.get("z", 0.0)))
		parts.append(KeeperSite.p("cyl", [0.26, 0.08], at + Vector3(0.0, STOOL_HEIGHT - 0.04, 0.0), ["#D8604A", "#F08060"], 0.04))
		parts.append(KeeperSite.p("cyl", [0.05, STOOL_HEIGHT - 0.06], at + Vector3(0.0, (STOOL_HEIGHT - 0.06) * 0.5, 0.0), "#5A4A3A"))
	# 오늘의 메뉴 입간판
	var board: Vector3 = _counter + Vector3(4.6, 0.0, 1.2)
	parts.append(KeeperSite.p("rbox", [0.9, 1.1, 0.08], board + Vector3(0.0, 0.75, 0.0), ["#2E3A30", "#3E4E40"], 0.2, Vector3(-8.0, 0.0, 0.0)))
	parts.append(KeeperSite.p("rbox", [1.0, 0.08, 0.12], board + Vector3(0.0, 1.32, 0.0), WOOD, 0.3))
	add_child(_mesh(PartMesh.build(parts), clay_material))
	var menu: Label3D = _label("오늘의 메뉴", 40, Color("#F4F1EA"))
	add_child(menu)
	menu.position = board + Vector3(0.0, 1.05, 0.06)
	var body: StaticBody3D = StaticBody3D.new()
	add_child(body)
	for t: Vector3 in _tables:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = 0.7
		cyl.height = 0.8
		shape.shape = cyl
		shape.position = t + Vector3(0.0, 0.4, 0.0)
		body.add_child(shape)


func _make_steam() -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.6
	p.emitting = false
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 1.0, 0.0)
	m.spread = 12.0
	m.initial_velocity_min = 0.35
	m.initial_velocity_max = 0.6
	m.gravity = Vector3(0.0, 0.1, 0.0)
	m.scale_min = 0.6
	m.scale_max = 1.2
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct: CurveTexture = CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	p.process_material = m
	var puff: SphereMesh = SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	puff.radial_segments = 8
	puff.rings = 4
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = mat
	p.draw_pass_1 = puff
	return p


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


func _label(text: String, size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 16
	label.modulate = color
	label.outline_modulate = Color("#4A3020")
	return label
