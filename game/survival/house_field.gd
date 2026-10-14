class_name HouseField
extends Node3D
## v0.23 솔내 옛마을 빈집촌: 사람이 떠난 1층 단층집 16채 (data/survival/houses.json · GameData.survival).
## 집마다: 마루 바닥 · 바깥벽 · 방 칸막이(문틈) · 창(판자로 막힌 집도) · 쓰러진 현관문 · 함석 박공지붕(안에 들어가면 지붕을 걷는다) ·
## 마당의 무성한 풀 · 기운 울타리, 안에는 뒤질 수 있는 가구(신발장 · 냉장고 · 싱크대 · 서랍장 · 옷장 · 욕실 약장)와
## 그냥 놓인 가구(밥상 · 넘어진 의자 · 침대 · 변기 · 욕조). 뒤진 가구는 문이 열리고 서랍이 빠진 모습이 된다 (다시 차면 닫힌다).
## v0.24 거점: 깨진 창(검은 구멍 · 유리 조각)과 떨어진 현관문 자리에 판자를 대면 판자(안팎) · 판자문이 보인다.
## 반쯤 부서지면 금 간 판자, 크리처가 두드리면 흔들린다. 판자문은 사람이 다가가면 열린다 (사람은 지나가고 크리처는 못 지나간다).

@export var clay_material: Material
@export var window_material: Material
@export var player: Node3D
@export_range(40.0, 400.0, 10.0, "suffix:m") var draw_distance: float = 150.0

const WALL_H: float = 2.7
const FLOOR_WOOD: Color = Color("#A27A52")
const DARK: Color = Color("#3E3A36")
const PLANK: Color = Color("#8A6440")
const WHITE: Color = Color("#ECEAE4")

## 집 id → 지붕 메시 (안에 들어가면 숨긴다).
var _roofs: Dictionary[String, MeshInstance3D] = {}
## 가구 id → [닫힌 모습, 열린 모습] 메시.
var _boxes: Dictionary[String, Array] = {}
## 뚫린 곳 key ("집:자리") → [판자 노드, 멀쩡한 판자 메시, 금 간 판자 메시].
var _boards: Dictionary[String, Array] = {}
## 현관 key → 판자문 경첩 · 떨어진 옛 문.
var _door_hinges: Dictionary[String, Node3D] = {}
var _fallen_doors: Dictionary[String, Node3D] = {}


func _ready() -> void:
	var rules: SurvivalRules = GameData.survival
	for h: SurvivalRules.House in rules.houses:
		_build_house(h, rules)
	Net.container_changed.connect(func(_id: String, _until: float) -> void: _refresh_boxes())
	Net.welcomed.connect(_refresh_boxes.unbind(3))
	Net.welcomed.connect(_refresh_boards.unbind(3))
	Net.board_changed.connect(_on_board_changed)
	_refresh_boxes()
	_refresh_boards()


func _process(delta: float) -> void:
	if player == null:
		return
	for h: SurvivalRules.House in GameData.survival.houses:
		var roof: MeshInstance3D = _roofs.get(h.id)
		if roof != null:
			roof.visible = not h.contains(player.global_position, 0.6)
	# 판자문: 사람이 곁에 오면 안으로 열린다.
	var people: Array[Vector3] = [player.global_position]
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if replicator != null:
		people.append_array(replicator.remote_positions())
	for key: String in _door_hinges:
		var hinge: Node3D = _door_hinges[key]
		if not hinge.visible:
			continue
		var at: Vector3 = GameData.survival.breaches[key].position
		var near: bool = false
		for p: Vector3 in people:
			if Vector2(p.x - at.x, p.z - at.z).length() < 1.9:
				near = true
				break
		hinge.rotation.y = move_toward(hinge.rotation.y, 1.5 if near else 0.0, delta * 5.0)


func _on_board_changed(key: String, _hp: int, info: Dictionary) -> void:
	_refresh_boards()
	# 크리처가 두드리면 흔들린다.
	var parts: Array = _boards.get(key, [])
	if parts.is_empty() or int(info.get("by", -1)) != 0:
		return
	var node: Node3D = parts[0]
	var rest: Vector3 = node.get_meta(&"rest", node.position)
	node.set_meta(&"rest", rest)
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "position", rest + Vector3(0.0, 0.0, 0.06), 0.05)
	tween.tween_property(node, "position", rest, 0.12)


