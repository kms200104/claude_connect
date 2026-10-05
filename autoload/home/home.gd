extends Node
## 집 안 상태 (v0.10) — 서버가 보낸 값만 들고 있다: 지금 들어가 있는 호수, 평면도, 집 안 원점, 주인, 가구.
## 들어가기·나가기·가구 놓기/옮기기/회수 요청을 보낸다. 판정(현관 앞인지, 내 집인지, 바닥 위인지)은 서버가 한다.

## 집에 들어갔다 (unit) / 나왔다 (unit = ""). position = 서버가 옮겨 준 자리.
signal door_passed(unit: String, position: Vector3)
## 가구 목록이 바뀌었다 (서버가 확정한 목록).
signal furniture_changed
signal failed(kind: String, code: String)

const KINDS: PackedStringArray = ["home_enter", "home_exit", "home_place", "home_move", "home_pickup"]

## 집 안 가구 하나 (평면도 기준 미터, rot = 45° 단위 0~7).
class Furniture:
	var id: String = ""
	var item: String = ""
	var position: Vector2 = Vector2.ZERO
	var rot: int = 0

## 들어가 있는 호수 ("" = 집 밖).
var unit: String = ""
var plan: FloorPlan = null
## 집 안 월드 원점 (평면도 왼쪽 위).
var origin: Vector3 = Vector3.ZERO
## 주인 자리 번호 (0 = 아직 아무도 안 산 집 — 모델하우스처럼 구경만).
var owner_slot: int = 0
## 가구를 옮길 수 있는지 (내 집 · 우리 세대 집).
var editable: bool = false
var furniture: Array[Furniture] = []
## 서버가 마지막으로 확정한 목록 (옮기기가 거절되면 이걸로 되돌린다).
var _confirmed: Array = []


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind in KINDS:
			if kind == "home_move":
				_apply_furniture(_confirmed)
			failed.emit(kind, code))
	Net.state_changed.connect(func(s: int) -> void:
		if s == Net.State.DISCONNECTED:
			_clear())


func is_inside() -> bool:
	return not unit.is_empty()


func find(id: String) -> Furniture:
	for f: Furniture in furniture:
		if f.id == id:
			return f
	return null


## 평면도 기준 (x, z) → 월드.
func to_world(at: Vector2) -> Vector3:
	return origin + Vector3(at.x, 0.0, at.y)


## 월드 → 평면도 기준.
func to_local(world: Vector3) -> Vector2:
	return Vector2(world.x - origin.x, world.z - origin.z)


## 현관문 바깥쪽 앞 (나가기 버튼이 뜨는 자리의 기준).
func front_world() -> Vector3:
	return to_world(plan.front) if plan != null else Vector3.ZERO


func enter(unit_id: String) -> void:
	Net.request("home_enter", {"unit": unit_id})


func exit() -> void:
	Net.request("home_exit")


func place(slot: int, at: Vector2, rot: int) -> void:
	Net.request("home_place", {"slot": slot, "x": snappedf(at.x, 0.01), "z": snappedf(at.y, 0.01), "rot": posmod(rot, 8)})


func move(id: String, at: Vector2, rot: int) -> void:
	# 서버 답을 기다리는 동안에도 그 자리에 보이게 먼저 옮겨 둔다 (거절되면 서버 목록으로 되돌아간다).
	var f: Furniture = find(id)
	if f != null:
		f.position = at
		f.rot = posmod(rot, 8)
	Net.request("home_move", {"id": id, "x": snappedf(at.x, 0.01), "z": snappedf(at.y, 0.01), "rot": posmod(rot, 8)})


func pickup(id: String) -> void:
	Net.request("home_pickup", {"id": id})


## 보이지 않는 격자 (서버와 같은 간격, 기본 0.25m).
func grid() -> float:
	return float(GameData.econ.home_rules.get("grid", 0.25)) if GameData.econ != null else 0.25


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			_clear()
		"home":
			var at: Vector3 = Vector3(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)), float(msg.get("z", 0.0)))
			unit = str(msg.get("unit", ""))
			if unit.is_empty():
				_clear()
			else:
				plan = GameData.econ.plans.get(str(msg.get("plan", ""))) if GameData.econ != null else null
				origin = Vector3(float(msg.get("ox", 0.0)), 0.0, float(msg.get("oz", 0.0)))
				owner_slot = int(msg.get("owner", 0))
				editable = bool(msg.get("edit", false))
				_apply_furniture(msg.get("f", []))
			door_passed.emit(unit, at)
		"home_f":
			if str(msg.get("unit", "")) == unit:
				_apply_furniture(msg.get("f", []))


func _apply_furniture(list: Variant) -> void:
	furniture.clear()
	_confirmed = (list as Array).duplicate(true) if list is Array else []
	if list is Array:
		for entry: Variant in list:
			if entry is Array and (entry as Array).size() >= 5:
				var f: Furniture = Furniture.new()
				f.id = str(entry[0])
				f.item = str(entry[1])
				f.position = Vector2(float(entry[2]), float(entry[3]))
				f.rot = posmod(int(entry[4]), 8)
				furniture.append(f)
	furniture_changed.emit()


func _clear() -> void:
	unit = ""
	plan = null
	owner_slot = 0
	editable = false
	furniture.clear()
