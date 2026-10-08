class_name VehicleCatalog
extends RefCounted
## 차고 탈것 데이터 (v19, data/vehicles/garage.json): 자전거 · 전기오토바이 모델과 꾸미기 부품 (킥보드는 아이템 · VehicleInfo).
## 성능 계산(stats)은 서버 server/src/garage.js 의 vehicleStats 와 같아야 한다 (이동 속도 검사가 같은 값을 쓴다).

## 타는 동안의 성능 (m/s · m/s² · rad/s). wade = 여울에서의 속도 배율.
class Stats:
	var top: float = 6.0
	var accel: float = 2.0
	var brake: float = 4.5
	var coast: float = 0.25
	var turn: float = 2.4
	var wade: float = 0.55
	var regen: float = 1.0


class Model:
	var id: String = ""
	## "bike" | "moto"
	var kind: String = "bike"
	## 몸체 모양: city · mini · mtb · road · scooter · classic · sport (VehicleModel 이 빚는다).
	var style: String = "city"
	var name: String = ""
	var type_name: String = ""
	var spec: String = ""
	var desc: String = ""
	var price: int = 0
	var base: Stats = Stats.new()
	## 바퀴 반지름 (m) · 기어비 (페달 한 바퀴에 바퀴가 도는 수) · 타는 동안 캐릭터를 올리는 높이 (m).
	var wheel: float = 0.28
	var gear: float = 2.2
	var lift: float = 0.16
	var paint: Color = Color.WHITE
	var trim: Color = Color.WHITE
	var seat: Color = Color.BLACK
	## 자리 이름 → 탈것 좌표 (바닥 y = 0, 앞 = -z).
	var anchors: Dictionary[String, Vector3] = {}

	func anchor(key: String) -> Vector3:
		return anchors.get(key, Vector3.ZERO)


class Part:
	var id: String = ""
	var slot: String = ""
	var name: String = ""
	var desc: String = ""
	var kinds: PackedStringArray = []
	## 종류 → 값.
	var price: Dictionary[String, int] = {}
	## 색 (도색 · 포인트 색), 없으면 투명.
	var color: Color = Color(0, 0, 0, 0)
	## 성능 배율 { top, accel, brake, turn, wade }.
	var stats: Dictionary[String, float] = {}
	## 전조등 { range, energy, angle, color, lens, drl } · 미등 { energy, size } · 타이어 { c, w, tread } · 시트 { c, shape, c2 } · 빛 장식 { c, where }.
	var light: Dictionary = {}
	var tail: Dictionary = {}
	var tire: Dictionary = {}
	var seat: Dictionary = {}
	var glow: Dictionary = {}
	## 액세서리 모양 (PartMesh 도형 목록, anchor 기준).
	var model: Array = []
	var anchor: String = ""
	## 줄무늬처럼 몸체에 칠하는 두 번째 색 자리 ("$trim" 등).
	var paint2: String = ""

	func fits(kind: String) -> bool:
		return kind in kinds

	func price_for(kind: String) -> int:
		return price.get(kind, 0) if fits(kind) else 0


var max_owned: int = 6
var resale: float = 0.55
## 종류 → { name, pose, turn_speed, throttle_rise, throttle_fall, brake_rise, jerk }
var kinds: Dictionary[String, Dictionary] = {}
## 칸 [{ id, name }] (보여 주는 순서).
var slots: Array[Dictionary] = []
var models: Array[Model] = []
var parts: Dictionary[String, Part] = {}
var _models: Dictionary[String, Model] = {}