## 판자 hp 에 맞게: 없음 · 멀쩡함 · 금 감 (절반 이하).
func _refresh_boards() -> void:
	for key: String in _boards:
		var hp: int = int(Net.boards.get(key, 0))
		var br: SurvivalRules.Breach = GameData.survival.breaches[key]
		var parts: Array = _boards[key]
		(parts[0] as Node3D).visible = hp > 0
		(parts[1] as Node3D).visible = hp * 2 > br.max_hp
		(parts[2] as Node3D).visible = hp > 0 and hp * 2 <= br.max_hp
		if _fallen_doors.has(key):
			_fallen_doors[key].visible = hp <= 0


## 뒤진 가구는 열린 모습으로.
func _refresh_boxes() -> void:
	for id: String in _boxes:
		var open: bool = not Net.can_loot(id)
		(_boxes[id][0] as Node3D).visible = not open
		(_boxes[id][1] as Node3D).visible = open


func _build_house(h: SurvivalRules.House, rules: SurvivalRules) -> void:
	var root: Node3D = Node3D.new()
	root.name = "House_%s" % h.id
	add_child(root)
	root.position = h.position
	root.rotation.y = h.yaw
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(h.id)
	var clay: BoxBatch = BoxBatch.new()
	var glass: BoxBatch = BoxBatch.new()
	var hw: float = h.size.x * 0.5
	var hd: float = h.size.y * 0.5
	var inner: Color = h.wall.lightened(0.08)
	# 기단 · 마루.
	clay.box(Vector3(0.0, 0.08, 0.0), Vector3(h.size.x + 0.6, 0.16, h.size.y + 0.6), Color("#9C978E"))
	clay.box(Vector3(0.0, 0.18, 0.0), Vector3(h.size.x - 0.1, 0.04, h.size.y - 0.1), FLOOR_WOOD)
	# 장판 (앞방 노란 장판, 뒷방 꽃무늬 느낌).
	clay.box(Vector3(0.0, 0.205, 2.0), Vector3(h.size.x - 0.4, 0.01, 3.7), Color("#D9B76A"))
	clay.box(Vector3(-1.5, 0.205, -2.0), Vector3(6.6, 0.01, 3.7), Color("#C9A27A"))
	# 벽 (칸막이 선분, 높이 WALL_H).
	var body: StaticBody3D = StaticBody3D.new()
	root.add_child(body)
	for w: Array in rules.walls:
		var a: Vector2 = Vector2(float(w[0][0]), float(w[0][1]))
		var b: Vector2 = Vector2(float(w[1][0]), float(w[1][1]))
		var mid: Vector2 = (a + b) * 0.5
		var length: float = a.distance_to(b)
		var outer: bool = absf(absf(mid.x) - hw) < 0.05 or absf(absf(mid.y) - hd) < 0.05
		var size: Vector3 = Vector3(length + 0.2, WALL_H, 0.22) if absf(a.y - b.y) < 0.01 else Vector3(0.22, WALL_H, length + 0.2)
		clay.box(Vector3(mid.x, 0.2 + WALL_H * 0.5, mid.y), size, h.wall if outer else inner)
		# 벽 아래 걸레받이 · 바깥벽 아래 얼룩 (물 자국).
		if outer:
			clay.box(Vector3(mid.x, 0.55, mid.y), size * Vector3(1.0, 0.0, 1.0) + Vector3(0.02, 0.5, 0.02), h.wall.darkened(0.22))
		_collider(body, Vector3(mid.x, 1.4, mid.y), size)
	# 창 (houses.json openings): 멀쩡한 창은 유리, 깨진 창은 검은 구멍 · 유리 조각 (판자를 댈 수 있다).
	for o: Dictionary in rules.openings:
		var oid: String = str(o.get("id", ""))
		var normal: Vector2 = Vector2(float(o.get("nx", 0.0)), float(o.get("nz", 0.0)))
		var center: Vector3 = Vector3(float(o.get("lx", 0.0)), 1.6, float(o.get("lz", 0.0)))
		if str(o.get("kind", "")) == "door":
			_build_door(root, "%s:%s" % [h.id, oid], center, hd)
			continue
		var along_x: bool = absf(normal.y) > 0.5
		var out: Vector3 = Vector3(normal.x, 0.0, normal.y) * 0.13
		var pane: Vector3 = Vector3(1.4, 1.0, 0.04) if along_x else Vector3(0.04, 1.0, 1.4)
		var frame: Vector3 = Vector3(1.6, 0.1, 0.1) if along_x else Vector3(0.1, 0.1, 1.6)
		var broken: bool = h.broken.has(oid)
		var tip: Vector3 = Vector3(0.5, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 0.5)
		var spin: Vector3 = Vector3(normal.x, 0.0, normal.y)
		for face: float in ([1.0, -1.0] if broken else [1.0]):
			var at: Vector3 = center + out * face
			if broken:
				clay.box(at, pane, Color("#24201C"))
				# 남은 유리 조각.
				glass.box(at + tip + Vector3(0, 0.3, 0) + out * (0.1 * face), pane * Vector3(0.25, 0.35, 1.0) + Vector3(0, 0, 0.01), Color.WHITE, Basis(spin, 0.5))
				glass.box(at - tip - Vector3(0, 0.32, 0) + out * (0.1 * face), pane * Vector3(0.2, 0.3, 1.0) + Vector3(0, 0, 0.01), Color.WHITE, Basis(spin, -0.4))
			else:
				glass.box(at, pane, Color.WHITE)
			clay.box(at + Vector3(0, -0.55, 0), frame, Color("#6E5A44"))
			clay.box(at + Vector3(0, 0.55, 0), frame, Color("#6E5A44"))
		if broken:
			_build_window_boards(root, "%s:%s" % [h.id, oid], center, normal, along_x)
	# 현관 문틀 (떨어진 옛 문 · 판자문은 _build_door).
	clay.box(Vector3(-3.0, 0.2 + 2.2, hd), Vector3(1.4, 0.15, 0.3), Color("#6E5A44"))
	# 지붕 (따로: 안에 들어가면 숨긴다) — 함석 박공 두 장 + 박공 벽.
	var roof_batch: BoxBatch = BoxBatch.new()
	var slope: float = 0.42
	var half_span: float = hd + 0.6
	var rise: float = tan(slope) * half_span
	for s: float in [-1.0, 1.0]:
		roof_batch.box(Vector3(0.0, 0.2 + WALL_H + rise * 0.5 + 0.1, s * half_span * 0.5), Vector3(h.size.x + 0.9, 0.12, half_span / cos(slope) + 0.1), h.roof if s > 0 else h.roof.darkened(0.12), Basis(Vector3.RIGHT, -s * slope))
		# 골 (함석 줄무늬).
		for k: int in 7:
			var x: float = -hw + 0.6 + float(k) * (h.size.x - 1.2) / 6.0
			roof_batch.box(Vector3(x, 0.2 + WALL_H + rise * 0.5 + 0.18, s * half_span * 0.5), Vector3(0.06, 0.04, half_span / cos(slope)), h.roof.darkened(0.25), Basis(Vector3.RIGHT, -s * slope))
	for s: float in [-1.0, 1.0]:
		for k: int in 4:
			var t: float = float(k) / 4.0
			roof_batch.box(Vector3(s * (hw + 0.05), 0.2 + WALL_H + rise * (t + 0.125), 0.0), Vector3(0.18, rise / 4.0, (1.0 - t) * h.size.y), h.wall.darkened(0.06))
	roof_batch.box(Vector3(0.0, 0.2 + WALL_H + rise + 0.12, 0.0), Vector3(h.size.x + 1.0, 0.16, 0.3), h.roof.darkened(0.3))
	var roof: MeshInstance3D = _mesh(roof_batch, clay_material, "Roof")
	root.add_child(roof)
	_roofs[h.id] = roof
	# 그냥 놓인 가구 (뒤지지 않는다): 밥상 · 넘어진 의자 · 침대 · 변기 · 욕조 · 벽시계.
	clay.box(Vector3(-1.5, 0.45, 2.0), Vector3(1.4, 0.06, 0.9), Color("#8A5A35"))
	for lx: float in [-2.1, -0.9]:
		for lz: float in [1.65, 2.35]:
			clay.box(Vector3(lx, 0.33, lz), Vector3(0.06, 0.26, 0.06), Color("#6E4628"))
	clay.box(Vector3(0.0, 0.42, 2.8), Vector3(0.5, 0.06, 0.5), Color("#9A6A40"), Basis(Vector3.BACK, 1.3))
	clay.box(Vector3(-3.2, 0.45, -2.5), Vector3(1.6, 0.3, 2.2), Color("#E0D8CC"))
	clay.box(Vector3(-3.2, 0.62, -3.5), Vector3(1.6, 0.18, 0.4), Color("#C9B7D8"))
	clay.box(Vector3(3.4, 0.55, -1.0), Vector3(0.5, 0.7, 0.6), WHITE)
	clay.box(Vector3(3.9, 0.5, -2.6), Vector3(1.2, 0.6, 1.4), Color("#D8E4EA"))
	clay.box(Vector3(0.6, 2.2, -0.12), Vector3(0.4, 0.4, 0.04), Color("#F4F0E8"))
	# 먼지 · 떨어진 물건.
	for k: int in 6:
		clay.box(Vector3(rng.randf_range(-hw + 0.8, hw - 0.8), 0.23, rng.randf_range(-hd + 0.8, hd - 0.8)), Vector3(rng.randf_range(0.15, 0.4), 0.04, rng.randf_range(0.1, 0.3)), Color("#7A6A5A").lightened(rng.randf() * 0.3), Basis(Vector3.UP, rng.randf() * TAU))
	# 마당: 무성한 풀 덤불 · 기운 울타리 · 깨진 화분.
	for k: int in 8:
		var gx: float = rng.randf_range(-hw - 2.0, hw + 2.0)
		var gz: float = hd + rng.randf_range(0.8, 3.6)
		clay.box(Vector3(gx, 0.3, gz), Vector3(rng.randf_range(0.5, 1.1), rng.randf_range(0.4, 0.8), rng.randf_range(0.5, 1.0)), Color("#5E8A44").lightened(rng.randf() * 0.2), Basis(Vector3.UP, rng.randf() * TAU))
	for k: int in 9:
		var fx: float = -hw - 1.0 + float(k) * (h.size.x + 2.0) / 8.0
		clay.box(Vector3(fx, 0.5, hd + 4.2), Vector3(0.08, 1.0, 0.08), Color("#8A7A62"), Basis(Vector3.RIGHT, 0.15 * float(k % 3 - 1)))
	clay.box(Vector3(0.0, 0.85, hd + 4.2), Vector3(h.size.x + 2.0, 0.08, 0.06), Color("#8A7A62"), Basis(Vector3.BACK, 0.04))
	# 뒤질 수 있는 가구 (닫힌 모습 · 열린 모습 따로).
	for c: SurvivalRules.LootBox in h.containers:
		_build_box(root, body, c)
	var mi: MeshInstance3D = _mesh(clay, clay_material, "Body")
	root.add_child(mi)
	root.add_child(_mesh(glass, window_material, "Glass"))


