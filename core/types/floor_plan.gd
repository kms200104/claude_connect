class_name FloorPlan
extends RefCounted
## 아파트 평면도 하나 (data/realestate/floorplans.json). 그림 픽셀 좌표를 scale 로 미터로 바꾼다 — 서버 homes.js 의 planInMeters 와 같은 식.
## 좌표는 평면도 왼쪽 위(북서쪽)가 (0, 0), +x 동쪽, +y(= 월드 +z) 남쪽(발코니·큰 창).

## 방 하나: 종류(kind)와 사각형들 (미터).
class Room:
	var id: String = ""
	var kind: String = ""
	var rects: Array[Rect2] = []

	func area() -> float:
		var a: float = 0.0
		for r: Rect2 in rects:
			a += r.get_area()
		return a

	## 가장 큰 사각형 (방 이름표·조명 자리).
	func main_rect() -> Rect2:
		var best: Rect2 = rects[0]
		for r: Rect2 in rects:
			if r.get_area() > best.get_area():
				best = r
		return best

## 처음 놓이는 가구.
class Default:
	var item: String = ""
	var position: Vector2 = Vector2.ZERO
	var rot: int = 0

var id: String = ""
var display_name: String = ""
var pyeong: int = 0
var size: Vector2 = Vector2.ZERO
var rooms: Array[Room] = []
## 방과 방 사이 문 자리 (그 벽을 door_width 만큼 비운다).
var doors: Array[Vector2] = []
## 현관문 (바깥으로 나가는 문, 현관 북쪽 벽 위).
var front: Vector2 = Vector2.ZERO
## 들어오면 서는 자리 (현관 가운데).
var spawn: Vector2 = Vector2.ZERO
var defaults: Array[Default] = []


static func from_dict(plan_id: String, raw: Dictionary) -> FloorPlan:
	var p: FloorPlan = FloorPlan.new()
	p.id = plan_id
	p.display_name = str(raw.get("name", plan_id))
	p.pyeong = int(raw.get("pyeong", 0))
	var s: float = float(raw.get("scale", 0.02))
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for room: Variant in raw.get("rooms", []):
		for r: Variant in (room as Dictionary).get("r", []):
			lo = lo.min(Vector2(float(r[0]), float(r[1])))
			hi = hi.max(Vector2(float(r[2]), float(r[3])))
	var to_m: Callable = func(x: float, y: float) -> Vector2:
		return Vector2(snappedf((x - lo.x) * s, 0.001), snappedf((y - lo.y) * s, 0.001))
	p.size = to_m.call(hi.x, hi.y)
	for room_raw: Variant in raw.get("rooms", []):
		var rd: Dictionary = room_raw
		var room: Room = Room.new()
		room.id = str(rd.get("id", ""))
		room.kind = str(rd.get("kind", ""))
		for r: Variant in rd.get("r", []):
			var a: Vector2 = to_m.call(float(r[0]), float(r[1]))
			var b: Vector2 = to_m.call(float(r[2]), float(r[3]))
			room.rects.append(Rect2(a, b - a))
		p.rooms.append(room)
	for d: Variant in raw.get("doors", []):
		p.doors.append(to_m.call(float(d[0]), float(d[1])))
	var f: Array = raw.get("front", [0, 0])
	p.front = to_m.call(float(f[0]), float(f[1]))
	var entry: Room = p.first_room("entry")
	if entry != null:
		var e: Rect2 = entry.rects[0]
		p.spawn = Vector2(snappedf(e.get_center().x, 0.001), snappedf(e.get_center().y + 0.15, 0.001))
	for d: Variant in raw.get("defaults", []):
		var dd: Dictionary = d
		var def: Default = Default.new()
		def.item = str(dd.get("item", ""))
		var at: Array = dd.get("at", [0, 0])
		def.position = to_m.call(float(at[0]), float(at[1]))
		def.rot = posmod(int(dd.get("rot", 0)), 8)
		p.defaults.append(def)
	return p


func first_room(kind: String) -> Room:
	for r: Room in rooms:
		if r.kind == kind:
			return r
	return null


## 그 자리가 바닥(방 사각형 하나) 안인지. margin 만큼 안쪽이어야 한다 (서버 onFloor 와 같다).
func on_floor(at: Vector2, margin: float = 0.0) -> bool:
	for room: Room in rooms:
		for r: Rect2 in room.rects:
			if at.x >= r.position.x + margin and at.x <= r.end.x - margin and at.y >= r.position.y + margin and at.y <= r.end.y - margin:
				return true
	return false


## 그 자리의 방 (없으면 null).
func room_at(at: Vector2) -> Room:
	for room: Room in rooms:
		for r: Rect2 in room.rects:
			if r.grow(0.001).has_point(at):
				return room
	return null


func bedroom_count() -> int:
	var n: int = 0
	for r: Room in rooms:
		if r.kind == "bedroom" or r.kind == "master":
			n += 1
	return n
