class_name ShopData
extends RefCounted
## data/shop/shop.json — 서버 판정(문 거리, 실내 범위)과 같은 값.

class Level:
	var level: int = 1
	var display_name: String = ""
	## 이 단계가 되는 상점 포인트.
	var points: int = 0
	## 팔 때 더 쳐주는 비율 (0.1 = 10%).
	var sell_bonus: float = 0.0
	var stock: PackedStringArray = []

var keeper: NpcInfo = null
## 바깥 문 앞(들어가기 판정 기준)과 나왔을 때 서는 곳.
var door: Vector3 = Vector3.ZERO
var outside_spawn: Vector3 = Vector3.ZERO
var enter_range: float = 2.2
## 실내 공간 (마을에서 멀리 떨어진 곳). 가운데와 반 너비·깊이.
var interior_center: Vector3 = Vector3.ZERO
var interior_half: Vector2 = Vector2.ONE
var inside_spawn: Vector3 = Vector3.ZERO
## 실내 출구 (나가기 판정 기준).
var exit: Vector3 = Vector3.ZERO
var exit_range: float = 1.8
## 실내 방의 남쪽 벽(출구) 가운데. 방은 여기서 -Z 쪽으로 펼쳐진다.
var room_origin: Vector3 = Vector3.ZERO
var levels: Array[Level] = []
## 식재료 배달 (v13): 배달 알바, 배달비, 기다리는 시간.
var courier: NpcInfo = null
var delivery_fee: int = 0
var delivery_min_s: float = 20.0
var delivery_max_s: float = 30.0
var delivery_max_n: int = 99
var delivery_max_active: int = 3


static func from_dict(data: Dictionary) -> ShopData:
	var d: ShopData = ShopData.new()
	var keeper_data: Variant = data.get("keeper", {})
	if keeper_data is Dictionary:
		d.keeper = NpcInfo.from_dict(keeper_data)
	d.door = _point(data.get("door"))
	d.outside_spawn = _point(data.get("outside_spawn"))
	d.enter_range = float(data.get("enter_range", 2.2))
	var interior: Variant = data.get("interior", {})
	if interior is Dictionary:
		d.interior_center = Vector3(float(interior.get("x", 0.0)), 0.0, float(interior.get("z", 0.0)))
		d.interior_half = Vector2(float(interior.get("half_x", 1.0)), float(interior.get("half_z", 1.0)))
	d.inside_spawn = _point(data.get("inside_spawn"))
	d.exit = _point(data.get("exit"))
	d.exit_range = float(data.get("exit_range", 1.8))
	d.room_origin = _point(data.get("room_origin"))
	var deliv: Variant = data.get("delivery", {})
	if deliv is Dictionary:
		if deliv.get("courier") is Dictionary:
			d.courier = NpcInfo.from_dict(deliv["courier"])
		d.delivery_fee = int(deliv.get("fee", 0))
		d.delivery_min_s = float(deliv.get("min_delay_s", 20.0))
		d.delivery_max_s = float(deliv.get("max_delay_s", 30.0))
		d.delivery_max_n = int(deliv.get("max_n", 99))
		d.delivery_max_active = int(deliv.get("max_active", 3))
	for entry: Variant in data.get("levels", []):
		if entry is Dictionary:
			var lv: Level = Level.new()
			lv.level = int(entry.get("level", 1))
			lv.display_name = str(entry.get("name", ""))
			lv.points = int(entry.get("points", 0))
			lv.sell_bonus = float(entry.get("sell_bonus", 0.0))
			lv.stock = PackedStringArray(entry.get("stock", []))
			d.levels.append(lv)
	return d


func level_info(level: int) -> Level:
	for lv: Level in levels:
		if lv.level == level:
			return lv
	return levels[0]


## 지금 단계까지 열린 진열품 전부.
func stock_for(level: int) -> PackedStringArray:
	var out: PackedStringArray = []
	for lv: Level in levels:
		if lv.level <= level:
			out.append_array(lv.stock)
	return out


func is_inside(position: Vector3) -> bool:
	return absf(position.x - interior_center.x) <= interior_half.x and absf(position.z - interior_center.z) <= interior_half.y


## 팔 때 받는 솔 (서버 sellValue 와 같은 식).
func sell_value(base_price: int, count: int, level: int) -> int:
	return floori(base_price * count * (1.0 + level_info(level).sell_bonus))


static func _point(v: Variant) -> Vector3:
	if v is Dictionary:
		return Vector3(float(v.get("x", 0.0)), 0.0, float(v.get("z", 0.0)))
	return Vector3.ZERO