## 깨진 창 판자: 바깥 · 안쪽에 엇갈린 판자 셋 (멀쩡함) / 둘 + 늘어진 하나 (금 감).
func _build_window_boards(root: Node3D, key: String, center: Vector3, normal: Vector2, along_x: bool) -> void:
	var node: Node3D = Node3D.new()
	node.name = "Boards_%s" % key.replace(":", "_")
	root.add_child(node)
	node.position = center
	var whole: BoxBatch = BoxBatch.new()
	var cracked: BoxBatch = BoxBatch.new()
	var axis: Vector3 = Vector3.BACK if along_x else Vector3.RIGHT
	var plank: Vector3 = Vector3(1.8, 0.2, 0.05) if along_x else Vector3(0.05, 0.2, 1.8)
	var tip: Vector3 = Vector3(0.75, 0, 0) if along_x else Vector3(0, 0, 0.75)
	var tilts: Array[float] = [0.18, -0.12, 0.08]
	for face: float in [1.0, -1.0]:
		var out: Vector3 = Vector3(normal.x, 0.0, normal.y) * (0.2 * face)
		for k: int in 3:
			var y: float = -0.35 + 0.35 * float(k)
			whole.box(out + Vector3(0, y, 0), plank, PLANK.darkened(0.08 * float(k)), Basis(axis, tilts[k]))
			if k < 2:
				cracked.box(out + Vector3(0, y, 0), plank, PLANK.darkened(0.2 + 0.08 * float(k)), Basis(axis, tilts[k]))
			else:
				cracked.box(out + Vector3(0, y - 0.25, 0), plank * Vector3(0.6, 1.0, 0.6) + Vector3(0.02, 0.0, 0.02), PLANK.darkened(0.3), Basis(axis, 0.7))
		# 못 대가리.
		for sgn: float in [1.0, -1.0]:
			whole.box(out * 1.15 + tip * sgn, Vector3(0.05, 0.05, 0.05), DARK)
	var a: MeshInstance3D = _mesh(whole, clay_material, "Whole")
	var b: MeshInstance3D = _mesh(cracked, clay_material, "Cracked")
	node.add_child(a)
	node.add_child(b)
	node.visible = false
	_boards[key] = [node, a, b]


