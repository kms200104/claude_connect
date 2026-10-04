class_name ActiveEvent
extends RefCounted
## 지금 열려 있는 이벤트 하나 (서버의 `ev` 목록). 오늘 고른 물건(wanted)과 배율은 서버가 정한다.

var id: String = ""
var wanted: PackedStringArray = []
var multiplier: float = 1.0
var stock: PackedStringArray = []


static func from_dict(data: Dictionary) -> ActiveEvent:
	var e: ActiveEvent = ActiveEvent.new()
	e.id = str(data.get("id", ""))
	for id: Variant in data.get("wanted", []):
		e.wanted.append(str(id))
	e.multiplier = float(data.get("mult", 1.0))
	for id: Variant in data.get("stock", []):
		e.stock.append(str(id))
	return e


func info() -> EventInfo:
	return GameData.event_info(id)
