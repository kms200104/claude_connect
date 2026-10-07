extends Node
## 집 안 걷기 검증: 평면도마다 집을 지어(벽·붙박이·처음 가구) 캐릭터 몸(캡슐 반지름)이 현관에서 모든 방과 현관문까지
## 실제로 지나갈 수 있는지 5cm 칸으로 퍼뜨려 본다. 문이 좁거나 붙박이가 길을 막으면 실패.
## 사용: godot --headless --path . res://tests/home_walk_check.tscn

const CELL: float = 0.05
## 캐릭터 캡슐 반지름 (game/player/player.tscn) + 여유.
const BODY_RADIUS: float = 0.42
## 이 높이 범위에 걸치는 충돌체만 걸음을 막는다 (문 위 인방·높은 찬장은 빼고).
const BODY_LOW: float = 0.12
const BODY_HIGH: float = 1.5
## 걸어서 닿지 않아도 되는 방 (밖에서 보는 공간).
const SKIP_KINDS: PackedStringArray = ["aircon"]

var _failures: int = 0
## --png=폴더 를 주면 평면마다 걸음 지도를 그린다 (검정 = 막힘, 회색 = 바닥이지만 못 감, 초록 = 걸어 닿음, 빨강 = 문 자리).
var _png: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--png="):
			_png = arg.trim_prefix("--png=")
	var ids: Array = GameData.econ.plans.keys()
	ids.sort()
	for id: Variant in ids:
		await _check_plan(GameData.econ.plans[id])
	print("HOME WALK %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_plan(plan: FloorPlan) -> void:
	var home: HomeInterior = HomeInterior.new()
	add_child(home)
	home.build(plan)
	var list: Array[Home.Furniture] = []
	for i: int in plan.defaults.size():
		var d: FloorPlan.Default = plan.defaults[i]
		var f: Home.Furniture = Home.Furniture.new()
		f.id = "d%d" % i
		f.item = d.item
		f.position = d.position
		f.rot = d.rot
		list.append(f)
	home.sync_furniture(list)
	await get_tree().process_frame
	var boxes: Array[AABB] = []
	for shape: Node in home.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = shape
		if cs.shape == null or cs.disabled:
			continue
		var box: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		if box.position.y < BODY_HIGH and box.end.y > BODY_LOW:
			boxes.append(box)
	var w: int = int(ceil(plan.size.x / CELL)) + 1
	var h: int = int(ceil(plan.size.y / CELL)) + 1
	var free: PackedByteArray = PackedByteArray()
	free.resize(w * h)
	for j: int in h:
		for i: int in w:
			var p: Vector2 = Vector2(i, j) * CELL
			var ok: bool = plan.on_floor(p)
			if ok:
				for b: AABB in boxes:
					var dx: float = maxf(maxf(b.position.x - p.x, p.x - b.end.x), 0.0)
					var dz: float = maxf(maxf(b.position.z - p.y, p.y - b.end.z), 0.0)
					if dx * dx + dz * dz < BODY_RADIUS * BODY_RADIUS:
						ok = false
						break
			free[j * w + i] = 1 if ok else 0
	# 현관 시작 자리에서 퍼뜨린다.
	var start: Vector2i = _nearest_free(free, w, h, plan.spawn)
	var reached: PackedByteArray = PackedByteArray()
	reached.resize(w * h)
	if start.x >= 0:
		var queue: Array[Vector2i] = [start]
		reached[start.y * w + start.x] = 1
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var k: int = n.y * w + n.x
				if free[k] == 1 and reached[k] == 0:
					reached[k] = 1
					queue.append(n)
	_check(start.x >= 0, "%s: 현관 시작 자리에 설 수 있다" % plan.id)
	for room: FloorPlan.Room in plan.rooms:
		if room.kind in SKIP_KINDS:
			continue
		var hit: bool = false
		for r: Rect2 in room.rects:
			for j: int in range(int(r.position.y / CELL), int(r.end.y / CELL) + 1):
				for i: int in range(int(r.position.x / CELL), int(r.end.x / CELL) + 1):
					if i >= 0 and j >= 0 and i < w and j < h and reached[j * w + i] == 1:
						hit = true
						break
				if hit:
					break
			if hit:
				break
		_check(hit, "%s: 현관에서 %s(%s)까지 걸어갈 수 있다" % [plan.id, room.id, room.kind])
	if not _png.is_empty():
		var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
		for j: int in h:
			for i: int in w:
				var k: int = j * w + i
				var on: bool = plan.on_floor(Vector2(i, j) * CELL)
				img.set_pixel(i, j, Color(0.2, 0.75, 0.3) if reached[k] == 1 else (Color(0.6, 0.6, 0.6) if free[k] == 1 else (Color(0.05, 0.05, 0.05) if on else Color(1, 1, 1))))
		for d: Vector2 in plan.doors:
			var c: Vector2i = Vector2i(int(d.x / CELL), int(d.y / CELL))
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if c.x + dx >= 0 and c.y + dy >= 0 and c.x + dx < w and c.y + dy < h:
						img.set_pixel(c.x + dx, c.y + dy, Color.RED)
		img.resize(w * 3, h * 3, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/walk_%s.png" % [_png, plan.id])
	var door: Vector2i = _nearest_free(free, w, h, plan.front, 1.0)
	_check(door.x >= 0 and reached[door.y * w + door.x] == 1, "%s: 현관문 앞까지 걸어갈 수 있다" % plan.id)
	home.queue_free()


func _nearest_free(free: PackedByteArray, w: int, h: int, at: Vector2, max_dist: float = 0.8) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = max_dist
	var c: Vector2i = Vector2i(int(round(at.x / CELL)), int(round(at.y / CELL)))
	var r: int = int(ceil(max_dist / CELL))
	for j: int in range(c.y - r, c.y + r + 1):
		for i: int in range(c.x - r, c.x + r + 1):
			if i < 0 or j < 0 or i >= w or j >= h or free[j * w + i] == 0:
				continue
			var d: float = (Vector2(i, j) * CELL).distance_to(at)
			if d < best_d:
				best_d = d
				best = Vector2i(i, j)
	return best


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	print("[walk] %s: %s" % ["ok  " if ok else "FAIL", what])