## 현관: 판자를 대지 않았으면 떨어져 기운 옛 문, 대면 경첩에 달린 판자문 (사람이 다가가면 열린다, 부딪힘 없음).
func _build_door(root: Node3D, key: String, center: Vector3, hd: float) -> void:
	var fallen: BoxBatch = BoxBatch.new()
	fallen.box(Vector3(-1.7, 0.2 + 0.9, hd + 0.7), Vector3(0.9, 1.9, 0.06), Color("#5E7A8A"), Basis(Vector3.UP, 1.1) * Basis(Vector3.BACK, 0.12))
	var old: MeshInstance3D = _mesh(fallen, clay_material, "FallenDoor")
	root.add_child(old)
	_fallen_doors[key] = old
	var hinge: Node3D = Node3D.new()
	hinge.name = "Door_%s" % key.replace(":", "_")
	root.add_child(hinge)
	hinge.position = Vector3(center.x - 0.6, 0.2, hd)
	var whole: BoxBatch = BoxBatch.new()
	var cracked: BoxBatch = BoxBatch.new()
	for batch: BoxBatch in [whole, cracked]:
		var worn: bool = batch == cracked
		var dark: float = 0.22 if worn else 0.0
		for k: int in 4:
			var tall: float = 2.1 - (0.3 if worn and k == 3 else 0.0)
			batch.box(Vector3(0.15 + 0.3 * float(k), tall * 0.5, 0.0), Vector3(0.28, tall, 0.06), PLANK.darkened(dark + 0.05 * float(k % 2)))
		# 가로대 · 손잡이.
		batch.box(Vector3(0.6, 1.6, 0.06), Vector3(1.15, 0.14, 0.05), PLANK.darkened(0.25 + dark))
		batch.box(Vector3(0.6, 0.5, 0.06), Vector3(1.15, 0.14, 0.05), PLANK.darkened(0.25 + dark), Basis(Vector3.BACK, 0.15 if worn else 0.0))
		batch.box(Vector3(1.0, 1.05, 0.1), Vector3(0.08, 0.08, 0.08), DARK)
	var a: MeshInstance3D = _mesh(whole, clay_material, "Whole")
	var b: MeshInstance3D = _mesh(cracked, clay_material, "Cracked")
	hinge.add_child(a)
	hinge.add_child(b)
	hinge.visible = false
	_boards[key] = [hinge, a, b]
	_door_hinges[key] = hinge