static func from_dict(d: Dictionary) -> VehicleCatalog:
	var c: VehicleCatalog = VehicleCatalog.new()
	c.max_owned = int(d.get("max_owned", 6))
	c.resale = float(d.get("resale", 0.55))
	var k: Variant = d.get("kinds", {})
	if k is Dictionary:
		for key: Variant in k:
			c.kinds[str(key)] = k[key]
	for s: Variant in d.get("slots", []):
		if s is Dictionary:
			c.slots.append(s)
	for raw: Variant in d.get("models", []):
		if not raw is Dictionary:
			continue
		var m: Model = Model.new()
		m.id = str(raw.get("id", ""))
		m.kind = str(raw.get("kind", "bike"))
		m.style = str(raw.get("style", "city"))
		m.name = str(raw.get("name", m.id))
		m.type_name = str(raw.get("type", ""))
		m.spec = str(raw.get("spec", ""))
		m.desc = str(raw.get("desc", ""))
		m.price = int(raw.get("price", 0))
		m.base.top = float(raw.get("top", 6.0))
		m.base.accel = float(raw.get("accel", 2.0))
		m.base.brake = float(raw.get("brake", 4.5))
		m.base.coast = float(raw.get("coast", 0.25))
		m.base.turn = float(raw.get("turn", 2.4))
		m.base.wade = float(raw.get("wade", 0.55))
		m.base.regen = float(raw.get("regen", 1.0))
		m.wheel = float(raw.get("wheel", 0.28))
		m.gear = float(raw.get("gear", 2.2))
		m.lift = float(raw.get("lift", 0.16))
		m.paint = Color.html(str(raw.get("paint", "#FFFFFF")))
		m.trim = Color.html(str(raw.get("trim", "#FFFFFF")))
		m.seat = Color.html(str(raw.get("seat", "#232326")))
		var anchors: Variant = raw.get("anchors", {})
		if anchors is Dictionary:
			for key: Variant in anchors:
				var v: Variant = anchors[key]
				if v is Array and v.size() >= 3:
					m.anchors[str(key)] = Vector3(float(v[0]), float(v[1]), float(v[2]))
		c.models.append(m)
		c._models[m.id] = m
	for raw: Variant in d.get("parts", []):
		if not raw is Dictionary:
			continue
		var p: Part = Part.new()
		p.id = str(raw.get("id", ""))
		p.slot = str(raw.get("slot", ""))
		p.name = str(raw.get("name", p.id))
		p.desc = str(raw.get("desc", ""))
		p.kinds = PackedStringArray(raw.get("kinds", []))
		var price: Variant = raw.get("price", {})
		if price is Dictionary:
			for key: Variant in price:
				p.price[str(key)] = int(price[key])
		if raw.has("c"):
			p.color = Color.html(str(raw.get("c")))
		var stats: Variant = raw.get("stats", {})
		if stats is Dictionary:
			for key: Variant in stats:
				p.stats[str(key)] = float(stats[key])
		for field: String in ["light", "tail", "tire", "seat", "glow"]:
			var v: Variant = raw.get(field, {})
			if v is Dictionary:
				p.set(field, v)
		var model: Variant = raw.get("model", [])
		p.model = model if model is Array else []
		p.anchor = str(raw.get("anchor", ""))
		p.paint2 = str(raw.get("paint2", ""))
		c.parts[p.id] = p
	return c


func model(id: String) -> Model:
	return _models.get(id)


func part(id: String) -> Part:
	return parts.get(id)


func kind_name(kind: String) -> String:
	return str(kinds.get(kind, {}).get("name", kind))


## 그 종류 탈것에 맞는 그 칸 부품 (데이터 순서).
func parts_for(kind: String, slot: String) -> Array[Part]:
	var out: Array[Part] = []
	for p: Part in parts.values():
		if p.slot == slot and p.fits(kind):
			out.append(p)
	return out


## 끼운 부품 배율을 곱한 성능 (서버 vehicleStats 와 같다).
func stats(model_id: String, fit: Dictionary) -> Stats:
	var m: Model = model(model_id)
	var s: Stats = Stats.new()
	if m == null:
		return s
	s.top = m.base.top
	s.accel = m.base.accel
	s.brake = m.base.brake
	s.coast = m.base.coast
	s.turn = m.base.turn
	s.wade = m.base.wade
	s.regen = m.base.regen
	for id: Variant in fit.values():
		var p: Part = part(str(id))
		if p == null:
			continue
		s.top *= p.stats.get("top", 1.0)
		s.accel *= p.stats.get("accel", 1.0)
		s.brake *= p.stats.get("brake", 1.0)
		s.turn *= p.stats.get("turn", 1.0)
		s.wade *= p.stats.get("wade", 1.0)
	s.wade = minf(s.wade, 1.0)
	return s


## 팔 때 돌려받는 돈 (서버 resaleValue 와 같다).
func resale_value(model_id: String, owned: PackedStringArray) -> int:
	var m: Model = model(model_id)
	if m == null:
		return 0
	var spent: int = m.price
	for id: String in owned:
		var p: Part = part(id)
		if p != null:
			spent += p.price_for(m.kind)
	return roundi(float(spent) * resale / 100.0) * 100