func _build_box(root: Node3D, body: StaticBody3D, c: SurvivalRules.LootBox) -> void:
	var closed: BoxBatch = BoxBatch.new()
	var opened: BoxBatch = BoxBatch.new()
	var basis: Basis = Basis(Vector3.UP, c.yaw)
	var at: Vector3 = Vector3(c.local.x, 0.2, c.local.y)
	# 가구 로컬: 앞면이 +Z (yaw 로 돌린다). size = (폭, 높이, 깊이).
	var size: Vector3 = Vector3.ONE
	var color: Color = WHITE
	match c.kind:
		"shoe_cabinet":
			size = Vector3(1.0, 1.0, 0.4)
			color = Color("#B88A5A")
		"fridge":
			size = Vector3(0.75, 1.8, 0.7)
			color = Color("#E8ECEE")
		"sink":
			size = Vector3(1.6, 0.9, 0.6)
			color = Color("#D8D2C6")
		"drawer":
			size = Vector3(1.2, 0.9, 0.45)
			color = Color("#9A6A40")
		"wardrobe":
			size = Vector3(1.2, 2.0, 0.6)
			color = Color("#8A6440")
		"medicine":
			size = Vector3(0.6, 0.6, 0.18)
			color = Color("#F4F0E8")
			at.y = 1.3
	var center: Vector3 = at + Vector3(0.0, size.y * 0.5, 0.0)
	var front: Vector3 = basis * Vector3(0.0, 0.0, size.z * 0.5 + 0.02)
	for batch: BoxBatch in [closed, opened]:
		batch.box(center, size, color, basis)
	match c.kind:
		"fridge":
			closed.box(center + front + basis * Vector3(0.28, 0.25, 0.0), Vector3(0.04, 0.4, 0.04), DARK, basis)
			closed.box(center + front + basis * Vector3(0.0, 0.3, 0.0), Vector3(size.x - 0.02, 0.02, 0.02), Color("#B8BEC2"), basis)
			opened.box(center + basis * Vector3(-size.x * 0.5 - 0.3, 0.1, size.z * 0.5 + 0.3), Vector3(0.05, 1.6, 0.72), color, basis * Basis(Vector3.UP, -1.1))
			opened.box(center + front * 0.6, Vector3(size.x - 0.12, 1.6, 0.04), Color("#9AA3AA"), basis)
		"drawer", "shoe_cabinet", "sink":
			var rows: int = 3 if c.kind == "drawer" else 2
			for k: int in rows:
				var y: float = -size.y * 0.5 + (float(k) + 0.5) * size.y / float(rows)
				closed.box(center + front + basis * Vector3(0.0, y, 0.0), Vector3(size.x - 0.1, size.y / float(rows) - 0.08, 0.03), color.lightened(0.1), basis)
				closed.box(center + front + basis * Vector3(0.0, y, 0.03), Vector3(0.2, 0.04, 0.03), DARK, basis)
			# 열린 모습: 빠져나온 서랍 · 열린 문짝.
			opened.box(center + basis * Vector3(0.0, size.y * 0.2, size.z * 0.5 + 0.22), Vector3(size.x - 0.14, size.y / float(rows) - 0.1, 0.42), color.darkened(0.15), basis)
			opened.box(center + front + basis * Vector3(0.0, -size.y * 0.2, 0.0), Vector3(size.x - 0.1, 0.03, 0.03), DARK, basis)
			if c.kind == "sink":
				closed.box(center + Vector3(0.0, size.y * 0.5 + 0.02, 0.0), Vector3(size.x, 0.04, size.z), Color("#B8C0C6"), basis)
				opened.box(center + Vector3(0.0, size.y * 0.5 + 0.02, 0.0), Vector3(size.x, 0.04, size.z), Color("#B8C0C6"), basis)
		"wardrobe", "medicine":
			closed.box(center + front, Vector3(0.02, size.y - 0.1, 0.03), DARK, basis)
			closed.box(center + front + basis * Vector3(0.1, 0.0, 0.0), Vector3(0.04, 0.2, 0.04), Color("#C9A23A"), basis)
			closed.box(center + front + basis * Vector3(-0.1, 0.0, 0.0), Vector3(0.04, 0.2, 0.04), Color("#C9A23A"), basis)
			opened.box(center + basis * Vector3(size.x * 0.5 + 0.2, 0.0, size.z * 0.5 + 0.25), Vector3(size.x * 0.5, size.y - 0.1, 0.04), color, basis * Basis(Vector3.UP, 1.2))
			opened.box(center + front * 0.5, Vector3(size.x - 0.1, size.y - 0.1, 0.02), color.darkened(0.45), basis)
	var a: MeshInstance3D = _mesh(closed, clay_material, "Box_%s" % c.id)
	var b: MeshInstance3D = _mesh(opened, clay_material, "BoxOpen_%s" % c.id)
	b.visible = false
	root.add_child(a)
	root.add_child(b)
	_boxes[c.id] = [a, b]
	if c.kind != "medicine":
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.transform = Transform3D(basis, center)
		body.add_child(shape)


func _collider(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


func _mesh(batch: BoxBatch, material: Material, node_name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = batch.commit()
	mi.material_override = material
	mi.visibility_range_end = draw_distance
	return mi
